//! Admin HTTP endpoints — the "god-mode" surface Godot's debug UI calls.
//!
//! These port the Elixir admin API 1:1 in shape: same URL paths, same JSON
//! payloads. Each handler does the minimum mutation needed so the Godot
//! client stops seeing 404s; fully-fleshed-out spawn logic (recipes, crew
//! defaults, etc.) can layer on top once Phase 12 covers observability.
//!
//! **Safety**: these endpoints mutate live simulation state. The tick loop
//! owns `AgentStore`, so we funnel mutations through an `AdminCommand` on
//! the control channel and reply once the engine has applied it. This is
//! the same pattern pause/resume/speed already use — no lock contention.
//!
//! ## Routes
//!
//! | Method | Path | Purpose |
//! |---|---|---|
//! | POST | `/api/admin/ships` | Spawn a ship (body is JSON) |
//! | DELETE | `/api/admin/ships/:id` | Decommission a ship by agent id |
//! | POST | `/api/admin/facilities` | Spawn a facility |
//! | DELETE | `/api/admin/facilities/:id` | Remove a facility by agent id |
//! | POST | `/api/admin/markets/:location/supply` | Adjust market supply |
//! | POST | `/api/admin/save` | Flush the persistence buffer now |
//! | POST | `/api/admin/save-as` | Snapshot DB to a named file |

use crate::app_state::AppState;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sim_core::economy::commodities::Commodity;
use std::sync::atomic::Ordering;

#[derive(Debug, Deserialize)]
pub struct AdminCreateShipReq {
    pub class: String,
    pub faction_id: String,
    pub location: String,
    pub name: Option<String>,
    #[serde(default)]
    pub credits: Option<i64>,
}

/// POST /api/admin/ships — INSERTs a ship row, then asks the engine to
/// spawn the matching hecs entity on its next tick. Returns 201 with
/// `{id, db_id}` so the client can eagerly seed its local state.
///
/// Validation: `class` must exist in `sim_core::simulation::config`,
/// `location` must resolve to a known locations row.
pub async fn create_ship(
    State(state): State<AppState>,
    Json(body): Json<AdminCreateShipReq>,
) -> (StatusCode, Json<Value>) {
    use sqlx::Row;

    // --- Validate class ---
    let class_cfg = match sim_core::simulation::config::ship_class(&body.class) {
        Some(c) => c,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": format!("unknown class: {}", body.class),
                })),
            );
        }
    };

    // --- Resolve location + body + system in one join. Schema:
    //   locations(id, name, celestial_body_id → celestial_bodies.id)
    //   celestial_bodies(id, body_id, current_angle, orbit_radius,
    //     star_system_id → star_systems.id)
    //   star_systems(id, name, universe_offset_x, universe_offset_y)
    let loc_row = match sqlx::query(
        "SELECT l.id AS loc_id, l.name AS loc_name,
                b.body_id, b.current_angle, b.orbit_radius,
                s.id AS sys_id, s.name AS sys_name,
                s.universe_offset_x, s.universe_offset_y
         FROM locations l
         JOIN celestial_bodies b ON b.id = l.celestial_body_id
         JOIN star_systems s ON s.id = b.star_system_id
         WHERE l.name = ?1
         LIMIT 1",
    )
    .bind(&body.location)
    .fetch_optional(&*state.db_pool)
    .await
    {
        Ok(Some(r)) => r,
        Ok(None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": format!("unknown location: {}", body.location)})),
            );
        }
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": format!("db error: {e}")})),
            );
        }
    };
    let location_id: i64 = loc_row.get("loc_id");
    let location_name: String = loc_row.get("loc_name");
    let system_id: String = loc_row.get::<String, _>("sys_name");
    let offset_x = loc_row.get::<f64, _>("universe_offset_x") as f32;
    let offset_y = loc_row.get::<f64, _>("universe_offset_y") as f32;
    let angle = loc_row.get::<f64, _>("current_angle") as f32;
    let radius = loc_row.get::<f64, _>("orbit_radius") as f32;
    let rad = angle.to_radians();
    let body_x = radius * rad.cos() + offset_x;
    let body_y = radius * rad.sin() + offset_y;

    // --- Build a unique name for the new ship ---
    let name = body.name.clone().unwrap_or_else(|| {
        format!(
            "Admin Ship {:x}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0)
        )
    });
    let credits = body.credits.unwrap_or(5000);

    // --- Insert ship row, get db_id back ---
    let insert_result = sqlx::query(
        "INSERT INTO ships
           (name, class, location_id, location_name, system_id,
            universe_offset_x, universe_offset_y, position_x, position_y,
            cargo_capacity, fuel, fuel_capacity, fuel_consumption_rate,
            speed_modifier, credits, faction_id, faction_reputation)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17)",
    )
    .bind(&name)
    .bind(&body.class)
    .bind(location_id)
    .bind(&location_name)
    .bind(&system_id)
    .bind(offset_x as f64)
    .bind(offset_y as f64)
    .bind(body_x as f64)
    .bind(body_y as f64)
    .bind(class_cfg.cargo_capacity as i64)
    .bind(class_cfg.fuel_capacity as f64)
    .bind(class_cfg.fuel_capacity as f64)
    .bind(class_cfg.fuel_consumption_base as f64)
    .bind(class_cfg.speed_modifier as f64)
    .bind(credits)
    .bind(&body.faction_id)
    .bind("{}")
    .execute(&*state.db_pool)
    .await;
    let db_id = match insert_result {
        Ok(r) => r.last_insert_rowid(),
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": format!("insert failed: {e}")})),
            );
        }
    };
    let agent_id = format!("ship-admin-{}", db_id);

    // --- Dispatch spawn to the engine ---
    let payload = crate::control::AdminSpawnShipPayload {
        db_id,
        agent_id: agent_id.clone(),
        name: name.clone(),
        class: body.class.clone(),
        location_name: location_name.clone(),
        faction_id: body.faction_id.clone(),
        universe_offset: (offset_x, offset_y),
        position: (body_x, body_y),
        credits,
    };
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminSpawnShip(payload))
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }

    (
        StatusCode::CREATED,
        Json(json!({
            "id": agent_id,
            "db_id": db_id,
            "name": name,
            "class": body.class,
            "location": location_name,
            "faction_id": body.faction_id,
            "credits": credits,
            "position": {"x": body_x, "y": body_y},
        })),
    )
}

