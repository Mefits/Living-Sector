//! Embedded simulator state + tick schedule for the Bevy client.
//!
//! Bundle 2a wired in the tick cadence. Bundle 2b.2 loads the real
//! world via `sim_db` on Startup so the heartbeat shows real agent
//! counts. The tick loop still just bumps a counter — Bundle 2b.3
//! extracts the full phase orchestration into a shared `sim_engine`
//! crate and wires it in here.

use bevy::prelude::*;
use sim_core::{
    agents::{celestial_body, facility, faction, market, population, ship},
    simulation::{commands::CommandBuffer, config::TickConfig, spawner::AgentStore, tuning::WorldTuning},
    world::registry::WorldRegistry,
};
use sim_db::persistence::RetirementRow;
use std::path::PathBuf;
use std::sync::Arc;

/// Historical ship retirements loaded at startup from the
/// `retired_ships` table. Frozen snapshot — the embedded client
/// doesn't currently write new retirements (apply_ship_commands is
/// deferred to Bundle 2b.4), so reloading during play is unnecessary
/// until that wiring lands. Newest-first, capped at the loader's
/// limit.
#[derive(Resource, Default)]
pub struct Retirements(pub Vec<RetirementRow>);

/// Rolling ring of per-tick events drained from the tick chain's
/// `events: Vec<serde_json::Value>`. Oldest at the front; bounded
/// at [`EVENTS_CAP`] to keep memory flat for long sessions. Each
/// entry stores the tick it fired at alongside the raw json so the
/// events panel can render in insertion order without reparsing
/// tick numbers.
#[derive(Resource, Default)]
pub struct EventsLog(pub std::collections::VecDeque<(u64, serde_json::Value)>);

/// Ring capacity — roughly 2 minutes of events at 1000 events/tick.
/// Well below a MB of memory; the egui panel paginates anyway.
pub const EVENTS_CAP: usize = 2000;

/// One-shot flag set by the top-bar "Save as…" button; consumed by
/// [`process_save_as`] which opens the sim DB + runs VACUUM INTO a
/// timestamped sibling path. Mirrors the admin save-as endpoint in
/// sim_server but without the persistence-flush pre-step (embedded
/// client has no worker yet — the snapshot reflects on-disk load
/// state, which we acknowledge in the button's tooltip).
#[derive(Resource, Default)]
pub struct SaveAsRequest(pub bool);

/// One-shot flag for the top-bar "Spawn test freighter" admin
/// button. Consumed by [`process_spawn_ship`] which builds an
/// `AdminSpawnShipPayload` targeting earth-station with a random
/// agent id + name, then calls `sim_server::engine::admin_spawn_ship`.
/// Paired with the render-side `reconcile_new_ships` system which
/// surfaces the new hecs entity as a Bevy render entity.
#[derive(Resource, Default)]
pub struct SpawnShipRequest(pub bool);

/// Base tick interval (seconds). Matches sim_server's default 125 ms
/// cadence. World-speed UI in a future bundle rescales this.
pub const DEFAULT_TICK_INTERVAL_S: f64 = 0.125;

/// Bevy plugin: registers the `Sim` resource + schedules the tick
/// system on `FixedUpdate`. Startup system loads the world from the
/// existing sim DB via a one-shot tokio runtime.
pub struct SimPlugin;

impl Plugin for SimPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Sim>()
            .init_resource::<Retirements>()
            .init_resource::<EventsLog>()
            .init_resource::<SaveAsRequest>()
            .init_resource::<SpawnShipRequest>()
            .add_systems(Startup, load_world)
            .add_systems(FixedUpdate, tick_sim)
            .add_systems(Update, (process_save_as, process_spawn_ship));
    }
}

/// The sim, as a Bevy Resource. Wraps `sim_core::AgentStore` (which
/// in turn owns the hecs `World`, the contract board, the various
/// pending queues, etc.) plus the counters `sim_server` tracks
/// separately on `AppState`.
#[derive(Resource)]
pub struct Sim {
    pub store: AgentStore,
    pub registry: Arc<WorldRegistry>,
    pub tick: u64,
    pub running: bool,
    /// World-speed multiplier. `tick_sim` runs this many sim ticks
    /// per fixed update; 1 = normal 125ms cadence, 2 = 2× speed, 4
    /// = 4× speed, etc. Bumped by the top-bar speed combo; persists
    /// only for the current session.
    pub tick_mult: u32,
    #[allow(dead_code)]
    pub world_seed: u64,
}

