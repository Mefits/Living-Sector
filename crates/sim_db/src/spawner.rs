//! Load world state from SQLite into a hecs-backed AgentStore.

use anyhow::Result;
use bevy_ecs::prelude::{Entity, World};
use sim_core::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit, BodyResources},
        facility::{FacilityIdentity, FacilityLocation, FacilityOperations, FacilityStorage, FacilityOrbit},
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
    let rows =
        sqlx::query("SELECT id, name, universe_offset_x, universe_offset_y, star_type FROM star_systems")
            .fetch_all(pool)
            .await?;
    for r in rows {
        let id: i64 = r.get("id");
        let name: String = r.get("name");
        let ox: f64 = r.get("universe_offset_x");
        let oy: f64 = r.get("universe_offset_y");
        let star_type: Option<String> = r.try_get("star_type").ok().flatten();
        registry.systems.insert(
            name.clone(),
            SystemInfo {
                db_id: id,
                name,
                universe_offset: (ox as f32, oy as f32),
                star_type,
            },
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
    world: &mut World,
    pool: &SqlitePool,
    registry: &WorldRegistry,
    tick_config: &TickConfig,
) -> Result<AgentStore> {
    let mut store = AgentStore::new();

    load_bodies(world, pool, registry, &mut store).await?;
    load_factions(world, pool, &mut store).await?;
    load_facilities(world, pool, &mut store).await?;
    load_markets(world, pool, tick_config, &mut store).await?;
    // Phase 20d: rehydrate the in-memory trend-sample ring from
    // `market_trend_samples`. Must run AFTER `load_markets` (the
    // markets need to exist in hecs first) but before any tick
    // logic so `tick_one_market`'s "is the latest sample current?"
    // check has the right reference.
    load_market_trend_samples(world, pool, &mut store).await?;
    load_populations(world, pool, &mut store).await?;
    load_ships(world, pool, registry, tick_config, &mut store).await?;
    load_contracts(pool, &mut store).await?;
    load_construction_sites(world, pool, &mut store).await?;

    // Build the gate location-pair lookup used by the pathfinder
    // BEFORE seeding ship price knowledge — tier-3 ships need to know
    // neighbor-system adjacency to populate their starting memory.
    // Admin spawn/remove of gates triggers a rebuild.
    store.rebuild_gate_pairs(world);

    seed_ship_price_knowledge(world, &mut store);

    info!("Spawner: {}", store.summary());
    Ok(store)
}

/// Bootstrap every ship's `price_knowledge` with a snapshot scoped to
/// what its comms tier could plausibly know from its starting location.
///
/// Matches the per-tick [`observe_prices`][ship-observe] radius model:
///   - tier 1 (default): markets on the same celestial body
///   - tier 2: every market in the same star system
///   - tier 3+: system + gate-adjacent neighbor systems
///
/// Ships without a seed location fall back to seeding nothing — they'll
/// learn at their first dock. This matters specifically so that at boot,
/// small tier-1 couriers don't see the full 6-system price chart and get
/// dominated by extreme-margin arbitrage pairs (e.g. $5 ore at a mine
/// vs $45 ore at a consumer), which made the planner pick `trade_run`
/// over every available contract in the outer systems.
///
/// All seeded entries carry `tick: 0` so per-tick `observe_prices` can
/// progressively refresh them with live-tick values as the ship visits.
///
/// [ship-observe]: sim_core::agents::ship::observe_prices
fn seed_ship_price_knowledge(world: &mut World, store: &mut AgentStore) {
    use sim_core::agents::celestial_body::BodyIdentity;
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
    use sim_core::agents::market::{MarketIdentity, MarketPricing};
    use sim_core::agents::ship::{ShipFitting, ShipMemory, ShipPosition};
    use sim_core::economy::commodities::PriceMemory;
    use std::collections::HashSet;

    // location -> commodity -> price
    let mut market_prices: HashMap<String, HashMap<sim_core::economy::commodities::Commodity, f32>> =
        HashMap::new();
    {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing)>();
        for (id, pricing) in q.iter(world) {
            market_prices.insert(id.facility_location.clone(), pricing.prices.clone());
        }
    }

    // location -> body_id
    let loc_to_body: HashMap<String, String> = {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        q.iter(world)
            .map(|(id, loc)| (loc.location_name.clone(), id.body_id.clone()))
            .collect()
    };

    // body_id -> all locations orbiting it
    let mut body_to_locs: HashMap<String, Vec<String>> = HashMap::new();
    for (loc, body) in &loc_to_body {
        body_to_locs.entry(body.clone()).or_default().push(loc.clone());
    }

    // location -> system_name (via body_db_id -> system)
    let body_db_to_system: HashMap<i64, String> = {
        let mut q = world.query::<&BodyIdentity>();
        q.iter(world)
            .map(|id| (id.db_id, id.system_name.clone()))
            .collect()
    };
    // celestial_body_id on WorldRegistry is the DB id; but we only have
    // the FacilityIdentity.body_id *string*. Re-map via a body_name ->
    // db_id pass so we can connect location -> system.
    let body_name_to_db: HashMap<String, i64> = {
        let mut q = world.query::<&BodyIdentity>();
        q.iter(world)
            .map(|id| (id.body_id.clone(), id.db_id))
            .collect()
    };
    let location_to_system: HashMap<String, String> = loc_to_body
        .iter()
        .filter_map(|(loc, body_name)| {
            let db = body_name_to_db.get(body_name)?;
            let sys = body_db_to_system.get(db)?;
            Some((loc.clone(), sys.clone()))
        })
        .collect();

    // system -> locations-in-system
    let mut system_to_locs: HashMap<String, Vec<String>> = HashMap::new();
    for (loc, sys) in &location_to_system {
        system_to_locs.entry(sys.clone()).or_default().push(loc.clone());
    }

    // system -> gate-adjacent neighbor systems
    let mut system_neighbors: HashMap<String, HashSet<String>> = HashMap::new();
    for (a_loc, b_loc) in &store.gate_pairs {
        if let (Some(a_sys), Some(b_sys)) = (
            location_to_system.get(a_loc),
            location_to_system.get(b_loc),
        ) {
            if a_sys != b_sys {
                system_neighbors
                    .entry(a_sys.clone())
                    .or_default()
                    .insert(b_sys.clone());
                system_neighbors
                    .entry(b_sys.clone())
                    .or_default()
                    .insert(a_sys.clone());
            }
        }
    }

    let mut q = world.query::<(&ShipPosition, &ShipFitting, &mut ShipMemory)>();
    for (pos, fitting, mut memory) in q.iter_mut(world) {
        if !memory.price_knowledge.is_empty() {
            continue;
        }
        let Some(loc) = pos.location_name.as_ref() else {
            continue;
        };

        let comms_tier = fitting.slots[sim_core::modules::Slot::Comms.index()]
            .and_then(sim_core::modules::get)
            .map(|m| m.tier)
            .unwrap_or(1);

        let mut visible: HashSet<&str> = HashSet::new();
        visible.insert(loc.as_str());
        if let Some(body) = loc_to_body.get(loc) {
            if let Some(locs) = body_to_locs.get(body) {
                for l in locs {
                    visible.insert(l.as_str());
                }
            }
        }
        if comms_tier >= 2 {
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(locs) = system_to_locs.get(sys) {
                    for l in locs {
                        visible.insert(l.as_str());
                    }
                }
            }
        }
        if comms_tier >= 3 {
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(neighbors) = system_neighbors.get(sys) {
                    for n in neighbors {
                        if let Some(locs) = system_to_locs.get(n) {
                            for l in locs {
                                visible.insert(l.as_str());
                            }
                        }
                    }
                }
            }
        }

        for v_loc in visible {
            if let Some(prices) = market_prices.get(v_loc) {
                let entry = memory.price_knowledge.entry(v_loc.to_string()).or_default();
                for (&commodity, &price) in prices {
                    entry.insert(commodity, PriceMemory { price, tick: 0 });
                }
            }
        }
    }
}