/// DELETE /api/admin/ships/:id — dispatches an AdminRemoveShip via the
/// control channel. Engine resolves the string id to an Entity and
/// despawns it atomically on the next tick.
pub async fn destroy_ship(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> (StatusCode, Json<Value>) {
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminRemoveShip { id: id.clone() })
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }
    (
        StatusCode::NO_CONTENT,
        Json(json!({"status": "scheduled", "id": id})),
    )
}

#[derive(Debug, Deserialize)]
pub struct AdminCreateFacilityReq {
    pub name: String,
    pub facility_type: String,
    pub body_id: String,
    pub faction_id: String,
    /// Location-name slug the new facility lives at. If omitted, we pick
    /// the first location associated with `body_id`.
    pub location: Option<String>,
    #[serde(default)]
    pub docking_capacity: Option<u32>,
    #[serde(default)]
    pub credits: Option<i64>,
}

/// POST /api/admin/facilities — INSERTs a facility row and asks the
/// engine to spawn the matching hecs entity. Returns 201 with ids.
pub async fn create_facility(
    State(state): State<AppState>,
    Json(body): Json<AdminCreateFacilityReq>,
) -> (StatusCode, Json<Value>) {
    use sqlx::Row;

    // Resolve location. Schema: locations.celestial_body_id → bodies.id,
    // bodies.body_id is the string slug like "earth". If `body.location`
    // was provided, use its name; otherwise pick the first location
    // whose body has the requested slug.
    let loc_row = match body.location.as_deref() {
        Some(name) => {
            sqlx::query(
                "SELECT l.id AS loc_id, l.name AS loc_name, b.body_id AS slug
                 FROM locations l
                 JOIN celestial_bodies b ON b.id = l.celestial_body_id
                 WHERE l.name = ?1
                 LIMIT 1",
            )
            .bind(name)
            .fetch_optional(&*state.db_pool)
            .await
        }
        None => {
            sqlx::query(
                "SELECT l.id AS loc_id, l.name AS loc_name, b.body_id AS slug
                 FROM locations l
                 JOIN celestial_bodies b ON b.id = l.celestial_body_id
                 WHERE b.body_id = ?1
                 LIMIT 1",
            )
            .bind(&body.body_id)
            .fetch_optional(&*state.db_pool)
            .await
        }
    };
    let loc_row = match loc_row {
        Ok(Some(r)) => r,
        Ok(None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "location not found for given body/location"})),
            );
        }
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": format!("db error: {e}")})),
            );
        }
    };
    let location_id: i64 = loc_row.get("loc_id");
    let location_name: String = loc_row.get("loc_name");
    let resolved_body_id: String = loc_row.get("slug");

    let docking_capacity = body.docking_capacity.unwrap_or(4);
    let credits = body.credits.unwrap_or(10_000);
    let reputation: i32 = 50;
    let condition: f32 = 1.0;

    let insert_result = sqlx::query(
        "INSERT INTO facilities
           (name, facility_type, location_id, location_name, body_id, faction_id,
            docking_capacity, services, condition, reputation, credits,
            reserves, docked_ships)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)",
    )
    .bind(&body.name)
    .bind(&body.facility_type)
    .bind(location_id)
    .bind(&location_name)
    .bind(&resolved_body_id)
    .bind(&body.faction_id)
    .bind(docking_capacity as i64)
    .bind("[\"market\"]")
    .bind(condition as f64)
    .bind(reputation as i64)
    .bind(credits)
    .bind("{}")
    .bind("[]")
    .execute(&*state.db_pool)
    .await;
    let db_id = match insert_result {
        Ok(r) => r.last_insert_rowid(),
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": format!("insert failed: {e}")})),
            );
        }
    };
    let slug = body
        .name
        .to_lowercase()
        .replace(|c: char| !c.is_alphanumeric(), "-");
    let agent_id = format!("facility-{location_name}-{slug}");

    let payload = crate::control::AdminSpawnFacilityPayload {
        db_id,
        agent_id: agent_id.clone(),
        name: body.name.clone(),
        facility_type: body.facility_type.clone(),
        body_id: resolved_body_id.clone(),
        faction_id: body.faction_id.clone(),
        location_name: location_name.clone(),
        location_id,
        docking_capacity,
        condition,
        reputation,
        credits,
    };
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminSpawnFacility(payload))
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }

    (
        StatusCode::CREATED,
        Json(json!({
            "id": agent_id,
            "db_id": db_id,
            "name": body.name,
            "facility_type": body.facility_type,
            "body_id": resolved_body_id,
            "location": location_name,
            "faction_id": body.faction_id,
            "docking_capacity": docking_capacity,
        })),
    )
}

