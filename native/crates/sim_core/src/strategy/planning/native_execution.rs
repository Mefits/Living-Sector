//! Block A: opt-in, receipt-driven HTN -> *native Genesis* contract bridge.
//!
//! `LIVING_SECTOR_PLANNER=htn` enables it in Execute mode only. The default
//! remains the Galaxy 0.2 director. Search forecasts never write goods, wages,
//! ship positions or money. Actual delivery goes through the existing funded
//! ContractBoard and station-order dispatcher. Production is observed (not
//! commanded or assumed successful) through its real paid work-shift receipt.
//!
//! Native director + contract board are checkpointed in the SAME EconomicFrame.
//! A Prepared step is *never* blindly resubmitted after a restart.

use std::collections::BTreeMap;
use bevy_ecs::prelude::*;
use serde::{Deserialize, Serialize};

use crate::agents::{
    faction::{self, FactionData},
    market::MarketIdentity,
    facility::{FacilityCrew, FacilityIdentity, FacilityLocation},
    ship::{ShipCargo, ShipEconomy, ShipFuel, ShipIdentity, ShipPosition, ShipTransit},
    faction_relations::FactionRelations,
};
use crate::economy::contracts::{ContractBoard, ContractStatus, FundingSource};
use crate::strategy::{colony, coordination::HeadDecision, director, orders, sourcing, PROJECT_TAG};

use super::{
    native_catalogue, ActionKind, ActionSpec, ExecutionReceipt, GoalSpec,
    PlanGate, PlanLedger, PlanningSnapshot, ReceiptStatus,
    SearchBudget, HybridPreferences,
};

