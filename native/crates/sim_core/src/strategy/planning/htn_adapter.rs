//! Stage 04: bounded, **read-only** HTN planning over a native Galaxy snapshot.
//!
//! This ports the method-generation idea from the supplied AI Bench v1.3
//! `src/htn_adapter.rs`. Search decomposes a stock goal into grounded native
//! actions and prerequisites; the actual `htn` 0.2.1 crate verifies each
//! primitive and the ordered plan against a changing blackboard.
//!
//! IMPORTANT: A projected delivery is not a ship order. `PlanningSnapshot`
//! currently lacks routes, ETA/fuel cost, ship commitments, workforce and
//! facility-specific market IDs. In particular this adapter does NOT prove
//! that native dispatch will accept any projected action. It is intentionally
//! NOT wired to `strategy::coordination` and cannot mutate World or issue work.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use htn::{ArithmeticOp, ComparisonOp, Condition, Effect, Task, Value};

use super::{
    ActionKind, ActionSpec, GoalSpec, PlanResult, PlanStatus, PlanStep,
    Planner, PlanningSnapshot, SearchBudget, SCHEMA_VERSION,
};
use crate::economy::commodities::Commodity;

/// Proposed planner. Not used by the native director until runtime
/// integration and compilation have been demonstrated.
pub struct HtnAdapter;

#[derive(Clone)]
pub(super) struct NativeAction {
    pub(super) catalogue_index: usize,
    /// Necessary stocks/available cash before applying this step.
    pub(super) pre: Vec<(usize, i32)>,
    /// Effects apply to the *same* location-scoped stock/cash projection.
    pub(super) delta: Vec<(usize, i32)>,
}

impl NativeAction {
    pub(super) fn effect(&self, field: usize) -> i32 {
        self.delta.iter().find(|(f, _)| *f == field)
            .map_or(0, |(_, amount)| *amount)
    }

    pub(super) fn apply(&self, state: &[i32]) -> Option<Vec<i32>> {
        if self.pre.iter().any(|(field, needed)| state[*field] < *needed) {
            return None;
        }
        let mut after = state.to_vec();
        for &(field, delta) in &self.delta {
            let updated = after[field].checked_add(delta)?;
            if updated < 0 { return None; }
            after[field] = updated;
        }
        Some(after)
    }
}

pub(super) struct NativeDomain {
    pub(super) fields: Vec<String>,
    pub(super) initial: Vec<i32>,
    pub(super) goal_field: usize,
    pub(super) goal_amount: i32,
    pub(super) actions: Vec<NativeAction>,
}

fn integer(value: i32) -> Value { Value::Int(value) }

fn stock_field(location: &str, commodity: Commodity) -> String {
    // The location length keeps distinct IDs distinct even if IDs contain ':'
    format!("market:{}:{}:{}", location.len(), location, commodity.as_str())
}

fn catalogue_is_recipe(snapshot: &PlanningSnapshot, action: &ActionSpec) -> bool {
    let Some(facility_type) = action.required_facility_type.as_deref() else { return false };
    if !snapshot.facilities.iter().any(|f| {
        f.location_id == action.destination_id && f.facility_type == facility_type &&
            // New native actions pin a stable producer ID. Older test-only
            // projections had none; the native dispatcher rejects those.
            action.source_id.as_ref().is_none_or(|id| id == &f.facility_id)
    }) { return false; }
    // Do not trust arbitrary hand-authored 'outputs' as a production effect.
    let mut inputs = action.inputs.clone();
    let mut outputs = action.outputs.clone();
    inputs.sort_by_key(|(c, _)| c.as_str());
    outputs.sort_by_key(|(c, _)| c.as_str());
    snapshot.recipes.iter().any(|recipe| {
        if recipe.facility_type != facility_type { return false; }
        let mut ri = recipe.inputs.clone();
        let mut ro = recipe.outputs.clone();
        ri.sort_by_key(|(c, _)| c.as_str());
        ro.sort_by_key(|(c, _)| c.as_str());
        ri == inputs && ro == outputs
    })
}