async fn load_bodies(
    world: &mut World,
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

        let entity = world.spawn((
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
        )).id();
        store.index_body(body_id, entity);
    }
    Ok(())
}

async fn load_factions(world: &mut World, pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
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

        let entity = world.spawn((FactionData {
            id: id.clone(),
            name,
            faction_type,
            home_system,
            treasury,
            personality,
            colors: FactionColors { primary, secondary },
            active_subsidies: 0,
            dirty: false,
        },)).id();
        store.index_faction(id, entity);
    }
    Ok(())
}

async fn load_facilities(world: &mut World, pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
    let rows = sqlx::query(
        "SELECT id, name, facility_type, location_id, location_name, body_id, faction_id,
                docking_capacity, services, condition, reputation, credits, reserves, docked_ships,
                gate_paired_id, module_stock, fitting, crew_state, orbit_angle
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
        let entity = world.spawn((
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
                starving_notified: false,
            },
            FacilityStorage {
                reserves,
                docked_ships: vec![],
                pending_deliveries: vec![],
                dock_queue: vec![],
            },
            sim_core::agents::facility::FacilityLifecycle::new(),
            FacilityOrbit::new(&location_name, r.try_get::<Option<f64>, _>("orbit_angle")
                .ok().flatten().map(|v| v as f32)),
            sim_core::simulation::lod::AgentLod::new(),
        )).id();
        // Attach FacilityFitting (Phase 18e) to every non-gate
        // facility. Gates don't run recipes, so the fitting has no
        // effect on them — skipping keeps the component set tight.
        let fac_type_for_crew = {
            // Pull the type out before it's moved into identity.
            let id_ref = world
                .get::<FacilityIdentity>(entity)
                .expect("just-spawned facility has identity");
            id_ref.facility_type.clone()
        };
        if !is_gate {
            let fitting_json: String = r.try_get("fitting").unwrap_or_default();
            let fitting = parse_facility_fitting(&fitting_json);
            world.entity_mut(entity).insert(fitting);
        }

        // Phase 19a: attach FacilityCrew to every facility. Gate
        // types get a zero-crew default (automated infrastructure);
        // every staffed type gets a count sized by its role.
        // Hydrates from the crew_state JSON if set, else type default.
        let crew_json: String = r.try_get("crew_state").unwrap_or_default();
        let crew = parse_facility_crew(&crew_json, &fac_type_for_crew);
        world.entity_mut(entity).insert(crew);

        // Attach ModuleStock to shipyards (Phase 18c). Non-shipyards
        // get nothing — the tick phase keys on facility_type before
        // querying, and the snapshot layer serializes None.
        if facility_entity_is_shipyard_like(world, entity) {
            let module_stock_json: String =
                r.try_get("module_stock").unwrap_or_default();
            let stock = parse_module_stock(&module_stock_json);
            world
                .entity_mut(entity)
                .insert(sim_core::agents::facility::ModuleStock {
                    stock,
                    dirty: false,
                });
        }

        // Attach GateLink for gate facilities. Pairing is symmetric but
        // we validate only existence here; the pathfinder will resolve
        // the paired entity at lookup time.
        if is_gate {
            if let Some(paired) = gate_paired_id.filter(|s| !s.is_empty()) {
                use sim_core::agents::facility::{
                    GateLink, DEFAULT_GATE_FEE_FLAT, DEFAULT_GATE_FEE_PER_CARGO,
                    DEFAULT_GATE_THROUGHPUT,
                };
                world
                    .entity_mut(entity)
                    .insert(GateLink {
                        paired_gate_id: paired,
                        fee_flat: DEFAULT_GATE_FEE_FLAT,
                        fee_per_cargo_unit: DEFAULT_GATE_FEE_PER_CARGO,
                        throughput_cap: DEFAULT_GATE_THROUGHPUT,
                    });
            }
        }
        store.index_facility(id, location_name, entity);
    }
    Ok(())
}

