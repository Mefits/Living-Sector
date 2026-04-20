//! Shared application state for axum handlers.

use crate::{control::ControlCommand, snapshot::SnapshotCache, ws::protocol::ServerMsg};
use std::sync::{
    atomic::{AtomicBool, AtomicU64},
    Arc,
};
use tokio::sync::{broadcast, mpsc};

#[derive(Clone)]
pub struct AppState {
    pub snapshots: Arc<SnapshotCache>,
    pub tick: Arc<AtomicU64>,
    pub running: Arc<AtomicBool>,
    pub interval_ms: Arc<AtomicU64>,
    pub agent_count: Arc<AtomicU64>,
    pub broadcast_tx: broadcast::Sender<Arc<ServerMsg>>,
    pub control_tx: mpsc::Sender<ControlCommand>,
}
