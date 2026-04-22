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
    app_state::Observer,
    control::ControlCommand,
    db::persistence::DbWrite,
    snapshot::SnapshotCache,
    ws::protocol::{PositionEntry, ServerMsg},
};
use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        facility,
        faction,
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
    atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
    Arc,
};
use tokio::sync::{broadcast, mpsc};
use tokio::time::{interval, Duration, MissedTickBehavior};
use tracing::{debug, info};

pub type TickCounter = Arc<AtomicU64>;
pub type RunningFlag = Arc<AtomicBool>;
/// Six rolling counters (one per LOD divisor tier). Extracted to a
/// named alias so the engine signature isn't a wall of Arc<AtomicU64>.
pub type LodCounters = (
    Arc<AtomicU64>,
    Arc<AtomicU64>,
    Arc<AtomicU64>,
    Arc<AtomicU64>,
    Arc<AtomicU64>,
    Arc<AtomicU64>,
);

#[allow(clippy::too_many_arguments)]
pub async fn run_tick_loop(
    mut store: AgentStore,
    registry: Arc<WorldRegistry>,
    mut tick_config: TickConfig,
    tick_counter: TickCounter,
    running: RunningFlag,
    snapshots: Arc<SnapshotCache>,
    interval_ms: Arc<AtomicU64>,
    ticks_per_second: Arc<AtomicU32>,
    world_speed_bits: Arc<AtomicU32>,
    tick_compute_p50_us: Arc<AtomicU64>,
    tick_compute_p99_us: Arc<AtomicU64>,
    observers: Arc<std::sync::RwLock<Vec<Observer>>>,
    lod_counters: LodCounters,
    broadcast_tx: broadcast::Sender<Arc<ServerMsg>>,
    mut control_rx: mpsc::Receiver<ControlCommand>,
    persist_tx: mpsc::Sender<DbWrite>,
) {
    let mut timer_interval = tick_config.tick_interval_ms();
    interval_ms.store(timer_interval, Ordering::Relaxed);
    ticks_per_second.store(tick_config.ticks_per_second, Ordering::Relaxed);
    world_speed_bits.store(tick_config.world_speed.to_bits(), Ordering::Relaxed);
    let mut timer = interval(Duration::from_millis(timer_interval));
    timer.set_missed_tick_behavior(MissedTickBehavior::Delay);

    let mut commands = CommandBuffer::new();
    let mut events: Vec<serde_json::Value> = Vec::new();
    let mut tick_scale = tick_config.tick_scale();
    let mut tick_mult = tick_config.tick_multiplier();
    // Rolling 60-tick window of compute times (µs). Last-N semantics via
    // `VecDeque` pop-front. Updated atomically into AppState every 8 ticks.
    let mut perf_window: std::collections::VecDeque<u64> =
        std::collections::VecDeque::with_capacity(64);
    // Step-debug counter. When > 0, the tick loop runs regardless of the
    // `running` flag, and decrements — stops itself when it reaches 0.
    let mut steps_remaining: u32 = 0;

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
                ControlCommand::SetTicksPerSecond { tps } => {
                    if (1..=60).contains(&tps) {
                        tick_config.ticks_per_second = tps;
                        timer_interval = tick_config.tick_interval_ms();
                        interval_ms.store(timer_interval, Ordering::Relaxed);
                        ticks_per_second.store(tps, Ordering::Relaxed);
                        tick_scale = tick_config.tick_scale();
                        tick_mult = tick_config.tick_multiplier();
                        timer = interval(Duration::from_millis(timer_interval));
                        timer.set_missed_tick_behavior(MissedTickBehavior::Delay);
                        info!(
                            "Engine: ticks_per_second={} interval={}ms (tick_scale={:.4}, mult={})",
                            tps, timer_interval, tick_scale, tick_mult,
                        );
                    }
                }
                ControlCommand::SetWorldSpeed { world_speed } => {
                    if (0.0..=16.0).contains(&world_speed) {
                        tick_config.world_speed = world_speed;
                        tick_scale = tick_config.tick_scale();
                        tick_mult = tick_config.tick_multiplier();
                        world_speed_bits.store(world_speed.to_bits(), Ordering::Relaxed);
                        info!(
                            "Engine: world_speed={:.3} (tick_scale={:.4}, mult={})",
                            world_speed, tick_scale, tick_mult,
                        );
                    }
                }
                ControlCommand::MoveObserver { id, x, y, radius } => {
                    // Update (or insert) this observer by id. Heights
                    // are tiny (almost always 1 — the main camera), so
                    // a linear scan is cheaper than hashing.
                    if let Ok(mut obs) = observers.write() {
                        match obs.iter_mut().find(|o| o.id == id) {
                            Some(existing) => {
                                existing.x = x;
                                existing.y = y;
                                existing.radius = radius;
                            }
                            None => obs.push(Observer { id, x, y, radius }),
                        }
                    }
                }
                ControlCommand::Step { ticks } => {
                    // Schedule N forced ticks even if the sim is paused.
                    // Stacks with any already-queued steps so a user can
                    // tap "step 8" twice to step 16.
                    steps_remaining = steps_remaining.saturating_add(ticks);
                    info!("Engine: queued {} step-debug ticks", ticks);
                }
                ControlCommand::AdminSpawnShip(payload) => {
                    admin_spawn_ship(&mut store, &registry, payload, &mut events);
                }
                ControlCommand::AdminRemoveShip { id } => {
                    admin_remove_ship(&mut store, &id, &mut events, &persist_tx).await;
                }
                ControlCommand::AdminSpawnFacility(payload) => {
                    admin_spawn_facility(&mut store, payload, &mut events);
                }
                ControlCommand::AdminRemoveFacility { id } => {
                    admin_remove_facility(&mut store, &id, &mut events, &persist_tx).await;
                }
                ControlCommand::AdminMarketSupplyDelta { location, deltas } => {
                    admin_market_supply_delta(&mut store, &location, &deltas, &mut events);
                }
            }
        }

        // Step-debug override: if paused but the user asked for N steps,
        // run one step here and decrement. Otherwise honour the pause.
        let is_running = running.load(Ordering::Relaxed);
        if !is_running {
            if steps_remaining > 0 {
                steps_remaining -= 1;
            } else {
                tokio::time::sleep(Duration::from_millis(50)).await;
                continue;
            }
        }

        let tick = tick_counter.fetch_add(1, Ordering::Relaxed) + 1;
        let t_start = std::time::Instant::now();

        // Tick phases
        tick_bodies(&mut store, tick_scale);
        sim_core::agents::celestial_body::tick_bodies_regen(
            &mut store.world,
            tick,
            tick_scale,
            tick_mult,
        );

        // LOD recompute — gated by interval so we're not rebuilding the
        // distance table every tick. Populations + facilities inherit
        // their body's current position; ships use their own.
        let lod_interval = sim_core::simulation::lod::LOD_RECOMPUTE_INTERVAL_BASE
            * tick_mult as u64;
        if lod_interval > 0 && tick % lod_interval == 0 {
            let stats = recompute_lod(&mut store, &observers, tick);
            // Publish counters so the perf HUD can read tier distribution.
            lod_counters.0.store(stats.d1 as u64, Ordering::Relaxed);
            lod_counters.1.store(stats.d2 as u64, Ordering::Relaxed);
            lod_counters.2.store(stats.d5 as u64, Ordering::Relaxed);
            lod_counters.3.store(stats.d10 as u64, Ordering::Relaxed);
            lod_counters.4.store(stats.d20 as u64, Ordering::Relaxed);
            lod_counters.5.store(stats.d50 as u64, Ordering::Relaxed);
        }
        // Snapshot gate_pairs before ship tick so the pathfinder has a
        // stable read during BT planning. AgentStore.gate_pairs is
        // updated when gates spawn/despawn (admin operations).
        let gate_pairs_snapshot = store.gate_pairs.clone();
        ship::tick_ships(
            &mut store.world,
            &registry,
            &gate_pairs_snapshot,
            &store.contracts,
            &mut commands,
            tick,
            tick_scale,
            tick_mult,
        );
        apply_ship_commands(&mut store, &mut commands, &mut events);
        facility::tick_facilities(
            &mut store.world,
            &mut store.contracts,
            tick,
            tick_scale,
            tick_mult,
        );
        population::tick_populations(
            &mut store.world,
            &mut store.contracts,
            tick,
            tick_scale,
            tick_mult,
        );
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);
        // Market emits TransferCredits (spread revenue) — apply before clearing
        apply_ship_commands(&mut store, &mut commands, &mut events);
        faction::tick_factions(&mut store.world, &mut store.contracts, tick, tick_mult);
        commands.clear();

        let tick_compute_us = t_start.elapsed().as_micros() as u64;

        // Maintain a 60-tick rolling window for p50/p99.
        if perf_window.len() >= 60 {
            perf_window.pop_front();
        }
        perf_window.push_back(tick_compute_us);
        if tick.is_multiple_of(8) && !perf_window.is_empty() {
            let mut sorted: Vec<u64> = perf_window.iter().copied().collect();
            sorted.sort_unstable();
            let p50 = sorted[sorted.len() / 2];
            let p99 = sorted[sorted.len().saturating_sub(1).min(
                (sorted.len() as f32 * 0.99).ceil() as usize,
            )];
            tick_compute_p50_us.store(p50, Ordering::Relaxed);
            tick_compute_p99_us.store(p99, Ordering::Relaxed);
        }

        // Snapshot write
        snapshots.update_from(&store);
        let total_us = t_start.elapsed().as_micros() as u64;

        // Emit dirty-state writes for the persistence worker (cheap: try_send + mark clean)
        emit_persist_writes(&mut store, tick, &persist_tx);

        // Broadcasts (cadences match the protocol spec)
        publish_positions(tick, timer_interval, &snapshots, &broadcast_tx);
        if !events.is_empty() {
            let drained = std::mem::take(&mut events);
            let msg = ServerMsg::Events { tick, events: drained };
            let _ = broadcast_tx.send(Arc::new(msg));
        }
        if tick % 8 == 0 {
            publish_ship_states(tick, &snapshots, &broadcast_tx);
        }
        if tick % 16 == 0 {
            publish_market_states(tick, &snapshots, &broadcast_tx);
            publish_facility_states(tick, &snapshots, &broadcast_tx);
            publish_population_states(tick, &snapshots, &broadcast_tx);
        }
        if tick % 32 == 0 {
            publish_faction_states(tick, &snapshots, &broadcast_tx);
            publish_contract_states(tick, &snapshots, &broadcast_tx);
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
            log_factions(&store, tick);
        } else if tick % (8 * 5) == 0 {
            debug!(tick, tick_compute_us, total_us, "Engine: tick");
        }
    }
}

