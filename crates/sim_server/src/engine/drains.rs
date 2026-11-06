//! Async drains for the three pending-X queues.
//!
//! `AgentStore` carries three queues that hold work the synchronous
//! tick can't do alone (they all need a `sqlx::SqlitePool` or a
//! tokio mpsc handle):
//!
//!   * **PendingMaterialization** — construction site finished, a
//!     real facility needs to spawn. Drained via
//!     [`drain_pending_materializations`]: queue creation metadata and source
//!     site deletion in the same economic frame, with stable negative DB IDs.
//!   * **PendingDecommission** — a ship hit `MAX_STRIKES` (broke
//!     or hoard) and needs to retire. Drained via
//!     [`drain_pending_decommissions`]: write a row into the
//!     retirement ledger, run the standard `admin_remove_ship` path
//!     (cascade contracts, kick docks, despawn entity), and queue a
//!     `PendingRespawn` so the fleet stays at steady-state size.
//!   * **PendingRespawn** — a retired ship's replacement is due.
//!     Drained via [`drain_pending_respawns`] +
//!     [`spawn_replacement_ship`]: deterministic seed-derived class /
//!     faction / location / name, then admin_spawn_ship the new ship.
//!
//! These three drains run twice per tick — once after the ship
//! phase's apply, once after the market phase's apply — so commands
//! emitted during either pass land in the same tick they were
//! generated. Order matters: materializations create new entities
//! that subsequent drains may want to reference.
//!
//! [`materialize_facility`] is the per-entity build-and-index
//! helper used by drain_pending_materializations; the
//! [`random_ship_name`] generator feeds spawn_replacement_ship and
//! some admin spawn paths.
//!
//! Extracted from `engine.rs` in the Phase-21 god-module split.

use bevy_ecs::prelude::World;
use sim_core::simulation::{spawner::AgentStore, tuning::WorldTuning};
use sim_core::world::registry::WorldRegistry;
use sim_db::persistence::DbWrite;
use tokio::sync::mpsc;

use super::admin::{admin_remove_ship, admin_spawn_ship};

/// Move construction creation into the same economic frame as the final
/// delivery, issuer debit and source-site removal. No direct SQL here.
pub(super) async fn drain_pending_materializations(
    world: &mut World,
    store: &mut AgentStore,
    _pool: &sqlx::SqlitePool,
    _persist_tx: &mpsc::Sender<DbWrite>,
    _events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::facility::FacilityIdentity;
    for req in std::mem::take(&mut store.pending_materializations) {
        if let Some(identity) = world.get::<FacilityIdentity>(req.entity) {
            let row = sim_db::persistence::ConstructedFacilityRow {
                db_id: identity.db_id, source_site_id: req.source_site_id.clone(),
                name: req.name, facility_type: req.facility_type, faction_id: req.faction_id,
                body_id: req.body_id, location_id: req.location_id, location_name: req.location_name,
                docking_capacity: req.docking_capacity, credits: req.credits,
                reputation: req.reputation, condition: req.condition,
            };
            super::persist::queue_lifecycle_write(world, DbWrite::ConstructedFacility { row });
        }
        super::persist::queue_lifecycle_write(world, DbWrite::ConstructionSiteDelete { agent_id: req.source_site_id });
    }
}

/// Constructed facilities use negative DB IDs; SQLite/admin seed IDs are
/// positive. Reserve synchronously so dock references are stable before flush.
#[derive(bevy_ecs::prelude::Resource)]
struct ConstructionIds(i64);

fn next_construction_id(world: &mut World) -> i64 {
    if !world.contains_resource::<ConstructionIds>() {
        let mut q = world.query::<&sim_core::agents::facility::FacilityIdentity>();
        let next = q.iter(world).map(|id| id.db_id).min().unwrap_or(0).min(0)
            .checked_sub(1).expect("construction ID space exhausted");
        world.insert_resource(ConstructionIds(next));
    }
    let mut ids = world.resource_mut::<ConstructionIds>();
    let id = ids.0;
    ids.0 = id.checked_sub(1).expect("construction ID space exhausted");
    id
}

