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
        self.store.contracts.register_prepaid(&id, sim_core::economy::contracts::FundingSource::Facility);
        self.store.contracts.get_mut(&id).unwrap().funding.as_mut().unwrap().agreed_payment = Some(120);
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

fn escrow_offer(f: &mut Fixture) -> String {
    let id = f.delivery(false);
    assert!(f.store.contracts.release(&id, Some("ship-0")));
    f.world
        .get_mut::<ShipEconomy>(f.ships[0])
        .unwrap()
        .active_contract_id = None;
    // A real publisher debits this advance before registering it.
    f.world
        .get_mut::<FacilityOperations>(f.facility)
        .unwrap()
        .credits = 880;
    f.store.contracts.get_mut(&id).unwrap().funding.as_mut().unwrap().agreed_payment = None;
    f.store.contracts.get_mut(&id).unwrap().payment = 150;
    id
}

#[test]
fn escrow_acceptance_reserves_and_locks_reward_until_delivery() {
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    let id = escrow_offer(&mut f);
    let accept = f.submit(
        ship,
        ShipTransaction::Accept {
            contract_id: id.clone(),
        },
    );
    f.apply(ship, accept);
    assert_eq!(f.result(ship), Ok(()));
    assert_eq!(
        f.world
            .get::<FacilityOperations>(f.facility)
            .unwrap()
            .credits,
        850
    );
    let funding = f
        .store
        .contracts
        .get(&id)
        .unwrap()
        .funding
        .as_ref()
        .unwrap();
    assert_eq!((funding.reserved, funding.agreed_payment), (150, Some(150)));
    f.apply(ship, accept); // duplicate acceptance cannot debit again
    assert_eq!(
        f.world
            .get::<FacilityOperations>(f.facility)
            .unwrap()
            .credits,
        850
    );
    f.world
        .get_mut::<ShipEconomy>(ship)
        .unwrap()
        .transaction
        .pending = None;
    // Spend the requestor's remaining budget and change the current quote:
    // neither can revoke the money already reserved for this carrier.
    f.world
        .get_mut::<FacilityOperations>(f.facility)
        .unwrap()
        .credits = 0;
    f.store.contracts.get_mut(&id).unwrap().payment = 9999;
    let deliver = f.submit(
        ship,
        ShipTransaction::Deliver {
            contract_id: id.clone(),
        },
    );
    f.apply(ship, deliver);
    assert_eq!(f.result(ship), Ok(()));
    assert_eq!(f.world.get::<ShipEconomy>(ship).unwrap().credits, 1150);
    assert_eq!(
        f.store
            .contracts
            .get(&id)
            .unwrap()
            .funding
            .as_ref()
            .unwrap()
            .reserved,
        0
    );
    assert_eq!(
        f.store.contracts.get(&id).unwrap().status,
        ContractStatus::Paid
    );
    let after = f.snapshot(ship);
    f.apply(ship, deliver);
    assert_eq!(f.snapshot(ship), after);
}

#[test]
fn escrow_competing_acceptances_cannot_spend_the_same_budget() {
    use sim_core::economy::contracts::FundingSource;
    let mut f = Fixture::new(0.0, 0.0);
    let a = escrow_offer(&mut f);
    let b = f.store.contracts.post_delivery_for(
        "station".into(),
        None,
        Commodity::Ore,
        10,
        "source".into(),
        "port".into(),
        120,
        0,
        1000,
    );
    f.world
        .get_mut::<FacilityOperations>(f.facility)
        .unwrap()
        .credits -= 120;
    f.store
        .contracts
        .register_prepaid(&b, FundingSource::Facility);
    for id in [&a, &b] {
        f.store.contracts.get_mut(id).unwrap().payment = 600;
    }
    let [first, second] = f.ships;
    let ra = f.submit(
        first,
        ShipTransaction::Accept {
            contract_id: a.clone(),
        },
    );
    let rb = f.submit(
        second,
        ShipTransaction::Accept {
            contract_id: b.clone(),
        },
    );
    f.apply(first, ra);
    assert_eq!(f.result(first), Ok(()));
    let before = f.snapshot(second);
    f.apply(second, rb);
    assert_eq!(f.result(second), Err("insufficient_contract_funding"));
    assert_eq!(f.snapshot(second), before);
    assert_eq!(
        f.store.contracts.get(&b).unwrap().status,
        ContractStatus::Posted
    );
    assert!(f
        .world
        .get::<ShipEconomy>(second)
        .unwrap()
        .active_contract_id
        .is_none());
    let reserved: i64 = [&a, &b]
        .iter()
        .map(|id| {
            f.store
                .contracts
                .get(id)
                .unwrap()
                .funding
                .as_ref()
                .unwrap()
                .reserved
        })
        .sum();
    assert_eq!(
        reserved
            + f.world
                .get::<FacilityOperations>(f.facility)
                .unwrap()
                .credits,
        1000
    );
}

