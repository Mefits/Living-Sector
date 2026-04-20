use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        market::{self, MarketIdentity, MarketPricing},
    },
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
/// Phase order (subset so far — expands in Phase 4+):
///   1. drain command buffer (pause/resume/etc from WS handlers)
///   2. bodies: advance orbital angles
///   3. [ships — Phase 4]
///   4. apply cross-agent effects from command buffer
///   5. markets: 8-phase tick (produce→consume→orders→match→demand→shortage→prices)
///   6. [facilities — Phase 6]
///   7. [populations — Phase 6]
///   8. [snapshot write — Phase 5]
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
    let tick_scale = tick_config.tick_scale();
    let tick_mult = tick_config.tick_multiplier();

    info!(
        "Engine: tick loop started at {}ms/tick ({} tps, world_speed={}, mult={})",
        tick_config.tick_interval_ms(),
        tick_config.ticks_per_second,
        tick_config.world_speed,
        tick_mult,
    );
    log_sample_market(&store, "initial");

    loop {
        timer.tick().await;

        if !running.load(Ordering::Relaxed) {
            tokio::time::sleep(Duration::from_millis(100)).await;
            continue;
        }

        let tick = tick_counter.fetch_add(1, Ordering::Relaxed) + 1;

        // Phase 0: drain commands queued from WS handlers (pause/resume/observer).
        // TODO Phase 5: actually process these commands.
        commands.clear();

        // Phase 1: orbital bodies
        tick_bodies(&mut store, tick_scale);

        // Phase 2: ships — coming in Phase 4

        // Phase 3: apply cross-agent effects from ship phase — Phase 4

        // Phase 4: markets (uses command buffer for spread-revenue transfers)
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);

        // Phase 5+: facilities, populations — Phase 6

        // Diagnostics
        if tick % (8 * 5) == 0 {
            debug!(tick, commands = commands.len(), "Engine: tick");
        }
        if tick % (8 * 10) == 0 {
            info!(tick, "Engine: {} | commands/tick={}", store.summary(), commands.len());
            log_sample_market(&store, &format!("tick={tick}"));
        }
    }
}

fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_e, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}

/// Logs one market's price for a few key commodities at a specific moment —
/// useful in smoke tests to confirm prices move over time.
fn log_sample_market(store: &AgentStore, label: &str) {
    use sim_core::economy::commodities::Commodity::*;
    // Pick Earth Station market if present, else the first market
    let target = store
        .market_at_location
        .get("earth-station")
        .copied()
        .or_else(|| store.market_by_id.values().next().copied());
    if let Some(entity) = target {
        if let Ok(mut q) = store.world.query_one::<(&MarketIdentity, &MarketPricing)>(entity) {
            if let Some((id, pricing)) = q.get() {
                let fuel = pricing.prices.get(&Fuel).copied().unwrap_or(0.0);
                let food = pricing.prices.get(&Food).copied().unwrap_or(0.0);
                let ore = pricing.prices.get(&Ore).copied().unwrap_or(0.0);
                let fuel_supply = pricing.supply.get(&Fuel).copied().unwrap_or(0.0);
                info!(
                    "market[{}] {}: fuel={:.2} food={:.2} ore={:.2} fuel_supply={:.0}",
                    id.id, label, fuel, food, ore, fuel_supply,
                );
            }
        }
    }
}
