//! WebSocket JSON protocol for Godot ↔ simulator communication.
//!
//! The `type` field discriminates messages on both sides. No Phoenix
//! channel wrapping — plain JSON over WebSocket text frames.

use serde::{Deserialize, Serialize};

// ============================================================================
// Server → Godot
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
    /// Reply to get_agent / get_snapshot requests.
    AgentState {
        id: String,
        data: serde_json::Value,
    },
    /// Reply to sim_control commands.
    SimControlAck {
        action: String,
        tick: u64,
        running: bool,
    },
}

#[derive(Debug, Clone, Serialize)]
pub struct PositionEntry {
    pub id: String,
    pub x: f32,
    pub y: f32,
    #[serde(rename = "type")]
    pub kind: &'static str,
}

// ============================================================================
// Godot → Server
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
    /// Legacy: interval_ms → tps mapping. Does NOT change world_speed.
    SetSpeed { interval_ms: u64 },
    /// Change tick resolution (client smoothness) independently of speed.
    SetTicksPerSecond { tps: u32 },
    /// Change game-time multiplier (gameplay pace) independently of resolution.
    SetWorldSpeed { world_speed: f32 },
    GetTick,
}
