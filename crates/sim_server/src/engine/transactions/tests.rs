use super::*;
use sim_core::agents::construction::ConstructionSite;
use sim_core::simulation::commands::{CommandBuffer, SimCommand};

struct Fixture {
    world: World,
    store: AgentStore,
    facility: Entity,
    market: Entity,
    ships: [Entity; 2],
    events: Vec<serde_json::Value>,
}

impl Fixture {
    fn new(stock: f32, reserve: f32) -> Self {
        let mut world = World::new();
        let mut store = AgentStore::new();
        let facility = world
            .spawn((
                FacilityIdentity {
                    db_id: 1,
                    id: "station".into(),
                    name: "Station".into(),
                    facility_type: "station".into(),
                    faction_id: "".into(),
                    body_id: "earth".into(),
                },
                FacilityLocation {
                    location_id: 1,
                    location_name: "port".into(),
                },
                FacilityOperations {
                    docking_capacity: 4,
                    services: vec!["refuel".into()],
                    condition: 1.0,
                    reputation: 50,
                    credits: 0,
                    dirty: false,
                    starving_notified: false,
                },
                FacilityStorage {
                    reserves: [(Commodity::Fuel, reserve)].into(),
                    ..Default::default()
                },
                FacilityLifecycle::new(),
            ))
            .id();
        store.facility_by_id.insert("station".into(), facility);
        let market = world
            .spawn((
                MarketIdentity {
                    db_id: 2,
                    id: "market".into(),
                    facility,
                    facility_location: "port".into(),
                },
                MarketPricing {
                    price_elasticity: 1.0,
                    spread: 0.0,
                    prices: [(Commodity::Ore, 10.0)].into(),
                    supply: [(Commodity::Ore, stock)].into(),
                    demand: Default::default(),
                },
                MarketHistory::default(),
            ))
            .id();
        store.market_at_location.insert("port".into(), market);
        let ships = std::array::from_fn(|i| {
            let id = format!("ship-{i}");
            let ship = world
                .spawn((
                    ShipIdentity {
                        db_id: 10 + i as i64,
                        id: id.clone(),
                        name: id.clone(),
                        class: "freighter".into(),
                        faction_id: "haulers".into(),
                        size: sim_core::simulation::config::ShipSize::Medium,
                    },
                    ShipPosition {
                        location_name: Some("port".into()),
                        docked_at: Some(facility),
                        system_id: "sol".into(),
                        universe_offset: (0.0, 0.0),
                        position: (0.0, 0.0),
                    },
                    ShipTransit { transit: None },
                    ShipCargo {
                        cargo: Default::default(),
                        capacity: 100,
                        cargo_age: Default::default(),
                        cargo_origin: Default::default(),
                    },
                    ShipFuel {
                        fuel: 10.0,
                        fuel_capacity: 100.0,
                        fuel_consumption_rate: 0.05,
                        speed_modifier: 1.0,
                    },
                    ShipEconomy {
                        transaction: Default::default(),
                        credits: 1000,
                        efficiency: 1.0,
                        active_contract_id: None,
                        faction_reputation: Default::default(),
                        dock_dwell_start_tick: None,
                        rest_start_tick: None,
                        dock_attempt_start_tick: None,
                    },
                    ShipLifecycle {
                        broke_strikes: 0,
                        hoard_strikes: 0,
                        idle_ticks: 0,
                        dirty: false,
                    },
                    ShipCrewSkills::for_roles(&[]),
                    sim_core::agents::ship::ShipProgression::new(),
                ))
                .id();
            store.ship_by_id.insert(id, ship);
            world
                .get_mut::<FacilityStorage>(facility)
                .unwrap()
                .docked_ships
                .push(ship);
            ship
        });
        Self {
            world,
            store,
            facility,
            market,
            ships,
            events: vec![],
        }
    }

