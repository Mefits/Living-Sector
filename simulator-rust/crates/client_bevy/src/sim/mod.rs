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

/// One-shot request for the top-bar admin spawn button.
/// `Some(params)` carries the picker selections from the Add Ship
/// dialog; `None` means "use default preset" (quick freighter at
/// earth-station). Consumed by [`process_spawn_ship`] which builds
/// an `AdminSpawnShipPayload`, then calls
/// `sim_server::engine::admin_spawn_ship`. Paired with the
/// render-side `reconcile_new_ships` system which surfaces the new
/// hecs entity as a Bevy render entity.
#[derive(Resource, Default)]
pub struct SpawnShipRequest(pub Option<SpawnShipParams>);

/// Picker selections from the Add Ship dialog. `name` empty means
/// "let process_spawn_ship generate one" so users can leave it
/// blank.
#[derive(Clone, Debug)]
pub struct SpawnShipParams {
    pub class: String,
    pub faction_id: String,
    pub location_name: String,
    pub credits: i64,
    pub name: String,
}

/// One-shot facility-spawn request emitted by the Add Facility
/// dialog. Consumed by [`process_spawn_facility`] which derives the
/// agent_id + location and calls
/// `sim_server::engine::admin_spawn_facility`. Skips DB INSERT —
/// embedded ships and facilities aren't persisted yet (no worker).
#[derive(Resource, Default)]
pub struct SpawnFacilityRequest(pub Option<SpawnFacilityParams>);

#[derive(Clone, Debug)]
pub struct SpawnFacilityParams {
    pub name: String,
    pub facility_type: String,
    pub body_id: String,
    pub faction_id: String,
    pub docking_capacity: u32,
    pub credits: i64,
}

/// One-shot ship-deletion request (right-click → Destroy, or future
/// confirmation flows). Carries the agent_id; consumed by
/// [`process_delete_ship`]. Mirrors the inline cleanup the
/// ship-details Delete button does today.
#[derive(Resource, Default)]
pub struct DeleteShipRequest(pub Option<String>);

/// Same for facilities. The cleanup mirrors
/// `sim_server::engine::admin_remove_facility` (sync subset — no
/// persist_tx, no async): kick docked ships, cancel contracts where
/// this facility is requestor, despawn, drop the index entry.
#[derive(Resource, Default)]
pub struct DeleteFacilityRequest(pub Option<String>);

/// Rolling tick-compute timing window — `tick_sim` measures wall
/// time and pushes microseconds into here so the perf overlay can
/// surface p50/p99. Mirrors `sim_server.perf.tick_compute_*` so
/// the embedded client has the same diagnostic budget visibility.
#[derive(Resource, Default)]
pub struct TickPerf {
    pub samples: std::collections::VecDeque<u64>,
    pub p50_us: u64,
    pub p99_us: u64,
}

/// Sample-window length for [`TickPerf`]. 60 ticks at 8 tps =
/// 7.5 s — long enough to smooth single-tick spikes, short
/// enough that recent regressions surface quickly.
pub const TICK_PERF_WINDOW: usize = 60;

