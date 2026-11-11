//! Block C: genuinely cooperating, *pure* faction planner.
//!
//! Genesis Utility/Personality chooses the strategic goal before this module
//! runs. HTN decomposes that goal; where it ends in a simple native recipe,
//! Telic-guided GOAP may solve the missing-ingredient subgoal and feed its
//! result into the HTN production milestone. Otherwise GOAP acts as a full-goal
//! fallback. Beam is only invoked when viable alternatives disagree (or both
//! structural planners fail). All candidates must replay through the *same*
//! conservative quantity/cash domain, with one shared node budget.
//!
//! The result is a forecast, never a ship order or a production receipt.
//! NativeExecution is the ONLY component permitted to dispatch a plan.

use serde::Serialize;
use super::{ActionKind, ActionSpec, ControlBeamAdapter, GoalSpec, HtnAdapter,
    Planner, PlanningSnapshot, PlanResult, PlanStatus, PlanStep, SearchBudget,
    TelicGoapAdapter, validate_plan};
use super::htn_adapter::domain_from_native;

/// Preferences are derived from the EXISTING Genesis commander profile; not
/// a second personality system. Never relaxes a resource/legal precondition.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HybridPreferences {
    pub cost_weight: f64,
    pub speed_weight: f64,
    pub caution_weight: f64,
}
impl Default for HybridPreferences {
    fn default() -> Self {Self { cost_weight:1.0, speed_weight:1.0, caution_weight:0.5 }}
}
impl HybridPreferences {
    pub fn bounded(self) -> Self {
        let f=|v:f64| if v.is_finite() {v.clamp(0.1, 8.0)} else {1.0};
        Self {cost_weight:f(self.cost_weight),speed_weight:f(self.speed_weight),
            caution_weight:f(self.caution_weight)}
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct HybridRoleTrace {
    pub htn_status: PlanStatus,
    pub goap_status: PlanStatus,
    pub goap_full_status: Option<PlanStatus>,
    pub beam_status: Option<PlanStatus>,
    pub goap_role: &'static str,
    pub beam_reason: &'static str,
    pub selected_source: String,
    pub nodes_htn: u32,
    pub nodes_goap: u32,
    pub nodes_beam: u32,
    pub note: &'static str,
}

#[derive(Clone, Debug, Serialize)]
pub struct HybridDecision {
    pub result: PlanResult,
    pub roles: HybridRoleTrace,
}

#[derive(Clone, Copy, Debug)]
pub struct HybridPlanner {pub preferences: HybridPreferences}
impl Default for HybridPlanner {
    fn default() -> Self { Self { preferences: HybridPreferences::default() } }
}

fn rejected(goal:&GoalSpec, status:PlanStatus, nodes:u32, reason:&str) -> PlanResult {
    PlanResult{status,goal_id:goal.goal_id.clone(),planner_id:"hybrid_utility_htn_goap_beam".into(),
        steps:Vec::new(),forecast_credits:0,forecast_ticks:0,nodes_expanded:nodes,
        explanation:reason.into()}
}

/// All candidate steps must actually consume/create goods through the trusted
/// model. The shared structural validator alone cannot prove stock conservation.
fn safe_candidate(snapshot:&PlanningSnapshot, goal:&GoalSpec,
    actions:&[ActionSpec], result:&PlanResult, budget:SearchBudget) -> bool {
    if result.status!=PlanStatus::Ready ||
        validate_plan(snapshot,goal,actions,result,budget).is_err() {return false;}
    let Ok(domain)=domain_from_native(snapshot,goal,actions) else{return false;};
    let mut state=domain.initial.clone();
    for step in &result.steps {
        let Some(index)=actions.iter().position(|a|a.action_id==step.action_id) else {return false;};
        let Some(native)=domain.actions.iter().find(|n|n.catalogue_index==index) else {return false;};
        let Some(after)=native.apply(&state) else{return false;};
        state=after;
    }
    state[domain.goal_field]>=domain.goal_amount
}

/// Build one GOAP-supplied *ingredient* subplan plus the final HTN recipe step.
/// Only this provably simple decomposition is executable at present. For more
/// complex/multi-input trees, preserve the entire safe HTN plan unchanged.
fn compose_ingredient_route(snapshot:&PlanningSnapshot, goal:&GoalSpec,
    actions:&[ActionSpec], htn:&PlanResult, goap:&PlanResult) -> Option<PlanResult> {
    if htn.status!=PlanStatus::Ready || goap.status!=PlanStatus::Ready {return None;}
    let final_step=htn.steps.last()?;
    let recipe=actions.iter().find(|a|a.action_id==final_step.action_id)?;
    if recipe.kind!=ActionKind::Produce || recipe.inputs.len()!=1 ||
        !recipe.outputs.iter().any(|(c,_)| *c==goal.commodity) ||
        recipe.destination_id!=goal.destination_id {return None;}
    let mut steps=Vec::new();
    let mut credits=0_i64;
    let mut ticks=0_u64;
    for (i,step) in goap.steps.iter().enumerate() {
        let action=actions.iter().find(|a|a.action_id==step.action_id)?;
        credits=credits.checked_add(action.cost_credits)?;
        ticks=ticks.checked_add(action.expected_ticks)?;
        let previous=(i>0).then(||format!("hybrid-s{}",i));
        steps.push(PlanStep{step_id:format!("hybrid-s{}",i+1),
            action_id:action.action_id.clone(),depends_on:previous.into_iter().collect(),
            expected_condition:step.expected_condition.clone()});
    }
    credits=credits.checked_add(recipe.cost_credits)?;
    ticks=ticks.checked_add(recipe.expected_ticks)?;
    let previous=steps.last().map(|s|s.step_id.clone());
    steps.push(PlanStep{step_id:format!("hybrid-s{}",steps.len()+1),
        action_id:recipe.action_id.clone(),depends_on:previous.into_iter().collect(),
        expected_condition:final_step.expected_condition.clone()});
    let combined=PlanResult{status:PlanStatus::Ready,goal_id:goal.goal_id.clone(),
        planner_id:"hybrid_utility_htn_goap_beam".into(),steps,forecast_credits:credits,
        forecast_ticks:ticks,nodes_expanded:htn.nodes_expanded.saturating_add(goap.nodes_expanded),
        explanation:"HTN recipe milestone with GOAP ingredient-acquisition subplan".into()};
    let budget=SearchBudget{max_nodes:combined.nodes_expanded.max(1),max_depth:12};
    safe_candidate(snapshot,goal,actions,&combined,budget).then_some(combined)
}

fn score(plan:&PlanResult, actions:&[ActionSpec], p:HybridPreferences) -> f64 {
    let p=p.bounded();
    let predicted_payroll_risk=plan.steps.iter().filter(|step|actions.iter()
        .any(|a|a.action_id==step.action_id && a.kind==ActionKind::Produce)).count() as f64;
    p.cost_weight * plan.forecast_credits as f64 / 1000.0
       + p.speed_weight * plan.forecast_ticks as f64 / 100.0
       + p.caution_weight * (plan.steps.len() as f64 * 0.15 + predicted_payroll_risk)
}

impl HybridPlanner {
    pub fn decide(&self,snapshot:&PlanningSnapshot,goal:&GoalSpec,
        actions:&[ActionSpec], budget:SearchBudget) -> HybridDecision {
        const NOTE:&str="Native Utility selected goal; forecast never implies native completion";
        let no=PlanStatus::NoPlan;
        let mut trace=HybridRoleTrace {htn_status:no,goap_status:no,goap_full_status:None,beam_status:None,
            goap_role:"not_invoked",beam_reason:"not_invoked",selected_source:"none".into(),
            nodes_htn:0,nodes_goap:0,nodes_beam:0,note:NOTE};
        if budget.max_nodes<3 || budget.max_depth==0 {
            return HybridDecision{result:rejected(goal,PlanStatus::BudgetExhausted,0,"insufficient shared planning budget"),roles:trace};
        }
        // Fixed allocation prevents stacking N independent full budgets.
        let htn_nodes=(budget.max_nodes.saturating_mul(2)/5).max(1);
        let goap_nodes=(budget.max_nodes.saturating_mul(2)/5).max(1);
        let beam_nodes=budget.max_nodes.saturating_sub(htn_nodes).saturating_sub(goap_nodes);
        let htn_budget=SearchBudget{max_nodes:htn_nodes,max_depth:budget.max_depth};
        let htn=HtnAdapter.plan(snapshot,goal,actions,htn_budget);
        trace.nodes_htn=htn.nodes_expanded;
        trace.htn_status=htn.status;
        let htn_ok=safe_candidate(snapshot,goal,actions,&htn,htn_budget);
        let mut alternatives:Vec<(&'static str,PlanResult)>=Vec::new();
        if htn_ok {alternatives.push(("htn_decomposition",htn.clone()));}
        // Delegate a true HTN-produced intermediate goal to GOAP when possible.
        // Otherwise GOAP searches the original goal as a separate fallback.
        let intermediate=if htn_ok {
            htn.steps.last().and_then(|step|actions.iter().find(|a|a.action_id==step.action_id))
                .and_then(|recipe|{
                    if recipe.kind!=ActionKind::Produce || recipe.inputs.len()!=1 ||
                        recipe.destination_id!=goal.destination_id ||
                        !recipe.outputs.iter().any(|(c,_)|*c==goal.commodity) {return None;}
                    let (input,required)=recipe.inputs[0];
                    let market=snapshot.owned_markets.iter().find(|m|m.location_id==goal.destination_id)?;
                    let present=market.stock.get(input.as_str()).copied().unwrap_or(0.0);
                    if !present.is_finite() || present<0.0 || present>=f64::from(required) {return None;}
                    Some(GoalSpec{goal_id:format!("{}:ingredient:{}",goal.goal_id,input.as_str()),
                        destination_id:goal.destination_id.clone(),commodity:input,
                        target_units:required,priority:goal.priority})
                })
        } else {None};
        let (goap_goal,role)=match &intermediate {
            Some(subgoal)=>(subgoal,"htn_ingredient_subgoal_and_full_goal"),
            None=>(goal,"full_goal_alternative"),
        };
        trace.goap_role=role;
        // When HTN supplies an ingredient milestone, GOAP's allotted budget
        // is divided between that REAL subgoal and an independent full-goal
        // alternative. This allows direct supply to compete with a refinery.
        let ingredient_budget=if intermediate.is_some() {(goap_nodes/2).max(1)} else {goap_nodes};
        let partial_budget=SearchBudget{max_nodes:ingredient_budget,max_depth:budget.max_depth};
        let goap=TelicGoapAdapter.plan(snapshot,goap_goal,actions,partial_budget);
        trace.nodes_goap=goap.nodes_expanded;
        trace.goap_status=goap.status;
        if safe_candidate(snapshot,goap_goal,actions,&goap,partial_budget) {
            if intermediate.is_some() {
                if let Some(composed)=compose_ingredient_route(snapshot,goal,actions,&htn,&goap) {
                    if composed.steps.len()<=budget.max_depth &&
                        composed.nodes_expanded<=budget.max_nodes {
                        alternatives.push(("htn_plus_telic_goap",composed));
                    }
                }
            } else {
                alternatives.push(("telic_goap_fallback",goap));
            }
        }
        if intermediate.is_some() && goap_nodes>ingredient_budget {
            let full_budget=SearchBudget{max_nodes:goap_nodes-ingredient_budget,max_depth:budget.max_depth};
            let full=TelicGoapAdapter.plan(snapshot,goal,actions,full_budget);
            trace.nodes_goap=trace.nodes_goap.saturating_add(full.nodes_expanded);
            trace.goap_full_status=Some(full.status);
            if safe_candidate(snapshot,goal,actions,&full,full_budget) {
                alternatives.push(("telic_goap_direct",full));
            }
        }
        // Beam is not run on every faction or every tick: disagreement must
        // be material, or both structural options must fail.
        let disagreement=alternatives.first().is_some_and(|(_,first)|{
            alternatives.iter().skip(1).any(|(_,other)|first.steps.iter()
                .map(|s|&s.action_id).ne(other.steps.iter().map(|s|&s.action_id)))
        });
        let need_beam=alternatives.is_empty() || disagreement;
        if need_beam && beam_nodes>0 {
            trace.beam_reason=if alternatives.is_empty() {"no_valid_structural_plan"}
                else {"candidate_paths_disagree"};
            let beam_budget=SearchBudget{max_nodes:beam_nodes,max_depth:budget.max_depth};
            let beam=ControlBeamAdapter.plan(snapshot,goal,actions,beam_budget);
            trace.nodes_beam=beam.nodes_expanded;
            trace.beam_status=Some(beam.status);
            if safe_candidate(snapshot,goal,actions,&beam,beam_budget) {
                alternatives.push(("selective_beam",beam));
            }
        }
        let used=trace.nodes_htn.saturating_add(trace.nodes_goap).saturating_add(trace.nodes_beam);
        // Stable order on ties; no stochastic tests or hidden personal bias.
        // Prefer a successful HTN+GOAP cooperative decomposition at equal
        // forecast utility; otherwise use deterministic stable labels.
        let source_rank=|name:&str|match name {
            "htn_plus_telic_goap"=>0, "htn_decomposition"=>1,
            "telic_goap_direct"=>2, "telic_goap_fallback"=>3,
            "selective_beam"=>4, _=>5,
        };
        let selected=alternatives.into_iter().min_by(|(name_a,a),(name_b,b)|{
            score(a,actions,self.preferences).total_cmp(&score(b,actions,self.preferences))
                .then_with(||source_rank(name_a).cmp(&source_rank(name_b)))
        });
        let result=if let Some((source,mut plan))=selected {
            trace.selected_source=source.into();
            plan.nodes_expanded=used;
            plan.planner_id="hybrid_utility_htn_goap_beam".into();
            plan.explanation=format!("Utility goal; HTN={:?}; GOAP={} ({:?})/full={:?}; Beam={}; selected={source}; forecast only",
                trace.htn_status,trace.goap_role,trace.goap_status,
                trace.goap_full_status,trace.beam_reason);
            plan
        } else {
            let status=if [Some(trace.htn_status),Some(trace.goap_status),trace.goap_full_status,trace.beam_status]
                .into_iter().flatten().any(|s|s==PlanStatus::BudgetExhausted){
                PlanStatus::BudgetExhausted
            } else if [Some(trace.htn_status),Some(trace.goap_status),trace.goap_full_status,trace.beam_status]
                .into_iter().flatten().any(|s|s==PlanStatus::InvalidSnapshot){
                PlanStatus::InvalidSnapshot
            } else {PlanStatus::NoPlan};
            rejected(goal,status,used,"No valid HTN / GOAP / selective Beam path within shared budget")
        };
        HybridDecision{result,roles:trace}
    }
}
impl Planner for HybridPlanner {
    fn id(&self)->&'static str {"hybrid_utility_htn_goap_beam"}
    fn plan(&self,snapshot:&PlanningSnapshot,goal:&GoalSpec,
        actions:&[ActionSpec],budget:SearchBudget)->PlanResult {
        self.decide(snapshot,goal,actions,budget).result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::{FacilityEntry, MarketEntry, RecipeEntry, ShipEntry, SCHEMA_VERSION};
    use crate::economy::commodities::Commodity;
    use std::collections::BTreeMap;
    fn stock(id:&str,location:&str,commodity:Commodity,amount:f64)->MarketEntry{
        MarketEntry{market_id:id.into(),facility_id:format!("facility-{id}"),location_id:location.into(),
            stock:[(commodity.as_str().to_string(),amount)].into(),demand:BTreeMap::new(),prices:BTreeMap::new()}
    }
    fn fixture()->(PlanningSnapshot,GoalSpec,Vec<ActionSpec>){
        let s=PlanningSnapshot{schema_version:SCHEMA_VERSION,tick:100,faction_id:"f".into(),
            treasury_credits:30_000,treasury_floor_credits:10_000,
            owned_markets:vec![stock("belt","belt",Commodity::Ice,8.0),stock("refinery","colony",Commodity::Water,0.0)],
            facilities:vec![FacilityEntry{facility_id:"facility-refinery".into(),location_id:"colony".into(),facility_type:"refinery".into()}],
            ships:vec![ShipEntry{ship_id:"ship".into(),class:"courier".into(),location_id:Some("belt".into()),
                in_transit:false,free_cargo:20,fuel:100.0}],active_commitments:vec![],technologies:vec![],
            recipes:vec![RecipeEntry{recipe_id:"ice".into(),facility_type:"refinery".into(),
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10)]}]};
        let goal=GoalSpec{goal_id:"water".into(),destination_id:"colony".into(),commodity:Commodity::Water,
            target_units:10,priority:100};
        let actions=vec![
            ActionSpec{action_id:"deliver-ice".into(),kind:ActionKind::Deliver,source_id:Some("belt".into()),
                destination_id:"colony".into(),commodity:Some(Commodity::Ice),units:8,cost_credits:200,
                expected_ticks:80,inputs:vec![],outputs:vec![],required_facility_type:None},
            ActionSpec{action_id:"refine".into(),kind:ActionKind::Produce,source_id:None,destination_id:"colony".into(),
                commodity:Some(Commodity::Water),units:10,cost_credits:100,expected_ticks:40,
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10)],
                required_facility_type:Some("refinery".into())}];
        (s,goal,actions)
    }
    #[test]
    fn htn_decomposes_then_goap_can_supply_a_real_ingredient(){
        let (s,g,a)=fixture();
        let before=serde_json::to_vec(&s).unwrap();
        let result=HybridPlanner::default().decide(&s,&g,&a,SearchBudget::default());
        assert_eq!(result.result.status,PlanStatus::Ready,"{}",result.result.explanation);
        assert_eq!(result.roles.goap_role,"htn_ingredient_subgoal_and_full_goal");
        assert_eq!(result.roles.selected_source,"htn_plus_telic_goap");
        assert!(result.roles.beam_status.is_none());
        assert_eq!(result.roles.goap_full_status,Some(PlanStatus::Ready));
        assert_eq!(result.result.steps.iter().map(|x|x.action_id.as_str()).collect::<Vec<_>>(),vec!["deliver-ice","refine"]);
        assert!(safe_candidate(&s,&g,&a,&result.result,SearchBudget::default()));
        assert_eq!(before,serde_json::to_vec(&s).unwrap());
    }
    #[test]
    fn empty_source_never_creates_ice(){
        let (mut s,g,a)=fixture();
        s.owned_markets[0].stock.insert("ice".into(),0.0);
        let result=HybridPlanner::default().decide(&s,&g,&a,SearchBudget::default());
        assert_ne!(result.result.status,PlanStatus::Ready);
    }
    #[test]
    fn shared_budget_is_not_counted_three_times(){
        let (s,g,a)=fixture();
        let budget=SearchBudget{max_nodes:15,max_depth:12};
        let result=HybridPlanner::default().decide(&s,&g,&a,budget);
        assert!(result.result.nodes_expanded<=15);
        if result.result.status==PlanStatus::Ready {
            assert!(safe_candidate(&s,&g,&a,&result.result,budget));
        }
    }
    #[test]
    fn multiple_markets_are_not_combined(){
        let (mut s,g,a)=fixture();
        s.owned_markets.push(stock("another","colony",Commodity::Water,100.0));
        let result=HybridPlanner::default().decide(&s,&g,&a,SearchBudget::default());
        assert_ne!(result.result.status,PlanStatus::Ready);
    }
    #[test]
    fn preferences_are_bounded_even_if_loaded_profile_is_corrupt(){
        let p=HybridPreferences{cost_weight:f64::NAN,speed_weight:f64::INFINITY,caution_weight:-8.0}.bounded();
        assert_eq!(p,HybridPreferences{cost_weight:1.0,speed_weight:1.0,caution_weight:0.1});
    }
    #[test]
    fn personality_weights_change_choice_between_price_and_speed(){
        let (s,g,a)=fixture();
        let mut cheap=HybridPlanner::default().plan(&s,&g,&a,SearchBudget::default());
        cheap.forecast_credits=400;
        cheap.forecast_ticks=600;
        let mut fast=cheap.clone();
        fast.forecast_credits=7_000;
        fast.forecast_ticks=50;
        let economist=HybridPreferences{cost_weight:4.0,speed_weight:0.2,caution_weight:0.5};
        let urgent=HybridPreferences{cost_weight:0.2,speed_weight:5.0,caution_weight:0.5};
        assert!(score(&cheap,&a,economist)<score(&fast,&a,economist));
        assert!(score(&fast,&a,urgent)<score(&cheap,&a,urgent));
    }
    #[test]
    fn dispatcher_cannot_be_justified_by_a_forged_output(){
        let (s,g,a)=fixture();
        let mut bogus=HybridPlanner::default().plan(&s,&g,&a,SearchBudget::default());
        assert_eq!(bogus.status,PlanStatus::Ready);
        bogus.steps[0].action_id="magic-ice".into();
        assert!(!safe_candidate(&s,&g,&a,&bogus,SearchBudget::default()));
    }
}