    fn submit(&mut self, ship: Entity, request: ShipTransaction) -> u64 {
        self.world
            .get_mut::<ShipEconomy>(ship)
            .unwrap()
            .transaction
            .begin(request)
            .unwrap()
    }
    fn apply(&mut self, ship: Entity, id: u64) {
        let mut commands = CommandBuffer::new();
        commands.push(SimCommand::RequestShipTransaction {
            ship,
            request_id: id,
        });
        super::super::apply::apply_ship_commands(
            &mut self.world,
            &mut self.store,
            &mut commands,
            &mut self.events,
            10,
        );
    }
    fn result(&self, ship: Entity) -> Result<(), Rejection> {
        self.world
            .get::<ShipEconomy>(ship)
            .unwrap()
            .transaction
            .pending
            .as_ref()
            .unwrap()
            .result
            .unwrap()
    }
    fn snapshot(&self, ship: Entity) -> serde_json::Value {
        let econ = self.world.get::<ShipEconomy>(ship).unwrap();
        let cargo = self.world.get::<ShipCargo>(ship).unwrap();
        let skills = self.world.get::<ShipCrewSkills>(ship).unwrap();
        serde_json::json!({ "credits": econ.credits, "active": econ.active_contract_id,
            "cargo": cargo.cargo, "age": cargo.cargo_age, "origin": cargo.cargo_origin,
            "fuel": self.world.get::<ShipFuel>(ship).unwrap().fuel,
            "stock": self.world.get::<MarketPricing>(self.market).unwrap().supply,
            "reserve": self.world.get::<FacilityStorage>(self.facility).unwrap().reserves,
            "seller_credits": self.world.get::<FacilityOperations>(self.facility).unwrap().credits,
            "skills": [skills.navigation, skills.trading],
            "progression": self.world.get::<sim_core::agents::ship::ShipProgression>(ship).unwrap().xp,
            "contracts": self.store.contracts.iter().collect::<Vec<_>>(),
        })
    }
    fn delivery(&mut self, construction: bool) -> String {
        let id = if construction {
            self.store.contracts.post_construction(
                "station".into(),
                None,
                Commodity::Ore,
                10,
                "source".into(),
                "port".into(),
                120,
                0,
                1000,
            )
        } else {
            self.store.contracts.post_delivery_for(
                "station".into(),
                None,
                Commodity::Ore,
                10,
                "source".into(),
                "port".into(),
                120,
                0,
                1000,
            )
        };
        assert!(self.store.contracts.accept(&id, "ship-0".into(), 1));
        let ship = self.ships[0];
        self.world
            .get_mut::<ShipEconomy>(ship)
            .unwrap()
            .active_contract_id = Some(id.clone());
        self.world
            .get_mut::<ShipCargo>(ship)
            .unwrap()
            .cargo
            .insert(Commodity::Ore, 10);
        id
    }
    fn site(&mut self, remaining: u32) -> Entity {
        self.world
            .spawn(ConstructionSite {
                id: "site".into(),
                name: "Site".into(),
                facility_type: "mining_rig".into(),
                faction_id: "haulers".into(),
                body_id: "earth".into(),
                location_name: "port".into(),
                commodity: Commodity::Ore,
                progress_delivered: 0,
                progress_required: remaining,
                position: (0.0, 0.0),
                spawned_at_tick: 0,
                completed: false,
                dirty: false,
            })
            .id()
    }
}

fn purchase() -> ShipTransaction {
    ShipTransaction::Buy {
        location: "port".into(),
        commodity: Commodity::Ore,
        quantity: 10,
        max_unit_price: 10.0,
    }
}

