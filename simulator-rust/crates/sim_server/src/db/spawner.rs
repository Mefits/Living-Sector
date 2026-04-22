//! Load world state from SQLite into a hecs-backed AgentStore.

use anyhow::Result;
use sim_core::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit, BodyResources},
        facility::{FacilityIdentity, FacilityLocation, FacilityOperations, FacilityStorage},
        faction::{FactionColors, FactionData},
        market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing},
        population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment},
        ship::{
            ShipAI, ShipCargo, ShipCrew, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle,
            ShipMemory, ShipPosition, ShipTransit, Transit,
        },
    },
    ai::personality::Personality,
    economy::commodities::{Cargo, Commodity, PriceKnowledge},
    simulation::{config::TickConfig, spawner::AgentStore},
    world::registry::{LocationInfo, Route, SystemInfo, WorldRegistry},
};
use sqlx::{Row, SqlitePool};
use std::collections::HashMap;
use tracing::info;

/// Load the world registry (topology, routes, factions) from DB.
pub async fn load_registry(pool: &SqlitePool) -> Result<WorldRegistry> {
    let mut registry = WorldRegistry::default();

    // Systems
    let rows = sqlx::query("SELECT id, name, universe_offset_x, universe_offset_y FROM star_systems")
        .fetch_all(pool).await?;
    for r in rows {
        let id: i64 = r.get("id");
        let name: String = r.get("name");
        let ox: f64 = r.get("universe_offset_x");
        let oy: f64 = r.get("universe_offset_y");
        registry.systems.insert(
            name.clone(),
            SystemInfo { db_id: id, name, universe_offset: (ox as f32, oy as f32) },
        );
    }

    // Locations
    let rows = sqlx::query("SELECT id, name, loc_type, celestial_body_id FROM locations")
        .fetch_all(pool).await?;
    for r in rows {
        let id: i64 = r.get("id");
        let name: String = r.get("name");
        let loc_type: String = r.get("loc_type");
        let body_id: i64 = r.get("celestial_body_id");
        registry.locations.insert(
            name.clone(),
            LocationInfo { db_id: id, name, loc_type, celestial_body_id: body_id },
        );
    }

    // Travel routes
    let rows = sqlx::query("SELECT from_location, to_location, distance FROM travel_routes")
        .fetch_all(pool).await?;
    for r in rows {
        let from: String = r.get("from_location");
        let to: String = r.get("to_location");
        let dist: i64 = r.get("distance");
        registry.routes.entry(from).or_default().push(Route { to, distance: dist as u32 });
    }

    // Faction ids
    let rows = sqlx::query("SELECT id FROM factions").fetch_all(pool).await?;
    registry.faction_ids = rows.into_iter().map(|r| r.get("id")).collect();

    Ok(registry)
}

/// Load all agents from DB into a hecs-backed AgentStore.
pub async fn load_agents(
    pool: &SqlitePool,
    registry: &WorldRegistry,
    tick_config: &TickConfig,
) -> Result<AgentStore> {
    let mut store = AgentStore::new();

    load_bodies(pool, registry, &mut store).await?;
    load_factions(pool, &mut store).await?;
    load_facilities(pool, &mut store).await?;
    load_markets(pool, tick_config, &mut store).await?;
    load_populations(pool, &mut store).await?;
    load_ships(pool, registry, tick_config, &mut store).await?;

    seed_ship_price_knowledge(&mut store);

    // Build the gate location-pair lookup used by the pathfinder. Done
    // once at load time; admin spawn/remove of gates triggers a rebuild.
    store.rebuild_gate_pairs();
    info!("Spawner: {}", store.summary());
    Ok(store)
}

/// Bootstrap every ship's `price_knowledge` with a snapshot of every market's
/// current prices. Models "captains know the rough price patterns around the
/// sector even before visiting" — without this ships have no basis for
/// picking a trade_run goal until they've visited multiple markets.
fn seed_ship_price_knowledge(store: &mut AgentStore) {
    use sim_core::agents::market::{MarketIdentity, MarketPricing};
    use sim_core::agents::ship::ShipMemory;
    use sim_core::economy::commodities::PriceMemory;

    // Collect a location → commodity → price snapshot.
    let mut snapshot: HashMap<String, HashMap<sim_core::economy::commodities::Commodity, f32>> =
        HashMap::new();
    for (_e, (id, pricing)) in store
        .world
        .query::<(&MarketIdentity, &MarketPricing)>()
        .iter()
    {
        snapshot.insert(id.facility_location.clone(), pricing.prices.clone());
    }

    for (_e, memory) in store.world.query_mut::<&mut ShipMemory>() {
        if !memory.price_knowledge.is_empty() {
            continue;
        }
        for (loc, prices) in &snapshot {
            let entry = memory.price_knowledge.entry(loc.clone()).or_default();
            for (&commodity, &price) in prices {
                entry.insert(commodity, PriceMemory { price, tick: 0 });
            }
        }
    }
}

