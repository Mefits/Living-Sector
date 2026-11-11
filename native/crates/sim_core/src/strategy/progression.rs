//! Galaxy 0.5 domain rules for *real* station tier upgrades.
 //!
 //! This module is deliberately pure: it knows no ECS, credits,
 //! stock ledgers, construction receipts, docking capacity, or
 //! artificial progress. A higher tier is never inferred from
 //! how many building glyphs are rendered on the Observer map.
 //!
 //! E2–E7 will read the actual world and native paid construction
 //! receipts before persisting an upgrade. T2/T3 resources still
 //! require their own real production implementation.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StationTier {
    #[default] T1,
    T2,
    T3,
}

impl StationTier {
    pub const fn max_modules(self) -> usize {
        match self {Self::T1=>4, Self::T2=>5, Self::T3=>6}
    }

    pub const fn next(self) -> Option<Self> {
        match self {Self::T1=>Some(Self::T2), Self::T2=>Some(Self::T3), Self::T3=>None}
    }

    pub const fn research_gate(self) -> Option<&'static str> {
        match self {
            Self::T1=>None,
            Self::T2=>Some("structuretech2"),
            Self::T3=>Some("structuretech3"),
        }
    }
}

/// This only checks counts passed by the caller. It is NOT a
/// building-spawn capability and does not create a reserved slot.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SlotAvailability {
    Available{remaining:usize},
    Full{capacity:usize},
    InvalidCounts,
}

pub fn available_slot(tier:StationTier, built:usize, native_in_progress:usize)->SlotAvailability {
    let Some(occupied)=built.checked_add(native_in_progress) else {
        return SlotAvailability::InvalidCounts;
    };
    let cap=tier.max_modules();
    if occupied>=cap {SlotAvailability::Full{capacity:cap}}
    else {SlotAvailability::Available{remaining:cap-occupied}}
}

/// The research gate may only be consulted BEFORE a real funded site starts.
/// Actual paid goods and labor are checked by the native executor and
/// must be revalidated again before commitment; this function never
/// upgrades or creates station tiers.
pub fn upgrade_research_ready(
    current:StationTier, target:StationTier, completed:&[String]
)->bool {
    current.next()==Some(target) &&
    target.research_gate().is_some_and(|id|completed.iter().any(|t|t==id))
}

