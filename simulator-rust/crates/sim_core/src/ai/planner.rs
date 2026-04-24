//! Forward-search action planner (GOAP-lite, MVP).
//!
//! Takes a `WorldState` and a goal predicate, searches through a set of
//! `Operator`s with preconditions + effects, and returns a plan —
//! `Vec<ShipAction>` — that reaches the goal. The caller can wrap the
//! returned sequence in `BtNode::sequence` to hand to the existing BT
//! executor.
//!
//! ## Why this exists
//!
//! The hand-authored BT builders (`build_fulfill_delivery_bt`,
//! `build_trade_run_bt`, etc.) are static: each goal gets one
//! pre-baked sequence of actions. They can't express *combined*
//! goals like "deliver this contract AND end with fuel safety margin
//! AND pick up a retrofit at the shipyard you pass through" because
//! the combination wasn't anticipated at write-time.
//!
//! A forward planner generates a sequence from a goal predicate and
//! an operator catalog, so the combined case falls out naturally —
//! whichever action chain reaches the predicate first wins.
//!
//! ## Scope (MVP)
//!
//! - Abstract state, not the real world. `WorldState` tracks only
//!   the handful of facts that matter for delivery-class plans:
//!   current location (as a symbolic `Loc`), docked flag, fuel
//!   bucket, contract cargo state, contract delivered flag.
//! - Deterministic BFS with a depth cap. No A*, no heuristics.
//!   For the small state space (few hundred reachable states) BFS
//!   finds shortest plans in microseconds.
//! - No integration with `plan_goal` yet — the module's value in
//!   this bundle is the framework + tests proving combined plans
//!   synthesise correctly. A follow-up bundle wires it into the
//!   planner path for a specific combined-goal case.
//!
//! ## Not in scope
//!
//! - Multi-system gate routes (current operator set assumes
//!   reachable locations are directly travelable; real routing
//!   still goes through `route_actions`).
//! - Learning / caching plans across ticks (each call plans fresh).
//! - Heuristic-guided search.
//!
//! ## Known limitations (document before you act on weird behaviour)
//!
//! - **Planner starts from full fuel.** The callers in ship/mod.rs
//!   pass `WorldState::new(Loc::Origin, 10)` regardless of the
//!   ship's actual fuel. This means the planner produces
//!   *structurally correct* plans — the shape is right — but it
//!   can't reason about fuel-aware optimizations like "skip the
//!   refuel step because we're flush." The real ship still
//!   handles fuel constraints at execution time via the
//!   Travel/Refuel executors. When we want combined-plan
//!   decisions to depend on real fuel (e.g. "this retrofit detour
//!   is only worth it if we're already full"), feed the ship's
//!   actual `fuel.fraction()` bucket in as the initial state.
//! - **Cost estimation is coarse.** `estimate_fuel_bucket_cost` in
//!   ship/mod.rs rounds distance to buckets at ~50 units per
//!   bucket. Routes right at the boundary (distance 49 vs 51)
//!   flip into a longer-plan bucket, which can cause a refuel
//!   insertion that wouldn't happen in reality. Not worth fixing
//!   until we see routing that the perf HUD flags as anomalous.
//! - **No cost-weighted search.** BFS picks shortest-by-steps
//!   plans, not cheapest-by-fuel plans. For now delivery plans
//!   are short enough that this rarely matters, but a combined
//!   goal with three detours might pick the wrong one.

use crate::agents::ship::ShipAction;
use crate::economy::commodities::Commodity;
use std::collections::{HashSet, VecDeque};

/// Symbolic locations relevant to a single plan. Four variants
/// cover delivery, trade-run, and retrofit-on-route combined goals.
/// Keep the enum tiny — a small state space keeps BFS cheap and
/// dedup effective. New location roles should earn their place
/// with a concrete combined goal that needs them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Loc {
    /// Where the ship is when planning starts.
    Origin,
    /// Where the contract's cargo is bought / picked up.
    /// For trade-run plans this is the `buy_loc`.
    Source,
    /// Where the contract's cargo is delivered / the trade-run
    /// sells its cargo.
    Dest,
    /// Shipyard a retrofit-on-route plan visits. `LocMap.shipyard`
    /// resolves this to a real location only when the caller is
    /// asking for a combined retrofit goal.
    Shipyard,
}