async fn load_bodies(
    pool: &SqlitePool,
    registry: &WorldRegistry,
    store: &mut AgentStore,
) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, body_id, name, body_type, orbit_radius, orbit_period,
                current_angle, resources, star_system_id
         FROM celestial_bodies",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let id: i64 = r.get("id");
        let body_id: String = r.get("body_id");
        let name: String = r.get("name");
        let body_type: String = r.get("body_type");
        let orbit_radius: f64 = r.get("orbit_radius");
        let orbit_period: i64 = r.get("orbit_period");
        let current_angle: f64 = r.get("current_angle");
        let resources_json: String = r.get("resources");
        let biome: String = r.try_get("biome").unwrap_or_default();
        let system_id: i64 = r.get("star_system_id");

        let system_name = registry
            .systems
            .values()
            .find(|s| s.db_id == system_id)
            .map(|s| s.name.clone())
            .unwrap_or_default();
        let universe_offset = registry
            .systems
            .get(&system_name)
            .map(|s| s.universe_offset)
            .unwrap_or((0.0, 0.0));

        let resources = parse_commodity_f32_map(&resources_json);
        // Seed max_resources = starting resources. Mining decrements
        // `resources`; the regen phase ramps back toward these caps.
        let max_resources = resources.clone();

        let entity = store.world.spawn((
            BodyIdentity {
                db_id: id,
                body_id: body_id.clone(),
                name,
                body_type,
                star_system_id: system_id,
                system_name,
            },
            BodyOrbit {
                orbit_radius: orbit_radius as f32,
                orbit_period: orbit_period as u32,
                current_angle: current_angle as f32,
                universe_offset,
                dirty: false,
            },
            BodyResources {
                resources,
                max_resources,
            },
            sim_core::agents::celestial_body::BodyBiome::new(biome),
        ));
        store.index_body(body_id, entity);
    }
    Ok(())
}

async fn load_factions(pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, name, faction_type, home_system, treasury, personality, colors FROM factions",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let id: String = r.get("id");
        let name: String = r.get("name");
        let faction_type: String = r.get("faction_type");
        let home_system: String = r.get("home_system");
        let treasury: i64 = r.get("treasury");
        let personality_json: String = r.get("personality");
        let colors_json: String = r.get("colors");

        let personality = serde_json::from_str::<Personality>(&personality_json)
            .unwrap_or_else(|_| Personality::balanced_trader());
        let colors_val: serde_json::Value =
            serde_json::from_str(&colors_json).unwrap_or_default();
        let primary = colors_val
            .get("primary")
            .and_then(|v| v.as_str())
            .unwrap_or("#888")
            .to_string();
        let secondary = colors_val
            .get("secondary")
            .and_then(|v| v.as_str())
            .unwrap_or("#444")
            .to_string();

        let entity = store.world.spawn((FactionData {
            id: id.clone(),
            name,
            faction_type,
            home_system,
            treasury,
            personality,
            colors: FactionColors { primary, secondary },
            active_subsidies: 0,
            dirty: false,
        },));
        store.index_faction(id, entity);
    }
    Ok(())
}