#[test]
fn escrow_expiry_cancellation_and_loss_refund_once_but_release_keeps_reserve() {
    for reason in ["expiry", "cancellation", "cargo_lost"] {
        let mut f = Fixture::new(0.0, 0.0);
        let ship = f.ships[0];
        let id = escrow_offer(&mut f);
        let request = f.submit(
            ship,
            ShipTransaction::Accept {
                contract_id: id.clone(),
            },
        );
        f.apply(ship, request);
        if reason == "expiry" {
            assert!(f.store.contracts.release(&id, Some("ship-0")));
            f.apply(ship, request);
            assert_eq!(
                f.world
                    .get::<FacilityOperations>(f.facility)
                    .unwrap()
                    .credits,
                850
            );
            assert_eq!(
                f.store
                    .contracts
                    .get(&id)
                    .unwrap()
                    .funding
                    .as_ref()
                    .unwrap()
                    .agreed_payment,
                None
            );
            let c = f.store.contracts.get_mut(&id).unwrap();
            c.renewal_count = u8::MAX;
            c.expires_at_tick = 0;
            f.store.contracts.sweep_expiring(11, 10);
        } else if reason == "cancellation" {
            f.store
                .contracts
                .cancel_for_facility(None, None, Some("port"));
        } else {
            assert!(f.store.contracts.mark_picked_up(&id));
            f.store.contracts.drop_ship_holdings("ship-0");
        }
        assert_eq!(
            f.store.contracts.get(&id).unwrap().status,
            ContractStatus::Expired
        );
        // An unavailable refund beneficiary must not make the reserve disappear.
        f.store.facility_by_id.remove("station");
        f.apply(ship, request);
        assert_eq!(
            f.store
                .contracts
                .get(&id)
                .unwrap()
                .funding
                .as_ref()
                .unwrap()
                .reserved,
            150
        );
        f.store.facility_by_id.insert("station".into(), f.facility);
        f.apply(ship, request);
        assert_eq!(
            f.world
                .get::<FacilityOperations>(f.facility)
                .unwrap()
                .credits,
            1000
        );
        assert_eq!(
            f.store
                .contracts
                .get(&id)
                .unwrap()
                .funding
                .as_ref()
                .unwrap()
                .reserved,
            0
        );
        f.apply(ship, request);
        assert_eq!(
            f.world
                .get::<FacilityOperations>(f.facility)
                .unwrap()
                .credits,
            1000
        );
        assert_eq!(
            f.events
                .iter()
                .filter(|e| e["kind"] == "contract_escrow_refunded")
                .count(),
            1
        );
    }
}

