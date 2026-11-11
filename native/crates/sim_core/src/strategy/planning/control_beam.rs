//! Pure Control Beam baseline on the same projected native state transitions.
//! Unlike Telic-guided best-first, Beam limits the number of states kept at
//! each level; it may fail even when a valid longer/less obvious path exists.

use super::{ActionSpec, GoalSpec, Planner, PlanningSnapshot, PlanResult,PlanStatus,SearchBudget};
use super::htn_adapter::domain_from_native;
use super::forward_search::{no_result,path_result,search,SearchMode};

pub struct ControlBeamAdapter;

impl Planner for ControlBeamAdapter {
    fn id(&self)->&'static str {"control_beam_native"}

    fn plan(&self,snapshot:&PlanningSnapshot,goal:&GoalSpec,
        actions:&[ActionSpec],budget:SearchBudget)->PlanResult {
        if budget.max_nodes==0 || budget.max_depth==0 {
            return no_result(self.id(),goal,PlanStatus::BudgetExhausted,0,"search budget is zero");
        }
        let Ok(domain)=domain_from_native(snapshot,goal,actions) else {
            return no_result(self.id(),goal,PlanStatus::InvalidSnapshot,0,"unsafe native projection");
        };
        if domain.initial[domain.goal_field]>=domain.goal_amount {
            return no_result(self.id(),goal,PlanStatus::NoPlan,0,"goal already reached");
        }
        let outcome=search(&domain,actions,budget,SearchMode::Beam{width:16},&[]);
        match outcome.path {
            Some(path)=>path_result(self.id(),goal,actions,&domain,path,outcome.nodes_expanded,
                "Beam width 16 over exactly the same projected stock/cash actions as HTN and GOAP"),
            None=>no_result(self.id(),goal,
                if outcome.exhausted {PlanStatus::BudgetExhausted} else {PlanStatus::NoPlan},
                outcome.nodes_expanded,"No stock-feasible Beam plan within width/depth/node budget"),
        }
    }
}