impl Default for Sim {
    fn default() -> Self {
        Self {
            store: AgentStore::new(),
            registry: Arc::new(WorldRegistry::default()),
            tick: 0,
            running: true,
            tick_mult: 1,
            world_seed: 0,
        }
    }
}

/// Startup system: init DB, seed if empty, load agents into the Sim
/// Resource. Uses a one-shot tokio runtime — we need it for sqlx's
/// async API during this startup sequence only. The runtime gets
/// dropped after the load; Bundle 2b.3 will keep a long-lived one
/// for the persistence worker.
///
/// Behaviour mirrors `sim_server::main` exactly for this slice so
/// the same `sim.db` file can be used interchangeably between the
/// two binaries during the migration.
fn load_world(mut sim: ResMut<Sim>, mut retirements: ResMut<Retirements>) {
    let db_path = resolve_db_path();
    info!("client_bevy: sim DB at {db_path}");

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => {
            error!("client_bevy: failed to build tokio runtime: {e}");
            return;
        }
    };

    let load = async move {
        let pool = sim_db::pool::create_pool(&db_path).await?;
        sim_db::pool::run_migrations(&pool).await?;
        info!("client_bevy: migrations done");

        if !sim_db::seeder::is_seeded(&pool).await? {
            let data_dir = resolve_data_dir();
            info!("client_bevy: seeding from {}", data_dir.display());
            sim_db::seeder::seed_all(&pool, &data_dir).await?;
        } else {
            info!("client_bevy: DB already seeded — skipping");
        }

        // Same WorldTuning path sim_server uses. Missing file → defaults.
        let tuning_path = resolve_data_dir().join("tuning.json");
        let tuning = match std::fs::read_to_string(&tuning_path) {
            Ok(s) => serde_json::from_str::<WorldTuning>(&s).unwrap_or_default(),
            Err(_) => WorldTuning::default(),
        };
        WorldTuning::set(tuning);

        let config = TickConfig::DEFAULT;
        let registry = sim_db::spawner::load_registry(&pool).await?;
        let store = sim_db::spawner::load_agents(&pool, &registry, &config).await?;

        let world_seed = sim_db::persistence::load_or_init_world_seed(&pool).await;
        let resumed_tick = sim_db::persistence::load_tick_counter(&pool).await;
        // Best-effort — an empty / brand-new DB has no retirements
        // yet, so surface the load error as a warning rather than
        // failing startup.
        let retirements = sim_db::persistence::load_retirements(&pool, 200)
            .await
            .unwrap_or_else(|e| {
                warn!("client_bevy: retirements load failed (DB probably fresh): {e}");
                Vec::new()
            });

        Ok::<_, anyhow::Error>((store, registry, world_seed, resumed_tick, retirements))
    };

    match rt.block_on(load) {
        Ok((store, registry, world_seed, resumed_tick, retired)) => {
            let summary = store.summary();
            info!(
                "client_bevy: world loaded: {} ships, {} facilities, {} bodies, {} factions, {} pops; world_seed={}, resume tick={}",
                summary.ships,
                summary.facilities,
                summary.bodies,
                summary.factions,
                summary.populations,
                world_seed,
                resumed_tick,
            );
            sim.store = store;
            sim.registry = Arc::new(registry);
            sim.tick = resumed_tick;
            sim.world_seed = world_seed;
            // Mirror sim_server's post-load step: build the gate-pair
            // lookup so ships can gate-jump. Required for any transit
            // through a gate to pick the right paired endpoint.
            sim.store.rebuild_gate_pairs();
            let retired_count = retired.len();
            retirements.0 = retired;
            info!("client_bevy: loaded {retired_count} historical retirements");
        }
        Err(e) => {
            error!("client_bevy: world load failed: {e}");
        }
    }
    // rt drops here — Bundle 2b.3 keeps a long-lived one for
    // persistence worker + future async work.
}

