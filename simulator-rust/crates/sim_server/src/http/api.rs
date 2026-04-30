//! HTTP API endpoints for health, inspection, and sim control.

use crate::{app_state::AppState, control::ControlCommand};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde_json::json;
use std::sync::atomic::Ordering;

pub async fn health(State(state): State<AppState>) -> impl IntoResponse {
    Json(json!({
        "status": "ok",
        "tick": state.tick.load(Ordering::Relaxed),
        "running": state.running.load(Ordering::Relaxed),
        "agent_count": state.agent_count.load(Ordering::Relaxed),
        "interval_ms": state.interval_ms.load(Ordering::Relaxed),
        "ticks_per_second": state.ticks_per_second.load(Ordering::Relaxed),
        "world_speed": state.world_speed(),
        "tick_scale": state.tick_scale(),
        // Persistent world seed — clients use this to seed deterministic
        // procgen (e.g. Godot nebula clouds) so visual landmarks stay
        // put across restarts. Minted on first boot, round-tripped
        // through `simulation_state.world_seed` thereafter.
        "world_seed": state.world_seed,
        // Rolling perf window (updated every 8 ticks by the engine).
        "perf": {
            "tick_compute_p50_us": state.tick_compute_p50_us.load(Ordering::Relaxed),
            "tick_compute_p99_us": state.tick_compute_p99_us.load(Ordering::Relaxed),
            // Last-tick per-phase microsecond breakdown. Single sample —
            // poll over a window if you want stable readings. Useful for
            // localizing the dominant phase under stress.
            "phase_us": state
                .phase_breakdown_us
                .read()
                .ok()
                .map(|bd| serde_json::to_value(*bd).unwrap_or(serde_json::Value::Null))
                .unwrap_or(serde_json::Value::Null),
            // Spatial-LOD tier distribution (updated every 50 base-ticks by
            // the LOD recompute phase). Counts agents that carry an
            // AgentLod — ships always, facilities/populations carry the
            // component but their phases don't gate yet.
            "lod": {
                "d1": state.lod_d1.load(Ordering::Relaxed),
                "d2": state.lod_d2.load(Ordering::Relaxed),
                "d5": state.lod_d5.load(Ordering::Relaxed),
                "d10": state.lod_d10.load(Ordering::Relaxed),
                "d20": state.lod_d20.load(Ordering::Relaxed),
                "d50": state.lod_d50.load(Ordering::Relaxed),
            },
        },
    }))
}

/// POST /api/sim/step — advance the tick loop by N forced ticks even if
/// paused. Useful for slow-motion debugging. Body: `{ticks: u32}`.
#[derive(serde::Deserialize)]
pub struct StepBody {
    #[serde(default = "default_step_ticks")]
    pub ticks: u32,
}

fn default_step_ticks() -> u32 {
    1
}

pub async fn sim_step(
    State(state): State<AppState>,
    Json(body): Json<StepBody>,
) -> impl IntoResponse {
    if body.ticks == 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "ticks must be >= 1"})),
        );
    }
    if body.ticks > 1000 {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "ticks must be <= 1000"})),
        );
    }
    if state
        .control_tx
        .send(ControlCommand::Step { ticks: body.ticks })
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
            "ticks": body.ticks,
            "tick": state.tick.load(Ordering::Relaxed),
        })),
    )
}

