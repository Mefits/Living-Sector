use super::*;
use crate::strategy::{Mode,StrategyState};
use crate::economy::contracts::FundingSource;
use bevy_ecs::prelude::Entity;

fn ship(w:&mut World,id:&str,faction:&str)->Entity {
    w.spawn((ShipIdentity {db_id:1,id:id.into(),name:id.into(),class:"freighter".into(),faction_id:faction.into(),size:crate::simulation::config::ShipSize::Medium},
        ShipPosition {location_name:Some("source".into()),docked_at:None,system_id:"sol".into(),universe_offset:(0.,0.),position:(0.,0.)},
        ShipTransit {transit:None},ShipCargo {cargo:Default::default(),capacity:100,cargo_age:Default::default(),cargo_origin:Default::default()},
        ShipEconomy {transaction:Default::default(),credits:1000,efficiency:1.,active_contract_id:None,faction_reputation:Default::default(),dock_dwell_start_tick:None,rest_start_tick:None,dock_attempt_start_tick:None},
        ShipFuel {fuel:100.,fuel_capacity:100.,fuel_consumption_rate:0.05,speed_modifier:1.})).id()
}
fn contract(b:&mut ContractBoard)->String {
    let id=b.post_delivery_for("civ".into(),Some("civ".into()),Commodity::Ore,10,"source".into(),"port".into(),200,0,10000);
    b.register_prepaid(&id,FundingSource::Faction);
    b.get_mut(&id).unwrap().mission_category=Some(crate::strategy::PROJECT_TAG.into());id
}
fn fixture()->(World,ContractBoard,WorldRegistry,Entity,Entity) {
    let mut w=World::new();w.insert_resource(StrategyState {mode:Mode::Execute,..Default::default()});
    let a=ship(&mut w,"a","civ");let b=ship(&mut w,"b","civ");ship(&mut w,"0-independent","independent");
    let facility=w.spawn_empty().id();
    w.spawn((MarketIdentity {db_id:1,id:"market".into(),facility,facility_location:"source".into()},
        MarketPricing {price_elasticity:1.,spread:0.,prices:[(Commodity::Ore,10.)].into(),supply:[(Commodity::Ore,100.)].into(),demand:Default::default()}));
    let mut registry=WorldRegistry::default();
    // WorldRegistry::shortest_distance must see actual vertex registration;
    // a route to a non-existent location is invalid even if an edge says so.
    for name in ["source","port","backup"] {
        registry.locations.insert(name.into(),crate::world::registry::LocationInfo {
            db_id:0,name:name.into(),loc_type:"station".into(),celestial_body_id:0
        });
    }
    registry.routes.insert("source".into(),vec![
        crate::world::registry::Route {to:"port".into(),distance:1}
    ]);
    (w,ContractBoard::new(),registry,a,b)
}
fn cycle(w:&mut World,b:&mut ContractBoard,r:&WorldRegistry,t:u64) {dispatch(w,b,&FactionRelations::default(),r,t,1);}
#[test]
fn station_order_unique_assignment_recovery_and_no_economic_mutation() {
    let (mut w,mut b,r,a,_)=fixture();let x=contract(&mut b);let y=contract(&mut b);
    let before=crate::economy::money::MoneySnapshot::capture(&mut w,&b).total;
    cycle(&mut w,&mut b,&r,1);
    assert_eq!(contract_order(b.get(&x).unwrap()).unwrap().executor_id.as_deref(),Some("a"));
    assert_eq!(contract_order(b.get(&y).unwrap()).unwrap().executor_id.as_deref(),Some("b"));
    assert!(!may_accept(b.get(&x).unwrap(),"b","civ"));
    assert!(!may_accept(b.get(&x).unwrap(),"a","enemy"));
    let saved=b.get(&x).unwrap().funding.clone();
    let json=serde_json::to_string(&saved).unwrap();b.get_mut(&x).unwrap().funding=serde_json::from_str(&json).unwrap();
    cycle(&mut w,&mut b,&r,2);assert_eq!(b.get(&x).unwrap().funding,saved);
    assert_eq!(crate::economy::money::MoneySnapshot::capture(&mut w,&b).total,before);
    w.despawn(a);cycle(&mut w,&mut b,&r,3);
    assert_eq!(contract_order(b.get(&x).unwrap()).unwrap().blocked_reason.as_deref(),Some("executor_missing"));
    ship(&mut w,"c","civ");cycle(&mut w,&mut b,&r,33);
    let o=contract_order(b.get(&x).unwrap()).unwrap();assert_eq!(o.executor_id.as_deref(),Some("c"));assert_eq!(o.attempt,2);
}
#[test]
fn station_order_shadow_infeasible_and_timeout_are_observable() {
    let (mut w,mut b,r,a,c)=fixture();let id=contract(&mut b);
    w.resource_mut::<StrategyState>().mode=Mode::Shadow;cycle(&mut w,&mut b,&r,1);
    assert!(contract_order(b.get(&id).unwrap()).is_none());
    w.resource_mut::<StrategyState>().mode=Mode::Execute;
    w.get_mut::<ShipEconomy>(a).unwrap().credits=0;w.get_mut::<ShipCargo>(c).unwrap().capacity=1;
    cycle(&mut w,&mut b,&r,2);assert!(contract_order(b.get(&id).unwrap()).unwrap().executor_id.is_none());
    w.get_mut::<ShipEconomy>(a).unwrap().credits=1000;cycle(&mut w,&mut b,&r,32);
    assert_eq!(contract_order(b.get(&id).unwrap()).unwrap().executor_id.as_deref(),Some("a"));
    cycle(&mut w,&mut b,&r,332);assert!(contract_order(b.get(&id).unwrap()).unwrap().executor_id.is_none());
    cycle(&mut w,&mut b,&r,362);assert_eq!(contract_order(b.get(&id).unwrap()).unwrap().attempt,2);
}
#[test]
fn station_order_construction_shares_carriers_and_survives_restart() {
    let (mut w,mut b,r,_,_)=fixture();let id=contract(&mut b);
    let site=w.spawn(ConstructionSite {id:"site".into(),name:"Site".into(),facility_type:"farm".into(),faction_id:"civ".into(),body_id:"earth".into(),location_name:"port".into(),commodity:Commodity::Metals,progress_delivered:600,progress_required:600,position:(0.,0.),spawned_at_tick:0,completed:false,dirty:false,labor:Default::default()}).id();
    cycle(&mut w,&mut b,&r,1);
    assert_eq!(contract_order(b.get(&id).unwrap()).unwrap().executor_id.as_deref(),Some("a"));
    let o=w.get::<ConstructionSite>(site).unwrap().labor.station_order.clone().unwrap();assert_eq!(o.executor_id.as_deref(),Some("b"));
    let json=serde_json::to_string(&w.get::<ConstructionSite>(site).unwrap().labor).unwrap();
    w.get_mut::<ConstructionSite>(site).unwrap().labor=serde_json::from_str(&json).unwrap();
    cycle(&mut w,&mut b,&r,2);assert_eq!(w.get::<ConstructionSite>(site).unwrap().labor.station_order.as_ref(),Some(&o));
    assert!(builder_assigned(&mut w,"b"));
    let offers=crate::agents::construction::executor::offers(&mut w);assert_eq!(offers[0].claimed_by.as_deref(),Some("b"));
    w.get_mut::<ConstructionSite>(site).unwrap().labor.completed=150;
    cycle(&mut w,&mut b,&r,3);assert!(!builder_assigned(&mut w,"b"));
    assert_eq!(w.get::<ConstructionSite>(site).unwrap().labor.station_order.as_ref().unwrap().state,"completed");
}
#[test]
fn station_order_legacy_json_has_no_fabricated_assignment() {
    let f:crate::economy::contracts::ContractFunding=serde_json::from_str(r#"{"source":"faction","reserved":100,"agreed_payment":null}"#).unwrap();
    assert!(f.station_order.is_none());
    let l:crate::agents::construction::ConstructionLabor=serde_json::from_str("{}").unwrap();assert!(l.station_order.is_none());assert_eq!(l.completed,0);
}

#[test]
fn station_order_input_need_uses_head_portfolio_and_one_native_contract() {
    use crate::strategy::{station::{StationAdministration,StationView,Need},coordination};
    let (mut w,mut b,owner,destination,_)=crate::strategy::tests::fixture(Mode::Execute);
    w.get_mut::<crate::agents::market::MarketHistory>(destination).unwrap().shortage_ticks.clear();
    let mut administration=StationAdministration::default();
    administration.stations.push(StationView {faction_id:"own".into(),location:"port".into(),observed_tick:5,executing:true,
        workforce:6,already_working:0,assigned_workers:0,idle_workers:6,head_priority:None,modules:vec![],
        needs:vec![Need {facility_id:"refinery".into(),commodity:Commodity::Ore,kind:"supply_input"}]});
    w.insert_resource(administration);
    let relations=FactionRelations::default();
    coordination::run_cycle(&mut w,&mut b,&relations,&mut vec![],60,1);
    assert_eq!(b.iter().count(),0,"a request alone must not force spending without projected benefit");
    assert_eq!(w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().selected_option,"wait");
    { let mut m=w.get_mut::<MarketPricing>(destination).unwrap();
      m.demand.insert(Commodity::Ore,200.);m.prices.insert(Commodity::Ore,15.); }
    coordination::run_cycle(&mut w,&mut b,&relations,&mut vec![],120,1);
    assert_eq!(b.iter().count(),1,"a viable input request should become a head-funded shipment");
    assert_eq!(b.iter().next().unwrap().commodity,Commodity::Ore);
    let balance=w.get::<crate::agents::faction::FactionData>(owner).unwrap().treasury;
    coordination::run_cycle(&mut w,&mut b,&relations,&mut vec![],180,1);
    assert_eq!(b.iter().count(),1,"one need must not create duplicate orders");
    assert_eq!(w.get::<crate::agents::faction::FactionData>(owner).unwrap().treasury,balance);
}


#[test]
fn station_order_recovers_to_a_real_alternative_market() {
    let (mut world,mut board,mut registry,_,_)=fixture();
    let id=contract(&mut board);
    // Original source goes dry after funding, before a pilot accepts.
    let src=world.query::<(Entity,&MarketIdentity)>().iter(&world)
        .find(|(_,m)|m.facility_location=="source").unwrap().0;
    world.get_mut::<MarketPricing>(src).unwrap().supply.insert(Commodity::Ore,0.0);
    let market_owner=world.spawn_empty().id();
    let backup=world.spawn((
        MarketIdentity{db_id:2,id:"backup-market".into(),
            facility:market_owner,facility_location:"backup".into()},
        MarketPricing{price_elasticity:1.,spread:0.,
            prices:[(Commodity::Ore,8.0)].into(),
            supply:[(Commodity::Ore,100.0)].into(),demand:Default::default()}
    )).id();
    registry.routes.get_mut("source").unwrap().push(
        crate::world::registry::Route{to:"backup".into(),distance:2});
    registry.routes.insert("backup".into(),vec![
        crate::world::registry::Route{to:"port".into(),distance:2}]);
    let before=crate::economy::money::MoneySnapshot::capture(&mut world,&board).total;
    cycle(&mut world,&mut board,&registry,1);
    let c=board.get(&id).unwrap();
    assert_eq!(c.source_location,"backup");
    assert_eq!(contract_order(c).unwrap().executor_id.as_deref(),Some("a"));
    assert_eq!(c.status,ContractStatus::Posted);
    assert_eq!(world.get::<MarketPricing>(backup).unwrap().supply[&Commodity::Ore],100.0);
    assert_eq!(crate::economy::money::MoneySnapshot::capture(&mut world,&board).total,before);
}

#[test]
fn station_order_keeps_existing_source_when_a_carrier_is_eligible() {
    let (mut world,mut board,registry,_,_)=fixture();
    let id=contract(&mut board);
    cycle(&mut world,&mut board,&registry,1);
    assert_eq!(board.get(&id).unwrap().source_location,"source");
}

#[test]
fn facility_relief_waits_then_dispatches_only_to_native_t2_qualified_carrier() {
    use crate::agents::facility::{FacilityIdentity, FacilityOperations};
    use crate::agents::celestial_body::BodyIdentity;
    use crate::agents::ship::ShipFitting;
    use crate::modules::Slot;
    use crate::simulation::config::ShipSize;
    let (mut world, mut board, mut registry, a, b)=fixture();
    // A real own-faction business actually paid this public market request.
    world.spawn((
        FacilityIdentity {db_id:91,id:"facility-refining".into(),name:"Refining".into(),
            facility_type:"refinery".into(),faction_id:"civ".into(),body_id:"earth".into()},
        FacilityOperations {docking_capacity:0,services:vec![],condition:1.0,
            reputation:0,credits:1000,dirty:false,starving_notified:false}
    ));
    let id=board.post_delivery_for("facility-refining".into(),Some("civ".into()),
        Commodity::Ore,10,"source".into(),"port".into(),200,0,10000);
    board.register_prepaid(&id,FundingSource::Facility);

    world.spawn(BodyIdentity {db_id:101,body_id:"earth".into(),name:"Earth".into(),
        body_type:"planet".into(),star_system_id:1,system_name:"sol".into()});
    world.spawn(BodyIdentity {db_id:102,body_id:"alpha".into(),name:"Alpha".into(),
        body_type:"planet".into(),star_system_id:2,system_name:"alpha".into()});
    registry.locations.get_mut("source").unwrap().celestial_body_id=101;
    registry.locations.get_mut("port").unwrap().celestial_body_id=102;

    let before=crate::economy::money::MoneySnapshot::capture(&mut world,&board).total;
    cycle(&mut world,&mut board,&registry,179);
    assert!(contract_order(board.get(&id).unwrap()).is_none(),
        "Ordinary new facility offers must remain public, without early dispatch");
    cycle(&mut world,&mut board,&registry,180);
    let blocked=contract_order(board.get(&id).unwrap()).unwrap();
    assert_eq!(blocked.blocked_reason.as_deref(),Some("no_sensor_qualified_carrier"));
    assert!(may_accept(board.get(&id).unwrap(),"independent","independent"),
        "Unassigned rescue must not hide the public market from private pilots");

    // One properly upgraded ship can accept the EXISTING funded order.
    let mut fit=ShipFitting::new_for_size(ShipSize::Medium,"a");
    fit.set(Slot::Sensors,Some("sensors_t2"));
    world.entity_mut(a).insert(fit);
    cycle(&mut world,&mut board,&registry,210);
    let c=board.get(&id).unwrap();
    assert_eq!(contract_order(c).unwrap().executor_id.as_deref(),Some("a"));
    assert!(!may_accept(c,"b","civ"));
    assert!(!may_accept(c,"0-independent","independent"));
    assert_eq!(c.status,ContractStatus::Posted);
    assert_eq!(c.funding.as_ref().unwrap().reserved,200);
    assert_eq!(crate::economy::money::MoneySnapshot::capture(&mut world,&board).total,before);
    let market=world.query::<(&MarketIdentity,&MarketPricing)>().iter(&world)
        .find(|(m,_)|m.facility_location=="source").unwrap().1;
    assert_eq!(market.supply[&Commodity::Ore],100.0);

    assert!(board.accept(&id,"a".into(),211));
    cycle(&mut world,&mut board,&registry,211);
    let c=board.get(&id).unwrap();
    assert_eq!(contract_order(c).unwrap().state,"executing");
    assert_eq!(contract_order(c).unwrap().executor_id.as_deref(),Some("a"));

    // If the order is never accepted, lease expires and public market
    // reopens; no permanent lock on the rest of the economy.
    let (mut world2,mut board2,mut registry2,a2,_)=fixture();
    world2.spawn((FacilityIdentity {db_id:92,id:"facility-refining".into(),
        name:"Refining".into(),facility_type:"refinery".into(),
        faction_id:"civ".into(),body_id:"earth".into()},
        FacilityOperations {docking_capacity:0,services:vec![],condition:1.0,
            reputation:0,credits:1000,dirty:false,starving_notified:false}));
    let id2=board2.post_delivery_for("facility-refining".into(),Some("civ".into()),
        Commodity::Ore,10,"source".into(),"port".into(),200,0,10000);
    board2.register_prepaid(&id2,FundingSource::Facility);
    // Same-system rescue: a T1 ship is eligible because topology is known.
    world2.spawn(BodyIdentity {db_id:101,body_id:"earth".into(),name:"Earth".into(),
        body_type:"planet".into(),star_system_id:1,system_name:"sol".into()});
    registry2.locations.get_mut("source").unwrap().celestial_body_id=101;
    registry2.locations.get_mut("port").unwrap().celestial_body_id=101;
    cycle(&mut world2,&mut board2,&registry2,180);
    assert_eq!(contract_order(board2.get(&id2).unwrap()).unwrap().executor_id.as_deref(),Some("a"));
    cycle(&mut world2,&mut board2,&registry2,480);
    assert!(contract_order(board2.get(&id2).unwrap()).unwrap().executor_id.is_none());
    assert!(may_accept(board2.get(&id2).unwrap(),"independent","independent"));
    let _=a2; let _=b; 
}

#[test]
fn facility_relief_never_assigns_without_escrow_topup_or_when_shadow() {
    use crate::agents::facility::{FacilityIdentity, FacilityOperations};
    use crate::agents::celestial_body::BodyIdentity;
    let (mut world,mut board,mut registry,_,_)=fixture();
    world.spawn(BodyIdentity {db_id:101,body_id:"earth".into(),name:"Earth".into(),
        body_type:"planet".into(),star_system_id:1,system_name:"sol".into()});
    registry.locations.get_mut("source").unwrap().celestial_body_id=101;
    registry.locations.get_mut("port").unwrap().celestial_body_id=101;
    world.spawn((
        FacilityIdentity {db_id:91,id:"facility-refining".into(),name:"Refining".into(),
            facility_type:"refinery".into(),faction_id:"civ".into(),body_id:"earth".into()},
        FacilityOperations {docking_capacity:0,services:vec![],condition:1.,
            reputation:0,credits:0,dirty:false,starving_notified:false}
    ));
    let id=board.post_delivery_for("facility-refining".into(),Some("civ".into()),
        Commodity::Ore,10,"source".into(),"port".into(),200,0,10000);
    board.register_prepaid(&id,FundingSource::Facility);
    board.get_mut(&id).unwrap().payment=400; // native payment escalation
    world.resource_mut::<StrategyState>().mode=Mode::Shadow;
    cycle(&mut world,&mut board,&registry,180);
    assert!(contract_order(board.get(&id).unwrap()).is_none());
    world.resource_mut::<StrategyState>().mode=Mode::Execute;
    let before=crate::economy::money::MoneySnapshot::capture(&mut world,&board).total;
    cycle(&mut world,&mut board,&registry,180);
    let c=board.get(&id).unwrap();
    assert_eq!(contract_order(c).unwrap().blocked_reason.as_deref(),Some("no_viable_local_carrier"));
    assert_eq!(c.funding.as_ref().unwrap().reserved,200);
    assert_eq!(crate::economy::money::MoneySnapshot::capture(&mut world,&board).total,before);
    assert!(may_accept(c,"independent","independent"));
}
