//! Snapshot cache — DashMap-backed, lock-free reads for HTTP/WS handlers.
//!
//! The tick loop writes snapshots at the end of each tick (after all agent
//! logic runs). HTTP handlers read from here without touching the live
//! AgentStore. This is the ETS-snapshots equivalent from the Elixir design.

use dashmap::DashMap;
use sim_core::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit, BodySnapshot},
        facility::{
            FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations,
            FacilitySnapshot, FacilityStorage, GateLink,
        },
        faction::{FactionData, FactionSnapshot},
        market::{MarketHistory, MarketIdentity, MarketPricing, MarketSnapshot},
        population::{
            PopDemographics, PopEconomy, PopIdentity, PopSentiment, PopSnapshot,
        },
        ship::{
            ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFuel, ShipIdentity,
            ShipLifecycle, ShipPosition, ShipSnapshot, ShipTransit,
        },
    },
    simulation::spawner::AgentStore,
};
use std::sync::Arc;

#[derive(Default)]
pub struct SnapshotCache {
    pub ships: DashMap<String, ShipSnapshot>,
    pub markets: DashMap<String, MarketSnapshot>,
    pub facilities: DashMap<String, FacilitySnapshot>,
    pub populations: DashMap<String, PopSnapshot>,
    pub bodies: DashMap<String, BodySnapshot>,
    pub factions: DashMap<String, FactionSnapshot>,
    /// Serialized contract board snapshot. Keyed by contract id. Refreshed
    /// at the end of each tick in `update_from`. Stored as `Value` so the
    /// snapshot layer doesn't depend on `ContractBoard`'s internal types.
    pub contracts: DashMap<String, serde_json::Value>,
    /// agent_id → (x, y). Ships + bodies mix here since Godot renders them the same way.
    pub positions: DashMap<String, (f32, f32)>,
}

impl SnapshotCache {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Write snapshots for every agent by querying the world.
    /// Called at the end of each tick by the engine.
    pub fn update_from(&self, store: &AgentStore) {
        self.update_ships(store);
        self.update_markets(store);
        self.update_facilities(store);
        self.update_populations(store);
        self.update_bodies(store);
        self.update_factions(store);
        self.update_contracts(store);
    }

    fn update_contracts(&self, store: &AgentStore) {
        // Clear stale entries — contracts that transitioned to Paid /
        // Expired are still in the board but we keep them around for
        // history. If the board removes them entirely, drop here.
        let mut live: std::collections::HashSet<String> = Default::default();
        for c in store.contracts.iter() {
            live.insert(c.id.clone());
            if let Ok(v) = serde_json::to_value(c) {
                self.contracts.insert(c.id.clone(), v);
            }
        }
        self.contracts.retain(|k, _| live.contains(k));
    }

    fn update_ships(&self, store: &AgentStore) {
        let mut live: std::collections::HashSet<String> = Default::default();
        for (e, (identity, position, transit, cargo, fuel, economy, ai, lifecycle)) in store
            .world
            .query::<(
                &ShipIdentity,
                &ShipPosition,
                &ShipTransit,
                &ShipCargo,
                &ShipFuel,
                &ShipEconomy,
                &ShipAI,
                &ShipLifecycle,
            )>()
            .iter()
        {
            // ShipCrew is optional since we only added it in Phase 8d.
            // ShipCrewSkills came in Phase 11b; also optional on older saves.
            let crew = store.world.get::<&ShipCrew>(e).ok();
            let skills = store.world.get::<&ShipCrewSkills>(e).ok();
            let snap = ShipSnapshot::build(
                identity,
                position,
                transit,
                cargo,
                fuel,
                economy,
                ai,
                lifecycle,
                crew.as_deref(),
                skills.as_deref(),
            );
            self.positions.insert(identity.id.clone(), position.position);
            self.ships.insert(identity.id.clone(), snap);
            live.insert(identity.id.clone());
        }
        // Purge snapshots for ships that no longer exist in the world
        // (admin-destroyed or recycled). Without this, /api/ships keeps
        // returning the despawned ship until next restart.
        self.ships.retain(|k, _| live.contains(k));
        // Positions DashMap mixes ships + bodies, so only prune entries
        // with the `ship-` prefix to avoid wiping body positions.
        self.positions.retain(|k, _| !k.starts_with("ship-") || live.contains(k));
    }

