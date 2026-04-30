//! Ship components for hecs storage.
//!
//! A ship entity is spawned with the full bundle of components below. Fields
//! are grouped by access pattern so that tick phases load only the data they
//! need — position updates don't pull cargo or AI into cache.
//!
//! Spawn a ship with:
//! ```ignore
//! world.spawn((
//!     ShipIdentity { ... },
//!     ShipPosition { ... },
//!     ShipTransit { transit: None },
//!     ShipCargo { ... },
//!     ShipFuel { ... },
//!     ShipEconomy { ... },
//!     ShipAI { ... },
//!     ShipMemory { ... },
//!     ShipLifecycle { ... },
//! ));
//! ```

use bevy_ecs::prelude::{Entity, World};

use crate::{
    ai::behavior_tree::{Blackboard, BtStatus},
    economy::commodities::Commodity,
};

pub mod actions;
pub use actions::ShipAction;
use actions::execute_ship_action;

mod components;
pub use components::*;

mod behavior;
pub use behavior::*;

pub mod snapshot;
pub use snapshot::{
    ShipCrewSkillsSnapshot, ShipCrewSnapshot, ShipDerivedStatsSnapshot, ShipFittingSnapshot,
    ShipProgressionSnapshot, ShipSnapshot,
};


// ============================================================================
// Tick logic — Phase 4 MVP
// ============================================================================
//
// Direct state-machine approach rather than full BT execution. The BT engine
// from Phase 1 is still available for Phase 4.5 when we want more elaborate
// goal chains, but for the MVP we use a simple decision tree each tick:
//
//   1. Advance transit (if in transit). Arrive → set location, clear transit.
//   2. Observe local market prices (if at a location, not in transit).
//   3. Decide:
//      - in transit? consume fuel, position interpolation
//      - fuel below 25%? instant refill (facility-based later)
//      - at location with cargo? sell locally at known price
//      - at location with empty cargo + known margin? buy locally → travel to sell
//      - at location without profitable route? idle (or explore later)
//
// Market supply changes emit SimCommand::AddSupply / RemoveSupply to the
// buffer. Credits move in-place (within the ship) because self-transfers
// don't need cross-agent coordination.

use crate::economy::commodities::PriceMemory;
use crate::simulation::commands::CommandBuffer;
use crate::world::{pathfinder::{LegKind, PathfinderCtx}, registry::WorldRegistry};
use std::collections::HashMap as StdHashMap;

/// Estimate gate fees a contract route will cost. Used by the contract
/// planner to reject unprofitable cross-system runs before committing
/// to them. Counts the number of gate hops across all provided
/// (from, to) pairs and multiplies by the default per-gate fee using a
/// conservative cargo estimate.
///
/// Uses only `gate_pairs` (not a full registry) — the assumption is
/// that every cross-system trip crosses exactly one gate pair, which
/// is true for our 3-system topology today. A richer pathfinder-based
/// estimate can drop in later if we add intermediate systems.
fn estimate_route_gate_fees(
    pairs: &[(&str, &str)],
    gate_pairs: &StdHashMap<String, String>,
    cargo_estimate: u32,
) -> i64 {
    if gate_pairs.is_empty() {
        return 0;
    }
    // Build a cheap "system-of" lookup from gate location prefixes. Our
    // gate locations follow `{sys}-{dest_sys}-gate` — extract the first
    // two chars (the source system token) as a system tag.
    //
    // This is brittle (naming-dependent) but fast and contained. When
    // we add new systems, revisit.
    let system_tag = |loc: &str| -> String {
        // "sol-ac-gate" → "sol". "earth-station" → "earth-station" (no match).
        // We want to categorise *any* location by system; cheap proxy:
        // if the location is itself a gate, strip the dest-and-suffix;
        // else treat as a generic intra-system location and rely on
        // gate_pairs lookup below.
        if gate_pairs.contains_key(loc) {
            loc.split('-').next().unwrap_or(loc).to_string()
        } else {
            // Non-gate location; we'll handle it in the gate_pairs
            // walk below.
            String::from("_other_")
        }
    };
    let mut total: i64 = 0;
    // For each (from, to) pair, count 1 gate hop if they're in
    // different systems. We proxy "different systems" by checking the
    // gate_pairs map for any overlapping entry.
    for (from, to) in pairs {
        // Quick heuristic: if either endpoint is a known gate location,
        // there's a gate hop in this segment. Otherwise assume intra.
        let either_is_gate = gate_pairs.contains_key(*from) || gate_pairs.contains_key(*to);
        if either_is_gate {
            // Assume one gate hop per segment.
            total += crate::agents::facility::DEFAULT_GATE_FEE_FLAT
                + (crate::agents::facility::DEFAULT_GATE_FEE_PER_CARGO
                    * cargo_estimate as i64);
        } else {
            // System-tag heuristic as a fallback.
            let (a, b) = (system_tag(from), system_tag(to));
            if a != b && a != "_other_" && b != "_other_" {
                total += crate::agents::facility::DEFAULT_GATE_FEE_FLAT
                    + (crate::agents::facility::DEFAULT_GATE_FEE_PER_CARGO
                        * cargo_estimate as i64);
            }
        }
    }
    total
}