async fn load_markets(world: &mut World, pool: &SqlitePool, _config: &TickConfig, store: &mut AgentStore) -> Result<()> {
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
        let facility_entity = facility_entity_by_db_id(world, facility_db_id)
            .ok_or_else(|| anyhow::anyhow!("market {db_id} references missing facility db_id={facility_db_id}"))?;

        let id = format!("market-{}", facility_location);
        let entity = world.spawn((
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
                trend_samples: Default::default(),
                trade_volume: parse_commodity_f32_map(&volume_json),
                shortage_ticks: parse_commodity_u32_map(&shortage_json),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
                crisis_notified: Default::default(),
            },
        )).id();
        store.index_market(id, facility_location, entity);
    }
    Ok(())
}

/// Phase 20d: read the most recent `MARKET_TREND_KEEP` samples per
/// market from the `market_trend_samples` table and rehydrate each
/// `MarketHistory.trend_samples` ring. Must run after `load_markets`
/// so the target hecs entities exist.
///
/// Query strategy: pull every row in tick-ascending order (per market)
/// and let the in-memory cap take care of trimming. Cheap because the
/// "interesting" set is bounded — at the worst case, 39 markets × ~6
/// commodities × 200 ring depth = ~47k rows; deliberate-table-scan
/// territory, especially with the `(market_id, tick DESC)` index from
/// migration 013.
async fn load_market_trend_samples(
    world: &mut World,
    pool: &SqlitePool,
    _store: &mut AgentStore,
) -> Result<()> {
    use sim_core::agents::market::{MarketHistory, MarketIdentity, MarketTrendSample, MARKET_TREND_KEEP};
    use sim_core::economy::commodities::Commodity;
    use std::collections::HashMap;

    // Build market_db_id → bevy_ecs::Entity once. Mirrors the helper used
    // by `load_markets`'s facility lookup.
    let entity_by_db_id: HashMap<i64, Entity> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(world)
            .map(|(e, id)| (id.db_id, e))
            .collect()
    };

    // Pull every persisted sample. The KEEP cap is enforced after the
    // pivot (sorted ASC, then truncated from the front) so even if the
    // DB has more rows than the in-memory ring per market, we end up
    // with exactly the freshest `MARKET_TREND_KEEP` samples in RAM.
    let rows = sqlx::query(
        "SELECT market_id, tick, commodity, price, supply
         FROM market_trend_samples
         ORDER BY market_id ASC, tick ASC",
    )
    .fetch_all(pool)
    .await?;

    if rows.is_empty() {
        return Ok(());
    }

    // Pivot: (market_db_id, tick) → HashMap<Commodity, (price, supply)>
    let mut by_market_tick: HashMap<i64, HashMap<i64, MarketTrendSample>> =
        HashMap::new();
    for r in rows {
        let market_db_id: i64 = r.get("market_id");
        let tick: i64 = r.get("tick");
        let commodity_str: String = r.get("commodity");
        let price: f64 = r.get("price");
        let supply: f64 = r.get("supply");
        let Some(commodity) = Commodity::parse(&commodity_str) else {
            continue;
        };
        let market_bucket = by_market_tick.entry(market_db_id).or_default();
        let sample = market_bucket
            .entry(tick)
            .or_insert_with(|| MarketTrendSample {
                tick: tick as u64,
                prices: HashMap::new(),
                supply: HashMap::new(),
            });
        sample.prices.insert(commodity, price as f32);
        sample.supply.insert(commodity, supply as f32);
    }

    // Apply per market: sort samples ascending, keep newest KEEP entries,
    // push into the live `MarketHistory.trend_samples`.
    let mut total_loaded = 0usize;
    for (market_db_id, tick_map) in by_market_tick {
        let Some(&entity) = entity_by_db_id.get(&market_db_id) else {
            // Market was dropped between the trend write and the load —
            // skip the orphan rows. The ON DELETE CASCADE in migration
            // 013 should make this rare, but seed-rebuild paths can
            // still produce it.
            continue;
        };
        let mut samples: Vec<MarketTrendSample> = tick_map.into_values().collect();
        samples.sort_by_key(|s| s.tick);
        // Trim to the in-memory ring depth (keep newest).
        if samples.len() > MARKET_TREND_KEEP {
            let drop_n = samples.len() - MARKET_TREND_KEEP;
            samples.drain(..drop_n);
        }
        if let Some(mut hist) = world.get_mut::<MarketHistory>(entity) {
            hist.trend_samples = samples.into_iter().collect();
            total_loaded += hist.trend_samples.len();
        }
    }

    info!("Spawner: rehydrated {} market trend samples", total_loaded);
    Ok(())
}

