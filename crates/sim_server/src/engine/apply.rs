//! SimCommand applier + dock + gate + refuel + construction + delivery.
//!
//! Every cross-entity effect a ship's tick can produce flows through
//! [`apply_ship_commands`]. The tick loop drains the `CommandBuffer`
//! into this dispatcher, which fans each [`SimCommand`] variant out
//! to the matching apply helper:
//!
//!   * **Dock cycle** — [`apply_request_dock_typed`] →
//!     [`commit_dock`] → [`apply_release_dock`]. Multi-tick: the
//!     ship's `Dock` action waits in [`commit_dock`] until a slot
//!     opens (queue head admit) or the budget elapses. Stale
//!     queue entries get pruned by [`prune_stale_dock_queue`] both
//!     inline and globally via [`tick_dock_queue_advance`].
//!   * **Gate jump** — [`apply_gate_jump`] charges fees, hops the
//!     ship to the paired gate's universe coordinates, and emits a
//!     `ship_gate_jumped` event for the trail effect.
//!   * **Refuel** — [`apply_facility_refuel`] is multi-tick; the
//!     ship's Refuel action returns Running until tank full or
//!     facility reserves dry, capturing the dwell. Drains
//!     `FacilityStorage.reserves[Fuel]` and credits the facility.
//!   * **Construction delivery** — [`apply_construction_delivery`]
//!     handles the special site delivery contract: cargo moves into
//!     `ConstructionSite.progress_delivered`, and at full progress
//!     the site queues a `PendingMaterialization` for the next tick's
//!     async drain (see `super::drains`).
//!
//! Helpers:
//!   * [`primary_dock_at_location`] / [`primary_dock_at_location_typed`] /
//!     [`dockable_candidates_ordered`] — facility ranking by
//!     occupancy + capacity, used when admin paths want a "primary
//!     station here" reference and when the apply path falls through
//!     to secondary candidates.
//!   * [`tick_dock_queue_advance`] — runs each tick after apply pass,
//!     advances any dock queue heads independent of whether the ship
//!     at the head is currently emitting `RequestDock`. Decouples
//!     queue pull from ship LOD cadence.
//!
//! Cross-module call: construction materialization needs the async
//! DB pool, so [`apply_construction_delivery`] queues a
//! `PendingMaterialization` rather than calling
//! [`super::drains::materialize_facility`] inline. The drain runs on
//! the next tick boundary and INSERTs the new facility row.
//!
//! Extracted from `engine.rs` in the Phase-21 god-module split.

use bevy_ecs::prelude::{Entity, World};
use sim_core::agents::market::MarketPricing;
use sim_core::agents::ship::ShipPosition;
use sim_core::simulation::commands::{CommandBuffer, SimCommand};
use sim_core::simulation::spawner::AgentStore;

use super::admin::{apply_fitting_swap, commit_shipyard_refit, try_shipyard_refit, RefitAttempt};
use super::drains::materialize_facility;

