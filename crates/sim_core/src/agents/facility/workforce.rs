//! Paid local shifts. Native population wallets and facility crew JSON are the
//! accounts/receipts; there is no second population system or payroll ledger.
use super::{FacilityCrew, FacilityIdentity, FacilityLocation, FacilityOperations};
use crate::agents::population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment};
use bevy_ecs::prelude::{Entity, World};
use std::collections::HashMap;

/// One CR per worker per completed work shift, a prototype wage policy.
pub const WAGE_PER_SHIFT: i64 = 1;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WorkShift {
    pub tick: u64,
    pub workers: Vec<(String, u16)>,
    pub wages: i64,
    pub input_payment: i64,
    pub processing_fee: i64,
}

/// None: stock owner commissions processing and owns both inputs and output.
/// Some(cost): producer buys inputs from stock owner and owns its output.
/// Self-owned stock has no internal payment. All validation precedes writes.
pub fn pay_shift(world: &mut World, producer: Entity, stock_owner: Entity,
    tick: u64, input_payment: Option<i64>) -> Result<WorkShift, &'static str> {
    let outcome = commit_shift(world, producer, stock_owner, tick, input_payment);
    if let Some(mut crew) = world.get_mut::<FacilityCrew>(producer) {
        if outcome.as_ref().err() != Some(&"already_worked_this_tick") {
            crew.work_blocked_reason = outcome.as_ref().err().map(|r| r.to_string());
            crew.dirty = true;
        }
    }
    outcome
}

fn commit_shift(world: &mut World, producer: Entity, stock_owner: Entity,
    tick: u64, input_payment: Option<i64>) -> Result<WorkShift, &'static str> {
    let crew = world.get::<FacilityCrew>(producer).ok_or("missing_workforce")?;
    if crew.work_shift.as_ref().is_some_and(|s| s.tick >= tick) {
        return Err("already_worked_this_tick");
    }
    if input_payment.is_none() && !crate::strategy::station::permits(world, producer, tick) {
        return Err("station_workforce_not_assigned");
    }
    let required = crew.crew_count;
    if required == 0 { return Err("no_staffed_jobs"); }
    let identity = world.get::<FacilityIdentity>(producer).ok_or("missing_employer")?;
    let faction = identity.faction_id.clone();
    let location = world.get::<FacilityLocation>(producer).ok_or("missing_workplace")?.location_name.clone();
    let owner = world.get::<FacilityIdentity>(stock_owner).ok_or("missing_stock_owner")?;
    if owner.faction_id != faction || world.get::<FacilityLocation>(stock_owner)
        .is_none_or(|l| l.location_name != location) { return Err("foreign_workplace_stock"); }
    let occupied = occupied_workers(world, tick);
    let mut candidates: Vec<_> = world.query::<(Entity, &PopIdentity, &PopDemographics, &PopEconomy)>()
        .iter(world).filter(|(_, id, demo, _)| id.facility_location == location && id.faction_id == faction && demo.population_count > 0)
        .map(|(e, id, demo, cash)| (id.id.clone(), e,
            ((demo.population_count as i128 * 3 / 5) as i64 - occupied.get(&id.id).copied().unwrap_or(0)).max(0), cash.total_wealth))
        .collect();
    candidates.sort_by(|a,b| a.0.cmp(&b.0));
    let mut needed = required as i64;
    let mut assignments = Vec::new();
    for (id, entity, available, balance) in candidates {
        let count = available.min(needed);
        if count == 0 { continue; }
        if balance < 0 { return Err("invalid_household_balance"); }
        let after = balance.checked_add(count * WAGE_PER_SHIFT).ok_or("household_credit_overflow")?;
        assignments.push((id, entity, count as u16, after));
        needed -= count;
        if needed == 0 { break; }
    }
    if needed != 0 { return Err("insufficient_workers"); }
    let wages = required as i64 * WAGE_PER_SHIFT;
    let producer_cash = world.get::<FacilityOperations>(producer).ok_or("missing_employer_cash")?.credits;
    let owner_cash = world.get::<FacilityOperations>(stock_owner).ok_or("missing_owner_cash")?.credits;
    if producer_cash < 0 || owner_cash < 0 { return Err("invalid_cash_balance"); }
    let distinct = producer != stock_owner;
    let (producer_after, owner_after, input_cost, fee) = if let Some(cost) = input_payment {
        if cost < 0 { return Err("invalid_input_payment"); }
        let cost = if distinct { cost } else { 0 };
        let debit = wages.checked_add(cost).ok_or("credit_overflow")?;
        if producer_cash < debit { return Err("insufficient_payroll_budget"); }
        (producer_cash - debit, owner_cash.checked_add(cost).ok_or("credit_overflow")?, cost, 0)
    } else if distinct {
        // Local processing service. The stock owner pays wages plus a modest
        // explicit fee to the producer, who retains the fee after paying labor.
        let fee = (wages + 9) / 10;
        let debit = wages + fee;
        if owner_cash < debit { return Err("insufficient_processing_budget"); }
        (producer_cash.checked_add(fee).ok_or("credit_overflow")?, owner_cash - debit, 0, debit)
    } else {
        if producer_cash < wages { return Err("insufficient_payroll_budget"); }
        (producer_cash - wages, producer_cash - wages, 0, 0)
    };
    let shift = WorkShift { tick, workers:assignments.iter().map(|(id,_,count,_)| (id.clone(),*count)).collect(),
        wages, input_payment:input_cost, processing_fee:fee };
    let mut ops = world.get_mut::<FacilityOperations>(producer).unwrap(); ops.credits = producer_after; ops.dirty = true;
    if distinct {
        let mut ops = world.get_mut::<FacilityOperations>(stock_owner).unwrap(); ops.credits = owner_after; ops.dirty = true;
    }
    for (id, entity, count, after) in assignments {
        world.get_mut::<PopEconomy>(entity).unwrap().total_wealth = after;
        let mut demo = world.get_mut::<PopDemographics>(entity).unwrap();
        demo.employed_fraction = ((occupied.get(&id).copied().unwrap_or(0) + count as i64) as f32
            / (demo.population_count as f32 * 0.6).max(1.0)).clamp(0.0,1.0);
        if let Some(mut sent) = world.get_mut::<PopSentiment>(entity) { sent.dirty = true; }
    }
    let mut crew = world.get_mut::<FacilityCrew>(producer).unwrap();
    crew.work_shift = Some(shift.clone()); crew.dirty = true;
    Ok(shift)
}

