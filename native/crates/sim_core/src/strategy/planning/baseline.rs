//! Read-only bridge from the existing Genesis head decision to the common
//! planner contract. This is a DIAGNOSTIC adapter: it never dispatches orders.
//!
//! Only alternatives already evaluated as `ready` by the native coordinator
//! can enter the catalogue. These are immediate native *first steps*, not a
//! claim that a long construction/research/production chain is feasible.

use super::{
    validate_plan, ActionKind, ActionSpec, ContractBoard, GoalSpec, PlanResult,
    PlanStatus, PlanStep, Planner, PlanningSnapshot, SearchBudget,
};
use crate::agents::faction;
use crate::strategy::coordination::HeadDecision;
use bevy_ecs::prelude::World;
use serde::Serialize;

#[derive(Clone, Debug, Serialize)]
pub struct ShadowTrace {
    /// Never mistake this diagnostic for an executed or funded native order.
    pub mode: &'static str,
    pub snapshot_tick: u64,
    pub faction_id: String,
    pub selected_native_action: String,
    pub catalogue_size: usize,
    pub goal_id: Option<String>,
    pub status: String,
    pub validation: String,
    pub proposal: Option<PlanResult>,
    /// HTN over a separate, conservative subset of actual owned market data.
    /// Not an executable native dispatch and not proof of a successful chain.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub htn: Option<super::HtnNativeShadow>,
    /// Expensive multi-planner shadow only when explicitly requested.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planner_comparison: Option<super::PlannerComparison>,
}

/// The current Genesis director is the baseline. It selects an action before
/// this adapter runs; this adapter only expresses it in the common contract.
pub struct BaselineAdapter {
    pub selected_action_id: Option<String>,
}

impl Planner for BaselineAdapter {
    fn id(&self) -> &'static str { "genesis_baseline" }

    fn plan(&self, _snapshot: &PlanningSnapshot, goal: &GoalSpec,
            actions: &[ActionSpec], budget: SearchBudget) -> PlanResult {
        let selected = self.selected_action_id.as_ref()
            .and_then(|id| actions.iter().find(|action| action.action_id == *id));
        let status = if budget.max_nodes == 0 || budget.max_depth == 0 {
            PlanStatus::BudgetExhausted
        } else if selected.is_some() { PlanStatus::Ready } else { PlanStatus::NoPlan };
        let steps = if status == PlanStatus::Ready {
            selected.map(|action| vec![PlanStep {
                step_id: "native-first-step".into(),
                action_id: action.action_id.clone(),
                depends_on: Vec::new(),
                expected_condition: "await_native_execution_receipt".into(),
            }]).unwrap_or_default()
        } else { Vec::new() };
        PlanResult {
            status,
            goal_id: goal.goal_id.clone(),
            planner_id: self.id().into(),
            steps,
            // These are quotes for the *first native action*, NOT the total
            // cost or duration of an entire production chain.
            forecast_credits: if status == PlanStatus::Ready { selected.map_or(0, |a| a.cost_credits) } else { 0 },
            forecast_ticks: if status == PlanStatus::Ready { selected.map_or(0, |a| a.expected_ticks) } else { 0 },
            nodes_expanded: if status == PlanStatus::Ready { 1 } else { 0 },
            explanation: "Legacy Genesis selection, read-only projection; no dispatch".into(),
        }
    }
}

/// Map a selected native shortage into a faction-scoped planning goal.
pub fn goal_from_head(head: &HeadDecision) -> Option<GoalSpec> {
    let problem = head.problem.as_ref()?;
    Some(GoalSpec {
        goal_id: format!("{}:{}:{}", problem.goal_id, problem.destination, problem.commodity.as_str()),
        destination_id: problem.destination.clone(),
        commodity: problem.commodity,
        target_units: faction::SUBSIDY_QUANTITY,
        priority: problem.score.max(0.0).min(u32::MAX as f32) as u32,
    })
}

