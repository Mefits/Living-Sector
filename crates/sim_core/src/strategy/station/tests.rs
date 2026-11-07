use super::*;
use crate::strategy::{StrategyState,Mode};
use crate::agents::population::PopEconomy;
use crate::economy::{contracts::ContractBoard,money::MoneySnapshot};

fn module(w:&mut World,id:&str,kind:&str)->Entity {
    let mut crew=FacilityCrew::new_for_type(kind);crew.crew_count=6;crew.morale=100.0;
    w.spawn((FacilityIdentity {db_id:1,id:id.into(),name:id.into(),facility_type:kind.into(),faction_id:"civ".into(),body_id:"earth".into()},
        FacilityLocation {location_id:1,location_name:"port".into()},
        FacilityOperations {docking_capacity:5,services:vec![],condition:1.0,reputation:50,credits:100,dirty:false,starving_notified:false},
        FacilityLifecycle::new(),crew)).id()
}
fn fixture(mode:Mode)->(World,Entity,Entity,Entity,Entity) {
    let mut w=World::new();w.insert_resource(StrategyState{mode,..Default::default()});
    let farm=module(&mut w,"a-farm","farm");let refinery=module(&mut w,"z-refinery","refinery");
    let pop=workforce::tests::household(&mut w,farm,"port","civ",10,0);
    let market=w.spawn((MarketIdentity {db_id:1,id:"market".into(),facility:farm,facility_location:"port".into()},
        MarketPricing {price_elasticity:0.02,spread:0.1,prices:HashMap::new(),
            supply:[(Commodity::Water,30.0),(Commodity::Ice,80.0),(Commodity::Food,1000.0),(Commodity::Fuel,1000.0)].into(),demand:HashMap::new()},
        MarketHistory::default())).id();
    (w,farm,refinery,pop,market)
}
fn assigned(w:&World,id:&str)->u16 {w.resource::<StationAdministration>().stations[0].modules.iter().find(|m|m.facility_id==id).unwrap().assigned_workers}

#[test]
fn station_admin_real_production_follows_need_not_entity_order() {
    let (mut w,farm,refinery,pop,market)=fixture(Mode::Execute);
    let mut board=ContractBoard::new();let total=MoneySnapshot::capture(&mut w,&board).total;
    crate::agents::facility::tick_facilities(&mut w,&mut board,&mut vec![],5,0.0,1);
    assert_eq!(assigned(&w,"a-farm"),0);assert_eq!(assigned(&w,"z-refinery"),6);
    assert_eq!(w.get::<MarketPricing>(market).unwrap().supply[&Commodity::Food],1000.0);
    assert!(w.get::<MarketPricing>(market).unwrap().supply[&Commodity::Water]>30.0);
    assert_eq!(w.get::<PopEconomy>(pop).unwrap().total_wealth,6);
    assert_eq!(w.get::<FacilityCrew>(farm).unwrap().work_blocked_reason.as_deref(),Some("station_workforce_not_assigned"));
    assert!(w.get::<FacilityCrew>(refinery).unwrap().work_shift.is_some());
    assert_eq!(MoneySnapshot::capture(&mut w,&board).total,total);
    assert_eq!(w.resource::<StationAdministration>().stations[0].modules.iter().map(|m|u32::from(m.actual_workers)).sum::<u32>(),6);
}

#[test]
fn station_admin_reallocates_when_need_changes_and_keeps_small_changes_stable() {
    let (mut w,_,_,_,market)=fixture(Mode::Execute);
    plan(&mut w,5);assert_eq!(assigned(&w,"z-refinery"),6);
    w.get_mut::<MarketPricing>(market).unwrap().supply.insert(Commodity::Water,31.0);
    plan(&mut w,10);assert_eq!(assigned(&w,"z-refinery"),6);
    {let mut p=w.get_mut::<MarketPricing>(market).unwrap();p.supply.insert(Commodity::Food,0.0);p.supply.insert(Commodity::Water,1000.0);}
    plan(&mut w,15);assert_eq!(assigned(&w,"a-farm"),6);assert_eq!(assigned(&w,"z-refinery"),0);
}

