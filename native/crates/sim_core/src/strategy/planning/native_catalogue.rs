//! Stage 05 — conservative HTN shadow on a REAL captured Genesis snapshot.
//!
//! Crucially, this is NOT dispatch. Native markets may share the same location,
//! ships have unknown routes/commitments, and production uses a separate work/
//! payroll system. No synthetic market stocks are merged and no ECS state is
//! modified. Only projectable *hypotheses* are passed to upstream HTN 0.2.1.

use std::collections::{BTreeMap, BTreeSet};

use serde::Serialize;

use crate::agents::{facility, faction};
use crate::economy::commodities::Commodity;

use super::{
    validate_plan, ActionKind, ActionSpec, GoalSpec, HtnAdapter, MarketEntry,
    PlanResult, PlanStatus, Planner, PlanningSnapshot, SearchBudget,
};

/// First end-to-end shadow experiments are intentionally one native recipe
/// batch in size, not a claim to solve the entire 200-unit subsidy project.
const PROBE_UNITS: u32 = 10;
const MAX_SHADOW_NODES: u32 = 350;
const MAX_SHADOW_DEPTH: usize = 12;
const PROJECTED_DELIVERY_TICKS: u64 = 2 * faction::SUBSIDY_CHECK_INTERVAL_BASE;

#[derive(Clone, Debug, Serialize)]
pub struct HtnNativeShadow {
    pub mode: &'static str,
    pub status: String,
    pub reason: String,
    pub market_id: Option<String>,
    pub incremental_probe_units: u32,
    pub snapshot_markets: usize,
    pub usable_markets: usize,
    pub catalogue_size: usize,
    pub validation: String,
    pub proposal: Option<PlanResult>,
    /// These unresolved requirements prevent native dispatch.
    pub dispatch_blockers: Vec<&'static str>,
}

fn projectable_stock(market: &MarketEntry, commodity: Commodity) -> Option<u32> {
    let value = market.stock.get(commodity.as_str()).copied().unwrap_or(0.0);
    if !value.is_finite() || value < 0.0 || value > f64::from(i32::MAX) { return None; }
    Some(value.floor() as u32)
}