/// Walk the world, emit a `DbWrite` for each dirty-flagged agent, clear the
/// flag in place. Uses `try_send` so a temporarily-full persistence channel
/// never blocks the tick loop; the write will simply be skipped this round
/// and picked up on the next dirty mark.
fn emit_persist_writes(
    store: &mut AgentStore,
    tick: u64,
    tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::{
        faction::FactionData,
        market::{MarketHistory, MarketIdentity, MarketPricing},
        ship::{
            ShipCargo, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle, ShipPosition,
        },
    };

    // Ships
    for (_e, (identity, pos, cargo, fuel, econ, life)) in store
        .world
        .query::<(
            &ShipIdentity,
            &ShipPosition,
            &ShipCargo,
            &ShipFuel,
            &ShipEconomy,
            &mut ShipLifecycle,
        )>()
        .iter()
    {
        if !life.dirty {
            continue;
        }
        let cargo_json: serde_json::Map<String, serde_json::Value> = cargo
            .cargo
            .iter()
            .map(|(c, &q)| (c.as_str().to_string(), serde_json::Value::from(q)))
            .collect();
        let write = DbWrite::Ship {
            db_id: identity.db_id,
            credits: econ.credits,
            fuel: fuel.fuel,
            position_x: pos.position.0,
            position_y: pos.position.1,
            cargo_json: serde_json::Value::Object(cargo_json).to_string(),
            current_goal: String::new(), // ShipAI field; we don't have it in this query
            active_contract_id: econ.active_contract_id.clone(),
            broke_strikes: life.broke_strikes,
            hoard_strikes: life.hoard_strikes,
            idle_ticks: life.idle_ticks,
        };
        let _ = tx.try_send(write);
        life.dirty = false;
    }

    // Markets
    for (_e, (identity, pricing, hist)) in store
        .world
        .query::<(&MarketIdentity, &MarketPricing, &mut MarketHistory)>()
        .iter()
    {
        if !hist.dirty {
            continue;
        }
        let to_json = |m: &std::collections::HashMap<sim_core::economy::commodities::Commodity, f32>| {
            let map: serde_json::Map<String, serde_json::Value> = m
                .iter()
                .map(|(c, v)| (c.as_str().to_string(), serde_json::Value::from(*v)))
                .collect();
            serde_json::Value::Object(map).to_string()
        };
        let shortage_json = {
            let map: serde_json::Map<String, serde_json::Value> = hist
                .shortage_ticks
                .iter()
                .map(|(c, v)| (c.as_str().to_string(), serde_json::Value::from(*v)))
                .collect();
            serde_json::Value::Object(map).to_string()
        };
        let _ = tx.try_send(DbWrite::Market {
            db_id: identity.db_id,
            prices_json: to_json(&pricing.prices),
            supply_json: to_json(&pricing.supply),
            demand_json: to_json(&pricing.demand),
            shortage_ticks_json: shortage_json,
        });
        hist.dirty = false;
    }

    // Factions
    for (_e, data) in store.world.query::<&mut FactionData>().iter() {
        if !data.dirty {
            continue;
        }
        let _ = tx.try_send(DbWrite::Faction {
            id: data.id.clone(),
            treasury: data.treasury,
        });
        data.dirty = false;
    }

    // Facilities, populations, and bodies change a lot less frequently
    // than ships — gate their flushes to every ~2 seconds (8 ticks × 2)
    // so we don't overflow the persistence channel. The 5-second
    // worker-side sweep would dedupe anyway, but this keeps the channel
    // usage O(10) writes/sec instead of O(hundreds).
    let flush_facility = tick.is_multiple_of(16);
    let flush_population = tick.is_multiple_of(16);
    let flush_body = tick.is_multiple_of(40);

    if flush_facility {
        use sim_core::agents::facility::{FacilityIdentity, FacilityOperations, FacilityStorage};
        for (_e, (fid, ops, storage)) in store
            .world
            .query::<(&FacilityIdentity, &mut FacilityOperations, &FacilityStorage)>()
            .iter()
        {
            if !ops.dirty {
                continue;
            }
            let reserves_json: serde_json::Map<String, serde_json::Value> = storage
                .reserves
                .iter()
                .map(|(c, &v)| (c.as_str().to_string(), serde_json::Value::from(v)))
                .collect();
            let _ = tx.try_send(DbWrite::Facility {
                db_id: fid.db_id,
                credits: ops.credits,
                condition: ops.condition,
                reserves_json: serde_json::Value::Object(reserves_json).to_string(),
            });
            ops.dirty = false;
        }
    }

    if flush_population {
        use sim_core::agents::population::{
            PopDemographics, PopEconomy, PopIdentity, PopSentiment,
        };
        for (_e, (pid, demo, econ, sent)) in store
            .world
            .query::<(&PopIdentity, &PopDemographics, &PopEconomy, &mut PopSentiment)>()
            .iter()
        {
            if !sent.dirty {
                continue;
            }
            let _ = tx.try_send(DbWrite::Population {
                db_id: pid.db_id,
                population_count: demo.population_count,
                overall_sentiment: sent.overall_sentiment,
                food_satisfaction: sent.food_satisfaction,
                total_wealth: econ.total_wealth,
            });
            sent.dirty = false;
        }
    }

    if flush_body {
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit, BodyResources};
        for (_e, (bid, orbit, resources)) in store
            .world
            .query::<(&BodyIdentity, &mut BodyOrbit, &BodyResources)>()
            .iter()
        {
            if !orbit.dirty {
                continue;
            }
            let resources_json: serde_json::Map<String, serde_json::Value> = resources
                .resources
                .iter()
                .map(|(c, &v)| (c.as_str().to_string(), serde_json::Value::from(v)))
                .collect();
            let _ = tx.try_send(DbWrite::Body {
                db_id: bid.db_id,
                current_angle: orbit.current_angle,
                resources_json: serde_json::Value::Object(resources_json).to_string(),
            });
            orbit.dirty = false;
        }
    }

    // Tick counter every 8 ticks (≈1s)
    if tick.is_multiple_of(8) {
        let _ = tx.try_send(DbWrite::Tick { tick });
    }
}

