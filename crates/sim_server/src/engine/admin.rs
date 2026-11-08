//! Admin (operator-override) handlers + refit family.
//!
//! Every entry point here is reachable two ways:
//!   * Over HTTP via `http::admin` (POST /api/admin/...) — the
//!     headless `simulator` binary's path.
//!   * In-process from `client_bevy` via `process_*` systems that
//!     call these `pub fn`s directly. Skipping the HTTP marshalling
//!     was the whole point of the embedded-arch pivot.
//!
//! ## Spawn / remove
//!   * [`admin_spawn_ship`] / [`admin_spawn_facility`] build a fresh
//!     hecs bundle from a CRUD payload + an already-INSERTed db_id.
//!     The HTTP handler does the row write; we just hydrate.
//!   * [`admin_remove_ship`] / [`admin_remove_facility`] cascade the
//!     delete: contract holdings released, dock entries kicked,
//!     paired-gate back-references cleared. Both `pub(super)` so
//!     [`super::drains`] can call admin_remove_ship from the
//!     decommission drain.
//!
//! ## Refit family
//!   * [`apply_fitting_swap`] — the lowest-level rebake (writes the
//!     slot, recomputes derived stats, bakes new cargo capacity / fuel
//!     speed into ShipCargo / ShipFuel so tick code reads unchanged
//!     fields).
//!   * [`try_shipyard_refit`] / [`commit_shipyard_refit`] — the
//!     two-phase shipyard path: try validates dock + stock + price,
//!     commit decrements stock + debits credits + applies. Split so
//!     the planner can speculate.
//!   * [`admin_refit_ship`] / [`admin_refit_facility`] — operator
//!     override that bypasses the shipyard validation. `via_shipyard`
//!     param routes to the validating path or the override path.
//!   * [`RefitAttempt`] — outcome enum used by both legacy callers
//!     and tests.
//!
//! ## Other
//!   * [`admin_grant_ship_xp`] — direct write into ShipProgression
//!     (banks retrofit points the way a real delivery would).
//!   * [`admin_market_supply_delta`] — operator-tuned per-commodity
//!     stockpile tweak; emits a `market_supply_adjusted` event.
//!   * [`admin_set_relations`] — operator-set faction standing /
//!     treaty; emits `faction_standing_changed`. Useful for dev-time
//!     scenario testing of the relations matrix.
//!
//! Extracted from `engine.rs` in the Phase-21 god-module split.

use bevy_ecs::prelude::{Entity, World};
use sim_core::agents::market::MarketPricing;
use sim_core::simulation::spawner::AgentStore;
use sim_core::world::registry::WorldRegistry;
use sim_db::persistence::DbWrite;
use tokio::sync::mpsc;

