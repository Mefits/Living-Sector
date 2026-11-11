//! Connect native construction sites to docking, population and persistence.
use bevy_ecs::prelude::{Entity, World};
use sim_core::{
    agents::{
        construction::ConstructionSite,
        facility::{
            FacilityCrew, FacilityFitting, FacilityIdentity, FacilityLifecycle, FacilityLocation,
            FacilityOperations, FacilityOrbit, FacilityStorage,
        },
        faction::FactionData,
        market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing},
        population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment},
    },
    economy::commodities::Commodity,
    simulation::{lod::AgentLod, spawner::AgentStore},
    strategy::{colony::DOCK_TYPE, construction::STARTUP_CAPITAL},
    world::registry::WorldRegistry,
};
use sim_db::persistence::{ConstructedFacilityRow, DbWrite};

pub(super) fn prepare_docks(
    world: &mut World,
    store: &mut AgentStore,
    registry: &WorldRegistry,
    events: &mut Vec<serde_json::Value>,
) {
    let sites: Vec<_> = world
        .query::<&ConstructionSite>()
        .iter(world)
        .filter(|s| {
            s.labor.colony_source.is_some()
                && !s.completed
                && !store.facilities_at_location.contains_key(&s.location_name)
        })
        .cloned()
        .collect();
    for site in sites {
        let Some(location) = registry.locations.get(&site.location_name) else {
            continue;
        };
        let db_id = super::drains::next_construction_id(world);
        let name_slug = site
            .name
            .to_lowercase()
            .replace(|c: char| !c.is_alphanumeric(), "-");
        let id = format!("facility-{}-{}", site.location_name, name_slug);
        let dock = world
            .spawn((
                FacilityIdentity {
                    db_id,
                    id: id.clone(),
                    name: site.name.clone(),
                    facility_type: DOCK_TYPE.into(),
                    faction_id: site.faction_id.clone(),
                    body_id: site.body_id.clone(),
                },
                FacilityLocation {
                    location_id: location.db_id,
                    location_name: site.location_name.clone(),
                },
                FacilityOperations {
                    docking_capacity: 4,
                    services: vec![],
                    condition: 1.0,
                    reputation: 50,
                    credits: 0,
                    dirty: true,
                    starving_notified: false,
                },
                FacilityStorage::default(),
                FacilityLifecycle::new(),
                FacilityOrbit::new(&site.location_name, None),
                FacilityFitting::new_default(),
                FacilityCrew::new_for_type(DOCK_TYPE),
                AgentLod::new(),
            ))
            .id();
        store.index_facility(id, site.location_name.clone(), dock);
        super::persist::queue_lifecycle_write(
            world,
            DbWrite::ConstructedFacility {
                row: ConstructedFacilityRow {
                    db_id,
                    source_site_id: site.id.clone(),
                    name: site.name.clone(),
                    facility_type: DOCK_TYPE.into(),
                    faction_id: site.faction_id.clone(),
                    body_id: site.body_id.clone(),
                    location_id: location.db_id,
                    location_name: site.location_name.clone(),
                    docking_capacity: 4,
                    credits: 0,
                    reputation: 50,
                    condition: 1.0,
                },
            },
        );

        let label = format!("Residents {}", site.location_name);
        let id = format!("pop-{}", label.to_lowercase().replace(' ', "-"));
        let household = world
            .spawn((
                PopIdentity {
                    db_id,
                    id: id.clone(),
                    label: label.clone(),
                    demographic: "workers".into(),
                    facility: dock,
                    facility_location: site.location_name.clone(),
                    faction_id: site.faction_id.clone(),
                },
                PopDemographics {
                    population_count: 0,
                    growth_rate: 0.0,
                    employed_fraction: 0.0,
                    migration_pressure: 0.0,
                },
                PopEconomy {
                    total_wealth: 0,
                    spending_rate: 0.02,
                    consumption: [(Commodity::Food, 1.0), (Commodity::Water, 0.6)].into(),
                    production_commodity: None,
                    production_amount: 0.0,
                },
                PopSentiment {
                    overall_sentiment: 50,
                    unrest: 0,
                    food_satisfaction: 50,
                    safety_satisfaction: 50,
                    entertainment_satisfaction: 50,
                    dirty: false,
                },
                AgentLod::new(),
            ))
            .id();
        store.index_population(id, household);
        super::persist::queue_lifecycle_write(
            world,
            DbWrite::ColonyPopulation {
                db_id,
                label,
                location: site.location_name.clone(),
                faction: site.faction_id.clone(),
            },
        );
        events.push(serde_json::json!({"kind":"construction_site_started","site_id":site.id,
            "facility_type":"station","location":site.location_name,"body_id":site.body_id,"required":site.progress_required}));
    }
}