/// Expand a (from, to) request into the sequence of `ShipAction`s that
/// actually flies it. Intra-system trips return a single `Travel`;
/// cross-system trips fan out into `Travel → GateJump → Travel`.
///
/// Used by every BT builder so the planner doesn't have to think about
/// whether a destination is local or across a gate — the pathfinder
/// does it at plan time, and the BT just executes the chain.
fn route_actions(
    from: &str,
    to: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Vec<ShipAction> {
    if from == to {
        return Vec::new();
    }
    let ctx = PathfinderCtx { registry, gate_pairs };
    let legs = match ctx.find_route(from, to) {
        Some(v) => v,
        None => {
            // No route — fall back to a direct Travel. The action's
            // executor will pick a default distance and the ship just
            // flies in a straight line. Better than stalling the plan.
            return vec![ShipAction::Travel { destination: to.to_string() }];
        }
    };
    let mut out: Vec<ShipAction> = Vec::with_capacity(legs.len());
    for leg in legs {
        match leg.kind {
            LegKind::Travel => {
                out.push(ShipAction::Travel { destination: leg.to });
            }
            LegKind::Gate => {
                out.push(ShipAction::GateJump {
                    src_gate: leg.from,
                    dest_gate: leg.to,
                });
            }
        }
    }
    out
}

const MIN_TRADE_MARGIN: f32 = 0.10; // 10% minimum margin
const TRADE_QTY_DEFAULT: u32 = 50;

/// Bundle 1.4: per-event personality-drift magnitudes. Tiny so
/// archetype identity stays stable over the short term; visible only
/// over tens-to-hundreds of events. Hundred successful deliveries
/// shifts a ship's `profit` axis by ~+0.2; ten rest-timeouts (real
/// trauma) shift `safety` by ~+0.2.
pub const DRIFT_DELIVERY_PROFIT: f32 = 0.002;
pub const DRIFT_REST_TIMEOUT_SAFETY: f32 = 0.02;

/// Half-life (in base ticks) of a remembered price's weight when
/// scoring trade routes. At age=0 a price contributes fully; at
/// HALF_LIFE it's worth 50%; asymptotes toward a floor so even very
/// old observations still weakly count. ~1500 base ticks ≈ 3 minutes
/// of game time at `WORLD_SPEED=1.0`. Prevents ships from routing
/// on stale prices after long exploration tours. Paired floor keeps
/// early-game sims (few observations) from scoring everything at 0.
pub const PRICE_MEMORY_HALF_LIFE_TICKS: u64 = 1500;
pub const PRICE_MEMORY_FRESHNESS_FLOOR: f32 = 0.10;

/// Exponential-decay weight for a price observed at `observed_tick`
/// being scored at `current_tick`. Returns 1.0 for same-tick, 0.5
/// at HALF_LIFE, clamped to `[FRESHNESS_FLOOR, 1.0]`.
pub fn price_freshness_weight(observed_tick: u64, current_tick: u64) -> f32 {
    let age = current_tick.saturating_sub(observed_tick) as f32;
    let half = PRICE_MEMORY_HALF_LIFE_TICKS as f32;
    let raw = (-age / half).exp2();
    raw.clamp(PRICE_MEMORY_FRESHNESS_FLOOR, 1.0)
}

/// Sensor range (universe-units) required to see cross-system
/// contracts in the planner. 2.0 matches the tier-2 `sensors_t2`
/// baseline — tier-1 tiny sensors (1.0 au) can't pick up
/// interstellar traffic, so small ships that haven't upgraded
/// sensors are effectively restricted to intra-system trade. Size
/// ≥ 5 hulls (Huge / Massive) ship with tier-2 sensors as their
/// default loadout; size-4 (Large) ships roll 50% tier-2 at spawn.
pub const CROSS_SYSTEM_SENSOR_RANGE_AU: f32 = 2.0;

// --- Crew constants (match Elixir CrewComplement rates) ---

/// Base per-tick hunger gain (before tick_scale). Elixir `@hunger_rate 2`.
/// Scaled down from 2.0 → 1.0 alongside fatigue: at the old rates, a
/// crew hit the morale-penalty hunger threshold (60) halfway through
/// a typical inter-system trip, which then cascaded into rest_crew
/// lockouts on the next replan.
pub const CREW_HUNGER_RATE_BASE: f32 = 1.0;
/// Base per-tick fatigue gain while active. Dropped 1.0 → 0.4: at 1.0,
/// a pilot on a 300-tick voyage arrives past the fatigue-morale penalty
/// threshold (70) with no recovery window between legs, and the planner
/// sends them straight to shore leave — contracts never get considered.
/// 0.4 gives roughly 3× longer voyages before burnout trips.
pub const CREW_FATIGUE_RATE_ACTIVE_BASE: f32 = 0.4;
/// Base per-tick fatigue recovery while resting (negative = recovery).
pub const CREW_FATIGUE_RATE_REST_BASE: f32 = -5.0;
/// Base per-tick morale decay toward 50.
pub const CREW_MORALE_DECAY_BASE: f32 = 0.5;
/// Base morale recovery bump applied docked/resting (per check interval).
/// Morale recovery applied each morale-check interval when docked but
/// not actively resting (i.e. during refuel/load/unload). Bumped 3 → 6
/// so a ship that arrives drained climbs back to sustainable morale
/// during a normal trade visit, no shore leave required.
pub const CREW_MORALE_RECOVERY_DOCKED: f32 = 6.0;
pub const CREW_MORALE_RECOVERY_RESTING: f32 = 8.0;

/// Hunger threshold that triggers Eating task + morale penalty zone.
pub const CREW_HUNGER_EAT_THRESHOLD: f32 = 55.0;
/// Hunger threshold above which morale drops on check.
pub const CREW_HUNGER_MORALE_PENALTY: f32 = 60.0;
/// Fatigue threshold that triggers Resting task.
pub const CREW_FATIGUE_REST_THRESHOLD: f32 = 65.0;
/// Fatigue threshold above which morale drops on check.
pub const CREW_FATIGUE_MORALE_PENALTY: f32 = 70.0;

/// Morale below this triggers the `rest_crew` planner goal (shore leave).
pub const CREW_SHORE_LEAVE_TRIGGER: f32 = 50.0;
/// Morale at/above this ends shore leave. Elixir requires full 100.
pub const CREW_SHORE_LEAVE_TARGET: f32 = 100.0;

/// Morale floor the legacy `Rest` action uses to return Success. Keeps
/// short-rest semantics separate from shore leave.
pub const CREW_REST_TARGET: f32 = 80.0;

/// Phase 18k: cap on how long a ship will stay in the `Rest` BT action
/// before giving up and returning `Success` regardless of morale. Guards
/// against a facility-full-dock → "speculative" Dock → Rest-forever
/// death spiral where a crew that couldn't actually dock can't get
/// the docked-state recovery boost and stays pinned at morale=0.
///
/// 300 base ticks = ~38 s at default `WORLD_SPEED=0.25` (mult=32) or
/// ~9 s at `WORLD_SPEED=4` (mult=2). Long enough for a legitimate
/// shore-leave to complete, short enough that a stuck ship unwinds
/// its BT within a visible window.
pub const MAX_REST_TICKS_BASE: u64 = 300;

/// Phase 18L: how long a ship will sit in the `Dock` action waiting
/// for the apply phase to actually put it in a slot before deciding
/// "docks are jammed — let's try elsewhere." Expressed in BASE ticks
/// (scaled by `tick_multiplier` at wait-check time). The effective
/// budget depends on ship context:
///  - Has an active contract (a ship with a job to finish is willing
///    to wait longer for the 'right' dock): `DOCK_WAIT_WITH_CONTRACT`.
///  - Low-morale shore-leave candidate (needs relief urgently, can't
///    afford to sit in line): `DOCK_WAIT_LOW_MORALE`.
///  - Everything else (default — mid-patience): `DOCK_WAIT_DEFAULT`.
pub const DOCK_WAIT_WITH_CONTRACT: u64 = 150;
pub const DOCK_WAIT_DEFAULT: u64 = 60;
pub const DOCK_WAIT_LOW_MORALE: u64 = 30;
/// Morale threshold below which a ship gets the impatient wait budget.
pub const DOCK_WAIT_LOW_MORALE_THRESHOLD: f32 = 40.0;
/// Legacy alias for planner-side rest trigger kept for existing call sites.
/// Morale threshold below which the planner switches the ship into
/// rest_crew mode, overriding every other goal (including accepting a
/// contract). Dropped from 35 → 15 — at 35 the rest_crew rule was
/// firing so aggressively on ships between trade runs that contracts
/// never got accepted. At 15, a ship has to be genuinely burned out
/// (starving + exhausted + broke) to trigger shore leave.
pub const CREW_REST_TRIGGER: f32 = 15.0;

/// Base wage per crew member per pay cycle. Paid out every WAGE_INTERVAL
/// base-ticks from ShipEconomy.credits; unpaid wages drop morale.
pub const CREW_WAGE_PER_HEAD: i64 = 5;
pub const CREW_WAGE_INTERVAL_BASE: u64 = 50;
pub const CREW_WAGE_UNPAID_MORALE_DROP: f32 = 5.0;

/// Morale-check cadence (base ticks, pre-mult). Matches Elixir's 5×mult.
pub const CREW_MORALE_CHECK_INTERVAL_BASE: u64 = 5;

/// Food units one crew consumes per Eating task. Consumes `size × 1` food.
pub const CREW_FOOD_PER_CREW_PER_MEAL: u32 = 1;
/// Hunger reduction when a meal is successfully consumed.
pub const CREW_HUNGER_MEAL_REDUCTION: f32 = 25.0;

/// Tick all ships in 4 passes to keep hecs borrows clean.
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_arguments)]
/// Per-tick last-sample microseconds for the four ship sub-phases.
/// Updated by [`tick_ships`] each call. Read by sim_server's
/// `/api/health.perf.phase_us.ships_breakdown` so the stress harness
/// can localize which sub-phase dominates the headline `ships=` cost.
///
/// Single sample, last-write-wins — average over a window for stable
/// readings. Values are 0 until the first `tick_ships` invocation.
#[derive(Debug, Clone, Copy, Default, serde::Serialize)]
pub struct ShipPhaseBreakdownUs {
    pub lod_gate: u64,
    pub advance_transits: u64,
    pub observe_prices: u64,
    pub tick_crew: u64,
    pub decide_and_act: u64,
}

/// Atomic-ish snapshot of the most recent [`tick_ships`] sub-phase
/// breakdown. Stashed in a `RwLock` rather than spread across atomics
/// so the whole struct round-trips through serde in one shot for the
/// `/api/health` payload. Lock contention is single-write per tick +
/// occasional reads from /api/health, so an `RwLock` is plenty.
pub static SHIP_PHASE_BREAKDOWN: std::sync::RwLock<ShipPhaseBreakdownUs> =
    std::sync::RwLock::new(ShipPhaseBreakdownUs {
        lod_gate: 0,
        advance_transits: 0,
        observe_prices: 0,
        tick_crew: 0,
        decide_and_act: 0,
    });