async fn load_facilities(pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, name, facility_type, location_id, location_name, body_id, faction_id,
                docking_capacity, services, condition, reputation, credits, reserves, docked_ships,
                gate_paired_id
         FROM facilities",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let db_id: i64 = r.get("id");
        let name: String = r.get("name");
        let facility_type: String = r.get("facility_type");
        let location_id: i64 = r.get("location_id");
        let location_name: String = r.get("location_name");
        let body_id: String = r.get("body_id");
        let faction_id: String = r.get("faction_id");
        let docking_capacity: i64 = r.get("docking_capacity");
        let services_json: String = r.get("services");
        let condition: f64 = r.get("condition");
        let reputation: i64 = r.get("reputation");
        let credits: i64 = r.get("credits");
        let reserves_json: String = r.get("reserves");
        let gate_paired_id: Option<String> = r.try_get("gate_paired_id").ok();

        // Include facility name-slug so multi-facility locations (earth-station
        // has a station + a farm) get distinct agent ids.
        let name_slug = name
            .to_lowercase()
            .replace(|c: char| !c.is_alphanumeric(), "-")
            .trim_matches('-')
            .to_string();
        let id = format!("facility-{}-{}", location_name, name_slug);
        let services: Vec<String> = serde_json::from_str(&services_json).unwrap_or_default();
        let reserves = parse_commodity_f32_map(&reserves_json);

        // docked_ships column holds DB ids (pre-migration state). Start empty at boot;
        // active docking relationships are repopulated by ship tick phases.
        let _ = r.try_get::<String, _>("docked_ships").unwrap_or_default();

        let is_gate = facility_type == "gate";
        let entity = store.world.spawn((
            FacilityIdentity {
                db_id,
                id: id.clone(),
                name,
                facility_type,
                faction_id,
                body_id,
            },
            FacilityLocation {
                location_id,
                location_name: location_name.clone(),
            },
            FacilityOperations {
                docking_capacity: docking_capacity as u32,
                services,
                condition: condition as f32,
                reputation: reputation as i32,
                credits,
                dirty: false,
            },
            FacilityStorage {
                reserves,
                docked_ships: vec![],
                pending_deliveries: vec![],
            },
            sim_core::agents::facility::FacilityLifecycle::new(),
            sim_core::simulation::lod::AgentLod::new(),
        ));
        // Attach GateLink for gate facilities. Pairing is symmetric but
        // we validate only existence here; the pathfinder will resolve
        // the paired entity at lookup time.
        if is_gate {
            if let Some(paired) = gate_paired_id.filter(|s| !s.is_empty()) {
                use sim_core::agents::facility::{
                    GateLink, DEFAULT_GATE_FEE_FLAT, DEFAULT_GATE_FEE_PER_CARGO,
                    DEFAULT_GATE_THROUGHPUT,
                };
                store
                    .world
                    .insert_one(
                        entity,
                        GateLink {
                            paired_gate_id: paired,
                            fee_flat: DEFAULT_GATE_FEE_FLAT,
                            fee_per_cargo_unit: DEFAULT_GATE_FEE_PER_CARGO,
                            throughput_cap: DEFAULT_GATE_THROUGHPUT,
                        },
                    )
                    .ok();
            }
        }
        store.index_facility(id, location_name, entity);
    }
    Ok(())
}

async fn load_markets(pool: &SqlitePool, _config: &TickConfig, store: &mut AgentStore) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, facility_id, facility_location, price_elasticity, spread,
                prices, supply, demand, production, consumption,
                shortage_ticks, trade_volume
         FROM markets",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let db_id: i64 = r.get("id");
        let facility_db_id: i64 = r.get("facility_id");
        let facility_location: String = r.get("facility_location");
        let price_elasticity: f64 = r.get("price_elasticity");
        let spread: f64 = r.get("spread");
        let prices_json: String = r.get("prices");
        let supply_json: String = r.get("supply");
        let demand_json: String = r.get("demand");
        let production_json: String = r.get("production");
        let consumption_json: String = r.get("consumption");
        let shortage_json: String = r.get("shortage_ticks");
        let volume_json: String = r.get("trade_volume");

        // Resolve the facility hecs::Entity by DB id
        let facility_entity = facility_entity_by_db_id(store, facility_db_id)
            .ok_or_else(|| anyhow::anyhow!("market {db_id} references missing facility db_id={facility_db_id}"))?;

        let id = format!("market-{}", facility_location);
        let entity = store.world.spawn((
            MarketIdentity {
                db_id,
                id: id.clone(),
                facility: facility_entity,
                facility_location: facility_location.clone(),
            },
            MarketPricing {
                price_elasticity: price_elasticity as f32,
                spread: spread as f32,
                prices: parse_commodity_f32_map(&prices_json),
                supply: parse_commodity_f32_map(&supply_json),
                demand: parse_commodity_f32_map(&demand_json),
            },
            MarketFlow {
                production: parse_commodity_f32_map(&production_json),
                consumption: parse_commodity_f32_map(&consumption_json),
                consumption_window: Default::default(),
                seed_demand: parse_commodity_f32_map(&demand_json),
            },
            MarketOrders {
                pending_buys: vec![],
                pending_sells: vec![],
                reserved: Default::default(),
                next_order_id: 0,
                next_reserve_id: 0,
                // base expiry is 50 ticks × tick_multiplier (32) = 1600 ticks.
                order_expiry_ticks: 50 * _config.tick_multiplier() as u64,
            },
            MarketHistory {
                price_history: Default::default(),
                trade_volume: parse_commodity_f32_map(&volume_json),
                shortage_ticks: parse_commodity_u32_map(&shortage_json),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
            },
        ));
        store.index_market(id, facility_location, entity);
    }
    Ok(())
}