/// Abstract state for the planner. Fields are deliberately coarse:
/// `fuel_bucket` as 0..=10 keeps the state space finite so BFS
/// terminates quickly and dedup is effective. Names resolve to real
/// `String`s via the `LocMap` the caller provides at plan time.
///
/// State-space size is
/// `locs(4) × docked(2) × fuel(11) × cargo(2) × delivered(2) × sold(2) × retrofitted(2) ≈ 1400`
/// — well within BFS comfort. If a future combined goal needs a new
/// field, add it here and grow the goal predicates accordingly.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct WorldState {
    pub at: Loc,
    pub docked: bool,
    /// Fuel in 10ths: 0 = empty, 10 = full. Conversions happen at
    /// the plan boundary.
    pub fuel_bucket: u8,
    /// Currently carrying cargo (either contract cargo or a
    /// trade-run's speculative buy).
    pub cargo_loaded: bool,
    /// A contract cargo has been delivered to its destination.
    /// Set by `DeliverCargo`. Distinct from `sold` because the
    /// economic effect + payment channel differs in the engine
    /// apply phase.
    pub delivered: bool,
    /// A trade-run cargo has been sold at its destination.
    /// Set by `SellAll`.
    pub sold: bool,
    /// A retrofit operation has completed at a shipyard. Set by
    /// `Refit`. Used by combined delivery-with-retrofit goals.
    pub retrofitted: bool,
    /// Crew has rested to full morale. Set by `Rest`. Used by
    /// crew-mission plans (goal: `delivered && rested`) and
    /// rest-crew plans (goal: `rested && !docked`).
    pub rested: bool,
}

impl WorldState {
    pub fn new(at: Loc, fuel_bucket: u8) -> Self {
        Self {
            at,
            docked: false,
            fuel_bucket: fuel_bucket.min(10),
            cargo_loaded: false,
            delivered: false,
            sold: false,
            retrofitted: false,
            rested: false,
        }
    }
}

/// Convert a ship's fuel fraction (0.0..=1.0) to a planner bucket
/// (0..=10). Rounds to nearest — a ship at 0.55 fuel becomes
/// bucket 6, giving the planner enough granularity to distinguish
/// "flush" from "low" without blowing up the state space. Fuel at
/// or below zero maps to bucket 0 so unreachable states stay
/// unreachable.
pub fn fuel_fraction_to_bucket(fraction: f32) -> u8 {
    if fraction <= 0.0 {
        return 0;
    }
    let bucket = (fraction * 10.0).round().clamp(0.0, 10.0);
    bucket as u8
}

/// The real-world identifiers a `Loc` resolves to. Caller fills
/// this from the ship's current position + the chosen contract
/// (and optional retrofit plan) before calling `plan`. The planner
/// itself is string-free so repeated plans don't churn allocations.
///
/// `contract_id` may be empty for trade-run plans. `shipyard`
/// fields may be `None` for plans that don't need a retrofit leg;
/// when `None`, the `Refit` operator fails its preconditions and
/// the planner never tries it.
#[derive(Debug, Clone)]
pub struct LocMap {
    pub origin: String,
    pub source: String,
    pub dest: String,
    /// Commodity the contract or trade-run buys. Wrapped into the
    /// synthesised `Buy { commodity, qty }` action.
    pub commodity: Commodity,
    pub quantity: u32,
    /// Empty for trade-run plans (no contract). Non-empty for
    /// delivery plans — compiled into the `AcceptContract` +
    /// `DeliverCargo` actions.
    pub contract_id: String,
    /// Symmetric travel costs between core locations. Buckets, not
    /// raw fuel units — the planner only cares about state
    /// transitions. Both directions explicit so asymmetric gate
    /// fees can be modelled later.
    pub cost_origin_to_source: u8,
    pub cost_source_to_dest: u8,
    pub cost_origin_to_dest: u8,

    /// Optional retrofit leg. Caller supplies all four fields
    /// together (or none). When `shipyard` is `None` the Refit
    /// operator is effectively disabled for this plan.
    pub shipyard: Option<String>,
    pub refit_slot: Option<crate::modules::Slot>,
    pub refit_slug: Option<&'static str>,
    pub cost_origin_to_shipyard: u8,
    pub cost_source_to_shipyard: u8,
    pub cost_shipyard_to_dest: u8,
}