/// Project a *goal-scoped, multi-station* action catalogue without conflating
/// separate native markets. Unlike the first water probe, an intermediate
/// ingredient may itself be produced at a different owned station and then
/// transported. Ambiguous sources are excluded, ambiguous targets are fatal.
/// No resource or carrier is moved by this pure projection.
fn catalogue(
    snapshot: &PlanningSnapshot,
    destination: &str,
    goal_commodity: Option<Commodity>,
) -> Result<(PlanningSnapshot, Vec<ActionSpec>, String), &'static str> {
    let mut counts = BTreeMap::<&str, usize>::new();
    for market in &snapshot.owned_markets {
        *counts.entry(market.location_id.as_str()).or_default() += 1;
    }
    if counts.get(destination).copied().unwrap_or(0) == 0 {
        return Err("destination_has_no_owned_market");
    }
    if counts.get(destination).copied() != Some(1) {
        return Err("ambiguous_destination_markets");
    }
    let mut projected = snapshot.clone();
    // A location is usable only if its market is unique and its stable owning
    // facility is present at that same location. Foreign / forged / damaged
    // source records cannot supply even a hypothetical delivery.
    projected.owned_markets.retain(|market| {
        counts.get(market.location_id.as_str()) == Some(&1) &&
            !market.market_id.is_empty() && !market.facility_id.is_empty() &&
            !market.location_id.is_empty() &&
            snapshot.facilities.iter().any(|facility| {
                facility.facility_id == market.facility_id &&
                facility.location_id == market.location_id
            })
    });
    let target = projected.owned_markets.iter()
        .find(|market| market.location_id == destination)
        .ok_or("destination_market_owner_missing_or_wrong_location")?;
    let target_id = target.market_id.clone();
    // Cargo already promised by an existing Posted/Accepted contract is not
    // free planning stock. Genesis has NOT necessarily picked it up yet, so
    // subtract that obligation ONLY from the read-only planning projection.
    // PickedUp/Delivered goods are already absent from the source supply.
    // Never mutate ECS market balances or reserve money a second time.
    for commitment in &snapshot.active_commitments {
        if commitment.quantity==0 || !matches!(commitment.status.as_str(),"posted"|"accepted") ||
            commitment.source==destination {continue;}
        if let Some(market)=projected.owned_markets.iter_mut()
            .find(|m|m.location_id==commitment.source) {
            let quantity=market.stock.entry(commitment.commodity.as_str().to_owned()).or_insert(0.0);
            if quantity.is_finite() && *quantity>=0.0 {
                *quantity=(*quantity - f64::from(commitment.quantity)).max(0.0);
            }
        }
    }
    let mut actions = Vec::<ActionSpec>::new();

    // Production can happen at ANY owned location with a unique native market,
    // not just the final goal location. The station market and the producing
    // facility are different entities in most Genesis scenarios.
    for market in &projected.owned_markets {
        for producer in snapshot.facilities.iter().filter(|f| f.location_id == market.location_id) {
            for recipe in snapshot.recipes.iter().filter(|r| r.facility_type == producer.facility_type) {
                if recipe.inputs.is_empty() || recipe.outputs.is_empty() ||
                    recipe.inputs.iter().any(|(_, q)| *q == 0) ||
                    recipe.outputs.iter().any(|(_, q)| *q == 0) {continue;}
                actions.push(ActionSpec {
                    action_id:format!("htn-preview:produce:{}:{}:{}",
                        market.market_id, producer.facility_id, recipe.recipe_id),
                    kind:ActionKind::Produce,
                    source_id:Some(producer.facility_id.clone()),
                    destination_id:market.location_id.clone(),
                    commodity:recipe.outputs.first().map(|(c,_)| *c),
                    units:recipe.outputs.first().map_or(0, |(_, q)| *q),
                    // Payroll is not free in Genesis: zero here means the
                    // *forecast* lacks a reliable live payroll quote. Actual
                    // wage/crew capacity remains enforced by native execution.
                    cost_credits:0,
                    expected_ticks:facility::RECIPE_INTERVAL_BASE,
                    inputs:recipe.inputs.clone(),outputs:recipe.outputs.clone(),
                    required_facility_type:Some(recipe.facility_type.clone()),
                });
            }
        }
    }

    let assigned: BTreeSet<&str> = snapshot.active_commitments.iter()
        .filter_map(|commitment|commitment.assigned_ship_id.as_deref()).collect();
    // Precompute output capacity to allow a future shipment of goods that are
    // NOT present yet, but can actually be made by an existing owned producer.
    // Merely advertising a recipe never creates its input stock.
    let mut producible = BTreeMap::<(String,String),u32>::new();
    for action in actions.iter().filter(|a|a.kind==ActionKind::Produce) {
        for &(output,qty) in &action.outputs {
            let key=(action.destination_id.clone(),output.as_str().to_owned());
            let entry=producible.entry(key).or_default();
            *entry=(*entry).max(qty);
        }
    }
    // A live incoming order owns its native delivery slot. Forecasting a
    // second shipment of the same good to the same destination would fail the
    // execution preflight, and could strand an already paid escrow.
    let incoming: BTreeSet<(String,String)> = snapshot.active_commitments.iter()
        .filter(|c| c.quantity>0)
        .map(|c|(c.destination.clone(),c.commodity.as_str().to_owned())).collect();
    // Each route is still a hypothetical DIRECT shipment. Native navigation,
    // fuel, carrier credits and escrow are checked on dispatch. Different
    // cargo lots allow a chain to satisfy recipe inputs without paying for a
    // huge speculative transport; the number of lot sizes is bounded.
    for source in &projected.owned_markets {
        let capacity = snapshot.ships.iter()
            .filter(|ship| !ship.in_transit && !assigned.contains(ship.ship_id.as_str()) &&
                ship.location_id.as_deref()==Some(source.location_id.as_str()) &&
                ship.fuel.is_finite() && ship.fuel>0.0)
            .map(|ship|ship.free_cargo).max().unwrap_or(0);
        if capacity==0 {continue;}
        for target in &projected.owned_markets {
            if source.location_id==target.location_id {continue;}
            for &commodity in Commodity::ALL {
                if incoming.contains(&(target.location_id.clone(),commodity.as_str().to_owned())) {
                    continue;
                }
                let Some(stock)=projectable_stock(source,commodity) else {continue;};
                let possible=producible.get(&(source.location_id.clone(),commodity.as_str().to_owned()))
                    .copied().unwrap_or(0);
                // A maximum of three hypothetical recipe batches may be used
                // for ONE shipment's forecast. The actual recipe, workforce
                // and stock must still be physically confirmed at execution.
                let available=stock.max(possible.saturating_mul(3));
                let max_lot=available.min(capacity).min(20);
                if max_lot==0 {continue;}
                let mut lots=BTreeSet::new();
                lots.insert(max_lot);
                lots.insert(max_lot.min(PROBE_UNITS));
                if possible>0 {lots.insert(max_lot.min(possible));}
                for producer in snapshot.facilities.iter().filter(|f|f.location_id==target.location_id) {
                    for recipe in snapshot.recipes.iter().filter(|r|r.facility_type==producer.facility_type) {
                        for &(input,units) in &recipe.inputs {
                            if input==commodity && units>0 && units<=max_lot {lots.insert(units);}
                        }
                    }
                }
                // Match MarketPricing::price(): an ABSENT quote falls back
                // to base price; an explicitly corrupt/negative quote cannot.
                let price=match source.prices.get(commodity.as_str()).copied() {
                    Some(p) if p.is_finite() && p>0.0 && p<=f64::from(f32::MAX) => p,
                    None => f64::from(commodity.base_price()),
                    _ => continue,
                };
                for units in lots {
                    if units==0 {continue;}
                    let estimate=(price*f64::from(units)).ceil();
                    if !estimate.is_finite() || estimate > i64::MAX as f64 -
                        faction::SUBSIDY_BASE_PAYMENT as f64 * 2.0 {continue;}
                    let estimated_cost=estimate as i64 + faction::SUBSIDY_BASE_PAYMENT * 2;
                    actions.push(ActionSpec {
                        action_id:format!("htn-preview:deliver:{}:{}:{}:{}",
                            source.market_id,target.market_id,commodity.as_str(),units),
                        kind:ActionKind::Deliver,source_id:Some(source.location_id.clone()),
                        destination_id:target.location_id.clone(),commodity:Some(commodity),units,
                        cost_credits:estimated_cost,expected_ticks:PROJECTED_DELIVERY_TICKS,
                        inputs:Vec::new(),outputs:Vec::new(),required_facility_type:None,
                    });
                }
            }
        }
    }

    // Backward relevance closure from the selected goal: a recipe is useful
    // only when it makes a required product; a delivery is useful only when
    // it carries one. Expand dependencies until fixed point. This keeps the
    // 350-node first integration budget out of irrelevant industry branches.
    if let Some(commodity)=goal_commodity {
        let mut needed=BTreeSet::<(String,String)>::new();
        needed.insert((destination.to_owned(),commodity.as_str().to_owned()));
        loop {
            let mut next=needed.clone();
            for action in &actions {
                match action.kind {
                    ActionKind::Produce if action.outputs.iter().any(|(product,_)|
                        needed.contains(&(action.destination_id.clone(),product.as_str().to_owned()))) => {
                        for &(input,_) in &action.inputs {
                            next.insert((action.destination_id.clone(),input.as_str().to_owned()));
                        }
                    }
                    ActionKind::Deliver if action.commodity.is_some_and(|c|
                        needed.contains(&(action.destination_id.clone(),c.as_str().to_owned()))) => {
                        if let (Some(source),Some(c))=(action.source_id.as_deref(),action.commodity) {
                            next.insert((source.to_owned(),c.as_str().to_owned()));
                        }
                    }
                    _=>{}
                }
            }
            if next==needed {break;}
            needed=next;
        }
        actions.retain(|action|match action.kind {
            ActionKind::Produce => action.outputs.iter().any(|(c,_)|
                needed.contains(&(action.destination_id.clone(),c.as_str().to_owned()))),
            ActionKind::Deliver => action.commodity.is_some_and(|c|
                needed.contains(&(action.destination_id.clone(),c.as_str().to_owned()))),
            _=>false,
        });
    }
    actions.sort_by(|a,b|a.action_id.cmp(&b.action_id));
    actions.dedup_by(|a,b|a.action_id == b.action_id);
    Ok((projected,actions,target_id))
}

