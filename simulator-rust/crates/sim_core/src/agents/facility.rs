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
#[derive(Debug, Clone, Serialize)]
pub struct FacilitySnapshot {
    pub id: String,
    pub name: String,
    pub facility_type: String,
    pub location_name: String,
    pub faction_id: String,
    pub condition: f32,
    pub reputation: i32,
    pub credits: i64,
    pub docked_ship_count: usize,
    pub docking_capacity: u32,
    pub services: Vec<String>,
}

impl FacilitySnapshot {
    pub fn build(
        identity: &FacilityIdentity,
        location: &FacilityLocation,
        ops: &FacilityOperations,
        storage: &FacilityStorage,
    ) -> Self {
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            facility_type: identity.facility_type.clone(),
            location_name: location.location_name.clone(),
            faction_id: identity.faction_id.clone(),
            condition: ops.condition,
            reputation: ops.reputation,
            credits: ops.credits,
            docked_ship_count: storage.docked_ships.len(),
            docking_capacity: ops.docking_capacity,
            services: ops.services.clone(),
        }
    }
}