/// Record each ship-originated command in the global debug trace
/// ring. Runs BEFORE `apply_ship_commands` on each pass so the
/// captured entry reflects what was requested, not the already-
/// applied outcome. Per-ship filtering happens on read — the ring is
/// Drain queued ship decommissions from the strike system. Each entry
/// runs the existing `admin_remove_ship` path (despawn + ledger row +
/// persistence delete + event) and schedules a `PendingRespawn` a few
/// hundred base-ticks out so fleet size recovers gradually rather than
/// instantly.
pub(super) async fn drain_pending_decommissions(
    world: &mut World,
    store: &mut AgentStore,
    tick: u64,
    events: &mut Vec<serde_json::Value>,
    persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::ship::ShipIdentity;
    let pending: Vec<sim_core::simulation::spawner::PendingDecommission> =
        std::mem::take(&mut store.pending_decommissions);
    if pending.is_empty() {
        return;
    }
    for req in pending {
        // Snapshot the ship's faction + id BEFORE despawn so the
        // respawn can prefer the same faction (losses register as
        // pressure before the weighted pick redistributes).
        let (ship_id, faction_id) = match world.get::<ShipIdentity>(req.entity) {
            Some(id) => (id.id.clone(), id.faction_id.clone()),
            None => continue,
        };
        // Overwrite the retirement reason by driving the existing
        // admin path; we want the same cleanup, just a different
        // ledger tag. admin_remove_ship sets reason = "admin" by
        // default — we patch the event afterwards so the reason
        // matches the strike trigger ("bankruptcy" / "stagnation").
        admin_remove_ship(world, store, &ship_id, tick, events, persist_tx).await;
        // Patch the most recent ship_decommissioned event's reason.
        if let Some(last) = events.last_mut() {
            if last.get("kind").and_then(|k| k.as_str()) == Some("ship_decommissioned") {
                if let Some(obj) = last.as_object_mut() {
                    obj.insert(
                        "reason".to_string(),
                        serde_json::Value::String(req.reason.to_string()),
                    );
                }
            }
        }
        if WorldTuning::current().auto_replace_retired_ships {
            // Preserve legacy stress-world steady-state fleet behavior.
            let delay = 300 + (tick % 300); // deterministic 300..=599 jitter
            store
                .pending_respawns
                .push(sim_core::simulation::spawner::PendingRespawn {
                    spawn_at_tick: tick + delay,
                    prefer_faction: Some(faction_id),
                });
        } else {
            // In Genesis ships are finite assets. This is deliberately NOT
            // a new ship-building mechanism: a hull must be constructed by
            // a real yard from real materials before it can join the fleet.
            events.push(serde_json::json!({
                "kind": "fleet_loss_unreplaced",
                "ship_id": ship_id,
                "faction_id": faction_id,
                "reason": req.reason,
                "tick": tick,
            }));
        }
    }
}

/// Drain replacement-ship spawns whose `spawn_at_tick` has arrived.
/// Picks a faction / class / location / name deterministically from
/// the current world state so the replacement reads as an organic new
/// captain commissioning, not a dev-console injection.
pub(super) async fn drain_pending_respawns(
    world: &mut World,
    store: &mut AgentStore,
    registry: &WorldRegistry,
    tick: u64,
    events: &mut Vec<serde_json::Value>,
    persist_tx: &mpsc::Sender<DbWrite>,
    pool: &sqlx::SqlitePool,
) {
    if !WorldTuning::current().auto_replace_retired_ships {
        // Also suppress a queued replacement if world policy changes to
        // finite ships (or the queue was created before the rule loaded).
        // Never silently convert a retirement into a free new hull.
        for req in std::mem::take(&mut store.pending_respawns) {
            events.push(serde_json::json!({
                "kind": "free_respawn_suppressed",
                "faction_id": req.prefer_faction,
                "scheduled_at_tick": req.spawn_at_tick,
                "tick": tick,
            }));
        }
        return;
    }
    let ready: Vec<sim_core::simulation::spawner::PendingRespawn> = {
        let mut pending = std::mem::take(&mut store.pending_respawns);
        let (due, keep): (Vec<_>, Vec<_>) =
            pending.drain(..).partition(|r| r.spawn_at_tick <= tick);
        store.pending_respawns = keep;
        due
    };
    if ready.is_empty() {
        return;
    }
    for req in ready {
        if let Err(e) = spawn_replacement_ship(world, store, registry, pool, persist_tx, tick, &req, events)
            .await
        {
            events.push(serde_json::json!({
                "kind": "respawn_failed",
                "prefer_faction": req.prefer_faction,
                "error": format!("{e}"),
            }));
        }
    }
}