pub(super) fn blocked(world: &mut World, facility: Entity, reason: &str) {
    if let Some(mut crew) = world.get_mut::<FacilityCrew>(facility) {
        crew.work_blocked_reason = Some(reason.into()); crew.dirty = true;
    }
}

/// Reconstruct latest-shift employment from durable receipts, including on
/// restart at the same tick. Residents not hired remain unemployed.
pub fn refresh_employment(world: &mut World, tick: u64) {
    let counts = occupied_workers(world, tick);
    for (id, mut demo, mut sentiment) in world.query::<(&PopIdentity, &mut PopDemographics, &mut PopSentiment)>().iter_mut(world) {
        demo.employed_fraction = (counts.get(&id.id).copied().unwrap_or(0) as f32
            / (demo.population_count as f32 * 0.6).max(1.0)).clamp(0.0,1.0);
        sentiment.dirty = true;
    }
}

#[cfg(test)]
pub(crate) mod tests;

/// Durable shared labor reservations for factories and construction sites.
pub fn occupied_workers(world: &mut World, tick: u64) -> HashMap<String, i64> {
    let mut result = HashMap::new();
    let mut shifts: Vec<_> = world.query::<&FacilityCrew>().iter(world)
        .filter_map(|crew| crew.work_shift.clone()).collect();
    shifts.extend(world.query::<&crate::agents::construction::ConstructionSite>().iter(world)
        .filter_map(|site| site.labor.last_shift.clone()));
    for shift in shifts { if shift.tick == tick {
        for (id, count) in shift.workers { *result.entry(id).or_insert(0) += i64::from(count); }
    }}
    result
}