pub fn tick_ships(
    world: &mut World,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    contracts: &crate::economy::contracts::ContractBoard,
    relations: &crate::agents::faction_relations::FactionRelations,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let mut bd = ShipPhaseBreakdownUs::default();
    let t_lod = std::time::Instant::now();
    // Pass 1: LOD gate. Fire each ship's cursor once, collect the set
    // of entities that should tick this round with their rate multiplier
    // (skipped-ticks since last fire). Subsequent phases filter on this
    // map — it's the single source of truth for "should ship X run?".
    // Ships without an AgentLod component default to "every tick".
    //
    // Bundle 1.5: restrict advancement to ship entities only. Prior
    // to this the query advanced every AgentLod cursor in the world
    // (facilities + populations included), which defeats facility /
    // population LOD gates downstream because their cursors would
    // already have been advanced this tick.
    use crate::simulation::lod::AgentLod;
    let ship_entities: std::collections::HashSet<Entity> = {
        let mut q = world.query::<(Entity, &ShipIdentity, &AgentLod)>();
        q.iter(&world).map(|(e, _, _)| e).collect()
    };
    let mut active: std::collections::HashMap<Entity, u32> =
        std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<(Entity, &mut AgentLod)>();
        for (e, mut lod) in lod_q.iter_mut(world) {
            if !ship_entities.contains(&e) {
                continue;
            }
            if let Some(skipped) = lod.try_fire(tick) {
                active.insert(e, skipped);
            }
        }
    }
    // Any ship without an AgentLod component runs every tick.
    let ids_with_lod: std::collections::HashSet<Entity> = {
        let mut q = world.query::<(Entity, &AgentLod)>();
        q.iter(&world).map(|(e, _)| e).collect()
    };
    let no_lod_ships: Vec<Entity> = {
        let mut q = world.query::<(Entity, &ShipIdentity)>();
        q.iter(&world)
            .map(|(e, _)| e)
            .filter(|e| !ids_with_lod.contains(e))
            .collect()
    };
    for e in no_lod_ships {
        active.insert(e, 1);
    }
    bd.lod_gate = t_lod.elapsed().as_micros() as u64;

    let t = std::time::Instant::now();
    advance_transits(world, registry, tick, tick_scale, tick_multiplier, &active);
    bd.advance_transits = t.elapsed().as_micros() as u64;

    let t = std::time::Instant::now();
    observe_prices(world, tick, &active, gate_pairs, registry);
    bd.observe_prices = t.elapsed().as_micros() as u64;

    let t = std::time::Instant::now();
    tick_crew(world, tick, tick_scale, tick_multiplier, &active);
    bd.tick_crew = t.elapsed().as_micros() as u64;

    let t = std::time::Instant::now();
    decide_and_act(
        world,
        registry,
        gate_pairs,
        contracts,
        relations,
        commands,
        tick,
        tick_multiplier,
        &active,
    );
    bd.decide_and_act = t.elapsed().as_micros() as u64;

    if let Ok(mut slot) = SHIP_PHASE_BREAKDOWN.write() {
        *slot = bd;
    }
}

/// Type alias for the LOD gate table shared across ship tick phases.
/// Maps `entity → skipped_ticks_since_last_fire`. Entities not in the
/// map skip this round entirely.
type ShipLodGate = std::collections::HashMap<Entity, u32>;

/// Crew tick — matches Elixir `CrewComplement.tick` behavior:
///   1. Decay: hunger rises, fatigue rises (active) or falls (resting/idle)
///   2. Morale adjust every 5×mult ticks (penalties + recovery + drift)
///   3. `auto_manage_needs`: sets `current_task` to Eating/Resting when
///      needs are past threshold, else back to the crew's `primary_task`
///   4. Pay wages every 50×mult ticks: deduct from ShipEconomy.credits;
///      if insufficient, drop morale (unpaid wages sting)
///   5. Push `efficiency()` back into ShipEconomy so trade math uses it.
///
/// Food consumption when Eating: consumes `size × 1` food from cargo. The
/// old `rest_crew` goal path still works — it now simply picks
/// `CrewTask::Resting` via the same auto-manage logic.
fn tick_crew(
    world: &mut World,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    let morale_check_interval =
        CREW_MORALE_CHECK_INTERVAL_BASE * tick_multiplier as u64;
    let wage_interval = CREW_WAGE_INTERVAL_BASE * tick_multiplier as u64;

    // Collect per-ship snapshot info we need: class (for crew roles), transit
    // state, docked state. Done in a read pass so the mutable pass can close
    // over static data without hecs borrow conflicts.
    #[derive(Clone)]
    struct CrewCtx {
        entity: Entity,
        roles: &'static [&'static str],
        in_transit: bool,
        docked: bool,
    }
    let contexts: Vec<CrewCtx> = {
        let mut q = world
            .query::<(Entity, &ShipIdentity, &ShipTransit, &ShipPosition, &ShipCrew)>();
        q.iter(&world)
            .map(|(e, id, transit, position, _crew)| {
                let roles = crate::simulation::config::ship_class(&id.class)
                    .map(|c| c.crew_roles)
                    .unwrap_or(&[]);
                CrewCtx {
                    entity: e,
                    roles,
                    in_transit: transit.transit.is_some(),
                    docked: position.docked_at.is_some(),
                }
            })
            .collect()
    };

    for ctx in contexts {
        // LOD gate — skipped_ticks scales the crew rates so a ship that
        // fires every 10 real ticks still ages its hunger/fatigue by the
        // right amount when it does fire.
        let skipped = match active.get(&ctx.entity).copied() {
            Some(n) => n,
            None => continue,
        };
        let effective_scale = tick_scale * skipped as f32;

        // Read-mutate ShipCrew + ShipEconomy + ShipCargo via query_one.
        let mut q = world.query::<(&mut ShipCrew, &mut ShipEconomy, &mut ShipCargo)>();
        let (mut crew, mut economy, mut cargo) = match q.get_mut(world, ctx.entity) {
            Ok(t) => t,
            Err(_) => continue,
        };

        // --- 1. Decay ---
        // While docked, the station provides food service and off-shift
        // rotation for the crew. Recovery rates are deliberately much
        // higher than in-transit drain (5× hunger, ~12× fatigue) so a
        // short visit clears most of the deficit — otherwise a ship
        // that's spent 200 ticks in transit can only recover a tiny
        // fraction during a brief dock dwell, cascades into morale
        // crisis, and the planner locks it into `rest_crew` for the
        // next N replans instead of accepting contracts.
        const CREW_HUNGER_DOCKED_RECOVERY: f32 = 5.0;
        const CREW_FATIGUE_DOCKED_RECOVERY: f32 = 5.0;
        let hunger_delta = if ctx.docked {
            -CREW_HUNGER_DOCKED_RECOVERY * effective_scale
        } else {
            CREW_HUNGER_RATE_BASE * effective_scale
        };
        crew.hunger = (crew.hunger + hunger_delta).clamp(0.0, 100.0);
        let fatigue_delta = match crew.current_task {
            CrewTask::Resting => CREW_FATIGUE_RATE_REST_BASE * effective_scale,
            CrewTask::Idle if !ctx.in_transit => -1.0 * effective_scale,
            _ if ctx.docked => -CREW_FATIGUE_DOCKED_RECOVERY * effective_scale,
            _ => CREW_FATIGUE_RATE_ACTIVE_BASE * effective_scale,
        };
        crew.fatigue = (crew.fatigue + fatigue_delta).clamp(0.0, 100.0);

        // --- 2. Morale check (every 5×mult ticks) ---
        if morale_check_interval > 0 && tick % morale_check_interval == 0 {
            // Hunger / fatigue penalties only apply OFF-STATION. A docked
            // ship's crew can eat and rotate shifts, so the signal to
            // the morale system is "they're coping"; the penalties would
            // otherwise keep firing even while the crew is actively
            // recovering, which stalls climb-out of rest_crew.
            let penalty: f32 = if ctx.docked {
                if crew.health < 50.0 { -2.0 } else { 0.0 }
            } else if crew.hunger > CREW_HUNGER_MORALE_PENALTY {
                -3.0
            } else if crew.fatigue > CREW_FATIGUE_MORALE_PENALTY {
                -2.0
            } else if crew.health < 50.0 {
                -4.0
            } else {
                0.0
            };
            // Docked + Resting gives the biggest bump. Plain docked also
            // gives meaningful recovery (up from 3) so a ship that
            // arrives drained can climb morale quickly during its
            // DockDwell + Refuel window without needing a full shore
            // leave.
            let recovery: f32 = if ctx.docked && crew.current_task == CrewTask::Resting {
                CREW_MORALE_RECOVERY_RESTING
            } else if ctx.docked {
                CREW_MORALE_RECOVERY_DOCKED
            } else if crew.current_task == CrewTask::Resting {
                // Phase 18k: bump the non-docked Resting recovery from
                // 0.5× docked-baseline to the full docked-baseline so
                // a crew caught on the Rest BT without having actually
                // docked (capacity-full station, broke ship, etc) can
                // still outpace hunger/fatigue penalties. Combined
                // with the Rest-action timeout this breaks the
                // morale-pinned-at-zero death spiral that stalled
                // ~50% of the fleet in Phase 18j smokes.
                CREW_MORALE_RECOVERY_DOCKED
            } else {
                0.0
            };
            let drift = if crew.morale > 50.0 {
                -CREW_MORALE_DECAY_BASE
            } else {
                CREW_MORALE_DECAY_BASE
            };
            crew.morale = (crew.morale + penalty + recovery + drift).clamp(0.0, 100.0);
        }

        // --- 3. Auto-manage needs → set current_task ---
        if crew.hunger > CREW_HUNGER_EAT_THRESHOLD {
            // Try to eat: consume `size × 1` food from cargo if available.
            let needed = crew.size * CREW_FOOD_PER_CREW_PER_MEAL;
            let have = cargo.cargo.get(&Commodity::Food).copied().unwrap_or(0);
            if have >= needed {
                *cargo.cargo.entry(Commodity::Food).or_insert(0) -= needed;
                if cargo.cargo.get(&Commodity::Food).copied().unwrap_or(0) == 0 {
                    cargo.cargo.remove(&Commodity::Food);
                    cargo.cargo_age.remove(&Commodity::Food);
                }
                crew.hunger = (crew.hunger - CREW_HUNGER_MEAL_REDUCTION).max(0.0);
            }
            crew.current_task = CrewTask::Eating;
        } else if crew.fatigue > CREW_FATIGUE_REST_THRESHOLD {
            crew.current_task = CrewTask::Resting;
        } else {
            // Fall-throughs that all pick `primary_task(roles, in_transit)`:
            //  1. Coming out of Eating/Resting — needs satisfied, back to work.
            //  2. Currently Idle — needs a real task.
            //  3. In transit but not yet piloting — UI should show the
            //     transition after refueling/ doching completes.
            let needs_refresh = (matches!(
                crew.current_task,
                CrewTask::Eating | CrewTask::Resting
            ) && crew.hunger < CREW_HUNGER_EAT_THRESHOLD
                && crew.fatigue < CREW_FATIGUE_REST_THRESHOLD)
                || crew.current_task == CrewTask::Idle
                || (ctx.in_transit && crew.current_task != CrewTask::Piloting);
            if needs_refresh {
                crew.current_task = primary_task(ctx.roles, ctx.in_transit);
            }
        }

        // --- 4. Pay wages (every 50×mult ticks) ---
        if wage_interval > 0 && tick % wage_interval == 0 && crew.size > 0 {
            let owed = CREW_WAGE_PER_HEAD * crew.size as i64;
            if economy.credits >= owed {
                economy.credits -= owed;
                crew.wages_credits = crew.wages_credits.saturating_add(owed);
            } else {
                crew.morale = (crew.morale - CREW_WAGE_UNPAID_MORALE_DROP).max(0.0);
            }
        }

        // --- 5. Push efficiency back to economy for trade math ---
        economy.efficiency = crew.efficiency();
        crew.dirty = true;
    }
}