pub fn apply_ship_commands(
    world: &mut World,
    store: &mut AgentStore,
    commands: &mut CommandBuffer,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) {
    use sim_core::agents::ship::{ShipCargo, ShipEconomy};

    let drained: Vec<SimCommand> = commands.drain().collect();
    let mut leftover: Vec<SimCommand> = Vec::with_capacity(drained.len());

    for cmd in drained {
        match cmd {
            SimCommand::AddSupplyAtShipLocation { ship, commodity, quantity }
            | SimCommand::RemoveSupplyAtShipLocation { ship, commodity, quantity } => {
                let adding = matches!(&cmd, SimCommand::AddSupplyAtShipLocation { .. });
                let location = world
                    .get::<ShipPosition>(ship)
                    .and_then(|p| p.location_name.clone());
                if let Some(loc) = location {
                    if let Some(&market_entity) = store.market_at_location.get(&loc) {
                        if let Some(mut pricing) = world.get_mut::<MarketPricing>(market_entity) {
                            let entry = pricing.supply.entry(commodity).or_insert(0.0);
                            if adding {
                                *entry += quantity;
                            } else {
                                *entry = (*entry - quantity).max(0.0);
                            }
                        }
                    }
                }
            }
            SimCommand::AddSupply { market, commodity, quantity } => {
                if let Some(mut pricing) = world.get_mut::<MarketPricing>(market) {
                    *pricing.supply.entry(commodity).or_insert(0.0) += quantity;
                }
            }
            SimCommand::RemoveSupply { market, commodity, quantity } => {
                if let Some(mut pricing) = world.get_mut::<MarketPricing>(market) {
                    let entry = pricing.supply.entry(commodity).or_insert(0.0);
                    *entry = (*entry - quantity).max(0.0);
                }
            }

            // --- Market spread revenue → facility ---
            SimCommand::TransferCredits { to, amount, .. } => {
                use sim_core::agents::facility::FacilityOperations;
                if amount > 0 {
                    if let Some(mut ops) = world.get_mut::<FacilityOperations>(to) {
                        ops.credits += amount;
                    }
                }
            }

            // --- Dock-dwell interactions (Phase 11a) ---
            SimCommand::RequestDock {
                ship,
                facility_location,
                preferred_facility_type,
            } => {
                let docked = apply_request_dock_typed(
                    world,
                    store,
                    ship,
                    &facility_location,
                    preferred_facility_type,
                );
                if docked {
                    events.push(serde_json::json!({
                        "kind": "ship_docked",
                        "ship_entity": format!("{:?}", ship),
                        "location": facility_location,
                        "preferred_type": preferred_facility_type,
                    }));
                }
            }
            SimCommand::ReleaseDock { ship, facility_location } => {
                apply_release_dock(world, store, ship, &facility_location);
            }
            SimCommand::FacilityRefuel {
                ship: _,
                facility_location,
                amount,
                payment,
            } => {
                apply_facility_refuel(world, store, &facility_location, amount, payment);
            }
            SimCommand::GrantCrewXp { ship, skill, amount } => {
                use sim_core::agents::ship::ShipCrewSkills;
                if let Some(mut skills) = world.get_mut::<ShipCrewSkills>(ship) {
                    skills.grant(skill, amount);
                }
            }
            SimCommand::RequestGateJump {
                ship,
                src_gate_location,
                dest_gate_location,
            } => {
                apply_gate_jump(
                    world,
                    store,
                    ship,
                    &src_gate_location,
                    &dest_gate_location,
                    events,
                );
            }

            // --- Contracts ---
            SimCommand::AcceptContract { contract_id, ship_id, .. } => {
                // Best-effort: silently drop if the contract was already taken.
                let tick_now = 0; // Apply phase doesn't know the tick; board records accepted_at separately.
                let accepted = store.contracts.accept(&contract_id, ship_id.clone(), tick_now);
                if accepted {
                    // Ticker event so players can watch the contract
                    // board churn in real time. Losing speculative
                    // accepts return false from `accept()` and don't
                    // emit (those ships will self-clean via the
                    // sanity-check pass on next tick).
                    if let Some(c) = store.contracts.get(&contract_id) {
                        events.push(serde_json::json!({
                            "kind": "contract_accepted",
                            "contract_id": contract_id,
                            "contract_type": c.contract_type.as_str(),
                            "ship_id": ship_id,
                            "commodity": c.commodity.as_str(),
                            "source": c.source_location,
                            "destination": c.destination_location,
                            "payment": c.payment,
                        }));
                    }
                }
            }
            SimCommand::ReleaseContract { ship_id, contract_id, reason } => {
                // Move Accepted → Posted so another ship can try. The
                // fulfiller_id guard inside `release` ensures a losing
                // speculative-accept can't yank the winning ship's
                // contract; if we weren't the named fulfiller, the
                // call is a no-op, which is what we want.
                //
                // Phase 19e: read the contract's faction + payment
                // BEFORE release so we can apply a breach rep penalty
                // on the winning ship only. `release` clears
                // fulfiller_id, so we need the snapshot up front.
                let breach_info = store.contracts.get(&contract_id).and_then(|c| {
                    c.faction_id.as_ref().map(|f| (f.clone(), c.payment))
                });
                let released = store
                    .contracts
                    .release(&contract_id, Some(&ship_id));
                if released {
                    tracing::debug!(
                        contract_id = %contract_id,
                        ship_id = %ship_id,
                        reason = %reason,
                        "contract released back to Posted"
                    );
                    // Breach penalty: shave faction rep by
                    // `10 + payment/1000`, clamped to [1, 25]. Matches
                    // Elixir — real stakes to accepting a contract.
                    // Only fires when the contract had a faction tag
                    // (most facility-owned deliveries do now that
                    // 19e-1 landed).
                    if let Some((faction, payment)) = breach_info {
                        let ship_entity = store.ship_by_id.get(&ship_id).copied();
                        if let Some(e) = ship_entity {
                            // Read ship faction up front — used by the
                            // Bundle A standing hit after the econ
                            // borrow releases.
                            let ship_faction = world
                                .get::<sim_core::agents::ship::ShipIdentity>(e)
                                .map(|i| i.faction_id.clone())
                                .unwrap_or_default();
                            if let Some(mut econ) = world.get_mut::<ShipEconomy>(e) {
                                let penalty: u8 = (10 + (payment / 1000))
                                    .clamp(1, 25) as u8;
                                let rep = econ
                                    .faction_reputation
                                    .entry(faction.clone())
                                    .or_insert(0);
                                *rep = rep.saturating_sub(penalty);
                                events.push(serde_json::json!({
                                    "kind": "contract_breached",
                                    "contract_id": contract_id,
                                    "ship_id": ship_id,
                                    "faction_id": faction,
                                    "rep_penalty": penalty,
                                    "reason": reason,
                                }));
                            }
                            // Bundle A: ship's faction takes the blame
                            // on the relations matrix too. Keeps the
                            // per-faction stance aligned with per-ship
                            // reputation — both sides walk together.
                            if !ship_faction.is_empty()
                                && !faction.is_empty()
                                && ship_faction != faction
                            {
                                let new_standing = store.relations.bump_standing(
                                    &ship_faction,
                                    &faction,
                                    sim_core::agents::faction_relations::BREACH_STANDING_PENALTY,
                                    tick,
                                );
                                events.push(serde_json::json!({
                                    "kind": "faction_standing_changed",
                                    "a": ship_faction,
                                    "b": faction,
                                    "delta": sim_core::agents::faction_relations::BREACH_STANDING_PENALTY,
                                    "new_standing": new_standing,
                                    "cause": "breach",
                                    "reason": reason,
                                }));
                            }
                        }
                    }
                }
            }
            SimCommand::DeliverContract { ship, contract_id } => {
                use sim_core::agents::population::PopDemographics;
                use sim_core::economy::contracts::ContractType;
                let delivered = store.contracts.mark_delivered(&contract_id);
                if let Some(c) = delivered {
                    // Pay the ship and bump faction reputation if the
                    // contract was tagged with one. +1 per successful
                    // delivery, capped at 100.
                    //
                    // Phase 18f: comms_bonus on the ship's fitting
                    // multiplies payment. A tier-3 comms suite adds
                    // 10% — reads the stat at apply time rather than
                    // baking it in to avoid stale-fitting edge cases
                    // after a refit mid-flight.
                    let comms_bonus = world
                        .get::<sim_core::agents::ship::ShipFitting>(ship)
                        .map(|f| f.derived.comms_bonus)
                        .unwrap_or(0.0);
                    // Bundle A: read ship faction up front for the
                    // relations-standing bump. Taking an immutable
                    // borrow of ShipIdentity here and letting it drop
                    // before the `&mut ShipEconomy` acquisition below
                    // keeps hecs happy (one live component borrow per
                    // entity).
                    let ship_faction = world
                        .get::<sim_core::agents::ship::ShipIdentity>(ship)
                        .map(|i| i.faction_id.clone())
                        .unwrap_or_default();
                    // Bundle B: treaty-driven payment bonus applies on
                    // top of Phase 18f's comms multiplier. TradePact =
                    // +10%, Allied = +15%, anything else = 1.0 (same
                    // as pre-Bundle-B behaviour).
                    let treaty_mult = c
                        .faction_id
                        .as_deref()
                        .map(|f| {
                            sim_core::agents::faction_relations::trade_pact_payment_multiplier(
                                &store.relations,
                                &ship_faction,
                                f,
                            )
                        })
                        .unwrap_or(1.0);
                    let effective_payment: i64 =
                        ((c.payment as f32) * (1.0 + comms_bonus) * treaty_mult)
                            .round() as i64;
                    if let Some(mut econ) = world.get_mut::<ShipEconomy>(ship) {
                        econ.credits += effective_payment;
                        if let Some(faction) = c.faction_id.as_ref() {
                            // Phase 19e: reputation gain scales with
                            // payment so big contracts move rep faster
                            // (otherwise a 1-off +1 makes faction-gated
                            // work effectively unreachable). Matches
                            // Elixir's `min(5 + payment/2000, 15)`.
                            let gain: u8 = (5 + (effective_payment / 2000))
                                .clamp(1, 15)
                                as u8;
                            let rep = econ
                                .faction_reputation
                                .entry(faction.clone())
                                .or_insert(0);
                            *rep = rep.saturating_add(gain).min(100);
                        }
                    }
                    // Bundle A: faction-to-faction standing bump. Fires
                    // when both sides are tagged and distinct. Small
                    // per-delivery nudge so a healthy trade corridor
                    // accumulates into a TradePact over hundreds of
                    // deliveries, not dozens. `bump_standing` is a
                    // no-op on empty or self-pairs.
                    if let Some(requestor) = c.faction_id.as_deref() {
                        if !ship_faction.is_empty()
                            && !requestor.is_empty()
                            && ship_faction != requestor
                        {
                            let new_standing = store.relations.bump_standing(
                                &ship_faction,
                                requestor,
                                sim_core::agents::faction_relations::DELIVERY_STANDING_BUMP,
                                tick,
                            );
                            events.push(serde_json::json!({
                                "kind": "faction_standing_changed",
                                "a": ship_faction,
                                "b": requestor,
                                "delta": sim_core::agents::faction_relations::DELIVERY_STANDING_BUMP,
                                "new_standing": new_standing,
                                "cause": "delivery",
                            }));
                        }
                    }
                    // Adaptive-fleet: clear hoard strikes on any
                    // successful delivery. A ship that's been rich +
                    // idle recovers toward "productive" the moment it
                    // moves cargo, without waiting for idle_ticks to
                    // drop below the threshold.
                    if let Some(mut life) = world
                        .get_mut::<sim_core::agents::ship::ShipLifecycle>(ship)
                    {
                        life.hoard_strikes = 0;
                    }
                    // Bundle 1.4: personality drift. A successful
                    // delivery nudges the ship's `profit` axis up a
                    // sliver. Invisible per-delivery; visible over
                    // many deliveries as a character arc.
                    if let Some(mut ai) = world
                        .get_mut::<sim_core::agents::ship::ShipAI>(ship)
                    {
                        ai.personality.drift(
                            sim_core::ai::personality::Axis::Profit,
                            sim_core::agents::ship::DRIFT_DELIVERY_PROFIT,
                        );
                    }
                    // Phase 18d: grant ship-level XP on every delivery.
                    // Cascades level-ups + banks retrofit points when a
                    // threshold crosses. Kept independent of crew skill
                    // XP; ships and crews progress on separate tracks.
                    {
                        use sim_core::agents::ship::{
                            ShipIdentity, ShipProgression, SHIP_XP_PER_DELIVERY,
                        };
                        let ship_agent_id = world
                            .get::<ShipIdentity>(ship)
                            .map(|i| i.id.clone())
                            .unwrap_or_default();
                        if let Some(mut prog) = world.get_mut::<ShipProgression>(ship) {
                            let gained = prog.grant_xp(SHIP_XP_PER_DELIVERY);
                            if gained > 0 {
                                events.push(serde_json::json!({
                                    "kind": "ship_leveled_up",
                                    "id": ship_agent_id,
                                    "new_level": prog.level,
                                    "retrofit_points": prog.retrofit_points,
                                    "levels_gained": gained,
                                }));
                            }
                        }
                    }

                    match c.contract_type {
                        ContractType::CrewMission => {
                            use sim_core::agents::ship::ShipCrewSkills;
                            use sim_core::economy::missions;
                            // Look up the template so we know which skill
                            // to grow and by how much. Missing template
                            // (e.g. legacy data) → no XP, just payment.
                            if let Some(cat) = c.mission_category.as_deref() {
                                if let Some(template) = missions::get(cat) {
                                    if let Some(mut skills) =
                                        world.get_mut::<ShipCrewSkills>(ship)
                                    {
                                        skills.grant(
                                            template.required_skill,
                                            template.skill_gain,
                                        );
                                    }
                                    events.push(serde_json::json!({
                                        "kind": "crew_mission_completed",
                                        "contract_id": c.id,
                                        "category": cat,
                                        "skill": template.required_skill,
                                        "skill_gain": template.skill_gain,
                                        "payment": c.payment,
                                    }));
                                }
                            }
                        }
                        ContractType::Passenger => {
                            // Disembark: increment destination population.
                            // We treat the facility_location as the pop's
                            // home; any pops there grow by the head count.
                            let mut q = world
                                .query::<(&sim_core::agents::population::PopIdentity, &mut PopDemographics)>();
                            for (id, mut demo) in q.iter_mut(world) {
                                if id.facility_location == c.destination_location {
                                    demo.population_count += c.quantity as i64;
                                }
                            }
                            events.push(serde_json::json!({
                                "kind": "passengers_arrived",
                                "contract_id": c.id,
                                "destination": c.destination_location,
                                "head_count": c.quantity,
                                "payment": c.payment,
                            }));
                        }
                        ContractType::Construction => {
                            // Phase 19c-c: the delivered commodity goes
                            // INTO the construction site, not the
                            // destination market. Remove from the ship's
                            // cargo hold the same way, then route
                            // progress to the site at this
                            // (location, commodity).
                            if let Some(mut cargo) = world.get_mut::<ShipCargo>(ship) {
                                let have = cargo.cargo.get(&c.commodity).copied().unwrap_or(0);
                                let leftover = have.saturating_sub(c.quantity);
                                if leftover == 0 {
                                    cargo.cargo.remove(&c.commodity);
                                    cargo.cargo_age.remove(&c.commodity);
                                } else {
                                    cargo.cargo.insert(c.commodity, leftover);
                                }
                            }
                            apply_construction_delivery(
                                world,
                                store,
                                &c.destination_location,
                                c.commodity,
                                c.quantity,
                                events,
                            );
                            events.push(serde_json::json!({
                                "kind": "contract_delivered",
                                "contract_id": c.id,
                                "contract_type": c.contract_type.as_str(),
                                "commodity": c.commodity.as_str(),
                                "destination": c.destination_location,
                                "payment": c.payment,
                                "faction_id": c.faction_id,
                            }));
                        }
                        _ => {
                            // Standard delivery / courier / subsidy: drop the
                            // commodity into the destination market supply.
                            if let Some(mut cargo) = world.get_mut::<ShipCargo>(ship) {
                                let have = cargo.cargo.get(&c.commodity).copied().unwrap_or(0);
                                let leftover = have.saturating_sub(c.quantity);
                                if leftover == 0 {
                                    cargo.cargo.remove(&c.commodity);
                                    cargo.cargo_age.remove(&c.commodity);
                                } else {
                                    cargo.cargo.insert(c.commodity, leftover);
                                }
                            }
                            if let Some(&market_entity) =
                                store.market_at_location.get(&c.destination_location)
                            {
                                if let Some(mut pricing) =
                                    world.get_mut::<MarketPricing>(market_entity)
                                {
                                    *pricing.supply.entry(c.commodity).or_insert(0.0) +=
                                        c.quantity as f32;
                                }
                            }
                            events.push(serde_json::json!({
                                "kind": "contract_delivered",
                                "contract_id": c.id,
                                "contract_type": c.contract_type.as_str(),
                                "commodity": c.commodity.as_str(),
                                "destination": c.destination_location,
                                "payment": c.payment,
                                "faction_id": c.faction_id,
                            }));
                        }
                    }
                }
            }

            // Phase 18d: agent-driven refit via shipyard. Validates
            // stock + credits + docked-at-shipyard, does the fitting
            // swap, commits the economic side, and consumes one
            // retrofit point on success. Silently drops on any
            // rejection — the BT will replan next tick.
            SimCommand::RequestRefit { ship, slot, slug } => {
                use sim_core::agents::ship::{ShipIdentity, ShipProgression};

                let has_point = world
                    .get::<ShipProgression>(ship)
                    .map(|p| p.retrofit_points > 0)
                    .unwrap_or(false);
                if !has_point {
                    continue;
                }
                let Ok((fac_entity, fac_id, cost)) = try_shipyard_refit(world, ship, slot, slug)
                else {
                    continue;
                };
                let prev_slug = match apply_fitting_swap(world, ship, slot, Some(slug)) {
                    RefitAttempt::Applied { prev_slug } => prev_slug,
                    _ => continue,
                };
                commit_shipyard_refit(world, ship, fac_entity, slug, cost);
                if let Some(mut prog) = world.get_mut::<ShipProgression>(ship) {
                    prog.spend_retrofit_point();
                }
                let ship_id = world
                    .get::<ShipIdentity>(ship)
                    .map(|i| i.id.clone())
                    .unwrap_or_default();
                events.push(serde_json::json!({
                    "kind": "ship_refitted",
                    "id": ship_id,
                    "slot": slot.as_str(),
                    "from": prev_slug,
                    "to": slug,
                    "via": "agent_shipyard",
                    "shipyard_id": fac_id,
                    "cost": cost,
                }));
            }

            SimCommand::DecommissionShip { ship, reason } => {
                // Queue for async drain — admin_remove_ship needs the
                // persist_tx + awaits events, which this sync fn can't
                // do. The tick loop runs `drain_pending_decommissions`
                // right after apply and also schedules a
                // `PendingRespawn` so fleet size recovers over time.
                store.pending_decommissions.push(
                    sim_core::simulation::spawner::PendingDecommission { entity: ship, reason },
                );
            }

            other => leftover.push(other),
        }
    }

    commands.commands.extend(leftover);
}