pub async fn destroy_facility(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> (StatusCode, Json<Value>) {
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminRemoveFacility { id: id.clone() })
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }
    (
        StatusCode::NO_CONTENT,
        Json(json!({"status": "scheduled", "id": id})),
    )
}

#[derive(Debug, Deserialize)]
pub struct AdminSupplyDeltaReq {
    /// commodity → delta. Positive grows supply, negative drains.
    #[serde(default)]
    pub deltas: std::collections::HashMap<String, f32>,
    /// Alternate single-commodity flow used by some Godot screens.
    pub commodity: Option<String>,
    pub delta: Option<f32>,
}

/// POST /api/admin/markets/:location/supply — nudge a market's supply.
/// Accepts either `{"deltas": {"food": 500, "fuel": -100}}` or the
/// single-commodity shorthand `{"commodity": "food", "delta": 500}`.
pub async fn market_supply_delta(
    State(state): State<AppState>,
    Path(location): Path<String>,
    Json(body): Json<AdminSupplyDeltaReq>,
) -> (StatusCode, Json<Value>) {
    let mut normalized: Vec<(Commodity, f32)> = Vec::new();
    for (commodity_name, delta) in body.deltas.iter() {
        if let Some(c) = Commodity::parse(commodity_name) {
            normalized.push((c, *delta));
        }
    }
    if let (Some(name), Some(delta)) = (body.commodity, body.delta) {
        if let Some(c) = Commodity::parse(&name) {
            normalized.push((c, delta));
        }
    }
    if normalized.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "no valid deltas supplied"})),
        );
    }
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminMarketSupplyDelta {
            location: location.clone(),
            deltas: normalized.clone(),
        })
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }
    (
        StatusCode::OK,
        Json(json!({
            "status": "scheduled",
            "location": location,
            "applied_count": normalized.len(),
        })),
    )
}

#[derive(Debug, Deserialize)]
pub struct AdminGrantXpReq {
    pub amount: u32,
}

/// POST /api/admin/ships/:id/grant-xp — grant Phase-18d ship XP
/// directly. Cascades level-ups and banks retrofit points. For smoke
/// tests and god-mode nudges.
pub async fn grant_ship_xp(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<AdminGrantXpReq>,
) -> (StatusCode, Json<Value>) {
    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminGrantShipXp {
            id: id.clone(),
            amount: body.amount,
        })
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }
    (
        StatusCode::ACCEPTED,
        Json(json!({
            "status": "scheduled",
            "id": id,
            "amount": body.amount,
        })),
    )
}

#[derive(Debug, Deserialize)]
pub struct AdminRefitShipReq {
    /// Slot name as it appears on the wire: `engine`, `cargo_bay`,
    /// `sensors`, `reactor`, `comms`.
    pub slot: String,
    /// Module slug from the catalog (e.g. `engine_t2`). `null` or missing
    /// clears the slot.
    #[serde(default)]
    pub slug: Option<String>,
    /// When true, the refit routes through the shipyard economy: ship
    /// must be docked at a shipyard with the target slug in stock,
    /// pays [`crate::control::ControlCommand::AdminRefitShip`]'s cost
    /// (debit ship, credit shipyard, decrement stock). When false
    /// (default) the swap is a pure admin override — no economy
    /// interaction. Phase 18c.
    #[serde(default)]
    pub via_shipyard: bool,
}