/// Primary task derived from crew roles. If the ship is in transit and
/// there's a pilot on board, piloting overrides role-priority so Godot
/// UI shows "piloting" instead of "trading" while underway.
fn primary_task(roles: &[&str], in_transit: bool) -> CrewTask {
    let has_pilot = roles.contains(&"pilot");
    let has_engineer = roles.contains(&"engineer");
    let has_trader = roles.contains(&"trader");
    if in_transit {
        if has_pilot {
            return CrewTask::Piloting;
        }
        if has_engineer {
            return CrewTask::Engineering;
        }
        if has_trader {
            return CrewTask::Trading;
        }
        return CrewTask::Idle;
    }
    // Docked / stationary: the pilot isn't flying. Whoever runs the
    // station-side work gets the task.
    if has_trader {
        return CrewTask::Trading;
    }
    if has_engineer {
        return CrewTask::Engineering;
    }
    CrewTask::Idle
}

/// Pass 1: advance transit clocks, interpolate position, consume fuel.
fn advance_transits(
    world: &mut World,
    registry: &WorldRegistry,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    use crate::agents::facility::{
        facility_offset_position, FacilityIdentity, FacilityLocation, FacilityOperations,
    };

    // Snapshot body positions for location→position lookups.
    let body_positions: std::collections::HashMap<i64, (f32, f32)> = {
        let mut q = world.query::<(
            &crate::agents::celestial_body::BodyIdentity,
            &crate::agents::celestial_body::BodyOrbit,
        )>();
        q.iter(&world)
            .map(|(id, orbit)| (id.db_id, orbit.universe_position()))
            .collect()
    };

    // Pick one "primary" facility id per location — the highest-capacity
    // dockable facility there. Ships aim at this facility's offset
    // position so they visually arrive at the station they'll actually
    // try to dock at (matches the server-side `primary_dock_at_location`
    // heuristic). The snapshot layer uses the same
    // `facility_offset_position` function so ship and station agree on
    // where the "dock" is.
    //
    // Pre-18M this picked by hecs iteration order, which at co-located
    // clusters (earth-station has 5 facilities) would sometimes land
    // on the farm or the refinery — ships visibly drifted to
    // "Terra Hydroponics" even when the contract destination was the
    // main station.
    let mut primary_facility_by_location: std::collections::HashMap<String, (String, u32)> =
        std::collections::HashMap::new();
    {
        let mut q = world
            .query::<(&FacilityIdentity, &FacilityLocation, &FacilityOperations)>();
        for (fac_id, fac_loc, ops) in q.iter(&world) {
            let cap = ops.docking_capacity;
            if cap == 0 {
                continue;
            }
            let entry = primary_facility_by_location
                .entry(fac_loc.location_name.clone())
                .or_insert_with(|| (fac_id.id.clone(), cap));
            if cap > entry.1 {
                *entry = (fac_id.id.clone(), cap);
            }
        }
    }

    let location_to_pos = |loc: &str| -> Option<(f32, f32)> {
        let info = registry.locations.get(loc)?;
        let body_pos = body_positions.get(&info.celestial_body_id).copied()?;
        // If there's a facility at this location, target its offset position
        // (where the client renders the station). Otherwise fall back to
        // body center (locations with no facility still need a position).
        if let Some((fac_id, _)) = primary_facility_by_location.get(loc) {
            Some(facility_offset_position(body_pos, fac_id))
        } else {
            Some(body_pos)
        }
    };

    let mut transit_q = world.query::<(
        Entity,
        &mut ShipPosition,
        &mut ShipTransit,
        &mut ShipFuel,
        &mut ShipMemory,
        &mut ShipLifecycle,
    )>();
    for (entity, mut position, mut transit, mut fuel, mut memory, mut lifecycle) in
        transit_q.iter_mut(world)
    {
        // LOD gate: skip ships whose divisor cursor hasn't fired this
        // round. Ships that do fire scale their fuel burn by skipped
        // ticks so total consumption over wall-clock is preserved.
        let skipped = match active.get(&entity).copied() {
            Some(n) => n,
            None => continue,
        };
        let effective_scale = tick_scale * skipped as f32;
        if let Some(mut t) = transit.transit.clone() {
            // Lazily snapshot the departure world position for legacy rows
            // (pre-Phase-18 transits persisted without it).
            if t.departure_position.is_none() {
                t.departure_position = Some(position.position);
            }

            // Ships drive themselves. Each tick the ship moves `velocity`
            // world-units directly toward its destination's *current* world
            // position. No rails, no precomputed tick budget. Total travel
            // time is emergent: distance-to-target divided by velocity,
            // recomputed every tick. This means a ship chasing a body
            // that's orbiting away naturally takes longer; a ship cutting
            // across to a closer body arrives sooner. It also means the
            // visual trail follows wherever the ship is actually going,
            // which is what you'd want when we later add combat / evasion
            // / fleeing — the ship just has a waypoint, not a rail.
            let target = match location_to_pos(&t.to) {
                Some(p) => p,
                None => {
                    transit.transit = Some(t);
                    continue;
                }
            };
            let dx = target.0 - position.position.0;
            let dy = target.1 - position.position.1;
            let dist = (dx * dx + dy * dy).sqrt();

            let velocity = SHIP_BASE_VELOCITY * fuel.speed_modifier * effective_scale;
            // Cap the per-tick step so a ship LOD'd heavily (large
            // `skipped`) doesn't teleport past its destination.
            let step = velocity.min(dist);

            if dist <= velocity.max(SHIP_ARRIVAL_THRESHOLD) {
                // Arrive.
                position.location_name = Some(t.to.clone());
                position.docked_at = None;
                position.position = target;
                transit.transit = None;
                if !memory.visited.contains(&t.to) {
                    memory.visited.push(t.to.clone());
                }
                lifecycle.dirty = true;
            } else {
                let norm = if dist > 0.0 { step / dist } else { 0.0 };
                position.position = (
                    position.position.0 + dx * norm,
                    position.position.1 + dy * norm,
                );
                // Initial total is set from the departure-time Euclidean
                // distance, used for progress fraction display. It never
                // changes — ongoing distance to target is dist, which
                // may exceed the original if a moving destination pulls
                // away, but the progress bar clamps.
                if t.distance_total <= 0.0 {
                    t.distance_total = dist + (step * 0.5).max(0.0001);
                }
                t.distance_travelled =
                    (t.distance_total - dist).clamp(0.0, t.distance_total);

                let consumption = fuel.fuel_consumption_rate * effective_scale;
                fuel.fuel = (fuel.fuel - consumption).max(0.0);

                // Display ETA (ticks): distance / per-tick step.
                let per_tick =
                    SHIP_BASE_VELOCITY * fuel.speed_modifier * tick_scale.max(0.00001);
                let ticks_left = (dist / per_tick.max(0.00001)) as u64;
                t.arrival_tick = tick.saturating_add(ticks_left);

                transit.transit = Some(t);
            }
        } else if position.location_name.is_some() {
            // Pin the ship to its location's current world coordinates.
            //
            // Covers two cases:
            //   1. Docked (`docked_at = Some`). Godot hides docked
            //      ships in the normal render, but click-to-follow
            //      still reads `position` — without this anchor,
            //      following a docked ship snaps the camera to the
            //      ship's last in-space position (often the approach
            //      point several ticks before docking).
            //   2. Waiting to dock (`docked_at = None` but location
            //      set after transit completion). Previously the ship
            //      arrived at the station's tick-N coordinates and
            //      stayed there while the station continued orbiting
            //      — the player saw "At: haven-station" in the details
            //      panel but the station had drifted out of frame.
            //      Pinning here keeps waiting ships parked alongside
            //      their station.
            if let Some(loc) = position.location_name.clone() {
                if let Some(p) = location_to_pos(&loc) {
                    position.position = p;
                }
            }
        }
    }
    // Placate the linter — tick_multiplier is no longer needed in the
    // velocity-based model but we keep the signature for now.
    let _ = tick_multiplier;
}