/// Tick system — runs on Bevy's `FixedUpdate` at
/// `DEFAULT_TICK_INTERVAL_S`. Bundle 2b.3 **minimum-viable** form:
/// calls `sim_core::agents::ship::tick_ships` to advance transits +
/// rotate the ships' internal state machines, but **discards the
/// emitted `CommandBuffer`** because `apply_ship_commands` lives
/// in `sim_server::engine` (private) and porting it cleanly is a
/// follow-up bundle. The consequence:
///
/// - Ships in transit MOVE (advance_transits writes directly to
///   `ShipPosition`).
/// - Ship crew / BT decisions fire but their *outputs* (buy,
///   deliver, dock fee, etc.) never apply. So the economy doesn't
///   progress, and docked ships won't undock on their own.
///
/// That's fine for visual validation — we can see the scaling
/// story (1500+ ships ticking, moving) without the full phase
/// chain. Bundle 2b.4 extracts `apply_ship_commands` + the other
/// phase helpers into a shared `sim_engine` crate and wires the
/// full tick in.
fn tick_sim(mut sim: ResMut<Sim>, mut events_log: ResMut<EventsLog>) {
    if !sim.running {
        return;
    }

    let config = TickConfig::DEFAULT;
    let tick_scale = config.tick_scale();
    let tick_mult = sim.tick_mult.max(1);

    // Run `tick_mult` sim ticks per fixed update so the world-speed
    // control feels crisp. Bundle 2b.4 wires in the full command-
    // apply phase via sim_server::engine — ships now actually dock,
    // gate-jump, deliver contracts, etc. Other phases (facilities,
    // markets, populations, factions) still aren't driven here; the
    // economy progresses partially until those land.
    for _ in 0..tick_mult {
        sim.tick += 1;
        let tick = sim.tick;
        let Sim { store, registry, .. } = &mut *sim;

        let mut commands = CommandBuffer::new();
        // `events` collects per-tick event values that every phase
        // may push into. The embedded client doesn't yet broadcast
        // or display these (no WS layer + no events-ticker panel),
        // so we drop the Vec at end-of-tick. Wire up to a future
        // events panel by stashing the drained list on a Resource.
        let mut events: Vec<serde_json::Value> = Vec::new();

        // Phase order mirrors sim_server::engine::run_tick_loop —
        // see its comments for the "why" of the ordering. The only
        // steps we skip vs. that loop are the three async drains
        // (materializations / decommissions / respawns) + the
        // persistence / snapshot writes. Those paths need tokio +
        // sqlx + the broadcast tx; not worth dragging into the
        // fixed-update system right now.
        //
        // Bodies first so anything reading orbit positions later
        // this tick sees today's orbit.
        sim_server::engine::tick_bodies(store, tick_scale);

        // Ships — AI decides + transits advance + commands get
        // emitted into the CommandBuffer.
        ship::tick_ships(
            &mut store.world,
            registry,
            &store.gate_pairs,
            &store.contracts,
            &store.relations,
            &mut commands,
            tick,
            tick_scale,
            tick_mult,
        );
        // First apply pass — docks, gate jumps, contract deliveries,
        // cargo buys/sells, credit transfers.
        sim_server::engine::apply_ship_commands(
            store,
            &mut commands,
            &mut events,
            tick,
        );
        sim_server::engine::tick_dock_queue_advance(store);

        // Facilities: recipes, condition degrade, crew food draw,
        // restock from local market, autonomous contract posting,
        // abandonment countdown, level-up on XP.
        facility::tick_facilities(
            &mut store.world,
            &mut store.contracts,
            &mut events,
            tick,
            tick_scale,
            tick_mult,
        );
        // Populations: food consumption, production, sentiment,
        // passenger-contract posting, migration pressure.
        population::tick_populations(
            &mut store.world,
            &mut store.contracts,
            &mut events,
            tick,
            tick_scale,
            tick_mult,
        );
        // Markets: the 8-phase pricing engine. Emits TransferCredits
        // (spread revenue → facility) into `commands`, so we do a
        // second apply pass below.
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);

        // Second apply pass — market TransferCredits + anything the
        // facility/pop phases emitted.
        sim_server::engine::apply_ship_commands(
            store,
            &mut commands,
            &mut events,
            tick,
        );

        // Body regen (separate from body-orbit `tick_bodies` above —
        // this regrows mined resources on a slower cadence).
        celestial_body::tick_bodies_regen(
            &mut store.world,
            tick,
            tick_scale,
            tick_mult,
        );

        // Structural-warning events: market_crisis + facility_starving
        // threshold crossings. Hysteresis-flagged; idempotent per
        // flag flip.
        sim_server::engine::scan_crisis_events(&mut store.world, &mut events);

        // Factions: tax + subsidy + construction cycle.
        faction::tick_factions(
            &mut store.world,
            &mut store.contracts,
            &mut events,
            tick,
            tick_mult,
        );
        // Relations: decay + treaty transitions (low frequency).
        sim_server::engine::tick_relations_pass(store, &mut events, tick, tick_mult);

        // Drop leftover commands. In the full run_tick_loop another
        // apply pass picks them up after faction phase; in the
        // embedded tick we're fine dropping — they're mostly
        // supply-delta housekeeping that will re-emit next tick.
        commands.clear();

        // Drain the per-tick events into the ring log so the events
        // ticker panel can render them. Bounded capacity — at tick
        // boundaries we pop-front until we're at the cap.
        for ev in events.drain(..) {
            if events_log.0.len() >= EVENTS_CAP {
                events_log.0.pop_front();
            }
            events_log.0.push_back((tick, ev));
        }
    }
}