#[test]
fn station_admin_shadow_budget_failures_and_locality() {
    let (mut w,farm,refinery,pop,_)=fixture(Mode::Shadow);
    plan(&mut w,5);assert!(permits(&w,farm,5));assert!(permits(&w,refinery,5));
    assert_eq!(w.get::<PopEconomy>(pop).unwrap().total_wealth,0);
    assert_eq!(w.get::<FacilityOperations>(farm).unwrap().credits,100);
    w.resource_mut::<StrategyState>().mode=Mode::Execute;
    w.get_mut::<FacilityOperations>(farm).unwrap().credits=0;
    plan(&mut w,10);assert_eq!(w.resource::<StationAdministration>().stations[0].assigned_workers,0);
    w.get_mut::<FacilityOperations>(farm).unwrap().credits=100;
    w.get_mut::<PopIdentity>(pop).unwrap().facility_location="other-station".into();
    plan(&mut w,15);assert_eq!(w.resource::<StationAdministration>().stations[0].workforce,0);
    assert_eq!(w.resource::<StationAdministration>().stations[0].assigned_workers,0);
}

#[test]
fn station_admin_restart_reconstructs_paid_shift_without_double_allocation() {
    let (mut w,farm,refinery,_,_)=fixture(Mode::Execute);
    plan(&mut w,5);workforce::pay_shift(&mut w,refinery,farm,5,None).unwrap();
    w.remove_resource::<StationAdministration>(); // Same native receipt restored from checkpoint.
    plan(&mut w,5);
    let view=&w.resource::<StationAdministration>().stations[0];
    assert_eq!(view.already_working,6);assert_eq!(view.assigned_workers,0);assert_eq!(view.idle_workers,0);
    assert_eq!(workforce::pay_shift(&mut w,refinery,farm,5,None).unwrap_err(),"already_worked_this_tick");
}

#[test]
fn station_admin_missing_inputs_produce_requests_not_resources() {
    let (mut w,_,_,_,market)=fixture(Mode::Execute);
    w.get_mut::<MarketPricing>(market).unwrap().supply.clear();
    let stock=w.get::<MarketPricing>(market).unwrap().supply.clone();plan(&mut w,5);
    let view=&w.resource::<StationAdministration>().stations[0];assert_eq!(view.assigned_workers,0);
    assert!(view.needs.iter().any(|n|n.commodity==Commodity::Water&&n.facility_id=="a-farm"));
    assert_eq!(w.get::<MarketPricing>(market).unwrap().supply,stock);
}

#[test]
fn station_admin_head_direction_can_override_local_preference() {
    let (mut w,_,_,_,_)=fixture(Mode::Execute);
    let goal=crate::strategy::Goal{goal_id:"supply".into(),commodity:Commodity::Food,destination:"port".into(),shortage_ticks:1,score:1.0};
    w.resource_mut::<StrategyState>().factions.insert("civ".into(),crate::strategy::FactionView {
        faction_id:"civ".into(),observed_tick:0,treasury:0,goals:vec![],assessments:vec![],selected_goal:None,
        administrator:"logistics",status:"idle".into(),reason:"test".into(),projects:vec![],construction:None,
        head:Some(crate::strategy::coordination::HeadDecision{observed_tick:0,selected_administrator:None,reason:"test".into(),treasury_before:0,
            spending_limit:0,planned_spend:0,committed_spend:0,proposals:vec![],problem:Some(goal),selected_option:"wait",horizon_ticks:1,alternatives:vec![]})});
    plan(&mut w,5);assert_eq!(assigned(&w,"a-farm"),6);
}

#[test]
fn station_admin_surplus_does_not_stop_staffed_production_and_shared_cash_is_bounded() {
    let (mut w,farm,_,pop,market)=fixture(Mode::Execute);
    w.get_mut::<PopDemographics>(pop).unwrap().population_count=20;
    w.get_mut::<MarketPricing>(market).unwrap().supply.insert(Commodity::Water,1000.0);
    plan(&mut w,5);
    assert_eq!(w.resource::<StationAdministration>().stations[0].assigned_workers,12,"surplus is priority input, not stop threshold");
    w.get_mut::<FacilityOperations>(farm).unwrap().credits=7;
    plan(&mut w,10);
    assert_eq!(w.resource::<StationAdministration>().stations[0].assigned_workers,6,"shared stock owner cannot promise both payrolls");
    assert_eq!(w.get::<FacilityOperations>(farm).unwrap().credits,7,"planning does not debit cash");
}
