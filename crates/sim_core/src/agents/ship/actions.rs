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
    ShipCargo, ShipCrew, ShipEconomy, ShipFuel, ShipMemory, ShipPosition,
    ShipTransit, ShipTransaction, Transit, CREW_REST_TARGET, DOCK_WAIT_DEFAULT, DOCK_WAIT_LOW_MORALE,
    DOCK_WAIT_LOW_MORALE_THRESHOLD, DOCK_WAIT_WITH_CONTRACT, MAX_REST_TICKS_BASE,
};
use crate::ai::behavior_tree::{BbValue, Blackboard, BtStatus};
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
    /// Request paid refuelling from the docked facility; wait for each receipt.
    Refuel,
    /// Buy up to `qty` units of `commodity` at the ship's current location.
    /// Returns Failure if no local price or ship can't afford any.
    Buy { commodity: Commodity, qty: u32 },
    /// Extract real body resources into a miner's cargo hold at a physical
    /// nav location, after a short mining shift. No market inventory is
    /// created until that ship returns and sells the ore/ice.
    Mine { location: String, body_id: String, commodity: Commodity, quantity: u32 },
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
    /// Remain on site while the server performs paid construction shifts.
    Construct { site_id: String, location: String },
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

#[allow(clippy::too_many_arguments)]
pub(super) fn execute_ship_action(
    action: &ShipAction,
    entity: bevy_ecs::prelude::Entity,
    _ship_id: &str,
    ship_faction: &str,
    crew: &mut ShipCrew,
    position: &mut ShipPosition,
    transit: &mut ShipTransit,
    cargo: &mut ShipCargo,
    fuel: &mut ShipFuel,
    economy: &mut ShipEconomy,
    memory: &mut ShipMemory,
    registry: &WorldRegistry,
    relations: &crate::agents::faction_relations::FactionRelations,
    controller_by_location: &std::collections::HashMap<String, String>,
    commands: &mut CommandBuffer,
    tick: u64,
    config: &crate::simulation::config::TickConfig,
    _bb: &mut Blackboard,
) -> BtStatus {
    match action {
        ShipAction::Idle => BtStatus::Success,
        ShipAction::Construct { location, .. } => {
            if position.location_name.as_deref() == Some(location.as_str()) && position.docked_at.is_some() && transit.transit.is_none() {
                BtStatus::Running
            } else { BtStatus::Failure }
        },

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
                // Bundle 1.4: if we hit the budget without morale
                // actually recovering, record the trauma for the
                // planner frame to drift personality toward safety.
                // Reading happens in `decide_and_act` right after
                // `bt.tick()` returns.
                if crew.morale < CREW_REST_TARGET {
                    _bb.set("rest_timed_out", BbValue::Bool(true));
                }
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
            if let Some(status) = poll_transaction(economy, |r| matches!(r, ShipTransaction::Refuel { .. })) {
                if status != BtStatus::Success { return status; }
            }
            if fuel.fuel >= fuel.fuel_capacity - 0.001 {
                return BtStatus::Success;
            }
            let Some(location) = position.location_name.clone() else { return BtStatus::Failure; };
            request_transaction(economy, commands, entity, ShipTransaction::Refuel { location })
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

        ShipAction::Mine { location, body_id, commodity, quantity } => {
            if let Some(status) = poll_transaction(economy, |r| matches!(r,
                ShipTransaction::Mine { location: at, body_id: body, commodity: c, quantity: qty }
                    if at == location && body == body_id && c == commodity && *qty > 0 && qty <= quantity
            )) {
                return status;
            }
            if position.location_name.as_deref() != Some(location.as_str())
                || transit.transit.is_some() || position.docked_at.is_some()
                || cargo.free() == 0
            {
                economy.dock_dwell_start_tick = None;
                return BtStatus::Failure;
            }
            // Measured in game time, rather than raw CPU/technical ticks.
            // Reuses the mutually exclusive BT dwell cursor; subsequent
            // dock actions start a new window.
            const MINE_SHIFT_GAME_SECONDS: u64 = 3;
            let ticks_to_work = MINE_SHIFT_GAME_SECONDS
                * config.tick_multiplier().max(1) as u64;
            let start = *economy.dock_dwell_start_tick.get_or_insert(tick);
            if tick.saturating_sub(start) < ticks_to_work {
                return BtStatus::Running;
            }
            economy.dock_dwell_start_tick = None;
            request_transaction(economy, commands, entity, ShipTransaction::Mine {
                location: location.clone(),
                body_id: body_id.clone(),
                commodity: *commodity,
                quantity: (*quantity).min(cargo.free()),
            })
        }

        ShipAction::Buy { commodity, qty } => {
            if let Some(status) = poll_transaction(economy, |r| matches!(r,
                ShipTransaction::Buy { commodity: c, .. } if c == commodity)) {
                return status;
            }

            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            // Enforce diplomatic embargo at the transaction point, not
            // only in GOAP planning. An old in-flight order or loaded
            // contract must never buy/sell at a newly hostile market.
            let owner = controller_by_location.get(&at).map(String::as_str).unwrap_or("");
            if !crate::agents::faction_relations::commerce_allowed(
                relations, ship_faction, owner,
            ) {
                return BtStatus::Failure;
            }
            let base_price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            // Bundle C: market-posture surcharge/discount. Controller
            // at this location plus the ship's stored rep with them
            // drives the multiplier (friend 0.75× → enemy 1.25×,
            // hostile treaty doubles any surcharge). Neutral at
            // unowned markets.
            let controller = controller_by_location
                .get(&at)
                .map(|s| s.as_str())
                .unwrap_or("");
            let rep = economy
                .faction_reputation
                .get(controller)
                .copied()
                .unwrap_or(0);
            let posture = crate::agents::faction_relations::market_buy_multiplier(
                relations,
                ship_faction,
                rep,
                controller,
            );
            let price = base_price * posture;
            let want = affordable_quantity(economy.credits, price, cargo.free()).min(*qty);
            if want == 0 {
                return BtStatus::Failure;
            }
            request_transaction(economy, commands, entity, ShipTransaction::Buy {
                location: at, commodity: *commodity, quantity: want, max_unit_price: price,
            })
        }

        ShipAction::Sell { commodity, qty } => {
            if let Some(status) = poll_transaction(economy, |r| matches!(r,
                ShipTransaction::Sell { commodity: c, .. } if c == commodity)) {
                return status;
            }
            let Some(at) = position.location_name.clone() else { return BtStatus::Failure };
            let Some(price) = memory.price_knowledge.get(&at).and_then(|p| p.get(commodity)).map(|p| p.price) else {
                return BtStatus::Failure;
            };
            let have = cargo.cargo.get(commodity).copied().unwrap_or(0);
            let amount = if *qty == 0 { have } else { (*qty).min(have) };
            if amount == 0 { return BtStatus::Failure; }
            let owner = controller_by_location.get(&at).map(String::as_str).unwrap_or("");
            let min_unit_price = price * crate::agents::faction_relations::market_buy_multiplier(
                relations, ship_faction, economy.faction_reputation.get(owner).copied().unwrap_or(0), owner);
            request_transaction(economy, commands, entity, ShipTransaction::Sell {
                location: at, commodity: *commodity, quantity: amount, min_unit_price,
            })
        }

        ShipAction::SellAll => {
            // Acknowledge before inspecting cargo: the apply phase may have removed
            // the final stack. Each commodity is a separate atomic exchange.
            if let Some(status) = poll_transaction(economy, |r| matches!(r, ShipTransaction::Sell { .. })) {
                if status != BtStatus::Success { return status; }
                return if cargo.cargo.values().any(|&q| q > 0) { BtStatus::Running } else { BtStatus::Success };
            }
            let Some(at) = position.location_name.clone() else { return BtStatus::Failure };
            let Some(prices) = memory.price_knowledge.get(&at) else { return BtStatus::Failure };
            let next = cargo.cargo.iter().filter(|(_, q)| **q > 0)
                .filter(|(c, _)| prices.contains_key(c))
                .min_by_key(|(c, _)| c.as_str());
            let Some((&commodity, &quantity)) = next else { return BtStatus::Success };
            let owner = controller_by_location.get(&at).map(String::as_str).unwrap_or("");
            let min_unit_price = prices[&commodity].price * crate::agents::faction_relations::market_buy_multiplier(
                relations, ship_faction, economy.faction_reputation.get(owner).copied().unwrap_or(0), owner);
            request_transaction(economy, commands, entity, ShipTransaction::Sell {
                location: at, commodity, quantity, min_unit_price,
            })
        }

        ShipAction::AcceptContract { contract_id } => {
            if let Some(status) = poll_transaction(economy, |r| matches!(r,
                ShipTransaction::Accept { contract_id: id } if id == contract_id)) {
                return status;
            }
            request_transaction(economy, commands, entity, ShipTransaction::Accept {
                contract_id: contract_id.clone(),
            })
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
            if let Some(status) = poll_transaction(economy, |r| matches!(r,
                ShipTransaction::Deliver { contract_id: id } if id == contract_id)) {
                return status;
            }
            request_transaction(economy, commands, entity, ShipTransaction::Deliver {
                contract_id: contract_id.clone(),
            })
        }
    }
}