/// Build a position lookup for every agent with an `AgentLod`, snapshot
/// the observer list, and hand off to `tick_lod_recompute`. Logs the
/// divisor distribution at info level when any agent got LOD'd down
/// (divisor > 1) — useful for spotting "everyone's at d=50 because
/// Godot never sent MoveObserver" config bugs.
fn recompute_lod(
    store: &mut AgentStore,
    observers: &Arc<std::sync::RwLock<Vec<Observer>>>,
    tick: u64,
) -> sim_core::simulation::lod::LodStats {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{FacilityIdentity, FacilityLocation},
        population::PopIdentity,
        ship::ShipPosition,
    };
    use sim_core::simulation::lod::{tick_lod_recompute, AgentLod};

    // Snapshot observers. Drop the lock before we take mutable world
    // iterators — avoids deadlocks from reentrant handlers.
    let obs_snapshot: Vec<(f32, f32, f32)> = match observers.read() {
        Ok(o) => o.iter().map(|o| (o.x, o.y, o.radius)).collect(),
        Err(_) => Vec::new(),
    };

    let mut pos_by_entity: std::collections::HashMap<hecs::Entity, (f32, f32)> =
        std::collections::HashMap::new();

    // Ships — live positions.
    for (e, (_lod, pos)) in store
        .world
        .query::<(&AgentLod, &ShipPosition)>()
        .iter()
    {
        pos_by_entity.insert(e, pos.position);
    }

    // Facilities + populations — look up by their facility location →
    // body position. Build body position map once.
    let body_pos: std::collections::HashMap<String, (f32, f32)> = store
        .world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    // Facilities.
    let facility_info: Vec<(hecs::Entity, String, String)> = store
        .world
        .query::<(&AgentLod, &FacilityIdentity, &FacilityLocation)>()
        .iter()
        .map(|(e, (_lod, id, _loc))| (e, id.body_id.clone(), id.id.clone()))
        .collect();
    for (e, body_id, fac_id) in facility_info {
        if let Some(&center) = body_pos.get(&body_id) {
            let pos = sim_core::agents::facility::facility_offset_position(center, &fac_id);
            pos_by_entity.insert(e, pos);
        }
    }

    // Populations — use the facility's body position (same offset as
    // the parent facility isn't necessary; body center is plenty for
    // LOD bucketing).
    let pop_info: Vec<(hecs::Entity, String)> = store
        .world
        .query::<(&AgentLod, &PopIdentity)>()
        .iter()
        .map(|(e, (_lod, id))| (e, id.facility_location.clone()))
        .collect();
    // location → body_id
    let loc_to_body: std::collections::HashMap<String, String> = store
        .world
        .query::<(&FacilityLocation, &FacilityIdentity)>()
        .iter()
        .map(|(_e, (loc, fid))| (loc.location_name.clone(), fid.body_id.clone()))
        .collect();
    for (e, loc) in pop_info {
        if let Some(body_id) = loc_to_body.get(&loc) {
            if let Some(&center) = body_pos.get(body_id) {
                pos_by_entity.insert(e, center);
            }
        }
    }

    let stats = tick_lod_recompute(&mut store.world, &pos_by_entity, &obs_snapshot, tick);
    if stats.total() > 0 && stats.d1 < stats.total() {
        debug!(
            tick,
            "LOD: {} @d1, {} @d2, {} @d5, {} @d10, {} @d20, {} @d50 (obs={})",
            stats.d1,
            stats.d2,
            stats.d5,
            stats.d10,
            stats.d20,
            stats.d50,
            obs_snapshot.len(),
        );
    }
    stats
}

fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_e, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}

fn apply_ship_commands(
    store: &mut AgentStore,
    commands: &mut CommandBuffer,
    events: &mut Vec<serde_json::Value>,
) {
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

            // --- Market spread revenue → facility ---
            SimCommand::TransferCredits { to, amount, .. } => {
                use sim_core::agents::facility::FacilityOperations;
                if amount > 0 {
                    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(to) {
                        ops.credits += amount;
                    }
                }
            }

            // --- Dock-dwell interactions (Phase 11a) ---
            SimCommand::RequestDock { ship, facility_location } => {
                let docked = apply_request_dock(store, ship, &facility_location);
                if docked {
                    events.push(serde_json::json!({
                        "kind": "ship_docked",
                        "ship_entity": format!("{:?}", ship),
                        "location": facility_location,
                    }));
                }
            }
            SimCommand::ReleaseDock { ship, facility_location } => {
                apply_release_dock(store, ship, &facility_location);
            }
            SimCommand::FacilityRefuel {
                ship: _,
                facility_location,
                amount,
                payment,
            } => {
                apply_facility_refuel(store, &facility_location, amount, payment);
            }
            SimCommand::GrantCrewXp { ship, skill, amount } => {
                use sim_core::agents::ship::ShipCrewSkills;
                if let Ok(mut skills) = store.world.get::<&mut ShipCrewSkills>(ship) {
                    skills.grant(skill, amount);
                }
            }
            SimCommand::RequestGateJump {
                ship,
                src_gate_location,
                dest_gate_location,
            } => {
                apply_gate_jump(
                    store,
                    ship,
                    &src_gate_location,
                    &dest_gate_location,
                    events,
                );
            }

            // --- Contracts ---
            SimCommand::AcceptContract { contract_id, ship_id, .. } => {
                // Best-effort: silently drop if the contract was already taken.
                let tick_now = 0; // Apply phase doesn't know the tick; board records accepted_at separately.
                store.contracts.accept(&contract_id, ship_id, tick_now);
            }
            SimCommand::DeliverContract { ship, contract_id } => {
                use sim_core::agents::population::PopDemographics;
                use sim_core::economy::contracts::ContractType;
                let delivered = store.contracts.mark_delivered(&contract_id);
                if let Some(c) = delivered {
                    // Pay the ship and bump faction reputation if the
                    // contract was tagged with one. +1 per successful
                    // delivery, capped at 100.
                    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
                        econ.credits += c.payment;
                        if let Some(faction) = c.faction_id.as_ref() {
                            let rep = econ
                                .faction_reputation
                                .entry(faction.clone())
                                .or_insert(0);
                            *rep = rep.saturating_add(1).min(100);
                        }
                    }

                    match c.contract_type {
                        ContractType::CrewMission => {
                            use sim_core::agents::ship::ShipCrewSkills;
                            use sim_core::economy::missions;
                            // Look up the template so we know which skill
                            // to grow and by how much. Missing template
                            // (e.g. legacy data) → no XP, just payment.
                            if let Some(cat) = c.mission_category.as_deref() {
                                if let Some(template) = missions::get(cat) {
                                    if let Ok(mut skills) =
                                        store.world.get::<&mut ShipCrewSkills>(ship)
                                    {
                                        skills.grant(
                                            template.required_skill,
                                            template.skill_gain,
                                        );
                                    }
                                    events.push(serde_json::json!({
                                        "kind": "crew_mission_completed",
                                        "contract_id": c.id,
                                        "category": cat,
                                        "skill": template.required_skill,
                                        "skill_gain": template.skill_gain,
                                        "payment": c.payment,
                                    }));
                                }
                            }
                        }
                        ContractType::Passenger => {
                            // Disembark: increment destination population.
                            // We treat the facility_location as the pop's
                            // home; any pops there grow by the head count.
                            for (_e, (id, demo)) in store
                                .world
                                .query::<(&sim_core::agents::population::PopIdentity, &mut PopDemographics)>()
                                .iter()
                            {
                                if id.facility_location == c.destination_location {
                                    demo.population_count += c.quantity as i64;
                                }
                            }
                            events.push(serde_json::json!({
                                "kind": "passengers_arrived",
                                "contract_id": c.id,
                                "destination": c.destination_location,
                                "head_count": c.quantity,
                                "payment": c.payment,
                            }));
                        }
                        _ => {
                            // Standard delivery / courier / subsidy: drop the
                            // commodity into the destination market supply.
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
                            events.push(serde_json::json!({
                                "kind": "contract_delivered",
                                "contract_id": c.id,
                                "contract_type": c.contract_type.as_str(),
                                "commodity": c.commodity.as_str(),
                                "destination": c.destination_location,
                                "payment": c.payment,
                                "faction_id": c.faction_id,
                            }));
                        }
                    }
                }
            }

            other => leftover.push(other),
        }
    }

    commands.commands.extend(leftover);
}