#[test]
fn foundation_legacy_reward_changes_do_not_prove_a_historic_debit() {
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    let id = f.delivery(false);
    f.store.contracts.get_mut(&id).unwrap().funding = None;
    f.store.contracts.get_mut(&id).unwrap().payment = 150;
    f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits = 880;
    let before = f.snapshot(ship);
    let request = f.submit(ship, ShipTransaction::Deliver { contract_id: id });
    f.apply(ship, request);
    assert_eq!(f.result(ship), Err("unverified_legacy_funding"));
    assert_eq!(f.snapshot(ship), before);
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
        // Test the rejected transaction itself. The enclosing apply pass also
        // legitimately refunds expired escrow, covered by escrow_expiry_* above.
        apply_transaction(&mut f.world, &mut f.store, ship, request, &mut f.events, 10);
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

#[tokio::test]
async fn lifecycle_removal_and_escrow_survive_backpressure_in_one_frame() {
    use sim_db::persistence::DbWrite;
    use crate::engine::{admin, contract_funding, persist};
    for remove_ship in [true, false] {
        let mut f = Fixture::new(0.0, 0.0);
        let ship = f.ships[0];
        let id = escrow_offer(&mut f);
        let request = f.submit(ship, ShipTransaction::Accept { contract_id: id.clone() });
        f.apply(ship, request);
        assert!(f.store.contracts.mark_picked_up(&id));
        let (tx, mut rx) = tokio::sync::mpsc::channel(1);
        tx.try_send(DbWrite::Tick { tick: 9 }).unwrap();
        if remove_ship {
            admin::admin_remove_ship(&mut f.world, &mut f.store, "ship-0", 10, &mut f.events, &tx).await;
        } else {
            admin::admin_remove_facility(&mut f.world, &mut f.store, "station", &mut f.events, &tx).await;
        }
        // Removal never blocks on the full queue or exposes a standalone delete.
        assert!(persist::has_lifecycle_writes(&f.world));
        assert_eq!(rx.len(), 1);
        contract_funding::refund_closed(&mut f.world, &mut f.store, &mut f.events, 10);
        persist::emit_persist_writes(&mut f.world, &mut f.store, 10, &tx);
        assert!(persist::has_lifecycle_writes(&f.world));
        rx.try_recv().unwrap();
        // Same tick models a paused engine retry: no simulation step required.
        persist::emit_persist_writes(&mut f.world, &mut f.store, 10, &tx);
        assert!(!persist::has_lifecycle_writes(&f.world));
        let DbWrite::EconomicFrame { writes } = rx.try_recv().unwrap() else { panic!("missing frame"); };
        let rows = writes.iter().find_map(|w| match w {
            DbWrite::ContractBoardSnapshot { rows } => Some(rows), _ => None,
        }).unwrap();
        let row = rows.iter().find(|r| r.id == id).unwrap();
        assert_eq!(row.status, "expired");
        let funding: serde_json::Value = serde_json::from_str(row.funding_json.as_ref().unwrap()).unwrap();
        if remove_ship {
            assert_eq!(funding["reserved"], 0);
            assert!(writes.iter().any(|w| matches!(w, DbWrite::Facility { db_id: 1, credits: 1000, .. })));
            assert_eq!(writes.iter().filter(|w| matches!(w, DbWrite::DeleteShip { db_id: 10 })).count(), 1);
            assert_eq!(writes.iter().filter(|w| matches!(w, DbWrite::RetireShip { .. })).count(), 1);
        } else {
            // A removed payer cannot receive a refund: preserve its escrow.
            assert_eq!(funding["reserved"], 150);
            assert_eq!(writes.iter().filter(|w| matches!(w, DbWrite::DeleteFacility { db_id: 1 })).count(), 1);
        }
        assert!(rx.try_recv().is_err());
    }
}

#[test]
fn flight_recovery_emitter_captures_stable_dock_and_flight_progress() {
    use sim_db::persistence::{DbWrite, ShipResumeState};
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    f.world.get_mut::<ShipLifecycle>(ship).unwrap().dirty = true;
    let (tx, mut rx) = tokio::sync::mpsc::channel(1);
    crate::engine::persist::emit_persist_writes(&mut f.world, &mut f.store, 40, &tx);
    let DbWrite::EconomicFrame { writes } = rx.try_recv().unwrap() else { panic!("frame"); };
    let resume = writes.iter().find_map(|w| match w {
        DbWrite::Ship { db_id: 10, resume_json, .. } => Some(serde_json::from_str::<ShipResumeState>(resume_json).unwrap()),
        _ => None,
    }).unwrap();
    assert_eq!(resume.docked_db_id, Some(1));
    assert_eq!(resume.location_name.as_deref(), Some("port"));
    assert!(resume.transit.is_none());
    {
        let mut pos = f.world.get_mut::<ShipPosition>(ship).unwrap();
        pos.location_name = None;
        pos.docked_at = None;
    }
    f.world.get_mut::<ShipTransit>(ship).unwrap().transit = Some(sim_core::agents::ship::Transit {
        from: "port".into(), to: "next".into(), departure_tick: 40, arrival_tick: 90,
        departure_position: Some((1.0, 2.0)), distance_total: 100.0, distance_travelled: 25.0,
    });
    f.world.get_mut::<ShipLifecycle>(ship).unwrap().dirty = true;
    crate::engine::persist::emit_persist_writes(&mut f.world, &mut f.store, 50, &tx);
    let DbWrite::EconomicFrame { writes } = rx.try_recv().unwrap() else { panic!("frame"); };
    let resume = writes.iter().find_map(|w| match w {
        DbWrite::Ship { db_id: 10, resume_json, .. } => Some(serde_json::from_str::<ShipResumeState>(resume_json).unwrap()),
        _ => None,
    }).unwrap();
    assert_eq!(resume.docked_db_id, None);
    assert_eq!(resume.location_name, None);
    assert_eq!(resume.transit.unwrap().distance_travelled, 25.0);
}

#[test]
fn strategy_block_head_to_logistics_to_native_delivery() {
    use sim_core::{strategy::{self, Mode, StrategyState}, agents::faction::{FactionData, FactionColors}};
    let mut f = Fixture::new(0.0, 100.0);
    f.world.get_mut::<FacilityIdentity>(f.facility).unwrap().faction_id = "haulers".into();
    let faction = f.world.spawn(FactionData { id: "haulers".into(), name: "Haulers".into(),
        faction_type: "normal".into(), home_system: "sol".into(), treasury: 20_000,
        personality: sim_core::ai::personality::Personality::balanced_trader(),
        colors: FactionColors { primary: String::new(), secondary: String::new() },
        active_subsidies: 0, dirty: false }).id();
    f.store.faction_by_id.insert("haulers".into(), faction);
    f.world.get_mut::<MarketHistory>(f.market).unwrap().shortage_ticks.insert(Commodity::Ore, 50);
    let source = f.world.spawn((
        FacilityIdentity { db_id: 5, id: "mine".into(), name: "Mine".into(), facility_type: "mining_rig".into(), faction_id: "haulers".into(), body_id: "earth".into() },
        FacilityLocation { location_id: 2, location_name: "mine".into() },
        FacilityOperations { docking_capacity: 4, services: vec![], condition: 1.0, reputation: 50, credits: 0, dirty: false, starving_notified: false },
        FacilityStorage::default(), FacilityLifecycle::new(),
    )).id();
    f.store.facility_by_id.insert("mine".into(), source);
    let source_market = f.world.spawn((MarketIdentity { db_id: 6, id: "mine-market".into(), facility: source, facility_location: "mine".into() },
        MarketHistory::default(), MarketPricing { price_elasticity: 1.0, spread: 0.0,
            prices: [(Commodity::Ore,1.0)].into(), supply: [(Commodity::Ore,200.0)].into(), demand: Default::default() })).id();
    f.store.market_at_location.insert("mine".into(), source_market);
    strategy::run_cycle(&mut f.world, &mut f.store.contracts, &f.store.relations, 60, 1);
    assert_eq!(f.store.contracts.iter().count(), 0, "shadow cannot commission");
    assert_eq!(f.world.get::<FactionData>(faction).unwrap().treasury, 20_000);
    assert_eq!(f.world.resource::<StrategyState>().factions["haulers"].status, "proposed");
    f.world.resource_mut::<StrategyState>().mode = Mode::Execute;
    f.world.get_mut::<FactionData>(faction).unwrap().treasury = 0;
    strategy::run_cycle(&mut f.world, &mut f.store.contracts, &f.store.relations, 80, 1);
    assert_eq!(f.world.resource::<StrategyState>().factions["haulers"].reason, "insufficient_budget");
    assert_eq!(f.store.contracts.iter().count(), 0);
    f.world.get_mut::<FactionData>(faction).unwrap().treasury = 20_000;
    f.world.get_mut::<MarketPricing>(source_market).unwrap().supply.insert(Commodity::Ore, 0.0);
    strategy::run_cycle(&mut f.world, &mut f.store.contracts, &f.store.relations, 100, 1);
    assert_eq!(f.world.resource::<StrategyState>().factions["haulers"].reason, "no_accessible_stock");
    assert_eq!(f.store.contracts.iter().count(), 0);
    f.world.get_mut::<MarketPricing>(source_market).unwrap().supply.insert(Commodity::Ore, 200.0);
    strategy::run_cycle(&mut f.world, &mut f.store.contracts, &f.store.relations, 120, 1);
    let id = f.store.contracts.iter().next().unwrap().id.clone();
    assert_eq!(f.store.contracts.get(&id).unwrap().funding.as_ref().unwrap().reserved, 1600);
    strategy::run_cycle(&mut f.world, &mut f.store.contracts, &f.store.relations, 180, 1);
    assert_eq!(f.store.contracts.iter().count(), 1, "held project cannot duplicate");
    assert_eq!(f.world.get::<FactionData>(faction).unwrap().treasury, 18_400);
    let ship = f.ships[0];
    f.world.get_mut::<ShipCargo>(ship).unwrap().capacity = 300;
    let request = f.submit(ship, ShipTransaction::Accept { contract_id: id.clone() });
    f.apply(ship, request); assert_eq!(f.result(ship), Ok(()));
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    { let mut pos = f.world.get_mut::<ShipPosition>(ship).unwrap(); pos.location_name = Some("mine".into()); pos.docked_at = Some(source); }
    f.world.get_mut::<FacilityStorage>(f.facility).unwrap().docked_ships.retain(|e| *e != ship);
    f.world.get_mut::<FacilityStorage>(source).unwrap().docked_ships.push(ship);
    let request = f.submit(ship, ShipTransaction::Buy { location: "mine".into(), commodity: Commodity::Ore, quantity: 200, max_unit_price: 1.0 });
    f.apply(ship, request); assert_eq!(f.result(ship), Ok(()));
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    // Arrival is supplied by the existing navigation system; exercise the real
    // destination settlement after moving the fixture to that dock.
    { let mut pos = f.world.get_mut::<ShipPosition>(ship).unwrap(); pos.location_name = Some("port".into()); pos.docked_at = Some(f.facility); }
    f.world.get_mut::<FacilityStorage>(source).unwrap().docked_ships.retain(|e| *e != ship);
    f.world.get_mut::<FacilityStorage>(f.facility).unwrap().docked_ships.push(ship);
    let request = f.submit(ship, ShipTransaction::Deliver { contract_id: id.clone() });
    f.apply(ship, request); assert_eq!(f.result(ship), Ok(()));
    strategy::refresh(&mut f.world, &f.store.contracts, 200);
    let snapshot = f.world.resource::<StrategyState>().snapshot(200);
    assert_eq!(snapshot.schema_version, 1);
    assert_eq!(snapshot.factions[0].projects[0].state, "paid");
    assert_eq!(f.world.get::<MarketPricing>(source_market).unwrap().supply[&Commodity::Ore], 0.0);
    assert_eq!(f.world.get::<ShipCargo>(ship).unwrap().cargo.get(&Commodity::Ore).copied().unwrap_or(0), 0);
    assert_eq!(f.world.get::<ShipEconomy>(ship).unwrap().credits, 2450);
    // A newly reconstructed diagnostic state discovers the persisted project tag.
    f.world.insert_resource(StrategyState { mode: Mode::Execute, ..Default::default() });
    strategy::refresh(&mut f.world, &f.store.contracts, 201);
    assert_eq!(f.world.resource::<StrategyState>().factions["haulers"].projects[0].contract_id, id);
}

#[tokio::test]
async fn strategy_block_construction_queues_complete_frame_without_free_capital() {
    use sim_core::agents::faction::{FactionData, FactionColors};
    use sim_db::persistence::DbWrite;
    let mut f = Fixture::new(0.0, 0.0);
    let owner = f.world.spawn(FactionData { id: "haulers".into(), name: "Haulers".into(),
        faction_type: "normal".into(), home_system: "sol".into(), treasury: 1000,
        personality: sim_core::ai::personality::Personality::balanced_trader(),
        colors: FactionColors { primary: String::new(), secondary: String::new() }, active_subsidies: 0, dirty: false }).id();
    f.store.faction_by_id.insert("haulers".into(), owner);
    crate::engine::drains::materialize_facility(&mut f.world, &mut f.store, "site", "New Factory",
        "factory", "earth", "haulers", "port", (0.0, 0.0), &mut f.events);
    let entity = f.store.pending_materializations[0].entity;
    let db_id = f.world.get::<FacilityIdentity>(entity).unwrap().db_id;
    assert!(db_id < 0);
    assert_eq!(f.world.get::<FacilityOperations>(entity).unwrap().credits, 1000);
    assert_eq!(f.world.get::<FactionData>(owner).unwrap().treasury, 0);
    let pool = sqlx::SqlitePool::connect_lazy("sqlite::memory:").unwrap();
    let (tx, mut rx) = tokio::sync::mpsc::channel(1);
    tx.try_send(DbWrite::Tick { tick: 1 }).unwrap();
    crate::engine::drains::drain_pending_materializations(&mut f.world, &mut f.store, &pool, &tx, &mut f.events).await;
    crate::engine::persist::emit_persist_writes(&mut f.world, &mut f.store, 2, &tx);
    assert!(crate::engine::persist::has_lifecycle_writes(&f.world));
    rx.try_recv().unwrap();
    crate::engine::persist::emit_persist_writes(&mut f.world, &mut f.store, 3, &tx);
    let DbWrite::EconomicFrame { writes } = rx.try_recv().unwrap() else { panic!("frame"); };
    assert!(writes.iter().any(|w| matches!(w, DbWrite::ConstructedFacility { row } if row.db_id == db_id && row.source_site_id == "site")));
    assert!(writes.iter().any(|w| matches!(w, DbWrite::ConstructionSiteDelete { agent_id } if agent_id == "site")));
    assert!(writes.iter().any(|w| matches!(w, DbWrite::Faction { treasury: 0, .. })));
    assert!(writes.iter().any(|w| matches!(w, DbWrite::Facility { credits: 1000, .. })));
    assert!(writes.iter().any(|w| matches!(w, DbWrite::ContractBoardSnapshot { .. })));
}

#[test]
fn strategy_block_construction_administrator_to_native_materialization() {
    use sim_core::{strategy::{self, Mode, StrategyState}, agents::{faction::{FactionData,FactionColors}, celestial_body::{BodyIdentity,BodyOrbit}}};
    let mut f = Fixture::new(0.0,100.0);
    f.world.insert_resource(StrategyState { mode: Mode::Execute, ..Default::default() });
    f.world.get_mut::<FacilityIdentity>(f.facility).unwrap().faction_id = "haulers".into();
    let owner = f.world.spawn(FactionData { id: "haulers".into(), name: "Haulers".into(),
        faction_type: "normal".into(), home_system: "sol".into(), treasury: 80_000,
        personality: sim_core::ai::personality::Personality::balanced_trader(),
        colors: FactionColors { primary: String::new(), secondary: String::new() }, active_subsidies: 0, dirty: false }).id();
    f.store.faction_by_id.insert("haulers".into(),owner);
    f.world.spawn((BodyIdentity { db_id: 1, body_id: "earth".into(), name: "Earth".into(), body_type: "planet".into(), star_system_id: 1, system_name: "sol".into() },
        BodyOrbit { orbit_radius: 1.0, orbit_period: 100, current_angle: 0.0, universe_offset: (0.0,0.0), dirty: false }));
    let site = f.site(600);
    f.world.get_mut::<ConstructionSite>(site).unwrap().progress_delivered = 590;
    let source = f.world.spawn((
        FacilityIdentity { db_id: 5, id: "mine".into(), name: "Mine".into(), facility_type: "mining_rig".into(), faction_id: "haulers".into(), body_id: "earth".into() },
        FacilityLocation { location_id: 2, location_name: "mine".into() },
        FacilityOperations { docking_capacity: 4, services: vec![], condition: 1.0, reputation: 50, credits: 0, dirty: false, starving_notified: false },
        FacilityStorage::default(), FacilityLifecycle::new(),
    )).id();
    f.store.facility_by_id.insert("mine".into(),source);
    let source_market = f.world.spawn((MarketIdentity { db_id: 6, id: "mine-market".into(), facility: source, facility_location: "mine".into() },
        MarketHistory::default(), MarketPricing { price_elasticity: 1.0, spread: 0.0,
            prices: [(Commodity::Ore,1.0)].into(), supply: [(Commodity::Ore,10.0)].into(), demand: Default::default() })).id();
    f.store.market_at_location.insert("mine".into(),source_market);
    strategy::construction::run_cycle(&mut f.world,&mut f.store.contracts,&f.store.relations,&mut f.events,200,1);
    let id = f.store.contracts.iter().next().unwrap().id.clone();
    assert_eq!(f.store.contracts.get(&id).unwrap().quantity,10);
    let ship = f.ships[0];
    let request = f.submit(ship,ShipTransaction::Accept { contract_id: id.clone() });
    f.apply(ship,request); assert_eq!(f.result(ship),Ok(()));
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    { let mut pos = f.world.get_mut::<ShipPosition>(ship).unwrap(); pos.location_name = Some("mine".into()); pos.docked_at = Some(source); }
    f.world.get_mut::<FacilityStorage>(f.facility).unwrap().docked_ships.retain(|e| *e != ship);
    f.world.get_mut::<FacilityStorage>(source).unwrap().docked_ships.push(ship);
    let request = f.submit(ship,ShipTransaction::Buy { location: "mine".into(), commodity: Commodity::Ore, quantity: 10, max_unit_price: 1.0 });
    f.apply(ship,request); assert_eq!(f.result(ship),Ok(()));
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    // Navigation is fixture relocation; all purchase/delivery/construction effects are native.
    { let mut pos = f.world.get_mut::<ShipPosition>(ship).unwrap(); pos.location_name = Some("port".into()); pos.docked_at = Some(f.facility); }
    f.world.get_mut::<FacilityStorage>(source).unwrap().docked_ships.retain(|e| *e != ship);
    f.world.get_mut::<FacilityStorage>(f.facility).unwrap().docked_ships.push(ship);
    let request = f.submit(ship,ShipTransaction::Deliver { contract_id: id.clone() });
    f.apply(ship,request); assert_eq!(f.result(ship),Ok(()));
    assert_eq!(f.store.contracts.get(&id).unwrap().status,ContractStatus::Paid);
    assert_eq!(f.world.get::<ShipCargo>(ship).unwrap().used(),0);
    assert!(f.world.get::<ConstructionSite>(site).is_none());
    assert_eq!(f.store.pending_materializations.len(),1);
    let built = f.store.pending_materializations[0].entity;
    assert_eq!(f.world.get::<FacilityIdentity>(built).unwrap().facility_type,"mining_rig");
    assert_eq!(f.world.get::<FacilityOperations>(built).unwrap().credits,20_000);
    assert_eq!(f.world.get::<FactionData>(owner).unwrap().treasury,50_000);
    strategy::construction::run_cycle(&mut f.world,&mut f.store.contracts,&f.store.relations,&mut f.events,400,1);
    assert_eq!(f.store.contracts.iter().count(),1,"completed project must not duplicate");
    assert_eq!(f.world.resource::<StrategyState>().factions["haulers"].projects[0].state,"paid");
}

#[test]
fn strategy_block_reward_stays_within_head_approval_through_renewal_and_acceptance() {
    use sim_core::agents::faction::{FactionColors, FactionData};
    use sim_core::economy::contracts::FundingSource;

    let mut f = Fixture::new(0.0, 0.0);
    let owner = f.world.spawn(FactionData {
        id: "haulers".into(),
        name: "Haulers".into(),
        faction_type: "normal".into(),
        home_system: "sol".into(),
        treasury: 5_000,
        personality: sim_core::ai::personality::Personality::balanced_trader(),
        colors: FactionColors { primary: String::new(), secondary: String::new() },
        active_subsidies: 0,
        dirty: false,
    }).id();
    f.store.faction_by_id.insert("haulers".into(), owner);
    let id = f.store.contracts.post_construction(
        "haulers".into(), Some("haulers".into()), Commodity::Ore, 10,
        "source".into(), "port".into(), 10_000, 0, 100,
    );
    f.store.contracts.register_prepaid(&id, FundingSource::Faction);
    let contract = f.store.contracts.get_mut(&id).unwrap();
    contract.mission_category = Some(sim_core::strategy::construction::PROJECT_TAG.into());
    // Older checkpoints can have an inflated Posted reward.
    contract.payment = 27_344;
    let mut restored = sim_core::economy::contracts::ContractBoard::new();
    restored.insert_loaded(contract.clone());
    assert_eq!(restored.get(&id).unwrap().payment, 10_000);
    f.store.contracts = restored;
    f.store.contracts.age_escalate_payment(1000);
    let sweep = f.store.contracts.sweep_expiring(1000, 100);
    assert_eq!(sweep.renewed[0].new_payment, 10_000);
    let ship = f.ships[0];
    let request = f.submit(ship, ShipTransaction::Accept { contract_id: id.clone() });
    f.apply(ship, request);
    assert_eq!(f.result(ship), Ok(()));
    let escrow = f.store.contracts.get(&id).unwrap().funding.as_ref().unwrap();
    assert_eq!(escrow.agreed_payment, Some(10_000));
    assert_eq!(escrow.reserved, 10_000);
    assert_eq!(f.world.get::<FactionData>(owner).unwrap().treasury, 5_000);
}

fn sale(quantity: u32) -> ShipTransaction {
    ShipTransaction::Sell { location: "port".into(), commodity: Commodity::Ore,
        quantity, min_unit_price: 10.0 }
}

#[test]
fn foundation_sale_competition_cash_stock_and_duplicate_receipt() {
    use sim_core::economy::money::MoneySnapshot;
    let mut f = Fixture::new(0.0, 0.0);
    f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits = 100;
    for ship in f.ships { f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Ore, 10); }
    let before = MoneySnapshot::capture(&mut f.world, &f.store.contracts);
    let [first, second] = f.ships;
    let a = f.submit(first, sale(10));
    let b = f.submit(second, sale(10));
    f.apply(first, a); f.apply(second, b);
    assert_eq!(f.result(first), Ok(()));
    assert_eq!(f.result(second), Err("insufficient_buyer_credits"));
    assert_eq!(f.world.get::<ShipCargo>(second).unwrap().cargo[&Commodity::Ore], 10);
    assert_eq!(f.world.get::<MarketPricing>(f.market).unwrap().supply[&Commodity::Ore], 10.0);
    assert_eq!(MoneySnapshot::capture(&mut f.world, &f.store.contracts).total, before.total);
    let committed = f.snapshot(first);
    f.apply(first, a);
    assert_eq!(f.snapshot(first), committed);
}