#[test]
fn supply_flow_reward_increases_are_funded_once_or_delivery_is_rejected() {
    use sim_core::agents::{
        faction::{FactionColors, FactionData},
        ship::ShipFitting,
    };
    for case in [
        "facility_age",
        "faction_bonus",
        "broke",
        "missing_payer",
        "missing_cargo",
    ] {
        let mut f = Fixture::new(0.0, 0.0);
        let ship = f.ships[0];
        let id = f.delivery(false);
        // Opening balances: 1000 ship + 880 requestor + 120 prepaid contract = 2000.
        let opening = if case == "broke" { 29 } else { 880 };
        let faction = if case == "faction_bonus" {
            let payer = f
                .world
                .spawn(FactionData {
                    id: "sponsor".into(),
                    name: "Sponsor".into(),
                    faction_type: "civilian".into(),
                    home_system: "sol".into(),
                    treasury: opening,
                    personality: sim_core::ai::personality::Personality::balanced_trader(),
                    colors: FactionColors {
                        primary: "blue".into(),
                        secondary: "white".into(),
                    },
                    active_subsidies: 0,
                    dirty: false,
                })
                .id();
            f.store.faction_by_id.insert("sponsor".into(), payer);
            f.store.contracts.get_mut(&id).unwrap().requestor_id = "sponsor".into();
            let mut fitting = ShipFitting::new_default();
            fitting.derived.comms_bonus = 0.25;
            f.world.entity_mut(ship).insert(fitting);
            Some(payer)
        } else {
            f.world
                .get_mut::<FacilityOperations>(f.facility)
                .unwrap()
                .credits = opening;
            f.store.contracts.get_mut(&id).unwrap().payment = 150; // aged offer, base still 120
            None
        };
        if case == "missing_payer" {
            f.store.contracts.get_mut(&id).unwrap().requestor_id = "removed".into();
        }
        if case == "missing_cargo" {
            f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.clear();
        }
        let request = f.submit(ship, ShipTransaction::Deliver { contract_id: id });
        let before = f.snapshot(ship);
        f.apply(ship, request);
        if matches!(case, "facility_age" | "faction_bonus") {
            assert_eq!(f.result(ship), Ok(()));
            let payer_remaining = match faction {
                Some(e) => f.world.get::<FactionData>(e).unwrap().treasury,
                None => {
                    f.world
                        .get::<FacilityOperations>(f.facility)
                        .unwrap()
                        .credits
                }
            };
            assert_eq!(payer_remaining, 850);
            assert_eq!(
                f.world.get::<ShipEconomy>(ship).unwrap().credits + payer_remaining,
                2000
            );
            assert_eq!(
                f.events
                    .iter()
                    .filter(|e| e["kind"] == "contract_reward_funded")
                    .count(),
                1
            );
            let after = f.snapshot(ship);
            f.apply(ship, request);
            assert_eq!(f.snapshot(ship), after);
            if let Some(e) = faction {
                assert_eq!(f.world.get::<FactionData>(e).unwrap().treasury, 850);
            }
        } else {
            assert!(f.result(ship).is_err(), "{case}");
            assert_eq!(f.snapshot(ship), before, "{case}");
            assert!(!f
                .events
                .iter()
                .any(|e| e["kind"] == "contract_reward_funded"));
            if case == "broke" {
                let cid = f
                    .world
                    .get::<ShipEconomy>(ship)
                    .unwrap()
                    .active_contract_id
                    .clone()
                    .unwrap();
                f.store.contracts.get_mut(&cid).unwrap().faction_id = Some("sponsor".into());
                f.world
                    .get_mut::<ShipEconomy>(ship)
                    .unwrap()
                    .faction_reputation
                    .insert("sponsor".into(), 50);
                let mut commands = CommandBuffer::new();
                commands.push(SimCommand::ReleaseContract {
                    ship_id: "ship-0".into(),
                    contract_id: cid.clone(),
                    reason: "issuer_funding_failure",
                });
                super::super::apply::apply_ship_commands(
                    &mut f.world,
                    &mut f.store,
                    &mut commands,
                    &mut f.events,
                    11,
                );
                assert_eq!(
                    f.world.get::<ShipEconomy>(ship).unwrap().faction_reputation["sponsor"],
                    50
                );
                assert_eq!(
                    f.store.contracts.get(&cid).unwrap().status,
                    ContractStatus::Posted
                );
            }
        }
    }
}
fn fuel_request() -> ShipTransaction {
    ShipTransaction::Refuel {
        location: "port".into(),
    }
}