/// Admin: spawn a new ship hecs entity from an already-INSERTed DB row.
/// The HTTP handler wrote the DB row and handed us the db_id; we build
/// the matching hecs bundle here and index it.
pub fn admin_spawn_ship(
    world: &mut World,
    store: &mut AgentStore,
    _registry: &WorldRegistry,
    payload: crate::control::AdminSpawnShipPayload,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::{
        agents::ship::{
            CrewTask, ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFuel,
            ShipIdentity, ShipLifecycle, ShipMemory, ShipPosition, ShipTransit,
        },
        ai::personality::Personality,
    };

    // Skip if a ship with this id was somehow already spawned (retry / dup).
    if store.ship_by_id.contains_key(&payload.agent_id) {
        return;
    }

    let class_cfg = sim_core::simulation::config::ship_class(&payload.class);
    let (cargo_cap, fuel_cap, fuel_rate, speed_mod, crew_size, crew_roles) = class_cfg
        .map(|c| {
            (
                c.cargo_capacity,
                c.fuel_capacity,
                c.fuel_consumption_base,
                c.speed_modifier,
                c.crew_size,
                c.crew_roles,
            )
        })
        .unwrap_or((500, 100.0, 0.05, 1.0, 5, &[] as &[&str]));

    // Phase 18a/f: admin-spawned ships use the size-aware default
    // fitting. The class's default_size drives sensor tier — a
    // hauler spawns with tier-2 sensors and can bid on cross-system
    // contracts day one; a courier starts with tier-1 and is
    // restricted to intra-system work until it retrofits.
    let size = class_cfg
        .map(|c| c.default_size)
        .unwrap_or(sim_core::simulation::config::ShipSize::Medium);
    let fitting = sim_core::agents::ship::ShipFitting::new_for_size(size, &payload.agent_id);
    let cargo_cap = ((cargo_cap as f32) * fitting.derived.cargo_capacity_mult).round() as u32;
    // Phase 18g: size-driven speed penalty, compounded with class +
    // fitting modifiers.
    let speed_mod = speed_mod * fitting.derived.speed_mult * size.speed_multiplier();

    let entity = world.spawn((
        ShipIdentity {
            db_id: payload.db_id,
            id: payload.agent_id.clone(),
            name: payload.name.clone(),
            class: payload.class.clone(),
            faction_id: payload.faction_id.clone(),
            size,
        },
        ShipPosition {
            location_name: Some(payload.location_name.clone()),
            docked_at: None,
            system_id: String::new(),
            universe_offset: payload.universe_offset,
            position: payload.position,
        },
        ShipTransit { transit: None },
        ShipCargo {
            cargo: std::collections::HashMap::new(),
            capacity: cargo_cap,
            cargo_age: std::collections::HashMap::new(),
            cargo_origin: std::collections::HashMap::new(),
        },
        ShipFuel {
            fuel: fuel_cap,
            fuel_capacity: fuel_cap,
            fuel_consumption_rate: fuel_rate,
            speed_modifier: speed_mod,
        },
        ShipEconomy {
            transaction: Default::default(),
            credits: payload.credits,
            efficiency: 1.0,
            active_contract_id: None,
            faction_reputation: std::collections::HashMap::new(),
            dock_dwell_start_tick: None,
                rest_start_tick: None,
                dock_attempt_start_tick: None,
        },
        ShipAI {
            // Phase 18i: admin-spawned ships take a class-appropriate
            // archetype — couriers get the courier archetype,
            // haulers get opportunistic_trucker, etc. The admin UI
            // will add a personality picker later; until then, class
            // is the best proxy for role-bias.
            personality: Personality::for_class(&payload.class),
            current_goal: "idle".to_string(),
            current_bt: None,
            current_goal_score: 0.0,
            last_plan_tick: 0,
        },
    )).id();
    world.entity_mut(entity).insert((
        ShipMemory {
            price_knowledge: std::collections::HashMap::new(),
            visited: vec![payload.location_name.clone()],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        },
        ShipLifecycle {
            broke_strikes: 0,
            hoard_strikes: 0,
            idle_ticks: 0,
            dirty: true, // ensure first persistence flush
        },
        ShipCrew {
            size: crew_size,
            hunger: 10.0,
            morale: 70.0,
            fatigue: 10.0,
            health: 100.0,
            wages_credits: 0,
            current_task: CrewTask::Idle,
            dirty: false,
        },
        ShipCrewSkills::for_roles(crew_roles),
        fitting,
        sim_core::agents::ship::ShipProgression::new(),
        sim_core::simulation::lod::AgentLod::new(),
    ));
    store.index_ship(payload.agent_id.clone(), entity);

    events.push(serde_json::json!({
        "kind": "ship_spawned",
        "id": payload.agent_id,
        "db_id": payload.db_id,
        "class": payload.class,
        "location": payload.location_name,
        "reason": "admin",
    }));
}

