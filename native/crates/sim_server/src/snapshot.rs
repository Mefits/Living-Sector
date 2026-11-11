//! Snapshot cache — DashMap-backed, lock-free reads for HTTP/WS handlers.
//!
//! The tick loop writes snapshots at the end of each tick (after all agent
//! logic runs). HTTP handlers read from here without touching the live
//! AgentStore. This is the ETS-snapshots equivalent from the Elixir design.

use bevy_ecs::prelude::{Entity, World};
use dashmap::DashMap;
use sim_core::{
    agents::{
        celestial_body::{BodyBiome, BodyIdentity, BodyOrbit, BodyResources, BodySnapshot, BodyTerritory},
        construction::{ConstructionSite, ConstructionSiteSnapshot},
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
            ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFitting, ShipFuel,
            ShipIdentity, ShipLifecycle, ShipPosition, ShipProgression, ShipSnapshot, ShipTransit,
        },
    },
    simulation::spawner::AgentStore,
};
use std::sync::Arc;

/// Flat JSON view of one relation pair, emitted by `/api/factions/relations`
/// and by the ws frame. Keeps the snapshot cache independent of
/// `FactionRelations`' internal types.
#[derive(Clone, serde::Serialize)]
pub struct RelationSnapshot {
    pub a: String,
    pub b: String,
    pub standing: i32,
    pub treaty: &'static str,
    pub since_tick: u64,
    pub last_event_tick: u64,
}

#[derive(Default)]
pub struct SnapshotCache {
    pub strategy: std::sync::RwLock<sim_core::strategy::Snapshot>,
    pub ships: DashMap<String, ShipSnapshot>,
    pub markets: DashMap<String, MarketSnapshot>,
    pub facilities: DashMap<String, FacilitySnapshot>,
    pub populations: DashMap<String, PopSnapshot>,
    pub bodies: DashMap<String, BodySnapshot>,
    pub factions: DashMap<String, FactionSnapshot>,
    /// Bundle A: canonical-pair-keyed matrix of inter-faction
    /// standing and treaty state. Refreshed on the faction snapshot
    /// cadence (16 ticks); relations move slowly enough that anything
    /// faster is wasted work. Key is `"{a}|{b}"` with `a < b` lexically.
    pub relations: DashMap<String, RelationSnapshot>,
    /// Serialized contract board snapshot. Keyed by contract id. Refreshed
    /// at the end of each tick in `update_from`. Stored as `Value` so the
    /// snapshot layer doesn't depend on `ContractBoard`'s internal types.
    pub contracts: DashMap<String, serde_json::Value>,
    /// agent_id → (x, y). Ships + bodies mix here since Godot renders them the same way.
    pub positions: DashMap<String, (f32, f32)>,
    /// Phase 19c: in-flight construction sites, keyed by site id.
    /// Empty when the demand analyzer hasn't triggered any builds
    /// yet. Godot consumes this to render the scaffold entities.
    pub construction_sites: DashMap<String, ConstructionSiteSnapshot>,
}