async fn load_populations(world: &mut World, pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
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

        let facility_entity = facility_entity_by_db_id(world, facility_db_id)
            .ok_or_else(|| anyhow::anyhow!("population {db_id} references missing facility db_id={facility_db_id}"))?;

        let id = format!("pop-{}", label.to_lowercase().replace(' ', "-"));
        let production_commodity = prod_commodity.as_deref().and_then(Commodity::parse);

        let entity = world.spawn((
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
        )).id();
        store.index_population(id, entity);
    }
    Ok(())
}

async fn load_ships(
    world: &mut World,
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
                active_contract_id, price_knowledge, visited, fitting, progression, size, resume_json
         FROM ships",
    )
    .fetch_all(pool)
    .await?;

    for r in rows {
        let resume: Option<crate::persistence::ShipResumeState> = r.get::<Option<String>, _>("resume_json")
            .map(|json| serde_json::from_str(&json)).transpose()?;
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

        // Phase 18i: on missing/malformed personality JSON, fall
        // back to a class-appropriate archetype with per-ship
        // variation — avoids funneling everyone into the same
        // balanced_trader and preserves randomness inside a class.
        let personality = serde_json::from_str::<Personality>(&personality_json)
            .unwrap_or_else(|_| {
                let mut rng = rand::thread_rng();
                Personality::for_class(&class).with_variation(&mut rng)
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

        // Phase 18a/b: resolve the ship's subsystem fitting.
        // New rows + migration-defaulted rows carry `fitting = '{}'`,
        // which parses as "no slot set" → falls back to the tier-1
        // default per slot. Rows persisted after a refit carry a
        // populated object. Either way the derived multipliers get
        // baked into the loaded cargo capacity + speed modifier so
        // tick-loop code reads the same fields it always did.
        // Phase 18f: resolve size. Empty → fall back to class default.
        let size_str: String = r.try_get("size").unwrap_or_default();
        let class_default_size = sim_core::simulation::config::ship_class(&class)
            .map(|c| c.default_size)
            .unwrap_or(sim_core::simulation::config::ShipSize::Medium);
        let ship_size = sim_core::simulation::config::ShipSize::parse(&size_str)
            .unwrap_or(class_default_size);

        // Phase 18f: size-aware default fitting. Tier-1 column means
        // "use the class/size default" — size ≥ 5 gets tier-2 sensors
        // at spawn, size 4 deterministically rolls 50%.
        let fitting_json: String = r.try_get("fitting").unwrap_or_default();
        let fitting = if fitting_json.trim().is_empty() || fitting_json == "{}" {
            sim_core::agents::ship::ShipFitting::new_for_size(ship_size, &id)
        } else {
            parse_ship_fitting(&fitting_json)
        };
        // Phase 18g: size-derived speed penalty. Compounds
        // multiplicatively with class speed_mod + fitting speed_mult
        // so a size-5 freighter with tier-2 engines is distinct from
        // a size-3 freighter with tier-1 engines.
        let size_speed_mod = ship_size.speed_multiplier();
        let progression_json: String = r.try_get("progression").unwrap_or_default();
        let progression = parse_ship_progression(&progression_json);
        let fitted_cargo_capacity =
            ((cargo_capacity as f32) * fitting.derived.cargo_capacity_mult).round() as u32;
        let fitted_speed_modifier =
            (speed_modifier as f32) * fitting.derived.speed_mult * size_speed_mod;

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

        // New snapshots override obsolete legacy columns. Explicit None clears
        // old docking/transit state rather than falling back to it.
        let (location_name, system_id, ox, oy, docked_at, transit, cargo_age, cargo_origin) =
            if let Some(state) = &resume {
                (state.location_name.clone().unwrap_or_default(), state.system_id.clone(),
                 state.universe_offset.0 as f64, state.universe_offset.1 as f64,
                 state.docked_db_id, state.transit.clone(), state.cargo_age.clone(), state.cargo_origin.clone())
            } else {
                (location_name, system_id, ox, oy, docked_at, transit, cargo_age, HashMap::new())
            };

        let visited: Vec<String> = serde_json::from_str(&visited_json).unwrap_or_default();
        let price_knowledge: PriceKnowledge =
            serde_json::from_str(&price_knowledge_json).unwrap_or_default();

        // Resolve docked-at facility entity from DB id, if any
        let docked_at_entity = docked_at.and_then(|fid| facility_entity_by_db_id(world, fid));

        // Seed ships don't have persisted `position_x/y` — they come out of
        // the DB as (0,0), which puts every ship at the universe origin
        // regardless of system. Resolve an initial position from the
        // ship's `location_name` via the body that location orbits. Falls
        // back to (0,0) only if the location or body can't be found.
        let (init_px, init_py) = if resume.is_none() && px.abs() < f64::EPSILON && py.abs() < f64::EPSILON {
            resolve_location_world_pos(world, registry, &location_name)
                .map(|(x, y)| (x as f64, y as f64))
                .unwrap_or((px, py))
        } else {
            (px, py)
        };

        let entity = world.spawn((
            ShipIdentity {
                db_id,
                id: id.clone(),
                name,
                class: class.clone(),
                faction_id,
                size: ship_size,
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
                capacity: fitted_cargo_capacity,
                cargo_age,
                cargo_origin,
            },
            ShipFuel {
                fuel: fuel as f32,
                fuel_capacity: fuel_capacity as f32,
                fuel_consumption_rate: fuel_consumption_rate as f32,
                speed_modifier: fitted_speed_modifier,
            },
            ShipEconomy {
                transaction: Default::default(),
                credits,
                efficiency: efficiency as f32,
                active_contract_id,
                faction_reputation,
                dock_dwell_start_tick: None,
                rest_start_tick: None,
                dock_attempt_start_tick: None,
            },
            ShipAI {
                personality,
                current_goal,
                current_bt: None,
                current_goal_score: 0.0,
                last_plan_tick: 0,
            },
            ShipMemory {
                price_knowledge,
                visited,
                recent_systems: std::collections::VecDeque::new(),
                route_performance: std::collections::HashMap::new(),
            },
            ShipLifecycle {
                broke_strikes: broke_strikes as u8,
                hoard_strikes: hoard_strikes as u8,
                idle_ticks: idle_ticks as u32,
                dirty: false,
            },
        )).id();
        // Crew from class. Seed from Elixir CrewComplement defaults:
        // morale=70, fatigue=10, hunger=10, health=100, idle task, no wages yet.
        let ship_class = sim_core::simulation::config::ship_class(&class);
        let crew_size = ship_class.map(|c| c.crew_size).unwrap_or(5);
        let crew_roles = ship_class.map(|c| c.crew_roles).unwrap_or(&[]);
        world.entity_mut(entity).insert(ShipCrew {
            size: crew_size,
            hunger: 10.0,
            morale: 70.0,
            fatigue: 10.0,
            health: 100.0,
            wages_credits: resume.as_ref().map(|r| r.crew_savings).unwrap_or(0),
            current_task: sim_core::agents::ship::CrewTask::Idle,
            dirty: false,
        });
        world
            .entity_mut(entity)
            .insert(sim_core::agents::ship::ShipCrewSkills::for_roles(crew_roles));
        world.entity_mut(entity).insert(fitting);
        world.entity_mut(entity).insert(progression);
        // Attach LOD cursor — defaults to divisor 1 so new ships run at
        // full cadence until the next `tick_lod_recompute` pass.
        world
            .entity_mut(entity)
            .insert(sim_core::simulation::lod::AgentLod::new());
        if let Some(facility) = docked_at_entity {
            if let Some(mut storage) = world.get_mut::<FacilityStorage>(facility) {
                storage.docked_ships.push(entity);
            }
        }
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
    world: &mut World,
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
    let body_pos = {
        let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
        q.iter(world)
            .find(|(id, _)| id.db_id == body_db_id)
            .map(|(_, orbit)| orbit.universe_position())?
    };
    // If there's a facility at this location, use its offset so the ship
    // starts at the dock rather than the body center.
    let fac_id = {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        q.iter(world)
            .find(|(_, loc)| loc.location_name == location_name)
            .map(|(id, _)| id.id.clone())
    };
    Some(if let Some(id) = fac_id {
        facility_offset_position(body_pos, &id)
    } else {
        body_pos
    })
}

fn facility_entity_by_db_id(world: &mut World, db_id: i64) -> Option<Entity> {
    // Look up by iterating the world; we only do this during initial spawn so cost is O(N_facilities)
    // and only runs once. After startup, agents reference facilities by hecs::Entity directly.
    let mut q = world.query::<(Entity, &FacilityIdentity)>();
    for (e, id) in q.iter(world) {
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

/// Parse a `facilities.fitting` JSON blob (slot_name → slug | null)
/// into a [`FacilityFitting`]. Empty / missing / malformed input
/// falls back to the tier-1 default — matches the migration default
/// so pre-Phase-18e rows round-trip cleanly into a neutral fitting.
fn parse_facility_fitting(json: &str) -> sim_core::agents::facility::FacilityFitting {
    use sim_core::facility_modules::{FACILITY_SLOTS, NUM_FACILITY_SLOTS};
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return sim_core::agents::facility::FacilityFitting::new_default(),
    };
    let Some(obj) = v.as_object() else {
        return sim_core::agents::facility::FacilityFitting::new_default();
    };
    if obj.is_empty() {
        return sim_core::agents::facility::FacilityFitting::new_default();
    }
    let mut raw: [Option<String>; NUM_FACILITY_SLOTS] = Default::default();
    for slot in FACILITY_SLOTS.iter().copied() {
        raw[slot.index()] = obj
            .get(slot.as_str())
            .and_then(|v| {
                if v.is_null() {
                    None
                } else {
                    v.as_str().map(|s| s.to_string())
                }
            });
        if raw[slot.index()].is_none() && !obj.contains_key(slot.as_str()) {
            raw[slot.index()] =
                Some(sim_core::facility_modules::default_for_slot(slot).to_string());
        }
    }
    sim_core::agents::facility::FacilityFitting::from_slugs(&raw)
}

/// Parse a `facilities.crew_state` JSON blob into a FacilityCrew.
/// Empty object (the migration default) or malformed JSON falls back
/// to the per-facility-type default — existing rows pre-migration-009
/// thus pick up a fresh crew complement without manual seeding.
fn parse_facility_crew(
    json: &str,
    facility_type: &str,
) -> sim_core::agents::facility::FacilityCrew {
    use sim_core::agents::facility::{FacilityCrew, FacilityCrewSnapshot};
    let snap: Option<FacilityCrewSnapshot> = serde_json::from_str(json).ok();
    match snap {
        Some(s) if s.crew_count > 0 => s.into(),
        _ => FacilityCrew::new_for_type(facility_type),
    }
}

/// Read the `facility_type` of the just-spawned facility entity and
/// check whether it's a shipyard. Queried off the live world instead
/// of passed explicitly so `load_facilities` doesn't need to hold an
/// extra variable mid-loop.
fn facility_entity_is_shipyard_like(world: &World, entity: Entity) -> bool {
    use sim_core::agents::facility::FacilityIdentity;
    match world.get::<FacilityIdentity>(entity) {
        Some(id) => id.facility_type == "shipyard",
        None => false,
    }
}

/// Parse a `facilities.module_stock` JSON blob (slug → integer) into
/// an in-memory map. Unknown slugs are dropped — same pattern as
/// `parse_ship_fitting`: a stale row can't bring a non-existent module
/// back from the dead.
fn parse_module_stock(json: &str) -> HashMap<String, u32> {
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return HashMap::new(),
    };
    v.as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, val)| {
                    // Only retain slugs still in the catalog. A sim
                    // that renamed `engine_t2` would otherwise keep
                    // ghost stock forever.
                    sim_core::modules::get(k)?;
                    Some((k.clone(), val.as_u64()? as u32))
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Parse a `ships.progression` JSON blob into a [`ShipProgression`].
/// Empty / missing / malformed input falls back to a fresh level-1
/// ship — matches the migration default so pre-18d rows round-trip
/// into identical runtime state.
fn parse_ship_progression(json: &str) -> sim_core::agents::ship::ShipProgression {
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return sim_core::agents::ship::ShipProgression::new(),
    };
    let level = v.get("level").and_then(|x| x.as_u64()).unwrap_or(1) as u8;
    let xp = v.get("xp").and_then(|x| x.as_u64()).unwrap_or(0) as u32;
    let retrofit_points = v
        .get("retrofit_points")
        .and_then(|x| x.as_u64())
        .unwrap_or(0) as u8;
    sim_core::agents::ship::ShipProgression {
        level: level.max(1),
        xp,
        retrofit_points,
        dirty: false,
    }
}

/// Parse a `ships.fitting` JSON blob (slot_name → slug | null) into a
/// `ShipFitting`. Empty / missing / malformed input falls back to the
/// tier-1 default — a pre-Phase-18b row stored as `'{}'` round-trips
/// cleanly into a baseline-neutral fitting.
fn parse_ship_fitting(json: &str) -> sim_core::agents::ship::ShipFitting {
    use sim_core::modules::{NUM_SLOTS, SLOTS};
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return sim_core::agents::ship::ShipFitting::new_default(),
    };
    let Some(obj) = v.as_object() else {
        return sim_core::agents::ship::ShipFitting::new_default();
    };
    // Treat empty object as "use defaults" for every slot — matches the
    // migration default.
    if obj.is_empty() {
        return sim_core::agents::ship::ShipFitting::new_default();
    }
    let mut raw: [Option<String>; NUM_SLOTS] = Default::default();
    for slot in SLOTS.iter().copied() {
        raw[slot.index()] = obj
            .get(slot.as_str())
            .and_then(|v| {
                if v.is_null() {
                    None
                } else {
                    v.as_str().map(|s| s.to_string())
                }
            });
        // If the key was *missing entirely* (not null), fall back to
        // the default so partial migrations still yield a viable fit.
        if raw[slot.index()].is_none() && !obj.contains_key(slot.as_str()) {
            raw[slot.index()] = Some(sim_core::modules::default_for_slot(slot).to_string());
        }
    }
    sim_core::agents::ship::ShipFitting::from_slugs(&raw)
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

/// Hydrate the contract board from SQLite on boot. Every row becomes
/// an entry in `store.contracts`; unknown enum values are skipped
/// with a warning rather than aborting the load. Fresh-seed runs land
/// here with zero rows (the table was just created), so the boot-time
/// contract pump runs afterward to populate the board.
pub(crate) async fn load_contracts(pool: &SqlitePool, store: &mut AgentStore) -> Result<()> {
    use sim_core::economy::contracts::{Contract, ContractStatus, ContractType};

    let rows = sqlx::query(
        "SELECT id, contract_type, status, requestor_id, fulfiller_id,
                commodity, quantity, source_location, destination_location,
                payment, initial_payment, funding_json, renewal_count,
                faction_id, min_reputation, initial_min_reputation,
                mission_category,
                posted_at_tick, accepted_at_tick, expires_at_tick
           FROM contracts",
    )
    .fetch_all(pool)
    .await?;

    let mut loaded = 0_usize;
    for r in rows {
        let id: String = r.get("id");
        let kind_str: String = r.get("contract_type");
        let status_str: String = r.get("status");
        let commodity_str: String = r.get("commodity");

        let contract_type = match kind_str.as_str() {
            "delivery" => ContractType::Delivery,
            "courier" => ContractType::Courier,
            "passenger" => ContractType::Passenger,
            "subsidy" => ContractType::Subsidy,
            "supply" => ContractType::Supply,
            "crew_mission" => ContractType::CrewMission,
            "construction" => ContractType::Construction,
            other => {
                tracing::warn!(id = %id, kind = %other, "skipping contract with unknown type");
                continue;
            }
        };
        let status = match status_str.as_str() {
            "posted" => ContractStatus::Posted,
            "accepted" => ContractStatus::Accepted,
            "picked_up" => ContractStatus::PickedUp,
            "delivered" => ContractStatus::Delivered,
            "paid" => ContractStatus::Paid,
            "expired" => ContractStatus::Expired,
            other => {
                tracing::warn!(id = %id, status = %other, "skipping contract with unknown status");
                continue;
            }
        };
        let Some(commodity) = Commodity::parse(&commodity_str) else {
            tracing::warn!(id = %id, commodity = %commodity_str, "skipping contract with unknown commodity");
            continue;
        };

        let payment: i64 = r.get("payment");
        let initial_payment_raw: i64 = r.get("initial_payment");
        let min_reputation: i64 = r.get("min_reputation");
        let initial_min_reputation_raw: i64 = r.get("initial_min_reputation");

        let funding = r.get::<Option<String>, _>("funding_json")
            .map(|json| serde_json::from_str(&json)).transpose()?;
        let contract = Contract {
            id: id.clone(),
            contract_type,
            status,
            requestor_id: r.get("requestor_id"),
            faction_id: r.try_get::<Option<String>, _>("faction_id").ok().flatten(),
            fulfiller_id: r.try_get::<Option<String>, _>("fulfiller_id").ok().flatten(),
            commodity,
            quantity: r.get::<i64, _>("quantity") as u32,
            source_location: r.get("source_location"),
            destination_location: r.get("destination_location"),
            payment,
            funding,
            initial_payment: if initial_payment_raw > 0 {
                initial_payment_raw
            } else {
                payment
            },
            posted_at_tick: r.get::<i64, _>("posted_at_tick") as u64,
            accepted_at_tick: r
                .try_get::<Option<i64>, _>("accepted_at_tick")
                .ok()
                .flatten()
                .map(|t| t as u64),
            expires_at_tick: r.get::<i64, _>("expires_at_tick") as u64,
            mission_category: r
                .try_get::<Option<String>, _>("mission_category")
                .ok()
                .flatten(),
            min_reputation: min_reputation.clamp(0, 100) as u8,
            initial_min_reputation: initial_min_reputation_raw.clamp(0, 100) as u8,
            renewal_count: r.get::<i64, _>("renewal_count").clamp(0, u8::MAX as i64) as u8,
        };
        store.contracts.insert_loaded(contract);
        loaded += 1;
    }

    if loaded > 0 {
        info!("Spawner: loaded {} contracts from DB", loaded);
    }
    Ok(())
}

/// Phase 19c-d: rebuild any live construction sites from the DB.
/// Incomplete sites (progress < 1.0 and not `completed`) spawn back
/// into the ECS; finished sites on disk are rare (a race between
/// completion-emit and restart) and are skipped so the subsequent
/// materialisation isn't attempted twice.
async fn load_construction_sites(world: &mut World, pool: &SqlitePool, _store: &mut AgentStore) -> Result<()> {
    use sim_core::agents::construction::ConstructionSite;
    use sim_core::economy::commodities::Commodity;

    let rows = sqlx::query(
        "SELECT agent_id, name, facility_type, faction_id, body_id,
                location_name, commodity,
                progress_delivered, progress_required,
                position_x, position_y,
                spawned_at_tick, completed, labor_state
           FROM construction_sites",
    )
    .fetch_all(pool)
    .await?;

    let mut loaded = 0_usize;
    for r in rows {
        let completed: i64 = r.get("completed");
        if completed != 0 {
            continue;
        }
        let commodity_str: String = r.get("commodity");
        let Some(commodity) = Commodity::parse(&commodity_str) else {
            tracing::warn!(
                commodity = %commodity_str,
                "skipping construction site with unknown commodity"
            );
            continue;
        };
        let site = ConstructionSite {
                labor: serde_json::from_str(&r.get::<String, _>("labor_state"))?,
            id: r.get("agent_id"),
            name: r.get("name"),
            facility_type: r.get("facility_type"),
            faction_id: r.get("faction_id"),
            body_id: r.get("body_id"),
            location_name: r.get("location_name"),
            commodity,
            progress_delivered: r.get::<i64, _>("progress_delivered") as u32,
            progress_required: r.get::<i64, _>("progress_required") as u32,
            position: (
                r.get::<f64, _>("position_x") as f32,
                r.get::<f64, _>("position_y") as f32,
            ),
            spawned_at_tick: r.get::<i64, _>("spawned_at_tick") as u64,
            completed: false,
            dirty: false,
        };
        world.spawn((site,));
        loaded += 1;
    }

    if loaded > 0 {
        info!("Spawner: loaded {} construction sites from DB", loaded);
    }
    Ok(())
}