/// Pick the primary dockable facility at a location.
///
/// "Primary" = highest docking_capacity (farms/mining_rigs have capacity 0
/// and aren't candidates). Ties broken by first-seen hecs iteration order.
/// Returns None if no dockable facility exists at the location, in which
/// case dock/refuel commands silently no-op.
pub fn primary_dock_at_location(world: &World, store: &AgentStore, location: &str) -> Option<Entity> {
    primary_dock_at_location_typed(world, store, location, None)
}

/// Pick the largest dockable facility at `location`, optionally
/// restricted to a `facility_type` (e.g. `"shipyard"`). Returns `None`
/// if no candidate matches; callers (e.g. agent retrofit BT) should
/// treat that as a silent dock rejection — the BT fails cleanly and
/// replans next tick.
pub fn primary_dock_at_location_typed(
    world: &World,
    store: &AgentStore,
    location: &str,
    facility_type: Option<&str>,
) -> Option<Entity> {
    dockable_candidates_ordered(world, store, location, facility_type)
        .into_iter()
        .next()
}

/// Return every dockable facility at `location` (docking_capacity > 0,
/// matching `facility_type` if set), sorted by capacity descending.
/// Phase 18k: lets `apply_request_dock_typed` fall through from the
/// primary to secondary/tertiary facilities when the biggest one is
/// full — haven-station has 5 facilities totalling 16 slots; pre-18k
/// only the 8-slot primary got used, so 111 ships piled up on it and
/// the remaining 8 slots sat idle.
pub fn dockable_candidates_ordered(
    world: &World,
    store: &AgentStore,
    location: &str,
    facility_type: Option<&str>,
) -> Vec<Entity> {
    use sim_core::agents::facility::{FacilityIdentity, FacilityOperations};
    let Some(candidates) = store.facilities_at_location.get(location) else {
        return Vec::new();
    };
    let mut scored: Vec<(Entity, u32)> = Vec::new();
    for &e in candidates {
        if let Some(want) = facility_type {
            let ok = world
                .get::<FacilityIdentity>(e)
                .map(|id| id.facility_type == want)
                .unwrap_or(false);
            if !ok {
                continue;
            }
        }
        let cap = world
            .get::<FacilityOperations>(e)
            .map(|o| o.docking_capacity)
            .unwrap_or(0);
        if cap == 0 {
            continue;
        }
        scored.push((e, cap));
    }
    scored.sort_by(|a, b| b.1.cmp(&a.1));
    scored.into_iter().map(|(e, _)| e).collect()
}