/// An action cannot advance its BT until the exclusive apply phase replies.
fn poll_transaction(
    economy: &mut ShipEconomy,
    matches: impl FnOnce(&ShipTransaction) -> bool,
) -> Option<BtStatus> {
    let pending = economy.transaction.pending.as_ref()?;
    if !matches(&pending.request) {
        economy.transaction.pending = None;
        return Some(BtStatus::Failure);
    }
    match pending.result {
        None => Some(BtStatus::Running),
        Some(result) => {
            economy.transaction.pending = None;
            Some(if result.is_ok() {
                BtStatus::Success
            } else {
                BtStatus::Failure
            })
        }
    }
}

fn request_transaction(
    economy: &mut ShipEconomy,
    commands: &mut CommandBuffer,
    ship: bevy_ecs::prelude::Entity,
    request: ShipTransaction,
) -> BtStatus {
    let Some(request_id) = economy.transaction.begin(request) else {
        return BtStatus::Failure;
    };
    commands.push(SimCommand::RequestShipTransaction { ship, request_id });
    BtStatus::Running
}

pub(super) fn affordable_quantity(credits: i64, price: f32, capacity: u32) -> u32 {
    if !price.is_finite() || price <= 0.0 || credits <= 0 {
        return 0;
    }
    let by_credits = (credits as f64 / price as f64).floor() as u32;
    by_credits.min(capacity)
}

