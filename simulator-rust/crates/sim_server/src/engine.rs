//! Simulation engine — the tick loop driver.
//!
//! Runs as a tokio task alongside the axum server. Holds exclusive ownership
//! of the [`AgentStore`] during each tick, so no locks are needed on agent
//! state. Publishes snapshots and broadcasts at phase boundaries.
//!
//! ## Phase order per tick
//! 1. **drain control channel** — pause/resume/speed/observer from HTTP/WS
//! 2. **bodies** — advance orbital angles
//! 3. **ships** — observe prices, pick goals, move/trade (emits `SimCommand`s)
//! 4. **apply_supply_commands** — resolve ship-location → market and adjust supply
//! 5. **facilities** — execute production recipes, mine from bodies
//! 6. **populations** — consume food/fuel, produce labor commodity, update sentiment
//! 7. **markets** — 8-phase tick (see `agents::market`)
//! 8. **snapshot write** — update `SnapshotCache` for readers
//! 9. **broadcast** — positions (every tick), ship_states (every 8), market_states (every 16)
//!
//! ## Performance
//! At 800 agents a full tick completes in ~3 ms on an M1 Mac, leaving the
//! bulk of the 125 ms tick budget idle. Rayon parallelism over agent slices
//! is not yet applied — headroom for 10k+ agents without it.

use crate::{
    control::ControlCommand,
    snapshot::SnapshotCache,
    ws::protocol::{PositionEntry, ServerMsg},
};
use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        facility,
        market::{self, MarketIdentity, MarketPricing},
        population,
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
use tokio::sync::{broadcast, mpsc};
use tokio::time::{interval, Duration, MissedTickBehavior};
use tracing::{debug, info};

pub type TickCounter = Arc<AtomicU64>;
pub type RunningFlag = Arc<AtomicBool>;

#[allow(clippy::too_many_arguments)]
pub async fn run_tick_loop(
    mut store: AgentStore,
    registry: Arc<WorldRegistry>,
    mut tick_config: TickConfig,
    tick_counter: TickCounter,
    running: RunningFlag,
    snapshots: Arc<SnapshotCache>,
    interval_ms: Arc<AtomicU64>,
    broadcast_tx: broadcast::Sender<Arc<ServerMsg>>,
    mut control_rx: mpsc::Receiver<ControlCommand>,
) {
    let mut timer_interval = tick_config.tick_interval_ms();
    interval_ms.store(timer_interval, Ordering::Relaxed);
    let mut timer = interval(Duration::from_millis(timer_interval));
    timer.set_missed_tick_behavior(MissedTickBehavior::Delay);

    let mut commands = CommandBuffer::new();
    let mut tick_scale = tick_config.tick_scale();
    let mut tick_mult = tick_config.tick_multiplier();

    info!(
        "Engine: tick loop started at {}ms/tick ({} tps, world_speed={}, mult={})",
        timer_interval, tick_config.ticks_per_second, tick_config.world_speed, tick_mult,
    );
    log_sample_market(&store, "initial");

    loop {
        timer.tick().await;

        // Drain control commands (non-blocking)
        while let Ok(cmd) = control_rx.try_recv() {
            match cmd {
                ControlCommand::Pause => {
                    running.store(false, Ordering::Relaxed);
                    info!("Engine: paused via control channel");
                }
                ControlCommand::Resume => {
                    running.store(true, Ordering::Relaxed);
                    info!("Engine: resumed via control channel");
                }
                ControlCommand::SetSpeed { interval_ms: ms } => {
                    if (10..=5_000).contains(&ms) {
                        timer_interval = ms;
                        interval_ms.store(ms, Ordering::Relaxed);
                        tick_config.ticks_per_second = (1000 / ms.max(1)) as u32;
                        tick_scale = tick_config.tick_scale();
                        tick_mult = tick_config.tick_multiplier();
                        timer = interval(Duration::from_millis(timer_interval));
                        timer.set_missed_tick_behavior(MissedTickBehavior::Delay);
                        info!("Engine: speed changed to {}ms/tick", ms);
                    }
                }
                ControlCommand::MoveObserver { .. } => {
                    // Spatial LOD deferred — acknowledge but no-op for now.
                }
            }
        }

        if !running.load(Ordering::Relaxed) {
            tokio::time::sleep(Duration::from_millis(50)).await;
            continue;
        }

        let tick = tick_counter.fetch_add(1, Ordering::Relaxed) + 1;
        let t_start = std::time::Instant::now();

        // Tick phases
        tick_bodies(&mut store, tick_scale);
        ship::tick_ships(
            &mut store.world,
            &registry,
            &store.contracts,
            &mut commands,
            tick,
            tick_scale,
            tick_mult,
        );
        apply_ship_commands(&mut store, &mut commands);
        facility::tick_facilities(&mut store.world, tick, tick_mult);
        population::tick_populations(&mut store.world, &mut store.contracts, tick, tick_mult);
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);
        commands.clear();

        let tick_compute_us = t_start.elapsed().as_micros() as u64;

        // Snapshot write
        snapshots.update_from(&store);
        let total_us = t_start.elapsed().as_micros() as u64;

        // Broadcasts (cadences match the protocol spec)
        publish_positions(tick, timer_interval, &snapshots, &broadcast_tx);
        if tick % 8 == 0 {
            publish_ship_states(tick, &snapshots, &broadcast_tx);
        }
        if tick % 16 == 0 {
            publish_market_states(tick, &snapshots, &broadcast_tx);
        }

        // Diagnostics
        if tick % (8 * 10) == 0 {
            info!(
                tick,
                "Engine: {} | tick_compute_us={} total_us={}",
                store.summary(),
                tick_compute_us,
                total_us,
            );
            log_sample_market(&store, &format!("tick={tick}"));
            log_sample_ships(&store, tick);
            log_contract_board(&store, tick);
        } else if tick % (8 * 5) == 0 {
            debug!(tick, tick_compute_us, total_us, "Engine: tick");
        }
    }
}

fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_e, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}

fn apply_ship_commands(store: &mut AgentStore, commands: &mut CommandBuffer) {
    use sim_core::agents::ship::{ShipCargo, ShipEconomy};

    let drained: Vec<SimCommand> = commands.drain().collect();
    let mut leftover: Vec<SimCommand> = Vec::with_capacity(drained.len());

    for cmd in drained {
        match cmd {
            SimCommand::AddSupplyAtShipLocation { ship, commodity, quantity }
            | SimCommand::RemoveSupplyAtShipLocation { ship, commodity, quantity } => {
                let adding = matches!(&cmd, SimCommand::AddSupplyAtShipLocation { .. });
                let location = store
                    .world
                    .get::<&ShipPosition>(ship)
                    .ok()
                    .and_then(|p| p.location_name.clone());
                if let Some(loc) = location {
                    if let Some(&market_entity) = store.market_at_location.get(&loc) {
                        if let Ok(mut pricing) = store.world.get::<&mut MarketPricing>(market_entity) {
                            let entry = pricing.supply.entry(commodity).or_insert(0.0);
                            if adding {
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

            // --- Contracts ---
            SimCommand::AcceptContract { contract_id, ship_id, .. } => {
                // Best-effort: silently drop if the contract was already taken.
                let tick_now = 0; // Apply phase doesn't know the tick; board records accepted_at separately.
                store.contracts.accept(&contract_id, ship_id, tick_now);
            }
            SimCommand::DeliverContract { ship, contract_id } => {
                let delivered = store.contracts.mark_delivered(&contract_id);
                if let Some(c) = delivered {
                    // Pay the ship
                    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
                        econ.credits += c.payment;
                    }
                    // Reduce ship cargo
                    if let Ok(mut cargo) = store.world.get::<&mut ShipCargo>(ship) {
                        let have = cargo.cargo.get(&c.commodity).copied().unwrap_or(0);
                        let leftover = have.saturating_sub(c.quantity);
                        if leftover == 0 {
                            cargo.cargo.remove(&c.commodity);
                            cargo.cargo_age.remove(&c.commodity);
                        } else {
                            cargo.cargo.insert(c.commodity, leftover);
                        }
                    }
                    // Add supply at destination market
                    if let Some(&market_entity) =
                        store.market_at_location.get(&c.destination_location)
                    {
                        if let Ok(mut pricing) =
                            store.world.get::<&mut MarketPricing>(market_entity)
                        {
                            *pricing.supply.entry(c.commodity).or_insert(0.0) +=
                                c.quantity as f32;
                        }
                    }
                }
            }

            other => leftover.push(other),
        }
    }

    commands.commands.extend(leftover);
}

fn publish_positions(
    tick: u64,
    interval_ms: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let entities: Vec<PositionEntry> = snapshots
        .positions
        .iter()
        .map(|e| {
            let id = e.key().clone();
            let (x, y) = *e.value();
            let kind = if id.starts_with("ship-") {
                "ship"
            } else {
                "body"
            };
            PositionEntry { id, x, y, kind }
        })
        .collect();
    let msg = ServerMsg::Positions { tick, interval_ms, entities };
    let _ = tx.send(Arc::new(msg));
}

fn publish_ship_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let ships: Vec<serde_json::Value> = snapshots
        .ships
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::ShipStates { tick, ships };
    let _ = tx.send(Arc::new(msg));
}

fn publish_market_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let markets: Vec<serde_json::Value> = snapshots
        .markets
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::MarketStates { tick, markets };
    let _ = tx.send(Arc::new(msg));
}

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

fn log_contract_board(store: &AgentStore, tick: u64) {
    let counts = store.contracts.counts_by_status();
    if !counts.is_empty() {
        info!(tick, "contracts: {:?} total={}", counts, store.contracts.len());
    }
}

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
            by_goal, avg, min_credits, max_credits, ships_with_cargo, avg_visited,
        );
    }
}