#[test]
fn foundation_sale_rejects_without_any_partial_change() {
    for case in 0..5 {
        let mut f = Fixture::new(0.0, 0.0);
        let ship = f.ships[0];
        f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits = 1000;
        f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Ore, 10);
        match case {
            0 => f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits = 0,
            1 => { f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.clear(); },
            2 => f.world.get_mut::<ShipPosition>(ship).unwrap().docked_at = None,
            3 => f.world.get_mut::<ShipEconomy>(ship).unwrap().credits = i64::MAX,
            _ => { f.world.get_mut::<MarketPricing>(f.market).unwrap().prices.insert(Commodity::Ore, 9.0); },
        }
        let before = f.snapshot(ship);
        let id = f.submit(ship, sale(10)); f.apply(ship, id);
        assert!(f.result(ship).is_err());
        assert_eq!(before, f.snapshot(ship));
    }
}

#[test]
fn foundation_market_placeholder_cannot_mint_a_spread() {
    let mut f = Fixture::new(0.0, 0.0);
    let mut commands = CommandBuffer::new();
    commands.push(SimCommand::TransferCredits { from: f.market, to: f.facility, amount: 100 });
    super::super::apply::apply_ship_commands(&mut f.world, &mut f.store, &mut commands, &mut f.events, 1);
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits, 0);
    assert_eq!(f.events.last().unwrap()["reason"], "unfunded_transfer");
}