impl SnapshotCache {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Write snapshots for every agent by querying the world.
    /// Called at the end of each tick by the engine.
    ///
    /// Bundle (M): slow-changing categories update on a throttle
    /// rather than every tick. Positions for bodies + facilities
    /// are recomputed every tick (bodies orbit, facilities follow
    /// their body) through lightweight helpers that skip the full
    /// snapshot struct construction. The full struct rebuilds
    /// happen at these cadences:
    ///
    /// - Ships, construction sites, body positions, facility
    ///   positions: **every tick** (entities that move).
    /// - Markets, facilities, populations, bodies, contracts:
    ///   **every 4 ticks** (~500ms at WORLD_SPEED=1). Matches the
    ///   WS broadcast cadence for these categories.
    /// - Factions: **every 16 ticks** (factions touch their state
    ///   only on tax / subsidy cycles that are much slower than
    ///   this).
    pub fn update_from(&self, world: &mut World, store: &mut AgentStore, tick: u64) {
        if let Some(strategy) = world.get_resource::<sim_core::strategy::StrategyState>() {
            if let Ok(mut snapshot) = self.strategy.write() {
                *snapshot = strategy.snapshot(tick);
                snapshot.commanders = world.get_resource::<sim_core::strategy::director::Director>().map(|d|d.commanders.clone()).unwrap_or_default();
                snapshot.station_progress = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.station_progress.clone()).unwrap_or_default();
                snapshot.research_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.research_mandates.clone()).unwrap_or_default();
                snapshot.economic_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_mandates.clone()).unwrap_or_default();
                snapshot.faction_charters = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.faction_charters.clone()).unwrap_or_default();
                snapshot.economic_proposals = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_proposals.clone()).unwrap_or_default();
                // Expose durable native receipts, not only the last ephemeral head decision.
                // The plan state is already saved with the economic frame; this is read-only.
                snapshot.ai_execution = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d| d.ai_execution.clone());
                snapshot.orders = sim_core::strategy::orders::snapshot(world, &store.contracts);
                snapshot.colonies = sim_core::strategy::colony_development::observe(world, &store.contracts);
                snapshot.stations = world.get_resource::<sim_core::strategy::station::StationAdministration>()
                    .map(|s|s.stations.clone()).unwrap_or_default();
            }
        }

        // Hot path — every tick.
        self.update_ships(world, store);
        self.update_construction_sites(world, store);
        self.update_body_positions(world, store);
        self.update_facility_positions(world, store);

        // Mid-cadence (4 ticks). Full snapshots rebuild; positions
        // stay fresh via the always-on helpers above.
        if tick % 4 == 0 {
            self.update_bodies(world, store);
            self.update_markets(world, store);
            self.update_facilities(world, store);
            self.update_populations(world, store);
            self.update_contracts(store);
        }

        // Slow cadence (16 ticks). Factions rarely change outside
        // their tax cycle (every 200 base-ticks) and subsidy cycle
        // (every 30 base-ticks). Same cadence catches the relations
        // matrix (Bundle A) — decay + treaty transitions only run on
        // `RELATIONS_TICK_INTERVAL_BASE` so a 16-tick refresh here
        // is plenty.
        if tick % 16 == 0 {
            self.update_factions(world, store);
            self.update_relations(store);
        }
    }

    /// Bundle A: copy the relations matrix into the lock-free cache.
    /// One entry per canonical pair; key is `"{a}|{b}"` so HTTP reads
    /// can scan in a stable order. Empty matrix = no entries.
    fn update_relations(&self, store: &mut AgentStore) {
        let mut live: std::collections::HashSet<String> = Default::default();
        for (pair, state) in store.relations.iter() {
            let key = format!("{}|{}", pair.0, pair.1);
            live.insert(key.clone());
            self.relations.insert(
                key,
                RelationSnapshot {
                    a: pair.0.clone(),
                    b: pair.1.clone(),
                    standing: state.standing,
                    treaty: state.treaty.as_str(),
                    since_tick: state.since_tick,
                    last_event_tick: state.last_event_tick,
                },
            );
        }
        self.relations.retain(|k, _| live.contains(k));
    }

    /// Bundle (M): lightweight body-position refresh — skips the
    /// full BodySnapshot rebuild. Called every tick so Godot sees
    /// smooth orbits; the full body snapshot (biome, resources,
    /// etc.) rolls over on the 4-tick throttle.
    fn update_body_positions(&self, world: &mut World, _store: &mut AgentStore) {
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
        for (id, orbit) in q.iter(&world) {
            self.positions
                .insert(id.body_id.clone(), orbit.universe_position());
        }
    }

    /// Bundle (M): lightweight facility-position refresh. Recomputes
    /// the body-centered position each tick using the latest orbit,
    /// without the `FacilitySnapshot::build` call or the optional-
    /// component queries (crew, fitting, module_stock). The full
    /// facility snapshot rolls over on the 4-tick throttle.
    fn update_facility_positions(&self, world: &mut World, _store: &mut AgentStore) {
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let mut body_pos: std::collections::HashMap<String, (f32, f32)> =
            std::collections::HashMap::new();
        {
            let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
            for (id, orbit) in q.iter(&world) {
                body_pos.insert(id.body_id.clone(), orbit.universe_position());
            }
        }
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation,
            Option<&sim_core::agents::facility::FacilityOrbit>)>();
        for (id, loc, orbit) in q.iter(&world) {
            let center = body_pos.get(&id.body_id).copied().unwrap_or((0.0, 0.0));
            let angle = orbit.map(|v| v.angle_degrees)
                .unwrap_or_else(|| sim_core::agents::facility::facility_orbit_initial_angle(&loc.location_name));
            let pos = sim_core::agents::facility::facility_orbit_position(center, angle);
            self.positions.insert(id.id.clone(), pos);
        }
    }

    /// Phase 19c: refresh construction sites every tick. The stored
    /// site.position is the universe coordinate at the creation tick;
    /// using it forever left sites on an old point of the planet's orbit.
    /// Resolve the current body position and keep the same stable relative
    /// offset used when the site was spawned. Do not mutate its persisted
    /// creation-time position or any simulation/economic state.
    fn update_construction_sites(&self, world: &mut World, _store: &mut AgentStore) {
        let mut body_positions: std::collections::HashMap<String, (f32, f32)> =
            std::collections::HashMap::new();
        {
            let mut bodies = world.query::<(&BodyIdentity, &BodyOrbit)>();
            for (id, orbit) in bodies.iter(&world) {
                body_positions.insert(id.body_id.clone(), orbit.universe_position());
            }
        }
        let mut live: std::collections::HashSet<String> = Default::default();
        let mut q = world.query::<&ConstructionSite>();
        for site in q.iter(&world) {
            live.insert(site.id.clone());
            let pos = construction_site_orbit_position(
                &body_positions, &site.body_id, &site.id, site.position,
            );
            let mut snapshot = ConstructionSiteSnapshot::from(site);
            snapshot.position = sim_core::agents::Position::from(pos);
            self.construction_sites.insert(site.id.clone(), snapshot);
            self.positions.insert(site.id.clone(), pos);
        }
        self.construction_sites.retain(|k, _| live.contains(k));
        self.positions
            .retain(|k, _| !k.starts_with("site-") || live.contains(k));
    }

    fn update_contracts(&self, store: &mut AgentStore) {
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

    fn update_ships(&self, world: &mut World, _store: &mut AgentStore) {
        let mut live: std::collections::HashSet<String> = Default::default();
        let mut q = world.query::<(
            Entity,
            &ShipIdentity,
            &ShipPosition,
            &ShipTransit,
            &ShipCargo,
            &ShipFuel,
            &ShipEconomy,
            &ShipAI,
            &ShipLifecycle,
        )>();
        for (e, identity, position, transit, cargo, fuel, economy, ai, lifecycle) in
            q.iter(&world)
        {
            // ShipCrew is optional since we only added it in Phase 8d.
            // ShipCrewSkills came in Phase 11b; also optional on older saves.
            // ShipFitting came in Phase 18a; also optional on older saves.
            let crew = world.get::<ShipCrew>(e);
            let skills = world.get::<ShipCrewSkills>(e);
            let fitting = world.get::<ShipFitting>(e);
            let progression = world.get::<ShipProgression>(e);
            let snap = ShipSnapshot::build(
                identity,
                position,
                transit,
                cargo,
                fuel,
                economy,
                ai,
                lifecycle,
                crew,
                skills,
                fitting,
                progression,
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

    fn update_markets(&self, world: &mut World, _store: &mut AgentStore) {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing, &MarketHistory)>();
        for (identity, pricing, history) in q.iter(&world) {
            let snap = MarketSnapshot::build(identity, pricing, history);
            self.markets.insert(identity.id.clone(), snap);
        }
    }

    fn update_facilities(&self, world: &mut World, _store: &mut AgentStore) {
        // Build body_id → universe_position map first so each facility can
        // inherit its body's position without a second world query.
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let mut body_pos: std::collections::HashMap<String, (f32, f32)> =
            std::collections::HashMap::new();
        {
            let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
            for (id, orbit) in q.iter(&world) {
                body_pos.insert(id.body_id.clone(), orbit.universe_position());
            }
        }

        // Build ship_entity → ship_id map so FacilityStorage.docked_ships
        // (Vec<Entity>) can be resolved to the string-id shape Godot reads.
        let ship_id_by_entity: std::collections::HashMap<Entity, String> = {
            let mut q = world.query::<(Entity, &ShipIdentity)>();
            q.iter(&world)
                .map(|(e, id)| (e, id.id.clone()))
                .collect()
        };

        // Snapshot the facility-entity rows up front so we can do nested
        // optional-component reads on `&world` afterwards without
        // holding the QueryState's borrow. The base components are cheap
        // to clone as references, so we collect (Entity, position, docked,
        // queue) tuples plus indexable handles to the components.
        let entities: Vec<Entity> = {
            let mut q = world.query::<(
                Entity,
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
            )>();
            q.iter(&world).map(|(e, _, _, _, _)| e).collect()
        };

        // Physical slot counts, not estimated from glyphs.
        let mut modules_by_location=std::collections::HashMap::<(String,String),usize>::new();
        for e in &entities {
            let Some(id)=world.get::<FacilityIdentity>(*e) else {continue;};
            let Some(loc)=world.get::<FacilityLocation>(*e) else {continue;};
            if id.facility_type=="station" || id.facility_type=="gate" {continue;}
            *modules_by_location.entry((id.faction_id.clone(),loc.location_name.clone()))
                .or_default()+=1;
        }
        let mut building_by_location=std::collections::HashMap::<(String,String),usize>::new();
        for site in world.query::<&ConstructionSite>().iter(world) {
            if !site.completed && site.facility_type!="station" {
                *building_by_location.entry((site.faction_id.clone(),site.location_name.clone()))
                    .or_default()+=1;
            }
        }
        let mut live: std::collections::HashSet<String> = Default::default();
        for e in entities {
            let Some(identity) = world.get::<FacilityIdentity>(e) else {
                continue;
            };
            let Some(location) = world.get::<FacilityLocation>(e) else {
                continue;
            };
            let Some(ops) = world.get::<FacilityOperations>(e) else {
                continue;
            };
            let Some(storage) = world.get::<FacilityStorage>(e) else {
                continue;
            };
            let body_center = body_pos
                .get(&identity.body_id)
                .copied()
                .unwrap_or((0.0, 0.0));
            // Every module sharing a station location has one physical
            // orbital anchor; the module sockets are local station geometry.
            let angle = world.get::<sim_core::agents::facility::FacilityOrbit>(e)
                .map(|v| v.angle_degrees)
                .unwrap_or_else(|| sim_core::agents::facility::facility_orbit_initial_angle(&location.location_name));
            let pos = sim_core::agents::facility::facility_orbit_position(body_center, angle);
            let docked_ship_ids: Vec<String> = storage
                .docked_ships
                .iter()
                .filter_map(|e| ship_id_by_entity.get(e).cloned())
                .collect();
            let dock_queue_ids: Vec<String> = storage
                .dock_queue
                .iter()
                .filter_map(|e| ship_id_by_entity.get(e).cloned())
                .collect();
            let lifecycle = world.get::<FacilityLifecycle>(e);
            let gate = world.get::<GateLink>(e);
            let module_stock = world.get::<sim_core::agents::facility::ModuleStock>(e);
            let fitting = world.get::<sim_core::agents::facility::FacilityFitting>(e);
            let crew = world.get::<sim_core::agents::facility::FacilityCrew>(e);
            let mut snap = FacilitySnapshot::build(
                &identity,
                &location,
                &ops,
                &storage,
                lifecycle,
                gate,
                module_stock,
                fitting,
                crew,
                sim_core::agents::Position::from(pos),
                docked_ship_ids,
                dock_queue_ids,
            );
            if identity.facility_type=="station" {
                let state=world.get_resource::<sim_core::strategy::director::Director>()
                    .and_then(|d|d.station_progress.get(&identity.id))
                    .cloned().unwrap_or_default();
                let built=modules_by_location.get(&(
                    identity.faction_id.clone(),location.location_name.clone()))
                    .copied().unwrap_or(0);
                let pending=building_by_location.get(&(
                    identity.faction_id.clone(),location.location_name.clone()))
                    .copied().unwrap_or(0);
                let cap=state.tier.max_modules();
                snap.station_core=Some(serde_json::json!({
                    "tier":format!("{:?}",state.tier).to_lowercase(),
                    "slot_capacity":cap,
                    "built":built,"in_progress":pending,
                    "used":built+pending,
                    "free":cap.saturating_sub(built+pending),
                    "upgrade_target":state.target
                        .map(|t|format!("{t:?}").to_lowercase()),
                    "upgrade_materials_installed":state.materials_installed,
                    "upgrade_labor_completed":state.labor_completed,
                    "upgrade_labor_required":state.target
                        .map(sim_core::strategy::progression::upgrade_work),
                    "upgrade_last_receipt_tick":state.last_receipt_tick,
                    "upgrade_blocked_reason":state.blocked_reason,
                }));
            }
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

    fn update_populations(&self, world: &mut World, _store: &mut AgentStore) {
        let mut q =
            world.query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>();
        for (identity, demo, econ, sent) in q.iter(&world) {
            let snap = PopSnapshot::build(identity, demo, econ, sent);
            self.populations.insert(identity.id.clone(), snap);
        }
    }

    fn update_bodies(&self, world: &mut World, _store: &mut AgentStore) {
        // Bundle D: BodyTerritory is optional — newly-spawned bodies that
        // haven't been through `derive_territorial_control` yet won't
        // carry one. The snapshot defaults those to `None / not contested`,
        // matching the `BodyTerritory::default()` behaviour at boot.
        let mut q =
            world.query::<(&BodyIdentity, &BodyOrbit, &BodyBiome, Option<&BodyTerritory>, Option<&BodyResources>)>();
        for (identity, orbit, biome, territory, resources) in q.iter(&world) {
            let snap = BodySnapshot::build(identity, orbit, biome, territory, resources);
            self.positions
                .insert(identity.body_id.clone(), (snap.universe_position.x, snap.universe_position.y));
            self.bodies.insert(identity.body_id.clone(), snap);
        }
    }

    fn update_factions(&self, world: &mut World, _store: &mut AgentStore) {
        let mut q = world.query::<&FactionData>();
        for data in q.iter(&world) {
            self.factions
                .insert(data.id.clone(), FactionSnapshot::build(data));
        }
    }
}

// Facility offset logic moved to sim_core so sim_core::agents::ship can use
// the same function for transit endpoints (ships aim at the station's
// actual offset, not the body center).
use sim_core::agents::facility::facility_offset_position;
 
/// Visual orbit anchor for an in-progress construction site. When its parent
/// body exists, the site's published coordinate follows that body's orbit;
/// otherwise retain the saved coordinate for a readable legacy snapshot.
fn construction_site_orbit_position(
    body_positions: &std::collections::HashMap<String, (f32, f32)>,
    body_id: &str,
    site_id: &str,
    saved_position: (f32, f32),
) -> (f32, f32) {
    body_positions
        .get(body_id)
        .map(|&center| facility_offset_position(center, site_id))
        .unwrap_or(saved_position)
}

#[cfg(test)]
mod construction_site_orbit_tests {
    use super::*;

    #[test]
    fn site_moves_with_body_and_retains_its_relative_offset() {
        let mut bodies = std::collections::HashMap::new();
        bodies.insert("jupiter".to_string(), (5.0, 0.0));
        let first = construction_site_orbit_position(
            &bodies, "jupiter", "site-water-jupiter-600", (9.0, 9.0),
        );
        bodies.insert("jupiter".to_string(), (3.0, 4.0));
        let second = construction_site_orbit_position(
            &bodies, "jupiter", "site-water-jupiter-600", (9.0, 9.0),
        );
        assert!(((second.0 - first.0) + 2.0).abs() < 0.0001);
        assert!(((second.1 - first.1) - 4.0).abs() < 0.0001);
        let radius = sim_core::agents::facility::FACILITY_ORBIT_RADIUS;
        assert!(((first.0 - 5.0).hypot(first.1) - radius).abs() < 0.0001);
    }

    #[test]
    fn missing_parent_keeps_saved_snapshot_position() {
        let bodies = std::collections::HashMap::new();
        assert_eq!(
            construction_site_orbit_position(
                &bodies, "missing-body", "site-orphan", (2.5, -1.0),
            ),
            (2.5, -1.0)
        );
    }
}