async fn load_populations(pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, label, demographic, facility_id, facility_location, faction_id,
                population_count, overall_sentiment, unrest, total_wealth, food_satisfaction,
                consumption, production_commodity, production_amount,
                employed_fraction, spending_rate, growth_rate, migration_pressure,
                safety_satisfaction, entertainment_satisfaction
         FROM populations",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let db_id: i64 = r.get("id");
        let label: String = r.get("label");
        let demographic: String = r.get("demographic");
        let facility_db_id: i64 = r.get("facility_id");
        let facility_location: String = r.get("facility_location");
        let faction_id: String = r.get("faction_id");
        let population_count: i64 = r.get("population_count");
        let overall_sentiment: i64 = r.get("overall_sentiment");
        let unrest: i64 = r.get("unrest");
        let total_wealth: i64 = r.get("total_wealth");
        let food_satisfaction: i64 = r.get("food_satisfaction");
        let consumption_json: String = r.get("consumption");
        let prod_commodity: Option<String> = r.get("production_commodity");
        let prod_amount: f64 = r.get("production_amount");
        let employed: f64 = r.get("employed_fraction");
        let spending: f64 = r.get("spending_rate");
        let growth: f64 = r.get("growth_rate");
        let migration: f64 = r.get("migration_pressure");
        let safety_sat: i64 = r.get("safety_satisfaction");
        let ent_sat: i64 = r.get("entertainment_satisfaction");

        let facility_entity = facility_entity_by_db_id(store, facility_db_id)
            .ok_or_else(|| anyhow::anyhow!("population {db_id} references missing facility db_id={facility_db_id}"))?;

        let id = format!("pop-{}", label.to_lowercase().replace(' ', "-"));
        let production_commodity = prod_commodity.as_deref().and_then(Commodity::parse);

        let entity = store.world.spawn((
            PopIdentity {
                db_id,
                id: id.clone(),
                label,
                demographic,
                facility: facility_entity,
                facility_location,
                faction_id,
            },
            PopDemographics {
                population_count,
                growth_rate: growth as f32,
                employed_fraction: employed as f32,
                migration_pressure: migration as f32,
            },
            PopEconomy {
                total_wealth,
                spending_rate: spending as f32,
                consumption: parse_commodity_f32_map(&consumption_json),
                production_commodity,
                production_amount: prod_amount as f32,
            },
            PopSentiment {
                overall_sentiment: overall_sentiment as i32,
                unrest: unrest as i32,
                food_satisfaction: food_satisfaction as i32,
                safety_satisfaction: safety_sat as i32,
                entertainment_satisfaction: ent_sat as i32,
                dirty: false,
            },
            sim_core::simulation::lod::AgentLod::new(),
        ));
        store.index_population(id, entity);
    }
    Ok(())
}