/// DB path resolution — honour `DATABASE_PATH` env var, else look
/// next to the running binary (matches `sim_server::resolve_db_path`
/// so both binaries share the same file).
fn resolve_db_path() -> String {
    std::env::var("DATABASE_PATH").unwrap_or_else(|_| {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("sim.db")))
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "sim.db".to_string())
    })
}

/// Resolve `priv/data/` relative to the workspace root, same as
/// `sim_server::resolve_data_dir` does.
fn resolve_data_dir() -> PathBuf {
    // Works when the binary is inside the workspace target directory
    // (standard cargo layout).
    let mut dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."));
    while dir.parent().is_some() && !dir.join("priv").is_dir() {
        dir = match dir.parent() {
            Some(p) => p.to_path_buf(),
            None => break,
        };
    }
    dir.join("priv").join("data")
}

/// Consume a pending [`SaveAsRequest`] by opening a one-shot tokio
/// runtime, pointing a sqlx pool at the live sim.db, and running
/// `VACUUM INTO` with a timestamped destination path. Blocking from
/// a Bevy Update system is ugly in principle but fine here — save
/// is user-triggered and happens rarely, and the VACUUM is tiny.
fn process_save_as(mut req: ResMut<SaveAsRequest>) {
    if !req.0 {
        return;
    }
    req.0 = false;

    let src_path = resolve_db_path();
    // Snapshot next to the source DB with a wall-clock timestamp
    // (seconds since epoch) so each save produces a unique name.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let dst_path = match std::path::PathBuf::from(&src_path)
        .parent()
        .map(|d| d.join(format!("sim-saveas-{ts}.db")))
    {
        Some(p) => p.to_string_lossy().to_string(),
        None => {
            error!("client_bevy: save-as could not resolve parent dir for {src_path}");
            return;
        }
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => {
            error!("client_bevy: save-as failed to build tokio runtime: {e}");
            return;
        }
    };
    let src_for_task = src_path.clone();
    let dst_for_task = dst_path.clone();
    let result: Result<(), anyhow::Error> = rt.block_on(async move {
        let pool = sim_db::pool::create_pool(&src_for_task).await?;
        sim_db::persistence::save_as(&pool, &dst_for_task).await?;
        Ok(())
    });
    match result {
        Ok(()) => info!("client_bevy: save-as → {dst_path}"),
        Err(e) => error!("client_bevy: save-as failed: {e}"),
    }
}

/// Consume a pending [`SpawnShipRequest`] by building a minimal
/// AdminSpawnShipPayload (freighter at earth-station, 5000 credits,
/// random name + agent id) and calling sim_server's admin_spawn_ship
/// against our in-memory store. The new hecs entity becomes a Bevy
/// render entity on the next frame via `reconcile_new_ships` in
/// render/.
fn process_spawn_ship(mut req: ResMut<SpawnShipRequest>, mut sim: ResMut<Sim>) {
    if !req.0 {
        return;
    }
    req.0 = false;

    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};

    // Build a throwaway id + name from wall-clock so repeated clicks
    // don't collide. Embedded ships aren't persisted yet (no DB
    // worker), so db_id=0 is fine — a restart drops these anyway.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let agent_id = format!("admin-spawn-{ts}");
    let name = format!("admin-{ts}");
    let location = "earth-station".to_string();

    // Position: resolve the body that earth-station orbits. Admin
    // spawn in sim_server uses per-facility offset math; here we
    // settle for body-centre, which is close enough — the ship
    // spawns docked-ish and the sim's planner takes over from there.
    let body_pos = sim
        .store
        .world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .find(|(_e, (b, _))| b.body_id == "earth")
        .map(|(_e, (_, o))| o.universe_position())
        .unwrap_or((0.0, 0.0));

    let payload = sim_server::control::AdminSpawnShipPayload {
        db_id: 0,
        agent_id: agent_id.clone(),
        name,
        class: "freighter".to_string(),
        location_name: location,
        faction_id: "independent".to_string(),
        universe_offset: (0.0, 0.0),
        position: body_pos,
        credits: 5_000,
    };

    let Sim { store, registry, .. } = &mut *sim;
    let mut events: Vec<serde_json::Value> = Vec::new();
    sim_server::engine::admin_spawn_ship(store, registry, payload, &mut events);
    info!(
        "client_bevy admin: spawned test freighter {} at earth-station",
        agent_id
    );
}
