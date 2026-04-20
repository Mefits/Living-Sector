use sim_core::{
    agents::celestial_body::BodyOrbit,
    simulation::{commands::CommandBuffer, config::TickConfig, spawner::AgentStore},
    world::registry::WorldRegistry,
};
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc,
};
use tokio::time::{interval, Duration, MissedTickBehavior};
use tracing::{debug, info};

pub type TickCounter = Arc<AtomicU64>;
pub type RunningFlag = Arc<AtomicBool>;

/// The engine tick loop.
///
/// Phases (Phase 2 skeleton — body orbits only):
///   1. Drain command buffer (no-op at boot)
///   2. Advance celestial body orbits
///   3. (future) ships → apply effects → markets → facilities → populations
///   4. Write snapshots
pub async fn run_tick_loop(
    mut store: AgentStore,
    _registry: Arc<WorldRegistry>,
    tick_config: TickConfig,
    tick_counter: TickCounter,
    running: RunningFlag,
) {
    let mut timer = interval(Duration::from_millis(tick_config.tick_interval_ms()));
    timer.set_missed_tick_behavior(MissedTickBehavior::Delay);

    let mut commands = CommandBuffer::new();

    info!(
        "Engine: tick loop started at {}ms/tick ({} tps, world_speed={})",
        tick_config.tick_interval_ms(),
        tick_config.ticks_per_second,
        tick_config.world_speed,
    );

    loop {
        timer.tick().await;

        if !running.load(Ordering::Relaxed) {
            tokio::time::sleep(Duration::from_millis(100)).await;
            continue;
        }

        let tick = tick_counter.fetch_add(1, Ordering::Relaxed) + 1;

        // Phase 0: drain any commands queued from WS handlers (pause/resume/etc).
        // Phase 2: none yet. Just clear.
        commands.clear();

        // Phase 1: advance orbital bodies. Pure, fast, data-parallel-safe.
        tick_bodies(&mut store, tick_config.tick_scale());

        // Diagnostic logging
        if tick.is_multiple_of(8) {
            debug!(tick, "Engine: tick");
        }
        if tick.is_multiple_of(8 * 30) {
            info!(tick, "Engine: {}", store.summary());
        }
    }
}

fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_entity, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}
