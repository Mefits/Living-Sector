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
    }))
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

    // Godot expects systems[].bodies[] with flat {id, name, type, x, y}
    // entries. Build that from SystemInfo + BodySnapshot + (optional)
    // body→system mapping that we already have in the world registry.
    let systems = build_systems_with_bodies(&state);

    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "running": state.running.load(Ordering::Relaxed),
        "interval_ms": state.interval_ms.load(Ordering::Relaxed),
        "config": {
            "tick_interval_ms": state.interval_ms.load(Ordering::Relaxed),
            "tick_scale": 0.03125_f32,  // world_speed / tps at defaults
        },
        "systems": systems,
        "ships": ships,
        "markets": markets,
        "facilities": facilities,
        "populations": populations,
        "factions": factions,
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

pub async fn factions(State(state): State<AppState>) -> impl IntoResponse {
    let data: Vec<_> = state
        .snapshots
        .factions
        .iter()
        .map(|e| e.value().clone())
        .collect();
    Json(json!({ "data": data }))
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

#[derive(serde::Deserialize)]
pub struct SpeedBody {
    pub interval_ms: u64,
}

pub async fn sim_speed(
    State(state): State<AppState>,
    Json(body): Json<SpeedBody>,
) -> impl IntoResponse {
    let _ = state
        .control_tx
        .send(ControlCommand::SetSpeed {
            interval_ms: body.interval_ms,
        })
        .await;
    Json(json!({ "interval_ms": body.interval_ms }))
}