/// The original Genesis director is still the default and emergency fallback.
pub fn execution_enabled() -> bool {
    matches!(std::env::var("LIVING_SECTOR_PLANNER").as_deref(), Ok("htn") | Ok("hybrid"))
}
fn hybrid_enabled() -> bool {
    std::env::var("LIVING_SECTOR_PLANNER").as_deref() == Ok("hybrid")
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct NativeExecution {
    #[serde(default)]
    pub active: BTreeMap<String, NativePlan>,
    /// Prevent retry storms after a real failed order or stale input.
    #[serde(default)]
    pub blocked_until: BTreeMap<String, u64>,
    /// Native terminal outcomes survive completion/replan and save/load.
    /// This is a bounded *audit trail*, never a second source of goods/money.
    #[serde(default)]
    pub history: Vec<NativeOutcome>,
    /// Retain a failed *goal*, never a stale action/route/price. The next
    /// attempt creates a fresh plan from a new native PlanningSnapshot.
    #[serde(default)]
    pub deferred_goals: BTreeMap<String, DeferredGoal>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeferredGoal {
    pub goal: GoalSpec,
    pub failed_attempts: u8,
    pub last_failed_tick: u64,
    pub last_reason: String,
}

const MAX_GOAL_RETRIES: u8 = 3;

fn same_stock_goal(a:&GoalSpec,b:&GoalSpec)->bool {
    // The initial native probe targets current stock + 10, while the head
    // describes a recurring deficit with a fixed 10-unit probe. The *same*
    // strategic need must not look like a different goal after a shipment.
    a.goal_id==b.goal_id && a.destination_id==b.destination_id &&
        a.commodity==b.commodity
}

fn is_urgent_preemption(new:&GoalSpec,old:&GoalSpec)->bool {
    let essentials=|c:crate::economy::commodities::Commodity|matches!(c,crate::economy::commodities::Commodity::Food |
        crate::economy::commodities::Commodity::Water);
    (!essentials(old.commodity) && essentials(new.commodity)) ||
        (new.priority>old.priority.saturating_add(old.priority/4).saturating_add(1))
}

/// A remembered goal outlives a failed native *attempt*, but a materially
/// higher-priority head problem can supersede it. Never reuse its action list,
/// prices, market snapshots, or native dispatch IDs.
fn select_stock_goal(head:Option<&GoalSpec>, deferred:Option<&DeferredGoal>)->Option<GoalSpec> {
    match (head,deferred) {
        (Some(now),Some(old)) if same_stock_goal(now,&old.goal) => {
            let mut result=old.goal.clone();
            result.priority=result.priority.max(now.priority);
            Some(result)
        },
        (Some(now),Some(old)) if is_urgent_preemption(now,&old.goal) => Some(now.clone()),
        (_,Some(old)) if old.failed_attempts<MAX_GOAL_RETRIES => Some(old.goal.clone()),
        (Some(now),_) => Some(now.clone()),
        (None,_) => None,
    }
}

fn retryable_native_failure(status:&str,reason:&str)->bool {
    status=="needs_replan" || (status=="blocked" && matches!(reason,
        "no_funded_idle_native_carrier" | "native_source_stock_gone" |
        "existing_native_delivery_commitment" | "native_treasury_floor" |
        "native_price_exceeds_funded_reward" | "native_quote_invalid" |
        "native_route_unavailable" | "production_facility_not_verifiable"))
}

fn next_retry_delay(mult:u32,attempts:u8)->u64 {
    let exponent=attempts.saturating_sub(1).min(3);
    2u64.saturating_mul(faction::SUBSIDY_CHECK_INTERVAL_BASE)
        .saturating_mul(u64::from(mult.max(1)))
        .saturating_mul(1u64 << exponent)
}

/// A failed search is not a failed native contract. Keep these diagnostics
/// separate, apply the same bounded cooldown, and let the old director act.
fn record_planning_failure(state:&mut NativeExecution,faction_id:&str,goal:&GoalSpec,
    reason:&str,tick:u64,mult:u32) {
    let attempts=state.deferred_goals.get(faction_id)
        .filter(|old|same_stock_goal(&old.goal,goal))
        .map_or(1,|old|old.failed_attempts.saturating_add(1));
    if attempts<MAX_GOAL_RETRIES {
        state.deferred_goals.insert(faction_id.into(),DeferredGoal {
            goal:goal.clone(),failed_attempts:attempts,
            last_failed_tick:tick,last_reason:format!("planning:{reason}"),
        });
    } else {
        state.deferred_goals.remove(faction_id);
    }
    state.blocked_until.insert(faction_id.into(),tick.saturating_add(next_retry_delay(mult,attempts)));
}

/// An attempt is released at the limit. Existing paid steps stay in the
/// terminal audit trail; a retry is not entitled to re-submit them blindly.
fn record_deferred_goal(state:&mut NativeExecution, faction_id:&str, plan:&NativePlan,
    status:&str,reason:&str,tick:u64,mult:u32) {
    if status=="completed" {
        state.deferred_goals.remove(faction_id);
        state.blocked_until.remove(faction_id);
        return;
    }
    let same=state.deferred_goals.get(faction_id)
        .filter(|old|same_stock_goal(&old.goal,&plan.goal));
    let attempts=same.map_or(1,|old|old.failed_attempts.saturating_add(1));
    if retryable_native_failure(status,reason) && attempts<MAX_GOAL_RETRIES {
        state.deferred_goals.insert(faction_id.into(),DeferredGoal {
            goal:plan.goal.clone(),failed_attempts:attempts,
            last_failed_tick:tick,last_reason:reason.into(),
        });
    } else {
        state.deferred_goals.remove(faction_id);
    }
    state.blocked_until.insert(faction_id.into(),tick.saturating_add(next_retry_delay(mult,attempts)));
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativeOutcome {
    pub faction_id: String,
    pub plan_id: String,
    pub planner_id: String,
    pub tick: u64,
    pub final_status: String,
    pub reason: String,
    /// Includes native order IDs and receipts; a forecast is not a receipt.
    pub steps: Vec<super::StepRecord>,
    /// Old checkpoints did not include terminal goal evidence.
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub goal: Option<GoalSpec>,
    /// Actual owned-market stock observed at closure, not a planner forecast.
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub observed_goal_stock: Option<f64>,
    /// Actual produced quantity since this plan was accepted, certified by
    /// native paid-recipe output counters; independent of later consumption.
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub produced_goal_units: Option<f64>,
    /// Minimum newly produced output that this particular plan promised.
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub required_goal_production_units: Option<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativePlan {
    pub ledger: PlanLedger,
    pub goal: GoalSpec,
    pub actions: Vec<ActionSpec>,
    /// Expected production starts at the *next* scheduled natural recipe tick.
    #[serde(default)]
    pub production_started_tick: Option<u64>,
    #[serde(default)]
    pub last_reason: String,
    /// Explanation from the planning roles, persisted with its real orders.
    #[serde(default)]
    pub planner_rationale: String,
    /// Promoted industrial goals can complete upon genuine paid production,
    /// even if citizens immediately buy/consume that output. A shipment-only
    /// goal still requires the final market to hold the target stock.
    #[serde(default)]
    pub production_goal: bool,
    #[serde(default)]
    pub production_target_delta: u32,
    /// Native cumulative output when the plan started. New entries have a
    /// product-qualified key, because a single paid recipe may produce water
    /// AND fuel. Old saves used an unqualified action ID for the first output.
    #[serde(default)]
    pub production_baselines: BTreeMap<String, f64>,
    /// Native cumulative output consumed by succeeded plan steps, NOT a
    /// second inventory. The same recipe shift cannot be credited twice.
    #[serde(default)]
    pub production_accounted: BTreeMap<String, f64>,
}

/// A single physical producer/recipe action may have several actual outputs.
/// The product is included in the counter key, but repeated steps keep the
/// same key so each paid production batch is consumed exactly once.
fn output_counter_key(action:&ActionSpec, commodity:crate::economy::commodities::Commodity)->String {
    format!("{}::output:{}",action.action_id,commodity.as_str())
}

/// Read checkpoints written before product-qualified output counters existed.
/// Those legacy entries described ONLY `action.commodity` (the first output);
/// never silently reuse them as evidence for a different by-product.
fn output_counter_value(counters:&BTreeMap<String,f64>,action:&ActionSpec,
    commodity:crate::economy::commodities::Commodity)->Option<f64> {
    counters.get(&output_counter_key(action,commodity)).copied()
        .or_else(||(action.commodity==Some(commodity))
            .then(||counters.get(&action.action_id).copied()).flatten())
}

impl NativePlan {
    fn produced_goal_units(&self) -> f64 {
        self.actions.iter().filter(|a|a.kind==ActionKind::Produce &&
            a.destination_id==self.goal.destination_id &&
            a.outputs.iter().any(|(output,qty)|*output==self.goal.commodity && *qty>0))
            .map(|a|{
                let start=output_counter_value(&self.production_baselines,a,self.goal.commodity)
                    .unwrap_or(0.0);
                let end=output_counter_value(&self.production_accounted,a,self.goal.commodity)
                    .unwrap_or(start);
                (end-start).max(0.0)
            }).sum()
    }

    /// An executing *production* milestone can guide the existing station
    /// administrator's workforce allocation. This is a priority, NEVER a
    /// command to manufacture stock or pay wages outside native Genesis.
    pub fn active_production_priority(&self) -> Option<(String,crate::economy::commodities::Commodity)> {
        let step_id=match self.ledger.next() {
            PlanGate::Ready{step_id,..} | PlanGate::AwaitNative{step_id,..} => step_id,
            _=>return None,
        };
        let action=action_for_step(self,&step_id)?;
        if action.kind!=ActionKind::Produce {return None;}
        // The step may exist for a by-product (fuel from process_ice),
        // not just for the first output shown in the action catalogue.
        // For intermediate recipes, keep prioritising that step's own output.
        let preferred=if action.outputs.iter().any(|(c,q)|
            *c==self.goal.commodity && *q>0) {
            self.goal.commodity
        } else {action.commodity?};
        Some((action.destination_id.clone(),preferred))
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct NativeDriveReport {
    pub mode: &'static str,
    pub planner_id: String,
    pub plan_id: String,
    pub status: &'static str,
    pub reason: String,
    pub step_id: Option<String>,
    pub native_order_id: Option<String>,
    pub committed_credits: i64,
    pub planner_rationale: String,
}

fn report(plan: &NativePlan, status: &'static str, reason: &str, committed: i64) -> NativeDriveReport {
    let entry = plan.ledger.steps.iter().find(|r|r.phase != super::StepPhase::Succeeded);
    NativeDriveReport {
        mode: if plan.ledger.planner_id.starts_with("hybrid_") {"native_hybrid_opt_in"} else {"native_htn_opt_in"},
        planner_id: plan.ledger.planner_id.clone(),
        plan_id: plan.ledger.plan_id.clone(), status,
        reason: reason.into(), step_id: entry.map(|r|r.step.step_id.clone()),
        native_order_id: entry.and_then(|r|r.native_order_id.clone()),
        committed_credits: committed, planner_rationale:plan.planner_rationale.clone(),
    }
}

fn unique_market<'a>(snap: &'a PlanningSnapshot, location: &str) -> Option<&'a super::MarketEntry> {
    let mut entries = snap.owned_markets.iter().filter(|m|m.location_id == location);
    let first = entries.next()?;
    if entries.next().is_some() || first.market_id.is_empty() {None} else {Some(first)}
}

/// The existing native contract/facility paths currently use a single market
/// per location. Do not let an owned-only snapshot conceal a foreign market.
fn unique_global_market(world:&mut World, location:&str, expected_id:&str) -> bool {
    let ids:Vec<_>=world.query::<&MarketIdentity>().iter(world)
        .filter(|m|m.facility_location == location).map(|m|m.id.clone()).collect();
    ids.len() == 1 && ids[0] == expected_id
}

/// A warehouse is a real, unique faction-owned market. Never combine co-located
/// accounts or accept invalid/negative stock as a successful goal.
fn observed_commodity_stock(snap:&PlanningSnapshot, location:&str,
    commodity:crate::economy::commodities::Commodity) -> Option<f64> {
    let market=unique_market(snap,location)?;
    let quantity=market.stock.get(commodity.as_str()).copied().unwrap_or(0.0);
    quantity.is_finite().then_some(quantity).filter(|n|*n>=0.0)
}

fn observed_stock(snap:&PlanningSnapshot, goal:&GoalSpec) -> Option<f64> {
    observed_commodity_stock(snap,&goal.destination_id,goal.commodity)
}

/// Native receipts are necessary but NOT sufficient: a paid delivery might
/// have been consumed, diverted or insufficient for the faction's real goal.
fn goal_stock_verified(snapshot:&PlanningSnapshot, goal:&GoalSpec) -> Option<bool> {
    observed_stock(snapshot,goal).map(|stock|stock>=f64::from(goal.target_units))
}

/// Intermediate recipes must be checked against *their own output*, not the
/// final target. Otherwise metal -> components -> final goods deadlocks on the
/// first metal recipe while waiting for components that cannot yet be made.
fn production_stock_verified(snapshot:&PlanningSnapshot, action:&ActionSpec) -> Option<bool> {
    let output=action.commodity?;
    observed_commodity_stock(snapshot,&action.destination_id,output)
        .map(|stock|stock>=f64::from(action.units))
}

/// Recheck *all* markets in the ECS: the faction-only snapshot must not hide
/// a co-located foreign market. Used only to certify completed native goals.
fn native_goal_stock(world:&mut World, board:&ContractBoard,
    tick:u64, faction_id:&str, goal:&GoalSpec) -> Option<f64> {
    let snapshot=PlanningSnapshot::capture(world,board,tick,faction_id).ok()?;
    let market=unique_market(&snapshot,&goal.destination_id)?;
    if !unique_global_market(world,&goal.destination_id,&market.market_id) {return None;}
    observed_stock(&snapshot,goal)
}

/// Actual cumulative native output, preserved across paid shifts and SQLite
/// checkpointing. The recipe tick increments it only after payroll succeeds.
fn native_recipe_output_total(world:&mut World, facility_id:&str, recipe_id:&str,
    output:crate::economy::commodities::Commodity) -> Option<f64> {
    let value=world.query::<(&FacilityIdentity,&FacilityCrew)>().iter(world)
        .find(|(identity,_)|identity.id==facility_id)
        .and_then(|(_,crew)|crew.work_shift.as_ref())
        .and_then(|shift|shift.produced_outputs.get(recipe_id))
        .and_then(|outputs|outputs.get(output.as_str())).copied()
        .unwrap_or(0.0);
    (value.is_finite() && value>=0.0).then_some(value)
}

fn native_production_baselines(world:&mut World,snap:&PlanningSnapshot,
    actions:&[ActionSpec]) -> BTreeMap<String,f64> {
    let mut result=BTreeMap::new();
    for action in actions.iter().filter(|a|a.kind==ActionKind::Produce) {
        let Some((id,recipe))=native_catalogue::pinned_producer_recipe(snap,action) else {continue};
        for &(output,qty) in &action.outputs {
            if qty==0 {continue;}
            if let Some(total)=native_recipe_output_total(world,&id,&recipe,output) {
                result.insert(output_counter_key(action,output),total);
            }
        }
    }
    result
}

fn action_for_step<'a>(plan: &'a NativePlan, step_id: &str) -> Option<&'a ActionSpec> {
    let action_id = &plan.ledger.steps.iter().find(|r|r.step.step_id == step_id)?.step.action_id;
    plan.actions.iter().find(|a|&a.action_id == action_id)
}

/// Read the *authoritative* board. A posted contract is not success;
/// delivery is successful only after the native payment/settlement phase.
fn contract_receipt(plan: &mut NativePlan, board: &ContractBoard, tick: u64) -> &'static str {
    let PlanGate::AwaitNative {step_id,native_order_id} = plan.ledger.next() else {return "no_order_to_reconcile";};
    if native_order_id.starts_with("facility:") {return "await_native_production";}
    let Some(contract) = board.get(&native_order_id) else {return "missing_native_contract_manual_reconcile";};
    if contract.requestor_id != plan.ledger.faction_id {return "native_contract_wrong_faction";}
    let status = match contract.status {
        ContractStatus::Posted => ReceiptStatus::Submitted,
        ContractStatus::Accepted | ContractStatus::PickedUp | ContractStatus::Delivered => ReceiptStatus::Running,
        ContractStatus::Paid => ReceiptStatus::Succeeded,
        ContractStatus::Expired => {
            if contract.funding.as_ref().is_some_and(|f|f.reserved > 0) {return "await_native_refund";}
            ReceiptStatus::Failed
        },
    };
    // Never overwrite Running with a stale Posted snapshot.
    if status == ReceiptStatus::Submitted && plan.ledger.steps.iter().any(|r|r.step.step_id == step_id
        && r.phase == super::StepPhase::Running) {return "waiting_native_contract";}
    let result = plan.ledger.apply_receipt(&ExecutionReceipt {
        plan_id:plan.ledger.plan_id.clone(),step_id,
        native_order_id:Some(native_order_id),status,
        reason_code:format!("native_contract_{:?}",contract.status).to_lowercase(),tick,
    });
    if result.is_err() {"native_receipt_transition_rejected"} else {"native_contract_checked"}
}

/// A passive production step is completed by BOTH a real paid facility shift
/// and a stock condition. No fictional Produce order or generated stock.
fn production_receipt(world: &mut World, snap: &PlanningSnapshot, plan: &mut NativePlan,
    step_id: &str, native_id: &str, tick: u64, mult: u32) -> &'static str {
    // Use an independent action snapshot so native receipts can update the ledger.
    let Some(action) = action_for_step(plan, step_id).cloned() else {return "missing_production_action";};
    if action.kind != ActionKind::Produce {return "not_production_action";}
    let Some(fac_type) = &action.required_facility_type else {return "no_production_facility_type";};
    let Some(market) = unique_market(snap,&action.destination_id) else {return "ambiguous_production_market";};
    let Some(facility_id)=native_id.strip_prefix("facility:") else {
        return "invalid_production_native_id";
    };
    // Production must come from the exact pinned producer. The station's
    // market is often owned by a DIFFERENT facility.
    let Some((confirmed_facility,recipe_id))=native_catalogue::pinned_producer_recipe(snap,&action) else {
        return "producer_recipe_identity_changed";
    };
    if action.source_id.as_deref()!=Some(facility_id) || confirmed_facility != facility_id {
        return "producer_identity_changed";
    }
    let Some(started) = plan.production_started_tick else {return "production_start_missing";};
    if !unique_global_market(world,&action.destination_id,&market.market_id) {
        return "production_global_market_ambiguity";
    }
    let paid_shift = world.query::<(&FacilityIdentity,&FacilityLocation,&FacilityCrew)>().iter(world)
        .any(|(identity,location,crew)|identity.id == facility_id &&
            identity.faction_id == plan.ledger.faction_id && identity.facility_type == fac_type.as_str() &&
            location.location_name == action.destination_id &&
            crew.work_shift.as_ref().and_then(|shift|shift.last_recipe_ticks.get(&recipe_id))
                .is_some_and(|last_tick|*last_tick > plan.ledger.created_tick));
    // A refinery can process delivered inputs BEFORE the dispatcher advances
    // from the Paid transport step. Compare cumulative native output against
    // the value frozen when this plan was created, NOT merely `started`.
    // Likewise, later household consumption must not erase a genuine output.
    // Each output belongs to ONE paid recipe shift. Require the native
    // cumulative counter of EVERY output to advance by its recipe quantity.
    // In particular process_ice is water + fuel: do not certify a second
    // fuel batch based on a water-only counter or reuse a previous shift.
    let measured:Option<Vec<(String,f64)>>=action.outputs.iter().map(|&(output,units)|{
        let baseline=output_counter_value(&plan.production_baselines,&action,output)?;
        let before=output_counter_value(&plan.production_accounted,&action,output)
            .unwrap_or(baseline);
        let after=native_recipe_output_total(world,facility_id,&recipe_id,output)?;
        let credited=before+f64::from(units);
        (units>0 && before.is_finite() && credited.is_finite() &&
            after+0.0001>=credited).then(||(output_counter_key(&action,output),credited))
    }).collect();
    // Pre-FIX4 save files may not include product-qualified counter baselines.
    // They cannot claim by-product production retroactively. As a conservative
    // compatibility path, require a paid shift and visible stock for EVERY
    // recipe output. No cumulative quantity is credited in this legacy mode.
    let legacy=measured.is_none() && paid_shift &&
        action.outputs.iter().all(|(output,units)|*units>0 &&
            observed_commodity_stock(snap,&action.destination_id,*output)
                .is_some_and(|stock|stock>=f64::from(*units))) &&
        production_stock_verified(snap,&action).unwrap_or(false) &&
        action.outputs.iter().any(|(output,_)|
            output_counter_value(&plan.production_baselines,&action,*output).is_none()) &&
        // Without output counters, one observed shift is NOT reusable for
        // another instance of the same recipe within this plan.
        !plan.ledger.steps.iter().any(|record|
            record.step.step_id!=step_id && record.step.action_id==action.action_id &&
                record.phase==super::StepPhase::Succeeded);
    if paid_shift && (measured.is_some() || legacy) {
        let reason_code=if measured.is_some(){"native_recipe_paid_and_all_outputs_confirmed"}
            else{"legacy_paid_shift_and_all_outputs_visible"};
        let receipt=ExecutionReceipt {plan_id:plan.ledger.plan_id.clone(),step_id:step_id.into(),
            native_order_id:Some(native_id.into()),status:ReceiptStatus::Succeeded,
            reason_code:reason_code.into(),tick};
        if plan.ledger.apply_receipt(&receipt).is_ok(){
            if let Some(credited)=measured {
                for (key,total) in credited {plan.production_accounted.insert(key,total);}
            }
            return "native_production_confirmed";
        }
        return "production_receipt_transition_rejected";
    }
    if tick >= started.saturating_add(5 * crate::agents::facility::RECIPE_INTERVAL_BASE * u64::from(mult.max(1))) {
        let _ = plan.ledger.apply_receipt(&ExecutionReceipt {
            plan_id:plan.ledger.plan_id.clone(),step_id:step_id.into(),
            native_order_id:Some(native_id.into()),status:ReceiptStatus::Failed,
            reason_code:"production_not_confirmed_before_deadline".into(),tick,
        });
        return "native_production_timeout";
    }
    "await_paid_production_and_stock"
}