/// Admin: spawn a new facility hecs entity from an already-INSERTed DB row.
pub fn admin_spawn_facility(
    world: &mut World,
    store: &mut AgentStore,
    payload: crate::control::AdminSpawnFacilityPayload,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::facility::{
        FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations, FacilityStorage,
        FacilityOrbit, current_facility_orbit_angle,
    };

    if store.facility_by_id.contains_key(&payload.agent_id) {
        return;
    }

    let orbit_angle = current_facility_orbit_angle(world, &payload.location_name);
    let entity = world.spawn((
        FacilityIdentity {
            db_id: payload.db_id,
            id: payload.agent_id.clone(),
            name: payload.name.clone(),
            facility_type: payload.facility_type.clone(),
            faction_id: payload.faction_id.clone(),
            body_id: payload.body_id.clone(),
        },
        FacilityLocation {
            location_id: payload.location_id,
            location_name: payload.location_name.clone(),
        },
        FacilityOperations {
            docking_capacity: payload.docking_capacity,
            services: vec!["market".to_string()],
            condition: payload.condition,
            reputation: payload.reputation,
            credits: payload.credits,
            dirty: true,
            starving_notified: false,
        },
        FacilityStorage {
            reserves: std::collections::HashMap::new(),
            docked_ships: vec![],
            pending_deliveries: vec![],
            dock_queue: vec![],
        },
        FacilityLifecycle::new(),
        FacilityOrbit::new(&payload.location_name, Some(orbit_angle)),
        sim_core::simulation::lod::AgentLod::new(),
    )).id();
    // Phase 18c: shipyards carry a ModuleStock. Attached separately so
    // non-shipyards don't pay the component cost.
    if payload.facility_type == "shipyard" {
        world
            .entity_mut(entity)
            .insert(sim_core::agents::facility::ModuleStock::default());
    }
    // Phase 18e: all non-gate facilities get a default FacilityFitting.
    if payload.facility_type != "gate" {
        world
            .entity_mut(entity)
            .insert(sim_core::agents::facility::FacilityFitting::new_default());
    }
    // Phase 19a: every facility (gates included) gets a crew complement
    // sized by type. Admin-spawned facilities pick the default the same
    // way seed-loaded ones do.
    world
        .entity_mut(entity)
        .insert(sim_core::agents::facility::FacilityCrew::new_for_type(
            &payload.facility_type,
        ));
    store.index_facility(
        payload.agent_id.clone(),
        payload.location_name.clone(),
        entity,
    );

    events.push(serde_json::json!({
        "kind": "facility_spawned",
        "id": payload.agent_id,
        "db_id": payload.db_id,
        "facility_type": payload.facility_type,
        "location": payload.location_name,
        "body_id": payload.body_id,
        "reason": "admin",
    }));
}