/// Apply `RequestDock`: runs the same occupancy/condition fee formula as
/// Elixir's `facility_agent.ex:request_dock`. Deducts the fee from the
/// ship, adds it to the facility's credits, appends the ship entity to
/// `FacilityStorage.docked_ships`, and sets `ShipPosition.docked_at`.
/// Returns `true` if the dock succeeded (ship now docked), `false` if
/// it was rejected (no facility, capacity full, or ship broke).
pub fn apply_request_dock_typed(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    location: &str,
    preferred_facility_type: Option<&'static str>,
) -> bool {
    use sim_core::agents::{
        facility::{docking_fee, FacilityOperations, FacilityStorage, DOCKING_FEE_BASE},
        ship::ShipEconomy,
    };

    // Phase 18k: iterate dockable facilities in descending-capacity
    // order so the ship falls through to secondary/tertiary
    // facilities when the primary is full.
    //
    // Phase 19-tail: FIFO dock queue. If a ship is already queued at
    // some facility at this location, it must wait its turn — a
    // fresh arrival can't queue-jump just because its RequestDock
    // landed the same tick a slot opened. Three cases:
    //
    //   1. Ship already queued at facility F:
    //      - If F has capacity AND ship is at head → admit, pop queue.
    //      - Else → noop (stay queued).
    //
    //   2. Ship not queued anywhere:
    //      - If any candidate facility has `docked + queue_len < cap`
    //        → admit immediately (fast path, no queue contention).
    //      - Else → append to the least-queued candidate's queue.
    //
    //   3. No candidates at location → reject (same as before).
    let candidates = dockable_candidates_ordered(world, store, location, preferred_facility_type);
    if candidates.is_empty() {
        return false;
    }

    // Sweep stale entries from each candidate's queue before checking
    // heads. A ship that left this location (started a new transit,
    // got admin-destroyed, etc.) can otherwise wedge the queue head
    // forever — everyone behind it starves. We rebuild each queue by
    // retaining only entries whose ShipPosition still points at this
    // facility's location string.
    for &e in &candidates {
        prune_stale_dock_queue(world, store, e, location);
    }

    // Case 1: ship already queued at one of these candidates?
    for &e in &candidates {
        let queued_at_head = world
            .get::<FacilityStorage>(e)
            .map(|s| s.dock_queue.first() == Some(&ship))
            .unwrap_or(false);
        let in_queue = world
            .get::<FacilityStorage>(e)
            .map(|s| s.dock_queue.contains(&ship))
            .unwrap_or(false);
        if !in_queue {
            continue;
        }
        if !queued_at_head {
            // Still waiting behind someone else. No admit this tick.
            return false;
        }
        // We're at the head of this facility's queue. Admit if a slot
        // is available AND we can afford the fee.
        let (fee, has_space) = {
            let ops = match world.get::<FacilityOperations>(e) {
                Some(o) => o,
                None => continue,
            };
            let storage = match world.get::<FacilityStorage>(e) {
                Some(s) => s,
                None => continue,
            };
            let docked = storage.docked_ships.len() as u32;
            if docked >= ops.docking_capacity {
                (0, false)
            } else {
                (
                    docking_fee(
                        DOCKING_FEE_BASE,
                        docked,
                        ops.docking_capacity,
                        ops.condition,
                    ),
                    true,
                )
            }
        };
        if !has_space {
            return false;
        }
        let ship_ok = world
            .get::<ShipEconomy>(ship)
            .map(|econ| econ.credits >= fee)
            .unwrap_or(false);
        if !ship_ok {
            // Broke head of line — evict so everyone behind can
            // proceed. The ship's Dock action sees Failure (we
            // returned `false` on a head-level reject) and its BT
            // replans, usually into a sell_cargo or refuel-elsewhere
            // flow that can recover credits. Without this eviction
            // the broke head stalls the queue forever.
            if let Some(mut storage) = world.get_mut::<FacilityStorage>(e) {
                storage.dock_queue.retain(|&q| q != ship);
            }
            return false;
        }
        commit_dock(world, store, ship, e, fee);
        if let Some(mut storage) = world.get_mut::<FacilityStorage>(e) {
            storage.dock_queue.retain(|&q| q != ship);
        }
        return true;
    }

    // Case 2a: not queued anywhere — try for an immediate slot.
    // `docked + queue_len < cap` captures "a ship can fit without
    // stepping on queue order" — if the queue is non-empty those
    // slots are implicitly reserved for the waiting ships.
    for &e in &candidates {
        let (fee, can_admit) = {
            let ops = match world.get::<FacilityOperations>(e) {
                Some(o) => o,
                None => continue,
            };
            let storage = match world.get::<FacilityStorage>(e) {
                Some(s) => s,
                None => continue,
            };
            let docked = storage.docked_ships.len() as u32;
            let queued = storage.dock_queue.len() as u32;
            if docked + queued >= ops.docking_capacity {
                (0, false)
            } else {
                (
                    docking_fee(
                        DOCKING_FEE_BASE,
                        docked,
                        ops.docking_capacity,
                        ops.condition,
                    ),
                    true,
                )
            }
        };
        if !can_admit {
            continue;
        }
        let ship_ok = world
            .get::<ShipEconomy>(ship)
            .map(|econ| econ.credits >= fee)
            .unwrap_or(false);
        if !ship_ok {
            continue;
        }
        commit_dock(world, store, ship, e, fee);
        return true;
    }

    // Case 2b: all facilities are full or have queues that eat the
    // remaining capacity. Append to the shortest queue — balances
    // load across secondaries and minimises the waiting ship's wait.
    let mut shortest: Option<(Entity, usize)> = None;
    for &e in &candidates {
        let qlen = world
            .get::<FacilityStorage>(e)
            .map(|s| s.dock_queue.len())
            .unwrap_or(usize::MAX);
        match shortest {
            None => shortest = Some((e, qlen)),
            Some((_, best)) if qlen < best => shortest = Some((e, qlen)),
            _ => {}
        }
    }
    if let Some((e, _)) = shortest {
        if let Some(mut storage) = world.get_mut::<FacilityStorage>(e) {
            if !storage.dock_queue.contains(&ship) {
                storage.dock_queue.push(ship);
            }
        }
    }
    false
}