/// A catalogue of the native, immediately ready first actions for one goal.
/// Never assume the selected option is ready merely because it has a name.
pub fn native_first_actions(head: &HeadDecision) -> Vec<ActionSpec> {
    let Some(problem) = head.problem.as_ref() else { return Vec::new() };
    let mut actions = Vec::new();
    for option in &head.alternatives {
        if option.status != "ready" || option.first_payment < 0 { continue; }
        let (kind, commodity, units) = match option.action {
            "deliver" if option.source.is_some() => (
                ActionKind::Deliver, Some(problem.commodity), faction::SUBSIDY_QUANTITY,
            ),
            "build" => (
                ActionKind::Construct, option.material, faction::CONSTRUCTION_QUANTITY,
            ),
            _ => continue,
        };
        actions.push(ActionSpec {
            action_id: format!("native:{}:{}:{}:{}", option.action,
                problem.destination, problem.commodity.as_str(),
                option.site_id.as_deref().or(option.source.as_deref()).unwrap_or("new")),
            kind,
            source_id: option.source.clone(),
            destination_id: problem.destination.clone(),
            commodity,
            units,
            // This is the native *first payment*, not an entire project's
            // total commitment; no fund reservation happens in this adapter.
            cost_credits: option.first_payment,
            expected_ticks: option.estimated_delay_ticks,
            inputs: Vec::new(),
            outputs: Vec::new(),
            required_facility_type: None,
        });
    }
    actions.sort_by(|a, b| a.action_id.cmp(&b.action_id));
    actions.dedup_by(|a, b| a.action_id == b.action_id);
    actions
}

/// Explicit opt-in. Disabled by default so ordinary Galaxy 0.2 behaviour and
/// performance remain unchanged until a new build is validated.
pub fn shadow_enabled() -> bool {
    std::env::var("LIVING_SECTOR_PLANNER_SHADOW")
        .is_ok_and(|value| value == "1" || value.eq_ignore_ascii_case("true"))
}

