//! AgentStore: hecs::World wrapper with string-id lookup indexes.
//!
//! Entity storage is delegated to hecs (archetype-based, cache-friendly for
//! component queries). On top we maintain HashMap indexes that let us go from
//! a human-readable string id ("ship-artemis-7") to a hecs::Entity in O(1).
//!
//! The tick loop owns AgentStore and writes directly. HTTP/WS handlers read
//! from the separate SnapshotCache (DashMap), not this.

use crate::agents::faction_relations::FactionRelations;
use crate::economy::contracts::ContractBoard;
use hecs::{Entity, World};
use std::collections::HashMap;

/// Adaptive-fleet retirement request. Ships hitting 3 broke/hoard
/// strikes push an entry here; the async tick loop drains it, emits
/// the retirement row, despawns the entity, and queues a
/// [`PendingRespawn`] so fleet size stays roughly constant.
#[derive(Debug, Clone)]
pub struct PendingDecommission {
    pub entity: Entity,
    pub reason: &'static str,
}

/// Adaptive-fleet replacement request. Emitted after a ship retires;
/// drained by the tick loop once `spawn_at_tick` arrives and then
/// dispatched through the admin-spawn path with randomised faction /
/// class / location / crew.
#[derive(Debug, Clone)]
pub struct PendingRespawn {
    pub spawn_at_tick: u64,
    /// Preference hint used by the spawner picker — usually the
    /// retiring ship's faction, so losses show up as "faction down a
    /// ship" pressure before the weighted pick redistributes. None
    /// lets the picker choose purely by ship-count deficit.
    pub prefer_faction: Option<String>,
}

/// Pending INSERT-then-backfill request for a facility that was just
/// materialised from a construction site. The ECS entity is already
/// spawned with `FacilityIdentity.db_id = 0`; the engine drains this
/// queue asynchronously after each apply phase, runs the real INSERT,
/// and updates the entity's db_id with the returned row id.
///
/// Pure data (strings + numbers) so `sim_core` stays free of sqlx.
#[derive(Debug, Clone)]
pub struct PendingMaterialization {
    pub entity: Entity,
    pub agent_id: String,
    /// Source construction-site agent id. The engine drains this
    /// queue and schedules a `ConstructionSiteDelete` for this id
    /// so the completed site doesn't resurrect on restart.
    pub source_site_id: String,
    pub name: String,
    pub facility_type: String,
    pub faction_id: String,
    pub body_id: String,
    pub location_id: i64,
    pub location_name: String,
    pub docking_capacity: u32,
    pub credits: i64,
    pub reputation: i32,
    pub condition: f32,
}

pub struct AgentStore {
    /// The ECS world holding all entity components.
    pub world: World,

    /// Contract board — directed demand signals between populations/facilities and ships.
    pub contracts: ContractBoard,

    /// Inter-faction relations matrix (Bundle A). Singleton — pairwise
    /// standing + treaty state for every faction pair that has ever
    /// touched it. Same rationale as `contracts`: pinning to
    /// AgentStore keeps it the single source of truth and avoids the
    /// "stored on one side but not the other" divergence risk.
    pub relations: FactionRelations,

    /// Construction-site materialisations awaiting DB INSERT. Pushed
    /// by the sync `apply_construction_delivery` path; drained by the
    /// async tick loop immediately after the apply phase.
    pub pending_materializations: Vec<PendingMaterialization>,

    /// Ships queued for decommission by the strike system. Drained
    /// by the tick loop after apply — each entry fires
    /// `admin_remove_ship` with the given reason and pushes a
    /// `PendingRespawn` for a delayed replacement.
    pub pending_decommissions: Vec<PendingDecommission>,

    /// Replacement ships queued to spawn after a retirement. Each
    /// entry carries a `spawn_at_tick`; the tick loop drains any entry
    /// whose tick has arrived and routes through the admin-spawn path
    /// with randomised class / location / crew.
    pub pending_respawns: Vec<PendingRespawn>,

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
    /// gate location → paired gate's location. Mirror-paired; both
    /// entries are present when seed data is correct. Built by
    /// `rebuild_gate_pairs()` after gate facilities are registered.
    pub gate_pairs: HashMap<String, String>,
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
            relations: FactionRelations::new(),
            pending_materializations: Vec::new(),
            pending_decommissions: Vec::new(),
            pending_respawns: Vec::new(),
            ship_by_id: HashMap::new(),
            market_by_id: HashMap::new(),
            facility_by_id: HashMap::new(),
            population_by_id: HashMap::new(),
            body_by_id: HashMap::new(),
            faction_by_id: HashMap::new(),
            market_at_location: HashMap::new(),
            facilities_at_location: HashMap::new(),
            gate_pairs: HashMap::new(),
        }
    }

    /// Rebuild the gate-pairs lookup from live `GateLink` components.
    /// Call after all gate facilities have been spawned (post-loader)
    /// and after any admin spawn that added/removed a gate.
    pub fn rebuild_gate_pairs(&mut self) {
        use crate::agents::facility::{FacilityIdentity, GateLink};
        let mut pairs = HashMap::new();
        // location → (facility_agent_id, paired_agent_id)
        let mut by_fac_id: HashMap<String, String> = HashMap::new();
        // Collect gate (facility_id, paired_facility_id) tuples.
        let gates: Vec<(String, String, String)> = self
            .world
            .query::<(&FacilityIdentity, &GateLink)>()
            .iter()
            .map(|(_e, (id, link))| {
                (
                    id.id.clone(),
                    link.paired_gate_id.clone(),
                    // location lookup via facility_by_id + facilities_at_location
                    String::new(),
                )
            })
            .collect();
        // Build facility_id → location.
        let fac_id_to_loc: HashMap<String, String> = self
            .world
            .query::<(&FacilityIdentity, &crate::agents::facility::FacilityLocation)>()
            .iter()
            .map(|(_e, (id, loc))| (id.id.clone(), loc.location_name.clone()))
            .collect();
        for (gate_id, paired_id, _) in gates {
            by_fac_id.insert(gate_id, paired_id);
        }
        for (gate_id, paired_id) in by_fac_id {
            let (Some(here), Some(there)) = (
                fac_id_to_loc.get(&gate_id),
                fac_id_to_loc.get(&paired_id),
            ) else {
                continue;
            };
            pairs.insert(here.clone(), there.clone());
        }
        self.gate_pairs = pairs;
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