/// Remove stale entries from a facility's `dock_queue`. A queue entry
/// is "stale" if the ship entity no longer exists OR the ship's
/// current location_name doesn't match this facility's location (the
/// ship left without emitting anything that told us to drop it from
/// the queue — started a Travel, got admin-destroyed, etc.) OR the
/// ship is not actively attempting a dock right now
/// (`dock_attempt_start_tick.is_none()`).
///
/// That last case is load-bearing: when a ship's `ShipAction::Dock`
/// times out it clears `dock_attempt_start_tick` and returns Failure,
/// but nothing removes it from whatever queue it was in. The ship
/// usually stays at the same location (BT unwinds to a planner that
/// picks another local goal), so the location-match prune above can't
/// catch it — the stuck entry lives on at the head of the queue and
/// blocks every ship behind it. A 2026-04-24 diagnostic showed
/// `luna-base` with 0 ships docked and 2 queued against a capacity of
/// 25 — pure phantom entries from prior dock-timeouts.
///
/// Without this sweep a single vanished/idle ship can wedge the queue
/// head forever and every ship behind it starves.
pub fn prune_stale_dock_queue(world: &mut World, _store: &mut AgentStore, facility: Entity, location: &str) {
    use sim_core::agents::{
        facility::FacilityStorage,
        ship::{ShipEconomy, ShipPosition},
    };
    let queue_snapshot: Vec<Entity> = match world.get::<FacilityStorage>(facility) {
        Some(s) => s.dock_queue.clone(),
        None => return,
    };
    if queue_snapshot.is_empty() {
        return;
    }
    let mut keep: Vec<Entity> = Vec::with_capacity(queue_snapshot.len());
    for e in queue_snapshot {
        let still_here = world
            .get::<ShipPosition>(e)
            .map(|p| p.location_name.as_deref() == Some(location))
            .unwrap_or(false);
        if !still_here {
            continue;
        }
        let still_trying = world
            .get::<ShipEconomy>(e)
            .map(|econ| econ.dock_attempt_start_tick.is_some())
            .unwrap_or(false);
        if !still_trying {
            continue;
        }
        keep.push(e);
    }
    if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
        if storage.dock_queue.len() != keep.len() {
            storage.dock_queue = keep;
        }
    }
}