/// Read the actual ECS, then describe what Genesis already selected. It is
/// explicitly NOT a candidate/dispatch path and must not change RNG or World.
pub fn native_decision_shadow(
    world: &mut World, board: &ContractBoard, tick: u64,
    faction_id: &str, head: &HeadDecision,
) -> ShadowTrace {
    let mut trace = ShadowTrace {
        mode: "diagnostic_only", snapshot_tick: tick, faction_id: faction_id.into(),
        selected_native_action: head.selected_option.into(), catalogue_size: 0,
        goal_id: None, status: "unavailable".into(),
        validation: "not_run".into(), proposal: None, htn: None, planner_comparison: None,
    };
    let snapshot = match PlanningSnapshot::capture(world, board, tick, faction_id) {
        Ok(snapshot) => snapshot,
        Err(reason) => { trace.status = reason.into(); return trace; }
    };
    let Some(goal) = goal_from_head(head) else {
        trace.status = "no_shortage_goal_for_native_choice".into();
        return trace;
    };
    trace.goal_id = Some(goal.goal_id.clone());
    // Observe the same shortage as the native director; HTN evaluates a small
    // physical-stock increment, NOT the full funded subsidy of 200 units.
    trace.htn = Some(super::htn_native_shadow(&snapshot, &goal));
    if std::env::var("LIVING_SECTOR_PLANNER_COMPARE").as_deref() == Ok("1") {
        if let Ok((projected,actions,actual_goal)) =
            super::native_catalogue::comparison_case(&snapshot,&goal) {
            trace.planner_comparison=Some(super::compare_planners(
                &projected,&actual_goal,&actions,
                SearchBudget{max_nodes:350,max_depth:12}));
        }
    }
    let actions = native_first_actions(head);
    trace.catalogue_size = actions.len();
    let selected = actions.iter().find(|action| {
        (head.selected_option == "deliver" && action.kind == ActionKind::Deliver)
        || (head.selected_option == "build" && action.kind == ActionKind::Construct)
    }).map(|action| action.action_id.clone());
    let baseline = BaselineAdapter { selected_action_id: selected };
    let budget = SearchBudget::default();
    let proposal = baseline.plan(&snapshot, &goal, &actions, budget);
    let validation = validate_plan(&snapshot, &goal, &actions, &proposal, budget);
    trace.validation = match validation {
        Ok(()) => "valid".into(),
        Err(error) => format!("rejected:{error:?}"),
    };
    trace.status = match proposal.status {
        PlanStatus::Ready if validation.is_ok() => "projected_first_step".into(),
        PlanStatus::Ready => "blocked_by_validator".into(),
        PlanStatus::NoPlan => "no_equivalent_first_step".into(),
        PlanStatus::BudgetExhausted => "search_budget_exhausted".into(),
        PlanStatus::InvalidSnapshot => "invalid_snapshot".into(),
    };
    trace.proposal = Some(proposal);
    trace
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::{SCHEMA_VERSION, ValidationError};
    use crate::economy::commodities::Commodity;

    fn snapshot() -> PlanningSnapshot {
        PlanningSnapshot {
            schema_version: SCHEMA_VERSION, tick: 42, faction_id: "faction".into(),
            treasury_credits: 8_000, treasury_floor_credits: 5_000,
            owned_markets: vec![], facilities: vec![], ships: vec![],
            active_commitments: vec![], technologies: vec![], recipes: vec![],
        }
    }
    fn goal() -> GoalSpec {
        GoalSpec { goal_id:"sustain:colony:water".into(), destination_id:"colony".into(),
            commodity:Commodity::Water, target_units: 20, priority: 100 }
    }
    fn delivery() -> ActionSpec {
        ActionSpec {
            action_id:"native:deliver:colony:water:ice-field".into(), kind:ActionKind::Deliver,
            source_id:Some("ice-field".into()), destination_id:"colony".into(),
            commodity:Some(Commodity::Water), units:20, cost_credits:1_600,
            expected_ticks:120, inputs:vec![], outputs:vec![], required_facility_type:None,
        }
    }
    #[test]
    fn baseline_projection_uses_shared_contract() {
        let snap=snapshot();let goal=goal();let action=delivery();
        let baseline=BaselineAdapter{selected_action_id:Some(action.action_id.clone())};
        let result=baseline.plan(&snap,&goal,&[action.clone()],SearchBudget::default());
        assert_eq!(result.status,PlanStatus::Ready);
        assert_eq!(result.steps[0].action_id,action.action_id);
        assert_eq!(validate_plan(&snap,&goal,&[action],&result,SearchBudget::default()),Ok(()));
        assert_eq!(result.planner_id,"genesis_baseline");
    }
    #[test]
    fn baseline_cannot_invent_unavailable_action() {
        let snap=snapshot();let goal=goal();
        let baseline=BaselineAdapter{selected_action_id:Some("nonexistent".into())};
        let result=baseline.plan(&snap,&goal,&[],SearchBudget::default());
        assert_eq!(result.status,PlanStatus::NoPlan);
        assert!(result.steps.is_empty());
        assert_eq!(validate_plan(&snap,&goal,&[],&result,SearchBudget::default()),Ok(()));
    }
    #[test]
    fn oversized_cost_is_rejected_by_shared_validator() {
        let mut expensive=delivery();expensive.cost_credits=4_000;
        let snap=snapshot();let goal=goal();
        let baseline=BaselineAdapter{selected_action_id:Some(expensive.action_id.clone())};
        let result=baseline.plan(&snap,&goal,&[expensive.clone()],SearchBudget::default());
        assert_eq!(validate_plan(&snap,&goal,&[expensive],&result,SearchBudget::default()),
            Err(ValidationError::SpendExceedsTreasury));
    }
}