/// Base movement rate in world units, scaled by `speed_modifier` and
/// `tick_scale`. Tuned so a courier (speed_mod=1.5) at default
/// world_speed=0.25 covers ~1 AU in about 500 ticks (~60s) and a tanker
/// (0.4) takes ~4× longer. Adjust here if play-feel wants faster ships.
pub const SHIP_BASE_VELOCITY: f32 = 0.05;
/// Arrival snap radius. If the ship would step onto (or inside) this
/// radius around the destination, we call it arrived. Prevents
/// hovering-just-outside when velocity is tiny and the target orbits.
pub const SHIP_ARRIVAL_THRESHOLD: f32 = 0.01;

/// Pass 2: observe local market prices into ship memory.
/// Comms-tier-scaled price observation.
///
/// When a ship is "landed" (position has a location_name — i.e. docked
/// or in-station space, not mid-transit), its comms module determines
/// how far the local-station data mesh reaches:
///
/// - **tier 1 (default)**: same celestial body — stations orbiting
///   the same planet/moon share a comms pool.
/// - **tier 2**: the full star system — system-wide relay network.
/// - **tier 3+**: system + gate-adjacent neighbor systems.
///
/// This is the information-access axis that lets tier-1 ships still
/// participate in contracts (prices for their immediate body) while
/// making comms upgrades meaningfully scale visibility. Cross-system
/// contract gating still applies separately via sensor range.
///
/// All observations land at `tick = current tick` — we don't model
/// relay lag here. If we ever add staleness-based confidence in
/// planning, PriceMemory.tick is the hook (currently unused by
/// planners beyond "is this entry present at all").
fn observe_prices(
    world: &mut World,
    tick: u64,
    active: &ShipLodGate,
    gate_pairs: &StdHashMap<String, String>,
    registry: &WorldRegistry,
) {
    use crate::agents::celestial_body::BodyIdentity;
    use crate::agents::facility::{FacilityIdentity, FacilityLocation};

    // market prices indexed by location
    let market_prices: std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, f32>,
    > = {
        let mut q = world.query::<(
            &crate::agents::market::MarketIdentity,
            &crate::agents::market::MarketPricing,
        )>();
        q.iter(&world)
            .map(|(id, pricing)| (id.facility_location.clone(), pricing.prices.clone()))
            .collect()
    };

    // location -> body_id (the string body id like "earth" or "frostheim")
    let loc_to_body: std::collections::HashMap<String, String> = {
        let mut q = world.query::<(&FacilityIdentity, &FacilityLocation)>();
        q.iter(&world)
            .map(|(id, loc)| (loc.location_name.clone(), id.body_id.clone()))
            .collect()
    };

    // body_id -> locations on that body
    let mut body_to_locs: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for (loc, body) in &loc_to_body {
        body_to_locs
            .entry(body.clone())
            .or_default()
            .push(loc.clone());
    }

    // location -> system name (via body -> system via registry)
    let body_db_to_system: std::collections::HashMap<i64, String> = {
        let mut q = world.query::<&BodyIdentity>();
        q.iter(&world)
            .map(|id| (id.db_id, id.system_name.clone()))
            .collect()
    };
    let location_to_system: std::collections::HashMap<String, String> = registry
        .locations
        .iter()
        .filter_map(|(name, info)| {
            let sys = body_db_to_system.get(&info.celestial_body_id)?;
            Some((name.clone(), sys.clone()))
        })
        .collect();

    // system -> locations in system
    let mut system_to_locs: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for (loc, sys) in &location_to_system {
        system_to_locs
            .entry(sys.clone())
            .or_default()
            .push(loc.clone());
    }

    // system -> set of gate-adjacent neighbor systems
    let mut system_neighbors: std::collections::HashMap<
        String,
        std::collections::HashSet<String>,
    > = std::collections::HashMap::new();
    for (a_loc, b_loc) in gate_pairs {
        if let (Some(a_sys), Some(b_sys)) = (
            location_to_system.get(a_loc),
            location_to_system.get(b_loc),
        ) {
            if a_sys != b_sys {
                system_neighbors
                    .entry(a_sys.clone())
                    .or_default()
                    .insert(b_sys.clone());
                system_neighbors
                    .entry(b_sys.clone())
                    .or_default()
                    .insert(a_sys.clone());
            }
        }
    }

    let mut ship_q = world.query::<(Entity, &ShipPosition, &ShipFitting, &mut ShipMemory)>();
    for (e, position, fitting, mut memory) in ship_q.iter_mut(world) {
        if !active.contains_key(&e) {
            continue;
        }
        let Some(loc) = position.location_name.as_ref() else {
            continue;
        };

        // Read the comms tier from the fitted module. Default to 1 if
        // the slug isn't in the catalog (shouldn't happen — new_default
        // fills every slot).
        let comms_slug = fitting.slots[crate::modules::Slot::Comms.index()];
        let comms_tier = comms_slug
            .and_then(crate::modules::get)
            .map(|m| m.tier)
            .unwrap_or(1);

        // Pick the visibility set based on tier.
        let mut visible: std::collections::HashSet<&str> =
            std::collections::HashSet::new();

        // Always include the ship's own location (covers edge cases
        // where loc isn't on a body, e.g. free-space placeholders).
        visible.insert(loc.as_str());

        // Tier 1: same body.
        if let Some(body) = loc_to_body.get(loc) {
            if let Some(locs) = body_to_locs.get(body) {
                for l in locs {
                    visible.insert(l.as_str());
                }
            }
        }

        if comms_tier >= 2 {
            // Tier 2: whole system.
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(locs) = system_to_locs.get(sys) {
                    for l in locs {
                        visible.insert(l.as_str());
                    }
                }
            }
        }

        if comms_tier >= 3 {
            // Tier 3+: neighbor systems (one gate hop). A future tier
            // bump can walk `system_neighbors` transitively for 2-hop
            // reach; not needed yet.
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(neighbors) = system_neighbors.get(sys) {
                    for n in neighbors {
                        if let Some(locs) = system_to_locs.get(n) {
                            for l in locs {
                                visible.insert(l.as_str());
                            }
                        }
                    }
                }
            }
        }

        for v_loc in visible {
            if let Some(prices) = market_prices.get(v_loc) {
                let entry = memory.price_knowledge.entry(v_loc.to_string()).or_default();
                for (&commodity, &price) in prices {
                    entry.insert(commodity, PriceMemory { price, tick });
                }
            }
        }
    }
}


#[cfg(test)]
mod crew_tests {
    use super::*;

