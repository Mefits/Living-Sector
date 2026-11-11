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
use bevy_ecs::prelude::{Entity, World};
use sim_db::persistence::DbWrite;
use sim_core::{
    agents::{
        celestial_body::BodyOrbit,
        facility, faction, market, population,
        ship,
    },
    simulation::{
        commands::CommandBuffer,
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

mod admin;
mod apply;
mod transactions;
mod contract_funding;
mod colony;
mod drains;
mod persist;
mod publish;
pub use apply::{
    apply_construction_delivery, apply_gate_jump, apply_release_dock,
    apply_request_dock_typed, apply_ship_commands, commit_dock, dockable_candidates_ordered,
    primary_dock_at_location, primary_dock_at_location_typed, prune_stale_dock_queue,
    tick_dock_queue_advance,
};
use admin::{
    admin_grant_ship_xp, admin_market_supply_delta, admin_refit_facility, admin_remove_facility,
    admin_remove_ship, admin_set_relations,
};
pub use admin::{
    admin_refit_ship, admin_spawn_facility, admin_spawn_ship, apply_fitting_swap,
    commit_shipyard_refit, try_shipyard_refit, RefitAttempt,
};
use drains::{
    drain_pending_decommissions, drain_pending_materializations, drain_pending_respawns,
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
    mut world: World,
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
    phase_breakdown_us: Arc<std::sync::RwLock<crate::app_state::PhaseBreakdownUs>>,
    observers: Arc<std::sync::RwLock<Vec<Observer>>>,
    lod_counters: LodCounters,
    broadcast_tx: broadcast::Sender<Arc<ServerMsg>>,
    mut control_rx: mpsc::Receiver<ControlCommand>,
    persist_tx: mpsc::Sender<DbWrite>,
    pool: sqlx::SqlitePool,
    command_trace: std::sync::Arc<std::sync::RwLock<std::collections::VecDeque<crate::app_state::CommandTraceEntry>>>,
    #[cfg(test)] test_run: Option<(u64, Option<&str>)>,
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
    let mode = if std::env::var("LIVING_SECTOR_STRATEGY_MODE").as_deref() == Ok("execute") {
        sim_core::strategy::Mode::Execute
    } else { sim_core::strategy::Mode::Shadow };
    #[cfg(test)]
    let mode = if test_run.is_some() { sim_core::strategy::Mode::Execute } else { mode };
    world.insert_resource(sim_core::strategy::StrategyState { mode, ..Default::default() });
    world.insert_resource(sim_core::strategy::colony::Navigation(registry.clone()));
    if std::env::var("LIVING_SECTOR_GALAXY").as_deref()==Ok("1") {
        let saved:Option<String>=sqlx::query_scalar("SELECT value FROM simulation_state WHERE key='galaxy_director_v1'").fetch_optional(&pool).await.expect("load director checkpoint");
        let director=saved.map(|s|serde_json::from_str::<sim_core::strategy::director::Director>(&s).expect("valid director checkpoint")).unwrap_or_default();
        world.insert_resource(director);
    }
    sim_core::strategy::refresh(&mut world, &store.contracts, tick_counter.load(Ordering::Relaxed));
    // Prime all snapshot categories before the first timer tick. In the
    // small Genesis scenario the launcher pauses almost immediately, and a
    // restored tick counter can land between the 4/16-tick refreshes.
    // Without this, /api/report contains ships but 0 bodies/facilities/
    // markets/factions until the simulation resumes long enough.
    // Using tick 0 intentionally forces every cache cadence.
    snapshots.update_from(&mut world, &mut store, 0);
    log_sample_market(&mut world, &mut store, "initial");

    loop {
        #[cfg(test)]
        if let Some((end, _)) = test_run {
            if tick_counter.load(Ordering::Relaxed) >= end { break; }
            tokio::task::yield_now().await;
        } else {
            timer.tick().await;
        }
        #[cfg(not(test))]
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
                    admin_spawn_ship(&mut world, &mut store, &registry, payload, &mut events);
                }
                ControlCommand::AdminRemoveShip { id } => {
                    let tick_now = tick_counter.load(Ordering::Relaxed);
                    admin_remove_ship(
                        &mut world,
                        &mut store,
                        &id,
                        tick_now,
                        &mut events,
                        &persist_tx,
                    )
                    .await;
                }
                ControlCommand::AdminSpawnFacility(payload) => {
                    admin_spawn_facility(&mut world, &mut store, payload, &mut events);
                }
                ControlCommand::AdminRemoveFacility { id } => {
                    admin_remove_facility(&mut world, &mut store, &id, &mut events, &persist_tx).await;
                }
                ControlCommand::AdminMarketSupplyDelta { location, deltas } => {
                    admin_market_supply_delta(&mut world, &mut store, &location, &deltas, &mut events);
                }
                ControlCommand::AdminGrantShipXp { id, amount } => {
                    admin_grant_ship_xp(&mut world, &mut store, &id, amount, &mut events);
                }
                ControlCommand::AdminRefitFacility { id, slot, slug } => {
                    admin_refit_facility(&mut world, &mut store, &id, slot, slug.as_deref(), &mut events);
                }
                ControlCommand::AdminRefitShip { id, slot, slug, via_shipyard } => {
                    admin_refit_ship(
                        &mut world,
                        &mut store,
                        &id,
                        slot,
                        slug.as_deref(),
                        via_shipyard,
                        &mut events,
                    );
                }
                ControlCommand::PlayerSetResearchMandate {faction_id,mandate} => {
                    let tick=tick_counter.load(Ordering::Relaxed);
                    let res=sim_core::strategy::governance::set_mandate(
                        &mut world,&faction_id,mandate,tick);
                    events.push(serde_json::json!({
                        "kind":"player_research_mandate_applied",
                        "tick":tick,"faction_id":faction_id,
                        "status":if res.is_ok(){"applied"}else{"rejected"},
                        "reason":res.err(),
                    }));
                }
                ControlCommand::PlayerClearResearchMandate {faction_id} => {
                    let removed=sim_core::strategy::governance::clear_mandate(
                        &mut world,&faction_id);
                    events.push(serde_json::json!({
                        "kind":"player_research_mandate_cleared",
                        "faction_id":faction_id,"removed":removed,
                    }));
                }
                ControlCommand::PlayerSetEconomicMandate {faction_id,mandate} => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let res=sim_core::strategy::economic_mandate::set_mandate(
                        &mut world,&faction_id,mandate,now);
                    events.push(serde_json::json!({
                        "kind":"player_economic_mandate_applied",
                        "tick":now,"faction_id":faction_id,
                        "status":if res.is_ok(){"applied"}else{"rejected"},
                        "reason":res.err(),
                    }));
                }
                ControlCommand::PlayerClearEconomicMandate {faction_id} => {
                    let removed=sim_core::strategy::economic_mandate::clear_mandate(
                        &mut world,&faction_id);
                    events.push(serde_json::json!({
                        "kind":"player_economic_mandate_cleared",
                        "faction_id":faction_id,"removed":removed,
                    }));
                }
                ControlCommand::PlayerSetFactionCharter {faction_id,charter} => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let result=sim_core::strategy::charter::set_charter(
                        &mut world,&faction_id,charter,now);
                    events.push(serde_json::json!({
                        "kind":"player_faction_charter_applied",
                        "tick":now,"faction_id":faction_id,
                        "status":if result.is_ok(){"applied"}else{"rejected"},
                        "reason":result.err(),
                    }));
                }
                ControlCommand::PlayerDecideEconomicProposal {
                    faction_id,proposal_id,approve
                } => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let result=sim_core::strategy::economic_proposal::decide(
                        &mut world,&faction_id,&proposal_id,approve,now);
                    events.push(serde_json::json!({
                        "kind":"player_economic_proposal_reviewed",
                        "tick":now,"faction_id":faction_id,
                        "proposal_id":proposal_id,"approve":approve,
                        "status":if result.is_ok(){"applied"}else{"rejected"},
                        "reason":result.err(),
                    }));
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
                // Admin deletions also checkpoint while paused. Admission
                // failure retains the entire lifecycle queue for the next loop.
                if persist::has_lifecycle_writes(&world) {
                    let tick = tick_counter.load(Ordering::Relaxed);
                    contract_funding::refund_closed(&mut world, &mut store, &mut events, tick);
                    emit_persist_writes(&mut world, &mut store, tick, &persist_tx);
                }
                tokio::time::sleep(Duration::from_millis(50)).await;
                continue;
            }
        }

        let tick = tick_counter.fetch_add(1, Ordering::Relaxed) + 1;
        let t_start = std::time::Instant::now();

        // `phase!` records elapsed microseconds into a local accumulator
        // so we can write the per-tick breakdown out at end-of-tick. Last
        // tick wins — single-sample noisy at low n, fine for stress.
        let mut breakdown = crate::app_state::PhaseBreakdownUs::default();
        macro_rules! phase {
            ($field:ident, $body:block) => {{
                let t = std::time::Instant::now();
                $body;
                breakdown.$field = t.elapsed().as_micros() as u64;
            }};
        }

        // Tick phases
        phase!(bodies, {
            tick_bodies(&mut world, &mut store, tick_scale);
            // Station orbital state follows its parent body's position but
            // revolves around that body on a much slower independent clock.
            sim_core::agents::facility::tick_facility_orbits(&mut world, tick_scale);
        });
        phase!(bodies_regen, {
            if sim_core::simulation::tuning::WorldTuning::current()
                .regenerate_body_resources
            {
                sim_core::agents::celestial_body::tick_bodies_regen(
                    &mut world,
                    tick,
                    tick_scale,
                    tick_mult,
                );
            }
        });

        // LOD recompute — gated by interval so we're not rebuilding the
        // distance table every tick. Populations + facilities inherit
        // their body's current position; ships use their own.
        phase!(lod, {
            let lod_interval = sim_core::simulation::lod::LOD_RECOMPUTE_INTERVAL_BASE
                * tick_mult as u64;
            if lod_interval > 0 && tick % lod_interval == 0 {
                let stats = recompute_lod(&mut world, &mut store, &observers, tick);
                // Publish counters so the perf HUD can read tier distribution.
                lod_counters.0.store(stats.d1 as u64, Ordering::Relaxed);
                lod_counters.1.store(stats.d2 as u64, Ordering::Relaxed);
                lod_counters.2.store(stats.d5 as u64, Ordering::Relaxed);
                lod_counters.3.store(stats.d10 as u64, Ordering::Relaxed);
                lod_counters.4.store(stats.d20 as u64, Ordering::Relaxed);
                lod_counters.5.store(stats.d50 as u64, Ordering::Relaxed);
            }
        });
        // Snapshot gate_pairs before ship tick so the pathfinder has a
        // stable read during BT planning. AgentStore.gate_pairs is
        // updated when gates spawn/despawn (admin operations).
        let gate_pairs_snapshot = store.gate_pairs.clone();
        phase!(ships, {
            sim_core::strategy::orders::dispatch(&mut world, &mut store.contracts, &store.relations, &registry, tick, tick_mult);
            ship::tick_ships(
                &mut world,
                &registry,
                &gate_pairs_snapshot,
                &store.contracts,
                &store.relations,
                &mut commands,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        phase!(apply1, {
            record_command_trace(&mut world, &mut store, &commands, tick, &command_trace);
            apply_ship_commands(&mut world, &mut store, &mut commands, &mut events, tick);
        });
        // Per-tick queue advance: admits any queue heads that have
        // space and credits, independent of whether the ship at the
        // head is currently emitting RequestDock. Prevents LOD'd-out
        // ships from indefinitely holding queue slots they can't
        // actively poll for.
        phase!(dock_queue, { tick_dock_queue_advance(&mut world, &mut store); });
        let t_drains = std::time::Instant::now();
        drain_pending_materializations(&mut world, &mut store, &pool, &persist_tx, &mut events).await;
        drain_pending_decommissions(&mut world, &mut store, tick, &mut events, &persist_tx).await;
        drain_pending_respawns(&mut world, &mut store, &registry, tick, &mut events, &persist_tx, &pool).await;
        breakdown.drains = t_drains.elapsed().as_micros() as u64;
        phase!(facilities, {
            facility::tick_facilities_with_relations(
                &mut world,
                &mut store.contracts,
                &mut events,
                &store.relations,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        apply::tick_construction_labor(&mut world, &mut store, &mut events, tick, tick_mult);
        phase!(populations, {
            population::tick_populations(
                &mut world,
                &mut store.contracts,
                &mut events,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        phase!(markets, {
            market::tick_markets(&mut world, &mut commands, tick, tick_mult);
        });
        // Bundle (S): after markets + facilities tick, emit
        // structural-warning events on threshold crossings so
        // Godot can surface "5 markets in crisis" / "2 facilities
        // starving" without polling every panel. Hysteresis
        // windows inside `scan_crisis_events` prevent flapping.
        phase!(crisis, { scan_crisis_events(&mut world, &mut events); });
        // Market emits TransferCredits (spread revenue) — apply before clearing
        let t_apply2 = std::time::Instant::now();
        record_command_trace(&mut world, &mut store, &commands, tick, &command_trace);
        apply_ship_commands(&mut world, &mut store, &mut commands, &mut events, tick);
        drain_pending_materializations(&mut world, &mut store, &pool, &persist_tx, &mut events).await;
        drain_pending_decommissions(&mut world, &mut store, tick, &mut events, &persist_tx).await;
        drain_pending_respawns(&mut world, &mut store, &registry, tick, &mut events, &persist_tx, &pool).await;
        breakdown.apply2 = t_apply2.elapsed().as_micros() as u64;
        phase!(factions, {
            faction::tick_factions(
                &mut world,
                &mut store.contracts,
                &mut events,
                &mut store.system_control,
                &store.relations,
                tick,
                tick_mult,
            );
        });
        // T2/T3 paid core work is part of this real ECS tick,
        // and persists with the existing economic checkpoint.
        sim_core::strategy::progression::tick_native_upgrades(
            &mut world,&mut events,tick,tick_mult);
        colony::prepare_docks(&mut world, &mut store, &registry, &mut events);
        // Bundle A: inter-faction relations. Low-frequency — decay +
        // threshold-driven treaty transitions only need to run on
        // the relations interval. Emits `treaty_changed` events for
        // every state crossing (picked up by Godot event ticker).
        phase!(relations, {
            tick_relations_pass(&mut store, &mut events, tick, tick_mult);
        });
        commands.clear();

        // Publish per-phase breakdown for /api/health. Last tick wins.
        if let Ok(mut bd) = phase_breakdown_us.write() {
            *bd = breakdown;
        }

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
        snapshots.update_from(&mut world, &mut store, tick);
        let total_us = t_start.elapsed().as_micros() as u64;

        // Admit a complete economic frame before clearing dirty state.
        emit_persist_writes(&mut world, &mut store, tick, &persist_tx);

        #[cfg(test)]
        let stop_test = test_run.and_then(|(_, kind)| kind)
            .is_some_and(|kind| events.iter().any(|event| event["kind"] == kind));

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

        #[cfg(test)]
        if stop_test { break; }

        // Diagnostics
        if tick % (8 * 10) == 0 {
            info!(
                tick,
                "Engine: {} | tick_compute_us={} total_us={}",
                store.summary(),
                tick_compute_us,
                total_us,
            );
            log_sample_market(&mut world, &mut store, &format!("tick={tick}"));
            log_sample_ships(&mut world, &mut store, tick);
            log_contract_board(&store, tick);
            log_factions(&mut world, &mut store, tick);
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
pub fn run_contract_pump(world: &mut World, store: &mut AgentStore, passes: u32) {
    if !store.contracts.is_empty() {
        return;
    }
    for _ in 0..passes {
        sim_core::agents::facility::tick_post_contracts_with_relations(
            world,
            &mut store.contracts,
            &store.relations,
            0,
            1,
        );
        sim_core::agents::facility::tick_post_crew_missions(
            world,
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
            world,
            &mut store.contracts,
            &mut pump_events,
            0,
            1.0,
            1,
        );
        sim_core::agents::faction::tick_factions(
            world,
            &mut store.contracts,
            &mut pump_events,
            &mut store.system_control,
            &store.relations,
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
    world: &mut World,
    _store: &mut AgentStore,
    observers: &Arc<std::sync::RwLock<Vec<Observer>>>,
    tick: u64,
) -> sim_core::simulation::lod::LodStats {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{FacilityIdentity, FacilityLocation, FacilityOrbit,
                   facility_orbit_position, facility_orbit_initial_angle},
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

    let mut pos_by_entity: std::collections::HashMap<Entity, (f32, f32)> =
        std::collections::HashMap::new();

    // Ships — live positions.
    {
        let mut q = world.query::<(Entity, &AgentLod, &ShipPosition)>();
        for (e, _lod, pos) in q.iter(world) {
            pos_by_entity.insert(e, pos.position);
        }
    }

    // Facilities + populations — look up by their facility location →
    // body position. Build body position map once.
    let body_pos: std::collections::HashMap<String, (f32, f32)> = {
        let mut q = world.query::<(&BodyIdentity, &BodyOrbit)>();
        q.iter(world)
            .map(|(id, orbit)| (id.body_id.clone(), orbit.universe_position()))
            .collect()
    };

    // Facilities.
    let facility_info: Vec<(Entity, String, f32)> = {
        let mut q = world.query::<(Entity, &AgentLod, &FacilityIdentity,
            &FacilityLocation, Option<&FacilityOrbit>)>();
        q.iter(world).map(|(e, _lod, id, loc, orbit)| (
            e, id.body_id.clone(), orbit.map(|o| o.angle_degrees)
                .unwrap_or_else(|| facility_orbit_initial_angle(&loc.location_name))
        )).collect()
    };
    for (e, body_id, angle) in facility_info {
        if let Some(&center) = body_pos.get(&body_id) {
            pos_by_entity.insert(e, facility_orbit_position(center, angle));
        }
    }

    // Populations — use the facility's body position (same offset as
    // the parent facility isn't necessary; body center is plenty for
    // LOD bucketing).
    let pop_info: Vec<(Entity, String)> = {
        let mut q = world.query::<(Entity, &AgentLod, &PopIdentity)>();
        q.iter(world)
            .map(|(e, _lod, id)| (e, id.facility_location.clone()))
            .collect()
    };
    // location → body_id
    let loc_to_body: std::collections::HashMap<String, String> = {
        let mut q = world
            .query::<(&FacilityLocation, &FacilityIdentity)>();
        q.iter(world)
            .map(|(loc, fid)| (loc.location_name.clone(), fid.body_id.clone()))
            .collect()
    };
    for (e, loc) in pop_info {
        if let Some(body_id) = loc_to_body.get(&loc) {
            if let Some(&center) = body_pos.get(body_id) {
                pos_by_entity.insert(e, center);
            }
        }
    }

    let stats = tick_lod_recompute(world, &pos_by_entity, &obs_snapshot, tick);
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

pub fn tick_bodies(world: &mut World, _store: &mut AgentStore, tick_scale: f32) {
    let mut q = world.query::<&mut BodyOrbit>();
    for mut orbit in q.iter_mut(world) {
        orbit.advance(tick_scale);
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
pub fn scan_crisis_events(world: &mut World, events: &mut Vec<serde_json::Value>) {
    use sim_core::agents::facility::{FacilityIdentity, FacilityOperations};
    use sim_core::agents::market::{MarketHistory, MarketIdentity};
    use sim_core::simulation::tuning::WorldTuning;

    let t = WorldTuning::current();

    {
        let mut q = world.query::<(&MarketIdentity, &mut MarketHistory)>();
        for (id, mut hist) in q.iter_mut(world) {
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
    }

    {
        let mut q = world.query::<(&FacilityIdentity, &mut FacilityOperations)>();
        for (id, mut ops) in q.iter_mut(world) {
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
    world: &mut World,
    _store: &mut AgentStore,
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
    let mut id_by_entity: std::collections::HashMap<Entity, String> =
        std::collections::HashMap::new();
    {
        let mut q = world.query::<(Entity, &ShipIdentity)>();
        for (e, id) in q.iter(world) {
            id_by_entity.insert(e, id.id.clone());
        }
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
    use bevy_ecs::prelude::{Entity, World};
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

    fn make_shipyard(world: &mut World, store: &mut AgentStore, stock_slug: &str, stock_qty: u32) -> Entity {
        let entity = world.spawn((
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
        )).id();
        store
            .facility_by_id
            .insert("facility-test-shipyard".into(), entity);
        entity
    }

    fn make_ship(
        world: &mut World,
        store: &mut AgentStore,
        docked_at: Option<Entity>,
        credits: i64,
    ) -> Entity {
        let entity = world.spawn((
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
                transaction: Default::default(),
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
        )).id();
        world.entity_mut(entity).insert((
            ShipMemory {
                price_knowledge: Default::default(),
                visited: vec![],
                recent_systems: std::collections::VecDeque::new(),
                route_performance: std::collections::HashMap::new(),
                contract_rejections: Default::default(),
            },
            ShipLifecycle {
                broke_strikes: 0,
                hoard_strikes: 0,
                idle_ticks: 0,
                dirty: false,
            },
            ShipFitting::new_default(),
            sim_core::agents::ship::ShipProgression::new(),
        ));
        store.ship_by_id.insert("ship-test".into(), entity);
        entity
    }

    #[test]
    fn shipyard_refit_happy_path_consumes_stock_and_credits() {
        let mut world = World::new();
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut world, &mut store, "engine_t2", 2);
        let ship = make_ship(&mut world, &mut store, Some(yard), 50_000);
        let mut events: Vec<serde_json::Value> = Vec::new();

        admin_refit_ship(&mut world, &mut store, "ship-test", Slot::Engine, Some("engine_t2"), true, &mut events);

        // Fitting now carries the new slug + rebaked speed_modifier.
        let fit = world.get::<ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t2"));
        let fuel = world.get::<ShipFuel>(ship).unwrap();
        assert!((fuel.speed_modifier - 1.15).abs() < 1e-5);

        // Shipyard stock decremented by 1; shipyard credits +8000.
        let stock = world.get::<ModuleStock>(yard).unwrap();
        assert_eq!(stock.count("engine_t2"), 1);
        let ops = world.get::<FacilityOperations>(yard).unwrap();
        assert_eq!(ops.credits, 8000);

        // Ship paid the cost.
        let econ = world.get::<ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 50_000 - 8_000);

        // Refit event carries the shipyard context.
        let ev = events.iter().find(|v| v["kind"] == "ship_refitted").unwrap();
        assert_eq!(ev["via"], "shipyard");
        assert_eq!(ev["cost"], 8000);
    }

    #[test]
    fn shipyard_refit_rejects_when_not_docked() {
        let mut world = World::new();
        let mut store = AgentStore::new();
        make_shipyard(&mut world, &mut store, "cargo_bay_t2", 3);
        let ship = make_ship(&mut world, &mut store, None, 50_000); // docked_at = None
        let mut events = Vec::new();

        admin_refit_ship(&mut world, &mut store, "ship-test", Slot::CargoBay, Some("cargo_bay_t2"), true, &mut events);

        // No refit happened — slot is still the tier-1 default.
        let fit = world.get::<ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::CargoBay), Some("cargo_bay_t1"));
        let econ = world.get::<ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 50_000, "credits shouldn't move on rejected refit");
    }

    #[test]
    fn shipyard_refit_rejects_when_stock_empty() {
        let mut world = World::new();
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut world, &mut store, "engine_t2", 0);
        let _ship = make_ship(&mut world, &mut store, Some(yard), 50_000);
        let mut events = Vec::new();

        admin_refit_ship(&mut world, &mut store, "ship-test", Slot::Engine, Some("engine_t2"), true, &mut events);

        let ops = world.get::<FacilityOperations>(yard).unwrap();
        assert_eq!(ops.credits, 0, "empty stock should not be saleable");
    }

    #[test]
    fn shipyard_refit_rejects_when_ship_broke() {
        let mut world = World::new();
        let mut store = AgentStore::new();
        let yard = make_shipyard(&mut world, &mut store, "reactor_t3", 1);
        let ship = make_ship(&mut world, &mut store, Some(yard), 100); // well below 28k cost
        let mut events = Vec::new();

        admin_refit_ship(&mut world, &mut store, "ship-test", Slot::Reactor, Some("reactor_t3"), true, &mut events);

        let fit = world.get::<ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Reactor), Some("reactor_t1"));
        let stock = world.get::<ModuleStock>(yard).unwrap();
        assert_eq!(stock.count("reactor_t3"), 1, "stock should not decrement");
    }

    #[test]
    fn admin_override_refit_bypasses_shipyard_checks() {
        // via_shipyard=false: pure admin swap, no cost, no dock requirement.
        let mut world = World::new();
        let mut store = AgentStore::new();
        let ship = make_ship(&mut world, &mut store, None, 0); // broke + not docked
        let mut events = Vec::new();

        admin_refit_ship(&mut world, &mut store, "ship-test", Slot::Engine, Some("engine_t3"), false, &mut events);

        let fit = world.get::<ShipFitting>(ship).unwrap();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t3"));
        let econ = world.get::<ShipEconomy>(ship).unwrap();
        assert_eq!(econ.credits, 0, "admin override does not charge");
    }
}

#[cfg(test)]
mod colony_test;