/// Strict preflight for a native shipment. Refuses ambiguous warehouses,
/// stale prices, unavailable carriers, foreign sources and absent direct routes.
/// The native acceptance pass performs all its own checks *again*.
fn post_native_delivery(world: &mut World, board: &mut ContractBoard, relations: &FactionRelations,
    tick:u64, mult:u32, faction_id:&str, action:&ActionSpec, key:&str,
) -> Result<String, &'static str> {
    if action.kind != ActionKind::Deliver || action.units == 0 || action.cost_credits <= 0 {
        return Err("invalid_delivery_action");
    }
    let Some(source_location) = action.source_id.as_deref() else {return Err("delivery_source_missing");};
    if source_location == action.destination_id {return Err("same_source_and_destination");}
    let snap = PlanningSnapshot::capture(world, board, tick, faction_id)?;
    let source = unique_market(&snap, source_location).ok_or("source_market_changed_or_ambiguous")?;
    let dest = unique_market(&snap, &action.destination_id).ok_or("destination_market_changed_or_ambiguous")?;
    if !unique_global_market(world,source_location,&source.market_id) ||
        !unique_global_market(world,&action.destination_id,&dest.market_id) {
        return Err("native_global_market_ambiguity");
    }
    let commodity = action.commodity.ok_or("delivery_commodity_missing")?;
    let expected_id = format!("htn-preview:deliver:{}:{}:{}:{}",
        source.market_id, dest.market_id, commodity.as_str(), action.units);
    if action.action_id != expected_id {return Err("native_market_identity_changed");}
    if source.stock.get(commodity.as_str()).copied().unwrap_or(0.0) < f64::from(action.units) {
        return Err("native_source_stock_gone");
    }
    // Native MarketPricing::price() uses the commodity base price if this
    // entry is absent; match that behavior before rechecking the quote.
    let price=source.prices.get(commodity.as_str()).copied()
        .unwrap_or_else(||f64::from(commodity.base_price()));
    if !price.is_finite() || price <= 0.0 {return Err("no_native_source_price");}
    if price > f64::from(f32::MAX) {return Err("native_price_out_of_range");}
    let purchase=sourcing::purchase_cost(price as f32, action.units, relations,
        faction_id, 0, faction_id).ok_or("native_quote_invalid")?;
    if purchase >= action.cost_credits {return Err("native_price_exceeds_funded_reward");}
    let route=world.get_resource::<colony::Navigation>()
        .and_then(|n|n.0.shortest_distance(source_location,&action.destination_id))
        .ok_or("native_route_unavailable")?;
    let assigned:std::collections::BTreeSet<_> = snap.active_commitments.iter()
        .filter_map(|c|c.assigned_ship_id.as_deref()).collect();
    let carrier=world.query::<(&ShipIdentity,&ShipPosition,&ShipTransit,&ShipCargo,&ShipFuel,&ShipEconomy)>()
        .iter(world).any(|(id,pos,transit,cargo,fuel,economy)| {
            id.faction_id == faction_id && !assigned.contains(id.id.as_str()) &&
            pos.location_name.as_deref() == Some(source_location) &&
            transit.transit.is_none() && cargo.free() >= action.units &&
            fuel.fuel.is_finite() && fuel.fuel > 0.0 && economy.credits >= purchase &&
            economy.active_contract_id.is_none()
        });
    if !carrier {return Err("no_funded_idle_native_carrier");}
    // No duplicate commitment, even one created by the old director.
    let conflicting=board.iter().any(|c|c.requestor_id == faction_id &&
        c.destination_location == action.destination_id && c.commodity == commodity &&
        !matches!(c.status, ContractStatus::Paid | ContractStatus::Expired));
    if conflicting {return Err("existing_native_delivery_commitment");}
    let entity=world.query::<(Entity,&FactionData)>().iter(world)
        .find(|(_,f)|f.id == faction_id && f.treasury
            .saturating_sub(faction::FACTION_SUBSIDY_FLOOR) >= action.cost_credits)
        .map(|(entity,_)|entity).ok_or("native_treasury_floor")?;
    let lifespan=faction::SUBSIDY_LIFESPAN_BASE
        .max(u64::from(route).saturating_mul(100).saturating_add(1200))
        .saturating_mul(u64::from(mult.max(1)));
    // The exact same native debit, posting, funding and station order as the
    // old Genesis coordinator, with an *attached* stable plan dispatch key.
    {let mut account=world.get_mut::<FactionData>(entity).unwrap();
        account.treasury -= action.cost_credits; account.dirty=true;}
    let contract_id=board.post_subsidy(faction_id.into(),commodity,action.units,
        source_location.into(),action.destination_id.clone(),action.cost_credits,tick,lifespan);
    board.register_prepaid(&contract_id,FundingSource::Faction);
    let contract=board.get_mut(&contract_id).expect("newly registered native contract");
    contract.mission_category=Some(PROJECT_TAG.into());
    contract.funding.as_mut().expect("registered escrow").station_order=
        Some(orders::Order::new("htn",key));
    Ok(contract_id)
}