/// Turn an industry input-shortage into an *actual processed-output* goal.
/// For example, an Ice shortage at an owned refinery can be a Water goal.
/// This is NOT a scripted "ice -> water" exception: every candidate is taken
/// from the captured native recipe catalogue. Only outputs with a real local
/// demand greater than stock are eligible; an empty/foreign/ambiguous market
/// cannot invent a goal. The head remains responsible for choosing the need.
pub(super) fn promote_industry_output_goal(
    snapshot: &PlanningSnapshot, head_goal: &GoalSpec,
) -> Option<GoalSpec> {
    if !head_goal.goal_id.starts_with("supply_industry:") { return None; }
    let (projected, actions, _) = catalogue(snapshot, &head_goal.destination_id,None).ok()?;
    let target = projected.owned_markets.iter()
        .find(|m|m.location_id==head_goal.destination_id)?;
    let mut choices = Vec::new();
    for action in actions.iter().filter(|a|a.kind==ActionKind::Produce &&
        a.destination_id==head_goal.destination_id &&
        a.inputs.iter().any(|(input,qty)|*input==head_goal.commodity && *qty>0)) {
        if pinned_producer_recipe(&projected,action).is_none() {continue;}
        for &(output,per_batch) in &action.outputs {
            if per_batch==0 || output==head_goal.commodity {continue;}
            let stock=target.stock.get(output.as_str()).copied().unwrap_or(0.0);
            let demand=target.demand.get(output.as_str()).copied().unwrap_or(0.0);
            if !stock.is_finite() || !demand.is_finite() ||
                stock<0.0 || demand<=stock {continue;}
            let essential=matches!(output, Commodity::Water|Commodity::Food);
            // Keep deterministic, conservative ordering. An essential
            // shortfall outranks surplus by-products such as refinery fuel.
            choices.push((essential, demand-stock, output.as_str(), output));
        }
    }
    choices.sort_by(|a,b|b.0.cmp(&a.0)
        .then_with(||b.1.total_cmp(&a.1))
        .then_with(||a.2.cmp(b.2)));
    let &(_,_,_,output)=choices.first()?;
    Some(GoalSpec {
        goal_id:format!("{}:output:{}",head_goal.goal_id,output.as_str()),
        destination_id:head_goal.destination_id.clone(),
        commodity:output,target_units:PROBE_UNITS,priority:head_goal.priority,
    })
}

