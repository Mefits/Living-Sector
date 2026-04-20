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
            FacilityIdentity, FacilityLocation, FacilityOperations, FacilitySnapshot,
            FacilityStorage,
        },
        faction::{FactionData, FactionSnapshot},
        market::{MarketHistory, MarketIdentity, MarketPricing, MarketSnapshot},
        population::{
            PopDemographics, PopEconomy, PopIdentity, PopSentiment, PopSnapshot,
        },
        ship::{
            ShipAI, ShipCargo, ShipCrew, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle,
            ShipPosition, ShipSnapshot, ShipTransit,
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
    }

    fn update_ships(&self, store: &AgentStore) {
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
            let crew = store.world.get::<&ShipCrew>(e).ok();
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
            );
            self.positions.insert(identity.id.clone(), position.position);
            self.ships.insert(identity.id.clone(), snap);
        }
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

        for (_e, (identity, location, ops, storage)) in store
            .world
            .query::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
            )>()
            .iter()
        {
            let pos = body_pos
                .get(&identity.body_id)
                .copied()
                .unwrap_or((0.0, 0.0));
            let snap = FacilitySnapshot::build(
                identity,
                location,
                ops,
                storage,
                sim_core::agents::Position::from(pos),
            );
            // Also publish the facility's position in the flat cache so
            // Godot's positions broadcast includes it with kind "facility".
            self.positions.insert(identity.id.clone(), pos);
            self.facilities.insert(identity.id.clone(), snap);
        }
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