/// Design-mapping metadata, not recipes that Genesis is allowed to execute.
pub struct CampaignDependency {
    pub milestone:&'static str,
    pub must_follow:&'static [&'static str],
    pub tier:StationTier,
    pub native:bool,
}
pub const CAMPAIGN_DEPENDENCIES:&[CampaignDependency]=&[
    CampaignDependency{milestone:"alloytech2", must_follow:&["automation"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"drilltech2", must_follow:&["alloytech2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"rare_ore", must_follow:&["drilltech2","survey2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"alloys", must_follow:&["rare_ore","alloyplant2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"station2", must_follow:&["alloys","structuretech2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"crystal_ore", must_follow:&["drill3","survey3"],tier:StationTier::T3,native:false},
    CampaignDependency{milestone:"quantum_cores", must_follow:&["crystal_ore","qfab3"],tier:StationTier::T3,native:false},
    CampaignDependency{milestone:"station3", must_follow:&["quantum_cores","structuretech3"],tier:StationTier::T3,native:false},
];

#[cfg(test)]
mod galaxy05_progression_tests {
    use super::*;

    #[test]
    fn tier_slot_limits_and_old_save_default() {
        assert_eq!(StationTier::default(), StationTier::T1);
        assert_eq!(StationTier::T1.max_modules(),4);
        assert_eq!(StationTier::T2.max_modules(),5);
        assert_eq!(StationTier::T3.max_modules(),6);
        assert_eq!(serde_json::from_str::<StationTier>(r#""t2""#).unwrap(),StationTier::T2);
        assert_eq!(serde_json::to_string(&StationTier::T3).unwrap(),r#""t3""#);
    }

    #[test]
    fn construction_is_an_occupied_slot_before_completion() {
        assert_eq!(available_slot(StationTier::T1,3,1),SlotAvailability::Full{capacity:4});
        assert_eq!(available_slot(StationTier::T1,3,0),SlotAvailability::Available{remaining:1});
        assert_eq!(available_slot(StationTier::T2,3,1),SlotAvailability::Available{remaining:1});
        assert_eq!(available_slot(StationTier::T3,3,1),SlotAvailability::Available{remaining:2});
        assert_eq!(available_slot(StationTier::T1,usize::MAX,5),SlotAvailability::InvalidCounts);
    }

    #[test]
    fn research_without_a_paid_build_does_not_change_tier() {
        let unlocked=vec!["structuretech2".into(),"structuretech3".into()];
        assert!(upgrade_research_ready(StationTier::T1,StationTier::T2,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T1,StationTier::T3,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T2,StationTier::T2,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T2,StationTier::T3,&[]));
        // Function only returns a gate verdict; there is no upgrade side effect.
        assert_eq!(StationTier::default(),StationTier::T1);
    }

    #[test]
    fn all_design_nodes_still_explicitly_marked_unimplemented() {
        assert!(CAMPAIGN_DEPENDENCIES.iter().all(|entry|!entry.native));
        assert!(CAMPAIGN_DEPENDENCIES.iter().any(|d|d.milestone=="station3" &&
            d.must_follow.contains(&"quantum_cores")));
    }
}


/// Persistent native upgrade state, not the XP level of an individual
/// facility. The absent record on old saves means a T1 core.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct StationDevelopment {
    pub tier:StationTier,
    pub target:Option<StationTier>,
    pub materials_installed:bool,
    pub labor_completed:u32,
    pub last_labor_tick:Option<u64>,
    pub last_receipt_tick:Option<u64>,
    pub blocked_reason:String,
}
pub const fn native_upgrade_bill(target:StationTier)->&'static [(crate::economy::commodities::Commodity,u32)]{
    use crate::economy::commodities::Commodity as C;
    match target {
        StationTier::T1=>&[],
        StationTier::T2=>&[(C::Metals,240),(C::Components,100),(C::Alloys,40)],
        StationTier::T3=>&[(C::Alloys,160),(C::Electronics,80),(C::QuantumCores,36)],
    }
}
pub const fn upgrade_work(target:StationTier)->u32{
    match target {StationTier::T1=>0,StationTier::T2=>150,StationTier::T3=>250}
}
pub fn core_tier(world:&bevy_ecs::prelude::World,id:&str)->StationTier{
    world.get_resource::<super::director::Director>()
        .and_then(|d|d.station_progress.get(id))
        .map_or(StationTier::T1,|state|state.tier)
}
pub fn location_tier(world:&mut bevy_ecs::prelude::World,faction:&str,location:&str)->StationTier{
    use crate::agents::facility::{FacilityIdentity,FacilityLocation};
    let id=world.query::<(&FacilityIdentity,&FacilityLocation)>()
        .iter(world).find(|(id,loc)|id.facility_type=="station" &&
            id.faction_id==faction && loc.location_name==location)
        .map(|(id,_)|id.id.clone());
    id.as_deref().map_or(StationTier::T1,|id|core_tier(world,id))
}
#[cfg(test)]
mod galaxy05_core_progress_tests {
    use super::*;
    #[test]
    fn old_world_t1_and_native_material_bills_are_nonempty() {
        let old:StationDevelopment=serde_json::from_str("{}").unwrap();
        assert_eq!(old.tier,StationTier::T1);
        assert!(!old.materials_installed);
        assert_eq!(upgrade_work(StationTier::T2),150);
        assert_eq!(upgrade_work(StationTier::T3),250);
        assert_eq!(native_upgrade_bill(StationTier::T2).len(),3);
        assert_eq!(native_upgrade_bill(StationTier::T3).len(),3);
    }
}


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