/// Resolve a specific, owned producer for a planned recipe in the current
/// native snapshot. Rechecks the market identity, facility and recipe: a
/// projected `Produce` step does not itself start or finish production.
pub(super) fn pinned_producer_recipe(snapshot:&PlanningSnapshot, action:&ActionSpec) -> Option<(String,String)> {
    if action.kind != ActionKind::Produce {return None;}
    let id=action.source_id.as_deref()?;
    let producer=snapshot.facilities.iter().find(|f|f.facility_id==id &&
        f.location_id==action.destination_id &&
        Some(f.facility_type.as_str())==action.required_facility_type.as_deref())?;
    let mut markets=snapshot.owned_markets.iter().filter(|m|m.location_id==action.destination_id);
    let market=markets.next()?;
    if markets.next().is_some() || !snapshot.facilities.iter().any(|f|
        f.facility_id==market.facility_id && f.location_id==action.destination_id){return None;}
    let recipe=snapshot.recipes.iter().find(|r| {
        r.facility_type==producer.facility_type && r.inputs==action.inputs && r.outputs==action.outputs &&
        action.commodity==r.outputs.first().map(|(c,_)|*c) &&
        action.units==r.outputs.first().map_or(0, |(_,q)|*q) &&
        action.action_id==format!("htn-preview:produce:{}:{}:{}",market.market_id,id,r.recipe_id)
    })?;
    if recipe.inputs.is_empty() || recipe.outputs.is_empty(){return None;}
    Some((producer.facility_id.clone(),recipe.recipe_id.clone()))
}

pub(super) fn pinned_producer_id(snapshot:&PlanningSnapshot,action:&ActionSpec)->Option<String>{
    pinned_producer_recipe(snapshot,action).map(|(id,_)|id)
}

/// Exact same immutable local market case for all three planners. Unlike
/// native_candidate this does not require HTN to find a plan, so failures are
/// also comparable. No World, contract board or ship is ever mutated.
pub(super) fn comparison_case(
    snapshot: &PlanningSnapshot, native_goal: &GoalSpec,
) -> Result<(PlanningSnapshot, Vec<ActionSpec>, GoalSpec), &'static str> {
    let (projected,actions,_market_id)=catalogue(snapshot,&native_goal.destination_id,Some(native_goal.commodity))?;
    let target=projected.owned_markets.iter()
        .find(|m|m.location_id==native_goal.destination_id)
        .ok_or("destination_market_not_projectable")?;
    let stock=projectable_stock(target,native_goal.commodity)
        .ok_or("invalid_destination_stock")?;
    let goal=GoalSpec {target_units:stock.checked_add(PROBE_UNITS)
        .ok_or("target_stock_overflow")?, ..native_goal.clone()};
    Ok((projected,actions,goal))
}

/// For a retried native execution goal, keep the absolute stock milestone
/// recorded by the previous attempt. For a *new* head request, preserve the
/// short +10 probe so large 200-unit strategic requests remain manageable.
fn projected_native_target(stock:u32,fixed_target:Option<u32>)->Result<u32,&'static str> {
    if let Some(target)=fixed_target {
        return if target>stock {Ok(target)} else {Err("native_goal_already_met")};
    }
    stock.checked_add(PROBE_UNITS).ok_or("target_stock_overflow")
}