/// Admin: remove a ship by its agent id. Despawns the hecs entity and
/// clears it from any facility `docked_ships` list it was sitting in.
pub(super) async fn admin_remove_ship(
    world: &mut World,
    store: &mut AgentStore,
    id: &str,
    tick_now: u64,
    events: &mut Vec<serde_json::Value>,
    _persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::{
        facility::FacilityStorage,
        ship::{ShipCrew, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle, ShipPosition},
    };
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };
    if store.contracts.iter().any(|c| c.fulfiller_id.as_deref() == Some(id)
        && c.funding.as_ref().is_some_and(|f| f.embarked.is_some()))
    {
        events.push(serde_json::json!({"kind":"ship_removal_blocked","ship_id":id,"reason":"passengers_aboard"}));
        return;
    }
    // Capture retirement snapshot BEFORE despawn so the ledger has a
    // full last-known state. Phase 19g — kept even after the ships
    // row is deleted so the player can scroll back through
    // decommissioned ships in the details panel.
    let retirement_row = {
        let identity = world.get::<ShipIdentity>(entity);
        let position = world.get::<ShipPosition>(entity);
        let econ = world.get::<ShipEconomy>(entity);
        let crew = world.get::<ShipCrew>(entity);
        let fuel = world.get::<ShipFuel>(entity);
        let life = world.get::<ShipLifecycle>(entity);
        identity.map(|id_ref| sim_db::persistence::RetirementRow {
            agent_id: id_ref.id.clone(),
            name: id_ref.name.clone(),
            class: id_ref.class.clone(),
            faction_id: id_ref.faction_id.clone(),
            final_location: position
                .as_ref()
                .and_then(|p| p.location_name.clone())
                .unwrap_or_default(),
            final_credits: econ.as_ref().map(|e| e.credits).unwrap_or(0),
            final_crew_morale: crew
                .as_ref()
                .map(|c| c.morale.round().clamp(0.0, 100.0) as i32)
                .unwrap_or(0),
            final_fuel_pct: fuel
                .as_ref()
                .map(|f| {
                    if f.fuel_capacity <= 0.0 {
                        0
                    } else {
                        ((f.fuel / f.fuel_capacity) * 100.0).round() as i32
                    }
                })
                .unwrap_or(0),
            broke_strikes: life.as_ref().map(|l| l.broke_strikes as i32).unwrap_or(0),
            hoard_strikes: life.as_ref().map(|l| l.hoard_strikes as i32).unwrap_or(0),
            retired_at_tick: tick_now as i64,
            reason: "admin".to_string(),
        })
    };
    let db_id = world
        .get::<ShipIdentity>(entity)
        .map(|i| i.db_id);
    // Pop from any facility's docked list AND dock queue first —
    // otherwise a despawned entity sits in a queue forever blocking
    // the head.
    {
        let mut q = world.query::<&mut FacilityStorage>();
        for mut storage in q.iter_mut(world) {
            storage.docked_ships.retain(|&e| e != entity);
            storage.dock_queue.retain(|&e| e != entity);
        }
    }
    // Release every contract the ship was fulfilling so the board
    // doesn't leave Accepted contracts pinned to a despawned ship
    // (nothing else can pick them up — `release()` guards on
    // fulfiller_id, so the contract would sit forever). Accepted →
    // back to Posted; PickedUp → Expired (cargo was aboard the ship,
    // so the contract can't be salvaged).
    let drop = store.contracts.drop_ship_holdings(id);
    for cid in &drop.released {
        events.push(serde_json::json!({
            "kind": "contract_released",
            "id": cid,
            "reason": "ship_destroyed",
            "ship_id": id,
        }));
    }
    for cid in &drop.cancelled {
        events.push(serde_json::json!({
            "kind": "contract_expired",
            "id": cid,
            "reason": "ship_destroyed_with_cargo",
            "ship_id": id,
        }));
    }
    world.despawn(entity);
    store.ship_by_id.remove(id);
    // Snapshot cache is purged by `update_from` on the next tick (diffs
    // live entity ids against the cache and removes missing keys).
    if let Some(db_id) = db_id {
        super::persist::queue_lifecycle_write(world, DbWrite::DeleteShip { db_id });
    }
    if let Some(row) = retirement_row {
        super::persist::queue_lifecycle_write(world, DbWrite::RetireShip { row });
    }
    events.push(serde_json::json!({
        "kind": "ship_decommissioned",
        "id": id,
        "reason": "admin",
    }));
}

