//! Ship behavior-tree actions.
//!
//! `ShipAction` is the leaf-action enum consumed by the BT engine;
//! `execute_ship_action` is the dispatch function the planner passes
//! to `BtNode::tick`. Extracted from the former monolithic `ship.rs`
//! in the Phase-20 refactor.
//!
//! This module is intentionally mechanical: each variant of
//! `ShipAction` has exactly one arm in `execute_ship_action` that
//! reads/writes ship components, optionally pushes a `SimCommand`
//! for cross-entity effects, and returns the BT status (Success /
//! Running / Failure).

use super::{
    CrewTask, ShipCargo, ShipCrew, ShipEconomy, ShipFuel, ShipMemory, ShipPosition,
    ShipTransit, Transit, CREW_REST_TARGET, DOCK_WAIT_DEFAULT, DOCK_WAIT_LOW_MORALE,
    DOCK_WAIT_LOW_MORALE_THRESHOLD, DOCK_WAIT_WITH_CONTRACT, MAX_REST_TICKS_BASE,
};
use crate::ai::behavior_tree::{Blackboard, BtStatus};
use crate::economy::commodities::Commodity;
use crate::simulation::commands::{CommandBuffer, SimCommand};
use crate::world::{registry::WorldRegistry, travel};

/// Ship-specific BT leaf actions. Each variant carries the parameters it
/// needs — the dispatch closure in `ship::decide_and_act` reads them and
/// executes against the ship's components.
#[derive(Debug, Clone)]
pub enum ShipAction {
    /// Begin transit to a named location. Returns Running until arrival.
    Travel { destination: String },
    /// Mark the ship as docked at its current location. Picks the
    /// highest-capacity dockable facility (stations tend to win).
    Dock,
    /// Variant of `Dock` that prefers a shipyard at the current
    /// location. Used by the Phase-18d retrofit BT so the ship
    /// doesn't park at the trade station when a shipyard shares the
    /// same location slug.
    DockAtShipyard,
    /// Undock (clear docked_at).
    Undock,
    /// Refill fuel to capacity (MVP: free refill at any location).
    Refuel,
    /// Buy up to `qty` units of `commodity` at the ship's current location.
    /// Returns Failure if no local price or ship can't afford any.
    Buy { commodity: Commodity, qty: u32 },
    /// Sell `qty` of `commodity` at the current location. `qty = 0` means "all".
    Sell { commodity: Commodity, qty: u32 },
    /// Sell every commodity in the hold.
    SellAll,
    /// Accept a delivery contract by id (Phase 8b).
    AcceptContract { contract_id: String },
    /// Pick up the cargo reserved for an accepted contract (Phase 8b).
    PickupCargo { contract_id: String },
    /// Deliver contract cargo and collect payment (Phase 8b).
    DeliverCargo { contract_id: String },
    /// Do nothing — always succeeds.
    Idle,
    /// Shore leave: dwell at current location until crew morale recovers.
    /// Returns Running until morale > CREW_REST_TARGET, then Success.
    Rest,
    /// Visible station dwell — "loading/unloading/paperwork/crew activity"
    /// time. Returns Running until `seconds` wall-clock seconds have
    /// elapsed (at TPS=8, that's `seconds × 8` base ticks), regardless of
    /// world_speed. Without this, the Dock→Refuel→Undock chain can
    /// complete in a few ticks and the ship visibly flickers off the pad.
    /// `dock_dwell_start_tick` on ShipEconomy tracks the deadline across
    /// ticks.
    DockDwell { seconds: u8 },
    /// Jump through a gate. Ship must be at `src_gate` location. Apply
    /// phase charges the gate fee (`flat + per_cargo × cargo_used`) and
    /// teleports the ship to `dest_gate`. Instant — no transit time.
    /// Fails if the ship can't afford the fee or isn't at the source
    /// gate.
    GateJump {
        src_gate: String,
        dest_gate: String,
    },
    /// Agent-driven subsystem install (Phase 18d). Emits
    /// `SimCommand::RequestRefit` and returns `Success` — the apply
    /// phase does the economic swap (debit ship, credit shipyard,
    /// decrement stock, spend retrofit point). The BT baked `slot` +
    /// `slug` in at plan time from the shipyard inventory snapshot.
    /// Ship must already be docked at a shipyard carrying `slug` with
    /// enough credits — the retrofit planner guarantees this at plan
    /// time; apply verifies again in case state drifted while the
    /// ship flew there.
    Refit {
        slot: crate::modules::Slot,
        slug: &'static str,
    },
}

