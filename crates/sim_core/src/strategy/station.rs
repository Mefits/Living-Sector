//! Station-wide workforce decisions; native payroll remains the only money writer.
//! One administrator per (faction, location). Plans are projections, not wallets.
use bevy_ecs::prelude::*;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use crate::agents::{facility::{FacilityIdentity,FacilityLocation,FacilityCrew,FacilityOperations,FacilityLifecycle,workforce},
    population::{PopIdentity,PopDemographics},market::{MarketIdentity,MarketPricing,MarketHistory},
    celestial_body::{BodyIdentity,BodyResources}};
use crate::economy::{commodities::Commodity,recipes};

#[derive(Clone,Debug,Serialize)]
pub struct ModuleDecision {
    pub facility_id:String,
    pub facility_type:String,
    pub required_workers:u16,
    pub assigned_workers:u16,
    pub score:f32,
    pub priority_commodity:Option<Commodity>,
    pub head_priority:bool,
    pub retained:bool,
    pub reason:String,
    pub actual_workers:u16,
    pub execution_reason:Option<String>,
}
/// Non-executable request for the next dispatch layer. No cargo/ship reservation.
#[derive(Clone,Debug,Serialize)]
pub struct Need { pub facility_id:String, pub commodity:Commodity, pub kind:&'static str }
#[derive(Clone,Debug,Serialize)]
pub struct StationView {
    pub faction_id:String,
    pub location:String,
    pub observed_tick:u64,
    pub executing:bool,
    pub workforce:i64,
    pub already_working:i64,
    pub assigned_workers:i64,
    pub idle_workers:i64,
    pub head_priority:Option<Commodity>,
    pub modules:Vec<ModuleDecision>,
    pub needs:Vec<Need>,
}
#[derive(Resource,Default)]
pub struct StationAdministration {
    pub tick:Option<u64>,
    pub executing:bool,
    pub stations:Vec<StationView>,
    allocations:HashMap<Entity,u16>,
}

pub fn permits(world:&World, facility:Entity, tick:u64) -> bool {
    world.get_resource::<StationAdministration>().is_none_or(|state|
        !state.executing || state.tick!=Some(tick) || state.allocations.get(&facility).is_none_or(|n|*n>0))
}

fn urgency(c:Commodity, supply:&HashMap<Commodity,f32>, shortages:&HashMap<Commodity,u32>) -> f32 {
    let stock=supply.get(&c).copied().unwrap_or(0.0).max(0.0);
    let essential=match c {Commodity::Food|Commodity::Water=>3.0,Commodity::Fuel=>2.0,_=>1.0};
    // Stock influences priority under labor scarcity, never a hard production cap.
    10.0 + essential * 40.0/(1.0+stock/20.0) + shortages.get(&c).copied().unwrap_or(0).min(100) as f32 * 0.2
}

/// Invoked after repair/restock and before production, on the native work cadence.
/// Full work teams preserve existing recipe throughput; idle staff stays local.
pub fn plan(world:&mut World,tick:u64) {
    if world.get_resource::<StationAdministration>().is_some_and(|s|s.tick==Some(tick)) { return; }
    let execute=super::executing(world);
    let previous:HashMap<String,bool>=world.get_resource::<StationAdministration>().map(|s|s.stations.iter()
        .flat_map(|v|v.modules.iter().map(|m|(m.facility_id.clone(),m.assigned_workers>0))).collect()).unwrap_or_default();
    let occupied=workforce::occupied_workers(world,tick);
    let mut population:BTreeMap<(String,String),(i64,i64)>=BTreeMap::new();
    for (id,demo) in world.query::<(&PopIdentity,&PopDemographics)>().iter(world) {
        let value=population.entry((id.faction_id.clone(),id.facility_location.clone())).or_default();
        value.0=value.0.saturating_add((demo.population_count.max(0) as i128*3/5) as i64);
        value.1=value.1.saturating_add(occupied.get(&id.id).copied().unwrap_or(0));
    }
    let priorities:HashMap<(String,String),Commodity>=world.get_resource::<super::StrategyState>().map(|s|s.factions.values()
        .filter_map(|f| f.head.as_ref().and_then(|h|h.problem.as_ref()).map(|g|((f.faction_id.clone(),g.destination.clone()),g.commodity)))
        .collect()).unwrap_or_default();
    let markets:HashMap<String,(Entity,MarketPricing,HashMap<Commodity,u32>)>=world.query::<(&MarketIdentity,&MarketPricing,&MarketHistory)>().iter(world)
        .map(|(id,p,h)|(id.facility_location.clone(),(id.facility,p.clone(),h.shortage_ticks.clone()))).collect();
    let bodies:HashMap<String,HashMap<Commodity,f32>>=world.query::<(&BodyIdentity,&BodyResources)>().iter(world)
        .map(|(id,r)|(id.body_id.clone(),r.resources.clone())).collect();
    let owners:HashMap<Entity,(String,i64)>=world.query::<(Entity,&FacilityIdentity,&FacilityOperations)>().iter(world)
        .map(|(e,id,ops)|(e,(id.faction_id.clone(),ops.credits))).collect();
    let mut groups:BTreeMap<(String,String),Vec<_>>=BTreeMap::new();
    for (e,id,loc,crew,life) in world.query::<(Entity,&FacilityIdentity,&FacilityLocation,&FacilityCrew,&FacilityLifecycle)>().iter(world) {
        if id.facility_type == super::colony::DOCK_TYPE { continue; }
        groups.entry((id.faction_id.clone(),loc.location_name.clone())).or_default().push((e,id.clone(),crew.clone(),life.abandoned));
    }
    let mut state=StationAdministration {tick:Some(tick),executing:execute,..Default::default()};
    let mut budgets:HashMap<Entity,i64>=owners.iter().map(|(e,(_,cash))|(*e,*cash)).collect();
    for ((faction,location),mut facilities) in groups {
        facilities.sort_by(|a,b|a.1.id.cmp(&b.1.id));
        let (workforce,working)=population.get(&(faction.clone(),location.clone())).copied().unwrap_or_default();
        let head=priorities.get(&(faction.clone(),location.clone())).copied();
        let mut view=StationView {faction_id:faction.clone(),location:location.clone(),observed_tick:tick,executing:execute,
            workforce,already_working:working,assigned_workers:0,idle_workers:(workforce-working).max(0),head_priority:head,modules:vec![],needs:vec![]};
        let mut candidates=Vec::new();
        for (entity,id,crew,abandoned) in facilities {
            let mining=id.facility_type=="mining_rig"||id.facility_type=="salvage_field";
            let recipes:Vec<_>=recipes::for_facility_type(&id.facility_type).collect();
            let managed=mining||!recipes.is_empty();
            let mut decision=ModuleDecision {facility_id:id.id.clone(),facility_type:id.facility_type.clone(),required_workers:crew.crew_count,
                assigned_workers:0,score:0.0,priority_commodity:None,head_priority:false,retained:false,reason:"outside_production_scope".into(),actual_workers:0,execution_reason:None};
            if !managed {view.modules.push(decision);continue;}
            state.allocations.insert(entity,0);
            let paid=crew.work_shift.as_ref().filter(|s|s.tick==tick);
            if let Some(shift)=paid { decision.reason="already_worked".into(); decision.actual_workers=shift.workers.iter().map(|(_,n)|*n).sum();view.modules.push(decision);continue; }
            if abandoned || crew.crew_count==0 {decision.reason=if abandoned {"abandoned"}else{"no_jobs"}.into();view.modules.push(decision);continue;}
            let Some((owner,pricing,shortages))=markets.get(&location) else {decision.reason="missing_market".into();view.modules.push(decision);continue;};
            if owners.get(owner).is_none_or(|(f,_)|*f!=faction) {decision.reason="foreign_stock_owner".into();view.modules.push(decision);continue;}
            let mut outputs=Vec::new();
            if mining {
                if let Some(resources)=bodies.get(&id.body_id) { outputs.extend(resources.iter().filter(|(_,r)|r.is_finite()&&**r>0.0).map(|(c,_)|*c)); }
            } else {
                for recipe in recipes {
                    let mut stock=pricing.supply.clone();
                    if !recipes::execute(recipe,&mut stock,crew.efficiency(),1,Some(&pricing.prices)).is_empty() {
                        outputs.extend(recipe.outputs.iter().map(|(c,_)|*c));
                    } else {
                        for (c,_) in recipe.inputs {if pricing.supply.get(c).copied().unwrap_or(0.0)<=0.0 {
                            view.needs.push(Need{facility_id:id.id.clone(),commodity:*c,kind:"supply_input"});
                        }}
                    }
                }
            }
            outputs.sort_by_key(|c|c.as_str());outputs.dedup();
            let best=outputs.into_iter().map(|c|(c,urgency(c,&pricing.supply,shortages)+if Some(c)==head {100.0}else{0.0}))
                .max_by(|a,b|a.1.total_cmp(&b.1).then_with(||b.0.as_str().cmp(a.0.as_str())));
            let Some((commodity,score))=best else {decision.reason=if mining {"no_extractable_resource"}else{"no_viable_recipe"}.into();view.modules.push(decision);continue;};
            decision.priority_commodity=Some(commodity);decision.head_priority=Some(commodity)==head;
            decision.retained=previous.get(&id.id).copied().unwrap_or(false);
            decision.score=score*if decision.retained {1.15}else{1.0};
            decision.reason="candidate".into();
            let wage=i64::from(crew.crew_count)*workforce::WAGE_PER_SHIFT;
            let cost=wage+if *owner!=entity {(wage+9)/10}else{0};
            candidates.push((entity,*owner,cost,decision));
        }
        candidates.sort_by(|a,b|b.3.score.total_cmp(&a.3.score).then_with(||a.3.facility_id.cmp(&b.3.facility_id)));
        for (e,owner,cost,mut d) in candidates {
            let budget=budgets.entry(owner).or_default();
            if view.idle_workers<i64::from(d.required_workers) {d.reason="insufficient_station_workers".into();}
            else if *budget<cost {d.reason="insufficient_existing_budget".into();}
            else {d.assigned_workers=d.required_workers;d.reason=if d.head_priority {"head_priority"}else if d.retained {"retain_viable_assignment"}else{"local_need"}.into();
                view.idle_workers-=i64::from(d.required_workers);view.assigned_workers+=i64::from(d.required_workers);*budget-=cost;
                state.allocations.insert(e,d.required_workers);}
            view.modules.push(d);
        }
        view.modules.sort_by(|a,b|a.facility_id.cmp(&b.facility_id));
        view.needs.sort_by(|a,b|a.facility_id.cmp(&b.facility_id).then_with(||a.commodity.as_str().cmp(b.commodity.as_str())));
        view.needs.dedup_by(|a,b|a.facility_id==b.facility_id&&a.commodity==b.commodity);
        state.stations.push(view);
    }
    world.insert_resource(state);
}

/// Record actual execution separately from the administrator's allocation.
pub fn feedback(world:&mut World,tick:u64) {
    let results:HashMap<String,(u16,Option<String>)>=world.query::<(&FacilityIdentity,&FacilityCrew)>().iter(world)
        .map(|(id,c)| (id.id.clone(),(c.work_shift.as_ref().filter(|s|s.tick==tick).map(|s|s.workers.iter().map(|(_,n)|*n).sum()).unwrap_or(0),c.work_blocked_reason.clone()))).collect();
    if let Some(mut state)=world.get_resource_mut::<StationAdministration>() {
        for v in &mut state.stations {for m in &mut v.modules {
            if let Some((n,reason))=results.get(&m.facility_id) {m.actual_workers=*n;m.execution_reason=reason.clone();}
        }}
    }
}

#[cfg(test)]
mod tests;
