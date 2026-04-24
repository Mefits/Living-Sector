//! Shared application state for axum handlers.

use crate::{control::ControlCommand, snapshot::SnapshotCache, ws::protocol::ServerMsg};
use sim_core::world::registry::WorldRegistry;
use sqlx::SqlitePool;
use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicBool, AtomicU32, AtomicU64},
    Arc, RwLock,
};
use tokio::sync::{broadcast, mpsc, oneshot};

/// One entry in the global command trace ring buffer. Captures the
/// tick, the ship actor's string id (only ship-originated commands
/// are traced), the variant's stable short label, and a short detail
/// string. Kept small (4 fields, no SimCommand clone) so 1000 entries
/// fit in ~50 KB of RAM.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CommandTraceEntry {
    pub tick: u64,
    pub ship_id: String,
    pub kind: &'static str,
    pub detail: String,
}

/// Camera-attached attention volume. The Godot client sends MoveObserver
/// over the control channel every time the viewport shifts; the LOD
/// phase reads this to set per-agent `AgentLod.divisor`. Multiple
/// observers are merged (nearest wins) which keeps multi-viewport / split
/// screen cheap if we ever want that.
#[derive(Debug, Clone)]
pub struct Observer {
    pub id: String,
    pub x: f32,
    pub y: f32,
    /// "In focus" radius in universe units — agents inside this distance
    /// get divisor 1 (every tick). Outside, divisor scales by tier.
    pub radius: f32,
}

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
    /// Request an on-demand flush from the persistence worker. Admin
    /// save-as sends a oneshot down this channel and awaits the reply
    /// so the VACUUM INTO snapshot is guaranteed-current rather than
    /// up to `sweep_interval` stale.
    pub persist_flush_tx: mpsc::Sender<oneshot::Sender<()>>,
    /// Path to the active SQLite file, populated at startup. Admin's
    /// save-as endpoint uses `VACUUM INTO` next to this path.
    pub db_path: Option<String>,
    /// SQLite pool shared with the persistence worker so admin save-as
    /// can issue a `VACUUM INTO` without opening a second connection.
    pub db_pool: Arc<SqlitePool>,
    /// Rolling p50/p99 tick compute time in microseconds. Updated every
    /// 8 ticks by the engine from a 60-tick sliding window. Godot's perf
    /// overlay reads these through `/api/health`.
    pub tick_compute_p50_us: Arc<AtomicU64>,
    pub tick_compute_p99_us: Arc<AtomicU64>,
    /// Attention volumes attached to client viewports. The control-drain
    /// writes here whenever it sees a `MoveObserver`; the tick loop's LOD
    /// phase reads. Kept tiny (usually 1 observer) — RwLock cost is
    /// minimal.
    pub observers: Arc<RwLock<Vec<Observer>>>,
    /// Last LOD divisor distribution (count of agents per tier). Written
    /// by the engine after each `tick_lod_recompute`, read by
    /// `/api/health` for the perf HUD. Atomics — zero-lock read.
    pub lod_d1: Arc<AtomicU64>,
    pub lod_d2: Arc<AtomicU64>,
    pub lod_d5: Arc<AtomicU64>,
    pub lod_d10: Arc<AtomicU64>,
    pub lod_d20: Arc<AtomicU64>,
    pub lod_d50: Arc<AtomicU64>,
    /// Persistent world seed — u64 minted on first boot, round-tripped
    /// through `simulation_state` thereafter. Clients use it to seed
    /// deterministic procgen (e.g. Godot's nebula-cloud generator) so
    /// obvious landmarks stay put across restarts. Exposed via
    /// `/api/health.world_seed`.
    pub world_seed: u64,
    /// Global ring buffer of recent ship-originated commands, for
    /// debug. Capped at [`COMMAND_TRACE_CAPACITY`]; oldest entries
    /// fall off the front. Read by `GET /api/debug/agent/:id/trace`
    /// filtered to the requested ship id. Written by the engine's
    /// command apply loop via `AppState::push_trace_entry`.
    pub command_trace: Arc<RwLock<VecDeque<CommandTraceEntry>>>,
}

/// Size of the global command-trace ring. Sized so 1k entries × ~64 B
/// ≈ 64 KB stays tiny relative to snapshot cache. Increase if
/// debugging consistently loses context before the interesting
/// moment.
pub const COMMAND_TRACE_CAPACITY: usize = 1000;

impl AppState {
    /// Push an entry onto the command-trace ring. Safe to call from
    /// the engine tick loop (brief write-lock) — readers are the
    /// `/api/debug/agent/:id/trace` handler, which holds a brief
    /// read-lock and iterates.
    pub fn push_trace_entry(&self, entry: CommandTraceEntry) {
        if let Ok(mut buf) = self.command_trace.write() {
            if buf.len() >= COMMAND_TRACE_CAPACITY {
                buf.pop_front();
            }
            buf.push_back(entry);
        }
    }

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
