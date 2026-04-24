//! Embedded simulator state + tick schedule for the Bevy client.
//!
//! Bundle 2a wires `sim_core`'s `AgentStore` into a Bevy `Resource`
//! so Bevy systems can read/mutate the sim directly, and schedules
//! tick work on Bevy's `FixedUpdate` at the same cadence `sim_server`
//! used (125 ms → 8 tps at world_speed 1.0).
//!
//! 2a is intentionally empty on the world-data side — no DB load, no
//! seeder, no real tick phases yet. The tick counter still
//! increments so we can prove the plugin wiring + schedule work on
//! an otherwise quiet sim. Bundle 2b brings in world loading + the
//! full tick-phase call chain that `sim_server::engine` runs today.

use bevy::prelude::*;
use sim_core::simulation::spawner::AgentStore;

/// Base tick interval (seconds). Matches sim_server's default 125 ms
/// cadence. World-speed UI in a future bundle rescales this.
pub const DEFAULT_TICK_INTERVAL_S: f64 = 0.125;

/// Bevy plugin: registers the `Sim` resource + schedules the tick
/// system on `FixedUpdate`.
pub struct SimPlugin;

impl Plugin for SimPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Sim>()
            .add_systems(FixedUpdate, tick_sim);
    }
}

/// The sim, as a Bevy Resource. Wraps `sim_core::AgentStore` (which
/// in turn owns the hecs `World`, the contract board, the various
/// pending queues, etc.) plus the couple of counters `sim_server`
/// currently keeps separately.
///
/// Every field `sim_server::AppState` maintains that's actually
/// relevant to the sim lives here. Items that are sim_server-only
/// (DB pool, HTTP broadcast tx, persistence channels, etc.) stay
/// out — we don't need them embedded.
#[derive(Resource)]
pub struct Sim {
    pub store: AgentStore,
    pub tick: u64,
    pub running: bool,
    /// Tick multiplier vs the 1x rate. 1 = normal, 2 = half speed,
    /// etc. Matches `sim_server`'s `tick_mult`. Unused until 2b
    /// wires in the real tick phases that consume it.
    #[allow(dead_code)]
    pub tick_mult: u32,
}

impl Default for Sim {
    fn default() -> Self {
        Self {
            store: AgentStore::new(),
            tick: 0,
            running: true,
            tick_mult: 1,
        }
    }
}

/// Tick system — runs on Bevy's `FixedUpdate` schedule at
/// `DEFAULT_TICK_INTERVAL_S`. Bundle 2a just bumps the counter;
/// 2b will call the existing `sim_core` tick phases in the same
/// order `sim_server::engine::run_tick_loop` uses.
fn tick_sim(mut sim: ResMut<Sim>) {
    if !sim.running {
        return;
    }
    sim.tick += 1;
    // Future phase chain goes here. See
    // `sim_server/src/engine.rs::run_tick_loop` for the reference
    // order: drain-control → bodies → ships → apply → facilities →
    // populations → markets → factions → relations. Each becomes a
    // call from this system (or its own Bevy system, depending on
    // how we split it in 2b).
}