pub(super) fn domain_from_native(
    snapshot: &PlanningSnapshot, goal: &GoalSpec, catalogue: &[ActionSpec],
) -> Result<NativeDomain, &'static str> {
    if snapshot.schema_version != SCHEMA_VERSION || snapshot.faction_id.is_empty() ||
        goal.destination_id.is_empty() || goal.target_units == 0 {
        return Err("invalid_snapshot_or_goal");
    }
    let floor = snapshot.treasury_floor_credits.max(0);
    let spendable = snapshot.treasury_credits.saturating_sub(floor).max(0);
    let spendable = i32::try_from(spendable).map_err(|_| "credits_out_of_i32_range")?;
    let goal_amount = i32::try_from(goal.target_units).map_err(|_| "goal_out_of_i32_range")?;

    let mut stock_by_location = BTreeMap::<String, BTreeMap<String, i32>>::new();
    for market in &snapshot.owned_markets {
        if market.location_id.is_empty() || stock_by_location.contains_key(&market.location_id) {
            // Multiple markets at one location cannot be aggregated safely until
            // the snapshot exposes stable market IDs and transfer permissions.
            return Err("ambiguous_market_location");
        }
        let mut local = BTreeMap::new();
        for commodity in Commodity::ALL {
            let quantity = market.stock.get(commodity.as_str()).copied().unwrap_or(0.0);
            if !quantity.is_finite() || quantity < 0.0 || quantity.floor() > f64::from(i32::MAX) {
                return Err("invalid_stock");
            }
            // Conservative rounding: a fractional stock unit is not free.
            local.insert(commodity.as_str().to_owned(), quantity.floor() as i32);
        }
        stock_by_location.insert(market.location_id.clone(), local);
    }
    if !stock_by_location.contains_key(&goal.destination_id) {
        return Err("goal_market_not_owned_or_missing");
    }
    let mut fields = Vec::new();
    let mut initial = Vec::new();
    let mut indices = BTreeMap::<(String, String), usize>::new();
    for (location, amounts) in &stock_by_location {
        for commodity in Commodity::ALL {
            let field = fields.len();
            fields.push(stock_field(location, *commodity));
            initial.push(amounts[commodity.as_str()]);
            indices.insert((location.clone(), commodity.as_str().into()), field);
        }
    }
    let cash_field = fields.len();
    fields.push("credits_spendable_after_treasury_floor".into());
    initial.push(spendable);
    let goal_field = indices[&(goal.destination_id.clone(), goal.commodity.as_str().into())];
    // A parked ship is not an infinite reusable resource. The first water
    // scenario had one delivery, but multi-station plans can contain multiple
    // voyages. Until native ship-repositioning actions exist, budget at most
    // one departure per idle, uncommitted carrier at its INITIAL location.
    // This is conservative: a ship may become available again after a native
    // return trip, in which case the next planning cycle can reconsider it.
    let committed_ships: BTreeSet<&str> = snapshot.active_commitments.iter()
        .filter_map(|c| c.assigned_ship_id.as_deref()).collect();
    let mut source_slots = BTreeMap::<String, usize>::new();
    for (location, _) in &stock_by_location {
        let eligible = snapshot.ships.iter().filter(|ship| {
            ship.location_id.as_deref() == Some(location.as_str()) &&
                !ship.in_transit && !committed_ships.contains(ship.ship_id.as_str()) &&
                ship.free_cargo > 0 && ship.fuel.is_finite() && ship.fuel > 0.0
        }).count();
        // Match the fixed-size integer symbolic state and guard the bound.
        let eligible = i32::try_from(eligible).map_err(|_| "too_many_available_carriers")?;
        let index = fields.len();
        fields.push(format!("available_departures:{}:{}", location.len(), location));
        initial.push(eligible);
        source_slots.insert(location.clone(), index);
    }
    let mut actions = Vec::new();
    let mut seen_actions = BTreeSet::new();
    for (catalogue_index, spec) in catalogue.iter().enumerate() {
        if spec.action_id.is_empty() || !seen_actions.insert(spec.action_id.as_str()) ||
            spec.cost_credits < 0 || spec.units == 0 || spec.destination_id.is_empty() {
            continue;
        }
        let Ok(cost) = i32::try_from(spec.cost_credits) else {continue};
        if cost > spendable { continue; }
        let mut delta = BTreeMap::<usize, i32>::new();
        let mut recognised = true;
        match &spec.kind {
            ActionKind::Deliver => {
                let (Some(source), Some(commodity)) = (spec.source_id.as_deref(), spec.commodity) else {continue};
                if source == spec.destination_id {continue;}
                let Some(&from) = indices.get(&(source.into(), commodity.as_str().into())) else {continue};
                let Some(&to) = indices.get(&(spec.destination_id.clone(), commodity.as_str().into())) else {continue};
                let Ok(quantity) = i32::try_from(spec.units) else {continue};
                // The action is a hypothetical delivery. Route and ship fuel
                // still require native validation before dispatch.
                let ship_candidate = snapshot.ships.iter().any(|ship| {
                    !ship.in_transit && !committed_ships.contains(ship.ship_id.as_str()) &&
                        ship.location_id.as_deref() == Some(source) &&
                        ship.free_cargo >= spec.units && ship.fuel.is_finite() && ship.fuel > 0.0
                });
                if !ship_candidate {continue;}
                let Some(&slot) = source_slots.get(source) else {continue};
                delta.insert(slot, -1);
                delta.insert(from, -quantity);
                delta.insert(to, quantity);
            }
            ActionKind::Produce => {
                if !catalogue_is_recipe(snapshot, spec) {continue;}
                for &(commodity, amount) in &spec.inputs {
                    if amount == 0 { recognised = false; break; }
                    let Some(&field) = indices.get(&(spec.destination_id.clone(), commodity.as_str().into())) else {
                        recognised = false; break;
                    };
                    let Ok(amount) = i32::try_from(amount) else {recognised = false; break};
                    let Some(next) = delta.get(&field).copied().unwrap_or(0).checked_sub(amount) else {
                        recognised = false; break;
                    };
                    delta.insert(field, next);
                }
                if !recognised {continue;}
                for &(commodity, amount) in &spec.outputs {
                    if amount == 0 { recognised = false; break; }
                    let Some(&field) = indices.get(&(spec.destination_id.clone(), commodity.as_str().into())) else {
                        recognised = false; break;
                    };
                    let Ok(amount) = i32::try_from(amount) else {recognised = false; break};
                    let Some(next) = delta.get(&field).copied().unwrap_or(0).checked_add(amount) else {
                        recognised = false; break;
                    };
                    delta.insert(field, next);
                }
            }
            // No claims about construction/research/colonization until they
            // have fully specified native prerequisites and effects.
            ActionKind::Construct | ActionKind::Research | ActionKind::FoundColony => continue,
        }
        if !recognised || delta.values().all(|d| *d == 0) {continue;}
        if cost > 0 {delta.insert(cash_field, -cost);}
        let pre = delta.iter().filter_map(|(field, amount)| {
            (*amount < 0).then_some((*field, -*amount))
        }).collect();
        actions.push(NativeAction {
            catalogue_index,
            pre, delta: delta.into_iter().collect(),
        });
    }
    Ok(NativeDomain { fields, initial, goal_field, goal_amount, actions })
}

