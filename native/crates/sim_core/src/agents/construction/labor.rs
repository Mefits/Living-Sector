//! Construction draws on the same local residents as paid native production.
use super::ConstructionSite;
use crate::agents::{faction::FactionData, population::{PopIdentity, PopDemographics, PopEconomy, PopSentiment},
    facility::workforce::{occupied_workers, WorkShift, WAGE_PER_SHIFT}};
use bevy_ecs::prelude::{Entity, World};

/// Maximum workers per shift; smaller available crews make proportional progress.
pub const MAX_SHIFT_WORKERS: u32 = 10;

pub fn work(world: &mut World, entity: Entity, tick: u64) -> Result<u32, &'static str> {
    let result = commit(world, entity, tick);
    if let Some(mut site) = world.get_mut::<ConstructionSite>(entity) {
        if result.as_ref().err() != Some(&"already_worked_this_tick") {
            site.labor.blocked_reason = result.as_ref().err().map(|s| s.to_string());
            site.dirty = true;
        }
    }
    result
}

fn commit(world: &mut World, entity: Entity, tick: u64) -> Result<u32, &'static str> {
    let site = world.get::<ConstructionSite>(entity).ok_or("missing_site")?.clone();
    if site.completed { return Err("completed_site"); }
    if site.remaining() > 0 { return Err("awaiting_materials"); }
    if site.labor.last_shift.as_ref().is_some_and(|s| s.tick >= tick) { return Err("already_worked_this_tick"); }
    let needed = site.labor.required.saturating_sub(site.labor.completed).min(MAX_SHIFT_WORKERS);
    if needed == 0 { return Ok(0); }
    let (payer, cash) = world.query::<(Entity, &FactionData)>().iter(world)
        .find(|(_, f)| f.id == site.faction_id).map(|(e,f)| (e,f.treasury)).ok_or("missing_sponsor")?;
    if cash < WAGE_PER_SHIFT { return Err("insufficient_labor_budget"); }
    let executor = super::executor::present(world, &site).ok_or("awaiting_construction_ship")?;
    let occupied = occupied_workers(world, tick);
    let mut candidates: Vec<_> = world.query::<(Entity, &PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
        .iter(world).filter(|(_,id,d,_,_)| id.faction_id == site.faction_id && id.facility_location == site.location_name && d.population_count > 0)
        .map(|(e,id,d,c,_)| (id.id.clone(), e, ((d.population_count as i128 * 3 / 5) as i64
            - occupied.get(&id.id).copied().unwrap_or(0)).max(0), c.total_wealth)).collect();
    candidates.sort_by(|a,b| a.0.cmp(&b.0));
    let mut remaining = i64::from(needed).min(cash / WAGE_PER_SHIFT);
    let mut assignments = Vec::new();
    for (id,e,available,balance) in candidates {
        let count = available.min(remaining);
        if count == 0 { continue; }
        if balance < 0 { return Err("invalid_household_balance"); }
        let after = balance.checked_add(count * WAGE_PER_SHIFT).ok_or("household_credit_overflow")?;
        assignments.push((id,e,count as u16,after));
        remaining -= count;
        if remaining == 0 { break; }
    }
    let workers: u32 = assignments.iter().map(|(_,_,n,_)| u32::from(*n)).sum();
    if workers == 0 { return Err("insufficient_workers"); }
    let wages = i64::from(workers) * WAGE_PER_SHIFT;
    let mut sponsor = world.get_mut::<FactionData>(payer).unwrap();
    sponsor.treasury -= wages; sponsor.dirty = true;
    for (_,e,_,after) in &assignments {
        world.get_mut::<PopEconomy>(*e).unwrap().total_wealth = *after;
        world.get_mut::<PopSentiment>(*e).unwrap().dirty = true;
    }
    let mut site = world.get_mut::<ConstructionSite>(entity).unwrap();
    site.labor.completed += workers;
    site.labor.last_executor = Some(executor);
    site.labor.last_shift = Some(WorkShift { tick, workers: assignments.into_iter().map(|(id,_,n,_)| (id,n)).collect(),
        wages, input_payment: 0, processing_fee: 0, last_recipe_ticks:Default::default(),produced_outputs:Default::default() });
    site.dirty = true;
    crate::agents::facility::workforce::refresh_employment(world, tick);
    Ok(workers)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agents::{construction::ConstructionLabor, faction::FactionColors, facility::{FacilityCrew, workforce}};
    fn fixture() -> (World,Entity,Entity,Entity) {
        let mut w=World::new();
        let payer=w.spawn(FactionData { id:"civ".into(),name:"Civ".into(),faction_type:"normal".into(),home_system:"sol".into(),treasury:150,
            personality:crate::ai::personality::Personality::balanced_trader(),colors:FactionColors {primary:String::new(),secondary:String::new()},active_subsidies:0,dirty:false }).id();
        let people=workforce::tests::household(&mut w,payer,"port","civ",10,0);
        let site=w.spawn(ConstructionSite { id:"site".into(),name:"Site".into(),facility_type:"farm".into(),faction_id:"civ".into(),body_id:"earth".into(),
            location_name:"port".into(),commodity:crate::economy::commodities::Commodity::Metals,progress_delivered:600,progress_required:600,
            position:(0.0,0.0),spawned_at_tick:0,completed:false,dirty:false,labor:ConstructionLabor::default() }).id();
        let dock=w.spawn(crate::agents::facility::FacilityStorage::default()).id();
        let ship=super::super::executor::tests::builder(&mut w,dock);
        w.get_mut::<crate::agents::facility::FacilityStorage>(dock).unwrap().docked_ships.push(ship);
        (w,payer,people,site)
    }
    #[test]
    fn construction_labor_partial_work_payments_and_duplicate_guard() {
        let (mut w,payer,people,site)=fixture();
        assert_eq!(work(&mut w,site,5),Ok(6));
        assert_eq!(w.get::<FactionData>(payer).unwrap().treasury,144);
        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,6);
        assert_eq!(work(&mut w,site,5),Err("already_worked_this_tick"));
        let other=w.spawn(w.get::<ConstructionSite>(site).unwrap().clone()).id();
        w.get_mut::<ConstructionSite>(other).unwrap().labor=Default::default();
        assert_eq!(work(&mut w,other,5),Err("insufficient_workers"));
        for tick in 6..30 { work(&mut w,site,tick).unwrap(); }
        assert_eq!(w.get::<ConstructionSite>(site).unwrap().labor.completed,150);
        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,150);
        assert_eq!(w.get::<FactionData>(payer).unwrap().treasury,0);
    }
    #[test]
    fn construction_labor_failure_and_shared_enterprise_reservation() {
        for reason in ["awaiting_materials","insufficient_labor_budget","insufficient_workers","household_credit_overflow"] {
            let (mut w,payer,people,site)=fixture();
            match reason {
                "awaiting_materials" => w.get_mut::<ConstructionSite>(site).unwrap().progress_delivered=599,
                "insufficient_labor_budget" => w.get_mut::<FactionData>(payer).unwrap().treasury=0,
                "household_credit_overflow" => w.get_mut::<PopEconomy>(people).unwrap().total_wealth=i64::MAX,
                _ => { let mut crew=FacilityCrew::new_for_type("farm");
                    crew.work_shift=Some(WorkShift{ tick:5,workers:vec![("workers".into(),6)],wages:6,input_payment:0,processing_fee:0,last_recipe_ticks:Default::default(),produced_outputs:Default::default() });w.spawn(crew); },
            }
            let cash=w.get::<FactionData>(payer).unwrap().treasury;
            let wealth=w.get::<PopEconomy>(people).unwrap().total_wealth;
            assert_eq!(work(&mut w,site,5),Err(reason));
            assert_eq!(w.get::<ConstructionSite>(site).unwrap().labor.completed,0);
            assert_eq!(w.get::<FactionData>(payer).unwrap().treasury,cash);
            assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,wealth);
        }
    }
}