#[test]
fn competing_buyers_cannot_create_stock_and_payment_reaches_seller() {
    let mut f = Fixture::new(10.0, 0.0);
    let [a, b] = f.ships;
    let ra = f.submit(a, purchase());
    let rb = f.submit(b, purchase());
    f.apply(a, ra);
    assert_eq!(f.result(a), Ok(()));
    let before_b = f.snapshot(b);
    f.apply(b, rb);
    assert_eq!(f.result(b), Err("insufficient_stock"));
    assert_eq!(before_b, f.snapshot(b));
    assert_eq!(f.world.get::<ShipCargo>(a).unwrap().used(), 10);
    assert_eq!(
        f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Ore],
        0.0
    );
    assert_eq!(f.world.get::<ShipEconomy>(a).unwrap().credits, 900);
    assert_eq!(
        f.world
            .get::<FacilityOperations>(f.facility)
            .unwrap()
            .credits,
        100
    );
    assert!(f.world.get::<MarketHistory>(f.market).unwrap().dirty);
}

#[test]
fn purchases_reject_without_side_effects() {
    for case in [
        "empty",
        "capacity",
        "credits",
        "price",
        "nan_price",
        "undocked",
        "owner_overflow",
        "war",
    ] {
        let mut f = Fixture::new(10.0, 0.0);
        let ship = f.ships[0];
        let request = f.submit(ship, purchase());
        match case {
            "empty" => {
                f.world
                    .get_mut::<MarketPricing>(f.market)
                    .unwrap()
                    .supply
                    .clear();
            }
            "capacity" => f.world.get_mut::<ShipCargo>(ship).unwrap().capacity = 9,
            "credits" => f.world.get_mut::<ShipEconomy>(ship).unwrap().credits = 99,
            "price" => {
                f.world
                    .get_mut::<MarketPricing>(f.market)
                    .unwrap()
                    .prices
                    .insert(Commodity::Ore, 11.0);
            }
            "nan_price" => {
                f.world
                    .get_mut::<MarketPricing>(f.market)
                    .unwrap()
                    .prices
                    .insert(Commodity::Ore, f32::NAN);
            }
            "undocked" => f.world.get_mut::<ShipPosition>(ship).unwrap().docked_at = None,
            "owner_overflow" => {
                f.world
                    .get_mut::<FacilityOperations>(f.facility)
                    .unwrap()
                    .credits = i64::MAX
            }
            "war" => {
                f.world
                    .get_mut::<FacilityIdentity>(f.facility)
                    .unwrap()
                    .faction_id = "rival".into();
                f.store.relations.set_treaty(
                    "haulers",
                    "rival",
                    sim_core::agents::faction_relations::TreatyKind::War,
                    2,
                );
            }
            _ => unreachable!(),
        }
        let before = f.snapshot(ship);
        f.apply(ship, request);
        assert!(f.result(ship).is_err(), "{case}");
        assert_eq!(before, f.snapshot(ship), "{case}");
    }
}

#[test]
fn duplicate_and_cancelled_requests_never_apply_twice() {
    let mut f = Fixture::new(30.0, 0.0);
    let ship = f.ships[0];
    let old = f.submit(ship, purchase());
    f.apply(ship, old);
    let after = f.snapshot(ship);
    f.apply(ship, old);
    assert_eq!(after, f.snapshot(ship));
    assert_eq!(f.events.len(), 1);
    f.world
        .get_mut::<ShipEconomy>(ship)
        .unwrap()
        .transaction
        .pending = None;
    let new = f.submit(ship, purchase());
    assert!(new > old);
    f.apply(ship, old);
    assert_eq!(after, f.snapshot(ship));
    f.world
        .get_mut::<ShipEconomy>(ship)
        .unwrap()
        .transaction
        .pending = None;
    f.apply(ship, new);
    assert_eq!(after, f.snapshot(ship));
}

