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
    snapshot::SnapshotCache,
    ws::protocol::ServerMsg,
};
use sim_db::persistence::DbWrite;
use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        facility,
        faction,
        market::{self, MarketPricing},
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

mod drains;
mod persist;
mod publish;
use drains::{
    drain_pending_decommissions, drain_pending_materializations, drain_pending_respawns,
    materialize_facility,
};
pub use drains::random_ship_name;
use persist::emit_persist_writes;
use publish::{
    log_contract_board, log_factions, log_sample_market, log_sample_ships,
    publish_contract_states, publish_facility_states, publish_faction_states,
    publish_market_states, publish_population_states, publish_positions, publish_ship_states,
};

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
    pool: sqlx::SqlitePool,
    command_trace: std::sync::Arc<std::sync::RwLock<std::collections::VecDeque<crate::app_state::CommandTraceEntry>>>,
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
                    let tick_now = tick_counter.load(Ordering::Relaxed);
                    admin_remove_ship(
                        &mut store,
                        &id,
                        tick_now,
                        &mut events,
                        &persist_tx,
                    )
                    .await;
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
                ControlCommand::AdminGrantShipXp { id, amount } => {
                    admin_grant_ship_xp(&mut store, &id, amount, &mut events);
                }
                ControlCommand::AdminRefitFacility { id, slot, slug } => {
                    admin_refit_facility(&mut store, &id, slot, slug.as_deref(), &mut events);
                }
                ControlCommand::AdminRefitShip { id, slot, slug, via_shipyard } => {
                    admin_refit_ship(
                        &mut store,
                        &id,
                        slot,
                        slug.as_deref(),
                        via_shipyard,
                        &mut events,
                    );
                }
                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {
                    admin_set_relations(
                        &mut store,
                        &a,
                        &b,
                        standing,
                        treaty,
                        tick_counter.load(Ordering::Relaxed),
                        &mut events,
                    );
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
            &store.relations,
            &mut commands,
            tick,
            tick_scale,
            tick_mult,
        );
        record_command_trace(&store, &commands, tick, &command_trace);
        apply_ship_commands(&mut store, &mut commands, &mut events, tick);
        // Per-tick queue advance: admits any queue heads that have
        // space and credits, independent of whether the ship at the
        // head is currently emitting RequestDock. Prevents LOD'd-out
        // ships from indefinitely holding queue slots they can't
        // actively poll for.
        tick_dock_queue_advance(&mut store);
        drain_pending_materializations(&mut store, &pool, &persist_tx, &mut events).await;
        drain_pending_decommissions(&mut store, tick, &mut events, &persist_tx).await;
        drain_pending_respawns(&mut store, &registry, tick, &mut events, &persist_tx, &pool).await;
        facility::tick_facilities(
            &mut store.world,
            &mut store.contracts,
            &mut events,
            tick,
            tick_scale,
            tick_mult,
        );
        population::tick_populations(
            &mut store.world,
            &mut store.contracts,
            &mut events,
            tick,
            tick_scale,
            tick_mult,
        );
        market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);
        // Bundle (S): after markets + facilities tick, emit
        // structural-warning events on threshold crossings so
        // Godot can surface "5 markets in crisis" / "2 facilities
        // starving" without polling every panel. Hysteresis
        // windows inside `scan_crisis_events` prevent flapping.
        scan_crisis_events(&mut store.world, &mut events);
        // Market emits TransferCredits (spread revenue) — apply before clearing
        record_command_trace(&store, &commands, tick, &command_trace);
        apply_ship_commands(&mut store, &mut commands, &mut events, tick);
        drain_pending_materializations(&mut store, &pool, &persist_tx, &mut events).await;
        drain_pending_decommissions(&mut store, tick, &mut events, &persist_tx).await;
        drain_pending_respawns(&mut store, &registry, tick, &mut events, &persist_tx, &pool).await;
        faction::tick_factions(&mut store.world, &mut store.contracts, &mut events, tick, tick_mult);
        // Bundle A: inter-faction relations. Low-frequency — decay +
        // threshold-driven treaty transitions only need to run on
        // the relations interval. Emits `treaty_changed` events for
        // every state crossing (picked up by Godot event ticker).
        tick_relations_pass(&mut store, &mut events, tick, tick_mult);
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
        snapshots.update_from(&store, tick);
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
/// Boot-time contract pump. Runs the posting phases of facilities,
/// populations, and factions N times in sequence to populate the
/// ContractBoard before the main tick loop starts. Skipped if the
/// board already has rows (DB-load case — contracts were hydrated).
///
/// Without this, a fresh-seed world boots with an empty contract
/// board and the Godot client shows "0 contracts" until a few real
/// ticks of the economy have run — feels dead for the first minute.
///
/// Tick is passed as 0 so posted_at_tick lines up with the "world
/// came online" moment. Each posting function's own throttles (one
/// active crew mission per facility, etc.) keep the board from
/// exploding across multiple passes.
pub fn run_contract_pump(store: &mut AgentStore, passes: u32) {
    if !store.contracts.is_empty() {
        return;
    }
    for _ in 0..passes {
        sim_core::agents::facility::tick_post_contracts(
            &mut store.world,
            &mut store.contracts,
            0,
            1,
        );
        sim_core::agents::facility::tick_post_crew_missions(
            &mut store.world,
            &mut store.contracts,
            0,
            1,
        );
        // tick_populations bails internally unless `tick` lands on a
        // CONSUMPTION or PRODUCTION interval; 0 % N == 0 for any N,
        // so this always fires. Boot-time pump has no client to ship
        // events to, so we feed a throwaway buffer.
        let mut pump_events: Vec<serde_json::Value> = Vec::new();
        sim_core::agents::population::tick_populations(
            &mut store.world,
            &mut store.contracts,
            &mut pump_events,
            0,
            1.0,
            1,
        );
        sim_core::agents::faction::tick_factions(
            &mut store.world,
            &mut store.contracts,
            &mut pump_events,
            0,
            1,
        );
    }
    tracing::info!(
        "Engine: contract pump ran {} passes — board size now {}",
        passes,
        store.contracts.len()
    );
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

pub fn tick_bodies(store: &mut AgentStore, tick_scale: f32) {
    for (_e, orbit) in store.world.query_mut::<&mut BodyOrbit>() {
        orbit.advance(tick_scale);
    }
}

pub fn apply_ship_commands(
    store: &mut AgentStore,
    commands: &mut CommandBuffer,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
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
            SimCommand::RequestDock {
                ship,
                facility_location,
                preferred_facility_type,
            } => {
                let docked = apply_request_dock_typed(
                    store,
                    ship,
                    &facility_location,
                    preferred_facility_type,
                );
                if docked {
                    events.push(serde_json::json!({
                        "kind": "ship_docked",
                        "ship_entity": format!("{:?}", ship),
                        "location": facility_location,
                        "preferred_type": preferred_facility_type,
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
                let accepted = store.contracts.accept(&contract_id, ship_id.clone(), tick_now);
                if accepted {
                    // Ticker event so players can watch the contract
                    // board churn in real time. Losing speculative
                    // accepts return false from `accept()` and don't
                    // emit (those ships will self-clean via the
                    // sanity-check pass on next tick).
                    if let Some(c) = store.contracts.get(&contract_id) {
                        events.push(serde_json::json!({
                            "kind": "contract_accepted",
                            "contract_id": contract_id,
                            "contract_type": c.contract_type.as_str(),
                            "ship_id": ship_id,
                            "commodity": c.commodity.as_str(),
                            "source": c.source_location,
                            "destination": c.destination_location,
                            "payment": c.payment,
                        }));
                    }
                }
            }
            SimCommand::ReleaseContract { ship_id, contract_id, reason } => {
                // Move Accepted → Posted so another ship can try. The
                // fulfiller_id guard inside `release` ensures a losing
                // speculative-accept can't yank the winning ship's
                // contract; if we weren't the named fulfiller, the
                // call is a no-op, which is what we want.
                //
                // Phase 19e: read the contract's faction + payment
                // BEFORE release so we can apply a breach rep penalty
                // on the winning ship only. `release` clears
                // fulfiller_id, so we need the snapshot up front.
                let breach_info = store.contracts.get(&contract_id).and_then(|c| {
                    c.faction_id.as_ref().map(|f| (f.clone(), c.payment))
                });
                let released = store
                    .contracts
                    .release(&contract_id, Some(&ship_id));
                if released {
                    tracing::debug!(
                        contract_id = %contract_id,
                        ship_id = %ship_id,
                        reason = %reason,
                        "contract released back to Posted"
                    );
                    // Breach penalty: shave faction rep by
                    // `10 + payment/1000`, clamped to [1, 25]. Matches
                    // Elixir — real stakes to accepting a contract.
                    // Only fires when the contract had a faction tag
                    // (most facility-owned deliveries do now that
                    // 19e-1 landed).
                    if let Some((faction, payment)) = breach_info {
                        let ship_entity = store.ship_by_id.get(&ship_id).copied();
                        if let Some(e) = ship_entity {
                            // Read ship faction up front — used by the
                            // Bundle A standing hit after the econ
                            // borrow releases.
                            let ship_faction = store
                                .world
                                .get::<&sim_core::agents::ship::ShipIdentity>(e)
                                .ok()
                                .map(|i| i.faction_id.clone())
                                .unwrap_or_default();
                            if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(e) {
                                let penalty: u8 = (10 + (payment / 1000))
                                    .clamp(1, 25) as u8;
                                let rep = econ
                                    .faction_reputation
                                    .entry(faction.clone())
                                    .or_insert(0);
                                *rep = rep.saturating_sub(penalty);
                                events.push(serde_json::json!({
                                    "kind": "contract_breached",
                                    "contract_id": contract_id,
                                    "ship_id": ship_id,
                                    "faction_id": faction,
                                    "rep_penalty": penalty,
                                    "reason": reason,
                                }));
                            }
                            // Bundle A: ship's faction takes the blame
                            // on the relations matrix too. Keeps the
                            // per-faction stance aligned with per-ship
                            // reputation — both sides walk together.
                            if !ship_faction.is_empty()
                                && !faction.is_empty()
                                && ship_faction != faction
                            {
                                let new_standing = store.relations.bump_standing(
                                    &ship_faction,
                                    &faction,
                                    sim_core::agents::faction_relations::BREACH_STANDING_PENALTY,
                                    tick,
                                );
                                events.push(serde_json::json!({
                                    "kind": "faction_standing_changed",
                                    "a": ship_faction,
                                    "b": faction,
                                    "delta": sim_core::agents::faction_relations::BREACH_STANDING_PENALTY,
                                    "new_standing": new_standing,
                                    "cause": "breach",
                                    "reason": reason,
                                }));
                            }
                        }
                    }
                }
            }
            SimCommand::DeliverContract { ship, contract_id } => {
                use sim_core::agents::population::PopDemographics;
                use sim_core::economy::contracts::ContractType;
                let delivered = store.contracts.mark_delivered(&contract_id);
                if let Some(c) = delivered {
                    // Pay the ship and bump faction reputation if the
                    // contract was tagged with one. +1 per successful
                    // delivery, capped at 100.
                    //
                    // Phase 18f: comms_bonus on the ship's fitting
                    // multiplies payment. A tier-3 comms suite adds
                    // 10% — reads the stat at apply time rather than
                    // baking it in to avoid stale-fitting edge cases
                    // after a refit mid-flight.
                    let comms_bonus = store
                        .world
                        .get::<&sim_core::agents::ship::ShipFitting>(ship)
                        .map(|f| f.derived.comms_bonus)
                        .unwrap_or(0.0);
                    // Bundle A: read ship faction up front for the
                    // relations-standing bump. Taking an immutable
                    // borrow of ShipIdentity here and letting it drop
                    // before the `&mut ShipEconomy` acquisition below
                    // keeps hecs happy (one live component borrow per
                    // entity).
                    let ship_faction = store
                        .world
                        .get::<&sim_core::agents::ship::ShipIdentity>(ship)
                        .ok()
                        .map(|i| i.faction_id.clone())
                        .unwrap_or_default();
                    // Bundle B: treaty-driven payment bonus applies on
                    // top of Phase 18f's comms multiplier. TradePact =
                    // +10%, Allied = +15%, anything else = 1.0 (same
                    // as pre-Bundle-B behaviour).
                    let treaty_mult = c
                        .faction_id
                        .as_deref()
                        .map(|f| {
                            sim_core::agents::faction_relations::trade_pact_payment_multiplier(
                                &store.relations,
                                &ship_faction,
                                f,
                            )
                        })
                        .unwrap_or(1.0);
                    let effective_payment: i64 =
                        ((c.payment as f32) * (1.0 + comms_bonus) * treaty_mult)
                            .round() as i64;
                    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
                        econ.credits += effective_payment;
                        if let Some(faction) = c.faction_id.as_ref() {
                            // Phase 19e: reputation gain scales with
                            // payment so big contracts move rep faster
                            // (otherwise a 1-off +1 makes faction-gated
                            // work effectively unreachable). Matches
                            // Elixir's `min(5 + payment/2000, 15)`.
                            let gain: u8 = (5 + (effective_payment / 2000))
                                .clamp(1, 15)
                                as u8;
                            let rep = econ
                                .faction_reputation
                                .entry(faction.clone())
                                .or_insert(0);
                            *rep = rep.saturating_add(gain).min(100);
                        }
                    }
                    // Bundle A: faction-to-faction standing bump. Fires
                    // when both sides are tagged and distinct. Small
                    // per-delivery nudge so a healthy trade corridor
                    // accumulates into a TradePact over hundreds of
                    // deliveries, not dozens. `bump_standing` is a
                    // no-op on empty or self-pairs.
                    if let Some(requestor) = c.faction_id.as_deref() {
                        if !ship_faction.is_empty()
                            && !requestor.is_empty()
                            && ship_faction != requestor
                        {
                            let new_standing = store.relations.bump_standing(
                                &ship_faction,
                                requestor,
                                sim_core::agents::faction_relations::DELIVERY_STANDING_BUMP,
                                tick,
                            );
                            events.push(serde_json::json!({
                                "kind": "faction_standing_changed",
                                "a": ship_faction,
                                "b": requestor,
                                "delta": sim_core::agents::faction_relations::DELIVERY_STANDING_BUMP,
                                "new_standing": new_standing,
                                "cause": "delivery",
                            }));
                        }
                    }
                    // Adaptive-fleet: clear hoard strikes on any
                    // successful delivery. A ship that's been rich +
                    // idle recovers toward "productive" the moment it
                    // moves cargo, without waiting for idle_ticks to
                    // drop below the threshold.
                    if let Ok(mut life) = store
                        .world
                        .get::<&mut sim_core::agents::ship::ShipLifecycle>(ship)
                    {
                        life.hoard_strikes = 0;
                    }
                    // Bundle 1.4: personality drift. A successful
                    // delivery nudges the ship's `profit` axis up a
                    // sliver. Invisible per-delivery; visible over
                    // many deliveries as a character arc.
                    if let Ok(mut ai) = store
                        .world
                        .get::<&mut sim_core::agents::ship::ShipAI>(ship)
                    {
                        ai.personality.drift(
                            sim_core::ai::personality::Axis::Profit,
                            sim_core::agents::ship::DRIFT_DELIVERY_PROFIT,
                        );
                    }
                    // Phase 18d: grant ship-level XP on every delivery.
                    // Cascades level-ups + banks retrofit points when a
                    // threshold crosses. Kept independent of crew skill
                    // XP; ships and crews progress on separate tracks.
                    {
                        use sim_core::agents::ship::{
                            ShipIdentity, ShipProgression, SHIP_XP_PER_DELIVERY,
                        };
                        let ship_agent_id = store
                            .world
                            .get::<&ShipIdentity>(ship)
                            .map(|i| i.id.clone())
                            .unwrap_or_default();
                        if let Ok(mut prog) = store.world.get::<&mut ShipProgression>(ship) {
                            let gained = prog.grant_xp(SHIP_XP_PER_DELIVERY);
                            if gained > 0 {
                                events.push(serde_json::json!({
                                    "kind": "ship_leveled_up",
                                    "id": ship_agent_id,
                                    "new_level": prog.level,
                                    "retrofit_points": prog.retrofit_points,
                                    "levels_gained": gained,
                                }));
                            }
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
                        ContractType::Construction => {
                            // Phase 19c-c: the delivered commodity goes
                            // INTO the construction site, not the
                            // destination market. Remove from the ship's
                            // cargo hold the same way, then route
                            // progress to the site at this
                            // (location, commodity).
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
                            apply_construction_delivery(
                                store,
                                &c.destination_location,
                                c.commodity,
                                c.quantity,
                                events,
                            );
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

            // Phase 18d: agent-driven refit via shipyard. Validates
            // stock + credits + docked-at-shipyard, does the fitting
            // swap, commits the economic side, and consumes one
            // retrofit point on success. Silently drops on any
            // rejection — the BT will replan next tick.
            SimCommand::RequestRefit { ship, slot, slug } => {
                use sim_core::agents::ship::{ShipIdentity, ShipProgression};

                let has_point = store
                    .world
                    .get::<&ShipProgression>(ship)
                    .map(|p| p.retrofit_points > 0)
                    .unwrap_or(false);
                if !has_point {
                    continue;
                }
                let Ok((fac_entity, fac_id, cost)) = try_shipyard_refit(store, ship, slot, slug)
                else {
                    continue;
                };
                let prev_slug = match apply_fitting_swap(store, ship, slot, Some(slug)) {
                    RefitAttempt::Applied { prev_slug } => prev_slug,
                    _ => continue,
                };
                commit_shipyard_refit(store, ship, fac_entity, slug, cost);
                if let Ok(mut prog) = store.world.get::<&mut ShipProgression>(ship) {
                    prog.spend_retrofit_point();
                }
                let ship_id = store
                    .world
                    .get::<&ShipIdentity>(ship)
                    .map(|i| i.id.clone())
                    .unwrap_or_default();
                events.push(serde_json::json!({
                    "kind": "ship_refitted",
                    "id": ship_id,
                    "slot": slot.as_str(),
                    "from": prev_slug,
                    "to": slug,
                    "via": "agent_shipyard",
                    "shipyard_id": fac_id,
                    "cost": cost,
                }));
            }

            SimCommand::DecommissionShip { ship, reason } => {
                // Queue for async drain — admin_remove_ship needs the
                // persist_tx + awaits events, which this sync fn can't
                // do. The tick loop runs `drain_pending_decommissions`
                // right after apply and also schedules a
                // `PendingRespawn` so fleet size recovers over time.
                store.pending_decommissions.push(
                    sim_core::simulation::spawner::PendingDecommission { entity: ship, reason },
                );
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
pub fn primary_dock_at_location(store: &AgentStore, location: &str) -> Option<hecs::Entity> {
    primary_dock_at_location_typed(store, location, None)
}

/// Pick the largest dockable facility at `location`, optionally
/// restricted to a `facility_type` (e.g. `"shipyard"`). Returns `None`
/// if no candidate matches; callers (e.g. agent retrofit BT) should
/// treat that as a silent dock rejection — the BT fails cleanly and
/// replans next tick.
pub fn primary_dock_at_location_typed(
    store: &AgentStore,
    location: &str,
    facility_type: Option<&str>,
) -> Option<hecs::Entity> {
    dockable_candidates_ordered(store, location, facility_type)
        .into_iter()
        .next()
}

/// Return every dockable facility at `location` (docking_capacity > 0,
/// matching `facility_type` if set), sorted by capacity descending.
/// Phase 18k: lets `apply_request_dock_typed` fall through from the
/// primary to secondary/tertiary facilities when the biggest one is
/// full — haven-station has 5 facilities totalling 16 slots; pre-18k
/// only the 8-slot primary got used, so 111 ships piled up on it and
/// the remaining 8 slots sat idle.
pub fn dockable_candidates_ordered(
    store: &AgentStore,
    location: &str,
    facility_type: Option<&str>,
) -> Vec<hecs::Entity> {
    use sim_core::agents::facility::{FacilityIdentity, FacilityOperations};
    let Some(candidates) = store.facilities_at_location.get(location) else {
        return Vec::new();
    };
    let mut scored: Vec<(hecs::Entity, u32)> = Vec::new();
    for &e in candidates {
        if let Some(want) = facility_type {
            let ok = store
                .world
                .get::<&FacilityIdentity>(e)
                .map(|id| id.facility_type == want)
                .unwrap_or(false);
            if !ok {
                continue;
            }
        }
        let cap = store
            .world
            .get::<&FacilityOperations>(e)
            .map(|o| o.docking_capacity)
            .unwrap_or(0);
        if cap == 0 {
            continue;
        }
        scored.push((e, cap));
    }
    scored.sort_by(|a, b| b.1.cmp(&a.1));
    scored.into_iter().map(|(e, _)| e).collect()
}

/// Apply `RequestDock`: runs the same occupancy/condition fee formula as
/// Elixir's `facility_agent.ex:request_dock`. Deducts the fee from the
/// ship, adds it to the facility's credits, appends the ship entity to
/// `FacilityStorage.docked_ships`, and sets `ShipPosition.docked_at`.
/// Returns `true` if the dock succeeded (ship now docked), `false` if
/// it was rejected (no facility, capacity full, or ship broke).
pub fn apply_request_dock_typed(
    store: &mut AgentStore,
    ship: hecs::Entity,
    location: &str,
    preferred_facility_type: Option<&'static str>,
) -> bool {
    use sim_core::agents::{
        facility::{docking_fee, FacilityOperations, FacilityStorage, DOCKING_FEE_BASE},
        ship::ShipEconomy,
    };

    // Phase 18k: iterate dockable facilities in descending-capacity
    // order so the ship falls through to secondary/tertiary
    // facilities when the primary is full.
    //
    // Phase 19-tail: FIFO dock queue. If a ship is already queued at
    // some facility at this location, it must wait its turn — a
    // fresh arrival can't queue-jump just because its RequestDock
    // landed the same tick a slot opened. Three cases:
    //
    //   1. Ship already queued at facility F:
    //      - If F has capacity AND ship is at head → admit, pop queue.
    //      - Else → noop (stay queued).
    //
    //   2. Ship not queued anywhere:
    //      - If any candidate facility has `docked + queue_len < cap`
    //        → admit immediately (fast path, no queue contention).
    //      - Else → append to the least-queued candidate's queue.
    //
    //   3. No candidates at location → reject (same as before).
    let candidates = dockable_candidates_ordered(store, location, preferred_facility_type);
    if candidates.is_empty() {
        return false;
    }

    // Sweep stale entries from each candidate's queue before checking
    // heads. A ship that left this location (started a new transit,
    // got admin-destroyed, etc.) can otherwise wedge the queue head
    // forever — everyone behind it starves. We rebuild each queue by
    // retaining only entries whose ShipPosition still points at this
    // facility's location string.
    for &e in &candidates {
        prune_stale_dock_queue(store, e, location);
    }

    // Case 1: ship already queued at one of these candidates?
    for &e in &candidates {
        let queued_at_head = store
            .world
            .get::<&FacilityStorage>(e)
            .map(|s| s.dock_queue.first() == Some(&ship))
            .unwrap_or(false);
        let in_queue = store
            .world
            .get::<&FacilityStorage>(e)
            .map(|s| s.dock_queue.contains(&ship))
            .unwrap_or(false);
        if !in_queue {
            continue;
        }
        if !queued_at_head {
            // Still waiting behind someone else. No admit this tick.
            return false;
        }
        // We're at the head of this facility's queue. Admit if a slot
        // is available AND we can afford the fee.
        let (fee, has_space) = {
            let ops = match store.world.get::<&FacilityOperations>(e) {
                Ok(o) => o,
                Err(_) => continue,
            };
            let storage = match store.world.get::<&FacilityStorage>(e) {
                Ok(s) => s,
                Err(_) => continue,
            };
            let docked = storage.docked_ships.len() as u32;
            if docked >= ops.docking_capacity {
                (0, false)
            } else {
                (
                    docking_fee(
                        DOCKING_FEE_BASE,
                        docked,
                        ops.docking_capacity,
                        ops.condition,
                    ),
                    true,
                )
            }
        };
        if !has_space {
            return false;
        }
        let ship_ok = store
            .world
            .get::<&ShipEconomy>(ship)
            .map(|econ| econ.credits >= fee)
            .unwrap_or(false);
        if !ship_ok {
            // Broke head of line — evict so everyone behind can
            // proceed. The ship's Dock action sees Failure (we
            // returned `false` on a head-level reject) and its BT
            // replans, usually into a sell_cargo or refuel-elsewhere
            // flow that can recover credits. Without this eviction
            // the broke head stalls the queue forever.
            if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(e) {
                storage.dock_queue.retain(|&q| q != ship);
            }
            return false;
        }
        commit_dock(store, ship, e, fee);
        if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(e) {
            storage.dock_queue.retain(|&q| q != ship);
        }
        return true;
    }

    // Case 2a: not queued anywhere — try for an immediate slot.
    // `docked + queue_len < cap` captures "a ship can fit without
    // stepping on queue order" — if the queue is non-empty those
    // slots are implicitly reserved for the waiting ships.
    for &e in &candidates {
        let (fee, can_admit) = {
            let ops = match store.world.get::<&FacilityOperations>(e) {
                Ok(o) => o,
                Err(_) => continue,
            };
            let storage = match store.world.get::<&FacilityStorage>(e) {
                Ok(s) => s,
                Err(_) => continue,
            };
            let docked = storage.docked_ships.len() as u32;
            let queued = storage.dock_queue.len() as u32;
            if docked + queued >= ops.docking_capacity {
                (0, false)
            } else {
                (
                    docking_fee(
                        DOCKING_FEE_BASE,
                        docked,
                        ops.docking_capacity,
                        ops.condition,
                    ),
                    true,
                )
            }
        };
        if !can_admit {
            continue;
        }
        let ship_ok = store
            .world
            .get::<&ShipEconomy>(ship)
            .map(|econ| econ.credits >= fee)
            .unwrap_or(false);
        if !ship_ok {
            continue;
        }
        commit_dock(store, ship, e, fee);
        return true;
    }

    // Case 2b: all facilities are full or have queues that eat the
    // remaining capacity. Append to the shortest queue — balances
    // load across secondaries and minimises the waiting ship's wait.
    let mut shortest: Option<(hecs::Entity, usize)> = None;
    for &e in &candidates {
        let qlen = store
            .world
            .get::<&FacilityStorage>(e)
            .map(|s| s.dock_queue.len())
            .unwrap_or(usize::MAX);
        match shortest {
            None => shortest = Some((e, qlen)),
            Some((_, best)) if qlen < best => shortest = Some((e, qlen)),
            _ => {}
        }
    }
    if let Some((e, _)) = shortest {
        if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(e) {
            if !storage.dock_queue.contains(&ship) {
                storage.dock_queue.push(ship);
            }
        }
    }
    false
}

/// Remove stale entries from a facility's `dock_queue`. A queue entry
/// is "stale" if the ship entity no longer exists OR the ship's
/// current location_name doesn't match this facility's location (the
/// ship left without emitting anything that told us to drop it from
/// the queue — started a Travel, got admin-destroyed, etc.) OR the
/// ship is not actively attempting a dock right now
/// (`dock_attempt_start_tick.is_none()`).
///
/// That last case is load-bearing: when a ship's `ShipAction::Dock`
/// times out it clears `dock_attempt_start_tick` and returns Failure,
/// but nothing removes it from whatever queue it was in. The ship
/// usually stays at the same location (BT unwinds to a planner that
/// picks another local goal), so the location-match prune above can't
/// catch it — the stuck entry lives on at the head of the queue and
/// blocks every ship behind it. A 2026-04-24 diagnostic showed
/// `luna-base` with 0 ships docked and 2 queued against a capacity of
/// 25 — pure phantom entries from prior dock-timeouts.
///
/// Without this sweep a single vanished/idle ship can wedge the queue
/// head forever and every ship behind it starves.
pub fn prune_stale_dock_queue(store: &mut AgentStore, facility: hecs::Entity, location: &str) {
    use sim_core::agents::{
        facility::FacilityStorage,
        ship::{ShipEconomy, ShipPosition},
    };
    let queue_snapshot: Vec<hecs::Entity> = match store.world.get::<&FacilityStorage>(facility) {
        Ok(s) => s.dock_queue.clone(),
        Err(_) => return,
    };
    if queue_snapshot.is_empty() {
        return;
    }
    let mut keep: Vec<hecs::Entity> = Vec::with_capacity(queue_snapshot.len());
    for e in queue_snapshot {
        let still_here = store
            .world
            .get::<&ShipPosition>(e)
            .map(|p| p.location_name.as_deref() == Some(location))
            .unwrap_or(false);
        if !still_here {
            continue;
        }
        let still_trying = store
            .world
            .get::<&ShipEconomy>(e)
            .map(|econ| econ.dock_attempt_start_tick.is_some())
            .unwrap_or(false);
        if !still_trying {
            continue;
        }
        keep.push(e);
    }
    if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
        if storage.dock_queue.len() != keep.len() {
            storage.dock_queue = keep;
        }
    }
}

/// Shared dock-commit helper: debits fee, credits facility, pushes the
/// ship onto `docked_ships`, sets `ShipPosition.docked_at`. Caller is
/// responsible for any queue cleanup.
pub fn commit_dock(
    store: &mut AgentStore,
    ship: hecs::Entity,
    facility: hecs::Entity,
    fee: i64,
) {
    use sim_core::agents::{
        facility::{FacilityIdentity, FacilityOperations, FacilityStorage},
        ship::{ShipEconomy, ShipIdentity, ShipPosition},
    };
    // Bundle B: trade-pact / allied dock discount. Look up the
    // relation between the ship's faction and the facility's
    // owning faction once up front — same-faction + unfactioned
    // facilities both no-op into (1.0, 1.0).
    let ship_faction = store
        .world
        .get::<&ShipIdentity>(ship)
        .ok()
        .map(|i| i.faction_id.clone())
        .unwrap_or_default();
    let fac_faction = store
        .world
        .get::<&FacilityIdentity>(facility)
        .ok()
        .map(|i| i.faction_id.clone())
        .unwrap_or_default();
    let (fee_mult, burn_mult) =
        sim_core::agents::faction_relations::trade_pact_dock_modifier(
            &store.relations,
            &ship_faction,
            &fac_faction,
        );
    let discounted_fee = ((fee as f32) * fee_mult).round() as i64;
    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
        econ.credits -= discounted_fee;
    }
    // Bundle (G): split the fee — facility takes the remainder
    // after burn, the burned portion is a true sink (subtracted
    // from the ship, never added to any balance). Burn fraction
    // lives in WorldTuning (Bundle Q); Bundle B further scales it
    // by treaty state so allied docks burn less (or nothing).
    let burn_pct = sim_core::simulation::tuning::WorldTuning::current().dock_fee_burn_pct;
    let effective_burn_pct = burn_pct * burn_mult;
    let burned = (discounted_fee as f32 * effective_burn_pct).round() as i64;
    let to_facility = discounted_fee - burned;
    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(facility) {
        ops.credits += to_facility;
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
}

/// Apply `ReleaseDock`: remove the ship from the facility's docked_ships
/// list AND anchor the ship's position to the facility it's leaving.
///
/// The second part is the fix for the "ship teleports across the screen
/// when it undocks" bug. Ships don't publish a position while docked
/// (Godot hides them at that point), so on undock we need to place
/// them at the station's current coordinates — otherwise they
/// re-appear at whatever stale position the server last broadcast and
/// slide to the travel target from there. Mirroring the station's
/// position here gives Godot a clean "leaves the station" visual.
///
/// The ship's `docked_at` has already been cleared in-place by the
/// Undock action.
pub fn apply_release_dock(
    store: &mut AgentStore,
    ship: hecs::Entity,
    location: &str,
) {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{facility_offset_position, FacilityIdentity, FacilityStorage},
        ship::ShipPosition,
    };
    let facility = match primary_dock_at_location(store, location) {
        Some(e) => e,
        None => return,
    };
    if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
        storage.docked_ships.retain(|&e| e != ship);
    }

    // Resolve the facility's world position: body center + the same
    // stable offset facility_offset_position() uses. Computing it here
    // avoids a dependency on the snapshot-side facility position,
    // which isn't written until after the tick's apply phase.
    let facility_pos = {
        let id = match store.world.get::<&FacilityIdentity>(facility) {
            Ok(id) => id.clone(),
            Err(_) => return,
        };
        let body_center = store
            .world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter()
            .find(|(_, (bid, _))| bid.body_id == id.body_id)
            .map(|(_, (_, orbit))| orbit.universe_position());
        let Some(body_center) = body_center else {
            return;
        };
        facility_offset_position(body_center, &id.id)
    };

    if let Ok(mut pos) = store.world.get::<&mut ShipPosition>(ship) {
        pos.position = facility_pos;
    }
}

/// Admin: spawn a new ship hecs entity from an already-INSERTed DB row.
/// The HTTP handler wrote the DB row and handed us the db_id; we build
/// the matching hecs bundle here and index it.
pub fn admin_spawn_ship(
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

    let entity = store.world.spawn((
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
    ));
    store.world.insert(
        entity,
        (
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
pub fn admin_spawn_facility(
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
            starving_notified: false,
        },
        FacilityStorage {
            reserves: std::collections::HashMap::new(),
            docked_ships: vec![],
            pending_deliveries: vec![],
            dock_queue: vec![],
        },
        FacilityLifecycle::new(),
        sim_core::simulation::lod::AgentLod::new(),
    ));
    // Phase 18c: shipyards carry a ModuleStock. Attached separately so
    // non-shipyards don't pay the component cost.
    if payload.facility_type == "shipyard" {
        store
            .world
            .insert_one(entity, sim_core::agents::facility::ModuleStock::default())
            .ok();
    }
    // Phase 18e: all non-gate facilities get a default FacilityFitting.
    if payload.facility_type != "gate" {
        store
            .world
            .insert_one(
                entity,
                sim_core::agents::facility::FacilityFitting::new_default(),
            )
            .ok();
    }
    // Phase 19a: every facility (gates included) gets a crew complement
    // sized by type. Admin-spawned facilities pick the default the same
    // way seed-loaded ones do.
    store
        .world
        .insert_one(
            entity,
            sim_core::agents::facility::FacilityCrew::new_for_type(
                &payload.facility_type,
            ),
        )
        .ok();
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
    store: &mut AgentStore,
    id: &str,
    tick_now: u64,
    events: &mut Vec<serde_json::Value>,
    persist_tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::{
        facility::FacilityStorage,
        ship::{ShipCrew, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle, ShipPosition},
    };
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };
    // Capture retirement snapshot BEFORE despawn so the ledger has a
    // full last-known state. Phase 19g — kept even after the ships
    // row is deleted so the player can scroll back through
    // decommissioned ships in the details panel.
    let retirement_row = {
        let identity = store.world.get::<&ShipIdentity>(entity).ok();
        let position = store.world.get::<&ShipPosition>(entity).ok();
        let econ = store.world.get::<&ShipEconomy>(entity).ok();
        let crew = store.world.get::<&ShipCrew>(entity).ok();
        let fuel = store.world.get::<&ShipFuel>(entity).ok();
        let life = store.world.get::<&ShipLifecycle>(entity).ok();
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
    let db_id = store
        .world
        .get::<&ShipIdentity>(entity)
        .ok()
        .map(|i| i.db_id);
    // Pop from any facility's docked list AND dock queue first —
    // otherwise a despawned entity sits in a queue forever blocking
    // the head.
    for (_e, storage) in store.world.query_mut::<&mut FacilityStorage>() {
        storage.docked_ships.retain(|&e| e != entity);
        storage.dock_queue.retain(|&e| e != entity);
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
    let _ = store.world.despawn(entity);
    store.ship_by_id.remove(id);
    // Snapshot cache is purged by `update_from` on the next tick (diffs
    // live entity ids against the cache and removes missing keys).
    if let Some(db_id) = db_id {
        let _ = persist_tx.send(DbWrite::DeleteShip { db_id }).await;
    }
    if let Some(row) = retirement_row {
        let _ = persist_tx.send(DbWrite::RetireShip { row }).await;
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
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation, GateLink};
    use sim_core::agents::ship::ShipPosition;
    let Some(&entity) = store.facility_by_id.get(id) else {
        return;
    };
    // Snapshot everything we need BEFORE mutating anything, so we can
    // cascade cleanup without re-querying a half-deleted world.
    let db_id = store
        .world
        .get::<&FacilityIdentity>(entity)
        .ok()
        .map(|i| i.db_id);
    let location_name = store
        .world
        .get::<&FacilityLocation>(entity)
        .ok()
        .map(|l| l.location_name.clone());
    let paired_gate_id = store
        .world
        .get::<&GateLink>(entity)
        .ok()
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
        for (_e, (identity, pos)) in store
            .world
            .query_mut::<(&sim_core::agents::ship::ShipIdentity, &mut ShipPosition)>()
        {
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
            if let Ok(mut link) = store.world.get::<&mut GateLink>(paired_entity) {
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

    let _ = store.world.despawn(entity);
    store.facility_by_id.remove(id);
    if let Some(db_id) = db_id {
        let _ = persist_tx.send(DbWrite::DeleteFacility { db_id }).await;
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
fn admin_grant_ship_xp(
    store: &mut AgentStore,
    id: &str,
    amount: u32,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::ship::ShipProgression;
    let Some(&entity) = store.ship_by_id.get(id) else {
        return;
    };
    let Ok(mut prog) = store.world.get::<&mut ShipProgression>(entity) else {
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
    store: &mut AgentStore,
    ship: hecs::Entity,
    slot: sim_core::modules::Slot,
    slug: Option<&'static str>,
) -> RefitAttempt {
    use sim_core::agents::ship::{ShipCargo, ShipFitting, ShipFuel, ShipIdentity, ShipLifecycle};

    let class_name = match store.world.get::<&ShipIdentity>(ship) {
        Ok(id) => id.class.clone(),
        Err(_) => return RefitAttempt::NoShip,
    };
    let class_cfg = sim_core::simulation::config::ship_class(&class_name);
    let (base_cargo, base_speed) = match class_cfg {
        Some(c) => (c.cargo_capacity, c.speed_modifier),
        None => return RefitAttempt::NoClass,
    };

    let (prev_slug, new_derived) = {
        let mut fitting = match store.world.get::<&mut ShipFitting>(ship) {
            Ok(f) => f,
            Err(_) => return RefitAttempt::NoShip,
        };
        let prev = fitting.slot_slug(slot).map(|s| s.to_string());
        fitting.set(slot, slug);
        (prev, fitting.derived)
    };

    if let Ok(mut cargo) = store.world.get::<&mut ShipCargo>(ship) {
        cargo.capacity = ((base_cargo as f32) * new_derived.cargo_capacity_mult).round() as u32;
    }
    if let Ok(mut fuel) = store.world.get::<&mut ShipFuel>(ship) {
        fuel.speed_modifier = base_speed * new_derived.speed_mult;
    }
    if let Ok(mut life) = store.world.get::<&mut ShipLifecycle>(ship) {
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
    store: &mut AgentStore,
    ship: hecs::Entity,
    slot: sim_core::modules::Slot,
    slug: &'static str,
) -> Result<(hecs::Entity, String, i64), RefitAttempt> {
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

    let docked_at = match store.world.get::<&ShipPosition>(ship) {
        Ok(pos) => pos.docked_at,
        Err(_) => return Err(RefitAttempt::NoShip),
    };
    let Some(facility_entity) = docked_at else {
        return Err(RefitAttempt::NotDocked);
    };

    let (fid_str, is_yard) = match store.world.get::<&FacilityIdentity>(facility_entity) {
        Ok(id) => (id.id.clone(), id.facility_type == "shipyard"),
        Err(_) => return Err(RefitAttempt::NotShipyard),
    };
    if !is_yard {
        return Err(RefitAttempt::NotShipyard);
    }

    let in_stock = store
        .world
        .get::<&ModuleStock>(facility_entity)
        .map(|s| s.count(slug) > 0)
        .unwrap_or(false);
    if !in_stock {
        return Err(RefitAttempt::NoStock);
    }

    let has_credits = store
        .world
        .get::<&ShipEconomy>(ship)
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
    store: &mut AgentStore,
    ship: hecs::Entity,
    facility_entity: hecs::Entity,
    slug: &'static str,
    cost: i64,
) {
    use sim_core::agents::facility::{FacilityOperations, ModuleStock};
    use sim_core::agents::ship::ShipEconomy;

    if let Ok(mut stock) = store.world.get::<&mut ModuleStock>(facility_entity) {
        stock.take_one(slug);
    }
    if let Ok(mut econ) = store.world.get::<&mut ShipEconomy>(ship) {
        econ.credits = econ.credits.saturating_sub(cost);
    }
    if let Ok(mut ops) = store.world.get::<&mut FacilityOperations>(facility_entity) {
        ops.credits = ops.credits.saturating_add(cost);
        ops.dirty = true;
    }
}

/// Admin (Phase 18e): swap the module in one slot of a facility's
/// fitting. Validates slug is in the facility catalog + matches the
/// slot, then updates `FacilityFitting` in place — the next recipe
/// tick reads the new derived stats automatically.
fn admin_refit_facility(
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
        let Ok(mut fit) = store.world.get::<&mut FacilityFitting>(entity) else {
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
        let Ok((fac_entity, fac_id, cost)) = try_shipyard_refit(store, entity, slot, slug_s) else {
            return;
        };
        let prev_slug = match apply_fitting_swap(store, entity, slot, interned) {
            RefitAttempt::Applied { prev_slug } => prev_slug,
            _ => return,
        };
        commit_shipyard_refit(store, entity, fac_entity, slug_s, cost);
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
        let prev_slug = match apply_fitting_swap(store, entity, slot, interned) {
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

/// Per-tick dock-queue advance. Independent of whether any queued
/// ship is currently emitting `RequestDock` — walks every facility
/// with a non-empty queue, prunes phantom entries inline, then
/// admits as many heads as the available space + the ships'
/// credits allow.
///
/// Why this exists: the original admission path only fires from a
/// ship's own `ShipAction::Dock` emitting `RequestDock`. When a
/// queued ship gets LOD-gated out (sitting at divisor 5/10/20/50)
/// it stops emitting RequestDock for most ticks — so even if the
/// facility has free slots, nothing pulls the queue forward. A
/// 5-minute soak surfaced luna-base with 0 docked and 3 queued
/// and similar patterns at proxima-outpost + belt-outpost. Moving
/// admission into a cadenced sweep decouples it from the ship's
/// individual tick cadence.
///
/// Cheap: only iterates facilities whose `dock_queue` is non-empty,
/// and most ticks have zero or a handful of such facilities.
pub fn tick_dock_queue_advance(store: &mut AgentStore) {
    use sim_core::agents::{
        facility::{
            docking_fee, FacilityLocation, FacilityOperations, FacilityStorage,
            DOCKING_FEE_BASE,
        },
        ship::{ShipEconomy, ShipPosition},
    };

    let facilities: Vec<(hecs::Entity, String)> = store
        .world
        .query::<(&FacilityLocation, &FacilityStorage)>()
        .iter()
        .filter(|(_, (_, s))| !s.dock_queue.is_empty())
        .map(|(e, (loc, _))| (e, loc.location_name.clone()))
        .collect();

    for (facility, location) in facilities {
        // Inline prune: drop entries whose ship moved or whose
        // `dock_attempt_start_tick` was cleared (timed out / replanned).
        let pruned: Vec<hecs::Entity> = {
            let q = match store.world.get::<&FacilityStorage>(facility) {
                Ok(s) => s.dock_queue.clone(),
                Err(_) => continue,
            };
            q.into_iter()
                .filter(|&e| {
                    let still_here = store
                        .world
                        .get::<&ShipPosition>(e)
                        .map(|p| p.location_name.as_deref() == Some(location.as_str()))
                        .unwrap_or(false);
                    let still_trying = store
                        .world
                        .get::<&ShipEconomy>(e)
                        .map(|econ| econ.dock_attempt_start_tick.is_some())
                        .unwrap_or(false);
                    still_here && still_trying
                })
                .collect()
        };
        if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
            if storage.dock_queue.len() != pruned.len() {
                storage.dock_queue = pruned;
            }
        }

        // Admit as many heads as we can — bounded by available
        // slots and the head's ability to pay the fee. Broke head
        // evicts without advancing the docked count.
        loop {
            let head = match store.world.get::<&FacilityStorage>(facility) {
                Ok(s) => s.dock_queue.first().copied(),
                Err(_) => break,
            };
            let Some(ship) = head else { break };

            let (fee, has_space) = {
                let ops = match store.world.get::<&FacilityOperations>(facility) {
                    Ok(o) => o,
                    Err(_) => break,
                };
                let storage = match store.world.get::<&FacilityStorage>(facility) {
                    Ok(s) => s,
                    Err(_) => break,
                };
                let docked = storage.docked_ships.len() as u32;
                if docked >= ops.docking_capacity {
                    (0, false)
                } else {
                    (
                        docking_fee(
                            DOCKING_FEE_BASE,
                            docked,
                            ops.docking_capacity,
                            ops.condition,
                        ),
                        true,
                    )
                }
            };
            if !has_space {
                break;
            }
            let can_afford = store
                .world
                .get::<&ShipEconomy>(ship)
                .map(|econ| econ.credits >= fee)
                .unwrap_or(false);
            if !can_afford {
                // Evict broke head so everyone behind can proceed.
                // The ship's own Dock action sees queue absence next
                // tick, BT unwinds, planner routes to a sell_cargo /
                // refuel-elsewhere flow.
                if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
                    storage.dock_queue.retain(|&q| q != ship);
                }
                continue;
            }
            commit_dock(store, ship, facility, fee);
            if let Ok(mut storage) = store.world.get::<&mut FacilityStorage>(facility) {
                storage.dock_queue.retain(|&q| q != ship);
            }
        }
    }
}

/// Bundle A: admin override for the inter-faction relations matrix.
/// Sets standing / treaty (either or both) and emits a
/// `faction_standing_changed` event so the Godot ticker shows the
/// intervention. Read-only inputs — all invariants enforced inside
/// `FactionRelations::set_state`.
fn admin_set_relations(
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
pub fn apply_gate_jump(
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

    // Phase 19h: record the destination system on the ship's recent
    // memory so the explore planner will prefer ELSEWHERE next time
    // it picks a target — prevents gate yo-yo (A ↔ B on repeat).
    // Runs only on real crossings (src system != dst system).
    {
        use sim_core::agents::ship::{ShipMemory, RECENT_SYSTEMS_CAP};
        // Infer destination system from any facility at the paired
        // gate location. Cheap enough to do per jump (rare event).
        let dest_system: Option<String> = {
            use sim_core::agents::celestial_body::BodyIdentity;
            use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
            let body_id = store
                .world
                .query::<(&FacilityIdentity, &FacilityLocation)>()
                .iter()
                .find(|(_, (_, loc))| loc.location_name == dest_gate_location)
                .map(|(_, (id, _))| id.body_id.clone());
            body_id.and_then(|b| {
                store
                    .world
                    .query::<&BodyIdentity>()
                    .iter()
                    .find(|(_, id)| id.body_id == b)
                    .map(|(_, id)| id.system_name.clone())
            })
        };
        if let Some(dst_sys) = dest_system {
            if let Ok(mut mem) = store.world.get::<&mut ShipMemory>(ship) {
                // Push only on new-system entry (skip if already
                // the most recent entry — rare but defensive).
                if mem.recent_systems.back() != Some(&dst_sys) {
                    mem.recent_systems.push_back(dst_sys);
                    while mem.recent_systems.len() > RECENT_SYSTEMS_CAP {
                        mem.recent_systems.pop_front();
                    }
                }
            }
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
pub fn apply_facility_refuel(
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

/// Phase 19c-c/d: route a Construction delivery into the matching
/// site's progress. When progress hits 1.0, the site materialises
/// into a real facility at the same position and the site entity is
/// despawned. Fires `construction_progress` and, on finish,
/// `construction_completed` events.
pub fn apply_construction_delivery(
    store: &mut AgentStore,
    destination: &str,
    commodity: sim_core::economy::commodities::Commodity,
    quantity: u32,
    events: &mut Vec<serde_json::Value>,
) {
    use sim_core::agents::construction::{self, ConstructionSite};

    let site_entity = match construction::find_site(&store.world, destination, commodity) {
        Some(e) => e,
        None => {
            // No matching site — fall through to normal market drop
            // as a graceful degradation. Shouldn't normally happen
            // because the demand analyzer spawns the site before
            // posting the contract.
            if let Some(&market_entity) = store.market_at_location.get(destination) {
                if let Ok(mut pricing) = store
                    .world
                    .get::<&mut sim_core::agents::market::MarketPricing>(market_entity)
                {
                    *pricing.supply.entry(commodity).or_insert(0.0) += quantity as f32;
                }
            }
            return;
        }
    };

    // Snapshot the fields we need before mutating.
    let (site_id, site_name, completed_now, new_progress, facility_type, body_id,
         faction_id, position, site_location) = {
        if let Ok(mut site) = store.world.get::<&mut ConstructionSite>(site_entity) {
            let absorbed = quantity.min(site.remaining());
            site.progress_delivered = site.progress_delivered.saturating_add(absorbed);
            site.dirty = true;
            let progress = site.progress();
            let finished = progress >= 1.0 && !site.completed;
            if finished {
                site.completed = true;
            }
            (
                site.id.clone(),
                site.name.clone(),
                finished,
                progress,
                site.facility_type.clone(),
                site.body_id.clone(),
                site.faction_id.clone(),
                site.position,
                site.location_name.clone(),
            )
        } else {
            return;
        }
    };

    events.push(serde_json::json!({
        "kind": "construction_progress",
        "site_id": site_id,
        "progress": new_progress,
        "location": site_location,
    }));

    if completed_now {
        // Despawn the site, materialise a real facility at the same
        // position via the shared admin-spawn plumbing. DB INSERT for
        // the new facility is queued via `pending_materializations`
        // and drained asynchronously right after the apply phase; the
        // site row itself is deleted here so restart doesn't resurrect
        // a completed site.
        let _ = store.world.despawn(site_entity);
        materialize_facility(
            store,
            &site_id,
            &site_name,
            &facility_type,
            &body_id,
            &faction_id,
            &site_location,
            position,
            events,
        );
    }
}

/// Record each ship-originated command in the global debug trace
/// ring. Runs BEFORE `apply_ship_commands` on each pass so the
/// captured entry reflects what was requested, not the already-
/// applied outcome. Per-ship filtering happens on read — the ring is
/// Bundle (S): scan markets + facilities for structural warning
/// thresholds and emit `market_crisis` / `facility_starving` events
/// on crossings. Hysteresis via `crisis_notified` / `starving_notified`
/// flags prevents duplicate events each tick while the condition
/// persists, and recovery events (`market_recovered` /
/// `facility_recovered`) fire when state normalises again.
pub fn scan_crisis_events(world: &mut hecs::World, events: &mut Vec<serde_json::Value>) {
    use sim_core::agents::facility::{FacilityIdentity, FacilityOperations};
    use sim_core::agents::market::{MarketHistory, MarketIdentity};
    use sim_core::simulation::tuning::WorldTuning;

    let t = WorldTuning::current();

    for (_e, (id, hist)) in world.query_mut::<(&MarketIdentity, &mut MarketHistory)>() {
        for (&commodity, &shortage) in hist.shortage_ticks.clone().iter() {
            let was_notified = hist.crisis_notified.get(&commodity).copied().unwrap_or(false);
            if shortage >= t.market_crisis_shortage_ticks && !was_notified {
                events.push(serde_json::json!({
                    "kind": "market_crisis",
                    "market_id": id.id,
                    "location": id.facility_location,
                    "commodity": commodity.to_string(),
                    "shortage_ticks": shortage,
                }));
                hist.crisis_notified.insert(commodity, true);
            } else if shortage <= t.market_crisis_recovery_ticks && was_notified {
                events.push(serde_json::json!({
                    "kind": "market_recovered",
                    "market_id": id.id,
                    "location": id.facility_location,
                    "commodity": commodity.to_string(),
                }));
                hist.crisis_notified.insert(commodity, false);
            }
        }
    }

    for (_e, (id, ops)) in world.query_mut::<(&FacilityIdentity, &mut FacilityOperations)>() {
        if ops.condition < t.facility_starving_condition && !ops.starving_notified {
            events.push(serde_json::json!({
                "kind": "facility_starving",
                "facility_id": id.id,
                "condition": ops.condition,
            }));
            ops.starving_notified = true;
        } else if ops.condition > t.facility_starving_recovery && ops.starving_notified {
            events.push(serde_json::json!({
                "kind": "facility_recovered",
                "facility_id": id.id,
                "condition": ops.condition,
            }));
            ops.starving_notified = false;
        }
    }
}

/// Bundle A: run the relations tick on cadence, then emit a
/// `treaty_changed` event for every transition surfaced by the pure
/// core pass. Gated on `RELATIONS_TICK_INTERVAL_BASE * tick_mult` so
/// standing decay + treaty evaluations don't run every tick.
pub fn tick_relations_pass(
    store: &mut AgentStore,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_multiplier: u32,
) {
    use sim_core::agents::faction_relations::{
        tick_relations, RELATIONS_TICK_INTERVAL_BASE,
    };
    let interval = RELATIONS_TICK_INTERVAL_BASE * tick_multiplier.max(1) as u64;
    if interval == 0 || !tick.is_multiple_of(interval) {
        return;
    }
    let out = tick_relations(&mut store.relations, tick, tick_multiplier);
    for ch in out.treaty_changes {
        events.push(serde_json::json!({
            "kind": "treaty_changed",
            "a": ch.a,
            "b": ch.b,
            "from": ch.from.as_str(),
            "to": ch.to.as_str(),
            "standing": ch.standing,
        }));
    }
}

/// shared across all ships to keep the insertion path cheap (one
/// write-lock per tick, not per-ship).
fn record_command_trace(
    store: &AgentStore,
    commands: &CommandBuffer,
    tick: u64,
    trace: &std::sync::Arc<
        std::sync::RwLock<std::collections::VecDeque<crate::app_state::CommandTraceEntry>>,
    >,
) {
    use sim_core::agents::ship::ShipIdentity;
    if commands.is_empty() {
        return;
    }
    // Resolve ship Entity → string id up front, one query, then close
    // over the map while iterating commands.
    let mut id_by_entity: std::collections::HashMap<hecs::Entity, String> =
        std::collections::HashMap::new();
    for (e, id) in store.world.query::<&ShipIdentity>().iter() {
        id_by_entity.insert(e, id.id.clone());
    }
    let Ok(mut buf) = trace.write() else { return };
    for cmd in &commands.commands {
        let Some(ship) = cmd.actor_ship() else { continue };
        let Some(ship_id) = id_by_entity.get(&ship) else { continue };
        if buf.len() >= crate::app_state::COMMAND_TRACE_CAPACITY {
            buf.pop_front();
        }
        buf.push_back(crate::app_state::CommandTraceEntry {
            tick,
            ship_id: ship_id.clone(),
            kind: cmd.kind_label(),
            detail: cmd.trace_detail(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::admin_refit_ship;
    use sim_core::{
        agents::{
            facility::{
                FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations,
                FacilityStorage, ModuleStock,
            },
            ship::{
                ShipAI, ShipCargo, ShipEconomy, ShipFitting, ShipFuel, ShipIdentity,
                ShipLifecycle, ShipMemory, ShipPosition, ShipTransit,
            },
        },
        ai::personality::Personality,
        modules::Slot,
        simulation::spawner::AgentStore,
    };

    fn make_shipyard(store: &mut AgentStore, stock_slug: &str, stock_qty: u32) -> hecs::Entity {
        let entity = store.world.spawn((
            FacilityIdentity {
                db_id: 100,
                id: "facility-test-shipyard".into(),
                name: "Test Shipyard".into(),
                facility_type: "shipyard".into(),
                faction_id: "test".into(),
                body_id: "earth".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "earth-station".into(),
            },
            FacilityOperations {
                docking_capacity: 4,
                services: vec!["shipyard".into()],
                condition: 1.0,
                reputation: 50,
                credits: 0,
                dirty: false,
                starving_notified: false,
            },
            FacilityStorage::default(),
            FacilityLifecycle::new(),
            {
                let mut s = ModuleStock::default();
                s.add(stock_slug, stock_qty);
                s.dirty = false; // fresh
                s
            },
        ));
        store
            .facility_by_id
            .insert("facility-test-shipyard".into(), entity);
        entity
    }

    fn make_ship(
        store: &mut AgentStore,
        docked_at: Option<hecs::Entity>,
        credits: i64,
    ) -> hecs::Entity {
        let entity = store.world.spawn((
            ShipIdentity {
                db_id: 1,
                id: "ship-test".into(),
                name: "Test Ship".into(),
                class: "freighter".into(),
                faction_id: "test".into(),
                size: sim_core::simulation::config::ShipSize::Medium,
            },
            ShipPosition {
                location_name: Some("earth-station".into()),
                docked_at,
                system_id: "sol".into(),
                universe_offset: (0.0, 0.0),
                position: (1.0, 0.0),
            },
            ShipTransit { transit: None },
            ShipCargo {
                cargo: std::collections::HashMap::new(),
                capacity: 500,
                cargo_age: std::collections::HashMap::new(),
                cargo_origin: std::collections::HashMap::new(),
            },
            ShipFuel {
                fuel: 100.0,
                fuel_capacity: 100.0,
                fuel_consumption_rate: 0.05,
                speed_modifier: 1.0,
            },
            ShipEconomy {
                credits,
                efficiency: 1.0,
                active_contract_id: None,
                faction_reputation: std::collections::HashMap::new(),
                dock_dwell_start_tick: None,
                rest_start_tick: None,
                dock_attempt_start_tick: None,
            },
            ShipAI {
                personality: Personality::balanced_trader(),
                current_goal: "idle".into(),
                current_bt: None,
                current_goal_score: 0.0,
                last_plan_tick: 0,
            },
        ));
        store.world.insert(
            entity,
            (
                ShipMemory {
                    price_knowledge: Default::default(),
                    visited: vec![],
                    recent_systems: std::collections::VecDeque::new(),
                    route_performance: std::collections::HashMap::new(),
                },
                ShipLifecycle {
                    broke_strikes: 0,
                    hoard_strikes: 0,
                    idle_ticks: 0,
                    dirty: false,
                },
                ShipFitting::new_default(),
                sim_core::agents::ship::ShipProgression::new(),
            ),
        )
        .ok();
        store.ship_by_id.insert("ship-test".into(), entity);
        entity
    }

    #[test]
    fn shipyard_refit_happy_path_consumes_stock_and_credits() {
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut store, "engine_t2", 2);
        let ship = make_ship(&mut store, Some(yard), 50_000);
        let mut events: Vec<serde_json::Value> = Vec::new();

        admin_refit_ship(&mut store, "ship-test", Slot::Engine, Some("engine_t2"), true, &mut events);

        // Fitting now carries the new slug + rebaked speed_modifier.
        let fit = store.world.get::<&ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t2"));
        let fuel = store.world.get::<&ShipFuel>(ship).unwrap();
        assert!((fuel.speed_modifier - 1.15).abs() < 1e-5);

        // Shipyard stock decremented by 1; shipyard credits +8000.
        let stock = store.world.get::<&ModuleStock>(yard).unwrap();
        assert_eq!(stock.count("engine_t2"), 1);
        let ops = store.world.get::<&FacilityOperations>(yard).unwrap();
        assert_eq!(ops.credits, 8000);

        // Ship paid the cost.
        let econ = store.world.get::<&ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 50_000 - 8_000);

        // Refit event carries the shipyard context.
        let ev = events.iter().find(|v| v["kind"] == "ship_refitted").unwrap();
        assert_eq!(ev["via"], "shipyard");
        assert_eq!(ev["cost"], 8000);
    }

    #[test]
    fn shipyard_refit_rejects_when_not_docked() {
        let mut store = AgentStore::new();
        make_shipyard(&mut store, "cargo_bay_t2", 3);
        let ship = make_ship(&mut store, None, 50_000); // docked_at = None
        let mut events = Vec::new();

        admin_refit_ship(&mut store, "ship-test", Slot::CargoBay, Some("cargo_bay_t2"), true, &mut events);

        // No refit happened — slot is still the tier-1 default.
        let fit = store.world.get::<&ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::CargoBay), Some("cargo_bay_t1"));
        let econ = store.world.get::<&ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 50_000, "credits shouldn't move on rejected refit");
    }

    #[test]
    fn shipyard_refit_rejects_when_stock_empty() {
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut store, "engine_t2", 0);
        let _ship = make_ship(&mut store, Some(yard), 50_000);
        let mut events = Vec::new();

        admin_refit_ship(&mut store, "ship-test", Slot::Engine, Some("engine_t2"), true, &mut events);

        let ops = store.world.get::<&FacilityOperations>(yard).unwrap();
        assert_eq!(ops.credits, 0, "empty stock should not be saleable");
    }

    #[test]
    fn shipyard_refit_rejects_when_ship_broke() {
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut store, "reactor_t3", 1);
        let ship = make_ship(&mut store, Some(yard), 100); // well below 28k cost
        let mut events = Vec::new();

        admin_refit_ship(&mut store, "ship-test", Slot::Reactor, Some("reactor_t3"), true, &mut events);

        let fit = store.world.get::<&ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Reactor), Some("reactor_t1"));
        let stock = store.world.get::<&ModuleStock>(yard).unwrap();
        assert_eq!(stock.count("reactor_t3"), 1, "stock should not decrement");
    }

    #[test]
    fn admin_override_refit_bypasses_shipyard_checks() {
        // via_shipyard=false: pure admin swap, no cost, no dock requirement.
        let mut store = AgentStore::new();
        let ship = make_ship(&mut store, None, 0); // broke + not docked
        let mut events = Vec::new();

        admin_refit_ship(&mut store, "ship-test", Slot::Engine, Some("engine_t3"), false, &mut events);

        let fit = store.world.get::<&ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t3"));
        let econ = store.world.get::<&ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 0, "admin override does not charge");
    }
}
