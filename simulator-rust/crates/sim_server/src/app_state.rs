//! Shared application state for axum handlers.

use crate::{control::ControlCommand, snapshot::SnapshotCache, ws::protocol::ServerMsg};
use sim_core::world::registry::WorldRegistry;
use std::sync::{
    atomic::{AtomicBool, AtomicU32, AtomicU64},
    Arc,
};
use tokio::sync::{broadcast, mpsc};

#[derive(Clone)]
pub struct AppState {
    pub snapshots: Arc<SnapshotCache>,
    pub registry: Arc<WorldRegistry>,
    pub tick: Arc<AtomicU64>,
    pub running: Arc<AtomicBool>,
    pub interval_ms: Arc<AtomicU64>,
    /// Current tick resolution (how often the tick loop fires).
    pub ticks_per_second: Arc<AtomicU32>,
    /// Current game-time multiplier, stored as `f32::to_bits`. Read via
    /// `f32::from_bits(self.world_speed_bits.load(...))`.
    pub world_speed_bits: Arc<AtomicU32>,
    pub agent_count: Arc<AtomicU64>,
    pub broadcast_tx: broadcast::Sender<Arc<ServerMsg>>,
    pub control_tx: mpsc::Sender<ControlCommand>,
}

impl AppState {
    pub fn world_speed(&self) -> f32 {
        f32::from_bits(
            self.world_speed_bits
                .load(std::sync::atomic::Ordering::Relaxed),
        )
    }
    pub fn tick_scale(&self) -> f32 {
        let tps = self
            .ticks_per_second
            .load(std::sync::atomic::Ordering::Relaxed)
            .max(1) as f32;
        self.world_speed() / tps
    }
}
