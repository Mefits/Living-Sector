use super::*;
use crate::agents::faction_relations::TreatyKind;

fn facility(world: &mut World, name: &str, credits: i64, fuel: f32) -> Entity {
    world
        .spawn((
            FacilityIdentity {
                db_id: 1,
                id: name.into(),
                name: name.into(),
                facility_type: "refinery".into(),
                faction_id: name.into(),
                body_id: "earth".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "port".into(),
            },
            FacilityOperations {
                docking_capacity: 2,
                services: vec![],
                condition: 1.0,
                reputation: 0,
                credits,
                dirty: false,
                starving_notified: false,
            },
            FacilityStorage {
                reserves: [(Commodity::Fuel, fuel)].into(),
                ..Default::default()
            },
            FacilityLifecycle::new(),
        ))
        .id()
}

#[test]
fn supply_flow_requests_real_recipe_inputs() {
    assert_eq!(
        recipe_input_commodities("refinery"),
        vec![
            Commodity::Ore,
            Commodity::Fuel,
            Commodity::Ice,
            Commodity::Gas
        ]
    );
    assert_eq!(
        recipe_input_commodities("factory"),
        vec![
            Commodity::Metals,
            Commodity::Polymers,
            Commodity::Components,
            Commodity::Water
        ]
    );
    assert_eq!(recipe_input_commodities("farm"), vec![Commodity::Water]);
    assert!(recipe_input_commodities("mining_rig").is_empty());
}

#[test]
fn supply_flow_restock_conserves_goods_and_money_and_respects_access() {
    for case in [
        "purchase",
        "own_stock",
        "war",
        "overflow",
        "no_money",
        "missing_owner",
        "invalid_price",
    ] {
        let mut world = World::new();
        let own = case == "own_stock";
        let seller = facility(
            &mut world,
            "seller",
            if case == "overflow" { i64::MAX } else { 0 },
            if own { 0.0 } else { 100.0 },
        );
        let buyer = if own {
            seller
        } else {
            facility(
                &mut world,
                "buyer",
                if case == "no_money" { 0 } else { 21 },
                0.0,
            )
        };
        let market = world
            .spawn((
                MarketIdentity {
                    db_id: 2,
                    id: "market".into(),
                    facility: seller,
                    facility_location: "port".into(),
                },
                MarketPricing {
                    price_elasticity: 1.0,
                    spread: 0.0,
                    prices: if own {
                        Default::default()
                    } else {
                        [(
                            Commodity::Fuel,
                            if case == "invalid_price" {
                                f32::NAN
                            } else {
                                10.5
                            },
                        )]
                        .into()
                    },
                    supply: [(Commodity::Fuel, 2.5)].into(),
                    demand: Default::default(),
                },
                MarketHistory::default(),
            ))
            .id();
        let mut relations = FactionRelations::new();
        if case == "war" {
            relations.set_treaty("buyer", "seller", TreatyKind::War, 0);
        }
        if case == "missing_owner" {
            world.entity_mut(seller).remove::<FacilityOperations>();
        }
        let initial_buyer = world.get::<FacilityOperations>(buyer).map(|o| o.credits);
        tick_restock(&mut world, &relations);
        let transferred = if case == "purchase" || own { 2.0 } else { 0.0 };
        assert_eq!(
            world.get::<MarketPricing>(market).unwrap().supply[&Commodity::Fuel],
            2.5 - transferred,
            "{case}"
        );
        assert_eq!(
            world.get::<FacilityStorage>(buyer).unwrap().reserves[&Commodity::Fuel],
            transferred,
            "{case}"
        );
        if case == "purchase" {
            assert_eq!(world.get::<FacilityOperations>(buyer).unwrap().credits, 0);
            assert_eq!(world.get::<FacilityOperations>(seller).unwrap().credits, 21);
            assert!(world.get::<FacilityOperations>(seller).unwrap().dirty);
        } else {
            assert_eq!(
                world.get::<FacilityOperations>(buyer).map(|o| o.credits),
                initial_buyer,
                "{case}"
            );
        }
        assert_eq!(
            world.get::<MarketHistory>(market).unwrap().dirty,
            transferred > 0.0,
            "{case}"
        );
    }
}

#[test]
fn household_food_and_water_stay_on_market_instead_of_idle_service_reserves() {
    let mut world = World::new();
    let owner = facility(&mut world, "owner", 5000, 100.0);
    let market = world.spawn((
        MarketIdentity {
            db_id: 2,
            id: "market-port".into(),
            facility: owner,
            facility_location: "port".into(),
        },
        MarketPricing {
            price_elasticity: 1.0,
            spread: 0.0,
            prices: [(Commodity::Food, 18.0), (Commodity::Water, 12.0)].into(),
            supply: [(Commodity::Food, 1000.0), (Commodity::Water, 1000.0)].into(),
            demand: Default::default(),
        },
        MarketHistory::default(),
    )).id();

    // F2 workers are real residents buying from the market, not a second
    // food-consuming population stored in FacilityStorage.
    tick_restock(&mut world, &FactionRelations::new());

    let pricing = world.get::<MarketPricing>(market).unwrap();
    assert_eq!(pricing.supply[&Commodity::Food], 1000.0);
    assert_eq!(pricing.supply[&Commodity::Water], 1000.0);
    let reserves = &world.get::<FacilityStorage>(owner).unwrap().reserves;
    assert_eq!(reserves.get(&Commodity::Food).copied().unwrap_or(0.0), 0.0);
    assert_eq!(reserves.get(&Commodity::Water).copied().unwrap_or(0.0), 0.0);
    assert_eq!(world.get::<FacilityOperations>(owner).unwrap().credits, 5000);
    assert!(!world.get::<MarketHistory>(market).unwrap().dirty);
}