/// Per-phase microsecond breakdown of the most recent embedded
/// tick. Updated in-place each `tick_sim` invocation so the perf
/// panel can read which sub-phase is dominant when the overall
/// budget is bad. Mirrors what a flame-graph would tell us
/// without pulling a profiler in.
#[derive(Resource, Default, Clone, Copy)]
pub struct PhasePerf {
    pub bodies_us: u64,
    pub ships_us: u64,
    pub apply1_us: u64,
    pub drains_us: u64,
    pub dock_queue_us: u64,
    pub facilities_us: u64,
    pub populations_us: u64,
    pub markets_us: u64,
    pub apply2_us: u64,
    pub regen_us: u64,
    pub crisis_us: u64,
    pub factions_us: u64,
    pub relations_us: u64,
    pub events_log_us: u64,
}

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
            .init_resource::<SpawnFacilityRequest>()
            .init_resource::<DeleteShipRequest>()
            .init_resource::<DeleteFacilityRequest>()
            .init_resource::<TickPerf>()
            .init_resource::<PhasePerf>()
            .init_resource::<SelectedSavePath>()
            // Discrete scenes: world load happens on `OnEnter(InGame)`
            // (when the user clicks Start or picks a save) and the
            // store is reset on `OnExit(InGame)` (Return to Main
            // Menu). The MainMenu state has an empty sim store —
            // different sessions can boot from different DBs cleanly
            // without a load-and-hide step.
            .add_systems(
                bevy::prelude::OnEnter(crate::AppState::InGame),
                load_world,
            )
            .add_systems(
                bevy::prelude::OnExit(crate::AppState::InGame),
                teardown_world,
            )
            .add_systems(
                FixedUpdate,
                tick_sim.run_if(bevy::prelude::in_state(crate::AppState::InGame)),
            )
            .add_systems(
                Update,
                (
                    process_save_as,
                    process_spawn_ship,
                    process_spawn_facility,
                    process_delete_ship,
                    process_delete_facility,
                ),
            );
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
            // Boot paused — MainMenu's Start button flips this true
            // on transition to InGame. Prevents one tick of phantom
            // motion before the user actually starts the game.
            running: false,
            tick_mult: 1,
            world_seed: 0,
        }
    }
}

/// Resource: which DB the next `OnEnter(InGame)` should load from.
/// `None` = default `sim.db` next to the executable. Set by the
/// save-list panel's Load button before transitioning to InGame.
/// Cleared on `OnExit(InGame)` so subsequent Start clicks don't
/// silently reuse the previous selection.
#[derive(Resource, Default)]
pub struct SelectedSavePath(pub Option<std::path::PathBuf>);

