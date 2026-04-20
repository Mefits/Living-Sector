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
    let bodies: Vec<_> = state.snapshots.bodies.iter().map(|e| e.value().clone()).collect();

    Json(json!({
        "tick": state.tick.load(Ordering::Relaxed),
        "running": state.running.load(Ordering::Relaxed),
        "interval_ms": state.interval_ms.load(Ordering::Relaxed),
        "ships": ships,
        "markets": markets,
        "facilities": facilities,
        "populations": populations,
        "factions": factions,
        "bodies": bodies,
    }))
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
