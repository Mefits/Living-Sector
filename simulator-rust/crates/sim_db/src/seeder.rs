use anyhow::{Context, Result};
use serde_json::Value;
use sqlx::SqlitePool;
use std::collections::HashMap;
use tracing::info;

/// Returns true if the DB appears to already be seeded (has star systems).
pub async fn is_seeded(pool: &SqlitePool) -> Result<bool> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM star_systems")
        .fetch_one(pool)
        .await?;
    Ok(count > 0)
}

/// Seeds everything from `data_dir` (path to the `priv/data` directory).
pub async fn seed_all(pool: &SqlitePool, data_dir: &std::path::Path) -> Result<()> {
    let factions_path = data_dir.join("factions.json");
    info!("Seeder: loading factions from {}", factions_path.display());
    seed_factions(pool, &factions_path).await?;

    let worlds_dir = data_dir.join("worlds");
    for entry in std::fs::read_dir(&worlds_dir)
        .with_context(|| format!("reading worlds dir: {}", worlds_dir.display()))?
    {
        let path = entry?.path();
        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            info!("Seeder: loading world {}", path.display());
            seed_world(pool, &path).await?;
        }
    }
    info!("Seeder: complete");
    Ok(())
}

async fn seed_factions(pool: &SqlitePool, path: &std::path::Path) -> Result<()> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let factions: Vec<Value> = serde_json::from_str(&text)?;

    for f in &factions {
        let id = str_field(f, "id")?;
        let personality = f.get("personality").cloned().unwrap_or(Value::Object(Default::default()));
        let colors = f.get("colors").cloned().unwrap_or(Value::Object(Default::default()));
        sqlx::query(
            "INSERT INTO factions (id, name, faction_type, description, home_system, treasury, personality, colors)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(id) DO UPDATE SET
               name=excluded.name, faction_type=excluded.faction_type,
               description=excluded.description, home_system=excluded.home_system,
               treasury=excluded.treasury, personality=excluded.personality,
               colors=excluded.colors, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
        )
        .bind(&id)
        .bind(str_field(f, "name")?)
        .bind(str_field(f, "type")?)
        .bind(f.get("description").and_then(|v| v.as_str()).unwrap_or(""))
        .bind(f.get("home_system").and_then(|v| v.as_str()).unwrap_or(""))
        .bind(f.get("treasury").and_then(|v| v.as_i64()).unwrap_or(0))
        .bind(personality.to_string())
        .bind(colors.to_string())
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn seed_world(pool: &SqlitePool, path: &std::path::Path) -> Result<()> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let data: Value = serde_json::from_str(&text)?;

    // --- 1. Star system ---
    let sys = data["system"].as_object().context("missing 'system'")?;
    let sys_name = sys["name"].as_str().context("system.name")?;
    let offset = sys.get("universe_offset")
        .and_then(|v| v.as_array())
        .filter(|a| a.len() == 2)
        .map(|a| (a[0].as_f64().unwrap_or(0.0) as f32, a[1].as_f64().unwrap_or(0.0) as f32))
        .unwrap_or((0.0, 0.0));
    // Optional spectral class. Renderer maps the string to a sun
    // colour + radius. Missing → default G-class yellow at load.
    let star_type: Option<&str> = sys.get("star_type").and_then(|v| v.as_str());

    sqlx::query(
        "INSERT INTO star_systems (name, universe_offset_x, universe_offset_y, star_type)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(name) DO UPDATE SET
           universe_offset_x=excluded.universe_offset_x,
           universe_offset_y=excluded.universe_offset_y,
           star_type=excluded.star_type,
           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
    )
    .bind(sys_name)
    .bind(offset.0)
    .bind(offset.1)
    .bind(star_type)
    .execute(pool)
    .await?;

    let system_id: i64 =
        sqlx::query_scalar("SELECT id FROM star_systems WHERE name = ?1")
            .bind(sys_name)
            .fetch_one(pool)
            .await?;

    // --- 2. Celestial bodies ---
    // body JSON id → DB row id
    let mut body_db_id: HashMap<String, i64> = HashMap::new();

    for body in data["bodies"].as_array().unwrap_or(&vec![]) {
        let bid = str_field(body, "id")?;
        let resources = body.get("resources").cloned().unwrap_or(Value::Object(Default::default()));
        sqlx::query(
            "INSERT INTO celestial_bodies
               (body_id, name, body_type, orbit_radius, orbit_period, current_angle, resources, biome, star_system_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(body_id) DO UPDATE SET
               name=excluded.name, body_type=excluded.body_type,
               orbit_radius=excluded.orbit_radius, orbit_period=excluded.orbit_period,
               current_angle=excluded.current_angle, resources=excluded.resources,
               biome=excluded.biome, star_system_id=excluded.star_system_id,
               updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
        )
        .bind(&bid)
        .bind(str_field(body, "name")?)
        .bind(body.get("type").and_then(|v| v.as_str()).unwrap_or("planet"))
        .bind(body["orbit_radius"].as_f64().unwrap_or(1.0) as f32)
        .bind(body["orbit_period"].as_i64().unwrap_or(365))
        .bind(body.get("current_angle").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32)
        .bind(resources.to_string())
        .bind(body.get("biome").and_then(|v| v.as_str()))
        .bind(system_id)
        .execute(pool)
        .await?;

        let db_id: i64 =
            sqlx::query_scalar("SELECT id FROM celestial_bodies WHERE body_id = ?1")
                .bind(&bid)
                .fetch_one(pool)
                .await?;
        body_db_id.insert(bid, db_id);
    }

    // --- 3. Facilities (creates locations on-demand) ---
    // location_name → DB id
    let mut location_db_id: HashMap<String, i64> = HashMap::new();

    for fac in data["facilities"].as_array().unwrap_or(&vec![]) {
        let loc_name = str_field(fac, "location")?;
        let body_json_id = fac.get("body").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let body_db = body_db_id.get(&body_json_id).copied().unwrap_or(0);

        // Upsert location
        if !location_db_id.contains_key(&loc_name) {
            sqlx::query(
                "INSERT INTO locations (name, loc_type, celestial_body_id)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(name) DO UPDATE SET
                   loc_type=excluded.loc_type,
                   celestial_body_id=excluded.celestial_body_id,
                   updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
            )
            .bind(&loc_name)
            .bind(fac.get("type").and_then(|v| v.as_str()).unwrap_or("station"))
            .bind(body_db)
            .execute(pool)
            .await?;

            let lid: i64 =
                sqlx::query_scalar("SELECT id FROM locations WHERE name = ?1")
                    .bind(&loc_name)
                    .fetch_one(pool)
                    .await?;
            location_db_id.insert(loc_name.clone(), lid);
        }

        let loc_id = location_db_id[&loc_name];
        let fac_name = str_field(fac, "name")?;

        // Skip if already seeded
        let exists: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM facilities WHERE location_id = ?1 AND name = ?2",
        )
        .bind(loc_id)
        .bind(&fac_name)
        .fetch_one(pool)
        .await?;

        if exists == 0 {
            let services = fac.get("services")
                .cloned()
                .unwrap_or(Value::Array(vec![]));
            let reserves = fac.get("reserves")
                .cloned()
                .unwrap_or(Value::Object(Default::default()));

            // Phase 18h: accept optional `fitting` + `module_stock`
            // on the facility JSON. Missing → tier-1 default /
            // empty stock (today's behavior). Lets world seeds ship
            // with "advanced" refineries (production_t2) or
            // pre-stocked shipyards so the economy starts with
            // capacity instead of spinning up over minutes.
            let fitting_json = fac
                .get("fitting")
                .filter(|v| v.is_object())
                .cloned()
                .map(|v| v.to_string())
                .unwrap_or_else(|| "{}".to_string());
            let module_stock_json = fac
                .get("module_stock")
                .filter(|v| v.is_object())
                .cloned()
                .map(|v| v.to_string())
                .unwrap_or_else(|| "{}".to_string());

            sqlx::query(
                "INSERT INTO facilities
                   (name, facility_type, location_id, location_name, body_id, faction_id,
                    docking_capacity, services, condition, reputation, credits, reserves,
                    gate_paired_id, fitting, module_stock)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
            )
            .bind(&fac_name)
            .bind(fac.get("type").and_then(|v| v.as_str()).unwrap_or("station"))
            .bind(loc_id)
            .bind(&loc_name)
            .bind(&body_json_id)
            .bind(fac.get("faction_id").and_then(|v| v.as_str()).unwrap_or(""))
            .bind(fac.get("docking_capacity").and_then(|v| v.as_i64()).unwrap_or(5))
            .bind(services.to_string())
            .bind(1.0_f32)
            .bind(50_i32)
            // Facility seed credits: enough runway for ~4 delivery
            // contracts (~24k) + docking fees + restocks before the
            // first tax cycle brings in faction support. At 10k,
            // facilities were burning out before the supply chain had
            // a chance to stabilize, which killed contract acceptance
            // outright — no facility could afford to keep posting.
            .bind(30_000_i64)
            .bind(reserves.to_string())
            .bind(fac.get("gate_paired_id").and_then(|v| v.as_str()))
            .bind(fitting_json)
            .bind(module_stock_json)
            .execute(pool)
            .await?;
        }
    }

    // Refresh location map for locations that may have been created above
    // but weren't in the facilities loop (e.g., if markets reference a location not yet seen)
    let all_locs: Vec<(i64, String)> =
        sqlx::query_as("SELECT id, name FROM locations")
            .fetch_all(pool)
            .await?;
    for (id, name) in all_locs {
        location_db_id.entry(name).or_insert(id);
    }

    // --- 4. Markets ---
    for mkt in data["markets"].as_array().unwrap_or(&vec![]) {
        // "facility_id" in JSON is actually the location name
        let loc_name = str_field(mkt, "facility_id")?;
        let loc_id = match location_db_id.get(&loc_name) {
            Some(&id) => id,
            None => continue,
        };

        let facility_id: Option<i64> = sqlx::query_scalar(
            "SELECT id FROM facilities WHERE location_id = ?1 LIMIT 1",
        )
        .bind(loc_id)
        .fetch_optional(pool)
        .await?;

        let fac_id = match facility_id {
            Some(id) => id,
            None => continue,
        };

        let prices = mkt.get("prices").cloned().unwrap_or_default();
        let supply = mkt.get("supply").cloned().unwrap_or_default();
        let demand = mkt.get("demand").cloned().unwrap_or_default();
        let production = mkt.get("production").cloned().unwrap_or_default();
        let consumption = mkt.get("consumption").cloned().unwrap_or_default();
        let elasticity = mkt.get("price_elasticity").and_then(|v| v.as_f64()).unwrap_or(0.02) as f32;

        sqlx::query(
            "INSERT INTO markets
               (facility_id, facility_location, price_elasticity, spread,
                prices, supply, demand, production, consumption)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(facility_id) DO UPDATE SET
               price_elasticity=excluded.price_elasticity, spread=excluded.spread,
               prices=excluded.prices, supply=excluded.supply, demand=excluded.demand,
               production=excluded.production, consumption=excluded.consumption,
               updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
        )
        .bind(fac_id)
        .bind(&loc_name)
        .bind(elasticity)
        .bind(0.10_f32)
        .bind(prices.to_string())
        .bind(supply.to_string())
        .bind(demand.to_string())
        .bind(production.to_string())
        .bind(consumption.to_string())
        .execute(pool)
        .await?;
    }

    // --- 5. Travel routes ---
    for route in data["travel_routes"].as_array().unwrap_or(&vec![]) {
        let from = str_field(route, "from")?;
        let to = str_field(route, "to")?;
        let dist = route["distance"].as_i64().unwrap_or(60);
        sqlx::query(
            "INSERT INTO travel_routes (from_location, to_location, distance)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(from_location, to_location) DO UPDATE SET distance=excluded.distance",
        )
        .bind(&from)
        .bind(&to)
        .bind(dist)
        .execute(pool)
        .await?;
        // Insert reverse direction too
        sqlx::query(
            "INSERT INTO travel_routes (from_location, to_location, distance)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(from_location, to_location) DO UPDATE SET distance=excluded.distance",
        )
        .bind(&to)
        .bind(&from)
        .bind(dist)
        .execute(pool)
        .await?;
    }

    // --- 6. Ships ---
    for ship in data["ships"].as_array().unwrap_or(&vec![]) {
        let name = str_field(ship, "name")?;
        // Idempotent: skip if already exists
        let exists: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM ships WHERE name = ?1")
                .bind(&name)
                .fetch_one(pool)
                .await?;
        if exists > 0 {
            continue;
        }

        let loc_name = str_field(ship, "location")?;
        let loc_id = location_db_id.get(&loc_name).copied();
        let class = ship.get("class").and_then(|v| v.as_str()).unwrap_or("freighter");
        let faction_id = ship.get("faction_id").and_then(|v| v.as_str()).unwrap_or("");
        let credits = ship.get("credits").and_then(|v| v.as_i64()).unwrap_or(5000);

        // Look up class stats from sim_core config
        let class_cfg = sim_core::simulation::config::ship_class(class);
        let (cargo_cap, fuel_cap, fuel_rate, speed) = class_cfg
            .map(|c| (c.cargo_capacity, c.fuel_capacity, c.fuel_consumption_base, c.speed_modifier))
            .unwrap_or((500, 100.0, 0.05, 1.0));

        // Phase 18h: accept optional `size` override. Falls back to
        // the class's default_size when unset. Stored as snake_case
        // string (tiny/small/.../massive) so the loader's
        // `ShipSize::parse` reads it back.
        let size_str = ship
            .get("size")
            .and_then(|v| v.as_str())
            .and_then(sim_core::simulation::config::ShipSize::parse)
            .map(|s| s.as_str())
            .unwrap_or_else(|| {
                class_cfg
                    .map(|c| c.default_size.as_str())
                    .unwrap_or("medium")
            });

        // Phase 18h: accept optional `fitting` override — map of
        // slot_name → slug. Missing slots fall back to the class's
        // size-aware default at load time. Passed through as a JSON
        // string so the ships.fitting column stores exactly what the
        // loader would've written itself after a refit.
        let fitting_json = ship
            .get("fitting")
            .filter(|v| v.is_object())
            .cloned()
            .map(|v| v.to_string())
            .unwrap_or_else(|| "{}".to_string());

        // Phase 18h: accept optional `progression` override — lets a
        // "veteran" ship spawn at level > 1 with banked retrofit
        // points so it can head for a shipyard day one.
        let progression_json = ship
            .get("progression")
            .filter(|v| v.is_object())
            .cloned()
            .map(|v| v.to_string())
            .unwrap_or_else(|| {
                r#"{"level":1,"xp":0,"retrofit_points":0}"#.to_string()
            });

        // Default reputation: 70 for own faction, 30 for others
        let faction_ids: Vec<String> =
            sqlx::query_scalar("SELECT id FROM factions")
                .fetch_all(pool)
                .await?;
        let rep_map: serde_json::Map<String, Value> = faction_ids
            .iter()
            .map(|fid| {
                let rep = if fid == faction_id { 70 } else { 30 };
                (fid.clone(), Value::Number(rep.into()))
            })
            .collect();

        sqlx::query(
            "INSERT INTO ships
               (name, class, location_id, location_name, system_id,
                universe_offset_x, universe_offset_y,
                cargo_capacity, fuel, fuel_capacity, fuel_consumption_rate,
                speed_modifier, credits, faction_id, faction_reputation,
                size, fitting, progression)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18)",
        )
        .bind(&name)
        .bind(class)
        .bind(loc_id)
        .bind(&loc_name)
        .bind(sys.get("id").and_then(|v| v.as_str()).unwrap_or(sys_name))
        .bind(offset.0)
        .bind(offset.1)
        .bind(cargo_cap as i64)
        .bind(fuel_cap)
        .bind(fuel_cap)
        .bind(fuel_rate)
        .bind(speed)
        .bind(credits)
        .bind(faction_id)
        .bind(Value::Object(rep_map).to_string())
        .bind(size_str)
        .bind(fitting_json)
        .bind(progression_json)
        .execute(pool)
        .await?;
    }

    // --- 7. Populations ---
    for pop in data["populations"].as_array().unwrap_or(&vec![]) {
        let label = str_field(pop, "label")?;
        let exists: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM populations WHERE label = ?1")
                .bind(&label)
                .fetch_one(pool)
                .await?;
        if exists > 0 {
            continue;
        }

        // "facility_id" in JSON = location name
        let loc_name = str_field(pop, "facility_id")?;
        let loc_id = match location_db_id.get(&loc_name) {
            Some(&id) => id,
            None => continue,
        };
        let fac_id: Option<i64> = sqlx::query_scalar(
            "SELECT id FROM facilities WHERE location_id = ?1 LIMIT 1",
        )
        .bind(loc_id)
        .fetch_optional(pool)
        .await?;

        let fac_id = match fac_id {
            Some(id) => id,
            None => continue,
        };

        let consumption = pop.get("consumption").cloned().unwrap_or_default();
        let prod_commodity = pop.get("production_commodity").and_then(|v| v.as_str());

        sqlx::query(
            "INSERT INTO populations
               (label, demographic, facility_id, facility_location, faction_id,
                population_count, total_wealth, food_satisfaction, consumption,
                production_commodity, production_amount)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)",
        )
        .bind(&label)
        .bind(pop.get("demographic").and_then(|v| v.as_str()).unwrap_or("workers"))
        .bind(fac_id)
        .bind(&loc_name)
        .bind(pop.get("faction_id").and_then(|v| v.as_str()).unwrap_or(""))
        .bind(pop.get("population_count").and_then(|v| v.as_i64()).unwrap_or(10_000))
        .bind(pop.get("total_wealth").and_then(|v| v.as_i64()).unwrap_or(500_000))
        .bind(pop.get("food_satisfaction").and_then(|v| v.as_i64()).unwrap_or(50))
        .bind(consumption.to_string())
        .bind(prod_commodity)
        .bind(pop.get("production_amount").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32)
        .execute(pool)
        .await?;
    }

    Ok(())
}

fn str_field(v: &Value, key: &str) -> Result<String> {
    v.get(key)
        .and_then(|x| x.as_str())
        .map(|s| s.to_string())
        .with_context(|| format!("missing string field '{key}'"))
}