/// Admin: remove a facility by agent id. The body's facility index list
/// is cleaned up too, otherwise future restock/contract scans would
/// crash.
pub(super) async fn admin_remove_facility(
    world: &mut World,
    store: &mut AgentStore,
    id: &str,
    events: &mut Vec<serde_json::Value>,
    _persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation, GateLink};
    use sim_core::agents::ship::ShipPosition;
    let Some(&entity) = store.facility_by_id.get(id) else {
        return;
    };
    // Snapshot everything we need BEFORE mutating anything, so we can
    // cascade cleanup without re-querying a half-deleted world.
    let db_id = world
        .get::<FacilityIdentity>(entity)
        .map(|i| i.db_id);
    let location_name = world
        .get::<FacilityLocation>(entity)
        .map(|l| l.location_name.clone());
    if location_name.as_ref().is_some_and(|location| {
        world.query::<&sim_core::agents::construction::ConstructionSite>().iter(world)
            .any(|site| site.location_name == *location && site.labor.colony_source.is_some())
        || store.contracts.iter().any(|c| c.destination_location == *location
            && c.funding.as_ref().is_some_and(|f| f.embarked.is_some()))
    }) {
        events.push(serde_json::json!({"kind":"facility_removal_blocked","facility_id":id,"reason":"active_colony_or_passengers"}));
        return;
    }
    let paired_gate_id = world
        .get::<GateLink>(entity)
        .map(|g| g.paired_gate_id.clone());

    // 1. Kick every ship docked at this facility. Without this, the
    //    ship's `docked_at` entity handle points at a despawned
    //    entity and any future tick that reads it hits an invalid
    //    component fetch. Setting `docked_at = None` forces the ship
    //    to replan — it's still at `location_name`, so if another
    //    facility exists there it'll pick one via the usual dock
    //    fallback path (18k); if not, the ship undocks into space
    //    and moves on.
    let kicked: Vec<String> = {
        let mut out = Vec::new();
        let mut q = world
            .query::<(&sim_core::agents::ship::ShipIdentity, &mut ShipPosition)>();
        for (identity, mut pos) in q.iter_mut(world) {
            if pos.docked_at == Some(entity) {
                pos.docked_at = None;
                out.push(identity.id.clone());
            }
        }
        out
    };
    for ship_id in &kicked {
        events.push(serde_json::json!({
            "kind": "ship_undocked",
            "id": ship_id,
            "reason": "facility_destroyed",
            "facility_id": id,
        }));
    }

    // 2. Remove from facilities_at_location map, then check whether
    //    any other facility still serves this location. That decides
    //    whether contracts targeting this location are rescuable by
    //    another facility or have to be cancelled outright.
    for entries in store.facilities_at_location.values_mut() {
        entries.retain(|&e| e != entity);
    }
    let location_still_served = location_name
        .as_ref()
        .and_then(|loc| store.facilities_at_location.get(loc))
        .map(|v| !v.is_empty())
        .unwrap_or(false);

    // 3. Cancel contracts that can't survive this facility going
    //    away: always cancel where this facility is the requestor;
    //    also cancel by source / destination location if this was
    //    the LAST facility there (otherwise remaining facilities can
    //    still service the run).
    let (src_filter, dst_filter) = if location_still_served {
        (None, None)
    } else {
        (location_name.as_deref(), location_name.as_deref())
    };
    let cancelled = store
        .contracts
        .cancel_for_facility(Some(id), src_filter, dst_filter);
    for cid in &cancelled {
        events.push(serde_json::json!({
            "kind": "contract_expired",
            "id": cid,
            "reason": "facility_destroyed",
            "facility_id": id,
        }));
    }

    // 4. Gate delete: null out the paired gate's back-reference so a
    //    ship trying to jump the other way gets a clean "no pair"
    //    failure instead of reaching a despawned entity. Keep the
    //    GateLink component but clear the id — the paired gate is
    //    still a valid facility; it just has nowhere to point.
    if let Some(paired_id) = paired_gate_id {
        if let Some(&paired_entity) = store.facility_by_id.get(&paired_id) {
            if let Some(mut link) = world.get_mut::<GateLink>(paired_entity) {
                link.paired_gate_id.clear();
            }
            events.push(serde_json::json!({
                "kind": "gate_unpaired",
                "id": paired_id,
                "reason": "paired_gate_destroyed",
                "removed_pair": id,
            }));
        }
    }

    world.despawn(entity);
    store.facility_by_id.remove(id);
    if let Some(db_id) = db_id {
        super::persist::queue_lifecycle_write(world, DbWrite::DeleteFacility { db_id });
    }
    events.push(serde_json::json!({
        "kind": "facility_removed",
        "id": id,
        "reason": "admin",
        "kicked_ships": kicked.len(),
        "cancelled_contracts": cancelled.len(),
    }));
}

/// Admin: apply a supply delta to the market at `location`. Positive
/// values top up, negative drain (floored at 0). No-ops if the location
/// has no market.
/// Admin: grant XP to a specific ship. Cascades level-ups + retrofit
/// point banking. No-op on unknown ship.
pub(super) fn admin_grant_ship_xp(
    world: &mut World,
    store: &mut AgentStore,
    id: &str,
    amount: u32,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::ship::ShipProgression;
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };
    let Some(mut prog) = world.get_mut::<ShipProgression>(entity) else {
        return;
    };
    let gained = prog.grant_xp(amount);
    if gained > 0 {
        events.push(serde_json::json!({
            "kind": "ship_leveled_up",
            "id": id,
            "new_level": prog.level,
            "retrofit_points": prog.retrofit_points,
            "levels_gained": gained,
            "reason": "admin_grant",
        }));
    }
}

