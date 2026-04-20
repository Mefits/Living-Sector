use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        market::{self, MarketIdentity, MarketPricing},
        ship::{self, ShipPosition},
    },
    simulation::{
        commands::{CommandBuffer, SimCommand},
        config::TickConfig,
        spawner::AgentStore,
    },
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

/// Simulation tick loop.
///
/// Phase order per tick:
///   1. drain commands from WS handlers (pause/observer/speed)
///   2. advance orbital bodies
///   3. ships: transit, observe, decide, act → emit commands
///   4. apply ship-emitted commands (AddSupplyAtShipLocation etc.)
///   5. markets: 8-phase tick → emit commands (TransferCredits)
///   6. apply market-emitted commands
///   7. [facilities / populations → Phase 6]
pub async fn run_tick_loop(
    mut store: AgentStore,
    registry: Arc<WorldRegistry>,
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

        // Phase 0: drain any WS-originating commands (reserved)
        commands.clear();

        // Phase 1: bodies
        tick_bodies(&mut store, tick_scale);

        // Phase 2: ships (may emit supply commands)
        ship::tick_ships(&mut store.world, &registry, &mut commands, tick, tick_scale, tick_mult);

        // Phase 3: apply supply commands to markets
        apply_supply_commands(&mut store, &mut commands);

        // Phase 4: markets (may emit credit-transfer commands)
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);

        // Phase 5: apply remaining commands (credit transfers etc.)
        // For Phase 4 MVP we don't apply transfer commands yet — facilities
        // aren't tracked as credit-holders until Phase 6.
        commands.clear();

        // Diagnostics
        if tick % (8 * 5) == 0 {
            debug!(tick, "Engine: tick");
        }
        if tick % (8 * 10) == 0 {
            info!(tick, "Engine: {}", store.summary());
            log_sample_market(&store, &format!("tick={tick}"));
            log_sample_ships(&store, tick);
        }
    }
}

fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_e, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}

/// Apply commands that need a lookup from ship-location → market-entity.
/// These are emitted by `ship::tick_ships` during buy/sell actions.
fn apply_supply_commands(store: &mut AgentStore, commands: &mut CommandBuffer) {
    // Take the commands out so we can iterate without holding a borrow on `commands`.
    let drained: Vec<SimCommand> = commands.drain().collect();
    let mut leftover: Vec<SimCommand> = Vec::with_capacity(drained.len());

    for cmd in drained {
        match cmd {
            SimCommand::AddSupplyAtShipLocation { ship, commodity, quantity }
            | SimCommand::RemoveSupplyAtShipLocation { ship, commodity, quantity } => {
                let sign = matches!(&cmd, SimCommand::AddSupplyAtShipLocation { .. });
                let location = store
                    .world
                    .get::<&ShipPosition>(ship)
                    .ok()
                    .and_then(|p| p.location_name.clone());
                if let Some(loc) = location {
                    if let Some(&market_entity) = store.market_at_location.get(&loc) {
                        if let Ok(mut pricing) = store.world.get::<&mut MarketPricing>(market_entity) {
                            let entry = pricing.supply.entry(commodity).or_insert(0.0);
                            if sign {
                                *entry += quantity;
                            } else {
                                *entry = (*entry - quantity).max(0.0);
                            }
                        }
                    }
                }
            }
            SimCommand::AddSupply { market, commodity, quantity } => {
                if let Ok(mut pricing) = store.world.get::<&mut MarketPricing>(market) {
                    *pricing.supply.entry(commodity).or_insert(0.0) += quantity;
                }
            }
            SimCommand::RemoveSupply { market, commodity, quantity } => {
                if let Ok(mut pricing) = store.world.get::<&mut MarketPricing>(market) {
                    let entry = pricing.supply.entry(commodity).or_insert(0.0);
                    *entry = (*entry - quantity).max(0.0);
                }
            }
            other => leftover.push(other),
        }
    }

    commands.commands.extend(leftover);
}

/// Log one market's price for a few key commodities.
fn log_sample_market(store: &AgentStore, label: &str) {
    use sim_core::economy::commodities::Commodity::*;
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

/// Log summary of ship states (counts by goal, credits distribution, visited locations).
fn log_sample_ships(store: &AgentStore, tick: u64) {
    use sim_core::agents::ship::{ShipAI, ShipCargo, ShipEconomy, ShipMemory};
    let mut by_goal: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
    let mut total_credits: i64 = 0;
    let mut ships_with_cargo: u32 = 0;
    let mut ship_count: u32 = 0;
    let mut max_credits: i64 = 0;
    let mut min_credits: i64 = i64::MAX;
    let mut total_visited: u32 = 0;
    for (_e, (ai, econ, cargo, mem)) in store
        .world
        .query::<(&ShipAI, &ShipEconomy, &ShipCargo, &ShipMemory)>()
        .iter()
    {
        *by_goal.entry(ai.current_goal.clone()).or_insert(0) += 1;
        total_credits += econ.credits;
        max_credits = max_credits.max(econ.credits);
        min_credits = min_credits.min(econ.credits);
        if cargo.used() > 0 {
            ships_with_cargo += 1;
        }
        total_visited += mem.visited.len() as u32;
        ship_count += 1;
    }
    if ship_count > 0 {
        let avg = total_credits / ship_count as i64;
        let avg_visited = total_visited as f32 / ship_count as f32;
        info!(
            tick,
            "ships: {:?} | credits avg/min/max={}/{}/{} | with_cargo={} | avg_visited_locs={:.1}",
            by_goal,
            avg,
            min_credits,
            max_credits,
            ships_with_cargo,
            avg_visited,
        );
    }
}