    #[test]
    fn crew_efficiency_floors_at_0_1() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 0.0,
            fatigue: 0.0,
            health: 0.0,
            wages_credits: 0,
            current_task: CrewTask::Idle,
            dirty: false,
        };
        assert!((c.efficiency() - 0.1).abs() < 1e-4);
    }

    #[test]
    fn crew_efficiency_at_full_health_and_morale_is_one() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 100.0,
            fatigue: 0.0,
            health: 100.0,
            wages_credits: 0,
            current_task: CrewTask::Piloting,
            dirty: false,
        };
        assert!((c.efficiency() - 1.0).abs() < 1e-4);
    }

    #[test]
    fn crew_needs_shore_leave_below_50() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 49.0,
            fatigue: 0.0,
            health: 100.0,
            wages_credits: 0,
            current_task: CrewTask::Idle,
            dirty: false,
        };
        assert!(c.needs_shore_leave());
        assert!(!c.shore_leave_complete());
    }

    #[test]
    fn skills_default_for_pilot_engineer_trader() {
        let s = ShipCrewSkills::for_roles(&["pilot", "engineer", "trader"]);
        assert_eq!(s.navigation, 40);
        assert_eq!(s.engineering, 40);
        assert_eq!(s.trading, 40);
        assert_eq!(s.combat, 20);
    }

    #[test]
    fn skills_grant_caps_at_100() {
        let mut s = ShipCrewSkills::for_roles(&["pilot"]);
        s.grant("navigation", 70);
        assert_eq!(s.navigation, 100); // 40 + 70 → capped
        s.grant("trading", 50);
        assert_eq!(s.trading, 80);
        s.grant("combat", 200);
        assert_eq!(s.combat, 100);
        // Unknown skill name is a no-op
        s.grant("telepathy", 10);
        assert_eq!(s.navigation, 100);
    }

    #[test]
    fn primary_task_prefers_piloting_in_transit() {
        assert_eq!(
            primary_task(&["pilot", "engineer", "trader"], true),
            CrewTask::Piloting
        );
        assert_eq!(
            primary_task(&["engineer", "trader"], true),
            CrewTask::Engineering
        );
        assert_eq!(primary_task(&["trader"], false), CrewTask::Trading);
        assert_eq!(primary_task(&[], false), CrewTask::Idle);
    }
}

#[cfg(test)]
mod tick_tests {
    use super::*;
    use super::actions::affordable_quantity;

    #[test]
    fn affordable_quantity_respects_credits_and_capacity() {
        assert_eq!(affordable_quantity(100, 10.0, 1000), 10);
        assert_eq!(affordable_quantity(0, 10.0, 1000), 0);
        assert_eq!(affordable_quantity(1000, 10.0, 50), 50);
        assert_eq!(affordable_quantity(50, 10.0, 100), 5);
    }

