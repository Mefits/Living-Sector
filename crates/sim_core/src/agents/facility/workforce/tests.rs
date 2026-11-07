use super::*;
use crate::agents::{facility::{FacilityLifecycle, FacilityCrewSnapshot}, market::{MarketIdentity, MarketPricing, MarketHistory}};
use crate::economy::{commodities::Commodity, contracts::ContractBoard, money::MoneySnapshot};

pub(crate) fn household(world: &mut World, facility: Entity, location: &str, faction: &str,
    count: i64, wealth: i64) -> Entity {
    world.spawn((PopIdentity { db_id:1,id:"workers".into(),label:"Workers".into(),demographic:"workers".into(),
        facility, facility_location:location.into(), faction_id:faction.into() },
        PopDemographics { population_count:count,growth_rate:0.0,employed_fraction:0.0,migration_pressure:0.0 },
        PopEconomy { total_wealth:wealth,spending_rate:1.0,consumption:Default::default(),production_commodity:None,production_amount:0.0 },
        PopSentiment { overall_sentiment:70,unrest:0,food_satisfaction:70,safety_satisfaction:50,entertainment_satisfaction:50,dirty:false })).id()
}

struct Farm { world:World, facility:Entity, market:Entity, people:Entity }
impl Farm {
    fn new(cash:i64, people:i64, water:f32) -> Self {
        let mut world=World::new();
        let mut crew=FacilityCrew::new_for_type("farm"); crew.morale=100.0;
        let facility=world.spawn((FacilityIdentity { db_id:1,id:"farm".into(),name:"Farm".into(),facility_type:"farm".into(),faction_id:"civ".into(),body_id:"earth".into() },
            FacilityLocation { location_id:1,location_name:"port".into() },
            FacilityOperations { docking_capacity:5,services:vec![],condition:1.0,reputation:50,credits:cash,dirty:false,starving_notified:false },
            FacilityLifecycle::new(),crew)).id();
        let market=world.spawn((MarketIdentity { db_id:1,id:"market".into(),facility,facility_location:"port".into() },
            MarketPricing { price_elasticity:0.02,spread:0.1,prices:[(Commodity::Water,1.0),(Commodity::Food,2.0)].into(),
                supply:[(Commodity::Water,water)].into(),demand:Default::default() },MarketHistory::default())).id();
        let people=household(&mut world,facility,"port","civ",people,0);
        Self {world,facility,market,people}
    }
    fn produce(&mut self,tick:u64) {
        refresh_employment(&mut self.world,tick);
        super::super::tick_recipes_and_mining(&mut self.world,tick,1,&[(self.facility,1)].into());
    }
    fn total(&mut self)->i128 { MoneySnapshot::capture(&mut self.world,&ContractBoard::new()).total }
}

#[test]
fn workforce_native_production_wages_consumption_and_next_shift() {
    let mut f=Farm::new(12,10,90.0);
    let before=f.total();
    f.produce(5);
    assert_eq!(f.world.get::<PopEconomy>(f.people).unwrap().total_wealth,6);
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits,6);
    assert!(f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Food]>0.0);
    assert_eq!(f.total(),before);
    let stock=f.world.get::<MarketPricing>(f.market).unwrap().supply.clone();
    f.produce(5);
    assert_eq!(f.world.get::<MarketPricing>(f.market).unwrap().supply,stock);
    assert_eq!(f.world.get::<PopEconomy>(f.people).unwrap().total_wealth,6);
    assert_eq!(crate::agents::population::purchase_consumption(&mut f.world,f.people,f.market,Commodity::Food,3.0,5),Ok((3.0,6)));
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits,12);
    // The next wage payment is financed by actual sales revenue. Inputs are
    // finite; no test-time cash or inventory injections occur.
    f.produce(10);
    assert_eq!(f.world.get::<PopEconomy>(f.people).unwrap().total_wealth,6);
    assert_eq!(crate::agents::population::purchase_consumption(&mut f.world,f.people,f.market,Commodity::Food,3.0,10),Ok((3.0,6)));
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits,12);
    assert_eq!(f.total(),before);
}

#[test]
fn workforce_missing_cash_people_or_inputs_changes_neither_stock_nor_money() {
    for (cash,people,water,reason) in [(5,10,12.0,"insufficient_payroll_budget"),(12,9,12.0,"insufficient_workers"),(12,10,0.0,"no_viable_recipe")] {
        let mut f=Farm::new(cash,people,water);
        let before=f.total(); let stock=f.world.get::<MarketPricing>(f.market).unwrap().supply.clone();
        f.produce(5);
        assert_eq!(f.total(),before);
        assert_eq!(f.world.get::<PopEconomy>(f.people).unwrap().total_wealth,0);
        assert_eq!(f.world.get::<MarketPricing>(f.market).unwrap().supply,stock);
        assert_eq!(f.world.get::<FacilityCrew>(f.facility).unwrap().work_blocked_reason.as_deref(),Some(reason));
    }
}

#[test]
fn workforce_competing_employers_cannot_hire_the_same_residents() {
    let mut f=Farm::new(100,10,12.0);
    let competitor=f.world.spawn((f.world.get::<FacilityIdentity>(f.facility).unwrap().clone(),
        f.world.get::<FacilityLocation>(f.facility).unwrap().clone(),
        f.world.get::<FacilityOperations>(f.facility).unwrap().clone(),FacilityCrew::new_for_type("farm"))).id();
    let before=f.total();
    assert!(pay_shift(&mut f.world,f.facility,f.facility,5,None).is_ok());
    assert_eq!(pay_shift(&mut f.world,competitor,competitor,5,None).unwrap_err(),"insufficient_workers");
    assert_eq!(f.total(),before);
    assert_eq!(f.world.get::<PopDemographics>(f.people).unwrap().employed_fraction,1.0);
}

#[test]
fn workforce_processing_owner_pays_actual_producer_and_households() {
    let mut f=Farm::new(100,10,12.0);
    let producer=f.world.spawn((f.world.get::<FacilityIdentity>(f.facility).unwrap().clone(),
        f.world.get::<FacilityLocation>(f.facility).unwrap().clone(),
        FacilityOperations {credits:0,..f.world.get::<FacilityOperations>(f.facility).unwrap().clone()},FacilityCrew::new_for_type("farm"))).id();
    let before=f.total();
    let receipt=pay_shift(&mut f.world,producer,f.facility,5,None).unwrap();
    assert_eq!(receipt.wages,6); assert_eq!(receipt.processing_fee,7);
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits,93);
    assert_eq!(f.world.get::<FacilityOperations>(producer).unwrap().credits,1);
    assert_eq!(f.world.get::<PopEconomy>(f.people).unwrap().total_wealth,6);
    assert_eq!(f.total(),before);
    // Persisted crew JSON retains labor allocation and prevents repayment.
    let json=serde_json::to_string(&FacilityCrewSnapshot::from(f.world.get::<FacilityCrew>(producer).unwrap())).unwrap();
    let restored:FacilityCrewSnapshot=serde_json::from_str(&json).unwrap();
    f.world.entity_mut(producer).insert(FacilityCrew::from(restored));
    assert_eq!(pay_shift(&mut f.world,producer,f.facility,5,None).unwrap_err(),"already_worked_this_tick");
    assert_eq!(pay_shift(&mut f.world,f.facility,f.facility,5,None).unwrap_err(),"insufficient_workers");
    assert_eq!(f.total(),before);
}