    fn update_markets(&self, store: &AgentStore) {
        for (_e, (identity, pricing, history)) in store
            .world
            .query::<(&MarketIdentity, &MarketPricing, &MarketHistory)>()
            .iter()
        {
            let snap = MarketSnapshot::build(identity, pricing, history);
            self.markets.insert(identity.id.clone(), snap);
        }
    }

    fn update_facilities(&self, store: &AgentStore) {
        // Build body_id → universe_position map first so each facility can
        // inherit its body's position without a second world query.
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let mut body_pos: std::collections::HashMap<String, (f32, f32)> =
            std::collections::HashMap::new();
        for (_e, (id, orbit)) in store
            .world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter()
        {
            body_pos.insert(id.body_id.clone(), orbit.universe_position());
        }

        // Build ship_entity → ship_id map so FacilityStorage.docked_ships
        // (Vec<Entity>) can be resolved to the string-id shape Godot reads.
        let ship_id_by_entity: std::collections::HashMap<hecs::Entity, String> = store
            .world
            .query::<&ShipIdentity>()
            .iter()
            .map(|(e, id)| (e, id.id.clone()))
            .collect();

        let mut live: std::collections::HashSet<String> = Default::default();
        for (e, (identity, location, ops, storage)) in store
            .world
            .query::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
            )>()
            .iter()
        {
            let body_center = body_pos
                .get(&identity.body_id)
                .copied()
                .unwrap_or((0.0, 0.0));
            // Offset from body center so co-located facilities don't stack
            // on top of the planet or each other. Angle comes from a stable
            // hash of the facility id so the same facility always lands at
            // the same spot around its body. Matches the Elixir sim's
            // `:erlang.phash2(id, 360)` offset pattern at radius 0.15.
            let pos = facility_offset_position(body_center, &identity.id);
            let docked_ship_ids: Vec<String> = storage
                .docked_ships
                .iter()
                .filter_map(|e| ship_id_by_entity.get(e).cloned())
                .collect();
            let lifecycle = store.world.get::<&FacilityLifecycle>(e).ok();
            let gate = store.world.get::<&GateLink>(e).ok();
            let snap = FacilitySnapshot::build(
                identity,
                location,
                ops,
                storage,
                lifecycle.as_deref(),
                gate.as_deref(),
                sim_core::agents::Position::from(pos),
                docked_ship_ids,
            );
            // Also publish the facility's position in the flat cache so
            // Godot's positions broadcast includes it with kind "facility".
            self.positions.insert(identity.id.clone(), pos);
            self.facilities.insert(identity.id.clone(), snap);
            live.insert(identity.id.clone());
        }
        // Purge snapshots for facilities that no longer exist (admin
        // destroy, abandonment cleanup). Positions cache entries for
        // facility ids are purged here too.
        self.facilities.retain(|k, _| live.contains(k));
        self.positions.retain(|k, _| !k.starts_with("facility-") || live.contains(k));
    }

    fn update_populations(&self, store: &AgentStore) {
        for (_e, (identity, demo, econ, sent)) in store
            .world
            .query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
            .iter()
        {
            let snap = PopSnapshot::build(identity, demo, econ, sent);
            self.populations.insert(identity.id.clone(), snap);
        }
    }

    fn update_bodies(&self, store: &AgentStore) {
        for (_e, (identity, orbit)) in store
            .world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter()
        {
            let snap = BodySnapshot::build(identity, orbit);
            self.positions
                .insert(identity.body_id.clone(), (snap.universe_position.x, snap.universe_position.y));
            self.bodies.insert(identity.body_id.clone(), snap);
        }
    }

    fn update_factions(&self, store: &AgentStore) {
        for (_e, data) in store.world.query::<&FactionData>().iter() {
            self.factions
                .insert(data.id.clone(), FactionSnapshot::build(data));
        }
    }
}

// Facility offset logic moved to sim_core so sim_core::agents::ship can use
// the same function for transit endpoints (ships aim at the station's
// actual offset, not the body center).
use sim_core::agents::facility::facility_offset_position;