    #[test]
    fn best_trade_route_finds_best_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("belt".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 50.0, tick: 1 });
        memory.price_knowledge.insert("earth".into(), b);
        let route = best_trade_route(&memory, 1).unwrap();
        assert_eq!(route.0, Commodity::Ore);
        assert_eq!(route.1, "belt");
        assert_eq!(route.2, "earth");
    }

    #[test]
    fn best_trade_route_prefers_fresher_over_slightly_better_stale() {
        // Stale huge-margin route at tick 1 vs fresh good-margin route
        // at tick 10_000. The fresh route should win even though the
        // stale one has a nominally larger raw margin.
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut stale_a = std::collections::HashMap::new();
        stale_a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("stale-belt".into(), stale_a);
        let mut stale_b = std::collections::HashMap::new();
        stale_b.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("stale-hub".into(), stale_b);
        // 900% raw margin, but 10_000 ticks old → heavily decayed.

        let mut fresh_a = std::collections::HashMap::new();
        fresh_a.insert(
            Commodity::Fuel,
            PriceMemory { price: 50.0, tick: 10_000 },
        );
        memory.price_knowledge.insert("fresh-belt".into(), fresh_a);
        let mut fresh_b = std::collections::HashMap::new();
        fresh_b.insert(
            Commodity::Fuel,
            PriceMemory { price: 150.0, tick: 10_000 },
        );
        memory.price_knowledge.insert("fresh-hub".into(), fresh_b);
        // 200% raw margin, freshly observed at tick 10_000.

        let route = best_trade_route(&memory, 10_000).unwrap();
        assert_eq!(
            route.0,
            Commodity::Fuel,
            "fresh fuel route should beat 10k-tick-stale ore route",
        );
    }

    #[test]
    fn price_freshness_weight_decays_monotonically() {
        // Sanity check the decay curve: fresh = 1.0, half-life = 0.5,
        // 2× half-life = 0.25, ancient floors at FRESHNESS_FLOOR.
        let fresh = price_freshness_weight(1000, 1000);
        assert!((fresh - 1.0).abs() < 1e-5);
        let half = price_freshness_weight(0, PRICE_MEMORY_HALF_LIFE_TICKS);
        assert!((half - 0.5).abs() < 1e-5, "half-life should halve weight, got {half}");
        let ancient = price_freshness_weight(0, 1_000_000);
        assert!(
            (ancient - PRICE_MEMORY_FRESHNESS_FLOOR).abs() < 1e-5,
            "very old should floor, got {ancient}",
        );
    }

    #[test]
    fn pick_rest_destination_prefers_current_when_free() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        cong.insert("earth-station".into(), (23, 5, 0)); // 21% full, no queue
        cong.insert("mars-station".into(), (10, 1, 0));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("earth-station".into(), "Sol".into());
        sys.insert("mars-station".into(), "Sol".into());
        // Current has free slots → stay.
        assert_eq!(
            pick_rest_destination("earth-station", &cong, &sys),
            "earth-station",
        );
    }

    #[test]
    fn pick_rest_destination_routes_away_from_saturated() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        cong.insert("haven-station".into(), (19, 19, 0)); // 100% full
        cong.insert("proxima-outpost".into(), (8, 2, 0)); // 25%
        cong.insert("refuge-station".into(), (6, 1, 0));  // 17%
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("haven-station".into(), "Alpha Centauri".into());
        sys.insert("proxima-outpost".into(), "Alpha Centauri".into());
        sys.insert("refuge-station".into(), "Alpha Centauri".into());
        // Current saturated → pick least-saturated same-system option.
        assert_eq!(
            pick_rest_destination("haven-station", &cong, &sys),
            "refuge-station",
        );
    }

    #[test]
    fn pick_rest_destination_stays_in_same_system() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        cong.insert("haven-station".into(), (19, 19, 0)); // AC saturated
        cong.insert("earth-station".into(), (23, 0, 0));  // Sol wide open
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("haven-station".into(), "Alpha Centauri".into());
        sys.insert("earth-station".into(), "Sol".into());
        // Even though earth has tons of space, it's cross-system.
        // Fall back to current saturated location.
        assert_eq!(
            pick_rest_destination("haven-station", &cong, &sys),
            "haven-station",
        );
    }

    #[test]
    fn pick_rest_destination_falls_back_when_all_full() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        cong.insert("a".into(), (10, 10, 0));
        cong.insert("b".into(), (5, 5, 0));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("a".into(), "Sol".into());
        sys.insert("b".into(), "Sol".into());
        // All saturated → stick with current. Ship will still try,
        // hit the Dock wait budget, and replan — better than None.
        assert_eq!(pick_rest_destination("a", &cong, &sys), "a");
    }

    #[test]
    fn pick_rest_destination_treats_queue_pressure_as_saturation() {
        // Post-tick-21k-spiral fix: a station whose dock isn't yet
        // full but whose queue is large should be considered
        // saturated. Without the queue term, 44 ships would pile
        // onto forge-smelter even as it was already failing.
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        // forge-smelter: 25 cap / 25 docked / 44 queued → effectively
        // full (load ratio 2.76).
        cong.insert("forge-smelter".into(), (25, 25, 44));
        // anvil-depot: 40 cap / 24 docked / 0 queued → load 0.6 — viable.
        cong.insert("anvil-depot".into(), (40, 24, 0));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("forge-smelter".into(), "Tau Ceti".into());
        sys.insert("anvil-depot".into(), "Tau Ceti".into());
        assert_eq!(
            pick_rest_destination("forge-smelter", &cong, &sys),
            "anvil-depot",
            "saturation should consider queue pressure",
        );
    }

    #[test]
    fn any_rest_destination_viable_returns_false_when_all_saturated() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        // Every station in the system is overloaded.
        cong.insert("forge-smelter".into(), (25, 25, 44));
        cong.insert("anvil-depot".into(), (10, 12, 5));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("forge-smelter".into(), "Tau Ceti".into());
        sys.insert("anvil-depot".into(), "Tau Ceti".into());
        assert!(
            !any_rest_destination_viable("forge-smelter", &cong, &sys),
            "all-saturated system should report no viable destination",
        );
    }

    #[test]
    fn any_rest_destination_viable_returns_true_when_any_has_room() {
        let mut cong: StdHashMap<String, (u32, u32, u32)> = StdHashMap::new();
        cong.insert("forge-smelter".into(), (25, 25, 44));
        cong.insert("anvil-depot".into(), (40, 5, 0));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("forge-smelter".into(), "Tau Ceti".into());
        sys.insert("anvil-depot".into(), "Tau Ceti".into());
        assert!(
            any_rest_destination_viable("forge-smelter", &cong, &sys),
            "uncrowded sibling station should qualify as viable",
        );
    }

    #[test]
    fn score_goal_positive_profit_scales_with_personality_bonus() {
        let p = crate::ai::personality::Personality::cautious_trader();
        // cautious_trader likes fulfill_delivery (+0.3) and
        // fulfill_contract (+0.3), flat on trade_run.
        let contract = score_strategic(1600, "fulfill_delivery", &p, false);
        let trade = score_strategic(1600, "trade_run", &p, false);
        assert!(
            contract > trade,
            "cautious_trader should favor fulfill_delivery over trade_run (got {contract} vs {trade})",
        );
    }

    #[test]
    fn score_goal_aggressive_trader_picks_trade_over_contract() {
        let p = crate::ai::personality::Personality::aggressive_trader();
        // aggressive_trader has prefer_goals[trade_run] = 0.3.
        let contract = score_strategic(1600, "fulfill_delivery", &p, false);
        let trade = score_strategic(1600, "trade_run", &p, false);
        assert!(
            trade > contract,
            "aggressive_trader should pick trade_run over equal-profit contract",
        );
    }

    #[test]
    fn score_goal_courier_picks_passenger_over_trade() {
        let p = crate::ai::personality::Personality::courier();
        let passenger = score_strategic(1200, "fulfill_passenger_transport", &p, false);
        let trade = score_strategic(1200, "trade_run", &p, false);
        assert!(passenger > trade, "courier should favor passenger work");
    }

    #[test]
    fn score_goal_zero_when_no_profit() {
        let p = crate::ai::personality::Personality::balanced_trader();
        assert_eq!(score_strategic(0, "fulfill_delivery", &p, false), 0.0);
        assert_eq!(score_strategic(-500, "trade_run", &p, false), 0.0);
    }

    #[test]
    fn score_goal_log_scales_so_small_bonus_can_flip_picks() {
        // Huge trade-run profit (50000) vs modest contract (2000)
        // — without bonus trade wins. With a strong contract bonus
        // (>0.7), contract might still lose because log-scale
        // compresses. This test documents the expected behaviour.
        let p_flat = crate::ai::personality::Personality::balanced_trader();
        assert!(score_strategic(50000, "trade_run", &p_flat, false) > score_strategic(2000, "fulfill_delivery", &p_flat, false));
        // With a modest contract preference it still doesn't win
        // a 25× profit gap (as designed — log-scaling prevents
        // personality from completely overriding profit).
        let mut p_biased = crate::ai::personality::Personality::balanced_trader();
        p_biased.prefer_goals.insert("fulfill_delivery".into(), 0.3);
        assert!(score_strategic(50000, "trade_run", &p_biased, false) > score_strategic(2000, "fulfill_delivery", &p_biased, false));
    }

    #[test]
    fn best_trade_route_none_for_thin_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("a".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 105.0, tick: 1 });
        memory.price_knowledge.insert("b".into(), b);
        assert!(best_trade_route(&memory, 1).is_none());
    }

    // --- Bundle 2.1 unified utility scorer tests ---

    #[test]
    fn unified_scorer_biological_dominates_strategic_when_critical() {
        // Critical fuel (5%) on a cautious trader must outscore a
        // 50k-credit trade. This is the "ship at 1% fuel shouldn't
        // pursue a distant contract" invariant.
        let p = crate::ai::personality::Personality::cautious_trader();
        let fuel_urgency = (1.0 - 0.05 / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let refuel_score = fuel_urgency * p.safety.max(0.2) * TIER_BIO_WEIGHT;
        let trade_score = score_strategic(50_000, "trade_run", &p, false);
        assert!(
            refuel_score > trade_score,
            "refuel at 5% fuel (score {refuel_score}) must beat 50k trade (score {trade_score})",
        );
    }

    #[test]
    fn unified_scorer_strategic_can_win_when_fuel_is_fine() {
        // With fuel at 60% (above FUEL_URGENCY_ONSET=0.45) there's no
        // refuel candidate at all, so a profitable trade is free to
        // win. Housekeeping-tier sell_cargo with empty hold also
        // scores 0. Strategic gets the nod.
        let p = crate::ai::personality::Personality::aggressive_trader();
        let trade_score = score_strategic(10_000, "trade_run", &p, false);
        // Arbitrary but low idle baseline — strategic should easily
        // clear it.
        let idle_floor = TIER_IDLE_FLOOR;
        assert!(
            trade_score > idle_floor,
            "10k trade (score {trade_score}) must beat idle baseline ({idle_floor})",
        );
    }

    #[test]
    fn unified_scorer_housekeeping_beats_strategic_when_cargo_onboard() {
        // A ship with 80% cargo on a balanced trader should prefer
        // sell_cargo to starting a 5k-credit trade run. Today's
        // waterfall has this invariant; scoring must preserve it.
        let p = crate::ai::personality::Personality::balanced_trader();
        let cargo_frac = 0.8_f32;
        let sell_score =
            (0.5 + cargo_frac * 0.5) * p.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        let trade_score = score_strategic(5_000, "trade_run", &p, false);
        assert!(
            sell_score > trade_score,
            "sell_cargo at 80% full (score {sell_score}) must beat 5k trade (score {trade_score})",
        );
    }

    #[test]
    fn replan_eligible_only_for_strategic_and_idle() {
        // Protect committed goals from mid-action replan.
        assert!(!is_replan_eligible("rest_crew"));
        assert!(!is_replan_eligible("refuel"));
        assert!(!is_replan_eligible("seek_retrofit"));
        assert!(!is_replan_eligible("sell_cargo"));
        // Combined delivery+retrofit is also committed — interrupting
        // mid-detour loses both the delivery and the retrofit.
        assert!(!is_replan_eligible("fulfill_delivery_with_retrofit"));
        // Same for combined trade_run+retrofit.
        assert!(!is_replan_eligible("trade_run_with_retrofit"));
        // Strategic + idle are fair game.
        assert!(is_replan_eligible("fulfill_delivery"));
        assert!(is_replan_eligible("fulfill_contract"));
        assert!(is_replan_eligible("fulfill_passenger_transport"));
        assert!(is_replan_eligible("trade_run"));
        assert!(is_replan_eligible("explore"));
        assert!(is_replan_eligible("idle"));
        assert!(is_replan_eligible("idle_seek_station"));
    }

    #[test]
    fn replan_ratio_requires_meaningful_improvement() {
        // Sanity check the threshold: a candidate must beat the
        // running plan by REPLAN_SCORE_RATIO (1.30) to interrupt.
        // Noise-level improvements (5-10%) don't trigger thrash.
        let current = 10.0_f32;
        let noise = 10.5_f32;       // +5%
        let solid_win = 14.0_f32;   // +40%
        assert!(noise < current * REPLAN_SCORE_RATIO);
        assert!(solid_win >= current * REPLAN_SCORE_RATIO);
    }

    #[test]
    fn unified_scorer_housekeeping_loses_to_critical_biological() {
        // A ship at 5% fuel with cargo onboard should still refuel
        // rather than chase a sale. Biological > housekeeping.
        let p = crate::ai::personality::Personality::balanced_trader();
        let fuel_urgency = (1.0 - 0.05 / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let refuel_score = fuel_urgency * p.safety.max(0.2) * TIER_BIO_WEIGHT;
        let sell_score = 1.0 * p.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        assert!(
            refuel_score > sell_score,
            "critical refuel (score {refuel_score}) must beat full-hold sell (score {sell_score})",
        );
    }

    #[test]
    fn fitting_set_swaps_slug_and_recomputes() {
        use crate::modules::Slot;

        let mut fit = ShipFitting::new_default();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t1"));
        assert!((fit.derived.speed_mult - 1.0).abs() < 1e-6);

        fit.set(Slot::Engine, Some("engine_t3"));
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t3"));
        assert!((fit.derived.speed_mult - 1.30).abs() < 1e-6);
        assert!((fit.derived.fuel_efficiency_mult - 0.90).abs() < 1e-6);
    }

    #[test]
    fn fitting_clear_slot_drops_to_neutral_mult() {
        use crate::modules::Slot;

        let mut fit = ShipFitting::new_default();
        fit.set(Slot::Engine, Some("engine_t3"));
        assert!(fit.derived.speed_mult > 1.0);
        // Clearing the slot removes the boost without penalising the
        // ship at the catalog layer — gameplay can layer a penalty on
        // top if it wants.
        fit.set(Slot::Engine, None);
        assert!((fit.derived.speed_mult - 1.0).abs() < 1e-6);
    }

    #[test]
    fn fitting_from_slugs_round_trips_valid_slugs() {
        use crate::modules::{Slot, NUM_SLOTS};
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_t2".into()),
            Some("cargo_bay_t2".into()),
            Some("sensors_t1".into()),
            Some("reactor_t1".into()),
            Some("comms_t1".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t2"));
        assert_eq!(fit.slot_slug(Slot::CargoBay), Some("cargo_bay_t2"));
        // Derived reflects the two tier-2 upgrades: 1.15 × 1.0 = 1.15
        // speed, 1.20 cargo mult.
        assert!((fit.derived.speed_mult - 1.15).abs() < 1e-6);
        assert!((fit.derived.cargo_capacity_mult - 1.20).abs() < 1e-6);
    }

    #[test]
    fn progression_levels_up_and_banks_point() {
        let mut p = ShipProgression::new();
        assert_eq!(p.level, 1);
        assert_eq!(p.retrofit_points, 0);

        // First threshold is 100 xp. 99 shouldn't level.
        assert_eq!(p.grant_xp(99), 0);
        assert_eq!(p.level, 1);
        assert_eq!(p.xp, 99);

        // 50 more → crosses 100, banks one point, leaves 49 xp.
        assert_eq!(p.grant_xp(50), 1);
        assert_eq!(p.level, 2);
        assert_eq!(p.retrofit_points, 1);
        assert_eq!(p.xp, 49);
        assert!(p.dirty);
    }

    #[test]
    fn progression_xp_cascades_multiple_levels() {
        let mut p = ShipProgression::new();
        // 600 xp from level 1: 100 → lvl2, 200 → lvl3, 300 → lvl4, no leftover.
        let gained = p.grant_xp(600);
        assert_eq!(gained, 3);
        assert_eq!(p.level, 4);
        assert_eq!(p.retrofit_points, 3);
        assert_eq!(p.xp, 0);
    }

    #[test]
    fn progression_stops_at_level_cap() {
        let mut p = ShipProgression::new();
        p.grant_xp(u32::MAX);
        assert_eq!(p.level, SHIP_LEVEL_CAP);
        // Points banked exactly equal levels gained past 1.
        assert_eq!(p.retrofit_points, SHIP_LEVEL_CAP - 1);
    }

    #[test]
    fn progression_spend_retrofit_point() {
        let mut p = ShipProgression::new();
        assert!(!p.spend_retrofit_point());
        p.retrofit_points = 2;
        assert!(p.spend_retrofit_point());
        assert_eq!(p.retrofit_points, 1);
        assert!(p.spend_retrofit_point());
        assert_eq!(p.retrofit_points, 0);
        assert!(!p.spend_retrofit_point());
    }

    fn yard(
        loc: &str,
        system: &str,
        slug: &str,
        qty: u32,
    ) -> (String, String, std::collections::HashMap<String, u32>) {
        let mut s: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
        s.insert(slug.into(), qty);
        (loc.into(), system.into(), s)
    }

    #[test]
    fn find_retrofit_opportunity_picks_first_upgradable_slot() {
        use crate::modules::Slot;
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("earth-station", "Sol", "engine_t2", 2)];
        let plan = find_retrofit_opportunity(&fit, &inventory, 50_000, "luna-base", "Sol").unwrap();
        assert_eq!(plan.slot, Slot::Engine);
        assert_eq!(plan.slug, "engine_t2");
        assert_eq!(plan.shipyard_location, "earth-station");
    }

    #[test]
    fn find_retrofit_opportunity_rejects_below_credit_reserve() {
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("earth-station", "Sol", "engine_t2", 2)];
        // 12k reserve - can't afford 8k engine_t2 AND keep reserve intact.
        assert!(find_retrofit_opportunity(&fit, &inventory, 15_000, "", "").is_none());
        assert!(find_retrofit_opportunity(&fit, &inventory, 50_000, "", "").is_some());
    }

    #[test]
    fn find_retrofit_opportunity_skips_slot_when_no_stock_and_tries_next() {
        use crate::modules::Slot;
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("mars-station", "Sol", "cargo_bay_t2", 1)];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "mars-station", "Sol").unwrap();
        assert_eq!(plan.slot, Slot::CargoBay);
    }

    #[test]
    fn find_retrofit_opportunity_none_when_fully_tiered() {
        use crate::modules::NUM_SLOTS;
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_t3".into()),
            Some("cargo_bay_t3".into()),
            Some("sensors_t3".into()),
            Some("reactor_t3".into()),
            Some("comms_t3".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        let inventory = vec![yard("anywhere", "Sol", "engine_t3", 5)];
        assert!(find_retrofit_opportunity(&fit, &inventory, 100_000, "", "").is_none());
    }

    #[test]
    fn find_retrofit_opportunity_prefers_same_location() {
        let fit = ShipFitting::new_default();
        // Same slug in two yards; ship is at earth-station, so
        // earth-station should win over haven-station.
        let inventory = vec![
            yard("haven-station", "Alpha Centauri", "engine_t2", 3),
            yard("earth-station", "Sol", "engine_t2", 1),
        ];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "earth-station", "Sol").unwrap();
        assert_eq!(plan.shipyard_location, "earth-station");
    }

    #[test]
    fn find_retrofit_opportunity_prefers_same_system_when_not_at_a_yard() {
        let fit = ShipFitting::new_default();
        // Ship is at anvil-depot (Tau Ceti). Same-system Anvil yard
        // vs cross-gate Earth yard — Anvil should win.
        let inventory = vec![
            yard("earth-station", "Sol", "engine_t2", 5),
            yard("anvil-depot", "Tau Ceti", "engine_t2", 1),
        ];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "anvil-depot", "Tau Ceti").unwrap();
        assert_eq!(plan.shipyard_location, "anvil-depot");
    }

    #[test]
    fn new_for_size_tiny_small_medium_gets_tier1_sensors() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        for sz in [ShipSize::Tiny, ShipSize::Small, ShipSize::Medium] {
            let fit = ShipFitting::new_for_size(sz, "ship-test");
            let slug = fit.slot_slug(Slot::Sensors).unwrap();
            assert_eq!(get(slug).unwrap().tier, 1, "size {:?}", sz);
        }
    }

    #[test]
    fn new_for_size_huge_and_massive_always_get_tier2_sensors() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        for sz in [ShipSize::Huge, ShipSize::Massive] {
            // Any ship id should yield tier-2 sensors.
            for id in ["ship-a", "ship-zzz", "whatever"] {
                let fit = ShipFitting::new_for_size(sz, id);
                let slug = fit.slot_slug(Slot::Sensors).unwrap();
                assert_eq!(
                    get(slug).unwrap().tier,
                    2,
                    "{:?} ship {} should have tier-2 sensors",
                    sz,
                    id,
                );
            }
        }
    }

    #[test]
    fn new_for_size_large_rolls_deterministically_and_mixes() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        let mut tier1 = 0;
        let mut tier2 = 0;
        for i in 0..40 {
            let id = format!("ship-fleet-{:03}", i);
            let fit = ShipFitting::new_for_size(ShipSize::Large, &id);
            let tier = get(fit.slot_slug(Slot::Sensors).unwrap())
                .unwrap()
                .tier;
            match tier {
                1 => tier1 += 1,
                2 => tier2 += 1,
                _ => panic!("unexpected tier"),
            }
            // Same id → same result every call (deterministic roll).
            let again = ShipFitting::new_for_size(ShipSize::Large, &id);
            assert_eq!(fit.slot_slug(Slot::Sensors), again.slot_slug(Slot::Sensors));
        }
        assert!(tier1 > 0 && tier2 > 0, "large roll should mix across 40 ships (got t1={} t2={})", tier1, tier2);
    }

    #[test]
    fn find_retrofit_opportunity_falls_back_when_no_local_match() {
        let fit = ShipFitting::new_default();
        // Ship in Sol, engine_t2 only stocked in Tau Ceti — still
        // picks it (cross-system retrofit beats no retrofit).
        let inventory = vec![yard("anvil-depot", "Tau Ceti", "engine_t2", 1)];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "earth-station", "Sol").unwrap();
        assert_eq!(plan.shipyard_location, "anvil-depot");
    }

    #[test]
    fn fitting_from_slugs_falls_back_to_default_on_unknown() {
        use crate::modules::{Slot, NUM_SLOTS};
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_mystery_xyz".into()), // unknown slug
            Some("cargo_bay_t1".into()),
            Some("sensors_t1".into()),
            Some("reactor_t1".into()),
            Some("comms_t1".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        // Unknown slug falls back to the tier-1 default — rehydration
        // from a stale DB row never yields an empty engine.
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t1"));
    }
}