/// Shared dock-commit helper: debits fee, credits facility, pushes the
/// ship onto `docked_ships`, sets `ShipPosition.docked_at`. Caller is
/// responsible for any queue cleanup.
pub fn commit_dock(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    facility: Entity,
    fee: i64,
) {
    use sim_core::agents::{
        facility::{FacilityIdentity, FacilityOperations, FacilityStorage},
        ship::{ShipEconomy, ShipIdentity, ShipPosition},
    };
    // Bundle B: trade-pact / allied dock discount. Look up the
    // relation between the ship's faction and the facility's
    // owning faction once up front — same-faction + unfactioned
    // facilities both no-op into (1.0, 1.0).
    let ship_faction = world
        .get::<ShipIdentity>(ship)
        .map(|i| i.faction_id.clone())
        .unwrap_or_default();
    let fac_faction = world
        .get::<FacilityIdentity>(facility)
        .map(|i| i.faction_id.clone())
        .unwrap_or_default();
    let (fee_mult, burn_mult) =
        sim_core::agents::faction_relations::trade_pact_dock_modifier(
            &store.relations,
            &ship_faction,
            &fac_faction,
        );
    let discounted_fee = ((fee as f32) * fee_mult).round() as i64;
    if let Some(mut econ) = world.get_mut::<ShipEconomy>(ship) {
        econ.credits -= discounted_fee;
    }
    // Bundle (G): split the fee — facility takes the remainder
    // after burn, the burned portion is a true sink (subtracted
    // from the ship, never added to any balance). Burn fraction
    // lives in WorldTuning (Bundle Q); Bundle B further scales it
    // by treaty state so allied docks burn less (or nothing).
    let burn_pct = sim_core::simulation::tuning::WorldTuning::current().dock_fee_burn_pct;
    let effective_burn_pct = burn_pct * burn_mult;
    let burned = (discounted_fee as f32 * effective_burn_pct).round() as i64;
    let to_facility = discounted_fee - burned;
    if let Some(mut ops) = world.get_mut::<FacilityOperations>(facility) {
        ops.credits += to_facility;
        ops.dirty = true;
    }
    if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
        if !storage.docked_ships.contains(&ship) {
            storage.docked_ships.push(ship);
        }
    }
    if let Some(mut pos) = world.get_mut::<ShipPosition>(ship) {
        pos.docked_at = Some(facility);
    }
}

/// Apply `ReleaseDock`: remove the ship from the facility's docked_ships
/// list AND anchor the ship's position to the facility it's leaving.
///
/// The second part is the fix for the "ship teleports across the screen
/// when it undocks" bug. Ships don't publish a position while docked
/// (Godot hides them at that point), so on undock we need to place
/// them at the station's current coordinates — otherwise they
/// re-appear at whatever stale position the server last broadcast and
/// slide to the travel target from there. Mirroring the station's
/// position here gives Godot a clean "leaves the station" visual.
///
/// The ship's `docked_at` has already been cleared in-place by the
/// Undock action.
pub fn apply_release_dock(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    location: &str,
) {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{facility_orbit_position, FacilityIdentity, FacilityStorage},
        ship::ShipPosition,
    };
    let facility = match primary_dock_at_location(world, store, location) {
        Some(e) => e,
        None => return,
    };
    if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
        storage.docked_ships.retain(|&e| e != ship);
    }

    // Use the current orbit before the snapshot is published.
    let facility_pos = {
        let id = match world.get::<FacilityIdentity>(facility) {
            Some(id) => id.clone(),
            None => return,
        };
        let body_center = {
            let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
            q.iter(&world)
                .find(|(bid, _)| bid.body_id == id.body_id)
                .map(|(_, orbit)| (orbit.universe_position(), orbit.current_angle))
        };
        let Some((body_center, angle)) = body_center else {
            return;
        };
        facility_orbit_position(body_center, angle, &id.id)
    };

    if let Some(mut pos) = world.get_mut::<ShipPosition>(ship) {
        pos.position = facility_pos;
    }
}