fn primitive_task(domain: &NativeDomain, action: &NativeAction, index: usize) -> Task {
    let preconditions = action.pre.iter().map(|(field, needed)| {
        Condition::compare(&domain.fields[*field], ComparisonOp::GTE, integer(*needed))
    }).collect();
    let effects = action.delta.iter().map(|(field, delta)| {
        Effect::new(&domain.fields[*field], ArithmeticOp::Add, integer(*delta))
    }).collect();
    Task::Action { preconditions, action: index.to_string(), effects }
}

fn blackboard(fields: &[String], state: &[i32]) -> HashMap<String, Value> {
    fields.iter().cloned().zip(state.iter().copied().map(integer)).collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Work {
    Require { field: usize, min: i32 },
    Prepare(usize),
    Apply { action: usize, goal_field: usize, min: i32 },
}

struct MethodSearch<'a> {
    domain: &'a NativeDomain,
    nodes_left: u32,
    depth: usize,
    seen: HashSet<(Vec<i32>, Vec<Work>, usize)>,
    depth_truncated: bool,
}

impl MethodSearch<'_> {
    fn expand(&mut self, state: &[i32], mut todo: Vec<Work>, path: &mut Vec<usize>) -> bool {
        let Some(work) = todo.pop() else {return true};
        if self.nodes_left == 0 {return false;}
        if todo.len() > 100 {self.depth_truncated=true;return false;}
        self.nodes_left -= 1;
        match work {
            Work::Require { field, min } if state[field] >= min => self.expand(state, todo, path),
            Work::Require { field, min } => {
                if path.len() >= self.depth {self.depth_truncated=true;return false;}
                if todo.iter().any(|w| {
                    matches!(w, Work::Apply {goal_field, min: target, ..} if *goal_field == field && *target == min)
                }) {return false;}
                // HTN decomposition: satisfying a stock goal can be achieved
                // by any producer; each method first meets prerequisites.
                let mut producers: Vec<usize> = self.domain.actions.iter().enumerate()
                    .filter(|(_, action)| action.effect(field) > 0)
                    .map(|(i,_)| i).collect();
                producers.sort_by_key(|&i| {
                    let action = &self.domain.actions[i];
                    (action.pre.iter().filter(|(f, n)|state[*f] < *n).count(),
                     self.domain.fields.len().saturating_sub(action.effect(field) as usize),
                     action.catalogue_index)
                });
                for index in producers {
                    let mut branch = todo.clone();
                    branch.push(Work::Require {field, min});
                    branch.push(Work::Apply {action:index,goal_field:field,min});
                    branch.push(Work::Prepare(index));
                    if self.expand(state, branch, path) {return true;}
                }
                false
            }
            Work::Prepare(index) => {
                let action = &self.domain.actions[index];
                let missing = action.pre.iter().find(|(f, n)| state[*f] < *n).copied();
                if let Some((field, min)) = missing {
                    if path.len() >= self.depth {self.depth_truncated=true;return false;}
                    let key = (state.to_vec(), todo.clone(), self.depth - path.len());
                    if !self.seen.insert(key) {return false;}
                    todo.push(Work::Prepare(index));
                    todo.push(Work::Require {field, min});
                    self.expand(state, todo, path)
                } else { self.expand(state, todo, path) }
            }
            Work::Apply { action:index, goal_field, min } => {
                if state[goal_field] >= min {return self.expand(state, todo, path);}
                if path.len() >= self.depth {self.depth_truncated=true;return false;}
                if self.domain.actions[index].effect(goal_field) <= 0 {return false;}
                let primitive = primitive_task(self.domain, &self.domain.actions[index], index);
                if htn::plan(&primitive, &blackboard(&self.domain.fields, state)).is_err() {
                    return false;
                }
                let Some(next) = self.domain.actions[index].apply(state) else {return false};
                path.push(index);
                if self.expand(&next, todo, path) {return true;}
                path.pop();
                false
            }
        }
    }
}