/// Spawn a randomised replacement ship: picks a class, faction, and
/// starting location from the live world; mirrors the admin HTTP
/// spawn path (same JOIN + INSERT + AdminSpawnShipPayload) so
/// persistence + snapshot stay consistent.
#[allow(clippy::too_many_arguments)]
async fn spawn_replacement_ship(
    world: &mut World,
    store: &mut AgentStore,
    registry: &WorldRegistry,
    pool: &sqlx::SqlitePool,
    _persist_tx: &mpsc::Sender<DbWrite>,
    tick: u64,
    req: &sim_core::simulation::spawner::PendingRespawn,
    events: &mut Vec<serde_json::Value>,
) -> anyhow::Result<()> {
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation, FacilityOperations};
    use sqlx::Row;

    // Classes we're happy to generate. Avoids specialist slots
    // (e.g. shipyard-only) that wouldn't make sense as a fresh
    // captain's starter pick.
    const CANDIDATE_CLASSES: &[&str] =
        &["courier", "freighter", "hauler", "tanker", "miner"];

    // Deterministic-but-varying picker: hash tick + prior faction so
    // multiple retirements on the same tick still pick different
    // slots instead of colliding.
    let seed = tick
        .wrapping_mul(6364136223846793005)
        .wrapping_add(
            req.prefer_faction
                .as_deref()
                .map(|s| s.bytes().map(|b| b as u64).sum())
                .unwrap_or(0),
        );
    let class = CANDIDATE_CLASSES[(seed as usize) % CANDIDATE_CLASSES.len()];

    // Faction: 70% chance stick with the retired ship's faction
    // (losses register as "that faction is down a ship" pressure);
    // else pick the faction with the fewest active ships right now
    // (adaptive pressure — underdogs get replenishment).
    let use_hint = (seed >> 8) % 10 < 7;
    let faction_id = if use_hint && req.prefer_faction.is_some() {
        req.prefer_faction.clone().unwrap()
    } else {
        let mut counts: std::collections::HashMap<String, u32> =
            std::collections::HashMap::new();
        let mut q = world.query::<&sim_core::agents::ship::ShipIdentity>();
        for id in q.iter(&world) {
            if !id.faction_id.is_empty() {
                *counts.entry(id.faction_id.clone()).or_insert(0) += 1;
            }
        }
        counts
            .into_iter()
            .min_by_key(|(_, n)| *n)
            .map(|(f, _)| f)
            .unwrap_or_else(|| {
                req.prefer_faction
                    .clone()
                    .unwrap_or_else(|| "terran-authority".to_string())
            })
    };

    // Location: prefer a dockable faction-owned station; fall back to
    // any dockable station if the faction has none left.
    let station_candidates: Vec<(String, String)> = {
        let mut q =
            world.query::<(&FacilityIdentity, &FacilityLocation, &FacilityOperations)>();
        q.iter(&world)
            .filter(|(id, _, ops)| {
                id.facility_type != "gate" && ops.docking_capacity > 0
            })
            .map(|(id, loc, _)| (loc.location_name.clone(), id.faction_id.clone()))
            .collect()
    };
    if station_candidates.is_empty() {
        anyhow::bail!("no dockable stations available for respawn");
    }
    let home_matches: Vec<(String, String)> = station_candidates
        .iter()
        .filter(|&(_, fid)| *fid == faction_id)
        .cloned()
        .collect();
    let (location_name, _) = if !home_matches.is_empty() {
        home_matches[(seed as usize) % home_matches.len()].clone()
    } else {
        station_candidates[(seed as usize) % station_candidates.len()].clone()
    };

    // JOIN-fetch location row to compute universe_offset + starting
    // position. Mirrors the admin HTTP path exactly.
    let loc_row = sqlx::query(
        "SELECT l.id AS loc_id, l.name AS loc_name,
                b.body_id, b.current_angle, b.orbit_radius,
                s.name AS sys_name,
                s.universe_offset_x, s.universe_offset_y
         FROM locations l
         JOIN celestial_bodies b ON b.id = l.celestial_body_id
         JOIN star_systems s ON s.id = b.star_system_id
         WHERE l.name = ?1
         LIMIT 1",
    )
    .bind(&location_name)
    .fetch_optional(pool)
    .await?;
    let Some(loc_row) = loc_row else {
        anyhow::bail!("location not found in DB: {location_name}");
    };
    let location_id: i64 = loc_row.get("loc_id");
    let system_id: String = loc_row.get::<String, _>("sys_name");
    let offset_x = loc_row.get::<f64, _>("universe_offset_x") as f32;
    let offset_y = loc_row.get::<f64, _>("universe_offset_y") as f32;
    let angle = loc_row.get::<f64, _>("current_angle") as f32;
    let radius = loc_row.get::<f64, _>("orbit_radius") as f32;
    let rad = angle.to_radians();
    let body_x = radius * rad.cos() + offset_x;
    let body_y = radius * rad.sin() + offset_y;

    let name = random_ship_name(seed);
    let credits: i64 = 5_000;
    let class_cfg = sim_core::simulation::config::ship_class(class)
        .ok_or_else(|| anyhow::anyhow!("unknown class: {class}"))?;

    let insert = sqlx::query(
        "INSERT INTO ships
           (name, class, location_id, location_name, system_id,
            universe_offset_x, universe_offset_y, position_x, position_y,
            cargo_capacity, fuel, fuel_capacity, fuel_consumption_rate,
            speed_modifier, credits, faction_id, faction_reputation, size)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18)",
    )
    .bind(&name)
    .bind(class)
    .bind(location_id)
    .bind(&location_name)
    .bind(&system_id)
    .bind(offset_x as f64)
    .bind(offset_y as f64)
    .bind(body_x as f64)
    .bind(body_y as f64)
    .bind(class_cfg.cargo_capacity as i64)
    .bind(class_cfg.fuel_capacity as f64)
    .bind(class_cfg.fuel_capacity as f64)
    .bind(class_cfg.fuel_consumption_base as f64)
    .bind(class_cfg.speed_modifier as f64)
    .bind(credits)
    .bind(&faction_id)
    .bind("{}")
    .bind(class_cfg.default_size.as_str())
    .execute(pool)
    .await?;
    let db_id = insert.last_insert_rowid();
    let agent_id = format!("ship-respawn-{db_id}");

    let payload = crate::control::AdminSpawnShipPayload {
        db_id,
        agent_id: agent_id.clone(),
        name: name.clone(),
        class: class.to_string(),
        location_name: location_name.clone(),
        faction_id: faction_id.clone(),
        universe_offset: (offset_x, offset_y),
        position: (body_x, body_y),
        credits,
    };
    admin_spawn_ship(world, store, registry, payload, events);
    events.push(serde_json::json!({
        "kind": "ship_spawned",
        "id": agent_id,
        "class": class,
        "faction_id": faction_id,
        "location": location_name,
        "reason": "adaptive_respawn",
    }));
    Ok(())
}