/// Per-tick dock-queue advance. Independent of whether any queued
/// ship is currently emitting `RequestDock` — walks every facility
/// with a non-empty queue, prunes phantom entries inline, then
/// admits as many heads as the available space + the ships'
/// credits allow.
///
/// Why this exists: the original admission path only fires from a
/// ship's own `ShipAction::Dock` emitting `RequestDock`. When a
/// queued ship gets LOD-gated out (sitting at divisor 5/10/20/50)
/// it stops emitting RequestDock for most ticks — so even if the
/// facility has free slots, nothing pulls the queue forward. A
/// 5-minute soak surfaced luna-base with 0 docked and 3 queued
/// and similar patterns at proxima-outpost + belt-outpost. Moving
/// admission into a cadenced sweep decouples it from the ship's
/// individual tick cadence.
///
/// Cheap: only iterates facilities whose `dock_queue` is non-empty,
/// and most ticks have zero or a handful of such facilities.
pub fn tick_dock_queue_advance(world: &mut World, store: &mut AgentStore) {
    use sim_core::agents::{
        facility::{
            docking_fee, FacilityLocation, FacilityOperations, FacilityStorage,
            DOCKING_FEE_BASE,
        },
        ship::{ShipEconomy, ShipPosition},
    };

    let facilities: Vec<(Entity, String)> = {
        let mut q = world
            .query::<(Entity, &FacilityLocation, &FacilityStorage)>();
        q.iter(&world)
            .filter(|(_, _, s)| !s.dock_queue.is_empty())
            .map(|(e, loc, _)| (e, loc.location_name.clone()))
            .collect()
    };

    for (facility, location) in facilities {
        // Inline prune: drop entries whose ship moved or whose
        // `dock_attempt_start_tick` was cleared (timed out / replanned).
        let pruned: Vec<Entity> = {
            let q = match world.get::<FacilityStorage>(facility) {
                Some(s) => s.dock_queue.clone(),
                None => continue,
            };
            q.into_iter()
                .filter(|&e| {
                    let still_here = world
                        .get::<ShipPosition>(e)
                        .map(|p| p.location_name.as_deref() == Some(location.as_str()))
                        .unwrap_or(false);
                    let still_trying = world
                        .get::<ShipEconomy>(e)
                        .map(|econ| econ.dock_attempt_start_tick.is_some())
                        .unwrap_or(false);
                    still_here && still_trying
                })
                .collect()
        };
        if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
            if storage.dock_queue.len() != pruned.len() {
                storage.dock_queue = pruned;
            }
        }

        // Admit as many heads as we can — bounded by available
        // slots and the head's ability to pay the fee. Broke head
        // evicts without advancing the docked count.
        loop {
            let head = match world.get::<FacilityStorage>(facility) {
                Some(s) => s.dock_queue.first().copied(),
                None => break,
            };
            let Some(ship) = head else { break };

            let (fee, has_space) = {
                let ops = match world.get::<FacilityOperations>(facility) {
                    Some(o) => o,
                    None => break,
                };
                let storage = match world.get::<FacilityStorage>(facility) {
                    Some(s) => s,
                    None => break,
                };
                let docked = storage.docked_ships.len() as u32;
                if docked >= ops.docking_capacity {
                    (0, false)
                } else {
                    (
                        docking_fee(
                            DOCKING_FEE_BASE,
                            docked,
                            ops.docking_capacity,
                            ops.condition,
                        ),
                        true,
                    )
                }
            };
            if !has_space {
                break;
            }
            let can_afford = world
                .get::<ShipEconomy>(ship)
                .map(|econ| econ.credits >= fee)
                .unwrap_or(false);
            if !can_afford {
                // Evict broke head so everyone behind can proceed.
                // The ship's own Dock action sees queue absence next
                // tick, BT unwinds, planner routes to a sell_cargo /
                // refuel-elsewhere flow.
                if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
                    storage.dock_queue.retain(|&q| q != ship);
                }
                continue;
            }
            commit_dock(world, store, ship, facility, fee);
            if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
                storage.dock_queue.retain(|&q| q != ship);
            }
        }
    }
}


