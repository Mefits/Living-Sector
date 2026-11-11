//! Exact projected-stock successor model shared by Telic/GOAP and Control Beam.
//!
//! Both searches consume the *same* conservative NativeDomain that was used
//! by HTN: owned market identities, verified native recipes, location-scoped
//! stocks and a single spendable treasury projection. A successful plan is
//! still a forecast; only NativeExecution may issue a native contract.

use std::collections::BTreeMap;

use super::{ActionSpec, GoalSpec, PlanResult, PlanStatus, PlanStep, SearchBudget};
use super::htn_adapter::NativeDomain;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum SearchMode {
    /// Global best-first, independently reconciling Telic's symbolic hints
    /// against exact resource and cash transitions.
    Goap,
    /// Bounded-width approximate search on the exact same transitions.
    Beam { width: usize },
}

#[derive(Clone)]
struct Node {
    stock: Vec<i32>,
    path: Vec<usize>,
    travel_ticks: u64,
    credits: i64,
    rank: u128,
}

#[derive(Debug)]
pub(super) struct SearchOutcome {
    pub path: Option<Vec<usize>>,
    pub nodes_expanded: u32,
    pub exhausted: bool,
}

fn rank(domain: &NativeDomain, node: &Node, mode: SearchMode, telic_hint: &[usize]) -> u128 {
    let shortage = domain.goal_amount.saturating_sub(node.stock[domain.goal_field]).max(0) as u128;
    let time_cost = u128::from(node.travel_ticks).saturating_add(u128::try_from(node.credits.max(0)).unwrap_or(u128::MAX) / 20);
    // The hint can break ties, but can NEVER make an infeasible state possible.
    // Its weight is deliberately below one stock-unit of real goal progress.
    let hint_bonus = node.path.last().and_then(|idx|{
        let catalogue_index = domain.actions[*idx].catalogue_index;
        telic_hint.iter().position(|h| *h == catalogue_index)
    }).map_or(0, |i| 12_u128.saturating_sub(i as u128));
    match mode {
        // Dijkstra-style ordering. The Telic guide *only breaks cost ties*,
        // it must not change which plan is truly cheaper on this projection.
        SearchMode::Goap => time_cost.saturating_mul(100)
            .saturating_add(12_u128.saturating_sub(hint_bonus)),
        // Beam prefers imminent real progress; its width bound is heuristic.
        SearchMode::Beam {..} => shortage.saturating_mul(1_000)
            .saturating_add(time_cost).saturating_add(node.path.len() as u128),
    }
}

fn score(ticks: u64, credits: i64) -> u128 {
    u128::from(ticks).saturating_add(u128::try_from(credits.max(0)).unwrap_or(u128::MAX) / 20)
}

fn next_nodes(domain:&NativeDomain, catalogue:&[ActionSpec], node: &Node,
              best: &mut BTreeMap<Vec<i32>, u128>, mode:SearchMode, telic_hint:&[usize],
) -> Vec<Node> {
    let mut next=Vec::new();
    for (index, action) in domain.actions.iter().enumerate() {
        let Some(stock)=action.apply(&node.stock) else {continue;};
        let spec=&catalogue[action.catalogue_index];
        let Some(ticks)=node.travel_ticks.checked_add(spec.expected_ticks) else {continue};
        let Some(credits)=node.credits.checked_add(spec.cost_credits) else {continue};
        let travel_cost=score(ticks,credits);
        if best.get(&stock).is_some_and(|old| *old <= travel_cost) {continue;}
        best.insert(stock.clone(),travel_cost);
        let mut path=node.path.clone();
        path.push(index);
        let mut candidate=Node {stock,path,travel_ticks:ticks,credits,rank:0};
        candidate.rank=rank(domain,&candidate,mode,telic_hint);
        next.push(candidate);
    }
    next
}