/// Tiny name picker — two-syllable word list hash-indexed by seed.
/// Not meant to be clever; it just produces varied human-readable
/// names without pulling in a full name-generator crate.
pub fn random_ship_name(seed: u64) -> String {
    const FIRST: &[&str] = &[
        "Dawn", "Ember", "Frost", "Ghost", "Iron", "Jade", "Kestrel",
        "Lark", "Mercury", "Nova", "Onyx", "Pike", "Quartz", "Raven",
        "Silver", "Tide", "Umbra", "Vanguard", "Wisp", "Xenon",
    ];
    const SECOND: &[&str] = &[
        "Runner", "Hawk", "Drift", "Talon", "Whisper", "Gale", "Echo",
        "Serpent", "Falcon", "Lance", "Marlin", "Spire", "Crane",
        "Thorn", "Vortex", "Harrow", "Halo", "Reaver", "Spark",
        "Beacon",
    ];
    let a = FIRST[((seed >> 16) as usize) % FIRST.len()];
    let b = SECOND[((seed >> 32) as usize) % SECOND.len()];
    format!("{a} {b}")
}

/// Spawn the runtime facility with a stable negative DB ID; queue creation
/// for the same economic checkpoint as the final construction delivery.
#[allow(clippy::too_many_arguments)]
pub(super) fn materialize_facility(
    world: &mut World,
    store: &mut AgentStore,
    source_site_id: &str,
    display_name: &str,
    facility_type: &str,
    body_id: &str,
    faction_id: &str,
    location_name: &str,
    position: (f32, f32),
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::facility::{
        FacilityCrew, FacilityFitting, FacilityIdentity, FacilityLifecycle, FacilityLocation,
        FacilityOperations, FacilityStorage,
    };
    use std::collections::HashMap;

    // Slug-ify the display name (strip the "under construction" tail).
    let clean_name = display_name
        .replace("(under construction)", "")
        .trim()
        .to_string();
    let name_slug: String = clean_name
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    let agent_id = format!("facility-{}-{}", location_name, name_slug);

    // Pull location_id from an existing facility at the same location
    // so the new entity slots into the same row.
    let location_id = {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        q.iter(&world)
            .find(|(_, loc)| loc.location_name == location_name)
            .map(|(_, loc)| loc.location_id)
            .unwrap_or(0)
    };

    let db_id = next_construction_id(world);
    // Working capital is a transfer, never an implicit creation grant.
    let credits = store.faction_by_id.get(faction_id).copied()
        .and_then(|e| world.get_mut::<sim_core::agents::faction::FactionData>(e))
        .map(|mut faction| {
            let amount = faction.treasury.clamp(0, 20_000);
            faction.treasury -= amount;
            faction.dirty = true;
            amount
        }).unwrap_or(0);

    let entity = world.spawn((
        FacilityIdentity {
            db_id,
            id: agent_id.clone(),
            name: clean_name.clone(),
            facility_type: facility_type.to_string(),
            faction_id: faction_id.to_string(),
            body_id: body_id.to_string(),
        },
        FacilityLocation {
            location_id,
            location_name: location_name.to_string(),
        },
        FacilityOperations {
            docking_capacity: 4,
            services: vec!["market".to_string()],
            condition: 1.0,
            reputation: 50,
            credits,
            dirty: true,
            starving_notified: false,
        },
        FacilityStorage {
            reserves: HashMap::new(),
            docked_ships: vec![],
            pending_deliveries: vec![],
            dock_queue: vec![],
        },
        FacilityLifecycle::new(),
        sim_core::simulation::lod::AgentLod::new(),
        FacilityFitting::new_default(),
        FacilityCrew::new_for_type(facility_type),
    )).id();

    // Record position on the positions snapshot so Godot renders the
    // facility at the same spot the site occupied. The per-tick
    // positions publisher picks this up automatically.
    store.facility_by_id.insert(agent_id.clone(), entity);
    store
        .facilities_at_location
        .entry(location_name.to_string())
        .or_default()
        .push(entity);

    // Queue creation metadata; the emitter sends it with current runtime
    // state and the issuer debit after reserving a complete frame slot.
    store
        .pending_materializations
        .push(sim_core::simulation::spawner::PendingMaterialization {
            entity,
            agent_id: agent_id.clone(),
            source_site_id: source_site_id.to_string(),
            name: clean_name.clone(),
            facility_type: facility_type.to_string(),
            faction_id: faction_id.to_string(),
            body_id: body_id.to_string(),
            location_id,
            location_name: location_name.to_string(),
            docking_capacity: 4,
            credits,
            reputation: 50,
            condition: 1.0,
        });

    events.push(serde_json::json!({
        "kind": "construction_completed",
        "site_id": source_site_id,
        "facility_id": agent_id,
        "facility_type": facility_type,
        "location": location_name,
        "position": { "x": position.0, "y": position.1 },
    }));
}
