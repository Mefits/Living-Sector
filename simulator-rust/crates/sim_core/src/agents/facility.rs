//! Facility components.

use crate::economy::commodities::Commodity;
use hecs::Entity;
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone)]
pub struct FacilityIdentity {
    pub db_id: i64,
    pub id: String,                  // "facility-earth-station"
    pub name: String,
    pub facility_type: String,       // station, refinery, farm, etc.
    pub faction_id: String,
    pub body_id: String,
}

/// Spatial anchor.
#[derive(Debug, Clone)]
pub struct FacilityLocation {
    pub location_id: i64,
    pub location_name: String,
}

/// Operations — docking, condition, finances.
#[derive(Debug, Clone)]
pub struct FacilityOperations {
    pub docking_capacity: u32,
    pub services: Vec<String>,
    pub condition: f32,      // 0.0–1.0
    pub reputation: i32,     // 0–100
    pub credits: i64,
    pub dirty: bool,
}

impl FacilityOperations {
    pub fn has_service(&self, service: &str) -> bool {
        self.services.iter().any(|s| s == service)
    }
}

/// Storage: resource reserves + currently docked ships + pending deliveries.
#[derive(Debug, Clone, Default)]
pub struct FacilityStorage {
    pub reserves: HashMap<Commodity, f32>,
    pub docked_ships: Vec<Entity>,
    pub pending_deliveries: Vec<String>, // contract ids
}

impl FacilityStorage {
    pub fn has_dock_space(&self, capacity: u32) -> bool {
        self.docked_ships.len() < capacity as usize
    }
}

/// Snapshot for HTTP/WS.
///
/// Field names match what Godot reads: `type` (not `facility_type`),
/// `location` (not `location_name`), `docked_ships` as an array of ship
/// agent-ids (not just a count — `facility.gd` checks `is Array`).
#[derive(Debug, Clone, Serialize)]
pub struct FacilitySnapshot {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub facility_type: String,
    #[serde(rename = "location")]
    pub location_name: String,
    /// Body this facility sits on (e.g. "earth", "mars", "belt"). Godot's
    /// `facility.gd` reads this to group facilities under a star_system.
    pub body_id: String,
    pub faction_id: String,
    pub condition: f32,
    pub reputation: i32,
    pub credits: i64,
    /// Ship agent-ids currently docked here (e.g. `["ship-artemis-7"]`).
    /// Godot's facility.gd uses `.size()` for its docking glow animation.
    pub docked_ships: Vec<String>,
    pub docking_capacity: u32,
    pub services: Vec<String>,
    /// Commodity → qty dict for this facility's on-hand reserves.
    /// Rendered in the details panel; reserves are kept per-facility
    /// separate from market supply.
    pub reserves: std::collections::HashMap<String, f32>,
    /// Universe-space position, inherited from the facility's body.
    pub position: super::Position,
}

impl FacilitySnapshot {
    pub fn build(
        identity: &FacilityIdentity,
        location: &FacilityLocation,
        ops: &FacilityOperations,
        storage: &FacilityStorage,
        position: super::Position,
    ) -> Self {
        // storage.docked_ships is Vec<hecs::Entity> and currently always
        // empty — runtime docking doesn't yet attach ship→facility in the
        // ECS. Emit an empty array so Godot's `is Array` check passes.
        // When real docking lands, build this via a db_id → agent_id lookup.
        let docked_ships: Vec<String> = Vec::new();
        let reserves: std::collections::HashMap<String, f32> = storage
            .reserves
            .iter()
            .map(|(c, &v)| (c.as_str().to_string(), v))
            .collect();
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            facility_type: identity.facility_type.clone(),
            location_name: location.location_name.clone(),
            body_id: identity.body_id.clone(),
            faction_id: identity.faction_id.clone(),
            condition: ops.condition,
            reputation: ops.reputation,
            credits: ops.credits,
            docked_ships,
            docking_capacity: ops.docking_capacity,
            services: ops.services.clone(),
            reserves,
            position,
        }
    }
}

// ============================================================================
// Facility tick
// ============================================================================
//
// Each tick (on an interval) the facility:
//   1. Executes any recipes available for its facility_type against the
//      local market's supply (pulls inputs, pushes outputs).
//   2. If a mining_rig, extracts resources from its celestial body into
//      the local market supply.
//
// Recipes operate directly on market supply (source of truth) rather than
// a separate facility-reserves ledger — simpler and the Elixir model does
// the same effectively.

use crate::agents::celestial_body::{BodyIdentity, BodyResources};
use crate::agents::market::{MarketIdentity, MarketPricing};
use crate::economy::recipes;

/// How often facilities run recipes. Base ticks at 1x world speed = 5 ticks.
/// At default 0.25 speed (mult=32) this is every 160 ticks (~20s).
pub const RECIPE_INTERVAL_BASE: u64 = 5;
pub const MINING_INTERVAL_BASE: u64 = 5;

/// Max batches a facility can run in a single cycle. Prevents one refinery
/// from draining all ore in one tick.
pub const RECIPE_MAX_BATCHES: u32 = 20;

/// Mining yield per cycle = body_resource_richness × RESOURCE_YIELD_PER_TICK
/// Units of commodity added to market supply per cycle.
pub const MINING_YIELD_PER_CYCLE: f32 = 80.0;

pub fn tick_facilities(world: &mut hecs::World, tick: u64, tick_multiplier: u32) {
    let mult = tick_multiplier as u64;
    let recipe_interval = RECIPE_INTERVAL_BASE * mult;
    let mining_interval = MINING_INTERVAL_BASE * mult;

    if tick % recipe_interval != 0 && tick % mining_interval != 0 {
        return;
    }

    // Build location → market_entity index once (needed to route recipe I/O)
    let market_at_location: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (id.facility_location.clone(), e))
        .collect();

    // Build body_id_str → body_entity index for mining rigs
    let body_by_string_id: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&BodyIdentity>()
        .iter()
        .map(|(e, id)| (id.body_id.clone(), e))
        .collect();

    // Collect facility info upfront to avoid nested mutable borrows.
    #[derive(Clone)]
    struct FacilityInfo {
        facility_type: String,
        location_name: String,
        body_id: String,
    }
    let facilities: Vec<FacilityInfo> = world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .map(|(_e, (id, loc))| FacilityInfo {
            facility_type: id.facility_type.clone(),
            location_name: loc.location_name.clone(),
            body_id: id.body_id.clone(),
        })
        .collect();

    if tick % recipe_interval == 0 {
        for fac in &facilities {
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            // Execute every recipe for this facility type against the market supply
            if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                for recipe in recipes::for_facility_type(&fac.facility_type) {
                    let _ = recipes::execute(recipe, &mut pricing.supply, 1.0, RECIPE_MAX_BATCHES);
                }
            }
        }
    }

    if tick % mining_interval == 0 {
        for fac in &facilities {
            if fac.facility_type != "mining_rig" {
                continue;
            }
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            let body_entity = match body_by_string_id.get(&fac.body_id) {
                Some(&e) => e,
                None => continue,
            };
            // Take a snapshot of body resources to avoid the simultaneous borrow
            let body_resources: Vec<(Commodity, f32)> = match world.get::<&BodyResources>(body_entity) {
                Ok(r) => r.resources.iter().map(|(&c, &v)| (c, v)).collect(),
                Err(_) => continue,
            };
            if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                for (commodity, richness) in body_resources {
                    if richness <= 0.0 {
                        continue;
                    }
                    let extracted = MINING_YIELD_PER_CYCLE * richness;
                    *pricing.supply.entry(commodity).or_insert(0.0) += extracted;
                }
            }
        }
    }
}