#[cfg(test)]
mod transaction_tests {
    use super::*;
    use crate::agents::ship::CrewTask;
    use crate::economy::commodities::PriceMemory;

    struct Ship {
        crew: ShipCrew,
        position: ShipPosition,
        transit: ShipTransit,
        cargo: ShipCargo,
        fuel: ShipFuel,
        economy: ShipEconomy,
        memory: ShipMemory,
        commands: CommandBuffer,
    }
    impl Ship {
        fn new() -> Self {
            Self {
                crew: ShipCrew {
                    size: 4,
                    hunger: 0.0,
                    morale: 100.0,
                    fatigue: 0.0,
                    health: 100.0,
                    wages_credits: 0,
                    current_task: CrewTask::Idle,
                    dirty: false,
                },
                position: ShipPosition {
                    location_name: Some("port".into()),
                    docked_at: None,
                    system_id: "sol".into(),
                    universe_offset: (0.0, 0.0),
                    position: (0.0, 0.0),
                },
                transit: ShipTransit { transit: None },
                cargo: ShipCargo {
                    cargo: Default::default(),
                    capacity: 100,
                    cargo_age: Default::default(),
                    cargo_origin: Default::default(),
                },
                fuel: ShipFuel {
                    fuel: 10.0,
                    fuel_capacity: 100.0,
                    fuel_consumption_rate: 0.05,
                    speed_modifier: 1.0,
                },
                economy: ShipEconomy {
                    transaction: Default::default(),
                    credits: 1000,
                    efficiency: 1.0,
                    active_contract_id: Some("contract".into()),
                    faction_reputation: Default::default(),
                    dock_dwell_start_tick: None,
                    rest_start_tick: None,
                    dock_attempt_start_tick: None,
                },
                memory: ShipMemory {
                    price_knowledge: [(
                        "port".into(),
                        [(
                            Commodity::Ore,
                            PriceMemory {
                                price: 10.0,
                                tick: 1,
                            },
                        )]
                        .into(),
                    )]
                    .into(),
                    visited: vec![],
                    recent_systems: Default::default(),
                    route_performance: Default::default(),
                },
                commands: CommandBuffer::new(),
            }
        }
        fn act(&mut self, action: &ShipAction) -> BtStatus {
            execute_ship_action(
                action,
                bevy_ecs::prelude::Entity::PLACEHOLDER,
                "ship",
                "haulers",
                &mut self.crew,
                &mut self.position,
                &mut self.transit,
                &mut self.cargo,
                &mut self.fuel,
                &mut self.economy,
                &mut self.memory,
                &WorldRegistry::default(),
                &Default::default(),
                &Default::default(),
                &mut self.commands,
                1,
                &crate::simulation::config::TickConfig::DEFAULT,
                &mut Blackboard::new(),
            )
        }
    }

