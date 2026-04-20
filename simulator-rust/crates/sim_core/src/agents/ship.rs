//! Ship components for hecs storage.
//!
//! A ship entity is spawned with the full bundle of components below. Fields
//! are grouped by access pattern so that tick phases load only the data they
//! need — position updates don't pull cargo or AI into cache.
//!
//! Spawn a ship with:
//! ```ignore
//! world.spawn((
//!     ShipIdentity { ... },
//!     ShipPosition { ... },
//!     ShipTransit { transit: None },
//!     ShipCargo { ... },
//!     ShipFuel { ... },
//!     ShipEconomy { ... },
//!     ShipAI { ... },
//!     ShipMemory { ... },
//!     ShipLifecycle { ... },
//! ));
//! ```

use crate::{
    ai::{behavior_tree::BtNode, personality::Personality},
    economy::commodities::{Cargo, Commodity, PriceKnowledge},
};
use hecs::Entity;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// In-transit data for a ship traveling between locations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transit {
    pub from: String,
    pub to: String,
    pub departure_tick: u64,
    pub arrival_tick: u64,
}

/// Stable identity — set at spawn, rarely mutated.
#[derive(Debug, Clone)]
pub struct ShipIdentity {
    pub db_id: i64,
    /// Human-readable agent id, e.g. "ship-artemis-7".
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
}

/// Spatial state — changes every tick while in transit.
#[derive(Debug, Clone)]
pub struct ShipPosition {
    pub location_name: Option<String>, // None while in transit
    pub docked_at: Option<Entity>,      // facility entity if docked
    pub system_id: String,
    pub universe_offset: (f32, f32),
    pub position: (f32, f32),
}

/// Transit state. `None` when the ship is stationary (docked or idle at a location).
#[derive(Debug, Clone)]
pub struct ShipTransit {
    pub transit: Option<Transit>,
}

/// Cargo hold.
#[derive(Debug, Clone)]
pub struct ShipCargo {
    pub cargo: Cargo,
    pub capacity: u32,
    /// tick each commodity was first acquired (for hoard detection)
    pub cargo_age: HashMap<Commodity, u64>,
}

impl ShipCargo {
    pub fn used(&self) -> u32 {
        self.cargo.values().sum()
    }
    pub fn free(&self) -> u32 {
        self.capacity.saturating_sub(self.used())
    }
}

/// Fuel and propulsion.
#[derive(Debug, Clone)]
pub struct ShipFuel {
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub fuel_consumption_rate: f32,
    pub speed_modifier: f32,
}

impl ShipFuel {
    pub fn fraction(&self) -> f32 {
        if self.fuel_capacity > 0.0 { self.fuel / self.fuel_capacity } else { 0.0 }
    }
}

/// Economic state.
#[derive(Debug, Clone)]
pub struct ShipEconomy {
    pub credits: i64,
    pub efficiency: f32,
    pub active_contract_id: Option<String>,
    pub faction_reputation: HashMap<String, u8>,
}

/// AI: personality + current goal + BT state.
#[derive(Debug, Clone)]
pub struct ShipAI {
    pub personality: Personality,
    pub current_goal: String,
    pub current_bt: Option<BtNode>,
}

/// Learned memory — price knowledge, visited locations.
/// Rarely loaded except during trade decisions.
#[derive(Debug, Clone)]
pub struct ShipMemory {
    pub price_knowledge: PriceKnowledge,
    pub visited: Vec<String>,
}

/// Lifecycle counters and dirty flag for persistence.
#[derive(Debug, Clone)]
pub struct ShipLifecycle {
    pub broke_strikes: u8,
    pub hoard_strikes: u8,
    pub idle_ticks: u32,
    pub dirty: bool,
}

/// Serializable snapshot for HTTP/WS clients — built by querying components.
#[derive(Debug, Clone, Serialize)]
pub struct ShipSnapshot {
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    pub location_name: Option<String>,
    pub docked: bool,
    pub transit: Option<Transit>,
    pub cargo: HashMap<String, u32>,
    pub cargo_capacity: u32,
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub credits: i64,
    pub current_goal: String,
    pub bt_action: Option<String>,
    pub position: (f32, f32),
}

impl ShipSnapshot {
    pub fn build(
        identity: &ShipIdentity,
        position: &ShipPosition,
        transit: &ShipTransit,
        cargo: &ShipCargo,
        fuel: &ShipFuel,
        economy: &ShipEconomy,
        ai: &ShipAI,
    ) -> Self {
        let cargo_map: HashMap<String, u32> = cargo
            .cargo
            .iter()
            .map(|(c, &qty)| (c.as_str().to_string(), qty))
            .collect();
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            class: identity.class.clone(),
            faction_id: identity.faction_id.clone(),
            location_name: position.location_name.clone(),
            docked: position.docked_at.is_some(),
            transit: transit.transit.clone(),
            cargo: cargo_map,
            cargo_capacity: cargo.capacity,
            fuel: fuel.fuel,
            fuel_capacity: fuel.fuel_capacity,
            credits: economy.credits,
            current_goal: ai.current_goal.clone(),
            bt_action: ai.current_bt.as_ref().and_then(|bt| bt.current_action()).map(String::from),
            position: position.position,
        }
    }
}