#[test]
fn last_fraction_of_fuel_is_transferred_once_from_actual_dock() {
    let mut f = Fixture::new(0.0, 1.5);
    // Another, larger dock at the same location must not supply this ship.
    let mut other_id = f.world.get::<FacilityIdentity>(f.facility).unwrap().clone();
    other_id.id = "other".into();
    let mut other_ops = f
        .world
        .get::<FacilityOperations>(f.facility)
        .unwrap()
        .clone();
    other_ops.docking_capacity = 20;
    let other = f
        .world
        .spawn((
            other_id,
            other_ops,
            FacilityLocation {
                location_id: 1,
                location_name: "port".into(),
            },
            FacilityStorage {
                reserves: [(Commodity::Fuel, 100.0)].into(),
                ..Default::default()
            },
            FacilityLifecycle::new(),
        ))
        .id();
    f.store.facility_by_id.insert("other".into(), other);
    let [a, b] = f.ships;
    let ra = f.submit(a, fuel_request());
    let rb = f.submit(b, fuel_request());
    f.apply(a, ra);
    assert_eq!(f.result(a), Ok(()));
    assert_eq!(f.world.get::<ShipFuel>(a).unwrap().fuel, 11.5);
    assert_eq!(
        f.world.get::<FacilityStorage>(f.facility).unwrap().reserves[&Commodity::Fuel],
        0.0
    );
    assert_eq!(
        f.world.get::<FacilityStorage>(other).unwrap().reserves[&Commodity::Fuel],
        100.0
    );
    let payment = 2 * REFUEL_PRICE_PER_UNIT;
    assert_eq!(
        f.world.get::<ShipEconomy>(a).unwrap().credits,
        1000 - payment
    );
    assert_eq!(
        f.world
            .get::<FacilityOperations>(f.facility)
            .unwrap()
            .credits,
        payment
    );
    let before_b = f.snapshot(b);
    f.apply(b, rb);
    assert_eq!(f.result(b), Err("no_fuel_transfer"));
    assert_eq!(before_b, f.snapshot(b));
    let after_a = f.snapshot(a);
    f.apply(a, ra);
    assert_eq!(after_a, f.snapshot(a));
}

#[test]
fn refuel_rejects_empty_broke_wrong_dock_and_invalid_fuel() {
    for case in [
        "empty",
        "broke",
        "wrong_dock",
        "not_registered",
        "nan",
        "overflow",
    ] {
        let mut f = Fixture::new(0.0, 50.0);
        let ship = f.ships[0];
        match case {
            "empty" => f
                .world
                .get_mut::<FacilityStorage>(f.facility)
                .unwrap()
                .reserves
                .clear(),
            "broke" => f.world.get_mut::<ShipEconomy>(ship).unwrap().credits = 0,
            "wrong_dock" => {
                f.world
                    .get_mut::<FacilityLocation>(f.facility)
                    .unwrap()
                    .location_name = "elsewhere".into()
            }
            "not_registered" => f
                .world
                .get_mut::<FacilityStorage>(f.facility)
                .unwrap()
                .docked_ships
                .clear(),
            "nan" => f.world.get_mut::<ShipFuel>(ship).unwrap().fuel = f32::NAN,
            "overflow" => {
                f.world
                    .get_mut::<FacilityOperations>(f.facility)
                    .unwrap()
                    .credits = i64::MAX
            }
            _ => unreachable!(),
        }
        let request = f.submit(ship, fuel_request());
        let before = f.snapshot(ship);
        f.apply(ship, request);
        assert!(f.result(ship).is_err(), "{case}");
        assert_eq!(before, f.snapshot(ship), "{case}");
    }
}