/// Pick the primary dockable facility at a location.
///
/// "Primary" = highest docking_capacity (farms/mining_rigs have capacity 0
/// and aren't candidates). Ties broken by first-seen hecs iteration order.
/// Returns None if no dockable facility exists at the location, in which
/// case dock/refuel commands silently no-op.
fn primary_dock_at_location(store: &AgentStore, location: &str) -> Option<hecs::Entity> {
    use sim_core::agents::facility::FacilityOperations;
    let candidates = store.facilities_at_location.get(location)?;
    let mut best: Option<(hecs::Entity, u32)> = None;
    for &e in candidates {
        let cap = store
            .world
            .get::<&FacilityOperations>(e)
            .map(|o| o.docking_capacity)
            .unwrap_or(0);
        if cap == 0 {
            continue;
        }
        if best.is_none_or(|(_, best_cap)| cap > best_cap) {
            best = Some((e, cap));
        }
    }
    best.map(|(e, _)| e)
}

/// Apply `RequestDock`: runs the same occupancy/condition fee formula as
/// Elixir's `facility_agent.ex:request_dock`. Deducts the fee from the
/// ship, adds it to the facility's credits, appends the ship entity to
/// `FacilityStorage.docked_ships`, and sets `ShipPosition.docked_at`.
/// Returns `true` if the dock succeeded (ship now docked), `false` if
/// it was rejected (no facility, capacity full, or ship broke).
fn apply_request_dock(
    store: &mut AgentStore,
    ship: hecs::Entity,
    location: &str,
) -> bool {
    use sim_core::agents::{
        facility::{docking_fee, FacilityOperations, FacilityStorage, DOCKING_FEE_BASE},
        ship::{ShipEconomy, ShipPosition},
    };

    let facility = match primary_dock_at_location(store, location) {
        Some(e) => e,
        None => return false,
    };

    // Read current occupancy + condition to compute fee.
    let (fee, at_capacity) = {
        let ops = match store.world.get::<&FacilityOperations>(facility) {
            Ok(o) => o,
            Err(_) => return false,
        };
        let storage = match store.world.get::<&FacilityStorage>(facility) {
            Ok(s) => s,
            Err(_) => return false,
        };
        let docked = storage.docked_ships.len() as u32;
        if docked >= ops.docking_capacity {
            (0, true)
        } else {
            (
                docking_fee(
                    DOCKING_FEE_BASE,
                    docked,
                    ops.docking_capacity,
                    ops.condition,
                ),
                false,
            )
        }
    };
    if at_capacity {
        return false;
    }

    // Can the ship afford it?
    let ship_ok = store
        .world
        .get::<&ShipEconomy>(ship)
        .map(|e| e.credits >= fee)
        .unwrap_or(false);
    if !ship_ok {
        return false;
    }

    // Deduct from ship, credit facility, register the dock.
    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
        econ.credits -= fee;
    }
    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(facility) {
        ops.credits += fee;
        ops.dirty = true;
    }
    if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
        if !storage.docked_ships.contains(&ship) {
            storage.docked_ships.push(ship);
        }
    }
    if let Ok(mut pos) = store.world.get::<&mut ShipPosition>(ship) {
        pos.docked_at = Some(facility);
    }
    true
}