/// POST /api/admin/ships/:id/refit — swap one subsystem slot on a ship.
///
/// Validates slot name, slug presence in the catalog, and slot match
/// before enqueueing the engine-side swap. Returns 202 so callers know
/// the change will land on the next engine drain (sub-tick latency).
pub async fn refit_ship(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<AdminRefitShipReq>,
) -> (StatusCode, Json<Value>) {
    // --- Resolve slot name --------------------------------------------
    let slot = match body.slot.as_str() {
        "engine" => sim_core::modules::Slot::Engine,
        "cargo_bay" => sim_core::modules::Slot::CargoBay,
        "sensors" => sim_core::modules::Slot::Sensors,
        "reactor" => sim_core::modules::Slot::Reactor,
        "comms" => sim_core::modules::Slot::Comms,
        other => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": format!("unknown slot: {other}")})),
            );
        }
    };

    // --- Validate slug (if provided) ----------------------------------
    if let Some(s) = body.slug.as_deref() {
        match sim_core::modules::get(s) {
            Some(def) if def.slot == slot => {}
            Some(def) => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({
                        "error": format!(
                            "slug {s} belongs to slot {}, not {}",
                            def.slot.as_str(),
                            slot.as_str(),
                        ),
                    })),
                );
            }
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({"error": format!("unknown module slug: {s}")})),
                );
            }
        }
    }

    // When via_shipyard is set, the target slug must be something the
    // economy can actually produce (no tier-1 defaults; those are free
    // and can't be bought). Reject at the HTTP layer so callers get a
    // clean 400 instead of a silent no-op.
    if body.via_shipyard {
        match body.slug.as_deref() {
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({
                        "error": "via_shipyard refit requires a slug (can't purchase an empty slot)",
                    })),
                );
            }
            Some(s) if sim_core::economy::module_production::get(s).is_none() => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({
                        "error": format!(
                            "module {s} is not produced by shipyards (tier-1 default or unknown)",
                        ),
                    })),
                );
            }
            _ => {}
        }
    }

    if state
        .control_tx
        .send(crate::control::ControlCommand::AdminRefitShip {
            id: id.clone(),
            slot,
            slug: body.slug.clone(),
            via_shipyard: body.via_shipyard,
        })
        .await
        .is_err()
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "control channel closed"})),
        );
    }

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "status": "scheduled",
            "id": id,
            "slot": slot.as_str(),
            "slug": body.slug,
            "via_shipyard": body.via_shipyard,
        })),
    )
}

/// POST /api/admin/save — returns the current tick to acknowledge.
/// The persistence worker flushes every 5s automatically; this endpoint
/// is a UI hook that says "yes I heard you." A future pass can wire a
/// blocking flush if the user wants a true synchronous save.
pub async fn save(State(state): State<AppState>) -> (StatusCode, Json<Value>) {
    (
        StatusCode::OK,
        Json(json!({
            "status": "ok",
            "tick": state.tick.load(Ordering::Relaxed),
            "note": "persistence flushes every 5s; state is already being saved",
        })),
    )
}

#[derive(Debug, Deserialize)]
pub struct SaveAsReq {
    pub name: String,
}

/// POST /api/admin/save-as — snapshot the current DB file next to itself
/// with the requested name. Relies on SQLite's VACUUM INTO which is a
/// proper cross-filesystem copy.
pub async fn save_as(
    State(state): State<AppState>,
    Json(body): Json<SaveAsReq>,
) -> (StatusCode, Json<Value>) {
    let sanitized: String = body
        .name
        .trim()
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '_' || *c == '-')
        .collect();
    if sanitized.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "name required (alphanumeric + _-)"})),
        );
    }
    let Some(current_db) = state.db_path.clone() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "db_path unknown"})),
        );
    };
    let parent = std::path::Path::new(&current_db)
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::path::PathBuf::from("."));
    let target = parent.join(format!("{sanitized}.db"));
    let target_str = target.to_string_lossy().to_string();
    // Use VACUUM INTO so SQLite takes care of page locking + integrity.
    let query = format!("VACUUM INTO '{target_str}'");
    match sqlx::query(&query).execute(&*state.db_pool).await {
        Ok(_) => (
            StatusCode::CREATED,
            Json(json!({
                "status": "ok",
                "name": sanitized,
                "path": target_str,
                "tick": state.tick.load(Ordering::Relaxed),
            })),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"error": format!("vacuum into failed: {e}")})),
        ),
    }
}