/// Apply `RequestGateJump`: locate the source gate at the ship's
/// location, charge the fee, credit the gate's owning facility,
/// teleport the ship to the paired gate's position. Emits a
/// `ship_gate_jumped` event for the HUD.
///
/// Silently no-ops when the ship isn't at a gate, the gate has no
/// link, or the ship can't afford the fee — the BT's
/// speculative position update has already moved the ship locally,
/// but apply reverses it by just... not actually teleporting (which
/// would be a bug). **TODO**: in a future pass, make the BT commit
/// position change only after apply confirms — current model is
/// optimistic and can drift if the jump fails. Low risk today because
/// the planner's "can_afford" check guards it.
pub fn apply_gate_jump(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    src_gate_location: &str,
    dest_gate_location: &str,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::{
        facility::{gate_transit_fee, FacilityIdentity, FacilityOperations, GateLink},
        ship::{ShipCargo, ShipEconomy, ShipIdentity, ShipPosition},
    };

    // Find the source gate facility at the requested location. Ignore
    // non-gate facilities at the same location.
    let src_gate_entity = store
        .facilities_at_location
        .get(src_gate_location)
        .into_iter()
        .flatten()
        .copied()
        .find(|&e| world.get::<GateLink>(e).is_some());
    let Some(src_gate_entity) = src_gate_entity else {
        return;
    };

    // Pull the fee up front (all reads) before any mutation.
    let (fee, paired_id) = {
        let link = match world.get::<GateLink>(src_gate_entity) {
            Some(l) => l,
            None => return,
        };
        let cargo_used = world
            .get::<ShipCargo>(ship)
            .map(|c| c.used())
            .unwrap_or(0);
        (gate_transit_fee(&link, cargo_used), link.paired_gate_id.clone())
    };

    // Ship must be able to pay.
    let can_afford = world
        .get::<ShipEconomy>(ship)
        .map(|e| e.credits >= fee)
        .unwrap_or(false);
    if !can_afford {
        return;
    }

    // Deduct from ship, credit gate.
    if let Some(mut econ) = world.get_mut::<ShipEconomy>(ship) {
        econ.credits -= fee;
    }
    if let Some(mut ops) = world.get_mut::<FacilityOperations>(src_gate_entity) {
        ops.credits += fee;
        ops.dirty = true;
    }

    // Resolve the paired gate and its position, teleport the ship.
    let dest_entity = store.facility_by_id.get(&paired_id).copied();
    let ship_new_pos = dest_entity.and_then(|e| {
        let id = world.get::<FacilityIdentity>(e)?.id.clone();
        // Find the body the paired gate is orbiting so we can compute
        // the offset-position to match where the paired gate renders.
        let body_id = world.get::<FacilityIdentity>(e)?.body_id.clone();
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let body_pos = {
            let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
            q.iter(&world)
                .find(|(bid, _)| bid.body_id == body_id)
                .map(|(_, orbit)| (orbit.universe_position(), orbit.current_angle))
        };
        let (body_pos, angle) = body_pos?;
        Some(sim_core::agents::facility::facility_orbit_position(
            body_pos, angle, &id,
        ))
    });
    if let Some(mut pos) = world.get_mut::<ShipPosition>(ship) {
        pos.location_name = Some(dest_gate_location.to_string());
        pos.docked_at = None;
        if let Some(new_pos) = ship_new_pos {
            pos.position = new_pos;
        }
    }

    // Phase 19h: record the destination system on the ship's recent
    // memory so the explore planner will prefer ELSEWHERE next time
    // it picks a target — prevents gate yo-yo (A ↔ B on repeat).
    // Runs only on real crossings (src system != dst system).
    {
        use sim_core::agents::ship::{ShipMemory, RECENT_SYSTEMS_CAP};
        // Infer destination system from any facility at the paired
        // gate location. Cheap enough to do per jump (rare event).
        let dest_system: Option<String> = {
            use sim_core::agents::celestial_body::BodyIdentity;
            use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
            let body_id = {
                let mut q = world
                    .query::<(&FacilityIdentity, &FacilityLocation)>();
                q.iter(&world)
                    .find(|(_, loc)| loc.location_name == dest_gate_location)
                    .map(|(id, _)| id.body_id.clone())
            };
            body_id.and_then(|b| {
                let mut q = world.query::<&BodyIdentity>();
                q.iter(&world)
                    .find(|id| id.body_id == b)
                    .map(|id| id.system_name.clone())
            })
        };
        if let Some(dst_sys) = dest_system {
            if let Some(mut mem) = world.get_mut::<ShipMemory>(ship) {
                // Push only on new-system entry (skip if already
                // the most recent entry — rare but defensive).
                if mem.recent_systems.back() != Some(&dst_sys) {
                    mem.recent_systems.push_back(dst_sys);
                    while mem.recent_systems.len() > RECENT_SYSTEMS_CAP {
                        mem.recent_systems.pop_front();
                    }
                }
            }
        }
    }

    let ship_id = world
        .get::<ShipIdentity>(ship)
        .map(|i| i.id.clone())
        .unwrap_or_else(|| "unknown".to_string());
    events.push(serde_json::json!({
        "kind": "ship_gate_jumped",
        "id": ship_id,
        "src_gate": src_gate_location,
        "dest_gate": dest_gate_location,
        "fee": fee,
    }));
}

/// Apply `FacilityRefuel`: drain fuel from the facility's reserves and
/// credit the facility's treasury. Ship-side fuel/credit updates already
/// happened when the command was emitted.
pub fn apply_facility_refuel(
    world: &mut World,
    store: &mut AgentStore,
    location: &str,
    amount: f32,
    payment: i64,
) {
    use sim_core::{
        agents::facility::{FacilityOperations, FacilityStorage},
        economy::commodities::Commodity,
    };
    let facility = match primary_dock_at_location(world, store, location) {
        Some(e) => e,
        None => return,
    };
    if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
        let entry = storage.reserves.entry(Commodity::Fuel).or_insert(0.0);
        *entry = (*entry - amount).max(0.0);
    }
    if let Some(mut ops) = world.get_mut::<FacilityOperations>(facility) {
        ops.credits += payment;
        ops.dirty = true;
    }
}

/// Phase 19c-c/d: route a Construction delivery into the matching
/// site's progress. When progress hits 1.0, the site materialises
/// into a real facility at the same position and the site entity is
/// despawned. Fires `construction_progress` and, on finish,
/// `construction_completed` events.
pub fn apply_construction_delivery(
    world: &mut World,
    store: &mut AgentStore,
    destination: &str,
    commodity: sim_core::economy::commodities::Commodity,
    quantity: u32,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::construction::{self, ConstructionSite};

    let site_entity = match construction::find_site(world, destination, commodity) {
        Some(e) => e,
        None => {
            // No matching site — fall through to normal market drop
            // as a graceful degradation. Shouldn't normally happen
            // because the demand analyzer spawns the site before
            // posting the contract.
            if let Some(&market_entity) = store.market_at_location.get(destination) {
                if let Some(mut pricing) = world
                    .get_mut::<sim_core::agents::market::MarketPricing>(market_entity)
                {
                    *pricing.supply.entry(commodity).or_insert(0.0) += quantity as f32;
                }
            }
            return;
        }
    };

    // Snapshot the fields we need before mutating.
    let (site_id, site_name, completed_now, new_progress, facility_type, body_id,
         faction_id, position, site_location) = {
        if let Some(mut site) = world.get_mut::<ConstructionSite>(site_entity) {
            let absorbed = quantity.min(site.remaining());
            site.progress_delivered = site.progress_delivered.saturating_add(absorbed);
            site.dirty = true;
            let progress = site.progress();
            let finished = progress >= 1.0 && !site.completed;
            if finished {
                site.completed = true;
            }
            (
                site.id.clone(),
                site.name.clone(),
                finished,
                progress,
                site.facility_type.clone(),
                site.body_id.clone(),
                site.faction_id.clone(),
                site.position,
                site.location_name.clone(),
            )
        } else {
            return;
        }
    };

    events.push(serde_json::json!({
        "kind": "construction_progress",
        "site_id": site_id,
        "progress": new_progress,
        "location": site_location,
    }));

    if completed_now {
        // Despawn the site, materialise a real facility at the same
        // position via the shared admin-spawn plumbing. DB INSERT for
        // the new facility is queued via `pending_materializations`
        // and drained asynchronously right after the apply phase; the
        // site row itself is deleted here so restart doesn't resurrect
        // a completed site.
        let _ = world.despawn(site_entity);
        materialize_facility(
            world,
            store,
            &site_id,
            &site_name,
            &facility_type,
            &body_id,
            &faction_id,
            &site_location,
            position,
            events,
        );
    }
}