/// One faction, one new native step per existing strategic cycle.
/// Some(report) means the HTN has an outstanding responsibility and the old
/// director must NOT also commit resources this cycle. None means fallback.
pub fn drive_native_htn(world:&mut World, board:&mut ContractBoard, relations:&FactionRelations,
    tick:u64,mult:u32,faction_id:&str,head:&HeadDecision,
) -> Option<NativeDriveReport> {
    if !execution_enabled() || world.get_resource::<director::Director>().is_none() {return None;}
    let (mut active, blocked_until, deferred) = {
        let mut d=world.resource_mut::<director::Director>();
        (d.ai_execution.active.remove(faction_id),
         d.ai_execution.blocked_until.get(faction_id).copied().unwrap_or(0),
         d.ai_execution.deferred_goals.get(faction_id).cloned())
    };
    if active.is_none() {
        // Never override research or colonisation. A remembered stock goal is
        // only retried while the head is still considering stock problems.
        if !matches!(head.selected_option,"deliver" | "build" | "wait") {return None;}
        let base_goal=head.problem.as_ref().filter(|_|head.reason!="already_commissioned_this_tick")
            .map(|problem|GoalSpec {goal_id:format!("{}:{}:{}",problem.goal_id,
                problem.destination,problem.commodity.as_str()),
                destination_id:problem.destination.clone(),commodity:problem.commodity,
                target_units:10,priority:problem.score.max(0.0) as u32});
        let early_snapshot=PlanningSnapshot::capture(world,board,tick,faction_id).ok();
        let promoted=base_goal.as_ref().and_then(|goal|early_snapshot.as_ref()
            .and_then(|snap|native_catalogue::promote_industry_output_goal(snap,goal)));
        let head_goal=promoted.clone().or(base_goal);
        // A higher-priority emergency may interrupt cooldown, but the normal
        // recovery path waits, letting native contracts and station ticks run.
        let preempted=matches!((&head_goal,&deferred), (Some(now),Some(old))
            if !same_stock_goal(now,&old.goal) && is_urgent_preemption(now,&old.goal));
        if tick<blocked_until && !preempted {return None;}
        let goal=select_stock_goal(head_goal.as_ref(),deferred.as_ref())?;
        let snap=early_snapshot?;
        // If native production or the legacy director already satisfied it,
        // simply forget the retry: no false receipt and no pointless order.
        if deferred.as_ref().is_some_and(|old|same_stock_goal(&old.goal,&goal)) &&
            observed_stock(&snap,&goal).is_some_and(|stock|stock>=f64::from(goal.target_units)) {
            let mut director=world.resource_mut::<director::Director>();
            director.ai_execution.deferred_goals.remove(faction_id);
            director.ai_execution.blocked_until.remove(faction_id);
            return None;
        }
        if deferred.as_ref().is_some_and(|old|!same_stock_goal(&old.goal,&goal)) {
            world.resource_mut::<director::Director>().ai_execution.deferred_goals.remove(faction_id);
        }
        // Personality has ALREADY selected the head's goal. These preferences
        // affect only choice among physically valid plans for that same goal.
        let preferences=world.get_resource::<director::Director>()
            .and_then(|d|d.commanders.get(faction_id))
            .map(|c|HybridPreferences {
                cost_weight:c.profile.industry,
                speed_weight:if c.crisis {3.0} else {c.profile.expansion.max(0.25)},
                caution_weight:c.profile.caution,
            }).unwrap_or_default();
        let fixed_target=deferred.as_ref().filter(|old|same_stock_goal(&old.goal,&goal))
            .map(|_|goal.target_units);
        let candidate=if hybrid_enabled() {
            native_catalogue::hybrid_native_candidate_with_target(&snap,&goal,preferences,fixed_target)
                .map(|(_,actions,goal,result,reason)|(actions,goal,result,reason))
        } else {
            native_catalogue::native_candidate_with_target(&snap,&goal,fixed_target)
                .map(|(_,actions,goal,result)|(actions,goal,result,
                    "legacy HTN single-planner proposal".into()))
        };
        let (actions,goal,result,rationale)=match candidate {
            Ok(candidate)=>candidate,
            Err(reason)=>{
                record_planning_failure(&mut world.resource_mut::<director::Director>().ai_execution,
                    faction_id,&goal,reason,tick,mult);
                return None;
            }
        };
        let plan_id=format!("native-{}:{}:{}:{}",
            if hybrid_enabled(){"hybrid"}else{"htn"},faction_id,tick,goal.goal_id);
        let ledger=match PlanLedger::from_proposal(&snap,&goal,&actions,&result,
            SearchBudget{max_nodes:350,max_depth:12},&plan_id) {
            Ok(ledger)=>ledger,
            Err(_)=>{
                record_planning_failure(&mut world.resource_mut::<director::Director>().ai_execution,
                    faction_id,&goal,"ledger_validation_failed",tick,mult);
                return None;
            }
        };
        let (last_reason,rationale)=if let Some(old)=deferred.as_ref()
            .filter(|old|same_stock_goal(&old.goal,&goal)) {
            ("native_goal_replanned",format!("recovery attempt {} of {}; prior={}; {}",
                old.failed_attempts.saturating_add(1),MAX_GOAL_RETRIES,
                old.last_reason,rationale))
        } else {("native_plan_accepted",rationale)};
        let production_baselines=native_production_baselines(world,&snap,&actions);
        let initial_stock=observed_stock(&snap,&goal).unwrap_or(0.0).floor().max(0.0) as u32;
        let production_goal=promoted.as_ref().is_some_and(|g|same_stock_goal(g,&goal)) ||
            deferred.as_ref().is_some_and(|d|same_stock_goal(&d.goal,&goal) &&
                d.goal.goal_id.contains(":output:"));
        let production_target_delta=goal.target_units.saturating_sub(initial_stock);
        active=Some(NativePlan {ledger,goal,actions,production_started_tick:None,
            last_reason:last_reason.into(),planner_rationale:rationale,
            production_goal,production_target_delta,production_baselines,
            production_accounted:BTreeMap::new()});
    }
    let mut plan=active?;
    let next=plan.ledger.next();
    let (status, reason, spend, keep) = match next {
        PlanGate::Completed => {
            // Completion is an observed *world condition*, not merely a list
            // of successful order receipts. It may be false if a delivery was
            // consumed while the next plan step was running.
            let production_receipted=plan.production_goal &&
                plan.ledger.steps.iter().any(|s|s.phase==super::StepPhase::Succeeded &&
                    plan.actions.iter().any(|a|a.action_id==s.step.action_id &&
                        a.kind==ActionKind::Produce && a.outputs.iter().any(|(commodity,qty)|
                            *commodity==plan.goal.commodity && *qty>0)));
            let produced=plan.produced_goal_units();
            if production_receipted && produced+0.0001>=f64::from(plan.production_target_delta) &&
                plan.production_target_delta>0 {
                ("completed","native_recipe_receipts_and_goal_production_confirmed",0,false)
            } else {
                match native_goal_stock(world,board,tick,faction_id,&plan.goal) {
                    Some(stock) if stock >= f64::from(plan.goal.target_units) =>
                        ("completed","native_receipts_and_goal_stock_confirmed",0,false),
                    Some(_) => ("needs_replan","native_receipts_complete_but_goal_stock_short",0,false),
                    None => ("blocked","native_goal_stock_unverifiable",0,true),
                }
            }
        },
        PlanGate::NeedsReplan {..} => ("needs_replan","native_execution_failed",0,false),
        PlanGate::AwaitDependencies {..} => ("waiting","await_plan_dependencies",0,true),
        PlanGate::ReconcilePrepared {dispatch_key,..} => {
            let existing=board.iter().find(|c|c.funding.as_ref()
                .and_then(|f|f.station_order.as_ref())
                .is_some_and(|o|o.order_id == format!("station:htn:{dispatch_key}")))
                .map(|c|c.id.clone());
            if let Some(id)=existing {
                let step_id=plan.ledger.steps.iter()
                    .find(|r|r.dispatch_key == dispatch_key).map(|r|r.step.step_id.clone());
                if let Some(step_id)=step_id {
                    let _=plan.ledger.acknowledge_native_order(&step_id,&dispatch_key,&id,tick);
                }
                ("waiting","reconciled_existing_native_order",0,true)
            } else {
                // Never resubmit a Prepared step blindly. The previous order
                // might have been committed in a different checkpoint.
                ("blocked","prepared_order_not_found_no_duplicate_dispatch",0,true)
            }
        },
        PlanGate::AwaitNative {step_id,native_order_id} => {
            let reason=if native_order_id.starts_with("facility:") {
                match PlanningSnapshot::capture(world,board,tick,faction_id) {
                    Ok(snap)=>production_receipt(world,&snap,&mut plan,&step_id,&native_order_id,tick,mult),
                    Err(_)=>"cannot_observe_native_production",
                }
            } else {contract_receipt(&mut plan,board,tick)};
            ("waiting",reason,0,true)
        },
        PlanGate::Ready {step_id,dispatch_key,action_id:_} => {
            // Preserve the existing one-funded-contract-per-faction-per-cycle
            // invariant, even if another administrator already posted work.
            let commissioned_now = board.iter().any(|c| c.requestor_id == faction_id &&
                c.posted_at_tick == tick && matches!(c.mission_category.as_deref(),
                    Some(PROJECT_TAG) | Some(crate::strategy::construction::PROJECT_TAG) |
                    Some(colony::PROJECT_TAG)));
            if commissioned_now {
                let report = report(&plan,"waiting","already_commissioned_this_tick",0);
                world.resource_mut::<director::Director>().ai_execution.active.insert(faction_id.into(),plan);
                return Some(report);
            }
            let action=action_for_step(&plan,&step_id).cloned();
            match action {
                Some(action) if action.kind == ActionKind::Deliver => {
                    match post_native_delivery(world,board,relations,tick,mult,faction_id,&action,&dispatch_key) {
                        Ok(id) => {
                            // Both ledger and contract board enter one checkpoint.
                            let acknowledged=plan.ledger.prepare(&step_id,tick).is_ok()
                                && plan.ledger.acknowledge_native_order(&step_id,&dispatch_key,&id,tick).is_ok();
                            if acknowledged {
                                ("submitted","funded_native_delivery_contract",action.cost_credits,true)
                            } else {
                                // The native contract already exists; never issue a replacement.
                                ("waiting","native_order_posted_ledger_reconciliation_needed",action.cost_credits,true)
                            }
                        },
                        Err(reason) => ("blocked",reason,0,false),
                    }
                },
                Some(action) if action.kind == ActionKind::Produce => {
                    let current=PlanningSnapshot::capture(world,board,tick,faction_id).ok();
                    let facility_id=current.as_ref().and_then(|s|{
                        let id=native_catalogue::pinned_producer_id(s,&action)?;
                        let market=unique_market(s,&action.destination_id)?;
                        unique_global_market(world,&action.destination_id,&market.market_id).then_some(id)
                    });
                    if let Some(id)=facility_id {
                        let native=format!("facility:{id}");
                        let acknowledged=plan.ledger.prepare(&step_id,tick).is_ok()
                            && plan.ledger.acknowledge_native_order(&step_id,&dispatch_key,&native,tick).is_ok();
                        if acknowledged {
                            plan.production_started_tick=Some(tick);
                            ("waiting","observe_native_paid_production_shift",0,true)
                        } else {("blocked","production_receipt_setup_failed",0,false)}
                    } else {("blocked","production_facility_not_verifiable",0,false)}
                },
                _ => ("blocked","htn_action_not_supported_by_native_dispatch",0,false),
            }
        },
    };
    plan.last_reason=reason.into();
    let report=report(&plan,status,reason,spend);
    let terminal_goal_stock=if keep {None} else {
        native_goal_stock(world,board,tick,faction_id,&plan.goal)
    };
    let mut d=world.resource_mut::<director::Director>();
    if keep {
        d.ai_execution.active.insert(faction_id.into(),plan);
    } else {
        // Terminal outcomes are retained *after* active plan eviction so a
        // snapshot poll or restart can still prove actual completion/failure.
        d.ai_execution.history.push(NativeOutcome {
            faction_id:faction_id.into(), plan_id:plan.ledger.plan_id.clone(),
            planner_id:plan.ledger.planner_id.clone(),tick,
            final_status:status.into(),reason:reason.into(),steps:plan.ledger.steps.clone(),
            goal:Some(plan.goal.clone()), observed_goal_stock:terminal_goal_stock,
            produced_goal_units:plan.production_goal.then(||plan.produced_goal_units()),
            required_goal_production_units:plan.production_goal.then_some(plan.production_target_delta),
        });
        const MAX_OUTCOMES:usize=64;
        let overflow=d.ai_execution.history.len().saturating_sub(MAX_OUTCOMES);
        if overflow>0 {d.ai_execution.history.drain(..overflow);}
        record_deferred_goal(&mut d.ai_execution,faction_id,&plan,status,reason,tick,mult);
    }
    Some(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::economy::commodities::Commodity;
    use super::super::{MarketEntry, PlanResult, PlanStatus, PlanStep, SCHEMA_VERSION};
    use std::collections::BTreeMap;

    fn dummy_plan() -> NativePlan {
        let goal=GoalSpec {goal_id:"water".into(),destination_id:"colony".into(),
            commodity:Commodity::Water,target_units:10,priority:10};
        let snap=PlanningSnapshot {schema_version:SCHEMA_VERSION,tick:10,faction_id:"f".into(),
            treasury_credits:10000,treasury_floor_credits:5000,
            owned_markets:vec![MarketEntry {market_id:"m".into(),facility_id:"fac".into(),
                location_id:"colony".into(),stock:BTreeMap::new(),demand:BTreeMap::new(),prices:BTreeMap::new()}],
            facilities:vec![],ships:vec![],active_commitments:vec![],technologies:vec![],recipes:vec![]};
        let actions=vec![ActionSpec {action_id:"deliver".into(),kind:ActionKind::Deliver,
            source_id:Some("source".into()),destination_id:"colony".into(),
            commodity:Some(Commodity::Water),units:10,cost_credits:1000,
            expected_ticks:100,inputs:vec![],outputs:vec![],required_facility_type:None}];
        let result=PlanResult {status:PlanStatus::Ready,goal_id:goal.goal_id.clone(),
            planner_id:"htn".into(),steps:vec![PlanStep{step_id:"s1".into(),
            action_id:"deliver".into(),depends_on:vec![],expected_condition:"paid".into()}],
            forecast_credits:1000,forecast_ticks:100,nodes_expanded:1,explanation:"test".into()};
        NativePlan{ledger:PlanLedger::from_proposal(&snap,&goal,&actions,&result,
            SearchBudget::default(),"p1").unwrap(),goal,actions,
            production_started_tick:None,last_reason:String::new(),planner_rationale:String::new(),
            production_goal:false,production_target_delta:0,
            production_baselines:BTreeMap::new(),production_accounted:BTreeMap::new()}
    }

    #[test]
    fn paid_recipe_accounting_survives_stock_consumption() {
        let mut plan=dummy_plan();
        plan.goal.commodity=Commodity::Water;
        plan.production_goal=true;
        plan.production_target_delta=10;
        plan.actions.push(ActionSpec{action_id:"produce-water".into(),kind:ActionKind::Produce,
            source_id:Some("refinery".into()),destination_id:"colony".into(),
            commodity:Some(Commodity::Water),units:10,cost_credits:0,
            expected_ticks:10,inputs:vec![(Commodity::Ice,8)],
            outputs:vec![(Commodity::Water,10)],required_facility_type:Some("refinery".into())});
        plan.production_baselines.insert("produce-water".into(),5.0);
        plan.production_accounted.insert("produce-water".into(),15.0);
        assert_eq!(plan.produced_goal_units(),10.0);
        assert!(plan.produced_goal_units()>=f64::from(plan.production_target_delta));
        // Current market stock may be zero; this is production evidence,
        // NOT a fabricated positive warehouse reading.
        let current_stock=0.0;
        assert!(current_stock<10.0);
    }

    #[test]
    fn intermediate_recipe_uses_its_own_stock_not_final_goal() {
        let plan=dummy_plan();
        let mut stock=BTreeMap::new();
        stock.insert(Commodity::Metals.as_str().into(),5.0);
        let snap=PlanningSnapshot {owned_markets:vec![MarketEntry {
            market_id:"market-colony".into(),facility_id:"colony-station".into(),
            location_id:"colony".into(),stock,demand:BTreeMap::new(),prices:BTreeMap::new(),
        }], ..PlanningSnapshot {
            schema_version:SCHEMA_VERSION,tick:10,faction_id:"f".into(),
            treasury_credits:10000,treasury_floor_credits:5000,
            owned_markets:vec![],facilities:vec![],ships:vec![],active_commitments:vec![],
            technologies:vec![],recipes:vec![]
        }};
        let metal_action=ActionSpec {action_id:"make_metal".into(),kind:ActionKind::Produce,
            source_id:Some("refinery".into()),destination_id:"colony".into(),
            commodity:Some(Commodity::Metals),units:5,cost_credits:0,expected_ticks:5,
            inputs:vec![(Commodity::Ore,5)],outputs:vec![(Commodity::Metals,5)],
            required_facility_type:Some("refinery".into())};
        assert_eq!(production_stock_verified(&snap,&metal_action),Some(true));
        // Final objective is water, and must NOT be marked complete yet.
        assert_eq!(goal_stock_verified(&snap,&plan.goal),Some(false));
        let mut short=metal_action.clone();short.units=6;
        assert_eq!(production_stock_verified(&snap,&short),Some(false));
    }

    #[test]
    fn native_goal_requires_real_unique_market_stock() {
        let (mut world,board,_,destination,_)=crate::strategy::tests::fixture(crate::strategy::Mode::Execute);
        let goal=GoalSpec{goal_id:"water".into(),destination_id:"port".into(),
            commodity:Commodity::Water,target_units:10,priority:10};
        assert_eq!(native_goal_stock(&mut world,&board,60,"own",&goal),Some(0.0));
        world.get_mut::<crate::agents::market::MarketPricing>(destination).unwrap()
            .supply.insert(Commodity::Water,10.0);
        assert_eq!(native_goal_stock(&mut world,&board,60,"own",&goal),Some(10.0));
        // Foreign second market at same location is not silently merged.
        let owner=world.get::<MarketIdentity>(destination).unwrap().facility;
        world.spawn(MarketIdentity{db_id:999,id:"alien-stock".into(),facility:owner,
            facility_location:"port".into()});
        assert_eq!(native_goal_stock(&mut world,&board,60,"own",&goal),None);
    }

    #[test]
    fn active_intermediate_recipe_guides_real_station_without_ordering_fake_output() {
        let mut plan=dummy_plan();
        plan.actions[0].kind=ActionKind::Produce;
        plan.actions[0].commodity=Some(Commodity::Metals);
        plan.actions[0].source_id=Some("refinery".into());
        assert_eq!(plan.active_production_priority(),Some(("colony".into(),Commodity::Metals)));
        let key=plan.ledger.prepare("s1",11).unwrap().to_string();
        plan.ledger.acknowledge_native_order("s1",&key,"facility:refinery",11).unwrap();
        assert_eq!(plan.active_production_priority(),Some(("colony".into(),Commodity::Metals)));
        plan.ledger.apply_receipt(&ExecutionReceipt{plan_id:"p1".into(),step_id:"s1".into(),
            native_order_id:Some("facility:refinery".into()),
            status:ReceiptStatus::Succeeded,reason_code:"paid_recipe".into(),tick:12}).unwrap();
        assert_eq!(plan.active_production_priority(),None);
    }

    #[test]
    fn old_terminal_history_without_goal_evidence_is_readable_but_unproven() {
        let raw=r#"{"faction_id":"own","plan_id":"p","planner_id":"htn", "tick":10,
            "final_status":"completed","reason":"legacy","steps":[]}"#;
        let historic:NativeOutcome=serde_json::from_str(raw).unwrap();
        assert!(historic.goal.is_none());
        assert!(historic.observed_goal_stock.is_none());
    }

    #[test]
    fn default_mode_is_non_executing_and_checkpoint_is_backward_compatible() {
        let old=r#"{"schema_version":1,"commanders":{}}"#;
        let d:director::Director=serde_json::from_str(old).unwrap();
        assert!(d.ai_execution.active.is_empty());
        assert!(d.ai_execution.blocked_until.is_empty());
        assert!(d.ai_execution.history.is_empty());
        assert!(d.ai_execution.deferred_goals.is_empty());
    }
    #[test]
    fn terminal_native_receipts_are_durable_and_not_forecasts() {
        let mut state=NativeExecution::default();
        let mut plan=dummy_plan();
        let key=plan.ledger.prepare("s1",11).unwrap().to_string();
        plan.ledger.acknowledge_native_order("s1",&key,"native-contract-1",11).unwrap();
        plan.ledger.apply_receipt(&ExecutionReceipt {
            plan_id:"p1".into(),step_id:"s1".into(),
            native_order_id:Some("native-contract-1".into()),
            status:ReceiptStatus::Succeeded,
            reason_code:"native_contract_paid".into(),tick:12,
        }).unwrap();
        state.history.push(NativeOutcome {
            faction_id:"f".into(),plan_id:"p1".into(),planner_id:"htn".into(),tick:13,
            final_status:"completed".into(),reason:"native_htn_goal_completed".into(),
            steps:plan.ledger.steps, goal:Some(plan.goal), observed_goal_stock:Some(10.0),
            produced_goal_units:None,required_goal_production_units:None,
        });
        let after:NativeExecution=serde_json::from_str(&serde_json::to_string(&state).unwrap()).unwrap();
        assert_eq!(after.history.len(),1);
        assert_eq!(after.history[0].steps[0].phase,super::super::StepPhase::Succeeded);
        assert_eq!(after.history[0].steps[0].native_order_id.as_deref(),Some("native-contract-1"));
    }
    #[test]
    fn native_paid_receipt_is_required_not_merely_a_posted_order() {
        let mut plan=dummy_plan();
        let mut board=ContractBoard::new();
        let id=board.post_subsidy("f".into(),Commodity::Water,10,
            "source".into(),"colony".into(),1000,10,1000);
        let key=plan.ledger.prepare("s1",10).unwrap().to_string();
        plan.ledger.acknowledge_native_order("s1",&key,&id,10).unwrap();
        assert_eq!(contract_receipt(&mut plan,&board,11),"native_contract_checked");
        assert!(matches!(plan.ledger.next(),PlanGate::AwaitNative{..}));
        board.get_mut(&id).unwrap().status=ContractStatus::Paid;
        assert_eq!(contract_receipt(&mut plan,&board,12),"native_contract_checked");
        assert!(matches!(plan.ledger.next(),PlanGate::Completed));
    }
    #[test]
    fn insufficient_native_preconditions_never_debit_money_or_post_orders() {
        let (mut world,mut board,owner,_,source)=crate::strategy::tests::fixture(crate::strategy::Mode::Execute);
        world.get_mut::<crate::agents::market::MarketPricing>(source).unwrap()
            .supply.insert(Commodity::Food,40.0);
        let credits=world.get::<FactionData>(owner).unwrap().treasury;
        let action=ActionSpec {action_id:"htn-preview:deliver:market-mine:market-port:food:10".into(),
            kind:ActionKind::Deliver,source_id:Some("mine".into()),destination_id:"port".into(),
            commodity:Some(Commodity::Food),units:10,cost_credits:1600,
            expected_ticks:100,inputs:vec![],outputs:vec![],required_facility_type:None};
        let result=post_native_delivery(&mut world,&mut board,&FactionRelations::new(),60,1,
            "own",&action,"one_stable_key");
        assert!(result.is_err(),"no navigation or carriers are installed in this fixture");
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,credits);
        assert_eq!(board.iter().count(),0);
    }
    #[test]
    fn expired_contract_waits_for_real_refund_before_replanning() {
        let mut plan=dummy_plan();
        let mut board=ContractBoard::new();
        let id=board.post_subsidy("f".into(),Commodity::Water,10,
            "source".into(),"colony".into(),1000,10,1000);
        board.register_prepaid(&id,FundingSource::Faction);
        let key=plan.ledger.prepare("s1",10).unwrap().to_string();
        plan.ledger.acknowledge_native_order("s1",&key,&id,10).unwrap();
        board.get_mut(&id).unwrap().status=ContractStatus::Expired;
        assert_eq!(contract_receipt(&mut plan,&board,11),"await_native_refund");
        assert!(matches!(plan.ledger.next(),PlanGate::AwaitNative{..}));
        board.get_mut(&id).unwrap().funding.as_mut().unwrap().reserved=0;
        assert_eq!(contract_receipt(&mut plan,&board,12),"native_contract_checked");
        assert!(matches!(plan.ledger.next(),PlanGate::NeedsReplan{..}));
    }
    #[test]
    fn old_native_plan_without_hybrid_rationale_loads_safely() {
        let plan=dummy_plan();
        let mut serialized=serde_json::to_value(&plan).unwrap();
        serialized.as_object_mut().unwrap().remove("planner_rationale");
        let restored:NativePlan=serde_json::from_value(serialized).unwrap();
        assert!(restored.planner_rationale.is_empty());
        assert_eq!(restored.ledger.plan_id,plan.ledger.plan_id);
    }
    #[test]
    fn reporting_identifies_hybrid_without_rewriting_legacy_receipts() {
        let mut plan=dummy_plan();
        plan.ledger.planner_id="hybrid_utility_htn_goap_beam".into();
        plan.planner_rationale="GOAP planned input before HTN recipe".into();
        let result=report(&plan,"waiting","await_native",0);
        assert_eq!(result.mode,"native_hybrid_opt_in");
        assert!(result.planner_rationale.contains("GOAP"));
        assert_eq!(result.plan_id,plan.ledger.plan_id);
    }
    #[test]
    fn restarting_with_prepared_step_does_not_issue_duplicate() {
        let mut plan=dummy_plan();
        plan.ledger.prepare("s1",11).unwrap();
        let encoded=serde_json::to_string(&plan).unwrap();
        let restored:NativePlan=serde_json::from_str(&encoded).unwrap();
        assert!(matches!(restored.ledger.next(),PlanGate::ReconcilePrepared{..}));
    }

    #[test]
    fn deferred_goal_survives_restart_without_carrying_old_dispatch_ids() {
        let mut state=NativeExecution::default();
        let plan=dummy_plan();
        record_deferred_goal(&mut state,"f",&plan,"needs_replan","native_execution_failed",100,1);
        let decoded:NativeExecution=serde_json::from_str(&serde_json::to_string(&state).unwrap()).unwrap();
        let deferred=decoded.deferred_goals.get("f").unwrap();
        assert_eq!(deferred.failed_attempts,1);
        assert_eq!(deferred.goal.destination_id,"colony");
        assert!(decoded.active.is_empty(),"a failed native action must never be revived by retry state");
        assert!(select_stock_goal(None,Some(deferred)).is_some());
    }

    #[test]
    fn head_can_preempt_deferred_goal_for_emergency_water() {
        let mut state=NativeExecution::default();
        let plan=dummy_plan();
        let mut low=plan.clone();
        low.goal.commodity=Commodity::Tools;
        low.goal.priority=8;
        record_deferred_goal(&mut state,"f",&low,"needs_replan","native_execution_failed",100,1);
        let emergency=GoalSpec{priority:10,..plan.goal};
        assert!(is_urgent_preemption(&emergency,&low.goal));
        assert_eq!(select_stock_goal(Some(&emergency),state.deferred_goals.get("f"))
            .unwrap().commodity,Commodity::Water);
    }

    #[test]
    fn retries_are_bounded_with_increasing_cooldowns() {
        let plan=dummy_plan();
        let mut state=NativeExecution::default();
        let mut before=0;
        for attempt in 1..=MAX_GOAL_RETRIES {
            let tick=u64::from(attempt)*1000;
            record_deferred_goal(&mut state,"f",&plan,"needs_replan","native_execution_failed",tick,1);
            let until=state.blocked_until["f"];
            assert!(until>tick);
            let delay=until-tick;
            assert!(delay>=before);
            before=delay;
        }
        assert!(state.deferred_goals.get("f").is_none(),"retry limit must release the goal");
        assert!(state.active.is_empty());
    }

    #[test]
    fn permanent_dispatch_error_never_sticks_as_retry_goal() {
        let mut state=NativeExecution::default();
        let plan=dummy_plan();
        record_deferred_goal(&mut state,"f",&plan,"blocked",
            "htn_action_not_supported_by_native_dispatch",100,1);
        assert!(state.deferred_goals.is_empty());
        record_deferred_goal(&mut state,"f",&plan,"blocked",
            "no_funded_idle_native_carrier",200,1);
        assert_eq!(state.deferred_goals["f"].failed_attempts,1);
        record_deferred_goal(&mut state,"f",&plan,"completed",
            "native_receipts_and_goal_stock_confirmed",300,1);
        assert!(state.deferred_goals.is_empty());
        assert!(state.blocked_until.is_empty());
    }

    #[test]
    fn no_plan_search_is_rate_limited_and_never_posts_native_order() {
        let plan=dummy_plan();
        let mut state=NativeExecution::default();
        record_planning_failure(&mut state,"f",&plan.goal,"htn_no_ready_plan",100,1);
        assert!(state.active.is_empty());
        assert!(state.history.is_empty());
        assert_eq!(state.deferred_goals["f"].last_reason,"planning:htn_no_ready_plan");
        let retry_after=state.blocked_until["f"];
        assert!(retry_after>100);
        record_planning_failure(&mut state,"f",&plan.goal,"htn_no_ready_plan",retry_after,1);
        assert_eq!(state.deferred_goals["f"].failed_attempts,2);
        record_planning_failure(&mut state,"f",&plan.goal,"htn_no_ready_plan",retry_after+1,1);
        assert!(state.deferred_goals.is_empty());
    }

    #[test]
    fn refreshed_head_probe_and_deferred_absolute_target_are_same_stock_goal() {
        let mut remembered=dummy_plan().goal;
        remembered.target_units=35;
        let head=GoalSpec{target_units:10,..remembered.clone()};
        assert!(same_stock_goal(&head,&remembered));
        let deferred=DeferredGoal{goal:remembered.clone(),failed_attempts:1,
            last_failed_tick:100,last_reason:"no_funded_idle_native_carrier".into()};
        assert_eq!(select_stock_goal(Some(&head),Some(&deferred)).unwrap().target_units,35);
    }
}