async fn load_ships(
    pool: &SqlitePool,
    registry: &WorldRegistry,
    _config: &TickConfig,
    store: &mut AgentStore,
) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, name, class, location_name, system_id,
                universe_offset_x, universe_offset_y, position_x, position_y,
                cargo_capacity, fuel, fuel_capacity, fuel_consumption_rate, speed_modifier,
                credits, efficiency, faction_id, faction_reputation, personality,
                cargo, cargo_age,
                docked_at, transit_from, transit_to, transit_departure_tick, transit_arrival_tick,
                current_goal, broke_strikes, hoard_strikes, idle_ticks,
                active_contract_id, price_knowledge, visited
         FROM ships",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let db_id: i64 = r.get("id");
        let name: String = r.get("name");
        let class: String = r.get("class");
        let location_name: String = r.get("location_name");
        let system_id: String = r.get("system_id");
        let ox: f64 = r.get("universe_offset_x");
        let oy: f64 = r.get("universe_offset_y");
        let px: f64 = r.get("position_x");
        let py: f64 = r.get("position_y");
        let cargo_capacity: i64 = r.get("cargo_capacity");
        let fuel: f64 = r.get("fuel");
        let fuel_capacity: f64 = r.get("fuel_capacity");
        let fuel_consumption_rate: f64 = r.get("fuel_consumption_rate");
        let speed_modifier: f64 = r.get("speed_modifier");
        let credits: i64 = r.get("credits");
        let efficiency: f64 = r.get("efficiency");
        let faction_id: String = r.get("faction_id");
        let rep_json: String = r.get("faction_reputation");
        let personality_json: String = r.get("personality");
        let cargo_json: String = r.get("cargo");
        let cargo_age_json: String = r.get("cargo_age");
        let docked_at: Option<i64> = r.get("docked_at");
        let transit_from: Option<String> = r.get("transit_from");
        let transit_to: Option<String> = r.get("transit_to");
        let transit_dep: Option<i64> = r.get("transit_departure_tick");
        let transit_arr: Option<i64> = r.get("transit_arrival_tick");
        let current_goal: String = r.get("current_goal");
        let broke_strikes: i64 = r.get("broke_strikes");
        let hoard_strikes: i64 = r.get("hoard_strikes");
        let idle_ticks: i64 = r.get("idle_ticks");
        let active_contract_id: Option<String> = r.get("active_contract_id");
        let price_knowledge_json: String = r.get("price_knowledge");
        let visited_json: String = r.get("visited");

        let id = format!(
            "ship-{}",
            name.to_lowercase()
                .replace(' ', "-")
                .replace(|c: char| !c.is_alphanumeric() && c != '-', "")
        );

        let personality = serde_json::from_str::<Personality>(&personality_json)
            .unwrap_or_else(|_| {
                let mut rng = rand::thread_rng();
                Personality::random_ship(&mut rng)
            });

        let faction_reputation: HashMap<String, u8> = {
            let v: serde_json::Value = serde_json::from_str(&rep_json).unwrap_or_default();
            v.as_object()
                .map(|m| {
                    m.iter()
                        .filter_map(|(k, v)| Some((k.clone(), v.as_u64()? as u8)))
                        .collect()
                })
                .unwrap_or_default()
        };
        let faction_reputation = if faction_reputation.is_empty() {
            registry
                .faction_ids
                .iter()
                .map(|fid| {
                    let rep = if fid == &faction_id { 70 } else { 30 };
                    (fid.clone(), rep)
                })
                .collect()
        } else {
            faction_reputation
        };

        let cargo: Cargo = parse_cargo(&cargo_json);
        let cargo_age: HashMap<Commodity, u64> = parse_commodity_u64_map(&cargo_age_json);

        let transit = match (transit_from, transit_to, transit_dep, transit_arr) {
            (Some(from), Some(to), Some(dep), Some(arr)) => Some(Transit {
                from,
                to,
                departure_tick: dep as u64,
                arrival_tick: arr as u64,
                // Legacy rows don't carry distance fields — advance_transits
                // reseeds them from the route registry on first tick.
                departure_position: None,
                distance_total: 0.0,
                distance_travelled: 0.0,
            }),
            _ => None,
        };

        let visited: Vec<String> = serde_json::from_str(&visited_json).unwrap_or_default();
        let price_knowledge: PriceKnowledge =
            serde_json::from_str(&price_knowledge_json).unwrap_or_default();

        // Resolve docked-at facility entity from DB id, if any
        let docked_at_entity = docked_at.and_then(|fid| facility_entity_by_db_id(store, fid));

        // Seed ships don't have persisted `position_x/y` — they come out of
        // the DB as (0,0), which puts every ship at the universe origin
        // regardless of system. Resolve an initial position from the
        // ship's `location_name` via the body that location orbits. Falls
        // back to (0,0) only if the location or body can't be found.
        let (init_px, init_py) = if px.abs() < f64::EPSILON && py.abs() < f64::EPSILON {
            resolve_location_world_pos(store, registry, &location_name)
                .map(|(x, y)| (x as f64, y as f64))
                .unwrap_or((px, py))
        } else {
            (px, py)
        };

        let entity = store.world.spawn((
            ShipIdentity {
                db_id,
                id: id.clone(),
                name,
                class: class.clone(),
                faction_id,
            },
            ShipPosition {
                location_name: if location_name.is_empty() {
                    None
                } else {
                    Some(location_name)
                },
                docked_at: docked_at_entity,
                system_id,
                universe_offset: (ox as f32, oy as f32),
                position: (init_px as f32, init_py as f32),
            },
            ShipTransit { transit },
            ShipCargo {
                cargo,
                capacity: cargo_capacity as u32,
                cargo_age,
            },
            ShipFuel {
                fuel: fuel as f32,
                fuel_capacity: fuel_capacity as f32,
                fuel_consumption_rate: fuel_consumption_rate as f32,
                speed_modifier: speed_modifier as f32,
            },
            ShipEconomy {
                credits,
                efficiency: efficiency as f32,
                active_contract_id,
                faction_reputation,
                dock_dwell_start_tick: None,
            },
            ShipAI {
                personality,
                current_goal,
                current_bt: None,
            },
            ShipMemory {
                price_knowledge,
                visited,
            },
            ShipLifecycle {
                broke_strikes: broke_strikes as u8,
                hoard_strikes: hoard_strikes as u8,
                idle_ticks: idle_ticks as u32,
                dirty: false,
            },
        ));
        // Crew from class. Seed from Elixir CrewComplement defaults:
        // morale=70, fatigue=10, hunger=10, health=100, idle task, no wages yet.
        let ship_class = sim_core::simulation::config::ship_class(&class);
        let crew_size = ship_class.map(|c| c.crew_size).unwrap_or(5);
        let crew_roles = ship_class.map(|c| c.crew_roles).unwrap_or(&[]);
        store.world.insert_one(
            entity,
            ShipCrew {
                size: crew_size,
                hunger: 10.0,
                morale: 70.0,
                fatigue: 10.0,
                health: 100.0,
                wages_credits: 0,
                current_task: sim_core::agents::ship::CrewTask::Idle,
                dirty: false,
            },
        ).ok();
        store.world.insert_one(
            entity,
            sim_core::agents::ship::ShipCrewSkills::for_roles(crew_roles),
        ).ok();
        // Attach LOD cursor — defaults to divisor 1 so new ships run at
        // full cadence until the next `tick_lod_recompute` pass.
        store.world.insert_one(
            entity,
            sim_core::simulation::lod::AgentLod::new(),
        ).ok();
        store.index_ship(id, entity);
    }
    Ok(())
}