impl LocMap {
    /// Delivery-plan constructor with no shipyard. Use this for a
    /// straight fulfill-delivery BT.
    #[allow(clippy::too_many_arguments)]
    pub fn delivery(
        origin: String,
        source: String,
        dest: String,
        commodity: Commodity,
        quantity: u32,
        contract_id: String,
        cost_origin_to_source: u8,
        cost_source_to_dest: u8,
        cost_origin_to_dest: u8,
    ) -> Self {
        Self {
            origin,
            source,
            dest,
            commodity,
            quantity,
            contract_id,
            cost_origin_to_source,
            cost_source_to_dest,
            cost_origin_to_dest,
            shipyard: None,
            refit_slot: None,
            refit_slug: None,
            cost_origin_to_shipyard: 0,
            cost_source_to_shipyard: 0,
            cost_shipyard_to_dest: 0,
        }
    }

    /// Trade-run constructor. `source` = buy location, `dest` =
    /// sell location. `contract_id` is empty because trade-runs
    /// don't post/accept contracts.
    #[allow(clippy::too_many_arguments)]
    pub fn trade_run(
        origin: String,
        buy_loc: String,
        sell_loc: String,
        commodity: Commodity,
        quantity: u32,
        cost_origin_to_buy: u8,
        cost_buy_to_sell: u8,
        cost_origin_to_sell: u8,
    ) -> Self {
        Self::delivery(
            origin,
            buy_loc,
            sell_loc,
            commodity,
            quantity,
            String::new(),
            cost_origin_to_buy,
            cost_buy_to_sell,
            cost_origin_to_sell,
        )
    }

    fn resolve(&self, loc: Loc) -> Option<&str> {
        match loc {
            Loc::Origin => Some(&self.origin),
            Loc::Source => Some(&self.source),
            Loc::Dest => Some(&self.dest),
            Loc::Shipyard => self.shipyard.as_deref(),
        }
    }

    fn travel_cost(&self, from: Loc, to: Loc) -> u8 {
        match (from, to) {
            (Loc::Origin, Loc::Source) | (Loc::Source, Loc::Origin) => self.cost_origin_to_source,
            (Loc::Source, Loc::Dest) | (Loc::Dest, Loc::Source) => self.cost_source_to_dest,
            (Loc::Origin, Loc::Dest) | (Loc::Dest, Loc::Origin) => self.cost_origin_to_dest,
            (Loc::Origin, Loc::Shipyard) | (Loc::Shipyard, Loc::Origin) => {
                self.cost_origin_to_shipyard
            }
            (Loc::Source, Loc::Shipyard) | (Loc::Shipyard, Loc::Source) => {
                self.cost_source_to_shipyard
            }
            (Loc::Dest, Loc::Shipyard) | (Loc::Shipyard, Loc::Dest) => self.cost_shipyard_to_dest,
            _ => 0,
        }
    }
}

/// An abstract operator. Produces the (next_state, action) pair when
/// its preconditions hold, or `None` otherwise. Operators are cheap
/// data — no allocation per try — so the BFS can fan out wide.
///
/// Keeping them as explicit enum variants (rather than a trait
/// object with function pointers) lets us serialise / replay plans
/// deterministically, which matters for testing.
#[derive(Debug, Clone, Copy)]
pub enum Operator {
    Travel { to: Loc },
    Dock,
    Undock,
    Refuel,
    Buy,
    SellAll,
    DeliverCargo,
    Refit,
    /// Passenger / courier delivery. Same apply-phase semantics as
    /// `DeliverCargo` in the engine (both emit `ShipAction::DeliverCargo`)
    /// but the precondition doesn't require `cargo_loaded` — passenger
    /// contracts don't occupy hold space. Effect: `delivered = true`.
    DeliverPassengers,
    /// Shore leave / crew-mission dwell. The real `ShipAction::Rest`
    /// returns Running until morale ≥ CREW_REST_TARGET; for the
    /// planner it's an instantaneous state transition. Pre: docked;
    /// eff: `rested = true`. Used by crew_mission + rest_crew
    /// catalogs.
    Rest,
}