pub(super) fn establish(
    world: &mut World,
    store: &mut AgentStore,
    site: &ConstructionSite,
    events: &mut Vec<serde_json::Value>,
    mult: u32,
) -> Result<Entity, &'static str> {
    let location = &site.location_name;
    let dock = store
        .facilities_at_location
        .get(location)
        .ok_or("missing_colony_dock")?
        .iter()
        .copied()
        .find(|e| {
            world
                .get::<FacilityIdentity>(*e)
                .is_some_and(|i| i.facility_type == DOCK_TYPE && i.faction_id == site.faction_id)
        })
        .ok_or("missing_colony_dock")?;
    let sponsor = *store
        .faction_by_id
        .get(&site.faction_id)
        .ok_or("missing_sponsor")?;
    let credits = world
        .get::<FacilityOperations>(dock)
        .ok_or("missing_colony_dock")?
        .credits
        .checked_add(STARTUP_CAPITAL)
        .ok_or("credit_overflow")?;
    let mut account = world
        .get_mut::<FactionData>(sponsor)
        .ok_or("missing_sponsor")?;
    if account.treasury < STARTUP_CAPITAL {
        return Err("insufficient_startup_capital");
    }
    account.treasury -= STARTUP_CAPITAL;
    account.dirty = true;

    let mut identity = world.get_mut::<FacilityIdentity>(dock).unwrap();
    identity.facility_type = "station".into();
    let db_id = identity.db_id;
    let facility_id = identity.id.clone();
    let mut ops = world.get_mut::<FacilityOperations>(dock).unwrap();
    ops.services.push("market".into());
    ops.credits = credits;
    ops.condition = 1.0;
    ops.dirty = true;
    // Service staffing can draw on the arrived residents when modeled.
    world.get_mut::<FacilityCrew>(dock).unwrap().dirty = true;

    let id = format!("market-{location}");
    let market = world
        .spawn((
            MarketIdentity {
                db_id,
                id: id.clone(),
                facility: dock,
                facility_location: location.clone(),
            },
            MarketPricing {
                price_elasticity: 0.02,
                spread: 0.10,
                prices: Commodity::ALL.iter().map(|c|(*c,c.base_price())).collect(),
                supply: Default::default(),
                demand: [(Commodity::Food,5.0),(Commodity::Water,3.0)].into(),
            },
            MarketFlow {
                production: Default::default(),
                consumption: Default::default(),
                consumption_window: Default::default(),
                seed_demand: [(Commodity::Food,5.0),(Commodity::Water,3.0)].into(),
            },
            MarketOrders {
                order_expiry_ticks: 50 * u64::from(mult),
                ..Default::default()
            },
            MarketHistory {
                dirty: true,
                ..Default::default()
            },
        ))
        .id();
    store.index_market(id, location.clone(), market);
    super::persist::queue_lifecycle_write(
        world,
        DbWrite::ColonyEstablished {
            db_id,
            location: location.clone(),
        },
    );
    super::persist::queue_lifecycle_write(
        world,
        DbWrite::ConstructionSiteDelete {
            agent_id: site.id.clone(),
        },
    );
    events.push(serde_json::json!({"kind":"construction_completed","site_id":site.id,
        "facility_id":facility_id,"facility_type":"station","location":location,"body_id":site.body_id,
        "faction_id":site.faction_id,"startup_capital":STARTUP_CAPITAL,"executor":site.labor.last_executor}));
    Ok(dock)
}