pub async fn report(State(state): State<AppState>) -> impl IntoResponse {
    let ships: Vec<_> = state.snapshots.ships.iter().map(|e| e.value().clone()).collect();
    let markets: Vec<_> = state.snapshots.markets.iter().map(|e| e.value().clone()).collect();
    let facilities: Vec<_> = state
        .snapshots
        .facilities
        .iter()
        .map(|e| e.value().clone())
        .collect();
    let populations: Vec<_> = state
        .snapshots
        .populations
        .iter()
        .map(|e| e.value().clone())
        .collect();
    let factions: Vec<_> = state
        .snapshots
        .factions
        .iter()
        .map(|e| e.value().clone())
        .collect();
    let construction_sites: Vec<_> = state
        .snapshots
        .construction_sites
        .iter()
        .map(|e| e.value().clone())
        .collect();

    // Godot expects systems[].bodies[] with flat {id, name, type, x, y}
    // entries. Build that from SystemInfo + BodySnapshot + (optional)
    // body→system mapping that we already have in the world registry.
    let systems = build_systems_with_bodies(&state);

    let tps = state.ticks_per_second.load(Ordering::Relaxed);
    let ws = state.world_speed();
    let interval = state.interval_ms.load(Ordering::Relaxed);
    let tick_scale = state.tick_scale();

    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "running": state.running.load(Ordering::Relaxed),
        "interval_ms": interval,
        "world_seed": state.world_seed,
        "config": {
            "ticks_per_second": tps,
            "world_speed": ws,
            "tick_scale": tick_scale,
            "tick_interval_ms": interval,
        },
        "perf": {
            "tick_compute_p50_us": state.tick_compute_p50_us.load(Ordering::Relaxed),
            "tick_compute_p99_us": state.tick_compute_p99_us.load(Ordering::Relaxed),
            "lod": {
                "d1": state.lod_d1.load(Ordering::Relaxed),
                "d2": state.lod_d2.load(Ordering::Relaxed),
                "d5": state.lod_d5.load(Ordering::Relaxed),
                "d10": state.lod_d10.load(Ordering::Relaxed),
                "d20": state.lod_d20.load(Ordering::Relaxed),
                "d50": state.lod_d50.load(Ordering::Relaxed),
            },
        },
        "systems": systems,
        "ships": ships,
        "markets": markets,
        "facilities": facilities,
        "populations": populations,
        "factions": factions,
        "construction_sites": construction_sites,
    }))
}

/// Build the `systems` array expected by Godot's `load_world_snapshot`:
/// each entry has `{id, name, offset_x, offset_y, bodies: [{id, name, type, x, y}]}`.
fn build_systems_with_bodies(state: &AppState) -> Vec<serde_json::Value> {
    use sim_core::agents::celestial_body::BodySnapshot;

    // Index body snapshots by their body_id for quick lookup
    let body_snaps: std::collections::HashMap<String, BodySnapshot> = state
        .snapshots
        .bodies
        .iter()
        .map(|e| (e.key().clone(), e.value().clone()))
        .collect();

    // We don't track body→system cleanly yet — each body's star_system_id
    // is on BodyIdentity (in hecs world), not on the snapshot. The
    // registry's locations carry celestial_body_id → body, but we need the
    // inverse (body → system). For now, group every body under every
    // system by matching universe_offset, which is deterministic enough
    // for the 3-system seed (Sol=0,0; AC=20,5; Tau Ceti=40,-10).
    //
    // Tolerance-based match handles f32 jitter.
    fn matches_offset(body_universe: (f32, f32), body_local: (f32, f32), sys_offset: (f32, f32)) -> bool {
        let expected = (body_local.0 + sys_offset.0, body_local.1 + sys_offset.1);
        (expected.0 - body_universe.0).abs() < 0.01 && (expected.1 - body_universe.1).abs() < 0.01
    }

    let mut systems = Vec::new();
    for sys in state.registry.systems.values() {
        let mut bodies_in_sys: Vec<serde_json::Value> = Vec::new();
        for (body_id, snap) in &body_snaps {
            let universe = (snap.universe_position.x, snap.universe_position.y);
            let local = (snap.position.x, snap.position.y);
            if matches_offset(universe, local, sys.universe_offset) {
                bodies_in_sys.push(json!({
                    "id": body_id,
                    "name": snap.name,
                    "type": snap.body_type,
                    "x": snap.universe_position.x,
                    "y": snap.universe_position.y,
                    "position": snap.universe_position,  // both shapes for compat
                    "current_angle": snap.current_angle,
                    "orbit_radius": snap.orbit_radius,
                    "orbit_period": snap.orbit_period,
                    "biome": snap.biome,
                    // Bundle D: territorial control surfaces in the
                    // body listing so external tools (sim-review,
                    // archived Godot client) can read it without an
                    // extra request.
                    "controlling_faction": snap.controlling_faction,
                    "contested": snap.contested,
                }));
            }
        }

        // System id — Godot expects "system-<slug>" style. Build from name.
        let sys_id = format!("system-{}", sys.name.to_lowercase().replace(' ', "-"));
        systems.push(json!({
            "id": sys_id,
            "name": sys.name,
            "offset_x": sys.universe_offset.0,
            "offset_y": sys.universe_offset.1,
            "bodies": bodies_in_sys,
        }));
    }
    systems
}

pub async fn ships(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state.snapshots.ships.iter().map(|e| e.value().clone()).collect();
    Json(json!({ "data": data }))
}