#[test]
fn foundation_unverified_legacy_contract_neither_claims_nor_pays() {
    let mut f = Fixture::new(0.0, 0.0);
    let id = f.store.contracts.post_delivery_for("station".into(), None, Commodity::Ore,
        10, "source".into(), "port".into(), 100, 0, 100);
    let ship = f.ships[0];
    let before = f.snapshot(ship);
    let request = f.submit(ship, ShipTransaction::Accept { contract_id: id.clone() });
    f.apply(ship, request);
    assert_eq!(f.result(ship), Err("unverified_legacy_funding"));
    assert_eq!(before, f.snapshot(ship));
    // Old saves may already have an accepted, unfunded contract.
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    f.store.contracts.accept(&id, "ship-0".into(), 1);
    f.world.get_mut::<ShipEconomy>(ship).unwrap().active_contract_id = Some(id.clone());
    f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Ore, 10);
    let before = f.snapshot(ship);
    let request = f.submit(ship, ShipTransaction::Deliver { contract_id: id });
    f.apply(ship, request);
    assert_eq!(f.result(ship), Err("unverified_legacy_funding"));
    assert_eq!(before, f.snapshot(ship));
}

#[test]
fn foundation_trade_and_household_consumption_recirculate_cash() {
    use sim_core::agents::population::*;
    use sim_core::economy::money::MoneySnapshot;
    let mut f = Fixture::new(20.0, 10.0);
    let ship = f.ships[0];
    let pop = f.world.spawn((PopIdentity { db_id: 1, id:"workers".into(), label:"Workers".into(),
        demographic:"workers".into(), facility:f.facility, facility_location:"port".into(), faction_id:"".into() },
        PopEconomy { total_wealth:100, spending_rate:1.0, consumption:Default::default(),
            production_commodity:None, production_amount:0.0 },
        PopSentiment { overall_sentiment:50, unrest:0, food_satisfaction:50,
            safety_satisfaction:50, entertainment_satisfaction:50, dirty:false })).id();
    let before = MoneySnapshot::capture(&mut f.world, &f.store.contracts).total;
    for _ in 0..2 {
        let request = f.submit(ship, purchase()); f.apply(ship, request);
        assert_eq!(f.result(ship), Ok(()));
        f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
        let request = f.submit(ship, sale(10)); f.apply(ship, request);
        assert_eq!(f.result(ship), Ok(()));
        f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
        assert_eq!(MoneySnapshot::capture(&mut f.world, &f.store.contracts).total, before);
    }
    assert_eq!(purchase_consumption(&mut f.world, pop, f.market, Commodity::Ore, 10.0, 5), Ok((10.0,100)));
    assert_eq!(f.world.get::<FacilityOperations>(f.facility).unwrap().credits, 100);
    assert_eq!(f.world.get::<PopEconomy>(pop).unwrap().total_wealth, 0);
    let stock = f.world.get::<MarketPricing>(f.market).unwrap().supply.clone();
    assert_eq!(purchase_consumption(&mut f.world, pop, f.market, Commodity::Ore, 1.0, 10), Err("insufficient_household_credits"));
    assert_eq!(f.world.get::<MarketPricing>(f.market).unwrap().supply, stock);
    assert_eq!(MoneySnapshot::capture(&mut f.world, &f.store.contracts).total, before);
}