/// Outcome of applying a subsystem refit. `RefitAttempt::Applied`
/// carries the prior slug (for event telemetry); the rejection
/// variants name the specific validation that failed so the engine
/// can decide whether to emit an event, log, or silently drop.
#[allow(dead_code)]
#[derive(Debug)]
pub enum RefitAttempt {
    Applied { prev_slug: Option<String> },
    NoShip,
    NoClass,
    InvalidSlug,
    NotDocked,
    NotShipyard,
    NoStock,
    InsufficientCredits,
}

/// Perform the fitting swap + rebake (cargo capacity, speed modifier).
/// Pure local — no shipyard economy interaction. Shared by admin
/// override refits and the admin/agent shipyard paths.
pub fn apply_fitting_swap(
    world: &mut World,
    ship: Entity,
    slot: sim_core::modules::Slot,
    slug: Option<&'static str>,
) -> RefitAttempt {
    use sim_core::agents::ship::{ShipCargo, ShipFitting, ShipFuel, ShipIdentity, ShipLifecycle};

    let class_name = match world.get::<ShipIdentity>(ship) {
        Some(id) => id.class.clone(),
        None => return RefitAttempt::NoShip,
    };
    let class_cfg = sim_core::simulation::config::ship_class(&class_name);
    let (base_cargo, base_speed) = match class_cfg {
        Some(c) => (c.cargo_capacity, c.speed_modifier),
        None => return RefitAttempt::NoClass,
    };

    let (prev_slug, new_derived) = {
        let mut fitting = match world.get_mut::<ShipFitting>(ship) {
            Some(f) => f,
            None => return RefitAttempt::NoShip,
        };
        let prev = fitting.slot_slug(slot).map(|s| s.to_string());
        fitting.set(slot, slug);
        (prev, fitting.derived)
    };

    if let Some(mut cargo) = world.get_mut::<ShipCargo>(ship) {
        cargo.capacity = ((base_cargo as f32) * new_derived.cargo_capacity_mult).round() as u32;
    }
    if let Some(mut fuel) = world.get_mut::<ShipFuel>(ship) {
        fuel.speed_modifier = base_speed * new_derived.speed_mult;
    }
    if let Some(mut life) = world.get_mut::<ShipLifecycle>(ship) {
        life.dirty = true;
    }

    RefitAttempt::Applied { prev_slug }
}

/// Validate that a shipyard refit is allowed right now and do the
/// economic side (debit ship, credit yard, decrement stock). Returns
/// `Applied` when the fitting swap should proceed + the caller's
/// extra work (event emit, retrofit-point consumption) should fire.
/// Never mutates the fitting itself — caller does that via
/// [`apply_fitting_swap`] after validation passes.
pub fn try_shipyard_refit(
    world: &mut World,
    ship: Entity,
    slot: sim_core::modules::Slot,
    slug: &'static str,
) -> Result<(Entity, String, i64), RefitAttempt> {
    use sim_core::agents::facility::{FacilityIdentity, ModuleStock};
    use sim_core::agents::ship::{ShipEconomy, ShipPosition};

    // Slug must match slot (defence-in-depth; HTTP layer validated).
    match sim_core::modules::get(slug) {
        Some(def) if def.slot == slot => {}
        _ => return Err(RefitAttempt::InvalidSlug),
    }
    let recipe = match sim_core::economy::module_production::get(slug) {
        Some(r) => r,
        None => return Err(RefitAttempt::InvalidSlug),
    };
    let cost = recipe.base_cost_credits;

    let docked_at = match world.get::<ShipPosition>(ship) {
        Some(pos) => pos.docked_at,
        None => return Err(RefitAttempt::NoShip),
    };
    let Some(facility_entity) = docked_at else {
        return Err(RefitAttempt::NotDocked);
    };

    let (fid_str, is_yard) = match world.get::<FacilityIdentity>(facility_entity) {
        Some(id) => (id.id.clone(), id.facility_type == "shipyard"),
        None => return Err(RefitAttempt::NotShipyard),
    };
    if !is_yard {
        return Err(RefitAttempt::NotShipyard);
    }

    let in_stock = world
        .get::<ModuleStock>(facility_entity)
        .map(|s| s.count(slug) > 0)
        .unwrap_or(false);
    if !in_stock {
        return Err(RefitAttempt::NoStock);
    }

    let has_credits = world
        .get::<ShipEconomy>(ship)
        .map(|e| e.credits >= cost)
        .unwrap_or(false);
    if !has_credits {
        return Err(RefitAttempt::InsufficientCredits);
    }

    Ok((facility_entity, fid_str, cost))
}