pub async fn markets(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state.snapshots.markets.iter().map(|e| e.value().clone()).collect();
    Json(json!({ "data": data }))
}

/// Phase 20d (persistent trends): time-series review endpoint. Returns
/// the `trend_samples` from this market's `MarketSnapshot` (which
/// flattens the in-memory `MarketHistory.trend_samples` ring on every
/// snapshot rebuild). For raw query power against the full persisted
/// history, query the table directly:
///
/// ```sh
/// sqlite3 sim.db 'SELECT tick, commodity, price, supply
///                 FROM market_trend_samples
///                 WHERE market_id = (SELECT id FROM markets
///                                    WHERE facility_location = "earth-station")
///                 ORDER BY tick DESC LIMIT 100'
/// ```
pub async fn market_trends(
    State(state): State<AppState>,
    axum::extract::Path(location): axum::extract::Path<String>,
) -> impl IntoResponse {
    // Match by facility_location first (the canonical id), fall
    // through to the synthesised `market-<location>` form so callers
    // can hit the endpoint with either shape.
    let market = state
        .snapshots
        .markets
        .iter()
        .find(|e| {
            let v = e.value();
            v.facility_location == location || v.id == format!("market-{location}")
        })
        .map(|e| e.value().clone());

    match market {
        Some(m) => Json(json!({
            "location": m.facility_location,
            "sample_count": m.trend_samples.len(),
            "samples": m.trend_samples,
        })),
        None => Json(json!({ "error": "market not found", "location": location })),
    }
}

pub async fn facilities(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .facilities
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({ "data": data }))
}

pub async fn populations(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .populations
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({ "data": data }))
}

/// Phase 19g: ship retirement ledger. Every ship that's been
/// decommissioned — whether admin-killed or (future) auto-recycled
/// after strike-out — has a row here. Sorted newest-first, capped
/// at 200 to keep the payload bounded.
pub async fn retirements(State(state): State<AppState>) -> impl IntoResponse {
    use sqlx::Row;
    let rows = sqlx::query(
        "SELECT agent_id, name, class, faction_id, final_location,
                final_credits, final_crew_morale, final_fuel_pct,
                broke_strikes, hoard_strikes, retired_at_tick,
                reason, retired_at
         FROM retired_ships
         ORDER BY retired_at_tick DESC, id DESC
         LIMIT 200",
    )
    .fetch_all(&*state.db_pool)
    .await;

    let data = match rows {
        Ok(rows) => rows
            .into_iter()
            .map(|r| {
                json!({
                    "agent_id": r.get::<String, _>("agent_id"),
                    "name": r.get::<String, _>("name"),
                    "class": r.get::<String, _>("class"),
                    "faction_id": r.get::<String, _>("faction_id"),
                    "final_location": r.get::<String, _>("final_location"),
                    "final_credits": r.get::<i64, _>("final_credits"),
                    "final_crew_morale": r.get::<i64, _>("final_crew_morale"),
                    "final_fuel_pct": r.get::<i64, _>("final_fuel_pct"),
                    "broke_strikes": r.get::<i64, _>("broke_strikes"),
                    "hoard_strikes": r.get::<i64, _>("hoard_strikes"),
                    "retired_at_tick": r.get::<i64, _>("retired_at_tick"),
                    "reason": r.get::<String, _>("reason"),
                    "retired_at": r.get::<String, _>("retired_at"),
                })
            })
            .collect::<Vec<_>>(),
        Err(e) => {
            return (
                axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": format!("{e}")})),
            )
                .into_response();
        }
    };
    Json(json!({ "data": data })).into_response()
}

/// Phase 19c: in-flight construction sites the demand analyzer has
/// started. Godot polls this on boot (and gets live updates via
/// positions + tick events) to render scaffolds for each one.
pub async fn construction_sites(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .construction_sites
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({ "data": data }))
}

pub async fn factions(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .factions
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({ "data": data }))
}

/// Bundle A: inter-faction standing + treaty state matrix. One entry
/// per canonical pair. Returns an empty list when the sim hasn't
/// generated any relations yet (fresh world, no deliveries).
pub async fn factions_relations(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .relations
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "data": data,
    }))
}

pub async fn contracts(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<serde_json::Value> = state
        .snapshots
        .contracts
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "data": data,
    }))
}