#[tokio::test]
async fn foundation_sale_checkpoint_restores_both_wallets_and_cargo_once() {
    use sim_db::persistence::PersistenceWorker;
    let pool = sim_db::pool::create_pool("sqlite::memory:").await.unwrap();
    sim_db::pool::run_migrations(&pool).await.unwrap();
    for sql in [
        "INSERT INTO star_systems (id,name) VALUES (1,'sol')",
        "INSERT INTO celestial_bodies (id,body_id,name,body_type,orbit_radius,orbit_period,current_angle,star_system_id) VALUES (1,'earth','Earth','planet',1,100,0,1)",
        "INSERT INTO locations (id,name,loc_type,celestial_body_id) VALUES (1,'port','station',1)",
        "INSERT INTO facilities (id,name,facility_type,location_id,location_name,credits) VALUES (1,'Station','station',1,'port',100)",
        "INSERT INTO markets (id,facility_id,facility_location,prices,supply) VALUES (2,1,'port','{\"ore\":10}','{\"ore\":0}')",
        "INSERT INTO ships (id,name,location_name,credits,cargo) VALUES (10,'Runner','port',1000,'{\"ore\":10}')",
        "INSERT INTO ships (id,name,location_name,credits) VALUES (11,'Other','port',1000)",
    ] { sqlx::query(sql).execute(&pool).await.unwrap(); }
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    f.world.get_mut::<FacilityOperations>(f.facility).unwrap().credits = 100;
    f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Ore, 10);
    let request = f.submit(ship, sale(10)); f.apply(ship, request);
    assert_eq!(f.result(ship), Ok(()));
    let (tx, rx) = tokio::sync::mpsc::channel(4);
    let (flush_tx, flush_rx) = tokio::sync::mpsc::channel(1);
    super::super::persist::emit_persist_writes(&mut f.world, &mut f.store, 10, &tx);
    // Closing the admitted write stream flushes the complete economic frame.
    drop(tx); drop(flush_tx);
    PersistenceWorker::new(pool.clone(), rx, flush_rx, std::time::Duration::from_secs(1)).run().await;
    let mut world = World::new();
    let mut store = sim_db::spawner::load_agents(&mut world, &pool,
        &sim_core::world::registry::WorldRegistry::default(),
        &sim_core::simulation::config::TickConfig::DEFAULT).await.unwrap();
    let ship = store.ship_by_id["ship-runner"];
    assert_eq!(world.get::<ShipEconomy>(ship).unwrap().credits, 1100);
    assert_eq!(world.get::<ShipCargo>(ship).unwrap().used(), 0);
    let market = store.market_at_location["port"];
    let owner = world.get::<MarketIdentity>(market).unwrap().facility;
    assert_eq!(world.get::<FacilityOperations>(owner).unwrap().credits, 0);
    assert_eq!(world.get::<MarketPricing>(market).unwrap().supply[&Commodity::Ore], 10.0);
    let before = sim_core::economy::money::MoneySnapshot::capture(&mut world, &store.contracts);
    let id = world.get_mut::<ShipEconomy>(ship).unwrap().transaction.begin(sale(10)).unwrap();
    apply_transaction(&mut world, &mut store, ship, id, &mut vec![], 11);
    assert!(world.get::<ShipEconomy>(ship).unwrap().transaction.pending.as_ref().unwrap().result.unwrap().is_err());
    assert_eq!(sim_core::economy::money::MoneySnapshot::capture(&mut world, &store.contracts), before);
    pool.close().await;
}

