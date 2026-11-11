//! Durable, receipt-driven plan state. the opt-in HTN
//! driver now uses this ledger, while the default game director stays unchanged. Native ECS orders remain the sole authority.
//!
//! Exactly-once submission cannot be inferred from memory alone: a crash may
//! happen after creating a native order but before acknowledging it here.
//! Such a `Prepared` step MUST be reconciled against native orders using the
//! stable dispatch key. It must NEVER be blindly issued a second time.

use serde::{Deserialize, Serialize};

use super::{
    dispatch_key, validate_plan, ExecutionReceipt, GoalSpec, PlanResult, PlanStatus,
    PlanStep, PlanningSnapshot, ReceiptStatus, SearchBudget, ValidationError,
    ActionSpec, SCHEMA_VERSION,
};

/// The plan is deliberately sequential at this first integration stage:
/// at most one native order can be prepared at a time per faction.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepPhase {
    Planned,
    Prepared,
    Submitted,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StepRecord {
    pub step: PlanStep,
    pub dispatch_key: String,
    pub phase: StepPhase,
    pub native_order_id: Option<String>,
    pub updated_tick: u64,
    pub reason_code: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanLedger {
    pub schema_version: u32,
    pub faction_id: String,
    pub plan_id: String,
    pub goal_id: String,
    pub planner_id: String,
    pub created_tick: u64,
    pub snapshot_tick: u64,
    pub steps: Vec<StepRecord>,
}

/// This is a REQUEST to dispatch, not a successful submission.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PlanGate {
    Ready { step_id: String, dispatch_key: String, action_id: String },
    /// A native order might already have been issued; lookup by key is required.
    ReconcilePrepared { step_id: String, dispatch_key: String },
    AwaitNative { step_id: String, native_order_id: String },
    AwaitDependencies { step_id: String },
    NeedsReplan { step_id: String, reason_code: String },
    Completed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LedgerError {
    InvalidPlan(ValidationError),
    NotReady,
    InvalidPlanId,
    WrongFaction,
    UnknownStep,
    WrongPlan,
    WrongDispatchKey,
    InvalidNativeOrder,
    ConflictingOrder,
    InvalidTransition,
    TickMovedBackwards,
}

impl PlanLedger {
    /// Make a new durable plan after validating a proposal on its own snapshot.
    /// This does NOT check the live market, fund a contract or dispatch a ship.
    pub fn from_proposal(
        snapshot: &PlanningSnapshot,
        goal: &GoalSpec,
        actions: &[ActionSpec],
        result: &PlanResult,
        budget: SearchBudget,
        plan_id: &str,
    ) -> Result<Self, LedgerError> {
        validate_plan(snapshot, goal, actions, result, budget)
            .map_err(LedgerError::InvalidPlan)?;
        if result.status != PlanStatus::Ready { return Err(LedgerError::NotReady); }
        if plan_id.is_empty() { return Err(LedgerError::InvalidPlanId); }
        let records = result.steps.iter().cloned().map(|step| StepRecord {
            dispatch_key: dispatch_key(&snapshot.faction_id, plan_id, &step.step_id),
            step,
            phase: StepPhase::Planned,
            native_order_id: None,
            updated_tick: snapshot.tick,
            reason_code: None,
        }).collect();
        Ok(Self {
            schema_version: SCHEMA_VERSION,
            faction_id: snapshot.faction_id.clone(),
            plan_id: plan_id.to_string(),
            goal_id: goal.goal_id.clone(),
            planner_id: result.planner_id.clone(),
            created_tick: snapshot.tick,
            snapshot_tick: snapshot.tick,
            steps: records,
        })
    }

    /// Returns the next safe *intention*. It never checks the live ECS: the
    /// native dispatcher must revalidate affordability, sources and permits.
    pub fn next(&self) -> PlanGate {
        for (i, entry) in self.steps.iter().enumerate() {
            match entry.phase {
                StepPhase::Succeeded => continue,
                StepPhase::Failed | StepPhase::Cancelled => return PlanGate::NeedsReplan {
                    step_id: entry.step.step_id.clone(),
                    reason_code: entry.reason_code.clone().unwrap_or_else(|| "native_execution_failed".into()),
                },
                StepPhase::Prepared => return PlanGate::ReconcilePrepared {
                    step_id: entry.step.step_id.clone(),
                    dispatch_key: entry.dispatch_key.clone(),
                },
                StepPhase::Submitted | StepPhase::Running => return PlanGate::AwaitNative {
                    step_id: entry.step.step_id.clone(),
                    native_order_id: entry.native_order_id.clone().unwrap_or_default(),
                },
                StepPhase::Planned => {
                    let ready = entry.step.depends_on.iter().all(|dep| {
                        self.steps[..i].iter().any(|prior| {
                            prior.step.step_id == *dep && prior.phase == StepPhase::Succeeded
                        })
                    });
                    return if ready { PlanGate::Ready {
                        step_id: entry.step.step_id.clone(),
                        dispatch_key: entry.dispatch_key.clone(),
                        action_id: entry.step.action_id.clone(),
                    }} else { PlanGate::AwaitDependencies { step_id: entry.step.step_id.clone() } };
                }
            }
        }
        PlanGate::Completed
    }

    /// Persist this Prepared transition BEFORE invoking a native order. If the
    /// process crashes after dispatch, a restart must reconcile by key.
    pub fn prepare(&mut self, step_id: &str, tick: u64) -> Result<&str, LedgerError> {
        let PlanGate::Ready { step_id: ready, .. } = self.next() else {
            return Err(LedgerError::NotReady);
        };
        if ready != step_id { return Err(LedgerError::NotReady); }
        let step = self.steps.iter_mut().find(|s| s.step.step_id == step_id)
            .ok_or(LedgerError::UnknownStep)?;
        if tick < step.updated_tick { return Err(LedgerError::TickMovedBackwards); }
        step.phase = StepPhase::Prepared;
        step.updated_tick = tick;
        Ok(&step.dispatch_key)
    }

    /// Persist a native order ID once the dispatcher has established it.
    /// Repeating the exact same acknowledgement is safe; changing IDs isn't.
    pub fn acknowledge_native_order(
        &mut self, step_id: &str, key: &str, native_order_id: &str, tick: u64,
    ) -> Result<(), LedgerError> {
        if native_order_id.is_empty() { return Err(LedgerError::InvalidNativeOrder); }
        let step = self.steps.iter_mut().find(|s| s.step.step_id == step_id)
            .ok_or(LedgerError::UnknownStep)?;
        if step.dispatch_key != key { return Err(LedgerError::WrongDispatchKey); }
        if tick < step.updated_tick { return Err(LedgerError::TickMovedBackwards); }
        if let Some(existing) = &step.native_order_id {
            return if existing == native_order_id { Ok(()) } else { Err(LedgerError::ConflictingOrder) };
        }
        if step.phase != StepPhase::Prepared { return Err(LedgerError::InvalidTransition); }
        step.native_order_id = Some(native_order_id.into());
        step.phase = StepPhase::Submitted;
        step.updated_tick = tick;
        Ok(())
    }

    /// Record verified native order status, not forecasts, logs, or planned effects.
    /// Terminal success/failure is never silently overwritten by a later event.
    pub fn apply_receipt(&mut self, receipt: &ExecutionReceipt) -> Result<(), LedgerError> {
        if receipt.plan_id != self.plan_id { return Err(LedgerError::WrongPlan); }
        let step = self.steps.iter_mut().find(|s| s.step.step_id == receipt.step_id)
            .ok_or(LedgerError::UnknownStep)?;
        if receipt.tick < step.updated_tick { return Err(LedgerError::TickMovedBackwards); }
        let Some(native_id) = &step.native_order_id else { return Err(LedgerError::InvalidNativeOrder); };
        if receipt.native_order_id.as_deref() != Some(native_id.as_str()) {
            return Err(LedgerError::ConflictingOrder);
        }
        let incoming = match receipt.status {
            ReceiptStatus::Submitted => StepPhase::Submitted,
            ReceiptStatus::Running => StepPhase::Running,
            ReceiptStatus::Succeeded => StepPhase::Succeeded,
            ReceiptStatus::Failed => StepPhase::Failed,
            ReceiptStatus::Cancelled => StepPhase::Cancelled,
        };
        let permitted = match (step.phase, incoming) {
            (StepPhase::Submitted, StepPhase::Submitted | StepPhase::Running | StepPhase::Succeeded | StepPhase::Failed | StepPhase::Cancelled)
            | (StepPhase::Running, StepPhase::Running | StepPhase::Succeeded | StepPhase::Failed | StepPhase::Cancelled)
            | (StepPhase::Succeeded, StepPhase::Succeeded)
            | (StepPhase::Failed, StepPhase::Failed)
            | (StepPhase::Cancelled, StepPhase::Cancelled) => true,
            _ => false,
        };
        if !permitted { return Err(LedgerError::InvalidTransition); }
        step.phase = incoming;
        step.reason_code = Some(receipt.reason_code.clone());
        step.updated_tick = receipt.tick;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::economy::commodities::Commodity;
    use super::super::{ActionKind, MarketEntry};

    fn fixture() -> (PlanningSnapshot, GoalSpec, Vec<ActionSpec>, PlanResult) {
        let snapshot = PlanningSnapshot {
            schema_version: SCHEMA_VERSION, tick: 100, faction_id: "f1".into(),
            treasury_credits: 10_000, treasury_floor_credits: 5_000,
            owned_markets: Vec::<MarketEntry>::new(), facilities: vec![], ships: vec![],
            active_commitments: vec![], technologies: vec![], recipes: vec![],
        };
        let goal = GoalSpec { goal_id: "water".into(), destination_id: "colony".into(),
            commodity: Commodity::Water, target_units: 10, priority: 10 };
        let actions = ["ice", "refine"].iter().map(|id| ActionSpec {
            action_id: (*id).into(), kind: ActionKind::Produce,
            source_id: None, destination_id: "colony".into(),
            commodity: Some(Commodity::Water), units: 10, cost_credits: 10,
            expected_ticks: 20, inputs: vec![], outputs: vec![], required_facility_type: None,
        }).collect();
        let plan = PlanResult { status: PlanStatus::Ready, goal_id: goal.goal_id.clone(),
            planner_id: "htn".into(), nodes_expanded: 2, forecast_credits: 20,
            forecast_ticks: 40, explanation: "fixture".into(),
            steps: vec![PlanStep { step_id: "s1".into(), action_id: "ice".into(),
                depends_on: vec![], expected_condition: "native_receipt".into() },
                PlanStep { step_id: "s2".into(), action_id: "refine".into(),
                    depends_on: vec!["s1".into()], expected_condition: "native_receipt".into() }],
        };
        (snapshot, goal, actions, plan)
    }

    #[test]
    fn restart_never_resubmits_prepared_step() {
        let (snapshot, goal, actions, plan) = fixture();
        let mut ledger = PlanLedger::from_proposal(&snapshot, &goal, &actions,
            &plan, SearchBudget::default(), "p1").unwrap();
        assert!(matches!(ledger.next(), PlanGate::Ready { .. }));
        ledger.prepare("s1", 101).unwrap();
        let restored: PlanLedger = serde_json::from_str(&serde_json::to_string(&ledger).unwrap()).unwrap();
        assert!(matches!(restored.next(), PlanGate::ReconcilePrepared { .. }));
    }

    #[test]
    fn success_requires_real_receipt() {
        let (snapshot, goal, actions, plan) = fixture();
        let mut ledger = PlanLedger::from_proposal(&snapshot, &goal, &actions,
            &plan, SearchBudget::default(), "p1").unwrap();
        let key = ledger.prepare("s1", 101).unwrap().to_string();
        assert!(matches!(ledger.next(), PlanGate::ReconcilePrepared { .. }));
        ledger.acknowledge_native_order("s1", &key, "native:c1", 102).unwrap();
        assert!(matches!(ledger.next(), PlanGate::AwaitNative { .. }));
        ledger.apply_receipt(&ExecutionReceipt { plan_id: "p1".into(), step_id: "s1".into(),
            native_order_id: Some("native:c1".into()), status: ReceiptStatus::Succeeded,
            tick: 105, reason_code: "delivered".into() }).unwrap();
        assert!(matches!(ledger.next(), PlanGate::Ready { step_id, .. } if step_id == "s2"));
    }

    #[test]
    fn conflicting_native_order_is_rejected() {
        let (snapshot, goal, actions, plan) = fixture();
        let mut ledger = PlanLedger::from_proposal(&snapshot, &goal, &actions,
            &plan, SearchBudget::default(), "p1").unwrap();
        let key = ledger.prepare("s1", 101).unwrap().to_string();
        ledger.acknowledge_native_order("s1", &key, "native:c1", 102).unwrap();
        assert_eq!(ledger.acknowledge_native_order("s1", &key, "native:c2", 103), Err(LedgerError::ConflictingOrder));
    }
}
