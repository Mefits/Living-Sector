"""Galaxy 0.5 E5: actual paid station-core upgrade executor.

Called from normal server tick after faction policy, with the current ECS
rather than planner guesses. Draws goods from real local market inventory,
moves CR to its real owner, and separately pays workforce labor over
many shifts. Each receipt persists with the Director economic frame.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
server=root/"crates/sim_server/src"

def one(path,a,b):
    s=path.read_text(encoding="utf8")
    if s.count(a)!=1:raise RuntimeError(f"Galaxy05 native E5 source drift: {path} {a[:85]!r}")
    path.write_text(s.replace(a,b,1),encoding="utf8")

p=server/"engine.rs"
one(p,
    """        colony::prepare_docks(&mut world, &mut store, &registry, &mut events);""",
    """        // T2/T3 paid core work is part of this real ECS tick,
        // and persists with the existing economic checkpoint.
        sim_core::strategy::progression::tick_native_upgrades(
            &mut world,&mut events,tick,tick_mult);
        colony::prepare_docks(&mut world, &mut store, &registry, &mut events);""")

p=core/"strategy/progression.rs"
s=p.read_text(encoding="utf8")
if "pub fn tick_native_upgrades" in s:raise RuntimeError("E5 already added")
s+=r'''

use bevy_ecs::prelude::{Entity,World};
use crate::agents::{
    faction::FactionData,
    facility::{FacilityIdentity,FacilityLocation,FacilityOperations,workforce},
    market::{MarketIdentity,MarketPricing,MarketHistory},
    population::{PopIdentity,PopDemographics,PopEconomy,PopSentiment},
};
use super::director::Director;

fn upgrade_block(world:&mut World,station:&str,reason:&str) {
    if let Some(mut d)=world.get_resource_mut::<Director>() {
        let s=d.station_progress.entry(station.into()).or_default();
        if s.blocked_reason!=reason{s.blocked_reason=reason.into();}
    }
}

/// Advance exactly one physical paid upgrade step per station and cycle.
/// Never reward an intent. Whole material charge is atomic with stock debit
/// and source wallet credit. Labor is a separate 10-worker paid shift.
pub fn tick_native_upgrades(
    world:&mut World,
    events:&mut Vec<serde_json::Value>,
    tick:u64,
    tick_multiplier:u32
) {
    if !super::executing(world)||world.get_resource::<Director>().is_none(){return;}
    let cadence=60_u64.saturating_mul(u64::from(tick_multiplier.max(1)));
    if tick==0 || tick%cadence!=0 {return;}
    let mut stations:Vec<_>=world.query::<(&FacilityIdentity,&FacilityLocation)>()
        .iter(world).filter(|(f,_)|f.facility_type=="station")
        .map(|(f,l)|(f.id.clone(),f.faction_id.clone(),l.location_name.clone()))
        .collect();
    stations.sort_by(|a,b|a.2.ends_with("-colony").cmp(&b.2.ends_with("-colony"))
        .then_with(||a.1.cmp(&b.1)).then_with(||a.0.cmp(&b.0)));
    for (station,faction,location) in stations {
        let record=world.resource::<Director>().station_progress
            .get(&station).cloned().unwrap_or_default();
        let Some(target)=record.tier.next() else{continue;};
        let Some((crisis,tech))=world.resource::<Director>()
            .commanders.get(&faction).map(|c|(c.crisis,c.technologies.clone()))
            else{continue;};
        if crisis {upgrade_block(world,&station,"life_support_priority");continue;}
        if !upgrade_research_ready(record.tier,target,&tech) {
            upgrade_block(world,&station,"research_required");continue;
        }
        let owner_market:Vec<_>=world.query::<(Entity,&MarketIdentity,&MarketPricing)>()
            .iter(world).map(|(e,id,p)|(e,id.facility,id.facility_location.clone(),p.clone()))
            .collect();
        let Some((market,owner,_,pricing))=owner_market.into_iter()
            .find(|(_,_,loc,_)|*loc==location) else{
            upgrade_block(world,&station,"missing_station_market");continue;
        };
        if world.get::<FacilityIdentity>(owner)
            .is_none_or(|id|id.faction_id!=faction) {
            upgrade_block(world,&station,"foreign_market_owner");continue;
        }
        let Some((payer,treasury))=world.query::<(Entity,&FactionData)>()
            .iter(world).find(|(_,f)|f.id==faction)
            .map(|(e,f)|(e,f.treasury)) else {continue;};
        if !record.materials_installed {
            let mut sum=0_i64;
            let mut block=None;
            for &(commodity,quantity) in native_upgrade_bill(target) {
                let have=pricing.supply.get(&commodity).copied().unwrap_or(0.0);
                if !have.is_finite()||have<quantity as f32 {
                    block=Some(format!("awaiting_{}",commodity.as_str()));break;
                }
                let price=pricing.price(commodity);
                if !price.is_finite()||price<0.0||price>10_000.0 {
                    block=Some("invalid_price".into());break;
                }
                let amount=(f64::from(price)*f64::from(quantity)).ceil();
                if amount<0.0||amount>=i64::MAX as f64 {
                    block=Some("price_overflow".into());break;
                }
                let Some(next)=sum.checked_add(amount as i64) else {
                    block=Some("price_overflow".into());break;
                };
                sum=next;
            }
            if let Some(reason)=block {
                upgrade_block(world,&station,&reason);continue;
            }
            if treasury.checked_sub(sum).is_none_or(|after|after<10_000) {
                upgrade_block(world,&station,"insufficient_project_budget");continue;
            }
            let Some(owner_balance)=world.get::<FacilityOperations>(owner)
                .and_then(|x|x.credits.checked_add(sum)) else {
                upgrade_block(world,&station,"owner_credit_overflow");continue;
            };
            // Real market units consumed; real faction credits transferred.
            {
                let mut pricing=world.get_mut::<MarketPricing>(market).unwrap();
                for &(commodity,quantity) in native_upgrade_bill(target) {
                    *pricing.supply.get_mut(&commodity).unwrap()-=quantity as f32;
                }
            }
            if let Some(mut hist)=world.get_mut::<MarketHistory>(market) {hist.dirty=true;}
            {
                let mut account=world.get_mut::<FactionData>(payer).unwrap();
                account.treasury-=sum;account.dirty=true;
            }
            {
                let mut owner_cash=world.get_mut::<FacilityOperations>(owner).unwrap();
                owner_cash.credits=owner_balance;owner_cash.dirty=true;
            }
            {
                let mut director=world.resource_mut::<Director>();
                let state=director.station_progress.entry(station.clone()).or_default();
                state.target=Some(target);
                state.materials_installed=true;
                state.last_receipt_tick=Some(tick);
                state.blocked_reason.clear();
            }
            events.push(serde_json::json!({"kind":"station_upgrade_materials_paid",
                "station_id":station,"tick":tick,"faction_id":faction,
                "tier":format!("{target:?}").to_lowercase(),
                "credits_transferred":sum}));
            continue;
        }
        // Worker shifts are paid separately, after materials have been
        // physically consumed. Multiple workers cannot be assigned twice
        // in the same native tick.
        if record.last_labor_tick.is_some_and(|t|t>=tick){continue;}
        if treasury<10_010 {
            upgrade_block(world,&station,"insufficient_payroll_budget");continue;
        }
        let occupied=workforce::occupied_workers(world,tick);
        let mut persons:Vec<_>=world.query::<(Entity,&PopIdentity,&PopDemographics,&PopEconomy)>()
            .iter(world).filter(|(_,id,d,_)|id.faction_id==faction &&
                id.facility_location==location &&
                d.population_count*3/5-occupied.get(&id.id).copied().unwrap_or(0)>=10)
            .map(|(e,id,_,cash)|(id.id.clone(),e,cash.total_wealth)).collect();
        persons.sort_by(|a,b|a.0.cmp(&b.0));
        let Some((worker_id,pop,wallet))=persons.first() else {
            upgrade_block(world,&station,"insufficient_workers");continue;
        };
        let Some(new_wallet)=wallet.checked_add(10) else {
            upgrade_block(world,&station,"worker_wallet_overflow");continue;
        };
        {
            let mut account=world.get_mut::<FactionData>(payer).unwrap();
            account.treasury-=10;account.dirty=true;
        }
        world.get_mut::<PopEconomy>(*pop).unwrap().total_wealth=new_wallet;
        if let Some(mut mood)=world.get_mut::<PopSentiment>(*pop){mood.dirty=true;}
        let done;
        {
            let mut director=world.resource_mut::<Director>();
            let state=director.station_progress.entry(station.clone()).or_default();
            state.labor_completed=state.labor_completed.saturating_add(10);
            state.last_labor_tick=Some(tick);
            state.last_receipt_tick=Some(tick);
            state.blocked_reason.clear();
            done=state.labor_completed>=upgrade_work(target);
            if done {
                state.tier=target;
                state.target=None;
                state.materials_installed=false;
                state.labor_completed=0;
            }
        }
        events.push(serde_json::json!({"kind":if done {"station_upgraded"}else{"station_upgrade_shift"},
            "tick":tick,"station_id":station,"faction_id":faction,
            "tier":format!("{target:?}").to_lowercase(),
            "worker_id":worker_id,"wages_paid":10}));
    }
}
'''
p.write_text(s,encoding="utf8")
print("Galaxy05: paid station upgrade native ECS executor attached to server tick")