/// Commit the shipyard economic side-effects once validation + swap
/// have succeeded. Split from `try_shipyard_refit` so the caller can
/// order {validate → swap → commit} and guarantee atomicity at the
/// tick-phase boundary.
pub fn commit_shipyard_refit(
    world: &mut World,
    ship: Entity,
    facility_entity: Entity,
    slug: &'static str,
    cost: i64,
) {
    use sim_core::agents::facility::{FacilityOperations, ModuleStock};
    use sim_core::agents::ship::ShipEconomy;

    if let Some(mut stock) = world.get_mut::<ModuleStock>(facility_entity) {
        stock.take_one(slug);
    }
    if let Some(mut econ) = world.get_mut::<ShipEconomy>(ship) {
        econ.credits = econ.credits.saturating_sub(cost);
    }
    if let Some(mut ops) = world.get_mut::<FacilityOperations>(facility_entity) {
        ops.credits = ops.credits.saturating_add(cost);
        ops.dirty = true;
    }
}

/// Admin (Phase 18e): swap the module in one slot of a facility's
/// fitting. Validates slug is in the facility catalog + matches the
/// slot, then updates `FacilityFitting` in place — the next recipe
/// tick reads the new derived stats automatically.
pub(super) fn admin_refit_facility(
    world: &mut World,
    store: &mut AgentStore,
    id: &str,
    slot: sim_core::facility_modules::FacilitySlot,
    slug: Option<&str>,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::facility::FacilityFitting;

    let Some(&entity) = store.facility_by_id.get(id) else {
        return;
    };
    let interned: Option<&'static str> = match slug {
        None => None,
        Some(s) => match sim_core::facility_modules::get(s) {
            Some(def) if def.slot == slot => Some(def.slug),
            _ => return,
        },
    };
    let prev_slug: Option<String> = {
        let Some(mut fit) = world.get_mut::<FacilityFitting>(entity) else {
            return;
        };
        let prev = fit.slot_slug(slot).map(|s| s.to_string());
        fit.set(slot, interned);
        prev
    };
    events.push(serde_json::json!({
        "kind": "facility_refitted",
        "id": id,
        "slot": slot.as_str(),
        "from": prev_slug,
        "to": interned,
    }));
}

