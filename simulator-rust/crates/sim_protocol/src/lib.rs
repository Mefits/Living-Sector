//! WebSocket JSON protocol for client ↔ simulator communication.
//!
//! The `type` field discriminates messages on both sides. No Phoenix
//! channel wrapping — plain JSON over WebSocket text frames.
//!
//! This crate intentionally stays dependency-light (just serde +
//! serde_json) so native clients can import it without pulling in
//! the server's heavy dependency graph (tokio, axum, sqlx, etc.).
//! `sim_server` re-exports these types; future Rust clients (e.g.
//! `client-bevy/`) depend on this crate directly, giving us a single
//! source of truth for the wire format.

use serde::{Deserialize, Serialize};

// ============================================================================
// Server → client
// ============================================================================

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMsg {
    /// Sent on client connect and periodically as a heartbeat.
    ServerHello {
        tick: u64,
        running: bool,
        agent_count: usize,
        interval_ms: u64,
        world_speed: f32,
        /// Persistent world seed — clients seed deterministic procgen
        /// (nebula clouds, etc.) off this so visual landmarks stay put
        /// across reconnects and server restarts.
        world_seed: u64,
    },
    /// Positions for all renderable entities. Every tick.
    Positions {
        tick: u64,
        interval_ms: u64,
        entities: Vec<PositionEntry>,
    },
    /// Full ship state deltas. Every ~1s (8 ticks).
    ShipStates {
        tick: u64,
        ships: Vec<serde_json::Value>,
    },
    /// Market snapshots. Every ~2s (16 ticks).
    MarketStates {
        tick: u64,
        markets: Vec<serde_json::Value>,
    },
    /// Facility snapshots. Every ~2s (16 ticks). Clients use this to
    /// render dock occupancy (count of `docked_ships`), fuel reserves,
    /// condition and faction ownership on stations.
    FacilityStates {
        tick: u64,
        facilities: Vec<serde_json::Value>,
    },
    /// Population snapshots. Every ~2s (16 ticks). Clients read
    /// `population_count`, `overall_sentiment`, `food_satisfaction`
    /// for colony health indicators.
    PopulationStates {
        tick: u64,
        populations: Vec<serde_json::Value>,
    },
    /// Faction snapshots. Every ~4s (32 ticks) — they change slowly.
    /// Clients read `treasury` for the faction ledger and show active
    /// subsidy counts.
    FactionStates {
        tick: u64,
        factions: Vec<serde_json::Value>,
    },
    /// Episodic events — ship docked, contract delivered, facility
    /// abandoned, subsidy posted, passengers arrived. Sent each tick
    /// only if the buffer is non-empty. HUD toasts / tickers subscribe.
    Events {
        tick: u64,
        events: Vec<serde_json::Value>,
    },
    /// Full contract board snapshot. Every 32 ticks (~4 s). Contracts
    /// panel reads posted/accepted/delivered contracts.
    ContractStates {
        tick: u64,
        contracts: Vec<serde_json::Value>,
    },
    /// Reply to get_agent / get_snapshot requests.
    AgentState {
        id: String,
        data: serde_json::Value,
    },
    /// Reply to sim_control commands. `world_speed` + `interval_ms`
    /// let client HUDs reflect the current pace after
    /// pause/resume/speed changes without a separate `/api/health`
    /// request.
    SimControlAck {
        action: String,
        tick: u64,
        running: bool,
        world_speed: f32,
        interval_ms: u64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PositionEntry {
    pub id: String,
    pub x: f32,
    pub y: f32,
    #[serde(rename = "type")]
    pub kind: String,
}

// ============================================================================
// Client → server
// ============================================================================

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMsg {
    Hello { client_id: Option<String> },
    GetAgent { id: String },
    GetSnapshot { agent_type: String },
    MoveObserver { id: String, x: f32, y: f32, radius: f32 },
    SimControl(SimControl),
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum SimControl {
    Pause,
    Resume,
    /// Change tick resolution (client smoothness) independently of speed.
    SetTicksPerSecond { tps: u32 },
    /// Change game-time multiplier (gameplay pace) independently of resolution.
    SetWorldSpeed { world_speed: f32 },
    GetTick,
}