#[test]
fn foundation_household_delivery_spends_escrow_without_reselling_its_food() {
    use sim_core::agents::population::*;
    use sim_core::economy::{contracts::FundingSource, money::MoneySnapshot};
    let mut f = Fixture::new(0.0, 0.0);
    let ship = f.ships[0];
    let pop = f.world.spawn((PopIdentity { db_id:1, id:"workers".into(), label:"Workers".into(),
        demographic:"workers".into(), facility:f.facility, facility_location:"port".into(), faction_id:"".into() },
        PopDemographics { population_count:100, growth_rate:0.0, employed_fraction:0.0, migration_pressure:0.0 },
        PopEconomy { total_wealth:200, spending_rate:1.0, consumption:Default::default(), production_commodity:None, production_amount:0.0 },
        PopSentiment { overall_sentiment:10, unrest:0, food_satisfaction:10, safety_satisfaction:50, entertainment_satisfaction:50, dirty:false })).id();
    f.store.population_by_id.insert("workers".into(), pop);
    let before = MoneySnapshot::capture(&mut f.world, &f.store.contracts).total;
    let id = f.store.contracts.post_delivery_for("workers".into(), None, Commodity::Food, 10,
        "source".into(), "port".into(), 120, 0, 1000);
    f.world.get_mut::<PopEconomy>(pop).unwrap().total_wealth -= 120;
    f.store.contracts.register_prepaid(&id, FundingSource::Population);
    let request = f.submit(ship, ShipTransaction::Accept { contract_id:id.clone() }); f.apply(ship, request);
    assert_eq!(f.result(ship), Ok(()));
    f.world.get_mut::<ShipEconomy>(ship).unwrap().transaction.pending = None;
    f.world.get_mut::<ShipCargo>(ship).unwrap().cargo.insert(Commodity::Food,10);
    let request = f.submit(ship, ShipTransaction::Deliver { contract_id:id.clone() }); f.apply(ship, request);
    assert_eq!(f.result(ship), Ok(()));
    assert_eq!(f.world.get::<ShipCargo>(ship).unwrap().used(),0);
    assert_eq!(f.world.get::<MarketPricing>(f.market).unwrap().supply.get(&Commodity::Food).copied().unwrap_or(0.0),0.0);
    assert_eq!(f.world.get::<PopEconomy>(pop).unwrap().total_wealth,80);
    assert_eq!(f.world.get::<ShipEconomy>(ship).unwrap().credits,1120);
    assert_eq!(MoneySnapshot::capture(&mut f.world, &f.store.contracts).total,before);
    assert_eq!(f.events.iter().filter(|e| e["kind"] == "household_delivery_consumed").count(),1);
    f.apply(ship, request);
    assert_eq!(f.events.iter().filter(|e| e["kind"] == "household_delivery_consumed").count(),1);
}

