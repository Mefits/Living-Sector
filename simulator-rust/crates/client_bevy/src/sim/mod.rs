//! Embedded simulator state + tick schedule for the Bevy client.
//!
//! Bundle 2a wired in the tick cadence. Bundle 2b.2 loads the real
//! world via `sim_db` on Startup so the heartbeat shows real agent
//! counts. The tick loop still just bumps a counter — Bundle 2b.3
//! extracts the full phase orchestration into a shared `sim_engine`
//! crate and wires it in here.

use bevy::prelude::*;
use sim_core::{
    simulation::{config::TickConfig, spawner::AgentStore, tuning::WorldTuning},
    world::registry::WorldRegistry,
};
use std::path::PathBuf;
use std::sync::Arc;

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
            .add_systems(Startup, load_world)
            .add_systems(FixedUpdate, tick_sim);
    }
}

/// The sim, as a Bevy Resource. Wraps `sim_core::AgentStore` (which
/// in turn owns the hecs `World`, the contract board, the various
/// pending queues, etc.) plus the counters `sim_server` tracks
/// separately on `AppState`.
///
/// Fields reserved for Bundle 2b.3 (tick orchestration) stay behind
/// `#[allow(dead_code)]` until they're consumed.
#[derive(Resource)]
pub struct Sim {
    pub store: AgentStore,
    pub registry: Arc<WorldRegistry>,
    pub tick: u64,
    pub running: bool,
    #[allow(dead_code)]
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
fn load_world(mut sim: ResMut<Sim>) {
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

        Ok::<_, anyhow::Error>((store, registry, world_seed, resumed_tick))
    };

    match rt.block_on(load) {
        Ok((store, registry, world_seed, resumed_tick)) => {
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
        }
        Err(e) => {
            error!("client_bevy: world load failed: {e}");
        }
    }
    // rt drops here — Bundle 2b.3 keeps a long-lived one for
    // persistence worker + future async work.
}

/// Tick system — runs on Bevy's `FixedUpdate` at
/// `DEFAULT_TICK_INTERVAL_S`. Bundle 2a bumped only the counter;
/// Bundle 2b.3 extracts `sim_server::engine::run_tick_loop` into a
/// sharable form and wires it in here.
fn tick_sim(mut sim: ResMut<Sim>) {
    if !sim.running {
        return;
    }
    sim.tick += 1;
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