fn result(status: PlanStatus, goal: &GoalSpec, nodes: u32, reason: &str) -> PlanResult {
    PlanResult {status,goal_id:goal.goal_id.clone(),planner_id:"htn_0_2_1_shadow".into(),
        steps:vec![],forecast_credits:0,forecast_ticks:0,nodes_expanded:nodes,
        explanation:reason.into()}
}

impl Planner for HtnAdapter {
    fn id(&self) -> &'static str {"htn_0_2_1_shadow"}

    fn plan(&self, snapshot: &PlanningSnapshot, goal: &GoalSpec,
        catalogue: &[ActionSpec], budget: SearchBudget) -> PlanResult {
        if budget.max_nodes == 0 || budget.max_depth == 0 {
            return result(PlanStatus::BudgetExhausted,goal,0,"search budget is zero");
        }
        let Ok(domain) = domain_from_native(snapshot, goal, catalogue) else {
            return result(PlanStatus::InvalidSnapshot,goal,0,"snapshot/goal cannot be projected safely");
        };
        if domain.initial[domain.goal_field] >= domain.goal_amount {
            return result(PlanStatus::NoPlan,goal,0,"goal already satisfied; no action required");
        }
        let mut search = MethodSearch {
            domain:&domain,nodes_left:budget.max_nodes,depth:budget.max_depth,
            seen: HashSet::new(), depth_truncated:false,
        };
        let mut path = Vec::new();
        let success = search.expand(&domain.initial,
            vec![Work::Require {field:domain.goal_field,min:domain.goal_amount}],&mut path);
        let nodes = budget.max_nodes - search.nodes_left;
        if !success {
            return result(if search.nodes_left == 0 || search.depth_truncated {
                PlanStatus::BudgetExhausted
            } else {PlanStatus::NoPlan},
                goal,nodes,"no valid decomposition found within budget; no native orders issued");
        }
        // Recheck the WHOLE ordered path using the original upstream HTN
        // implementation, not merely our custom method search's prediction.
        let mut tasks: Vec<Task> = path.iter().map(|index| {
            primitive_task(&domain,&domain.actions[*index],*index)
        }).collect();
        tasks.push(Task::Action {
            preconditions:vec![Condition::compare(&domain.fields[domain.goal_field],
                ComparisonOp::GTE,integer(domain.goal_amount))],
            action:"__goal_satisfied__".into(),effects:vec![],
        });
        let root = Task::Sequence {preconditions:vec![],tasks};
        let Ok(mut verified) = htn::plan(&root,&blackboard(&domain.fields,&domain.initial)) else {
            return result(PlanStatus::NoPlan,goal,nodes,"upstream HTN rejected projected sequence");
        };
        if verified.pop().as_deref() != Some("__goal_satisfied__") || verified.len() != path.len() {
            return result(PlanStatus::NoPlan,goal,nodes,"HTN verification returned an unexpected sequence");
        }
        let mut steps = Vec::new();
        let mut total_cost = 0_i64;
        let mut total_ticks = 0_u64;
        for (position, index) in path.into_iter().enumerate() {
            let spec = &catalogue[domain.actions[index].catalogue_index];
            let Some(cost) = total_cost.checked_add(spec.cost_credits) else {
                return result(PlanStatus::InvalidSnapshot,goal,nodes,"cost overflow");
            };
            let Some(ticks) = total_ticks.checked_add(spec.expected_ticks) else {
                return result(PlanStatus::InvalidSnapshot,goal,nodes,"duration overflow");
            };
            total_cost = cost;
            total_ticks = ticks;
            steps.push(PlanStep {
                step_id:format!("htn-{:03}",position + 1),
                action_id:spec.action_id.clone(),
                depends_on:if position == 0 {vec![]} else {vec![format!("htn-{:03}",position)]},
                expected_condition:"native_receipt_then_recheck_physical_stock".into(),
            });
        }
        PlanResult {status:PlanStatus::Ready,goal_id:goal.goal_id.clone(),
            planner_id:self.id().into(),steps,forecast_credits:total_cost,
            forecast_ticks:total_ticks,nodes_expanded:nodes,
            explanation:"HTN-verified stock plan; hypothetical until route/workforce/native dispatch validation".into()}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::{validate_plan, FacilityEntry, MarketEntry, RecipeEntry, ShipEntry};

    fn market(place:&str, stock:&[(Commodity,f64)]) -> MarketEntry {
        MarketEntry {market_id:format!("market-{place}"),facility_id:format!("facility-{place}"),
            location_id:place.into(),stock:stock.iter()
            .map(|(c,v)|(c.as_str().to_string(),*v)).collect(),
            demand:BTreeMap::new(),prices:BTreeMap::new()}
    }
    fn fixture() -> (PlanningSnapshot,GoalSpec,Vec<ActionSpec>) {
        let snap = PlanningSnapshot {schema_version:SCHEMA_VERSION,tick:100,
            faction_id:"genesis".into(),treasury_credits:30_000,
            treasury_floor_credits:10_000,
            owned_markets:vec![market("asteroid",&[(Commodity::Ice,8.0)]),
                market("colony",&[(Commodity::Water,0.0)])],
            facilities:vec![FacilityEntry {facility_id:"ref1".into(),location_id:"colony".into(),
                facility_type:"refinery".into()}],
            ships:vec![ShipEntry {ship_id:"miner".into(),class:"courier".into(),
                location_id:Some("asteroid".into()),in_transit:false,free_cargo:20,fuel:100.0}],
            active_commitments:vec![],technologies:vec![],
            recipes:vec![RecipeEntry {recipe_id:"process_ice".into(),facility_type:"refinery".into(),
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10),(Commodity::Fuel,5)]}],
        };
        let goal = GoalSpec {goal_id:"recover-water".into(),destination_id:"colony".into(),
            commodity:Commodity::Water,target_units:10,priority:100};
        let actions = vec![
            ActionSpec {action_id:"deliver-ice".into(),kind:ActionKind::Deliver,
                source_id:Some("asteroid".into()),destination_id:"colony".into(),
                commodity:Some(Commodity::Ice),units:8,cost_credits:200,expected_ticks:80,
                inputs:vec![],outputs:vec![],required_facility_type:None},
            ActionSpec {action_id:"process-ice".into(),kind:ActionKind::Produce,
                source_id:None,destination_id:"colony".into(),commodity:Some(Commodity::Water),
                units:10,cost_credits:100,expected_ticks:40,
                inputs:vec![(Commodity::Ice,8)],
                outputs:vec![(Commodity::Water,10),(Commodity::Fuel,5)],
                required_facility_type:Some("refinery".into())},
        ];
        (snap,goal,actions)
    }

    #[test]
    fn htn_finds_real_recipe_dependency_without_adding_free_stock() {
        let (snapshot,goal,actions)=fixture();
        let original=snapshot.clone();
        let proposal=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(proposal.status,PlanStatus::Ready,"{}",proposal.explanation);
        assert_eq!(proposal.steps.iter().map(|s|s.action_id.as_str()).collect::<Vec<_>>(),
            vec!["deliver-ice","process-ice"]);
        assert_eq!(proposal.forecast_credits,300);
        assert_eq!(validate_plan(&snapshot,&goal,&actions,&proposal,SearchBudget::default()),Ok(()));
        assert_eq!(snapshot,original,"shadow HTN must not mutate ECS projection");
    }

    #[test]
    fn htn_cannot_generate_ice_from_nothing() {
        let (mut snapshot,goal,actions)=fixture();
        snapshot.owned_markets[0].stock.insert("ice".into(),0.0);
        let plan=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(plan.status,PlanStatus::NoPlan);
        assert!(plan.steps.is_empty());
    }

    #[test]
    fn htn_cannot_spend_below_treasury_floor() {
        let (mut snapshot,goal,actions)=fixture();
        snapshot.treasury_credits=10_100;
        let plan=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(plan.status,PlanStatus::NoPlan);
    }

    #[test]
    fn htn_rejects_fake_recipe_or_missing_refinery() {
        let (mut snapshot,goal,actions)=fixture();
        snapshot.facilities.clear();
        let plan=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(plan.status,PlanStatus::NoPlan);
    }

    #[test]
    fn htn_has_real_bounded_search() {
        let (snapshot,goal,actions)=fixture();
        let plan=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget{max_nodes:1,max_depth:12});
        assert_eq!(plan.status,PlanStatus::BudgetExhausted);
        assert!(plan.nodes_expanded<=1);
    }

    #[test]
    fn htn_rejects_ambiguous_multimarket_snapshot() {
        let (mut snapshot,goal,actions)=fixture();
        snapshot.owned_markets.push(market("colony",&[(Commodity::Ice,9.0)]));
        let plan=HtnAdapter.plan(&snapshot,&goal,&actions,SearchBudget::default());
        assert_eq!(plan.status,PlanStatus::InvalidSnapshot);
    }
}