/// `OnEnter(InGame)` system: init DB, seed if empty, load agents
/// into the Sim Resource. Uses a one-shot tokio runtime — we need
/// it for sqlx's async API during this load sequence only. The
/// runtime gets dropped after the load; the persistence worker
/// (when it lands) will hold its own long-lived runtime.
///
/// Reads `SelectedSavePath` to choose between the default sim.db
/// and a user-picked save snapshot — letting different sessions
/// boot from different worlds without restart. The save-list's
/// Load button writes this resource before transitioning state.
pub(crate) fn load_world(
    mut sim: ResMut<Sim>,
    mut retirements: ResMut<Retirements>,
    selected: Res<SelectedSavePath>,
) {
    let db_path = match &selected.0 {
        Some(p) => p.to_string_lossy().to_string(),
        None => resolve_db_path(),
    };
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

/// `OnExit(InGame)` system: blow away the in-memory world. Mirrors
/// the boot-state Sim::default + empty Retirements + drained
/// EventsLog so the next `OnEnter(InGame)` (Start / Load Game)
/// builds a fresh world from whatever DB it picks. Also clears
/// `SelectedSavePath` so the next plain Start defaults back to
/// sim.db rather than silently re-using the picked save.
fn teardown_world(
    mut sim: ResMut<Sim>,
    mut retirements: ResMut<Retirements>,
    mut events: ResMut<EventsLog>,
    mut selected: ResMut<SelectedSavePath>,
) {
    let summary = sim.store.summary();
    info!(
        "client_bevy: tearing down world ({} ships, {} facilities, {} bodies)",
        summary.ships, summary.facilities, summary.bodies
    );
    *sim = Sim::default();
    retirements.0.clear();
    events.0.clear();
    selected.0 = None;
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
pub(crate) fn tick_sim(
    mut sim: ResMut<Sim>,
    mut events_log: ResMut<EventsLog>,
    mut perf: ResMut<TickPerf>,
    mut phase_perf: ResMut<PhasePerf>,
    mut retirements: ResMut<Retirements>,
) {
    if !sim.running {
        return;
    }
    let t_start = std::time::Instant::now();

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
        // Per-phase timing so the perf panel can identify the
        // dominant cost when the budget is bad. Microsecond
        // resolution. Each `time!` block records into a local var;
        // we copy to the PhasePerf resource at end-of-tick (last
        // tick wins for tick_mult > 1, which is fine for relative
        // diagnosis).
        let t_bodies: u64;
        let t_ships: u64;
        let t_apply1: u64;
        let t_drains: u64;
        let t_dock_queue: u64;
        let t_facilities: u64;
        let t_pops: u64;
        let t_markets: u64;
        let t_apply2: u64;
        let t_regen: u64;
        let t_crisis: u64;
        let t_factions: u64;
        let t_relations: u64;

        macro_rules! time {
            ($acc:ident, $body:block) => {{
                let t = std::time::Instant::now();
                $body;
                $acc = t.elapsed().as_micros() as u64;
            }};
        }

        // Bodies first so anything reading orbit positions later
        // this tick sees today's orbit.
        time!(t_bodies, {
            sim_server::engine::tick_bodies(store, tick_scale);
        });

        // Ships — AI decides + transits advance + commands get
        // emitted into the CommandBuffer.
        time!(t_ships, {
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
        });
        // First apply pass — docks, gate jumps, contract deliveries,
        // cargo buys/sells, credit transfers.
        time!(t_apply1, {
            sim_server::engine::apply_ship_commands(
                store,
                &mut commands,
                &mut events,
                tick,
            );
        });
        // Drain organic retirements (3-strike ship deaths) +
        // adaptive respawns.
        time!(t_drains, {
            drain_decommissions(store, &mut retirements.0, &mut events, tick);
            drain_respawns(store, registry, &mut events, tick);
        });
        time!(t_dock_queue, {
            sim_server::engine::tick_dock_queue_advance(store);
        });

        // Facilities: recipes, condition degrade, crew food draw,
        // restock from local market, autonomous contract posting,
        // abandonment countdown, level-up on XP.
        time!(t_facilities, {
            facility::tick_facilities(
                &mut store.world,
                &mut store.contracts,
                &mut events,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        // Populations: food consumption, production, sentiment,
        // passenger-contract posting, migration pressure.
        time!(t_pops, {
            population::tick_populations(
                &mut store.world,
                &mut store.contracts,
                &mut events,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        // Markets: the 8-phase pricing engine.
        time!(t_markets, {
            market::tick_markets(&mut store.world, &mut commands, tick, tick_mult);
        });

        // Second apply pass — market TransferCredits + anything the
        // facility/pop phases emitted.
        time!(t_apply2, {
            sim_server::engine::apply_ship_commands(
                store,
                &mut commands,
                &mut events,
                tick,
            );
        });

        time!(t_regen, {
            celestial_body::tick_bodies_regen(
                &mut store.world,
                tick,
                tick_scale,
                tick_mult,
            );
        });
        time!(t_crisis, {
            sim_server::engine::scan_crisis_events(&mut store.world, &mut events);
        });
        time!(t_factions, {
            faction::tick_factions(
                &mut store.world,
                &mut store.contracts,
                &mut events,
                tick,
                tick_mult,
            );
        });
        time!(t_relations, {
            sim_server::engine::tick_relations_pass(store, &mut events, tick, tick_mult);
        });

        // Last-tick wins; over tick_mult > 1 the relative
        // proportions are what matter, not absolute totals.
        *phase_perf = PhasePerf {
            bodies_us: t_bodies,
            ships_us: t_ships,
            apply1_us: t_apply1,
            drains_us: t_drains,
            dock_queue_us: t_dock_queue,
            facilities_us: t_facilities,
            populations_us: t_pops,
            markets_us: t_markets,
            apply2_us: t_apply2,
            regen_us: t_regen,
            crisis_us: t_crisis,
            factions_us: t_factions,
            relations_us: t_relations,
            events_log_us: 0, // populated below
        };

        // Drop leftover commands. In the full run_tick_loop another
        // apply pass picks them up after faction phase; in the
        // embedded tick we're fine dropping — they're mostly
        // supply-delta housekeeping that will re-emit next tick.
        commands.clear();

        // Drain the per-tick events into the ring log so the events
        // ticker panel can render them. Bounded capacity — at tick
        // boundaries we pop-front until we're at the cap.
        let t_evlog = std::time::Instant::now();
        for ev in events.drain(..) {
            if events_log.0.len() >= EVENTS_CAP {
                events_log.0.pop_front();
            }
            events_log.0.push_back((tick, ev));
        }
        phase_perf.events_log_us = t_evlog.elapsed().as_micros() as u64;
    }

    // Tick-compute window — record this fixed-update's wall-time
    // budget into the perf ring. `tick_sim` runs `tick_mult`
    // sub-ticks per FixedUpdate, so this is the FixedUpdate-level
    // budget (matches what the user actually sees against the
    // 125 ms FixedUpdate cadence at 1×).
    let elapsed_us = t_start.elapsed().as_micros() as u64;
    if perf.samples.len() >= TICK_PERF_WINDOW {
        perf.samples.pop_front();
    }
    perf.samples.push_back(elapsed_us);
    if !perf.samples.is_empty() {
        let mut sorted: Vec<u64> = perf.samples.iter().copied().collect();
        sorted.sort_unstable();
        perf.p50_us = sorted[sorted.len() / 2];
        let p99_idx = (sorted.len() as f32 * 0.99).ceil() as usize;
        perf.p99_us = sorted[p99_idx.saturating_sub(1).min(sorted.len() - 1)];
    }
}

/// Sync version of `sim_server::drain_pending_decommissions` for the
/// embedded client. Drains [`AgentStore::pending_decommissions`],
/// builds a retirement-ledger row for each, drops the ship's
/// contract holdings, removes the entity from facility docked +
/// queue lists, despawns from hecs, removes from `ship_by_id`, and
/// emits a `ship_decommissioned` event with the retirement reason.
/// Respawns: the embedded client doesn't auto-spawn replacements
/// yet, so we clear `pending_respawns` here to keep the queue from
/// growing without a consumer.
///
/// All in-memory work — no DB writes, no async. The retirement row
/// is pushed onto the live [`Retirements`] resource so the panel
/// grows during play instead of staying frozen at the load-time
/// snapshot.
fn drain_decommissions(
    store: &mut AgentStore,
    retirements_log: &mut Vec<RetirementRow>,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) {
    use sim_core::agents::{
        facility::FacilityStorage,
        ship::{ShipCrew, ShipEconomy, ShipFuel, ShipIdentity, ShipLifecycle, ShipPosition},
    };

    let pending: Vec<sim_core::simulation::spawner::PendingDecommission> =
        std::mem::take(&mut store.pending_decommissions);
    if pending.is_empty() {
        return;
    }
    for req in pending {
        let entity = req.entity;
        // Snapshot ship state for the retirement row before despawn.
        let id_clone = match store.world.get::<&ShipIdentity>(entity) {
            Ok(id) => id.id.clone(),
            Err(_) => continue,
        };
        let row = {
            let identity = store.world.get::<&ShipIdentity>(entity).ok();
            let position = store.world.get::<&ShipPosition>(entity).ok();
            let econ = store.world.get::<&ShipEconomy>(entity).ok();
            let crew = store.world.get::<&ShipCrew>(entity).ok();
            let fuel = store.world.get::<&ShipFuel>(entity).ok();
            let life = store.world.get::<&ShipLifecycle>(entity).ok();
            identity.map(|id_ref| RetirementRow {
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
                retired_at_tick: tick as i64,
                reason: req.reason.to_string(),
            })
        };

        // Pop from any facility's docked + queue lists so a despawned
        // entity doesn't wedge a queue head forever.
        for (_e, storage) in store.world.query_mut::<&mut FacilityStorage>() {
            storage.docked_ships.retain(|&e| e != entity);
            storage.dock_queue.retain(|&e| e != entity);
        }
        // Release contract holdings: Accepted → Posted (re-postable),
        // PickedUp → Expired (cargo gone with the ship).
        let drop = store.contracts.drop_ship_holdings(&id_clone);
        for cid in &drop.released {
            events.push(serde_json::json!({
                "kind": "contract_released",
                "id": cid,
                "reason": "ship_destroyed",
                "ship_id": id_clone.clone(),
            }));
        }
        for cid in &drop.cancelled {
            events.push(serde_json::json!({
                "kind": "contract_expired",
                "id": cid,
                "reason": "ship_destroyed_with_cargo",
                "ship_id": id_clone.clone(),
            }));
        }
        let _ = store.world.despawn(entity);
        store.ship_by_id.remove(&id_clone);

        events.push(serde_json::json!({
            "kind": "ship_decommissioned",
            "id": id_clone,
            "reason": req.reason.to_string(),
        }));
        if let Some(row) = row {
            // Newest-first match the panel's default display order.
            retirements_log.insert(0, row);
        }
    }

}

/// Sync version of `sim_server::drain_pending_respawns`. Drains the
/// `PendingRespawn` queue at end-of-tick, spawning replacement ships
/// for any entry whose `spawn_at_tick` has arrived. Embedded version
/// resolves the spawn location's body position from the in-memory
/// hecs world (no DB JOIN). Picks class deterministically from
/// (tick, prefer_faction) hash; faction is 70%-prefer the lost
/// ship's faction, else the underdog (fewest active ships).
fn drain_respawns(
    store: &mut AgentStore,
    registry: &WorldRegistry,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) {
    use sim_core::agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{FacilityIdentity, FacilityLocation, FacilityOperations},
        ship::ShipIdentity,
    };
    use sim_core::simulation::spawner::PendingRespawn;

    // Partition the queue into "fire now" + "still waiting" — keep
    // the not-yet-due entries for later ticks.
    let pending: Vec<PendingRespawn> = std::mem::take(&mut store.pending_respawns);
    let (due, later): (Vec<_>, Vec<_>) =
        pending.into_iter().partition(|r| r.spawn_at_tick <= tick);
    store.pending_respawns = later;
    if due.is_empty() {
        return;
    }

    const CANDIDATE_CLASSES: &[&str] =
        &["courier", "freighter", "hauler", "tanker", "miner"];

    for req in due {
        // Deterministic seed: hash tick + faction so multiple
        // retirements on the same tick still produce different picks.
        let seed = tick
            .wrapping_mul(6364136223846793005)
            .wrapping_add(
                req.prefer_faction
                    .as_deref()
                    .map(|s| s.bytes().map(|b| b as u64).sum())
                    .unwrap_or(0),
            );
        let class = CANDIDATE_CLASSES[(seed as usize) % CANDIDATE_CLASSES.len()];

        // Faction: 70% prefer the retired ship's faction, else the
        // faction with the fewest active ships ("underdog
        // pressure").
        let use_hint = (seed >> 8) % 10 < 7;
        let faction_id = if use_hint && req.prefer_faction.is_some() {
            req.prefer_faction.clone().unwrap()
        } else {
            let mut counts: std::collections::HashMap<String, u32> =
                std::collections::HashMap::new();
            for (_, id) in store.world.query::<&ShipIdentity>().iter() {
                if !id.faction_id.is_empty() {
                    *counts.entry(id.faction_id.clone()).or_insert(0) += 1;
                }
            }
            counts
                .into_iter()
                .min_by_key(|(_, n)| *n)
                .map(|(f, _)| f)
                .unwrap_or_else(|| {
                    req.prefer_faction
                        .clone()
                        .unwrap_or_else(|| "terran-authority".to_string())
                })
        };

        // Pick a dockable station — prefer the chosen faction's,
        // fall back to any.
        let candidates: Vec<(String, String, String)> = store
            .world
            .query::<(&FacilityIdentity, &FacilityLocation, &FacilityOperations)>()
            .iter()
            .filter(|(_, (id, _, ops))| {
                id.facility_type != "gate" && ops.docking_capacity > 0
            })
            .map(|(_, (id, loc, _))| {
                (
                    loc.location_name.clone(),
                    id.faction_id.clone(),
                    id.body_id.clone(),
                )
            })
            .collect();
        if candidates.is_empty() {
            continue;
        }
        let home: Vec<_> = candidates
            .iter()
            .filter(|(_, fid, _)| *fid == faction_id)
            .cloned()
            .collect();
        let pool = if home.is_empty() { &candidates } else { &home };
        let (location_name, _picked_faction, body_id) =
            pool[(seed as usize) % pool.len()].clone();

        // Resolve body position from the hecs world — no DB hop.
        let body_pos = store
            .world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter()
            .find(|(_, (b, _))| b.body_id == body_id)
            .map(|(_, (_, o))| o.universe_position())
            .unwrap_or((0.0, 0.0));

        let name = sim_server::engine::random_ship_name(seed);
        let agent_id = format!("ship-respawn-{tick}-{:x}", seed & 0xFFFF);
        let payload = sim_server::control::AdminSpawnShipPayload {
            db_id: 0,
            agent_id: agent_id.clone(),
            name,
            class: class.to_string(),
            location_name: location_name.clone(),
            faction_id: faction_id.clone(),
            universe_offset: (0.0, 0.0),
            position: body_pos,
            credits: 5_000,
        };
        sim_server::engine::admin_spawn_ship(store, registry, payload, events);
        events.push(serde_json::json!({
            "kind": "ship_spawned",
            "id": agent_id,
            "class": class,
            "faction_id": faction_id,
            "location": location_name,
            "reason": "adaptive_respawn",
        }));
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

/// Consume a pending [`SpawnShipRequest`] and call sim_server's
/// admin_spawn_ship against our in-memory store. `Some(params)`
/// honours the picker dropdown values; `None` falls back to the
/// freighter-at-earth-station preset for the quick-spawn path. The
/// new hecs entity becomes a Bevy render entity on the next frame
/// via `reconcile_new_ships` in render/.
fn process_spawn_ship(mut req: ResMut<SpawnShipRequest>, mut sim: ResMut<Sim>) {
    let Some(params) = req.0.take() else { return };

    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};

    // Throwaway id from wall-clock so repeated clicks don't collide.
    // Embedded ships aren't persisted yet (no DB worker), so db_id=0
    // is fine — a restart drops these anyway.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let agent_id = format!("admin-spawn-{ts}");
    let name = if params.name.trim().is_empty() {
        format!("admin-{ts}")
    } else {
        params.name.trim().to_string()
    };

    // Location → body_id: walk facilities and find the one whose
    // location_name matches the user's pick. Multiple facilities can
    // share a location (a station + a refinery on the same body); we
    // only need the body_id, which is consistent across them.
    let body_id_for_location: Option<String> = sim
        .store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .find(|(_e, (_id, loc))| loc.location_name == params.location_name)
        .map(|(_e, (id, _loc))| id.body_id.clone());

    let body_pos = body_id_for_location
        .as_deref()
        .and_then(|bid| {
            sim.store
                .world
                .query::<(&BodyIdentity, &BodyOrbit)>()
                .iter()
                .find(|(_e, (b, _))| b.body_id == bid)
                .map(|(_e, (_, o))| o.universe_position())
        })
        .unwrap_or((0.0, 0.0));

    let payload = sim_server::control::AdminSpawnShipPayload {
        db_id: 0,
        agent_id: agent_id.clone(),
        name,
        class: params.class.clone(),
        location_name: params.location_name.clone(),
        faction_id: params.faction_id.clone(),
        universe_offset: (0.0, 0.0),
        position: body_pos,
        credits: params.credits,
    };

    let Sim { store, registry, .. } = &mut *sim;
    let mut events: Vec<serde_json::Value> = Vec::new();
    sim_server::engine::admin_spawn_ship(store, registry, payload, &mut events);
    info!(
        "client_bevy admin: spawned {} {} at {} ({} cr)",
        params.class, agent_id, params.location_name, params.credits
    );
}

/// Consume a pending [`SpawnFacilityRequest`] and call sim_server's
/// admin_spawn_facility. The location_name is auto-derived from the
/// body_id + a sluggified name (matches the HTTP admin handler's
/// `facility-{location}-{slug}` agent_id pattern). location_id=0
/// is fine — embedded client doesn't persist these, so the DB FK
/// would only matter on next boot.
fn process_spawn_facility(mut req: ResMut<SpawnFacilityRequest>, mut sim: ResMut<Sim>) {
    let Some(params) = req.0.take() else { return };

    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let slug = params
        .name
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>();
    // Two facilities at the same body / same name would clash on
    // agent_id. Wall-clock ts disambiguates and keeps embedded admin
    // re-clicks idempotent-friendly (each click = a new id).
    let location_name = format!("{}-{}", params.body_id, slug);
    let agent_id = format!("facility-{location_name}-{ts}");

    let payload = sim_server::control::AdminSpawnFacilityPayload {
        db_id: 0,
        agent_id: agent_id.clone(),
        name: params.name.clone(),
        facility_type: params.facility_type.clone(),
        body_id: params.body_id.clone(),
        faction_id: params.faction_id.clone(),
        location_name,
        location_id: 0,
        docking_capacity: params.docking_capacity,
        condition: 1.0,
        reputation: 50,
        credits: params.credits,
    };

    let Sim { store, .. } = &mut *sim;
    let mut events: Vec<serde_json::Value> = Vec::new();
    sim_server::engine::admin_spawn_facility(store, payload, &mut events);
    info!(
        "client_bevy admin: spawned facility {} ({}) at body={}",
        agent_id, params.facility_type, params.body_id
    );
}

/// Consume a pending [`DeleteShipRequest`]. Cleanup mirrors the
/// inline path in ship_details_panel: yank the ship from any
/// facility's docked_ships / dock_queue, release its contract
/// holdings, despawn the hecs entity, drop the index entry. Render
/// cleanup happens in `cleanup_stale_ships`.
fn process_delete_ship(mut req: ResMut<DeleteShipRequest>, mut sim: ResMut<Sim>) {
    let Some(ship_id) = req.0.take() else { return };
    use sim_core::agents::facility::FacilityStorage;
    let Some(&entity) = sim.store.ship_by_id.get(&ship_id) else {
        return;
    };
    for (_e, storage) in sim.store.world.query_mut::<&mut FacilityStorage>() {
        storage.docked_ships.retain(|&e| e != entity);
        storage.dock_queue.retain(|&e| e != entity);
    }
    let _ = sim.store.contracts.drop_ship_holdings(&ship_id);
    let _ = sim.store.world.despawn(entity);
    sim.store.ship_by_id.remove(&ship_id);
    info!("client_bevy admin: deleted ship {}", ship_id);
}

/// Consume a pending [`DeleteFacilityRequest`]. Cleanup mirrors
/// `sim_server::engine::admin_remove_facility` (sync subset, no
/// persist_tx): clear `docked_at` on any ship pointing at this
/// facility's location, cancel contracts where this facility is the
/// requestor, despawn the hecs entity, drop the index. Render
/// cleanup is the responsibility of any future
/// `cleanup_stale_facilities` system; today the Bevy entity lingers
/// until restart, same trade-off the existing ship cascade lives with.
fn process_delete_facility(
    mut req: ResMut<DeleteFacilityRequest>,
    mut sim: ResMut<Sim>,
) {
    let Some(fac_id) = req.0.take() else { return };
    use sim_core::agents::ship::ShipPosition;
    let Some(&entity) = sim.store.facility_by_id.get(&fac_id) else {
        return;
    };

    // Clear docked_at on any ship pointing at this facility entity —
    // without this they'd hold a stale Entity reference. Same shape
    // as sim_server's admin_remove_facility ship-cleanup pass.
    for (_e, pos) in sim.store.world.query_mut::<&mut ShipPosition>() {
        if pos.docked_at == Some(entity) {
            pos.docked_at = None;
        }
    }

    // Cancel contracts requested by this facility. The sim will
    // re-post anything still relevant on the next economy cycle.
    sim.store
        .contracts
        .cancel_for_facility(Some(&fac_id), None, None);

    let _ = sim.store.world.despawn(entity);
    sim.store.facility_by_id.remove(&fac_id);
    info!("client_bevy admin: deleted facility {}", fac_id);
}