#[test]
fn delivery_moves_real_cargo_and_pays_only_once() {
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    let contract_id = f.delivery(false);
    let request = f.submit(
        ship,
        ShipTransaction::Deliver {
            contract_id: contract_id.clone(),
        },
    );
    f.apply(ship, request);
    assert_eq!(f.result(ship), Ok(()));
    assert_eq!(f.world.get::<ShipCargo>(ship).unwrap().used(), 0);
    assert_eq!(
        f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Ore],
        10.0
    );
    assert_eq!(f.world.get::<ShipEconomy>(ship).unwrap().credits, 1120);
    assert_eq!(
        f.store.contracts.get(&contract_id).unwrap().status,
        ContractStatus::Paid
    );
    assert!(f
        .world
        .get::<ShipEconomy>(ship)
        .unwrap()
        .active_contract_id
        .is_none());
    let after = f.snapshot(ship);
    f.apply(ship, request);
    assert_eq!(after, f.snapshot(ship));
    f.world
        .get_mut::<ShipEconomy>(ship)
        .unwrap()
        .transaction
        .pending = None;
    let again = f.submit(ship, ShipTransaction::Deliver { contract_id });
    f.apply(ship, again);
    assert!(f.result(ship).is_err());
    assert_eq!(after, f.snapshot(ship));
}

#[test]
fn invalid_deliveries_preserve_cargo_payment_status_and_experience() {
    for case in [
        "missing_cargo",
        "short_cargo",
        "wrong_fulfiller",
        "wrong_destination",
        "undocked",
        "missing_market",
        "expired",
        "war",
        "overflow",
    ] {
        let mut f = Fixture::new(0.0, 0.0);
        let contract_id = f.delivery(false);
        let ship = if case == "wrong_fulfiller" {
            f.ships[1]
        } else {
            f.ships[0]
        };
        match case {
            "missing_cargo" => f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.clear(),
            "short_cargo" => {
                f.world
                    .get_mut::<ShipCargo>(ship)
                    .unwrap()
                    .cargo
                    .insert(Commodity::Ore, 9);
            }
            "wrong_destination" => {
                f.world.get_mut::<ShipPosition>(ship).unwrap().location_name =
                    Some("elsewhere".into())
            }
            "undocked" => f.world.get_mut::<ShipPosition>(ship).unwrap().docked_at = None,
            "missing_market" => f.store.market_at_location.clear(),
            "expired" => {
                f.store.contracts.get_mut(&contract_id).unwrap().status = ContractStatus::Expired
            }
            "war" => {
                f.world
                    .get_mut::<FacilityIdentity>(f.facility)
                    .unwrap()
                    .faction_id = "rival".into();
                f.store.relations.set_treaty(
                    "haulers",
                    "rival",
                    sim_core::agents::faction_relations::TreatyKind::War,
                    2,
                );
            }
            "overflow" => f.world.get_mut::<ShipEconomy>(ship).unwrap().credits = i64::MAX,
            _ => {}
        }
        let request = f.submit(ship, ShipTransaction::Deliver { contract_id });
        let before = f.snapshot(ship);
        f.apply(ship, request);
        assert!(f.result(ship).is_err(), "{case}");
        assert_eq!(before, f.snapshot(ship), "{case}");
        assert_eq!(f.events.len(), 1, "no reward events on rejection: {case}");
    }
}

#[test]
fn construction_accepts_only_material_that_a_live_site_can_absorb() {
    for remaining in [0, 9, 20] {
        let mut f = Fixture::new(0.0, 0.0);
        let ship = f.ships[0];
        let contract_id = f.delivery(true);
        let site = if remaining > 0 {
            Some(f.site(remaining))
        } else {
            None
        };
        let request = f.submit(ship, ShipTransaction::Deliver { contract_id });
        let before = f.snapshot(ship);
        f.apply(ship, request);
        if remaining == 20 {
            assert_eq!(f.result(ship), Ok(()));
            assert_eq!(
                f.world
                    .get::<ConstructionSite>(site.unwrap())
                    .unwrap()
                    .progress_delivered,
                10
            );
            assert_eq!(f.world.get::<ShipCargo>(ship).unwrap().used(), 0);
            assert_eq!(
                f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Ore],
                0.0
            );
        } else {
            assert!(f.result(ship).is_err());
            assert_eq!(before, f.snapshot(ship));
            if let Some(site) = site {
                assert_eq!(
                    f.world
                        .get::<ConstructionSite>(site)
                        .unwrap()
                        .progress_delivered,
                    0
                );
            }
        }
    }
}