impl Operator {
    /// Operator catalog for delivery-class plans (contract pickup
    /// and delivery). Order is canonical — BFS is deterministic
    /// given insertion order, so this drives tie-breaks between
    /// same-length plans. Refit is included so a delivery plan
    /// can fold in a retrofit when the LocMap supplies a shipyard.
    pub fn delivery_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Buy,
            Operator::DeliverCargo,
            Operator::Refit,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Source },
            Operator::Travel { to: Loc::Dest },
            Operator::Travel { to: Loc::Shipyard },
        ]
    }

    /// Operator catalog for trade-run plans. Same shape as
    /// delivery, but uses `SellAll` instead of `DeliverCargo` at
    /// the destination (no contract payment, just market sell).
    pub fn trade_run_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Buy,
            Operator::SellAll,
            Operator::Refit,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Source },
            Operator::Travel { to: Loc::Dest },
            Operator::Travel { to: Loc::Shipyard },
        ]
    }

    /// Operator catalog for passenger / courier plans. No cargo
    /// mechanics — the contract's payment fires on
    /// `DeliverPassengers` when the ship docks at the destination.
    /// Refuel is still available so the planner can fold one in
    /// at source or dest if fuel is marginal.
    pub fn passenger_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::DeliverPassengers,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Source },
            Operator::Travel { to: Loc::Dest },
        ]
    }

    /// Operator catalog for standalone retrofit plans (the
    /// `seek_retrofit` goal). Ship travels to a shipyard, docks,
    /// refits, undocks. Goal = `retrofitted && fuel_bucket >= 2`.
    /// Uses the Shipyard location edges rather than Source/Dest,
    /// so LocMap callers point `shipyard` at the target yard and
    /// leave Source/Dest set to sensible no-ops.
    pub fn retrofit_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Refit,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Shipyard },
        ]
    }

    /// Operator catalog for crew-mission plans. Ship travels to
    /// the mission station (encoded in the LocMap as `Dest`,
    /// source is a placeholder), docks, refuels, rests, delivers
    /// payout, undocks. Goal = `delivered && rested && fuel_bucket >= 2`.
    pub fn crew_mission_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Rest,
            Operator::DeliverPassengers,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Dest },
        ]
    }

    /// Operator catalog for rest-crew (shore-leave) plans. Ship
    /// travels to a chosen rest target (encoded as `Dest`), docks,
    /// refuels, rests, undocks. Goal =
    /// `rested && !docked && at == Dest && fuel_bucket >= 2`.
    pub fn rest_crew_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Rest,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Dest },
        ]
    }

    /// Apply this operator to `state` if its preconditions hold.
    /// Returns `Some((next_state, action))` on success, `None` when
    /// the operator doesn't apply to this state.
    pub fn apply(&self, state: &WorldState, map: &LocMap) -> Option<(WorldState, ShipAction)> {
        match self {
            Operator::Travel { to } => {
                if state.docked {
                    return None;
                }
                if state.at == *to {
                    return None;
                }
                // Shipyard travel requires the caller to have
                // provided a shipyard location. No shipyard in map
                // → this travel edge is unreachable.
                let dest_name = map.resolve(*to)?;
                let cost = map.travel_cost(state.at, *to);
                if cost == 0 {
                    return None; // unreachable edge
                }
                if state.fuel_bucket < cost {
                    return None; // not enough fuel
                }
                let mut next = state.clone();
                next.at = *to;
                next.fuel_bucket -= cost;
                let action = ShipAction::Travel {
                    destination: dest_name.to_string(),
                };
                Some((next, action))
            }
            Operator::Dock => {
                if state.docked {
                    return None;
                }
                let mut next = state.clone();
                next.docked = true;
                // Use DockAtShipyard when at the shipyard so the
                // existing compile step emits the right action
                // kind (the apply phase treats them identically
                // today, but the distinction lets future
                // shipyard-specific dock logic branch cleanly).
                let action = if state.at == Loc::Shipyard {
                    ShipAction::DockAtShipyard
                } else {
                    ShipAction::Dock
                };
                Some((next, action))
            }
            Operator::Undock => {
                if !state.docked {
                    return None;
                }
                let mut next = state.clone();
                next.docked = false;
                Some((next, ShipAction::Undock))
            }
            Operator::Refuel => {
                if !state.docked {
                    return None;
                }
                if state.fuel_bucket >= 10 {
                    return None; // already full — don't chain useless refuels
                }
                let mut next = state.clone();
                next.fuel_bucket = 10;
                Some((next, ShipAction::Refuel))
            }
            Operator::Buy => {
                if !state.docked || state.at != Loc::Source {
                    return None;
                }
                if state.cargo_loaded {
                    return None;
                }
                let mut next = state.clone();
                next.cargo_loaded = true;
                let action = ShipAction::Buy {
                    commodity: map.commodity,
                    qty: map.quantity,
                };
                Some((next, action))
            }
            Operator::SellAll => {
                if !state.docked || state.at != Loc::Dest {
                    return None;
                }
                if !state.cargo_loaded {
                    return None;
                }
                let mut next = state.clone();
                next.cargo_loaded = false;
                next.sold = true;
                Some((next, ShipAction::SellAll))
            }
            Operator::DeliverCargo => {
                if !state.docked || state.at != Loc::Dest {
                    return None;
                }
                if !state.cargo_loaded {
                    return None;
                }
                // Contract-id empty → this isn't a delivery plan;
                // fall through so the planner picks SellAll instead.
                if map.contract_id.is_empty() {
                    return None;
                }
                let mut next = state.clone();
                next.cargo_loaded = false;
                next.delivered = true;
                let action = ShipAction::DeliverCargo {
                    contract_id: map.contract_id.clone(),
                };
                Some((next, action))
            }
            Operator::Rest => {
                if !state.docked {
                    return None;
                }
                if state.rested {
                    return None; // don't chain redundant Rest steps
                }
                let mut next = state.clone();
                next.rested = true;
                Some((next, ShipAction::Rest))
            }
            Operator::DeliverPassengers => {
                if !state.docked || state.at != Loc::Dest {
                    return None;
                }
                if state.delivered {
                    return None;
                }
                if map.contract_id.is_empty() {
                    return None; // no passenger contract to deliver
                }
                let mut next = state.clone();
                next.delivered = true;
                let action = ShipAction::DeliverCargo {
                    contract_id: map.contract_id.clone(),
                };
                Some((next, action))
            }
            Operator::Refit => {
                if !state.docked || state.at != Loc::Shipyard {
                    return None;
                }
                if state.retrofitted {
                    return None; // don't chain multiple refits in one plan
                }
                let (Some(slot), Some(slug)) = (map.refit_slot, map.refit_slug) else {
                    return None;
                };
                let mut next = state.clone();
                next.retrofitted = true;
                Some((next, ShipAction::Refit { slot, slug }))
            }
        }
    }
}