/// Search bounds are expressed in expanded nodes rather than wall clock time,
/// so an identical input and budget yields an identical set of expansions.
/// `exhausted` also denotes truncation by the depth limit; a truncated search
/// must not report `NoPlan` as proof of unreachable goals.
pub(super) fn search(domain:&NativeDomain,catalogue:&[ActionSpec],
    budget:SearchBudget,mode:SearchMode,telic_hint:&[usize]) -> SearchOutcome {
    if budget.max_nodes==0 || budget.max_depth==0 {
        return SearchOutcome{path:None,nodes_expanded:0,exhausted:true};
    }
    let start=Node {stock:domain.initial.clone(),path:Vec::new(),travel_ticks:0,credits:0,rank:0};
    let mut frontier=vec![start];
    let mut best=BTreeMap::new();
    best.insert(domain.initial.clone(),0_u128);
    let mut nodes=0_u32;
    let mut truncated=false;
    loop {
        if frontier.is_empty() {break;}
        // For Beam, whole level is explored before width pruning. For GOAP,
        // the globally best state is chosen next, even across depths.
        frontier.sort_by(|a,b|a.rank.cmp(&b.rank).then_with(||a.path.cmp(&b.path)));
        let active=if mode==SearchMode::Goap {
            vec![frontier.remove(0)]
        } else {
            std::mem::take(&mut frontier)
        };
        let mut next_level=Vec::new();
        for node in active {
            if node.stock[domain.goal_field]>=domain.goal_amount {
                return SearchOutcome{path:Some(node.path),nodes_expanded:nodes,exhausted:false};
            }
            if node.path.len()>=budget.max_depth {truncated=true;continue;}
            if nodes>=budget.max_nodes {return SearchOutcome{path:None,nodes_expanded:nodes,exhausted:true};}
            nodes+=1;
            next_level.extend(next_nodes(domain,catalogue,&node,&mut best,mode,telic_hint));
        }
        if let SearchMode::Beam {width} = mode {
            next_level.sort_by(|a,b|a.rank.cmp(&b.rank).then_with(||a.path.cmp(&b.path)));
            if next_level.len()>width {truncated=true;next_level.truncate(width);}
            frontier=next_level;
        } else {
            frontier.extend(next_level);
        }
    }
    SearchOutcome{path:None,nodes_expanded:nodes,exhausted:truncated}
}

pub(super) fn no_result(planner:&str,goal:&GoalSpec,status:PlanStatus,nodes:u32,reason:&str)->PlanResult {
    PlanResult {status,goal_id:goal.goal_id.clone(),planner_id:planner.into(),
        steps:Vec::new(),forecast_credits:0,forecast_ticks:0,
        nodes_expanded:nodes,explanation:reason.into()}
}

pub(super) fn path_result(planner:&str,goal:&GoalSpec,catalogue:&[ActionSpec],
    domain:&NativeDomain,path:Vec<usize>,nodes:u32,reason:&str)->PlanResult {
    let mut credits=0_i64;
    let mut ticks=0_u64;
    let mut steps=Vec::new();
    for (index,step) in path.iter().enumerate() {
        let spec=&catalogue[domain.actions[*step].catalogue_index];
        let (Some(new_credits),Some(new_ticks))=(credits.checked_add(spec.cost_credits),ticks.checked_add(spec.expected_ticks)) else {
            return no_result(planner,goal,PlanStatus::InvalidSnapshot,nodes,"forecast overflow");
        };
        credits=new_credits;ticks=new_ticks;
        steps.push(PlanStep {step_id:format!("search-{:03}",index+1),
            action_id:spec.action_id.clone(),
            depends_on:if index==0 {vec![]} else {vec![format!("search-{:03}",index)]},
            expected_condition:"native_receipt_then_recheck_physical_stock".into()});
    }
    PlanResult{status:PlanStatus::Ready,goal_id:goal.goal_id.clone(),planner_id:planner.into(),
        steps,forecast_credits:credits,forecast_ticks:ticks,nodes_expanded:nodes,
        explanation:reason.into()}
}