/// Stage A: the same *real* catalogue used in shadow mode, with the exact
/// ordered actions retained for a separately validated native dispatcher.
/// This function is pure; even a Ready result has NOT committed any cargo.
pub(super) fn native_candidate(
    snapshot: &PlanningSnapshot,
    native_goal: &GoalSpec,
) -> Result<(PlanningSnapshot, Vec<ActionSpec>, GoalSpec, PlanResult), &'static str> {
    native_candidate_with_target(snapshot,native_goal,None)
}

pub(super) fn native_candidate_with_target(
    snapshot:&PlanningSnapshot,native_goal:&GoalSpec,fixed_target:Option<u32>,
) -> Result<(PlanningSnapshot,Vec<ActionSpec>,GoalSpec,PlanResult),&'static str> {
    let (projected, actions, _) = catalogue(snapshot, &native_goal.destination_id,Some(native_goal.commodity))?;
    let target = projected.owned_markets.iter()
        .find(|m| m.location_id == native_goal.destination_id)
        .ok_or("destination_market_not_projectable")?;
    let start = projectable_stock(target, native_goal.commodity)
        .ok_or("invalid_destination_stock")?;
    let goal = GoalSpec { target_units:projected_native_target(start,fixed_target)?,
        ..native_goal.clone() };
    let budget = SearchBudget { max_nodes: MAX_SHADOW_NODES, max_depth: MAX_SHADOW_DEPTH };
    let mut result = HtnAdapter.plan(&projected, &goal, &actions, budget);
    result.planner_id = "htn_0_2_1_native".into();
    if result.status != PlanStatus::Ready {
        return Err(match result.status {
            PlanStatus::NoPlan => "htn_no_ready_plan",
            PlanStatus::BudgetExhausted => "htn_search_budget_exhausted",
            PlanStatus::InvalidSnapshot => "htn_invalid_snapshot",
            PlanStatus::Ready => unreachable!(),
        });
    }
    validate_plan(&projected, &goal, &actions, &result, budget)
        .map_err(|_| "htn_invalid_plan")?;
    // Native executor implements ONLY delivery and passive observed production.
    if result.steps.iter().any(|step| actions.iter()
        .find(|a| a.action_id == step.action_id)
        .is_none_or(|a| !matches!(&a.kind, ActionKind::Deliver | ActionKind::Produce))) {
        return Err("htn_action_not_dispatchable");
    }
    Ok((projected, actions, goal, result))
}

/// Block C: the same conservative native catalogue used by HTN, GOAP and
/// selective Beam. The native dispatcher still revalidates every commitment.
/// Only an explicit hybrid opt-in calls this from the live director.
pub(super) fn hybrid_native_candidate(
    snapshot:&PlanningSnapshot, native_goal:&GoalSpec,
    preferences:super::HybridPreferences,
) -> Result<(PlanningSnapshot, Vec<ActionSpec>, GoalSpec, PlanResult, String), &'static str> {
    hybrid_native_candidate_with_target(snapshot,native_goal,preferences,None)
}

pub(super) fn hybrid_native_candidate_with_target(
    snapshot:&PlanningSnapshot,native_goal:&GoalSpec,
    preferences:super::HybridPreferences,fixed_target:Option<u32>,
) -> Result<(PlanningSnapshot,Vec<ActionSpec>,GoalSpec,PlanResult,String),&'static str> {
    use super::HybridPlanner;
    let (projected,actions,mut goal)=comparison_case(snapshot,native_goal)?;
    if fixed_target.is_some() {
        let market=projected.owned_markets.iter().find(|m|m.location_id==goal.destination_id)
            .ok_or("destination_market_not_projectable")?;
        let current=projectable_stock(market,goal.commodity).ok_or("invalid_destination_stock")?;
        goal.target_units=projected_native_target(current,fixed_target)?;
    }
    let budget=SearchBudget{max_nodes:MAX_SHADOW_NODES,max_depth:MAX_SHADOW_DEPTH};
    let decision=HybridPlanner{preferences}.decide(&projected,&goal,&actions,budget);
    if decision.result.status!=PlanStatus::Ready {
        return Err(match decision.result.status {
            PlanStatus::NoPlan => "hybrid_no_ready_plan",
            PlanStatus::BudgetExhausted => "hybrid_search_budget_exhausted",
            PlanStatus::InvalidSnapshot => "hybrid_invalid_snapshot",
            PlanStatus::Ready => unreachable!(),
        });
    }
    validate_plan(&projected,&goal,&actions,&decision.result,budget)
        .map_err(|_|"hybrid_invalid_plan")?;
    if decision.result.steps.iter().any(|step|actions.iter()
        .find(|a|a.action_id==step.action_id)
        .is_none_or(|a|!matches!(&a.kind,ActionKind::Deliver|ActionKind::Produce))) {
        return Err("hybrid_action_not_dispatchable");
    }
    let reason=format!("HTN={:?}, GOAP={:?} as {}, Beam={}, selected={}; {}",
        decision.roles.htn_status,decision.roles.goap_status,decision.roles.goap_role,
        decision.roles.beam_reason,decision.roles.selected_source,decision.result.explanation);
    Ok((projected,actions,goal,decision.result,reason))
}

