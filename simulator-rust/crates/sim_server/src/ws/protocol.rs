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
        world_speed: f32,
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
    /// Facility snapshots. Every ~2s (16 ticks). Godot uses this to render
    /// dock occupancy (count of `docked_ships`), fuel reserves, condition
    /// and faction ownership on stations. Without it, `facility.gd` can't
    /// pulse the docking glow or show reserve tanks in the details panel.
    FacilityStates {
        tick: u64,
        facilities: Vec<serde_json::Value>,
    },
    /// Population snapshots. Every ~2s (16 ticks). Godot's population
    /// details panel reads `population_count`, `overall_sentiment`,
    /// `food_satisfaction`. Drives colony health indicators.
    PopulationStates {
        tick: u64,
        populations: Vec<serde_json::Value>,
    },
    /// Faction snapshots. Every ~4s (32 ticks) — they change slowly. Godot
    /// reads `treasury` for the faction ledger panel and displays active
    /// subsidy counts.
    FactionStates {
        tick: u64,
        factions: Vec<serde_json::Value>,
    },
    /// Episodic events — ship docked, contract delivered, facility
    /// abandoned, subsidy posted, passengers arrived. Sent each tick only
    /// if the buffer is non-empty. Godot's HUD toasts/ticker subscribes.
    Events {
        tick: u64,
        events: Vec<serde_json::Value>,
    },
    /// Full contract board snapshot. Every 32 ticks (~4 s). Godot's
    /// contracts panel reads posted/accepted/delivered contracts so the
    /// player can see passenger runs, subsidies, crew missions etc.
    ContractStates {
        tick: u64,
        contracts: Vec<serde_json::Value>,
    },
    /// Reply to get_agent / get_snapshot requests.
    AgentState {
        id: String,
        data: serde_json::Value,
    },
    /// Reply to sim_control commands. `world_speed` + `interval_ms` let the
    /// Godot HUD reflect the current pace after pause/resume/speed changes
    /// without issuing a separate `/api/health` request.
    SimControlAck {
        action: String,
        tick: u64,
        running: bool,
        world_speed: f32,
        interval_ms: u64,
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
    /// Change tick resolution (client smoothness) independently of speed.
    SetTicksPerSecond { tps: u32 },
    /// Change game-time multiplier (gameplay pace) independently of resolution.
    SetWorldSpeed { world_speed: f32 },
    GetTick,
}