// --- Helpers ---

/// Compute the world-space position of a named location by finding the
/// body it orbits and applying the facility offset if a facility sits
/// at that location. Returns `None` if the location is unknown or its
/// body isn't in the ECS yet (bodies must be loaded before ships — which
/// they are, per `load_agents`'s ordering).
fn resolve_location_world_pos(
    store: &AgentStore,
    registry: &WorldRegistry,
    location_name: &str,
) -> Option<(f32, f32)> {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{facility_offset_position, FacilityIdentity, FacilityLocation},
    };
    let loc_info = registry.locations.get(location_name)?;
    let body_db_id = loc_info.celestial_body_id;
    // Find the body by db_id and compute its universe position.
    let body_pos = store
        .world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .find(|(_, (id, _))| id.db_id == body_db_id)
        .map(|(_, (_, orbit))| orbit.universe_position())?;
    // If there's a facility at this location, use its offset so the ship
    // starts at the dock rather than the body center.
    let fac_id = store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .find(|(_, (_, loc))| loc.location_name == location_name)
        .map(|(_, (id, _))| id.id.clone());
    Some(if let Some(id) = fac_id {
        facility_offset_position(body_pos, &id)
    } else {
        body_pos
    })
}

fn facility_entity_by_db_id(store: &AgentStore, db_id: i64) -> Option<hecs::Entity> {
    // Look up by iterating the world; we only do this during initial spawn so cost is O(N_facilities)
    // and only runs once. After startup, agents reference facilities by hecs::Entity directly.
    for (e, id) in store.world.query::<&FacilityIdentity>().iter() {
        if id.db_id == db_id {
            return Some(e);
        }
    }
    None
}

fn parse_commodity_f32_map(json: &str) -> HashMap<Commodity, f32> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    v.as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| Some((Commodity::parse(k)?, v.as_f64()? as f32)))
                .collect()
        })
        .unwrap_or_default()
}

fn parse_commodity_u32_map(json: &str) -> HashMap<Commodity, u32> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    v.as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| Some((Commodity::parse(k)?, v.as_u64()? as u32)))
                .collect()
        })
        .unwrap_or_default()
}

fn parse_commodity_u64_map(json: &str) -> HashMap<Commodity, u64> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    v.as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| Some((Commodity::parse(k)?, v.as_u64()?)))
                .collect()
        })
        .unwrap_or_default()
}

fn parse_cargo(json: &str) -> Cargo {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    v.as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| Some((Commodity::parse(k)?, v.as_u64()? as u32)))
                .collect()
        })
        .unwrap_or_default()
}