/// Apply `ReleaseDock`: remove the ship from the facility's docked_ships
/// list. The ship's `docked_at` has already been cleared in-place by the
/// Undock action.
fn apply_release_dock(
    store: &mut AgentStore,
    ship: hecs::Entity,
    location: &str,
) {
    use sim_core::agents::facility::FacilityStorage;
    let facility = match primary_dock_at_location(store, location) {
        Some(e) => e,
        None => return,
    };
    if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
        storage.docked_ships.retain(|&e| e != ship);
    }
}

/// Admin: spawn a new ship hecs entity from an already-INSERTed DB row.
/// The HTTP handler wrote the DB row and handed us the db_id; we build
/// the matching hecs bundle here and index it.
fn admin_spawn_ship(
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

    // Phase 18a: admin-spawned ships also get the tier-1 default fitting
    // (gameplay-neutral). A later refit endpoint (Phase 18b) will let
    // callers pass a custom loadout at spawn.
    let fitting = sim_core::agents::ship::ShipFitting::new_default();
    let cargo_cap = ((cargo_cap as f32) * fitting.derived.cargo_capacity_mult).round() as u32;
    let speed_mod = speed_mod * fitting.derived.speed_mult;

    let entity = store.world.spawn((
        ShipIdentity {
            db_id: payload.db_id,
            id: payload.agent_id.clone(),
            name: payload.name.clone(),
            class: payload.class.clone(),
            faction_id: payload.faction_id.clone(),
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
        },
        ShipFuel {
            fuel: fuel_cap,
            fuel_capacity: fuel_cap,
            fuel_consumption_rate: fuel_rate,
            speed_modifier: speed_mod,
        },
        ShipEconomy {
            credits: payload.credits,
            efficiency: 1.0,
            active_contract_id: None,
            faction_reputation: std::collections::HashMap::new(),
            dock_dwell_start_tick: None,
        },
        ShipAI {
            // Admin-spawned ships get the balanced archetype as a reasonable
            // default — the admin UI will add a personality picker later.
            personality: Personality::balanced_trader(),
            current_goal: "idle".to_string(),
            current_bt: None,
        },
    ));
    store.world.insert(
        entity,
        (
            ShipMemory {
                price_knowledge: std::collections::HashMap::new(),
                visited: vec![payload.location_name.clone()],
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
            sim_core::simulation::lod::AgentLod::new(),
        ),
    )
    .ok();
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
fn admin_spawn_facility(
    store: &mut AgentStore,
    payload: crate::control::AdminSpawnFacilityPayload,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::facility::{
        FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations, FacilityStorage,
    };

    if store.facility_by_id.contains_key(&payload.agent_id) {
        return;
    }

    let entity = store.world.spawn((
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
        },
        FacilityStorage {
            reserves: std::collections::HashMap::new(),
            docked_ships: vec![],
            pending_deliveries: vec![],
        },
        FacilityLifecycle::new(),
        sim_core::simulation::lod::AgentLod::new(),
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
async fn admin_remove_ship(
    store: &mut AgentStore,
    id: &str,
    events: &mut Vec<serde_json::Value>,
    persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::{facility::FacilityStorage, ship::ShipIdentity};
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };
    // Pull db_id BEFORE despawn so we can schedule the row delete.
    let db_id = store
        .world
        .get::<&ShipIdentity>(entity)
        .ok()
        .map(|i| i.db_id);
    // Pop from any facility's docked list first.
    for (_e, storage) in store.world.query_mut::<&mut FacilityStorage>() {
        storage.docked_ships.retain(|&e| e != entity);
    }
    let _ = store.world.despawn(entity);
    store.ship_by_id.remove(id);
    // Snapshot cache is purged by `update_from` on the next tick (diffs
    // live entity ids against the cache and removes missing keys).
    if let Some(db_id) = db_id {
        let _ = persist_tx.send(DbWrite::DeleteShip { db_id }).await;
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
async fn admin_remove_facility(
    store: &mut AgentStore,
    id: &str,
    events: &mut Vec<serde_json::Value>,
    persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::facility::FacilityIdentity;
    let Some(&entity) = store.facility_by_id.get(id) else {
        return;
    };
    let db_id = store
        .world
        .get::<&FacilityIdentity>(entity)
        .ok()
        .map(|i| i.db_id);
    // Remove from facilities_at_location map.
    for entries in store.facilities_at_location.values_mut() {
        entries.retain(|&e| e != entity);
    }
    let _ = store.world.despawn(entity);
    store.facility_by_id.remove(id);
    if let Some(db_id) = db_id {
        let _ = persist_tx.send(DbWrite::DeleteFacility { db_id }).await;
    }
    events.push(serde_json::json!({
        "kind": "facility_removed",
        "id": id,
        "reason": "admin",
    }));
}

/// Admin: apply a supply delta to the market at `location`. Positive
/// values top up, negative drain (floored at 0). No-ops if the location
/// has no market.
fn admin_market_supply_delta(
    store: &mut AgentStore,
    location: &str,
    deltas: &[(sim_core::economy::commodities::Commodity, f32)],
    events: &mut Vec<serde_json::Value>,
) {
    let Some(&market_entity) = store.market_at_location.get(location) else {
        return;
    };
    let mut applied: Vec<(String, f32)> = Vec::new();
    if let Ok(mut pricing) = store.world.get::<&mut MarketPricing>(market_entity) {
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

/// Apply `RequestGateJump`: locate the source gate at the ship's
/// location, charge the fee, credit the gate's owning facility,
/// teleport the ship to the paired gate's position. Emits a
/// `ship_gate_jumped` event for the HUD.
///
/// Silently no-ops when the ship isn't at a gate, the gate has no
/// link, or the ship can't afford the fee — the BT's
/// speculative position update has already moved the ship locally,
/// but apply reverses it by just... not actually teleporting (which
/// would be a bug). **TODO**: in a future pass, make the BT commit
/// position change only after apply confirms — current model is
/// optimistic and can drift if the jump fails. Low risk today because
/// the planner's "can_afford" check guards it.
fn apply_gate_jump(
    store: &mut AgentStore,
    ship: hecs::Entity,
    src_gate_location: &str,
    dest_gate_location: &str,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::{
        facility::{gate_transit_fee, FacilityIdentity, FacilityOperations, GateLink},
        ship::{ShipCargo, ShipEconomy, ShipIdentity, ShipPosition},
    };

    // Find the source gate facility at the requested location. Ignore
    // non-gate facilities at the same location.
    let src_gate_entity = store
        .facilities_at_location
        .get(src_gate_location)
        .into_iter()
        .flatten()
        .copied()
        .find(|&e| store.world.get::<&GateLink>(e).is_ok());
    let Some(src_gate_entity) = src_gate_entity else {
        return;
    };

    // Pull the fee up front (all reads) before any mutation.
    let (fee, paired_id) = {
        let link = match store.world.get::<&GateLink>(src_gate_entity) {
            Ok(l) => l,
            Err(_) => return,
        };
        let cargo_used = store
            .world
            .get::<&ShipCargo>(ship)
            .map(|c| c.used())
            .unwrap_or(0);
        (gate_transit_fee(&link, cargo_used), link.paired_gate_id.clone())
    };

    // Ship must be able to pay.
    let can_afford = store
        .world
        .get::<&ShipEconomy>(ship)
        .map(|e| e.credits >= fee)
        .unwrap_or(false);
    if !can_afford {
        return;
    }

    // Deduct from ship, credit gate.
    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
        econ.credits -= fee;
    }
    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(src_gate_entity) {
        ops.credits += fee;
        ops.dirty = true;
    }

    // Resolve the paired gate and its position, teleport the ship.
    let dest_entity = store.facility_by_id.get(&paired_id).copied();
    let ship_new_pos = dest_entity.and_then(|e| {
        let id = store.world.get::<&FacilityIdentity>(e).ok()?.id.clone();
        // Find the body the paired gate is orbiting so we can compute
        // the offset-position to match where the paired gate renders.
        let body_id = store.world.get::<&FacilityIdentity>(e).ok()?.body_id.clone();
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
        let body_pos = store
            .world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter()
            .find(|(_, (bid, _))| bid.body_id == body_id)
            .map(|(_, (_, orbit))| orbit.universe_position());
        let body_pos = body_pos?;
        Some(sim_core::agents::facility::facility_offset_position(
            body_pos, &id,
        ))
    });
    if let Ok(mut pos) = store.world.get::<&mut ShipPosition>(ship) {
        pos.location_name = Some(dest_gate_location.to_string());
        pos.docked_at = None;
        if let Some(new_pos) = ship_new_pos {
            pos.position = new_pos;
        }
    }

    let ship_id = store
        .world
        .get::<&ShipIdentity>(ship)
        .map(|i| i.id.clone())
        .unwrap_or_else(|_| "unknown".to_string());
    events.push(serde_json::json!({
        "kind": "ship_gate_jumped",
        "id": ship_id,
        "src_gate": src_gate_location,
        "dest_gate": dest_gate_location,
        "fee": fee,
    }));
}

/// Apply `FacilityRefuel`: drain fuel from the facility's reserves and
/// credit the facility's treasury. Ship-side fuel/credit updates already
/// happened when the command was emitted.
fn apply_facility_refuel(
    store: &mut AgentStore,
    location: &str,
    amount: f32,
    payment: i64,
) {
    use sim_core::{
        agents::facility::{FacilityOperations, FacilityStorage},
        economy::commodities::Commodity,
    };
    let facility = match primary_dock_at_location(store, location) {
        Some(e) => e,
        None => return,
    };
    if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
        let entry = storage.reserves.entry(Commodity::Fuel).or_insert(0.0);
        *entry = (*entry - amount).max(0.0);
    }
    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(facility) {
        ops.credits += payment;
        ops.dirty = true;
    }
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
            } else if id.starts_with("facility-") {
                "facility"
            } else {
                // Body ids in the JSON world data are bare ("earth", "mars",
                // etc.) — default everything non-ship/non-facility to "body".
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

fn publish_facility_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let facilities: Vec<serde_json::Value> = snapshots
        .facilities
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::FacilityStates { tick, facilities };
    let _ = tx.send(Arc::new(msg));
}

fn publish_population_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let populations: Vec<serde_json::Value> = snapshots
        .populations
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::PopulationStates { tick, populations };
    let _ = tx.send(Arc::new(msg));
}

fn publish_faction_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let factions: Vec<serde_json::Value> = snapshots
        .factions
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::FactionStates { tick, factions };
    let _ = tx.send(Arc::new(msg));
}

/// Publish the full contract board from the snapshot cache (refreshed
/// every tick in `SnapshotCache::update_contracts`).
fn publish_contract_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let contracts: Vec<serde_json::Value> = snapshots
        .contracts
        .iter()
        .map(|e| e.value().clone())
        .collect();
    let msg = ServerMsg::ContractStates { tick, contracts };
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

fn log_factions(store: &AgentStore, tick: u64) {
    use sim_core::agents::faction::FactionData;
    let mut totals: Vec<(String, i64)> = store
        .world
        .query::<&FactionData>()
        .iter()
        .map(|(_, d)| (d.id.clone(), d.treasury))
        .collect();
    totals.sort_by(|a, b| b.1.cmp(&a.1));
    let summary: Vec<String> = totals
        .iter()
        .map(|(id, t)| format!("{id}={t}"))
        .collect();
    info!(tick, "factions: {}", summary.join(", "));
}

fn log_sample_ships(store: &AgentStore, tick: u64) {
    use sim_core::agents::ship::{ShipAI, ShipCargo, ShipCrew, ShipEconomy, ShipMemory};
    let mut by_goal: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
    let mut by_task: std::collections::HashMap<&'static str, u32> = std::collections::HashMap::new();
    let mut total_credits: i64 = 0;
    let mut ships_with_cargo: u32 = 0;
    let mut ship_count: u32 = 0;
    let mut max_credits: i64 = 0;
    let mut min_credits: i64 = i64::MAX;
    let mut total_visited: u32 = 0;
    let mut total_morale: f32 = 0.0;
    let mut min_morale: f32 = 100.0;
    for (_e, (ai, econ, cargo, mem, crew)) in store
        .world
        .query::<(&ShipAI, &ShipEconomy, &ShipCargo, &ShipMemory, &ShipCrew)>()
        .iter()
    {
        *by_goal.entry(ai.current_goal.clone()).or_insert(0) += 1;
        *by_task.entry(crew.current_task.as_str()).or_insert(0) += 1;
        total_credits += econ.credits;
        max_credits = max_credits.max(econ.credits);
        min_credits = min_credits.min(econ.credits);
        if cargo.used() > 0 {
            ships_with_cargo += 1;
        }
        total_visited += mem.visited.len() as u32;
        total_morale += crew.morale;
        min_morale = min_morale.min(crew.morale);
        ship_count += 1;
    }
    if ship_count > 0 {
        let avg = total_credits / ship_count as i64;
        let avg_visited = total_visited as f32 / ship_count as f32;
        let avg_morale = total_morale / ship_count as f32;
        info!(
            tick,
            "ships: {:?} | tasks: {:?} | credits avg/min/max={}/{}/{} | with_cargo={} | avg_visited={:.1} | morale avg/min={:.0}/{:.0}",
            by_goal, by_task, avg, min_credits, max_credits, ships_with_cargo, avg_visited, avg_morale, min_morale,
        );
    }
}