    #[test]
    fn economic_actions_wait_for_apply_without_speculative_changes_or_duplicate_commands() {
        for action in [
            ShipAction::Buy {
                commodity: Commodity::Ore,
                qty: 10,
            },
            ShipAction::Refuel,
            ShipAction::DeliverCargo {
                contract_id: "contract".into(),
            },
        ] {
            let mut s = Ship::new();
            assert_eq!(s.act(&action), BtStatus::Running);
            assert_eq!(s.act(&action), BtStatus::Running);
            let commands: Vec<_> = s.commands.drain().collect();
            assert_eq!(commands.len(), 1);
            assert!(matches!(
                commands[0],
                SimCommand::RequestShipTransaction { .. }
            ));
            assert_eq!(s.economy.credits, 1000);
            assert_eq!(s.fuel.fuel, 10.0);
            assert_eq!(s.cargo.used(), 0);
            assert_eq!(s.economy.active_contract_id.as_deref(), Some("contract"));
            assert_eq!(s.crew.current_task, CrewTask::Idle);
            s.economy.transaction.pending.as_mut().unwrap().result = Some(Err("rejected"));
            assert_eq!(s.act(&action), BtStatus::Failure);
            assert!(s.economy.transaction.pending.is_none());
        }
    }

    #[test]
    fn foundation_sell_actions_wait_for_payment_and_acknowledge_empty_hold() {
        for action in [ShipAction::Sell { commodity: Commodity::Ore, qty: 10 }, ShipAction::SellAll] {
            let mut s = Ship::new();
            s.cargo.cargo.insert(Commodity::Ore, 10);
            assert_eq!(s.act(&action), BtStatus::Running);
            assert_eq!(s.economy.credits, 1000);
            assert_eq!(s.cargo.used(), 10);
            assert_eq!(s.act(&action), BtStatus::Running);
            assert_eq!(s.commands.drain().count(), 1);
            // Apply is the only owner of cash/cargo writes.
            s.cargo.cargo.clear();
            s.economy.transaction.pending.as_mut().unwrap().result = Some(Ok(()));
            assert_eq!(s.act(&action), BtStatus::Success);
            assert!(s.economy.transaction.pending.is_none());
        }
    }

    #[test]
    fn escrow_accept_action_waits_before_claiming_a_contract() {
        let mut s = Ship::new();
        s.economy.active_contract_id = None;
        let action = ShipAction::AcceptContract { contract_id: "contract".into() };
        assert_eq!(s.act(&action), BtStatus::Running);
        assert!(s.economy.active_contract_id.is_none());
        assert_eq!(s.act(&action), BtStatus::Running);
        assert_eq!(s.commands.drain().count(), 1);
        s.economy.transaction.pending.as_mut().unwrap().result = Some(Err("insufficient_contract_funding"));
        assert_eq!(s.act(&action), BtStatus::Failure);
        assert!(s.economy.active_contract_id.is_none());
    }

    #[test]
    fn acknowledged_purchase_advances_without_rebuying_even_if_credits_are_now_zero() {
        let mut s = Ship::new();
        let action = ShipAction::Buy {
            commodity: Commodity::Ore,
            qty: 10,
        };
        assert_eq!(s.act(&action), BtStatus::Running);
        s.economy.credits = 0;
        s.economy.transaction.pending.as_mut().unwrap().result = Some(Ok(()));
        assert_eq!(s.act(&action), BtStatus::Success);
        assert_eq!(s.commands.drain().count(), 1);
        assert!(s.economy.transaction.pending.is_none());
    }

    #[test]
    fn refuel_waits_per_chunk_then_finishes_on_confirmed_full_tank() {
        let mut s = Ship::new();
        assert_eq!(s.act(&ShipAction::Refuel), BtStatus::Running);
        let first = s.economy.transaction.pending.as_ref().unwrap().id;
        s.fuel.fuel = 20.0;
        s.economy.transaction.pending.as_mut().unwrap().result = Some(Ok(()));
        assert_eq!(s.act(&ShipAction::Refuel), BtStatus::Running);
        assert!(s.economy.transaction.pending.as_ref().unwrap().id > first);
        s.fuel.fuel = 100.0;
        s.economy.transaction.pending.as_mut().unwrap().result = Some(Ok(()));
        assert_eq!(s.act(&ShipAction::Refuel), BtStatus::Success);
        assert_eq!(s.commands.drain().count(), 2);
    }
}
