//! Telic 0.1.0 GOAP-guided global search with *exact* Genesis stock/cash replay.
//!
//! Upstream Telic's Boolean effects are a structural *guide*, not evidence of
//! successful resource transfers. A separate bounded forward search evaluates
//! native action preconditions, actual quantities and treasury reductions on
//! the same read-only projection as HTN. No native orders are emitted here.

use std::collections::BTreeSet;

use telic::planning::{
    action::{ActionBuilder, ActionDef, Strategy},
    belief::{BeliefBuilder, BeliefSet},
    goal::GoalBuilder,
    planner::{CountHeuristic, GoapPlanner, SearchStrategy},
};

use super::{ActionSpec, GoalSpec, Planner, PlanningSnapshot, PlanResult,
    PlanStatus, SearchBudget, SCHEMA_VERSION};
use super::htn_adapter::{domain_from_native, NativeDomain};
use super::forward_search::{no_result, path_result, search, SearchMode};

pub struct TelicGoapAdapter;

#[derive(Debug)]
struct PlanningOnly;
impl Strategy for PlanningOnly { fn is_complete(&self) -> bool {true} }

fn fact_key(field:usize, threshold:i32)->String { format!("s{field}_at_least_{threshold}") }

/// Telic sees only Boolean landmarks. This has NO authority to change the
/// projection or validate action costs; it is a source of ordering hints only.
fn telic_structural_hint(domain:&NativeDomain, catalogue:&[ActionSpec]) -> Vec<usize> {
    // Prevent unbounded third-party search on a huge live galaxy snapshot.
    if domain.actions.is_empty() || domain.actions.len()>36 {return Vec::new();}
    let mut facts=BTreeSet::<(usize,i32)>::new();
    facts.insert((domain.goal_field,domain.goal_amount));
    for a in &domain.actions {
        if a.pre.len()>8 {return Vec::new();}
        facts.extend(a.pre.iter().copied().filter(|(_,n)|*n>0));
    }
    if facts.len()>96 {return Vec::new();}
    let mut beliefs=BeliefSet::new();
    for &(field,threshold) in &facts {
        beliefs.add(BeliefBuilder::new(fact_key(field,threshold))
            .condition(move |state:&Vec<i32>|state[field]>=threshold)
            .build());
    }
    let defs:Vec<ActionDef>=domain.actions.iter().enumerate().filter_map(|(i,action)| {
        let effects:Vec<_>=facts.iter().copied()
            .filter(|(field,_)|action.effect(*field)>0).collect();
        if effects.is_empty(){return None;}
        let spec=&catalogue[action.catalogue_index];
        let relative_cost=(spec.expected_ticks.min(u64::from(u32::MAX)) as f32 / 100.0)
            + (spec.cost_credits.max(0).min(100_000) as f32 / 1000.0) + 1.0;
        let mut b=ActionBuilder::new(i.to_string())
            .cost(relative_cost).strategy(PlanningOnly);
        for &(field,threshold) in &action.pre {
            if threshold>0 {b=b.precondition(fact_key(field,threshold));}
        }
        for (field,threshold) in effects {b=b.effect(fact_key(field,threshold));}
        Some(b.build())
    }).collect();
    let goal=GoalBuilder::new("native_stock_goal")
        .priority(1000)
        .desired_effect(fact_key(domain.goal_field,domain.goal_amount))
        .build();
    let Some(plan)=GoapPlanner::plan_with(
        &beliefs,&domain.initial,&defs,&[goal],None,
        SearchStrategy::Greedy,&CountHeuristic
    ) else {return Vec::new()};
    plan.actions.iter().filter_map(|name|name.parse::<usize>().ok())
        .filter_map(|domain_index|domain.actions.get(domain_index).map(|a|a.catalogue_index))
        .collect()
}

impl Planner for TelicGoapAdapter {
    fn id(&self)->&'static str {"telic_0_1_goap_guided"}

    fn plan(&self,snapshot:&PlanningSnapshot,goal:&GoalSpec,
        actions:&[ActionSpec],budget:SearchBudget)->PlanResult {
        if budget.max_nodes==0 || budget.max_depth==0 {
            return no_result(self.id(),goal,PlanStatus::BudgetExhausted,0,"search budget is zero");
        }
        if snapshot.schema_version != SCHEMA_VERSION {
            return no_result(self.id(),goal,PlanStatus::InvalidSnapshot,0,"unsupported snapshot schema");
        }
        let Ok(domain)=domain_from_native(snapshot,goal,actions) else {
            return no_result(self.id(),goal,PlanStatus::InvalidSnapshot,0,
                "native stock projection not safe; no orders issued");
        };
        if domain.initial[domain.goal_field]>=domain.goal_amount {
            return no_result(self.id(),goal,PlanStatus::NoPlan,0,"goal already reached");
        }
        let hint=telic_structural_hint(&domain,actions);
        let outcome=search(&domain,actions,budget,SearchMode::Goap,&hint);
        match outcome.path {
            Some(path)=>path_result(self.id(),goal,actions,&domain,path,outcome.nodes_expanded,
                if hint.is_empty() {"Exact stock search; Telic had no usable structural path; native dispatch not implied"}
                else {"Telic 0.1.0 GOAP structural guide + exact stock/cash replay; native dispatch not implied"}),
            None=>no_result(self.id(),goal,
                if outcome.exhausted {PlanStatus::BudgetExhausted} else {PlanStatus::NoPlan},
                outcome.nodes_expanded,"No exact feasible sequence within bounded GOAP search"),
        }
    }
}