pub(super) fn execute_ship_action(
    action: &ShipAction,
    entity: hecs::Entity,
    ship_id: &str,
    crew: &mut ShipCrew,
    position: &mut ShipPosition,
    transit: &mut ShipTransit,
    cargo: &mut ShipCargo,
    fuel: &mut ShipFuel,
    economy: &mut ShipEconomy,
    memory: &mut ShipMemory,
    registry: &WorldRegistry,
    commands: &mut CommandBuffer,
    tick: u64,
    config: &crate::simulation::config::TickConfig,
    _bb: &mut Blackboard,
) -> BtStatus {
    match action {
        ShipAction::Idle => BtStatus::Success,

        ShipAction::DockDwell { seconds } => {
            // Wall-clock timed dwell. Uses TPS (ticks_per_second) directly
            // so `seconds` always means real seconds at the pad, regardless
            // of `world_speed`. `economy.dock_dwell_start_tick` is set on
            // first entry and cleared on completion so a BT re-tick of the
            // same node continues its countdown instead of restarting.
            let total_ticks = (*seconds as u64) * config.ticks_per_second as u64;
            let start = match economy.dock_dwell_start_tick {
                Some(t) => t,
                None => {
                    economy.dock_dwell_start_tick = Some(tick);
                    tick
                }
            };
            if tick.saturating_sub(start) >= total_ticks {
                economy.dock_dwell_start_tick = None;
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Rest => {
            // Returns Running until morale has recovered to
            // CREW_REST_TARGET. `tick_crew` handles the actual recovery
            // via CrewTask::Resting (triggered automatically when fatigue
            // is high).
            //
            // Phase 18k: also caps the rest at MAX_REST_TICKS so a ship
            // whose `Dock` was silently dropped by the apply phase
            // (facility at capacity) doesn't stay pinned on Rest forever
            // with morale=0 — it gives up after the budget elapses so
            // the BT unwinds and the planner can re-plan (likely at
            // a different location if this one's congested).
            //
            // `rest_start_tick` on ShipEconomy tracks the start; cleared
            // here on success so the next Rest action starts fresh.
            let mult = config.tick_multiplier().max(1) as u64;
            let budget = MAX_REST_TICKS_BASE * mult;
            let start = match economy.rest_start_tick {
                Some(t) => t,
                None => {
                    economy.rest_start_tick = Some(tick);
                    tick
                }
            };
            let elapsed = tick.saturating_sub(start);
            if crew.morale >= CREW_REST_TARGET || elapsed >= budget {
                economy.rest_start_tick = None;
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Dock => {
            // Phase 18L: multi-tick with context-dependent wait budget.
            //  - If we're already docked, clear the attempt marker +
            //    Success. Happens on the tick after apply accepted us.
            //  - If we aren't docked yet, emit a RequestDock command and
            //    return Running. `dock_attempt_start_tick` on
            //    ShipEconomy tracks when we first started trying.
            //  - If the wait budget elapsed without a dock, give up →
            //    Failure. BT unwinds, planner replans; if the planner
            //    picks rest_crew again, the congestion-aware rest
            //    builder will try to route to a less-busy station.
            if position.docked_at.is_some() {
                economy.dock_attempt_start_tick = None;
                return BtStatus::Success;
            }
            let loc = match &position.location_name {
                Some(l) => l.clone(),
                None => {
                    economy.dock_attempt_start_tick = None;
                    return BtStatus::Failure;
                }
            };
            let start = match economy.dock_attempt_start_tick {
                Some(t) => t,
                None => {
                    economy.dock_attempt_start_tick = Some(tick);
                    tick
                }
            };
            let morale = crew.morale;
            let wait_base = if economy.active_contract_id.is_some() {
                DOCK_WAIT_WITH_CONTRACT
            } else if morale < DOCK_WAIT_LOW_MORALE_THRESHOLD {
                DOCK_WAIT_LOW_MORALE
            } else {
                DOCK_WAIT_DEFAULT
            };
            let budget = wait_base * config.tick_multiplier().max(1) as u64;
            if tick.saturating_sub(start) >= budget {
                economy.dock_attempt_start_tick = None;
                return BtStatus::Failure;
            }
            commands.push(SimCommand::RequestDock {
                ship: entity,
                facility_location: loc,
                preferred_facility_type: None,
            });
            BtStatus::Running
        }

        ShipAction::DockAtShipyard => {
            // Same as Dock, but the apply phase will prefer a
            // facility_type = "shipyard" at the current location so
            // the retrofit BT doesn't accidentally dock at the
            // highest-capacity station (which in sol is the trade
            // station, not the shipyard).
            //
            // Phase 18L: multi-tick, same wait-budget shape as Dock.
            // Retrofit ships are explicitly "no active contract"
            // (they wouldn't be retrofitting mid-job), so the
            // default/low-morale budget applies.
            if position.docked_at.is_some() {
                economy.dock_attempt_start_tick = None;
                return BtStatus::Success;
            }
            let loc = match &position.location_name {
                Some(l) => l.clone(),
                None => {
                    economy.dock_attempt_start_tick = None;
                    return BtStatus::Failure;
                }
            };
            let start = match economy.dock_attempt_start_tick {
                Some(t) => t,
                None => {
                    economy.dock_attempt_start_tick = Some(tick);
                    tick
                }
            };
            let wait_base = if crew.morale < DOCK_WAIT_LOW_MORALE_THRESHOLD {
                DOCK_WAIT_LOW_MORALE
            } else {
                DOCK_WAIT_DEFAULT
            };
            let budget = wait_base * config.tick_multiplier().max(1) as u64;
            if tick.saturating_sub(start) >= budget {
                economy.dock_attempt_start_tick = None;
                return BtStatus::Failure;
            }
            commands.push(SimCommand::RequestDock {
                ship: entity,
                facility_location: loc,
                preferred_facility_type: Some("shipyard"),
            });
            BtStatus::Running
        }

        ShipAction::Undock => {
            // Release our slot on the facility's docked_ships list.
            // Clear our own docked_at in-place so we don't re-request dock
            // next tick before the apply phase runs.
            if let Some(loc) = position.location_name.clone() {
                commands.push(SimCommand::ReleaseDock {
                    ship: entity,
                    facility_location: loc,
                });
            }
            position.docked_at = None;
            BtStatus::Success
        }

        ShipAction::Refuel => {
            // Multi-tick refuel. Each call drains one REFUEL_UNITS_PER_TICK
            // chunk from the facility's fuel reserves and charges the ship.
            // Returns Running until the tank is full, then Success. If the
            // ship can't afford the next increment, returns Failure so the
            // BT falls through to a different plan (station job, etc.).
            use crate::agents::facility::{REFUEL_PRICE_PER_UNIT, REFUEL_UNITS_PER_TICK};
            if fuel.fuel >= fuel.fuel_capacity - 0.001 {
                return BtStatus::Success;
            }
            let loc = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let amount = REFUEL_UNITS_PER_TICK.min(fuel.fuel_capacity - fuel.fuel);
            let payment = (amount.ceil() as i64) * REFUEL_PRICE_PER_UNIT;
            if economy.credits < payment {
                return BtStatus::Failure;
            }
            fuel.fuel += amount;
            economy.credits -= payment;
            commands.push(SimCommand::FacilityRefuel {
                ship: entity,
                facility_location: loc,
                amount,
                payment,
            });
            if fuel.fuel >= fuel.fuel_capacity - 0.001 {
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Travel { destination } => {
            // If we're already at the destination, step succeeds immediately
            if position.location_name.as_deref() == Some(destination.as_str()) {
                return BtStatus::Success;
            }
            // If already in transit, return Running until arrival
            if let Some(t) = &transit.transit {
                if tick >= t.arrival_tick {
                    // Arrival handled by advance_transits; this is the step completion
                    return BtStatus::Success;
                }
                return BtStatus::Running;
            }
            // Start the transit
            let from = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let distance = registry
                .travel_distance(&from, destination)
                .or_else(|| registry.travel_distance(destination, &from))
                .unwrap_or(60);
            let arrival = travel::arrival_tick(tick, distance, fuel.speed_modifier, config);
            transit.transit = Some(Transit {
                from,
                to: destination.clone(),
                departure_tick: tick,
                arrival_tick: arrival,
                departure_position: Some(position.position),
                distance_total: distance as f32,
                distance_travelled: 0.0,
            });
            position.location_name = None;
            position.docked_at = None;
            BtStatus::Running
        }

        ShipAction::Buy { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let want = affordable_quantity(economy.credits, price, cargo.free()).min(*qty);
            if want == 0 {
                return BtStatus::Failure;
            }
            let cost = (price * want as f32) as i64;
            economy.credits -= cost;
            *cargo.cargo.entry(*commodity).or_insert(0) += want;
            cargo.cargo_age.insert(*commodity, tick);
            // Phase 20: remember origin + unit price so the Sell arm
            // can compute realised profit and feed route_performance.
            cargo.cargo_origin.insert(*commodity, (at.clone(), price));
            commands.push(SimCommand::RemoveSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: want as f32,
            });
            // A successful trade grows the crew's trading skill by 1 (cap 100).
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "trading",
                amount: 1,
            });
            crew.current_task = CrewTask::Loading;
            BtStatus::Success
        }

        ShipAction::Sell { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let have = cargo.cargo.get(commodity).copied().unwrap_or(0);
            let amount = if *qty == 0 { have } else { (*qty).min(have) };
            if amount == 0 {
                return BtStatus::Failure;
            }
            let revenue = (price * amount as f32) as i64;
            economy.credits += revenue;
            // Phase 20: record realised trade-route outcome if the
            // sell location differs from where this cargo was
            // bought. The Buy arm stamps `cargo_origin`; we consume
            // it here once the full batch is sold so avg stays
            // trade-round-accurate.
            let origin_info = cargo.cargo_origin.get(commodity).cloned();
            let new_remaining = have - amount;
            if new_remaining == 0 {
                cargo.cargo.remove(commodity);
                cargo.cargo_age.remove(commodity);
                cargo.cargo_origin.remove(commodity);
                if let Some((bought_at, buy_price)) = origin_info {
                    if bought_at != at {
                        let profit = price - buy_price;
                        memory
                            .route_performance
                            .entry((bought_at, at.clone(), *commodity))
                            .or_default()
                            .record(profit);
                    }
                }
            } else {
                cargo.cargo.insert(*commodity, new_remaining);
            }
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: amount as f32,
            });
            BtStatus::Success
        }

        ShipAction::SellAll => {
            // Multi-tick unload — each call sells one commodity from the
            // hold. Returns Running if more cargo remains after selling
            // this commodity, Success when the hold is empty. Makes a
            // full unload visibly take N ticks where N = distinct
            // commodities in cargo.
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let prices = match memory.price_knowledge.get(&at) {
                Some(p) => p,
                None => return BtStatus::Failure,
            };
            // Pick a deterministic commodity (lowest as_str order) so
            // repeated calls progress through the hold in a stable order.
            let next = cargo
                .cargo
                .iter()
                .filter(|(_, &q)| q > 0)
                .filter(|(c, _)| prices.contains_key(c))
                .map(|(&c, &q)| (c, q))
                .min_by_key(|(c, _)| c.as_str());
            let (commodity, qty) = match next {
                Some(pair) => pair,
                None => return BtStatus::Success, // nothing sellable left
            };
            let price = prices
                .get(&commodity)
                .map(|pm| pm.price)
                .unwrap_or(0.0);
            let revenue = (price * qty as f32) as i64;
            economy.credits += revenue;
            // Phase 20: record realised route outcome before clearing
            // cargo_origin. SellAll always sells the whole stack, so
            // unlike partial Sell we don't need a remaining-qty guard.
            let origin_info = cargo.cargo_origin.remove(&commodity);
            cargo.cargo.remove(&commodity);
            cargo.cargo_age.remove(&commodity);
            if let Some((bought_at, buy_price)) = origin_info {
                if bought_at != at {
                    let profit = price - buy_price;
                    memory
                        .route_performance
                        .entry((bought_at, at.clone(), commodity))
                        .or_default()
                        .record(profit);
                }
            }
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity,
                quantity: qty as f32,
            });
            crew.current_task = CrewTask::Unloading;
            // Running if more cargo remains; otherwise Success.
            if cargo.cargo.values().any(|&q| q > 0) {
                BtStatus::Running
            } else {
                BtStatus::Success
            }
        }

        ShipAction::AcceptContract { contract_id } => {
            // Set the ship's active contract (own state) and emit a command
            // that the engine's apply phase will use to mutate the board.
            economy.active_contract_id = Some(contract_id.clone());
            commands.push(SimCommand::AcceptContract {
                ship: entity,
                ship_id: ship_id.to_string(),
                contract_id: contract_id.clone(),
            });
            BtStatus::Success
        }

        ShipAction::PickupCargo { .. } => {
            // Phase 8b doesn't use this variant (pickup is implicit via Buy).
            // Kept for future "pre-reserved cargo" contracts in Phase 8c.
            BtStatus::Success
        }

        ShipAction::Refit { slot, slug } => {
            // Ship must be docked — the plan put us at the shipyard.
            // If we aren't docked (rare: interrupt between Dock and
            // Refit), fail the action and let the BT unwind. Apply
            // also re-validates shipyard + stock + credits +
            // retrofit point availability.
            if position.docked_at.is_none() {
                return BtStatus::Failure;
            }
            commands.push(SimCommand::RequestRefit {
                ship: entity,
                slot: *slot,
                slug,
            });
            BtStatus::Success
        }

        ShipAction::GateJump { src_gate, dest_gate } => {
            // Must be at the source gate's location.
            if position.location_name.as_deref() != Some(src_gate.as_str()) {
                return BtStatus::Failure;
            }
            // Optimistic client-side fee estimate — the gate might charge
            // a different amount in apply, but this prevents the ship
            // from emitting jumps it clearly can't afford. Conservative
            // default fee of 300 (base flat 200 + some cargo surcharge).
            // The apply phase does the real deduction.
            if economy.credits < 50 {
                return BtStatus::Failure;
            }
            commands.push(SimCommand::RequestGateJump {
                ship: entity,
                src_gate_location: src_gate.clone(),
                dest_gate_location: dest_gate.clone(),
            });
            // Speculatively update our local position to the dest gate —
            // apply phase will confirm. This keeps the BT moving forward
            // this tick rather than stalling for one tick on every jump.
            position.location_name = Some(dest_gate.clone());
            position.docked_at = None;
            BtStatus::Success
        }

        ShipAction::DeliverCargo { contract_id } => {
            // Ship must be at a location (destination) and must have cargo.
            // The engine apply phase will: pay the ship, reduce cargo, add
            // supply at the destination market, and mark the contract Paid.
            if position.location_name.is_none() {
                return BtStatus::Failure;
            }
            commands.push(SimCommand::DeliverContract {
                ship: entity,
                contract_id: contract_id.clone(),
            });
            // Navigation + trading skill bumps for a successful delivery.
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "navigation",
                amount: 1,
            });
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "trading",
                amount: 1,
            });
            economy.active_contract_id = None;
            crew.current_task = CrewTask::Unloading;
            BtStatus::Success
        }
    }
}

pub(super) fn affordable_quantity(credits: i64, price: f32, capacity: u32) -> u32 {
    if price <= 0.0 || credits <= 0 {
        return 0;
    }
    let by_credits = (credits as f32 / price) as u32;
    by_credits.min(capacity)
}