/// Same game tick, same faction, no mutation, no order submission.
/// The HTN result is useful for debugging dependencies, not yet for gameplay.
pub fn htn_native_shadow(snapshot: &PlanningSnapshot, native_goal: &GoalSpec) -> HtnNativeShadow {
    let mut trace = HtnNativeShadow {
        mode:"read_only_real_genesis_snapshot",status:"blocked".into(),reason:String::new(),
        market_id:None,incremental_probe_units:PROBE_UNITS,
        snapshot_markets:snapshot.owned_markets.len(),usable_markets:0,catalogue_size:0,
        validation:"not_run".into(),proposal:None,
        dispatch_blockers:vec!["native_route_and_fuel_unverified","workforce_and_payroll_unverified",
            "native_order_receipts_not_connected","escrow_and_current_market_prices_require_recheck"],
    };
    let (projected, actions, market_id) = match catalogue(snapshot,&native_goal.destination_id,Some(native_goal.commodity)) {
        Ok(value) => value,
        Err(reason) => { trace.reason=reason.into(); return trace; }
    };
    trace.usable_markets = projected.owned_markets.len();
    trace.catalogue_size = actions.len();
    trace.market_id = Some(market_id);
    let Some(destination) = projected.owned_markets.iter().find(|m|m.location_id == native_goal.destination_id) else {
        trace.reason="no_unambiguous_destination".into();return trace;
    };
    let Some(stock) = projectable_stock(destination,native_goal.commodity) else {
        trace.reason="invalid_destination_stock".into();return trace;
    };
    let Some(target_units) = stock.checked_add(PROBE_UNITS) else {
        trace.reason="target_stock_overflow".into();return trace;
    };
    let goal = GoalSpec {target_units, ..native_goal.clone()};
    let budget = SearchBudget{max_nodes:MAX_SHADOW_NODES,max_depth:MAX_SHADOW_DEPTH};
    let candidate = HtnAdapter.plan(&projected,&goal,&actions,budget);
    let validated = validate_plan(&projected,&goal,&actions,&candidate,budget);
    trace.validation=if candidate.status == PlanStatus::Ready {
        match validated {
            Ok(())=>"valid_projected_plan".into(),
            Err(err)=>format!("rejected:{err:?}"),
        }
    } else {
        "not_applicable_no_ready_plan".into()
    };
    trace.status=match candidate.status {
        PlanStatus::Ready if validated.is_ok()=>"projected_plan_only".into(),
        PlanStatus::Ready=>"rejected_by_shared_validator".into(),
        PlanStatus::NoPlan=>"no_plan_with_available_owned_sources".into(),
        PlanStatus::BudgetExhausted=>"bounded_search_exhausted".into(),
        PlanStatus::InvalidSnapshot=>"invalid_snapshot".into(),
    };
    trace.reason="10-unit stock-increase probe; results are forecasts, never native dispatch".into();
    trace.proposal=Some(candidate);
    trace
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strategy::planning::{
        FacilityEntry, MarketEntry, PlanningSnapshot, RecipeEntry, ShipEntry, SCHEMA_VERSION,
    };
    use std::collections::BTreeMap;

    fn market(id:&str,facility:&str,location:&str,stock:&[(Commodity,f64)]) -> MarketEntry {
        MarketEntry {market_id:id.into(),facility_id:facility.into(),location_id:location.into(),
            stock:stock.iter().map(|(c,q)|(c.as_str().into(),*q)).collect(),
            demand:BTreeMap::new(),prices:BTreeMap::new()}
    }
    fn fixture() -> (PlanningSnapshot,GoalSpec) {
        let s = PlanningSnapshot{schema_version:SCHEMA_VERSION,tick:20,faction_id:"genesis".into(),
            treasury_credits:30_000,treasury_floor_credits:10_000,
            owned_markets:vec![market("source-market","source-station","belt",&[(Commodity::Ice,20.0)]),
                market("refinery-market","refinery-1","colony",&[(Commodity::Water,0.0)])],
            facilities:vec![FacilityEntry{facility_id:"source-station".into(),location_id:"belt".into(),facility_type:"station".into()},
                FacilityEntry{facility_id:"refinery-1".into(),location_id:"colony".into(),facility_type:"refinery".into()}],
            ships:vec![ShipEntry{ship_id:"carrier".into(),class:"courier".into(),
                location_id:Some("belt".into()),in_transit:false,free_cargo:40,fuel:100.0}],
            active_commitments:vec![],technologies:vec![],
            recipes:vec![RecipeEntry{recipe_id:"process_ice".into(),facility_type:"refinery".into(),
                inputs:vec![(Commodity::Ice,8)],outputs:vec![(Commodity::Water,10),(Commodity::Fuel,5)]}],
        };
        let g=GoalSpec{goal_id:"sustain-water".into(),destination_id:"colony".into(),
            commodity:Commodity::Water,target_units:200,priority:100};
        (s,g)
    }

    #[test]
    fn real_industry_input_shortage_becomes_water_output_goal() {
        let (mut snap, _)=fixture();
        // The tested target has a colocated refinery with process_ice.
        let market=snap.owned_markets.iter_mut()
            .find(|m|m.location_id=="colony").unwrap();
        market.stock.insert("ice".into(),0.0);
        market.stock.insert("water".into(),0.0);
        market.demand.insert("water".into(),8.0);
        market.stock.insert("fuel".into(),1000.0);
        market.demand.insert("fuel".into(),4.0);
        let head=GoalSpec{goal_id:"supply_industry:colony:ice".into(),
            destination_id:"colony".into(),commodity:Commodity::Ice,
            target_units:10,priority:60};
        let promoted=promote_industry_output_goal(&snap,&head).unwrap();
        assert_eq!(promoted.commodity,Commodity::Water);
        assert_eq!(promoted.destination_id,"colony");
        assert!(promoted.goal_id.ends_with(":output:water"));
        let (_,actions,goal,proposal)=native_candidate(&snap,&promoted).unwrap();
        assert_eq!(goal.commodity,Commodity::Water);
        assert!(proposal.steps.iter().any(|step|actions.iter().any(|a|
            a.action_id==step.action_id && a.kind==ActionKind::Produce &&
            a.outputs.iter().any(|(c,_)|*c==Commodity::Water))));
    }

    #[test]
    fn industry_output_goal_requires_actual_local_demand_and_owned_producer() {
        let (mut snap, _)=fixture();
        let head=GoalSpec{goal_id:"supply_industry:colony:ice".into(),
            destination_id:"colony".into(),commodity:Commodity::Ice,
            target_units:10,priority:60};
        let market=snap.owned_markets.iter_mut()
            .find(|m|m.location_id=="colony").unwrap();
        market.demand.insert("water".into(),0.0);
        assert!(promote_industry_output_goal(&snap,&head).is_none());
        snap.owned_markets.iter_mut().find(|m|m.location_id=="colony").unwrap()
            .demand.insert("water".into(),8.0);
        snap.facilities.retain(|f|f.facility_type!="refinery");
        assert!(promote_industry_output_goal(&snap,&head).is_none());
    }

    #[test]
    fn shadow_uses_real_recipe_and_owned_market_stock_without_dispatch() {
        let (snapshot,goal)=fixture();
        let before=serde_json::to_string(&snapshot).unwrap();
        let trace=htn_native_shadow(&snapshot,&goal);
        assert_eq!(trace.status,"projected_plan_only", "{:?}",trace.proposal);
        let plan=trace.proposal.unwrap();
        let names:Vec<_>=plan.steps.iter().map(|s|s.action_id.as_str()).collect();
        assert_eq!(names.len(),2);
        assert!(names[0].contains("deliver") && names[0].contains("ice"));
        assert!(names[1].contains("produce") && names[1].contains("process_ice"));
        assert_eq!(serde_json::to_string(&snapshot).unwrap(),before);
    }

    #[test]
    fn native_station_market_uses_colocated_refinery_not_market_owner() {
        let (mut snapshot,goal)=fixture();
        // Galaxy seed: one market belongs to the station; a distinct, owned
        // refinery module at the location performs the actual recipe tick.
        snapshot.owned_markets[1].facility_id="colony-station".into();
        snapshot.facilities.push(FacilityEntry{facility_id:"colony-station".into(),
            location_id:"colony".into(),facility_type:"station".into()});
        let (projection,actions,projected_goal,proposal)=native_candidate(&snapshot,&goal).unwrap();
        assert_eq!(proposal.status,PlanStatus::Ready);
        assert_eq!(proposal.steps.len(),2);
        let produce=actions.iter().find(|a|a.kind==ActionKind::Produce).unwrap();
        assert_eq!(produce.source_id.as_deref(),Some("refinery-1"));
        assert_eq!(pinned_producer_id(&projection,produce).as_deref(),Some("refinery-1"));
        assert!(produce.action_id.contains("refinery-1:process_ice"));
        assert!(projected_goal.target_units>0);
    }

    #[test]
    fn spoofed_or_missing_native_producer_is_rejected() {
        let (mut snapshot,goal)=fixture();
        snapshot.owned_markets[1].facility_id="colony-station".into();
        snapshot.facilities.push(FacilityEntry{facility_id:"colony-station".into(),
            location_id:"colony".into(),facility_type:"station".into()});
        let (projected,actions,_,_)=native_candidate(&snapshot,&goal).unwrap();
        let legitimate=actions.iter().find(|a|a.kind==ActionKind::Produce).unwrap();
        let mut forged=legitimate.clone();
        forged.source_id=Some("colony-station".into());
        assert_eq!(pinned_producer_id(&projected,&forged),None);
        forged=legitimate.clone();
        forged.action_id="htn-preview:produce:fake-market:refinery-1:process_ice".into();
        assert_eq!(pinned_producer_id(&projected,&forged),None);
        let mut lost=projected.clone();
        lost.facilities.retain(|f|f.facility_id!="refinery-1");
        assert_eq!(pinned_producer_id(&lost,legitimate),None);
    }

    #[test]
    fn ambiguous_destination_never_merges_two_warehouses() {
        let (mut snapshot,goal)=fixture();
        snapshot.owned_markets.push(market("other-market","second-refinery","colony",&[(Commodity::Water,999.0)]));
        let trace=htn_native_shadow(&snapshot,&goal);
        assert_eq!(trace.status,"blocked");
        assert_eq!(trace.reason,"ambiguous_destination_markets");
        assert!(trace.proposal.is_none());
    }

    #[test]
    fn committed_ship_is_not_available_for_a_new_htn_delivery() {
        let (mut snapshot,goal)=fixture();
        snapshot.active_commitments.push(super::super::CommitmentEntry {
            contract_id:"existing".into(),status:"active".into(),source:"belt".into(),
            destination:"colony".into(),commodity:Commodity::Ore,quantity:1,
            assigned_ship_id:Some("carrier".into()),
        });
        let trace=htn_native_shadow(&snapshot,&goal);
        assert_ne!(trace.status,"projected_plan_only");
        assert!(!trace.proposal.as_ref().is_some_and(|p|p.status == PlanStatus::Ready));
    }

    #[test]
    fn missing_destination_market_owner_does_not_invent_production() {
        let (mut snapshot,goal)=fixture();
        snapshot.owned_markets[1].facility_id="station-instead-of-refinery".into();
        let trace=htn_native_shadow(&snapshot,&goal);
        assert_eq!(trace.status,"blocked");
        assert_eq!(trace.reason,"destination_market_owner_missing_or_wrong_location");
        assert!(trace.proposal.is_none());
    }

    #[test]
    fn destination_market_owner_at_another_location_is_rejected() {
        let (mut snapshot,goal)=fixture();
        snapshot.owned_markets[1].facility_id="wrong-location-station".into();
        snapshot.facilities.push(FacilityEntry{facility_id:"wrong-location-station".into(),
            location_id:"belt".into(),facility_type:"station".into()});
        let trace=htn_native_shadow(&snapshot,&goal);
        assert_eq!(trace.status,"blocked");
        assert_eq!(trace.reason,"destination_market_owner_missing_or_wrong_location");
    }

    #[test]
    fn identical_snapshot_generates_identical_shadow_trace() {
        let (snapshot,goal)=fixture();
        let a=htn_native_shadow(&snapshot,&goal);
        let b=htn_native_shadow(&snapshot,&goal);
        assert_eq!(serde_json::to_value(a).unwrap(),serde_json::to_value(b).unwrap());
    }

    #[test]
    fn retried_native_goal_keeps_absolute_stock_target_without_goal_drift() {
        let (mut snapshot,mut goal)=fixture();
        snapshot.owned_markets[1].stock.insert(Commodity::Water.as_str().into(),3.0);
        goal.target_units=10;
        let (_,_,replanned_goal,result)=native_candidate_with_target(&snapshot,&goal,Some(10)).unwrap();
        assert_eq!(replanned_goal.target_units,10);
        assert_eq!(result.status,PlanStatus::Ready);
        let (_,_,fresh_goal,_)=native_candidate(&snapshot,&goal).unwrap();
        assert_eq!(fresh_goal.target_units,13,"a new probe still requests +10");
        assert_eq!(projected_native_target(10,Some(10)),Err("native_goal_already_met"));
    }
}