#[tokio::test]
async fn workforce_payroll_and_receipt_survive_actual_sqlite_checkpoint() {
    use sim_core::agents::{facility::{FacilityCrew,workforce::pay_shift},population::*};
    use sim_db::persistence::PersistenceWorker;
    let pool=sim_db::pool::create_pool("sqlite::memory:").await.unwrap();
    sim_db::pool::run_migrations(&pool).await.unwrap();
    for sql in [
        "INSERT INTO star_systems (id,name) VALUES (1,'sol')",
        "INSERT INTO celestial_bodies (id,body_id,name,body_type,orbit_radius,orbit_period,current_angle,star_system_id) VALUES (1,'earth','Earth','planet',1,100,0,1)",
        "INSERT INTO locations (id,name,loc_type,celestial_body_id) VALUES (1,'port','station',1)",
        "INSERT INTO facilities (id,name,facility_type,location_id,location_name,credits) VALUES (1,'Station','farm',1,'port',100)",
        "INSERT INTO populations (id,label,demographic,facility_id,facility_location,population_count,total_wealth) VALUES (1,'Workers','workers',1,'port',10,0)",
    ] { sqlx::query(sql).execute(&pool).await.unwrap(); }
    let mut world=World::new();
    let registry=sim_core::world::registry::WorldRegistry::default();
    let config=sim_core::simulation::config::TickConfig::DEFAULT;
    let mut store=sim_db::spawner::load_agents(&mut world,&pool,&registry,&config).await.unwrap();
    let facility=*store.facility_by_id.values().next().unwrap();
    let people=*store.population_by_id.values().next().unwrap();
    let before=sim_core::economy::money::MoneySnapshot::capture(&mut world,&store.contracts).total;
    pay_shift(&mut world,facility,facility,5,None).unwrap();
    assert_eq!(world.get::<PopEconomy>(people).unwrap().total_wealth,6);
    let (tx,rx)=tokio::sync::mpsc::channel(4);
    let (flush_tx,flush_rx)=tokio::sync::mpsc::channel(1);
    super::super::persist::emit_persist_writes(&mut world,&mut store,5,&tx);
    drop(tx); drop(flush_tx);
    PersistenceWorker::new(pool.clone(),rx,flush_rx,std::time::Duration::from_secs(1)).run().await;
    let mut restored=World::new();
    let store=sim_db::spawner::load_agents(&mut restored,&pool,&registry,&config).await.unwrap();
    let facility=*store.facility_by_id.values().next().unwrap();
    let people=*store.population_by_id.values().next().unwrap();
    assert_eq!(restored.get::<FacilityOperations>(facility).unwrap().credits,94);
    assert_eq!(restored.get::<PopEconomy>(people).unwrap().total_wealth,6);
    assert_eq!(restored.get::<PopDemographics>(people).unwrap().employed_fraction,1.0);
    assert_eq!(restored.get::<FacilityCrew>(facility).unwrap().work_shift.as_ref().unwrap().tick,5);
    assert_eq!(pay_shift(&mut restored,facility,facility,5,None).unwrap_err(),"already_worked_this_tick");
    assert_eq!(sim_core::economy::money::MoneySnapshot::capture(&mut restored,&store.contracts).total,before);
    pool.close().await;
}