/// Admin: swap the module in one slot of a ship's fitting. Looks up the
/// ship, validates the new slug (catalog presence + slot match),
/// updates `ShipFitting`, and rebakes `ShipCargo.capacity` + `ShipFuel
/// .speed_modifier` from the class base × the new derived multipliers.
/// Silently no-ops on unknown ship, unknown slug, or slot mismatch —
/// HTTP layer validates and returns 4xx before we even get here, so
/// this is defence-in-depth against stale control messages.
///
/// When `via_shipyard` is true, additionally requires the ship to be
/// docked at a shipyard with `slug` in stock, and debits the ship +
/// credits the shipyard + decrements the stock. Both paths emit a
/// `ship_refitted` event with the economic context attached.
pub fn admin_refit_ship(
    world: &mut World,
    store: &mut AgentStore,
    id: &str,
    slot: sim_core::modules::Slot,
    slug: Option<&str>,
    via_shipyard: bool,
    events: &mut Vec<serde_json::Value>,
) {
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };

    // Intern the slug so it lives in `&'static` memory — required by
    // `ShipFitting::set`. `None` (clear slot) is also valid.
    let interned: Option<&'static str> = match slug {
        None => None,
        Some(s) => match sim_core::modules::get(s) {
            Some(def) if def.slot == slot => Some(def.slug),
            _ => return,
        },
    };

    if via_shipyard {
        let Some(slug_s) = interned else { return };
        let Ok((fac_entity, fac_id, cost)) = try_shipyard_refit(world, entity, slot, slug_s) else {
            return;
        };
        let prev_slug = match apply_fitting_swap(world, entity, slot, interned) {
            RefitAttempt::Applied { prev_slug } => prev_slug,
            _ => return,
        };
        commit_shipyard_refit(world, entity, fac_entity, slug_s, cost);
        events.push(serde_json::json!({
            "kind": "ship_refitted",
            "id": id,
            "slot": slot.as_str(),
            "from": prev_slug,
            "to": interned,
            "via": "shipyard",
            "shipyard_id": fac_id,
            "cost": cost,
        }));
    } else {
        let prev_slug = match apply_fitting_swap(world, entity, slot, interned) {
            RefitAttempt::Applied { prev_slug } => prev_slug,
            _ => return,
        };
        events.push(serde_json::json!({
            "kind": "ship_refitted",
            "id": id,
            "slot": slot.as_str(),
            "from": prev_slug,
            "to": interned,
            "via": "admin",
        }));
    }
}
pub(super) fn admin_market_supply_delta(
    world: &mut World,
    store: &mut AgentStore,
    location: &str,
    deltas: &[(sim_core::economy::commodities::Commodity, f32)],
    events: &mut Vec<serde_json::Value>,
) {
    let Some(&market_entity) = store.market_at_location.get(location) else {
        return;
    };
    let mut applied: Vec<(String, f32)> = Vec::new();
    if let Some(mut pricing) = world.get_mut::<MarketPricing>(market_entity) {
        for (commodity, delta) in deltas {
            let entry = pricing.supply.entry(*commodity).or_insert(0.0);
            *entry = (*entry + delta).max(0.0);
            applied.push((commodity.as_str().to_string(), *delta));
        }
    }
    if !applied.is_empty() {
        events.push(serde_json::json!({
            "kind": "market_supply_adjusted",
            "location": location,
            "deltas": applied.into_iter().map(|(c, d)| serde_json::json!({
                "commodity": c, "delta": d
            })).collect::<Vec<_>>(),
        }));
    }
}

/// Bundle A: admin override for the inter-faction relations matrix.
/// Sets standing / treaty (either or both) and emits a
/// `faction_standing_changed` event so the Godot ticker shows the
/// intervention. Read-only inputs — all invariants enforced inside
/// `FactionRelations::set_state`.
pub(super) fn admin_set_relations(
    store: &mut AgentStore,
    a: &str,
    b: &str,
    standing: Option<i32>,
    treaty: Option<sim_core::agents::faction_relations::TreatyKind>,
    tick: u64,
    events: &mut Vec<serde_json::Value>,
) {
    if a == b || a.is_empty() || b.is_empty() {
        return;
    }
    let existing = store.relations.state_or_default(a, b);
    let new_standing = standing.unwrap_or(existing.standing);
    let new_treaty = treaty.unwrap_or(existing.treaty);
    store.relations.set_state(a, b, new_standing, new_treaty, tick);
    events.push(serde_json::json!({
        "kind": "faction_standing_changed",
        "a": a,
        "b": b,
        "delta": new_standing - existing.standing,
        "new_standing": new_standing,
        "cause": "admin",
    }));
    if new_treaty != existing.treaty {
        events.push(serde_json::json!({
            "kind": "treaty_changed",
            "a": a,
            "b": b,
            "from": existing.treaty.as_str(),
            "to": new_treaty.as_str(),
            "standing": new_standing,
            "cause": "admin",
        }));
    }
}