/// The planner's output: a successful plan.
#[derive(Debug, Clone)]
pub struct Plan {
    pub actions: Vec<ShipAction>,
    pub final_state: WorldState,
}

/// BFS forward search. Expands states breadth-first, first hit
/// wins (so plans are minimum-length). `max_depth` bounds the
/// search — for delivery-class plans we expect ~8 actions so a cap
/// around 12–16 is generous. Dedup by state keeps the frontier
/// small (few hundred unique states in practice).
///
/// `goal` is any predicate; the caller supplies it. For a
/// delivery-with-fuel-safety plan, pass something like
/// `|s| s.delivered && s.fuel_bucket >= 3`.
pub fn plan<F>(
    initial: WorldState,
    goal: F,
    operators: &[Operator],
    map: &LocMap,
    max_depth: usize,
) -> Option<Plan>
where
    F: Fn(&WorldState) -> bool,
{
    if goal(&initial) {
        return Some(Plan {
            actions: Vec::new(),
            final_state: initial,
        });
    }

    // Frontier holds (state, plan-so-far). Plan grows by push on
    // each expansion; we clone the Vec per child, which is fine at
    // this scale (max ~16 actions × few hundred states).
    let mut frontier: VecDeque<(WorldState, Vec<ShipAction>)> = VecDeque::new();
    let mut seen: HashSet<WorldState> = HashSet::new();
    frontier.push_back((initial.clone(), Vec::new()));
    seen.insert(initial);

    while let Some((state, path)) = frontier.pop_front() {
        if path.len() >= max_depth {
            continue;
        }
        for op in operators {
            let Some((next_state, action)) = op.apply(&state, map) else {
                continue;
            };
            if seen.contains(&next_state) {
                continue;
            }
            let mut next_path = path.clone();
            next_path.push(action);
            if goal(&next_state) {
                return Some(Plan {
                    actions: next_path,
                    final_state: next_state,
                });
            }
            seen.insert(next_state.clone());
            frontier.push_back((next_state, next_path));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn basic_map() -> LocMap {
        LocMap::delivery(
            "earth-station".into(),
            "belt-yard".into(),
            "mars-station".into(),
            Commodity::Ore,
            50,
            "contract-42".into(),
            2,
            3,
            4,
        )
    }

    fn trade_map() -> LocMap {
        LocMap::trade_run(
            "earth-station".into(),
            "belt-yard".into(),
            "mars-station".into(),
            Commodity::Ore,
            50,
            2,
            3,
            4,
        )
    }

    fn retrofit_map(shipyard_cost: (u8, u8, u8)) -> LocMap {
        use crate::modules::Slot;
        let mut m = basic_map();
        m.shipyard = Some("luna-yard".into());
        m.refit_slot = Some(Slot::Engine);
        m.refit_slug = Some("engine_t2");
        m.cost_origin_to_shipyard = shipyard_cost.0;
        m.cost_source_to_shipyard = shipyard_cost.1;
        m.cost_shipyard_to_dest = shipyard_cost.2;
        m
    }

    #[test]
    fn plans_trivial_delivery_from_full_fuel() {
        // Full tank: plan should be something like
        // Travel(Source) → Dock → Buy → Undock →
        // Travel(Dest) → Dock → DeliverCargo.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .expect("should find a plan");
        assert!(plan.final_state.delivered);
        // Minimum 7 actions for this route: Travel, Dock, Buy,
        // Undock, Travel, Dock, DeliverCargo.
        assert!(
            plan.actions.len() >= 7 && plan.actions.len() <= 10,
            "expected 7-10 actions, got {}: {:?}",
            plan.actions.len(),
            plan.actions,
        );
    }

    #[test]
    fn plan_inserts_refuel_when_fuel_is_low_and_goal_requires_safety() {
        // Start with just enough fuel to reach Source (cost 2) but
        // not enough to reach Dest from Source (cost 3). Without
        // a mid-route refuel, no plan can deliver.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 3);
        let plan = plan(
            initial,
            |s| s.delivered && s.fuel_bucket >= 2,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .expect("refuel-enabled plan should exist");
        assert!(plan.final_state.delivered);
        assert!(plan.final_state.fuel_bucket >= 2);
        // The synthesised plan must include at least one Refuel —
        // raw fuel (3) < origin→source (2) + source→dest (3) = 5.
        let refuels = plan
            .actions
            .iter()
            .filter(|a| matches!(a, ShipAction::Refuel))
            .count();
        assert!(
            refuels >= 1,
            "plan must include a Refuel step: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn plan_returns_none_when_goal_unreachable() {
        // Not enough fuel to reach source, and no Refuel available
        // at origin-type locations in this minimal model... actually
        // we CAN Dock+Refuel at Origin. Test a truly unreachable
        // setup instead: a map where every edge has cost > 10 so
        // the ship can't afford even one jump from a full tank.
        let mut map = basic_map();
        map.cost_origin_to_source = 12;
        map.cost_source_to_dest = 12;
        map.cost_origin_to_dest = 12;
        let initial = WorldState::new(Loc::Origin, 10);
        let result = plan(
            initial,
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            16,
        );
        assert!(result.is_none(), "impossible route should return None");
    }

    #[test]
    fn plan_is_empty_when_goal_already_holds() {
        let map = basic_map();
        let mut initial = WorldState::new(Loc::Dest, 10);
        initial.delivered = true;
        let plan = plan(
            initial,
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .expect("already-satisfied goal returns empty plan");
        assert!(plan.actions.is_empty());
    }

    #[test]
    fn plans_passenger_delivery_without_buy() {
        // Passenger/courier plans have no Buy step — the contract
        // payment fires on DeliverPassengers at the destination
        // regardless of cargo state. Plan shape: Travel → Dock →
        // Undock → Travel → Dock → DeliverPassengers.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.delivered,
            Operator::passenger_catalog(),
            &map,
            16,
        )
        .expect("passenger plan should exist");
        assert!(plan.final_state.delivered);
        // Must include DeliverCargo (our DeliverPassengers op emits
        // that action) but NOT Buy or SellAll.
        assert!(
            plan.actions.iter().any(|a| matches!(a, ShipAction::DeliverCargo { .. })),
            "passenger plan must include DeliverCargo: {:?}",
            plan.actions,
        );
        assert!(
            !plan.actions.iter().any(|a| matches!(a, ShipAction::Buy { .. })),
            "passenger plan must not Buy: {:?}",
            plan.actions,
        );
        assert!(
            !plan.actions.iter().any(|a| matches!(a, ShipAction::SellAll)),
            "passenger plan must not SellAll: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn passenger_plan_is_shorter_than_delivery_plan() {
        // Delivery requires Buy at source; passenger doesn't.
        // Plans should reflect that — passenger is typically
        // 1-2 actions shorter.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let delivery_plan = plan(
            initial.clone(),
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .unwrap();
        let passenger_plan = plan(
            initial,
            |s| s.delivered,
            Operator::passenger_catalog(),
            &map,
            16,
        )
        .unwrap();
        assert!(
            passenger_plan.actions.len() < delivery_plan.actions.len(),
            "passenger should be shorter than delivery: pax={} deliv={}",
            passenger_plan.actions.len(),
            delivery_plan.actions.len(),
        );
    }

    #[test]
    fn fuel_aware_delivery_skips_refuel_when_flush() {
        // Full tank — no refuel needed. Plan should contain zero
        // Refuel actions.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.delivered && s.fuel_bucket >= 2,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .unwrap();
        let refuels = plan
            .actions
            .iter()
            .filter(|a| matches!(a, ShipAction::Refuel))
            .count();
        assert_eq!(
            refuels, 0,
            "flush-tank plan must not Refuel: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn fuel_aware_delivery_forces_refuel_when_thirsty() {
        // Start at fuel bucket 4 — enough for origin→source (2)
        // but not for source→dest (3). Plan must insert a Refuel.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 4);
        let plan = plan(
            initial,
            |s| s.delivered && s.fuel_bucket >= 2,
            Operator::delivery_catalog(),
            &map,
            20,
        )
        .expect("thirsty-tank plan must still find a solution");
        let refuels = plan
            .actions
            .iter()
            .filter(|a| matches!(a, ShipAction::Refuel))
            .count();
        assert!(
            refuels >= 1,
            "thirsty-tank plan must include a Refuel: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn plans_trade_run_ends_in_sold_state() {
        let map = trade_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.sold,
            Operator::trade_run_catalog(),
            &map,
            16,
        )
        .expect("trade-run plan should exist");
        assert!(plan.final_state.sold);
        // Plan must contain a SellAll.
        assert!(
            plan.actions.iter().any(|a| matches!(a, ShipAction::SellAll)),
            "trade-run plan must include SellAll: {:?}",
            plan.actions,
        );
        // Plan must NOT contain DeliverCargo (trade-run has no
        // contract; DeliverCargo's precondition short-circuits on
        // empty contract_id).
        assert!(
            !plan.actions.iter().any(|a| matches!(a, ShipAction::DeliverCargo { .. })),
            "trade-run plan must not include DeliverCargo: {:?}",
            plan.actions,
        );
    }

    fn mission_map() -> LocMap {
        // Crew mission: station is the Dest (Source is an
        // irrelevant placeholder).
        LocMap::delivery(
            "earth-station".into(),
            "earth-station".into(), // Source (unused for mission)
            "mars-station".into(),
            Commodity::Food,
            0,
            "mission-contract-7".into(),
            0,
            0,
            3,
        )
    }

    #[test]
    fn plans_crew_mission_requires_rest_before_deliver() {
        // Crew mission plan goal: delivered && rested. Planner
        // must produce Rest before DeliverPassengers.
        let map = mission_map();
        let initial = WorldState::new(Loc::Origin, 10);
        let p = plan(
            initial,
            |s| s.delivered && s.rested,
            Operator::crew_mission_catalog(),
            &map,
            16,
        )
        .expect("crew mission plan should exist");
        assert!(p.final_state.delivered);
        assert!(p.final_state.rested);
        // Check ordering: Rest must appear before DeliverCargo in
        // the synthesised sequence.
        let rest_idx = p.actions.iter().position(|a| matches!(a, ShipAction::Rest));
        let deliver_idx = p
            .actions
            .iter()
            .position(|a| matches!(a, ShipAction::DeliverCargo { .. }));
        assert!(rest_idx.is_some(), "plan must include Rest: {:?}", p.actions);
        assert!(deliver_idx.is_some(), "plan must include DeliverCargo: {:?}", p.actions);
        assert!(
            rest_idx.unwrap() < deliver_idx.unwrap(),
            "Rest must precede DeliverCargo: {:?}",
            p.actions,
        );
    }

    #[test]
    fn plans_rest_crew_ends_undocked_at_target() {
        // rest_crew goal: rested && not docked && at Dest.
        let mut map = mission_map();
        map.cost_origin_to_dest = 2;
        let initial = WorldState::new(Loc::Origin, 10);
        let p = plan(
            initial,
            |s| s.rested && !s.docked && s.at == Loc::Dest,
            Operator::rest_crew_catalog(),
            &map,
            16,
        )
        .expect("rest_crew plan should exist");
        assert!(p.final_state.rested);
        assert!(!p.final_state.docked);
        assert_eq!(p.final_state.at, Loc::Dest);
    }

    #[test]
    fn standalone_retrofit_plan_travels_to_shipyard_and_refits() {
        // Use retrofit_map with a reachable shipyard. Goal is just
        // `retrofitted`, using the retrofit_catalog (no Buy /
        // SellAll / DeliverCargo available).
        let map = retrofit_map((2, 0, 0));
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.retrofitted,
            Operator::retrofit_catalog(),
            &map,
            16,
        )
        .expect("standalone retrofit plan should exist");
        assert!(plan.final_state.retrofitted);
        assert!(
            plan.actions
                .iter()
                .any(|a| matches!(a, ShipAction::Refit { .. })),
            "retrofit plan must include Refit: {:?}",
            plan.actions,
        );
        assert!(
            !plan.actions.iter().any(|a| matches!(a, ShipAction::Buy { .. })),
            "retrofit-only plan must not Buy: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn retrofit_on_route_produces_combined_plan_when_shipyard_cheap() {
        // Shipyard costs: cheap from origin (1) and cheap to dest
        // (2). The planner should fold refit into the delivery
        // because the combined detour is ~parity with separate
        // plans.
        let map = retrofit_map((1, 5, 2));
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.delivered && s.retrofitted,
            Operator::delivery_catalog(),
            &map,
            24,
        )
        .expect("combined delivery+retrofit plan should exist");
        assert!(plan.final_state.delivered);
        assert!(plan.final_state.retrofitted);
        // Plan must include both Refit and DeliverCargo.
        let has_refit = plan
            .actions
            .iter()
            .any(|a| matches!(a, ShipAction::Refit { .. }));
        let has_deliver = plan
            .actions
            .iter()
            .any(|a| matches!(a, ShipAction::DeliverCargo { .. }));
        assert!(has_refit, "combined plan needs Refit: {:?}", plan.actions);
        assert!(
            has_deliver,
            "combined plan needs DeliverCargo: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn retrofit_refused_when_shipyard_detour_unreachable() {
        // All shipyard edges cost 20 — more than a full tank. The
        // planner can't reach the yard, so a combined plan can't
        // exist. Must return None rather than hanging or emitting
        // a bogus plan.
        let map = retrofit_map((20, 20, 20));
        let initial = WorldState::new(Loc::Origin, 10);
        let result = plan(
            initial,
            |s| s.delivered && s.retrofitted,
            Operator::delivery_catalog(),
            &map,
            24,
        );
        assert!(
            result.is_none(),
            "unreachable shipyard should return None, got {:?}",
            result,
        );
    }

    #[test]
    fn delivery_plan_ignores_shipyard_when_goal_doesnt_need_it() {
        // Even with a cheap shipyard in the map, a plain delivery
        // goal (no retrofitted term in the predicate) should stay
        // minimal — no free detours.
        let map = retrofit_map((1, 1, 1));
        let initial = WorldState::new(Loc::Origin, 10);
        let plan = plan(
            initial,
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            24,
        )
        .expect("plan exists");
        // Plan should not include Refit — goal didn't ask for it.
        assert!(
            !plan.actions.iter().any(|a| matches!(a, ShipAction::Refit { .. })),
            "pure delivery plan must not refit: {:?}",
            plan.actions,
        );
    }

    #[test]
    fn plan_does_not_chain_redundant_refuels() {
        // If we're already at full fuel, Refuel's precondition
        // rejects it. The planner should never emit two Refuels
        // in a row for the same Dock stop.
        let map = basic_map();
        let initial = WorldState::new(Loc::Origin, 5);
        let plan = plan(
            initial,
            |s| s.delivered,
            Operator::delivery_catalog(),
            &map,
            16,
        )
        .expect("plan should exist");
        for pair in plan.actions.windows(2) {
            if matches!(pair[0], ShipAction::Refuel)
                && matches!(pair[1], ShipAction::Refuel)
            {
                panic!("found back-to-back Refuel in plan: {:?}", plan.actions);
            }
        }
    }
}
