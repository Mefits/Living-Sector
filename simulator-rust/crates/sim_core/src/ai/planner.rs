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

use crate::agents::ship::ShipAction;
use crate::economy::commodities::Commodity;
use std::collections::{HashSet, VecDeque};

/// Symbolic locations relevant to a single plan. Only three matter
/// for the MVP's delivery-class plans, so we keep the enum tiny —
/// a small state space keeps BFS cheap and dedup effective.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Loc {
    /// Where the ship is when planning starts.
    Origin,
    /// Where the contract's cargo is bought / picked up.
    Source,
    /// Where the contract's cargo is delivered.
    Dest,
}

/// Abstract state for the planner. Fields are deliberately coarse:
/// `fuel_bucket` as 0..=10 keeps the state space finite so BFS
/// terminates quickly and dedup is effective. Names resolve to real
/// `String`s via the `LocMap` the caller provides at plan time.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct WorldState {
    pub at: Loc,
    pub docked: bool,
    /// Fuel in 10ths: 0 = empty, 10 = full. Conversions happen at
    /// the plan boundary.
    pub fuel_bucket: u8,
    /// Currently carrying the contract commodity.
    pub cargo_loaded: bool,
    /// Contract has been delivered.
    pub delivered: bool,
}

impl WorldState {
    pub fn new(at: Loc, fuel_bucket: u8) -> Self {
        Self {
            at,
            docked: false,
            fuel_bucket: fuel_bucket.min(10),
            cargo_loaded: false,
            delivered: false,
        }
    }
}

/// The real-world identifiers a `Loc` resolves to. Caller fills this
/// from the ship's current position + the chosen contract before
/// calling `plan`. The planner itself is string-free so repeated
/// plans don't churn allocations.
#[derive(Debug, Clone)]
pub struct LocMap {
    pub origin: String,
    pub source: String,
    pub dest: String,
    /// Commodity the contract buys + delivers. Wrapped into the
    /// synthesised `Buy { commodity, qty }` / `DeliverCargo` actions.
    pub commodity: Commodity,
    pub quantity: u32,
    pub contract_id: String,
    /// Fuel-bucket cost of each directed edge. Buckets, not raw
    /// fuel units — the planner only cares about state transitions.
    /// Symmetric in practice; keep both directions explicit so
    /// asymmetric gate fees can be modelled later.
    pub cost_origin_to_source: u8,
    pub cost_source_to_dest: u8,
    pub cost_origin_to_dest: u8,
}

impl LocMap {
    fn resolve(&self, loc: Loc) -> &str {
        match loc {
            Loc::Origin => &self.origin,
            Loc::Source => &self.source,
            Loc::Dest => &self.dest,
        }
    }

    fn travel_cost(&self, from: Loc, to: Loc) -> u8 {
        match (from, to) {
            (Loc::Origin, Loc::Source) | (Loc::Source, Loc::Origin) => self.cost_origin_to_source,
            (Loc::Source, Loc::Dest) | (Loc::Dest, Loc::Source) => self.cost_source_to_dest,
            (Loc::Origin, Loc::Dest) | (Loc::Dest, Loc::Origin) => self.cost_origin_to_dest,
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
    DeliverCargo,
}

impl Operator {
    /// Full operator catalog for delivery-class plans. Order is
    /// canonical (BFS is deterministic given insertion order, so
    /// this drives tie-breaks between same-length plans).
    pub fn delivery_catalog() -> &'static [Operator] {
        &[
            Operator::Dock,
            Operator::Refuel,
            Operator::Buy,
            Operator::DeliverCargo,
            Operator::Undock,
            Operator::Travel { to: Loc::Origin },
            Operator::Travel { to: Loc::Source },
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
                    destination: map.resolve(*to).to_string(),
                };
                Some((next, action))
            }
            Operator::Dock => {
                if state.docked {
                    return None;
                }
                let mut next = state.clone();
                next.docked = true;
                Some((next, ShipAction::Dock))
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
            Operator::DeliverCargo => {
                if !state.docked || state.at != Loc::Dest {
                    return None;
                }
                if !state.cargo_loaded {
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
        LocMap {
            origin: "earth-station".into(),
            source: "belt-yard".into(),
            dest: "mars-station".into(),
            commodity: Commodity::Ore,
            quantity: 50,
            contract_id: "contract-42".into(),
            cost_origin_to_source: 2,
            cost_source_to_dest: 3,
            cost_origin_to_dest: 4,
        }
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
