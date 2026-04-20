//! AgentStore: hecs::World wrapper with string-id lookup indexes.
//!
//! Entity storage is delegated to hecs (archetype-based, cache-friendly for
//! component queries). On top we maintain HashMap indexes that let us go from
//! a human-readable string id ("ship-artemis-7") to a hecs::Entity in O(1).
//!
//! The tick loop owns AgentStore and writes directly. HTTP/WS handlers read
//! from the separate SnapshotCache (DashMap), not this.

use crate::economy::contracts::ContractBoard;
use hecs::{Entity, World};
use std::collections::HashMap;

pub struct AgentStore {
    /// The ECS world holding all entity components.
    pub world: World,

    /// Contract board — directed demand signals between populations/facilities and ships.
    pub contracts: ContractBoard,

    // --- String id lookups ---
    pub ship_by_id: HashMap<String, Entity>,
    pub market_by_id: HashMap<String, Entity>,
    pub facility_by_id: HashMap<String, Entity>,
    pub population_by_id: HashMap<String, Entity>,
    pub body_by_id: HashMap<String, Entity>,
    pub faction_by_id: HashMap<String, Entity>,

    // --- Spatial / relational indexes ---
    /// location_name → entity of the single market at that location (if any).
    pub market_at_location: HashMap<String, Entity>,
    /// location_name → all facility entities at that location.
    pub facilities_at_location: HashMap<String, Vec<Entity>>,
}

impl Default for AgentStore {
    fn default() -> Self {
        Self::new()
    }
}

impl AgentStore {
    pub fn new() -> Self {
        Self {
            world: World::new(),
            contracts: ContractBoard::new(),
            ship_by_id: HashMap::new(),
            market_by_id: HashMap::new(),
            facility_by_id: HashMap::new(),
            population_by_id: HashMap::new(),
            body_by_id: HashMap::new(),
            faction_by_id: HashMap::new(),
            market_at_location: HashMap::new(),
            facilities_at_location: HashMap::new(),
        }
    }

    /// Register a ship after spawning it.
    pub fn index_ship(&mut self, id: String, entity: Entity) {
        self.ship_by_id.insert(id, entity);
    }

    /// Register a market after spawning (maintains location index too).
    pub fn index_market(&mut self, id: String, location: String, entity: Entity) {
        self.market_by_id.insert(id, entity);
        self.market_at_location.insert(location, entity);
    }

    /// Register a facility after spawning (maintains location index too).
    pub fn index_facility(&mut self, id: String, location: String, entity: Entity) {
        self.facility_by_id.insert(id, entity);
        self.facilities_at_location
            .entry(location)
            .or_default()
            .push(entity);
    }

    pub fn index_population(&mut self, id: String, entity: Entity) {
        self.population_by_id.insert(id, entity);
    }

    pub fn index_body(&mut self, body_id: String, entity: Entity) {
        self.body_by_id.insert(body_id, entity);
    }

    pub fn index_faction(&mut self, id: String, entity: Entity) {
        self.faction_by_id.insert(id, entity);
    }

    // --- Summary for startup logging ---

    pub fn summary(&self) -> AgentStoreSummary {
        AgentStoreSummary {
            ships: self.ship_by_id.len(),
            markets: self.market_by_id.len(),
            facilities: self.facility_by_id.len(),
            populations: self.population_by_id.len(),
            factions: self.faction_by_id.len(),
            bodies: self.body_by_id.len(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct AgentStoreSummary {
    pub ships: usize,
    pub markets: usize,
    pub facilities: usize,
    pub populations: usize,
    pub factions: usize,
    pub bodies: usize,
}

impl std::fmt::Display for AgentStoreSummary {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} ships | {} markets | {} facilities | {} populations | {} factions | {} bodies",
            self.ships, self.markets, self.facilities, self.populations, self.factions, self.bodies
        )
    }
}