/// `GET /api/observers` — current attention volumes driving the LOD phase.
/// Useful for Godot's debug HUD ("which viewports is the sim tracking?")
/// and for test scripts to check that MoveObserver is landing.
pub async fn observers(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<serde_json::Value> = state
        .observers
        .read()
        .map(|o| {
            o.iter()
                .map(|ob| {
                    json!({
                        "id": ob.id,
                        "x": ob.x,
                        "y": ob.y,
                        "radius": ob.radius,
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "data": data,
    }))
}

pub async fn positions(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .positions
        .iter()
        .map(|e| json!({ "id": e.key().clone(), "x": e.value().0, "y": e.value().1 }))
        .collect();
    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "data": data,
    }))
}

/// `GET /api/debug/agent/:id/trace` — returns the most recent
/// ship-originated commands captured by the engine's trace ring,
/// filtered to the requested ship id. Default limit 40; query-param
/// `?limit=N` overrides (clamped 1..=200). Oldest-first ordering so
/// the panel reads top-to-bottom in tick order.
///
/// Entries carry `{tick, kind, detail}` — the ship id is implied by
/// the URL path. Returns `{data: []}` for unknown ids; never 404.
pub async fn agent_command_trace(
    Path(id): Path<String>,
    axum::extract::Query(params): axum::extract::Query<
        std::collections::HashMap<String, String>,
    >,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let limit: usize = params
        .get("limit")
        .and_then(|s| s.parse().ok())
        .unwrap_or(40)
        .clamp(1, 200);
    let entries: Vec<serde_json::Value> = if let Ok(buf) = state.command_trace.read() {
        buf.iter()
            .filter(|e| e.ship_id == id)
            .rev()
            .take(limit)
            .map(|e| {
                json!({
                    "tick": e.tick,
                    "kind": e.kind,
                    "detail": e.detail,
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect()
    } else {
        Vec::new()
    };
    Json(json!({ "data": entries }))
}

pub async fn agent_by_id(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    // Try each cache in order
    if let Some(e) = state.snapshots.ships.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    if let Some(e) = state.snapshots.markets.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    if let Some(e) = state.snapshots.facilities.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    if let Some(e) = state.snapshots.populations.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    if let Some(e) = state.snapshots.factions.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    if let Some(e) = state.snapshots.bodies.get(&id) {
        return (StatusCode::OK, Json(json!(e.value()))).into_response();
    }
    (StatusCode::NOT_FOUND, Json(json!({ "error": "not found" }))).into_response()
}

pub async fn sim_pause(State(state): State<AppState>) -> impl IntoResponse {
    let _ = state.control_tx.send(ControlCommand::Pause).await;
    Json(json!({ "status": "paused", "tick": state.tick.load(Ordering::Relaxed) }))
}

pub async fn sim_resume(State(state): State<AppState>) -> impl IntoResponse {
    let _ = state.control_tx.send(ControlCommand::Resume).await;
    Json(json!({ "status": "running", "tick": state.tick.load(Ordering::Relaxed) }))
}

/// `POST /api/sim/speed` accepts either or both of:
/// - `world_speed: f32` — game-time multiplier (0.0..=16.0)
/// - `ticks_per_second: u32` — tick resolution (1..=60)
///
/// Supplying both applies them independently — the two knobs don't touch
/// each other.
#[derive(serde::Deserialize, Default)]
pub struct SpeedBody {
    pub world_speed: Option<f32>,
    pub ticks_per_second: Option<u32>,
}

pub async fn sim_speed(
    State(state): State<AppState>,
    Json(body): Json<SpeedBody>,
) -> impl IntoResponse {
    if let Some(ws) = body.world_speed {
        let _ = state
            .control_tx
            .send(ControlCommand::SetWorldSpeed { world_speed: ws })
            .await;
    }
    if let Some(tps) = body.ticks_per_second {
        let _ = state
            .control_tx
            .send(ControlCommand::SetTicksPerSecond { tps })
            .await;
    }
    // The tick loop applies commands on its next iteration (~1 tick).
    // Return what the caller sent plus the current state.
    Json(json!({
        "applied": {
            "world_speed": body.world_speed,
            "ticks_per_second": body.ticks_per_second,
        },
        "current": {
            "world_speed": state.world_speed(),
            "ticks_per_second": state.ticks_per_second.load(Ordering::Relaxed),
            "tick_scale": state.tick_scale(),
            "interval_ms": state.interval_ms.load(Ordering::Relaxed),
        }
    }))
}
