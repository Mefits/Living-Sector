//! Facility components + tick logic.
//!
//! Component definitions, snapshot wire types, and small
//! per-facility helpers live in [`components`]. This file owns the
//! tick passes (recipes + mining, crew, condition decay,
//! self-repair, abandonment, restock, contract posting) that hecs
//! drives each engine tick.

mod components;
mod restock;
pub use components::*;

use crate::economy::commodities::Commodity;
use bevy_ecs::prelude::{Entity, World};

// ============================================================================
// Facility tick
// ============================================================================
//
// Each tick (on an interval) the facility:
//   1. Executes any recipes available for its facility_type against the
//      local market's supply (pulls inputs, pushes outputs).
//   2. If a mining_rig, extracts resources from its celestial body into
//      the local market supply.
//
// Recipes operate directly on market supply (source of truth) rather than
// a separate facility-reserves ledger — simpler and the Elixir model does
// the same effectively.

use crate::agents::celestial_body::{BodyIdentity, BodyResources};
use crate::agents::market::{MarketIdentity, MarketPricing};
use crate::economy::recipes;

/// How often facilities run recipes. Base ticks at 1x world speed = 5 ticks.
/// At default 0.25 speed (mult=32) this is every 160 ticks (~20s).
pub const RECIPE_INTERVAL_BASE: u64 = 5;
pub const MINING_INTERVAL_BASE: u64 = 5;

/// Max batches a facility can run in a single cycle. Prevents one refinery
/// from draining all ore in one tick.
pub const RECIPE_MAX_BATCHES: u32 = 20;

/// Mining yield per cycle = body_resource_richness × RESOURCE_YIELD_PER_TICK
/// Units of commodity added to market supply per cycle.
pub const MINING_YIELD_PER_CYCLE: f32 = 80.0;

/// Salvage fields are slower but can recycle ore, ice, gas and scrap
/// metals from a finite cache of wreckage. Their output multiplier is
/// one third of a normal extractor operating at equal richness.
pub const SALVAGE_SPEED_DIVISOR: f32 = 3.0;
/// Physical stock units represented by one unit of salvage richness.
/// A field starts with a fractional richness per material; every
/// salvaged unit reduces that stored richness, which is persisted in
/// the existing celestial-body resources column.
pub const SALVAGE_UNITS_PER_RICHNESS: f32 = 8_000.0;

/// Calculate one finite salvage draw from body richness. No input stock
/// means no output; the returned richness only decreases.
pub fn salvage_extraction(richness: f32, efficiency: f32) -> (f32, f32) {
    let available = richness.clamp(0.0, 1.0) * SALVAGE_UNITS_PER_RICHNESS;
    if available <= 0.0 || efficiency <= 0.0 {
        return (0.0, available / SALVAGE_UNITS_PER_RICHNESS);
    }
    let mut extracted = (MINING_YIELD_PER_CYCLE / SALVAGE_SPEED_DIVISOR)
        * richness.max(0.0) * efficiency;
    extracted = extracted.min(available);
    let remainder = available - extracted;
    // Sweep the last fractional unit rather than leaving an immortal
    // vanishingly small deposit at floating-point precision.
    if remainder < 1.0 {
        extracted = available;
    }
    let remaining = (available - extracted) / SALVAGE_UNITS_PER_RICHNESS;
    (extracted, remaining.max(0.0))
}

// --- Phase 11c: condition / restock / contracts / leveling / abandonment ---

/// Per-tick condition loss. Matches Elixir `0.0002 * tick_scale`.
pub const CONDITION_DEGRADE_PER_TICK: f32 = 0.0002;
/// Condition below this invites self-repair if tools available.
pub const CONDITION_REPAIR_THRESHOLD: f32 = 0.8;
/// Condition bump per tool consumed during self-repair.
pub const CONDITION_REPAIR_PER_TOOL: f32 = 0.01;
/// Interval (base-ticks) at which self-repair runs. Every 20×mult ticks.
pub const REPAIR_INTERVAL_BASE: u64 = 20;

// --- Phase 19a: facility crew complement ---

/// Fractional food units drawn from reserves per crew per base-tick.
/// Intentionally tiny — at ~90 facilities × ~10 crew average, this
/// nets to roughly 18 food/tick fleet-wide, vs ~300/tick from
/// populations. Facility crew is < 10% of total food demand.
pub const FOOD_PER_CREW_TICK: f32 = 0.02;

/// Hunger rise per base-tick (per crew). Crew hits the morale-hit
/// threshold (60) after ~200 ticks unfed at tick_scale=1, so a
/// facility can coast briefly through a food shortage without
/// immediately tanking production.
pub const CREW_HUNGER_RATE_PER_TICK: f32 = 0.3;

/// Hunger above this causes morale to slip each tick. Below it,
/// crew is content and morale drifts back toward full.
pub const HUNGER_MORALE_HIT_THRESHOLD: f32 = 60.0;

/// How fast morale moves each tick toward its target (either a
/// hunger-driven sag or a fed-crew recovery). Matches the pace of
/// ship-crew morale math loosely — recovery should be slower than
/// decay so "starving → fed" doesn't instantly snap production back.
pub const CREW_MORALE_HUNGRY_DECAY: f32 = 0.8;
pub const CREW_MORALE_RECOVERY: f32 = 0.3;

/// Morale at or below this emits the `facility_crew_starving` event.
/// Used only for UI signaling; the gameplay drag happens through
/// `efficiency()` continuously.
pub const CREW_STARVING_MORALE: f32 = 30.0;

/// Hunger reduction per meal successfully eaten. Crew eats one
/// "meal" whenever `food_debt` accumulates to ≥ 1 and there's food
/// in reserves. Meal size aligns with FOOD_PER_CREW_TICK so a fed
/// facility runs at hunger ≈ 0.
pub const CREW_MEAL_HUNGER_DECREASE: f32 = 20.0;

/// Interval (base-ticks) between crew morale checks + food draws.
/// Ties into the existing facility-tick cadence — cheap enough to
/// run every 5 base-ticks so the morale curve is smooth.
pub const FACILITY_CREW_TICK_INTERVAL_BASE: u64 = 5;

/// Reserve floor below which the restock phase tries to top up.
pub const RESERVE_RESTOCK_THRESHOLD: f32 = 100.0;
/// Reserve ceiling the restock phase targets (caps restock quantity).
pub const RESERVE_RESTOCK_TARGET: f32 = 500.0;
/// Interval (base-ticks) between restock passes.
pub const RESTOCK_INTERVAL_BASE: u64 = 20;
/// Commodities a facility tries to keep in reserve. Elixir stores fuel /
/// food / tools / water as the crew-essentials set.
pub const RESTOCK_COMMODITIES: &[Commodity] = &[
    Commodity::Fuel,
    Commodity::Food,
    Commodity::Tools,
    Commodity::Water,
];

/// Recipe input commodities a facility posts *market-supply* delivery
/// contracts for (distinct from `RESTOCK_COMMODITIES`, which are for the
/// facility's own reserves). Keyed by `facility_type`. When the local
/// market has been chronically short on one of these — meaning the
/// facility's recipes are starving — the facility posts a delivery
/// contract to pull supply in from elsewhere. Without this, mining
/// outputs pile up at the source but never reach the refiners/factories
/// that need them, and the upper-tier supply chain collapses.
///
/// Mining rigs aren't listed — they produce, not consume.
pub fn recipe_input_commodities(facility_type: &str) -> Vec<Commodity> {
    let mut inputs = Vec::new();
    for recipe in recipes::for_facility_type(facility_type) {
        for &(commodity, _) in recipe.inputs {
            if !inputs.contains(&commodity) { inputs.push(commodity); }
        }
    }
    inputs
}

/// Interval (base-ticks) between contract-posting passes. Every 50×mult.
pub const CONTRACT_POST_INTERVAL_BASE: u64 = 50;
/// Max delivery contracts a facility can have posted at once. Bumped from
/// 2 → 4 when we added recipe-input contracts on top of crew-essential
/// contracts — otherwise refineries hit the cap posting ore and can't
/// post fuel/food contracts too.
pub const MAX_ACTIVE_DELIVERIES_PER_FACILITY: usize = 4;
/// Contract lifespan (base ticks) before Expired. Matches Elixir's 500×mult.
/// Phase 18j: trimmed from 500 → 300 so unaccepted contracts churn
/// out the board faster and get re-posted at a fresh age-escalated
/// premium. Shorter churn + payment escalation together push the
/// fleet toward actually fulfilling supply-chain deliveries
/// instead of letting prices pin at ceiling while contracts
/// expire unclaimed.
pub const FACILITY_DELIVERY_LIFESPAN_BASE: u64 = 300;
/// Baseline delivery contract quantity. Facilities now scale up from
/// this when the triggering shortage has persisted (Bundle 1.3) —
/// shallow shortages still get ~50-unit contracts that couriers can
/// handle; deep / sustained shortages get larger orders that reward
/// bigger hulls with a single trip instead of many small ones.
pub const DELIVERY_CONTRACT_QTY: u32 = 50;
/// Floor on delivery contract qty (Bundle 1.3). Even if affordability
/// caps the order size, we never post a contract below this because
/// sub-25 quantities under-price transit/gate-fuel overhead.
pub const MIN_DELIVERY_CONTRACT_QTY: u32 = 25;
/// Ceiling on delivery contract qty (Bundle 1.3). 200 units fits a
/// medium freighter in one trip and matches the top of typical ship
/// cargo capacities. Caps pathological quantities during extreme
/// shortages that would otherwise exclude every ship in the fleet.
pub const MAX_DELIVERY_CONTRACT_QTY: u32 = 200;
/// Bucket size for shortage-driven qty scaling. Every extra
/// `SHORTAGE_QTY_BUCKET_TICKS` beyond the 30-tick trigger adds 25 units
/// to the requested quantity, so a 30-tick shortage → ~50 units, a
/// 90-tick shortage → ~100 units, a 200-tick shortage → ~175 units.
pub const SHORTAGE_QTY_BUCKET_TICKS: u32 = 30;

/// Bundle 1.3: scale delivery contract quantity by how long the
/// triggering shortage has persisted. `shortage_ticks` is 0 when
/// supply is healthy and grows while the market is short, so a deeper
/// / older shortage yields a larger order. Clamped to
/// `[MIN_DELIVERY_CONTRACT_QTY, MAX_DELIVERY_CONTRACT_QTY]`.
pub fn delivery_qty_for_shortage(shortage_ticks: u32) -> u32 {
    let bonus = shortage_ticks
        .saturating_sub(30)
        .saturating_div(SHORTAGE_QTY_BUCKET_TICKS)
        .saturating_mul(25);
    DELIVERY_CONTRACT_QTY
        .saturating_add(bonus)
        .clamp(MIN_DELIVERY_CONTRACT_QTY, MAX_DELIVERY_CONTRACT_QTY)
}
/// Base payment-per-unit floor. The real payment for a contract is
/// `max(QTY × BASE, src_price × QTY × delivery_multiplier)` — the flat
/// floor only wins when source prices are unusually cheap. Tuned to 40
/// so a commodity at the price floor (1.0) still produces a reasonable
/// 2k-cr contract.
pub const DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT: i64 = 40;
/// How much shortage a market needs to show before the facility's
/// recipe-input contract fires. Lower than the crew-essentials threshold
/// because refinery starvation cascades into the tier-2/tier-3 supply
/// chain quickly; we want to react before the chain breaks.
pub const RECIPE_INPUT_SHORTAGE_THRESHOLD: u32 = 15;

/// Facility XP threshold multiplier (level × 100) — see `next_level_threshold`.
pub const FACILITY_LEVEL_CAP: u8 = 10;
/// XP granted per recipe batch executed. Elixir: +recipe_count per tick.
pub const FACILITY_XP_PER_RECIPE: u32 = 1;

/// Interval (base-ticks) for crew-mission posting attempts. Matches
/// Elixir's `maybe_post_crew_missions` cadence (one shot per facility
/// tick pass, gated by a probability check).
pub const CREW_MISSION_POST_INTERVAL_BASE: u64 = 100;
/// Fraction of facilities that post a crew mission per cycle. Keeps the
/// board from being flooded with short-burst mission fodder.
pub const CREW_MISSION_POST_PROBABILITY: f32 = 0.25;
/// Max active crew missions per facility. Elixir uses 1.
pub const CREW_MISSION_MAX_ACTIVE_PER_FACILITY: usize = 1;

/// Interval (base-ticks) for abandonment-check bumps.
pub const ABANDON_CHECK_INTERVAL_BASE: u64 = 10;

/// Interval (base-ticks) between shipyard module-production passes.
/// Chosen so that at `WORLD_SPEED=4` (mult=2) a shipyard can top up a
/// module slot inside a 30s smoke, and at default 0.25 (mult=32)
/// produces modules at a slower, harder-to-stack cadence — aligns
/// with the "retrofit is rare" design intent.
pub const MODULE_PRODUCTION_INTERVAL_BASE: u64 = 15;
/// Ticks of triple-failure (low condition + no tools + low credits) before
/// the facility flips to `abandoned = true`. Matches Elixir's `200`.
pub const FACILITY_ABANDON_THRESHOLD_TICKS: u32 = 200;

/// Type alias for the facility LOD gate — matches the ship-side one
/// (`ShipLodGate`). `Entity → skipped_ticks`. Entities not in the
/// map should skip this tick's heaviest sub-phases.
pub type FacilityLodGate = std::collections::HashMap<Entity, u32>;

/// Bundle 1.5: build the facility LOD gate for this tick. Advances
/// each facility's own `AgentLod` cursor (ship-side passes are now
/// filtered to ship entities, so facility cursors belong to us
/// here). Facilities without an `AgentLod` default to "fires every
/// tick, skipped=1" so missing-component fallback matches the ship
/// behaviour.
fn build_facility_lod_gate(world: &mut World, tick: u64) -> FacilityLodGate {
    use crate::simulation::lod::AgentLod;
    let fac_with_lod: std::collections::HashSet<Entity> = {
        let mut q = world.query::<(Entity, &FacilityIdentity, &AgentLod)>();
        q.iter(&world).map(|(e, _, _)| e).collect()
    };
    let mut gate: FacilityLodGate = std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<(Entity, &mut AgentLod)>();
        for (e, mut lod) in lod_q.iter_mut(world) {
            if !fac_with_lod.contains(&e) {
                continue;
            }
            if let Some(skipped) = lod.try_fire(tick) {
                gate.insert(e, skipped);
            }
        }
    }
    // Fallback: facilities without an AgentLod fire every tick.
    let fac_no_lod: Vec<Entity> = {
        let mut q = world.query::<(Entity, &FacilityIdentity)>();
        q.iter(&world)
            .map(|(e, _)| e)
            .filter(|e| !fac_with_lod.contains(e))
            .collect()
    };
    for e in fac_no_lod {
        gate.insert(e, 1);
    }
    gate
}

pub fn tick_facilities(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    tick_facilities_with_relations(
        world, contracts, events,
        &crate::agents::faction_relations::FactionRelations::new(),
        tick, tick_scale, tick_multiplier,
    );
}

/// Used by the live server; ordinary contracts may trade with neutral
/// factions, never with a Hostile or War faction.
pub fn tick_facilities_with_relations(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    events: &mut Vec<serde_json::Value>,
    relations: &crate::agents::faction_relations::FactionRelations,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let mult = tick_multiplier as u64;
    let recipe_interval = RECIPE_INTERVAL_BASE * mult;
    let mining_interval = MINING_INTERVAL_BASE * mult;
    let repair_interval = REPAIR_INTERVAL_BASE * mult;
    let restock_interval = RESTOCK_INTERVAL_BASE * mult;
    let contract_interval = CONTRACT_POST_INTERVAL_BASE * mult;
    let abandon_interval = ABANDON_CHECK_INTERVAL_BASE * mult;

    // Bundle 1.5: LOD gate so off-screen facilities skip the heavy
    // sub-phases on most ticks. Built once per tick, consumed by
    // tick_recipes_and_mining for now; remaining sub-phases (restock
    // / condition / abandonment / contract-post) stay on their
    // existing global intervals because they're cheap per-facility.
    // Rate-scaling of recipe output per divisor is deferred — for
    // now off-screen facilities produce ~1/divisor of their
    // on-screen throughput, which is acceptable since the player
    // isn't looking.
    let facility_lod_gate = build_facility_lod_gate(world, tick);

    // Phase 1: condition degrade (every tick; cheap — one field write).
    tick_degrade_condition(world, tick_scale);

    // Phase 1a: dock-queue sweep. Purges entries whose ship has left
    // (location_name != this facility's location) or has been
    // despawned. Runs every 10×mult ticks — frequent enough to keep
    // queues responsive but cheap (one query + a short per-facility
    // retain). Without this, a ship that departs without docking
    // leaves a zombie at the head and every ship behind it starves.
    let queue_sweep_interval = 10 * mult;
    if queue_sweep_interval > 0 && tick % queue_sweep_interval == 0 {
        tick_dock_queue_sweep(world);
    }

    // Phase 1b (Phase 19a): crew complement — food draw, hunger,
    // morale. Runs on its own 5×mult cadence so the morale curve
    // is smooth without hammering the tick loop every frame.
    let crew_interval = FACILITY_CREW_TICK_INTERVAL_BASE * mult;
    if crew_interval > 0 && tick % crew_interval == 0 {
        tick_facility_crew(world, events, tick_scale, tick_multiplier);
    }

    // Phase 2: self-repair (every 20×mult ticks).
    if repair_interval > 0 && tick % repair_interval == 0 {
        tick_self_repair(world);
    }

    // Phase 3: abandonment check (every 10×mult ticks).
    if abandon_interval > 0 && tick % abandon_interval == 0 {
        tick_abandonment(world, events);
    }

    // Phase 4: restock reserves from local market (every 20×mult ticks).
    if restock_interval > 0 && tick % restock_interval == 0 {
        restock::tick_restock(world, relations);
    }

    // Phase 5: recipes + mining + XP (every 5×mult ticks).
    if tick % recipe_interval == 0 || tick % mining_interval == 0 {
        tick_recipes_and_mining(world, tick, tick_multiplier, &facility_lod_gate);
    }

    // Phase 6: post delivery + courier contracts (every 50×mult ticks).
    if contract_interval > 0 && tick % contract_interval == 0 {
        tick_post_contracts_with_relations(world, contracts, relations, tick, tick_multiplier);
    }

    // Phase 6b (Phase 18c): shipyards mint modules from local market
    // supply into their `ModuleStock`. Runs on its own interval —
    // decoupled from recipe_interval so module cadence is a separate
    // tuning knob.
    let module_production_interval = MODULE_PRODUCTION_INTERVAL_BASE * mult;
    if module_production_interval > 0 && tick % module_production_interval == 0 {
        tick_produce_modules(world);
    }

    // Phase 7: post crew missions (every 100×mult ticks, probabilistic).
    let crew_mission_interval = CREW_MISSION_POST_INTERVAL_BASE * mult;
    if crew_mission_interval > 0 && tick % crew_mission_interval == 0 {
        tick_post_crew_missions(world, contracts, tick, tick_multiplier);
    }
}

/// Phase 1: condition drifts down every tick. Abandoned facilities are
/// already dead and skip this.
fn tick_degrade_condition(world: &mut World, tick_scale: f32) {
    let delta = CONDITION_DEGRADE_PER_TICK * tick_scale;
    let mut q = world.query::<(&mut FacilityOperations, &FacilityLifecycle)>();
    for (mut ops, life) in q.iter_mut(world) {
        if life.abandoned {
            continue;
        }
        ops.condition = (ops.condition - delta).max(0.0);
    }
}

/// Phase 19a: crew complement tick — food consumption, hunger,
/// morale. Runs every `FACILITY_CREW_TICK_INTERVAL_BASE × mult`
/// ticks. Abandoned facilities skip (no one's home).
///
/// ## Flow per facility
///
/// 1. **Hunger** climbs by `CREW_HUNGER_RATE_PER_TICK × interval ×
///    tick_scale` (higher world-speed = hunger rises faster).
/// 2. **Food debt** accumulates at `crew_count × FOOD_PER_CREW_TICK
///    × interval`. Integer food units are deducted from reserves
///    whenever debt ≥ 1.0; successful deductions trim `hunger` via
///    `CREW_MEAL_HUNGER_DECREASE / crew_count` so larger crews eat
///    proportionally more to feel full.
/// 3. **Morale** drifts toward its target: well-fed crews
///    (`hunger < HUNGER_MORALE_HIT_THRESHOLD`) recover toward 100;
///    hungry crews lose morale. Both movements use the interval so
///    cadence is tick-scale-independent.
///
/// The crew's `efficiency()` is read by `tick_recipes_and_mining`
/// on its own interval and multiplies into recipe output + mining
/// yield.
/// Dock-queue sweep — runs on a slow cadence inside `tick_facilities`.
/// Each facility's queue is trimmed to entries whose ship is (a) still
/// at this facility's location AND (b) actively attempting a dock
/// right now (`dock_attempt_start_tick.is_some()`).
///
/// The second check catches phantom queue entries: when
/// `ShipAction::Dock` times out it returns Failure + clears
/// `dock_attempt_start_tick` but doesn't pop itself from any queue.
/// If the ship's BT unwinds into a new goal at the same location
/// (rest, sell cargo, retry a different contract from here) the
/// location-match alone keeps the phantom in the queue, blocking
/// every ship behind it indefinitely. Diagnostic on 2026-04-24 saw
/// luna-base with 0 docked and 2 queued against capacity 25 — pure
/// phantoms. Real ships can't get in because the queue head isn't
/// actually trying to dock anymore.
fn tick_dock_queue_sweep(world: &mut World) {
    use crate::agents::ship::{ShipEconomy, ShipPosition};
    // Collect facility (entity, location_string) up front so we can
    // check ship positions without double-borrowing the world.
    let facilities: Vec<(Entity, String)> = {
        let mut q = world.query::<(Entity, &FacilityLocation, &FacilityStorage)>();
        q.iter(&world)
            .filter(|(_, _, s)| !s.dock_queue.is_empty())
            .map(|(e, loc, _)| (e, loc.location_name.clone()))
            .collect()
    };
    for (entity, loc_name) in facilities {
        let queue_snapshot = match world.get::<FacilityStorage>(entity) {
            Some(s) => s.dock_queue.clone(),
            None => continue,
        };
        let mut keep: Vec<Entity> = Vec::with_capacity(queue_snapshot.len());
        for e in queue_snapshot {
            let still_here = world
                .get::<ShipPosition>(e)
                .map(|p| p.location_name.as_deref() == Some(loc_name.as_str()))
                .unwrap_or(false);
            if !still_here {
                continue;
            }
            let still_trying = world
                .get::<ShipEconomy>(e)
                .map(|econ| econ.dock_attempt_start_tick.is_some())
                .unwrap_or(false);
            if !still_trying {
                continue;
            }
            keep.push(e);
        }
        if let Some(mut storage) = world.get_mut::<FacilityStorage>(entity) {
            if storage.dock_queue.len() != keep.len() {
                storage.dock_queue = keep;
            }
        }
    }
}

fn tick_facility_crew(
    world: &mut World,
    events: &mut Vec<serde_json::Value>,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let interval = (FACILITY_CREW_TICK_INTERVAL_BASE * tick_multiplier as u64) as f32;
    let hunger_delta = CREW_HUNGER_RATE_PER_TICK * interval * tick_scale;

    // Need the identity/location for starving events — collect here
    // rather than querying again later so we don't fight hecs borrows.
    let mut q = world.query::<(
        &FacilityIdentity,
        &FacilityLocation,
        &mut FacilityCrew,
        &mut FacilityStorage,
        &FacilityLifecycle,
    )>();
    for (identity, loc, mut crew, mut storage, life) in q.iter_mut(world) {
        if life.abandoned || crew.crew_count == 0 {
            continue;
        }
        let before_morale = crew.morale;

        // Hunger rises uniformly per tick.
        crew.hunger = (crew.hunger + hunger_delta).clamp(0.0, 100.0);

        // Accumulate fractional food draw. Crew eats whole food units
        // from reserves only when the debt crosses 1.0, so the integer
        // reserves math stays clean even at 0.02/crew/tick.
        crew.food_debt += crew.crew_count as f32 * FOOD_PER_CREW_TICK * interval;
        while crew.food_debt >= 1.0 {
            let food = storage.reserves.entry(Commodity::Food).or_insert(0.0);
            if *food >= 1.0 {
                *food -= 1.0;
                crew.food_debt -= 1.0;
                // Per-meal hunger relief — scaled down for large crews
                // so 20 crew eating 20 food/tick doesn't all-clear
                // hunger from one meal. In practice debt-driven meals
                // at steady state keep hunger pinned near 0.
                let relief = CREW_MEAL_HUNGER_DECREASE / (crew.crew_count as f32).max(1.0);
                crew.hunger = (crew.hunger - relief).max(0.0);
            } else {
                // No food in reserves — leave debt accumulated so
                // the next tick with food will catch up.
                break;
            }
        }

        // Morale — hungry crews decay, fed crews recover.
        let morale_target = if crew.hunger > HUNGER_MORALE_HIT_THRESHOLD {
            0.0
        } else {
            100.0
        };
        let rate = if morale_target < crew.morale {
            CREW_MORALE_HUNGRY_DECAY
        } else {
            CREW_MORALE_RECOVERY
        };
        let step = rate * interval;
        if morale_target < crew.morale {
            crew.morale = (crew.morale - step).max(morale_target);
        } else if morale_target > crew.morale {
            crew.morale = (crew.morale + step).min(morale_target);
        }
        crew.morale = crew.morale.clamp(0.0, 100.0);

        // Emit a one-shot `facility_crew_starving` event only when
        // morale CROSSES the starving threshold going down. Tracking
        // the prior value avoids spamming the ticker every crew-tick
        // while morale hovers in the danger zone.
        if before_morale > CREW_STARVING_MORALE && crew.morale <= CREW_STARVING_MORALE {
            events.push(serde_json::json!({
                "kind": "facility_crew_starving",
                "facility_id": identity.id,
                "location": loc.location_name,
                "facility_type": identity.facility_type,
                "crew_count": crew.crew_count,
                "morale": crew.morale,
            }));
        }

        let changed = (crew.morale - before_morale).abs() > f32::EPSILON
            || crew.hunger > 0.0
            || crew.food_debt > 0.0;
        if changed {
            crew.dirty = true;
        }
    }
}

/// Phase 2: consume one Tool to bump condition. Only if condition is
/// already below REPAIR_THRESHOLD and reserves[Tools] > 0. Matches Elixir
/// `facility_agent.ex:maybe_self_repair`.
fn tick_self_repair(world: &mut World) {
    let mut q = world.query::<(
        &mut FacilityOperations,
        &mut FacilityStorage,
        &mut FacilityLifecycle,
    )>();
    for (mut ops, mut storage, mut life) in q.iter_mut(world) {
        if life.abandoned || ops.condition >= CONDITION_REPAIR_THRESHOLD {
            continue;
        }
        let tools = storage.reserves.get(&Commodity::Tools).copied().unwrap_or(0.0);
        if tools < 1.0 {
            continue;
        }
        *storage.reserves.entry(Commodity::Tools).or_insert(0.0) = (tools - 1.0).max(0.0);
        ops.condition = (ops.condition + CONDITION_REPAIR_PER_TOOL).min(1.0);
        ops.dirty = true;
        life.dirty = true;
    }
}

/// Phase 3: advance abandonment countdown. A facility is "dying" if
/// condition < 0.1 AND no tools AND credits < 100. Hold the dying state
/// for ABANDON_THRESHOLD_TICKS and it flips to `abandoned`. Any recovery
/// (tools restock, credits returning, repair) resets the counter.
fn tick_abandonment(
    world: &mut World,
    events: &mut Vec<serde_json::Value>,
) {
    let mut q = world.query::<(
        &FacilityIdentity,
        &FacilityLocation,
        &FacilityOperations,
        &FacilityStorage,
        &mut FacilityLifecycle,
    )>();
    for (identity, loc, ops, storage, mut life) in q.iter_mut(world) {
        if life.abandoned {
            continue;
        }
        let tools = storage.reserves.get(&Commodity::Tools).copied().unwrap_or(0.0);
        let dying = ops.condition < 0.1 && tools < 1.0 && ops.credits < 100;
        if dying {
            let was_below = life.abandon_counter;
            life.abandon_counter = life.abandon_counter.saturating_add(1);
            if life.abandon_counter >= FACILITY_ABANDON_THRESHOLD_TICKS && !life.abandoned {
                life.abandoned = true;
                // One-shot event on the exact tick that flips abandoned
                // true — threshold crossing, not every tick below.
                events.push(serde_json::json!({
                    "kind": "facility_abandoned",
                    "facility_id": identity.id,
                    "facility_type": identity.facility_type,
                    "location": loc.location_name,
                    "condition": ops.condition,
                    "credits": ops.credits,
                }));
            }
            life.dirty = true;
            let _ = was_below;
        } else if life.abandon_counter > 0 {
            life.abandon_counter = 0;
            life.dirty = true;
        }
    }
}

/// Phase 5: recipes + mining + XP. Runs every 5×mult ticks. Skips
/// abandoned facilities. Each recipe batch executed grants XP; crossing
/// the level × 100 threshold increments level (capped at
/// `FACILITY_LEVEL_CAP`) and boosts `max_batches` future runs via the
/// `level_scaled_max_batches` helper.
fn tick_recipes_and_mining(
    world: &mut World,
    tick: u64,
    tick_multiplier: u32,
    lod_gate: &FacilityLodGate,
) {
    let mult = tick_multiplier as u64;
    let recipe_interval = RECIPE_INTERVAL_BASE * mult;
    let mining_interval = MINING_INTERVAL_BASE * mult;

    // Location → market_entity and body_id → body_entity indexes.
    let market_at_location: std::collections::HashMap<String, Entity> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(&world)
            .map(|(e, id)| (id.facility_location.clone(), e))
            .collect()
    };
    let body_by_string_id: std::collections::HashMap<String, Entity> = {
        let mut q = world.query::<(Entity, &BodyIdentity)>();
        q.iter(&world)
            .map(|(e, id)| (id.body_id.clone(), e))
            .collect()
    };

    // Facility snapshot — include entity so we can update XP in place.
    #[derive(Clone)]
    struct FacilityInfo {
        entity: Entity,
        facility_type: String,
        location_name: String,
        body_id: String,
        level: u8,
        abandoned: bool,
    }
    let facilities: Vec<FacilityInfo> = {
        let mut q = world.query::<(Entity, &FacilityIdentity, &FacilityLocation, &FacilityLifecycle)>();
        q.iter(&world)
            .map(|(e, id, loc, life)| FacilityInfo {
                entity: e,
                facility_type: id.facility_type.clone(),
                location_name: loc.location_name.clone(),
                body_id: id.body_id.clone(),
                level: life.level,
                abandoned: life.abandoned,
            })
            .collect()
    };

    if tick % recipe_interval == 0 {
        for fac in &facilities {
            if fac.abandoned {
                continue;
            }
            // Bundle 1.5: LOD gate — off-screen facilities skip
            // recipes on ticks they aren't firing. No rate-scaling
            // yet; see comment in tick_facilities.
            if !lod_gate.contains_key(&fac.entity) {
                continue;
            }
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            // Phase 18e: fold the facility's FacilityFitting into the
            // recipe run. recipe_output_mult rides through `efficiency`
            // on `recipes::execute`; max_batches_bonus adds flat
            // capacity on top of the level-scaled base. Facilities
            // without a fitting (shouldn't happen post-Phase-18e spawn
            // but defend against hand-rolled DB rows) fall back to
            // neutral stats.
            let (output_mult_fitting, batches_bonus) = world
                .get::<FacilityFitting>(fac.entity)
                .map(|f| (f.derived.recipe_output_mult, f.derived.max_batches_bonus))
                .unwrap_or((1.0, 0));
            // Phase 19a: crew efficiency multiplies into the output
            // mult alongside fitting. Starving crew → half production.
            let crew_efficiency = world
                .get::<FacilityCrew>(fac.entity)
                .map(|c| c.efficiency())
                .unwrap_or(1.0);
            let output_mult = output_mult_fitting * crew_efficiency;
            let max_batches = level_scaled_max_batches(fac.level).saturating_add(batches_bonus);
            // Count recipes that actually produced output — XP only grows
            // when real work happens. Elixir increments XP by the number
            // of recipes that ran successfully each cycle.
            let mut recipes_run: u32 = 0;
            if let Some(mut pricing) = world.get_mut::<MarketPricing>(market_entity) {
                // Bundle (H): snapshot prices for the profitability
                // gate. Clone is cheap (HashMap<Commodity, f32>,
                // ~13 entries) and lets us keep the mutable supply
                // borrow below.
                let prices_snap = pricing.prices.clone();
                for recipe in recipes::for_facility_type(&fac.facility_type) {
                    let produced = recipes::execute(
                        recipe,
                        &mut pricing.supply,
                        output_mult,
                        max_batches,
                        Some(&prices_snap),
                    );
                    if !produced.is_empty() {
                        recipes_run += 1;
                    }
                }
            }
            if recipes_run > 0 {
                grant_facility_xp(world, fac.entity, recipes_run);
            }
        }
    }

    if tick % mining_interval == 0 {
        for fac in &facilities {
            if fac.abandoned
                || (fac.facility_type != "mining_rig"
                    && fac.facility_type != "salvage_field")
            {
                continue;
            }
            // Bundle 1.5: LOD gate for mining too.
            if !lod_gate.contains_key(&fac.entity) {
                continue;
            }
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            let body_entity = match body_by_string_id.get(&fac.body_id) {
                Some(&e) => e,
                None => continue,
            };
            let body_resources: Vec<(Commodity, f32)> =
                match world.get::<BodyResources>(body_entity) {
                    Some(r) => r.resources.iter().map(|(&c, &v)| (c, v)).collect(),
                    None => continue,
                };
            // Mining rigs honour the Production slot too — a tier-3
            // production module boosts extracted yield 1.3×. Phase 19a
            // also folds crew efficiency in: a starved mining crew
            // extracts half as much per cycle.
            let yield_fitting = world
                .get::<FacilityFitting>(fac.entity)
                .map(|f| f.derived.recipe_output_mult)
                .unwrap_or(1.0);
            let crew_efficiency = world
                .get::<FacilityCrew>(fac.entity)
                .map(|c| c.efficiency())
                .unwrap_or(1.0);
            let yield_mult = yield_fitting * crew_efficiency;
            let is_salvage = fac.facility_type == "salvage_field";
            let mut depleted: Vec<(Commodity, f32)> = Vec::new();
            if let Some(mut pricing) = world.get_mut::<MarketPricing>(market_entity) {
                for (commodity, richness) in body_resources {
                    if richness <= 0.0 {
                        continue;
                    }
                    let extracted = if is_salvage {
                        let (qty, new_richness) = salvage_extraction(richness, yield_mult);
                        depleted.push((commodity, new_richness));
                        qty
                    } else {
                        MINING_YIELD_PER_CYCLE * richness * yield_mult
                    };
                    *pricing.supply.entry(commodity).or_insert(0.0) += extracted;
                }
            }
            // Unlike legacy mining rigs, a salvage field owns a finite
            // physical cache. Only the removed units become market supply.
            // Body orbital writes persist the reduced resource fractions.
            if is_salvage {
                if let Some(mut body) = world.get_mut::<BodyResources>(body_entity) {
                    for (commodity, new_richness) in depleted {
                        if let Some(r) = body.resources.get_mut(&commodity) {
                            *r = r.min(new_richness).max(0.0);
                        }
                    }
                }
            }
        }
    }
}

/// Scale `RECIPE_MAX_BATCHES` by facility level. Level 1 → base; level 10 →
/// 2.9× base. Prevents a maxed-out factory from drowning the market in
/// one tick.
pub fn level_scaled_max_batches(level: u8) -> u32 {
    let lvl = level.clamp(1, FACILITY_LEVEL_CAP) as f32;
    ((RECIPE_MAX_BATCHES as f32) * (1.0 + (lvl - 1.0) * 0.2)).round() as u32
}

/// Grant XP to a facility; level up when `xp >= next_level_threshold`.
pub fn grant_facility_xp(world: &mut World, entity: Entity, batches: u32) {
    if let Some(mut life) = world.get_mut::<FacilityLifecycle>(entity) {
        if life.abandoned {
            return;
        }
        life.xp = life.xp.saturating_add(batches * FACILITY_XP_PER_RECIPE);
        while life.xp >= life.next_level_threshold() && life.level < FACILITY_LEVEL_CAP {
            life.xp -= life.next_level_threshold();
            life.level += 1;
            life.dirty = true;
        }
        life.dirty = true;
    }
}

/// Phase 6b (Phase 18c): shipyards mint modules from their local
/// market's supply.
///
/// Each shipyard iterates [`crate::economy::module_production::MODULE_RECIPES`],
/// skipping slugs already at `SHIPYARD_STOCK_TARGET`, and tries to
/// produce one unit of the first under-stock recipe whose inputs are
/// fully covered by the market supply. On success, inputs are consumed
/// from the market and stock is incremented. Stopping after one module
/// per tick keeps a single shipyard from hoovering the local
/// electronics/metals/components supply in a single phase — slower
/// cadence, more elastic market prices, retrofit stays a scarce event.
fn tick_produce_modules(world: &mut World) {
    use crate::economy::module_production::{
        consume_inputs, inputs_available, MODULE_RECIPES, SHIPYARD_STOCK_TARGET,
    };

    // Build a location → market_entity index once per call — same pattern
    // as tick_recipes_and_mining. Shipyards pull from their local
    // market's supply, NOT their own reserves, matching refinery/factory
    // behavior.
    let market_at_location: std::collections::HashMap<String, Entity> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(&world)
            .map(|(e, id)| (id.facility_location.clone(), e))
            .collect()
    };

    // Collect the shipyard (entity, location, abandoned) tuple so we can
    // mutate components without the query's borrow hanging around.
    struct ShipyardRef {
        entity: Entity,
        location: String,
    }
    let shipyards: Vec<ShipyardRef> = {
        let mut q = world.query::<(Entity, &FacilityIdentity, &FacilityLocation, &FacilityLifecycle)>();
        q.iter(&world)
            .filter_map(|(e, id, loc, life)| {
                if life.abandoned || id.facility_type != "shipyard" {
                    return None;
                }
                Some(ShipyardRef {
                    entity: e,
                    location: loc.location_name.clone(),
                })
            })
            .collect()
    };

    for yard in shipyards {
        let market_entity = match market_at_location.get(&yard.location) {
            Some(&e) => e,
            None => continue,
        };

        // Ensure the shipyard actually has a ModuleStock component.
        // We'd expect one on every shipyard (seeder/admin-spawn attach
        // it), but defend against hand-rolled DB rows that didn't.
        if world.get::<ModuleStock>(yard.entity).is_none() {
            world.entity_mut(yard.entity).insert(ModuleStock::default());
        }

        // Find the first under-stock recipe whose inputs are covered.
        // Walk recipes in catalog order so production distribution is
        // deterministic run-over-run.
        let chosen_slug: Option<&'static str> = {
            let pricing = match world.get::<MarketPricing>(market_entity) {
                Some(p) => p,
                None => continue,
            };
            let stock = match world.get::<ModuleStock>(yard.entity) {
                Some(s) => s,
                None => continue,
            };
            MODULE_RECIPES.iter().find_map(|recipe| {
                if stock.count(recipe.slug) >= SHIPYARD_STOCK_TARGET {
                    return None;
                }
                if inputs_available(recipe, &pricing.supply) {
                    Some(recipe.slug)
                } else {
                    None
                }
            })
        };

        let Some(slug) = chosen_slug else { continue };
        let recipe = match crate::economy::module_production::get(slug) {
            Some(r) => r,
            None => continue,
        };

        // Consume inputs from the market and bump stock.
        if let Some(mut pricing) = world.get_mut::<MarketPricing>(market_entity) {
            consume_inputs(recipe, &mut pricing.supply);
        }
        if let Some(mut stock) = world.get_mut::<ModuleStock>(yard.entity) {
            stock.add(slug, 1);
        }
    }
}

/// Phase 6: post delivery contracts when a commodity has been short for
/// long enough. Each facility posts at most `MAX_ACTIVE_DELIVERIES_PER_FACILITY`
/// contracts at a time. Source is left open (the ship planner looks at
/// price memory to pick where to buy). Payment scales with quantity.
pub fn tick_post_contracts(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u32,
) {
    tick_post_contracts_with_relations(
        world, contracts, &crate::agents::faction_relations::FactionRelations::new(),
        tick, tick_multiplier,
    );
}

pub fn tick_post_contracts_with_relations(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    relations: &crate::agents::faction_relations::FactionRelations,
    tick: u64,
    tick_multiplier: u32,
) {
    use crate::agents::market::MarketHistory;
    let lifespan = FACILITY_DELIVERY_LIFESPAN_BASE * tick_multiplier as u64;

    // Snapshot facility + market data to decide postings, then call the
    // mutable ContractBoard at the end.
    #[derive(Clone)]
    struct Plan {
        requestor_id: String,
        // Phase 19e: the facility's owning faction is tagged onto the
        // posted delivery so completing it awards +1 rep with that
        // faction. Without this, facility deliveries were all
        // faction-neutral and rep never grew organically (only subsidy
        // / crew mission deliveries carried a faction, and those are
        // rep-gated to begin with — a chicken-and-egg).
        faction_id: Option<String>,
        commodity: Commodity,
        destination: String,
        source: String,
        payment: i64,
        qty: u32,
    }

    impl ConvoyPlan for Plan {
        fn destination(&self) -> &str { &self.destination }
        fn commodity(&self) -> Commodity { self.commodity }
        fn qty(&self) -> u32 { self.qty }
        fn payment(&self) -> i64 { self.payment }
        fn requestor_id(&self) -> &str { &self.requestor_id }
        fn set_qty(&mut self, qty: u32) { self.qty = qty; }
        fn set_payment(&mut self, payment: i64) { self.payment = payment; }
    }

    // location → market_history for shortage lookup. Elixir's
    // shortage_ticks is a tick counter; we use u32 to match `MarketHistory`.
    let shortage_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, u32>> = {
        let mut q = world.query::<(&MarketIdentity, &MarketHistory)>();
        q.iter(&world)
            .map(|(id, hist)| (id.facility_location.clone(), hist.shortage_ticks.clone()))
            .collect()
    };
    let supply_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing)>();
        q.iter(&world)
            .map(|(id, pricing)| (id.facility_location.clone(), pricing.supply.clone()))
            .collect()
    };
    let price_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> = {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing)>();
        q.iter(&world)
            .map(|(id, pricing)| (id.facility_location.clone(), pricing.prices.clone()))
            .collect()
    };

    let source_owners = crate::agents::faction_relations::market_controllers(world);
    // Real stock must cover the planned delivery. Prefer own depots,
    // then any neutral/allied owner. At War/Hostile: no trade.
    let source_for_commodity = |commodity: Commodity,
                                destination: &str,
                                faction_id: &str,
                                qty: u32| -> Option<String> {
        let mut options: Vec<(&String, f32, bool)> = supply_by_location
            .iter()
            .filter_map(|(loc, sup)| {
                if loc == destination {
                    return None;
                }
                let owner = source_owners.get(loc).map(String::as_str).unwrap_or("");
                if !crate::agents::faction_relations::commerce_allowed(
                    relations, faction_id, owner,
                ) {
                    return None;
                }
                let stock = sup.get(&commodity).copied().unwrap_or(0.0);
                if !stock.is_finite() || stock < qty as f32 {
                    return None;
                }
                Some((loc, stock, owner == faction_id && !faction_id.is_empty()))
            })
            .collect();
        options.sort_by(|a,b| b.2.cmp(&a.2)
            .then_with(|| b.1.total_cmp(&a.1))
            .then_with(|| a.0.cmp(b.0)));
        options.first().map(|(loc,_,_)| (*loc).clone())
    };

    // Compute the payment the facility offers for a delivery contract.
    // Must be high enough that a ship's `buy_cost` at the CURRENT source
    // market price, plus gate fees, leaves a meaningful profit — otherwise
    // the ship planner's `cost >= payment` check rejects every contract
    // and nothing ever gets accepted. We take the MAX of:
    //   1. The flat base payment (`QTY × BASE_PAYMENT_PER_UNIT`).
    //   2. `src_price × QTY × delivery_multiplier` — covers the market
    //      cost of buying at source plus a 30% delivery premium.
    // Cap at what the facility can pay (else we'd post contracts we
    // can't honor).
    let compute_delivery_payment = |commodity: Commodity,
                                    source: &str,
                                    fac_credits: i64,
                                    qty: u32|
     -> i64 {
        let flat = (qty as i64) * DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT;
        let src_price = price_by_location
            .get(source)
            .and_then(|m| m.get(&commodity))
            .copied()
            .unwrap_or(0.0);
        let market_based =
            (src_price * qty as f32 * 1.3).round() as i64;
        flat.max(market_based).min(fac_credits)
    };

    let mut plans: Vec<Plan> = Vec::new();
    {
    let mut fac_q = world.query::<(
        &FacilityIdentity,
        &FacilityLocation,
        &FacilityLifecycle,
        &FacilityStorage,
        &FacilityOperations,
    )>();
    for (id, loc, life, storage, ops) in fac_q.iter(&world) {
        if life.abandoned {
            continue;
        }
        // Skip if facility already has too many active deliveries.
        let active = contracts
            .iter()
            .filter(|c| c.requestor_id == id.id)
            .filter(|c| {
                matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
            })
            .count();
        if active >= MAX_ACTIVE_DELIVERIES_PER_FACILITY {
            continue;
        }

        // Look at each tracked-reserve commodity. A facility posts a
        // delivery contract when BOTH its own reserve is critically low
        // AND the local market has been short for sustained ticks.
        let market_shortage = shortage_by_location
            .get(&loc.location_name)
            .cloned()
            .unwrap_or_default();

        // Minimum-qty affordability gate — if the facility can't
        // cover even a floor-sized contract at the flat base rate,
        // don't bother scaling by shortage.
        let can_afford = ops.credits
            >= (MIN_DELIVERY_CONTRACT_QTY as i64) * DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT;

        // --- Crew-essentials contracts (fuel/food/tools/water) ---
        // Fires when the facility's OWN RESERVES are low AND the local
        // market is chronically short, so docking ships can't refuel
        // either. Note: we DON'T early-exit after this cycle so a
        // refinery can post both a fuel-restock contract AND a recipe-
        // input contract in the same cycle (up to
        // `MAX_ACTIVE_DELIVERIES_PER_FACILITY`).
        if can_afford {
            for &commodity in RESTOCK_COMMODITIES {
                let reserve = storage.reserves.get(&commodity).copied().unwrap_or(0.0);
                if reserve >= RESERVE_RESTOCK_THRESHOLD {
                    continue;
                }
                let shortage: u32 = market_shortage.get(&commodity).copied().unwrap_or(0);
                // Phase 19f: urgency override for tools when the
                // facility is decaying. Condition < 0.8 triggers the
                // self-repair loop (consume 1 tool → +0.01 condition),
                // so running out of tools in that state is a death
                // spiral. Skip the normal 30-tick shortage wait — the
                // facility needs the tools yesterday.
                let urgent_tools = commodity == Commodity::Tools
                    && ops.condition < CONDITION_REPAIR_THRESHOLD
                    && reserve < 10.0;
                if !urgent_tools && shortage < 30 {
                    continue;
                }
                // Quote against the actual quantity rather than a
                // nominal minimum: don't post an undeliverable convoy.
                let qty = delivery_qty_for_shortage(shortage);
                let Some(source) = source_for_commodity(
                    commodity, &loc.location_name, &id.faction_id, qty,
                ) else {
                    continue;
                };
                let payment = compute_delivery_payment(commodity, &source, ops.credits, qty);
                if payment <= 0 {
                    continue;
                }
                plans.push(Plan {
                    requestor_id: id.id.clone(),
                    // Empty string = unowned ("independent"); treat as
                    // None so the rep grant on delivery no-ops rather
                    // than trying to +1 a bogus faction.
                    faction_id: if id.faction_id.is_empty() {
                        None
                    } else {
                        Some(id.faction_id.clone())
                    },
                    commodity,
                    destination: loc.location_name.clone(),
                    source,
                    payment,
                    qty,
                });
                break;
            }
        }

        // --- Recipe-input contracts (ore/gas/metals/polymers/...) ---
        // For producer facility types (refinery/factory/farm), post
        // contracts pulling RAW MATERIALS into the LOCAL MARKET so the
        // recipe tick actually has supply to consume. This is the fix for
        // the "ore piles up at the mine but refineries starve" failure
        // mode. No reserve check — recipes eat directly from market
        // supply — only a market-supply + shortage check.
        if can_afford {
            let local_supply = supply_by_location
                .get(&loc.location_name)
                .cloned()
                .unwrap_or_default();
            for commodity in recipe_input_commodities(&id.facility_type) {
                let on_market = local_supply.get(&commodity).copied().unwrap_or(0.0);
                // "Short" is market supply well below a recipe-batch's
                // worth, so buying only restores a few cycles of input.
                if on_market >= 100.0 {
                    continue;
                }
                let shortage: u32 = market_shortage.get(&commodity).copied().unwrap_or(0);
                if shortage < RECIPE_INPUT_SHORTAGE_THRESHOLD {
                    continue;
                }
                let qty = delivery_qty_for_shortage(shortage);
                let Some(source) = source_for_commodity(
                    commodity, &loc.location_name, &id.faction_id, qty,
                ) else {
                    continue;
                };
                let payment = compute_delivery_payment(commodity, &source, ops.credits, qty);
                if payment <= 0 {
                    continue;
                }
                plans.push(Plan {
                    requestor_id: id.id.clone(),
                    // Empty string = unowned ("independent"); treat as
                    // None so the rep grant on delivery no-ops rather
                    // than trying to +1 a bogus faction.
                    faction_id: if id.faction_id.is_empty() {
                        None
                    } else {
                        Some(id.faction_id.clone())
                    },
                    commodity,
                    destination: loc.location_name.clone(),
                    source,
                    payment,
                    qty,
                });
                break;
            }
        }
    }
    }

    // Bundle (J): merge plans whose (destination, commodity) match
    // into a single larger contract. Multiple co-located facilities
    // wanting the same thing → one bigger delivery instead of N
    // small ones. Delivery lands in the shared market supply so
    // everyone at the location benefits; the lead (highest-credits)
    // facility fronts the combined payment. Plans whose lead can't
    // cover the combined payment fall back to unbundled.
    let plans = {
        let credits_by_fac_id: std::collections::HashMap<String, i64> = {
            let mut q = world.query::<(&FacilityIdentity, &FacilityOperations)>();
            q.iter(&world)
                .map(|(id, ops)| (id.id.clone(), ops.credits))
                .collect()
        };
        bundle_convoy_plans(plans, |fid| credits_by_fac_id.get(fid).copied().unwrap_or(0))
    };

    // Apply the plans by posting to the board + debiting facility credits.
    // Iterate plans, resolve requestor facility entity, deduct payment.
    for plan in plans {
        // Find facility by requestor_id (= FacilityIdentity.id).
        let fac_entity = {
            let mut q = world.query::<(Entity, &FacilityIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.id == plan.requestor_id)
                .map(|(e, _)| e)
        };
        let Some(fac_entity) = fac_entity else { continue };
        if let Some(mut ops) = world.get_mut::<FacilityOperations>(fac_entity) {
            if ops.credits < plan.payment {
                continue;
            }
            ops.credits -= plan.payment;
            ops.dirty = true;
        }
        contracts.post_delivery_for(
            plan.requestor_id,
            plan.faction_id,
            plan.commodity,
            plan.qty,
            plan.source,
            plan.destination,
            plan.payment,
            tick,
            lifespan,
        );
    }
}

/// Bundle (J): group delivery plans by (destination, commodity)
/// and merge groups of 2+ into a single larger "convoy" contract.
/// The lead (highest-credits facility that can cover the combined
/// payment) becomes the requestor; non-lead plans are discarded
/// because delivery lands in the shared market supply at the
/// destination — everyone benefits from the one bigger order.
///
/// If no participant in a group can afford the combined payment,
/// the group is unbundled: all original plans pass through
/// individually so at least the best-funded facility still posts
/// its own (smaller) contract.
fn bundle_convoy_plans<P, F>(plans: Vec<P>, credits_for: F) -> Vec<P>
where
    P: ConvoyPlan,
    F: Fn(&str) -> i64,
{
    // Group plans by (destination_location, commodity). HashMap
    // ordering doesn't matter — each group is merged independently
    // and the apply loop processes the resulting Vec serially.
    let mut groups: std::collections::HashMap<(String, Commodity), Vec<P>> =
        std::collections::HashMap::new();
    for plan in plans {
        groups
            .entry((plan.destination().to_string(), plan.commodity()))
            .or_default()
            .push(plan);
    }

    let mut out: Vec<P> = Vec::new();
    for ((_dest, _com), group) in groups {
        if group.len() <= 1 {
            out.extend(group);
            continue;
        }
        let combined_qty: u32 = group
            .iter()
            .map(|p| p.qty())
            .fold(0u32, |acc, q| acc.saturating_add(q))
            .min(MAX_DELIVERY_CONTRACT_QTY * 2); // cap merged qty
        let combined_payment: i64 = group.iter().map(|p| p.payment()).sum();

        // Pick lead: the plan whose requestor has the most credits
        // AND can cover the combined payment alone. Fall back to
        // unbundled if nobody can afford it.
        let lead_idx = group
            .iter()
            .enumerate()
            .filter(|(_, p)| {
                credits_for(p.requestor_id())
                    >= combined_payment
            })
            .max_by_key(|(_, p)| {
                credits_for(p.requestor_id())
            })
            .map(|(i, _)| i);
        let Some(lead_idx) = lead_idx else {
            // No bundler rich enough — pass through unbundled.
            out.extend(group);
            continue;
        };
        let mut group = group;
        let mut lead = group.swap_remove(lead_idx);
        lead.set_qty(combined_qty);
        lead.set_payment(combined_payment);
        out.push(lead);
        // Other group members are discarded — the bundled contract
        // serves everyone at the destination through shared market
        // supply.
    }
    out
}

/// Trait the local Plan struct impls so `bundle_convoy_plans` can
/// be written generically and stay unit-testable against a tiny
/// fake. Kept in this module so the `Plan` struct is the only
/// implementor.
trait ConvoyPlan {
    fn destination(&self) -> &str;
    fn commodity(&self) -> Commodity;
    fn qty(&self) -> u32;
    fn payment(&self) -> i64;
    fn requestor_id(&self) -> &str;
    fn set_qty(&mut self, qty: u32);
    fn set_payment(&mut self, payment: i64);
}

/// Phase 7: post crew missions. Each eligible facility has a 25% chance
/// per cycle to post a new mission (if it has <MAX_ACTIVE active and
/// enough treasury). Mission templates come from `economy::missions`;
/// the picked template's `duration_ticks` becomes the contract's
/// quantity field, and the category slug rides along in
/// `Contract.mission_category` so the apply phase can look it back up.
pub fn tick_post_crew_missions(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u32,
) {
    use crate::economy::missions;

    #[derive(Clone)]
    struct Candidate {
        fac_id: String,
        faction_id: String,
        facility_type: String,
        location: String,
        credits: i64,
    }
    // Deterministic "coin flip" using (facility_id + tick) hash so the
    // behavior stays reproducible in tests. Matches sim_core's no-rand
    // convention for tick logic.
    fn hash_flip(key: &str, tick: u64, prob: f32) -> bool {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        key.hash(&mut h);
        tick.hash(&mut h);
        let roll = (h.finish() % 1000) as f32 / 1000.0;
        roll < prob
    }

    let candidates: Vec<Candidate> = {
        let mut q = world.query::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityLifecycle,
            &FacilityOperations,
        )>();
        q.iter(&world)
            .filter(|(_, _, life, _)| !life.abandoned)
            .filter_map(|(id, loc, _, ops)| {
                missions::for_facility_type(&id.facility_type).next()?;
                Some(Candidate {
                    fac_id: id.id.clone(),
                    faction_id: id.faction_id.clone(),
                    facility_type: id.facility_type.clone(),
                    location: loc.location_name.clone(),
                    credits: ops.credits,
                })
            })
            .collect()
    };

    let lifespan = 200 * tick_multiplier as u64; // short-lived gigs

    for cand in candidates {
        // Active mission cap.
        let active = contracts
            .iter()
            .filter(|c| {
                c.requestor_id == cand.fac_id
                    && c.contract_type == crate::economy::contracts::ContractType::CrewMission
                    && matches!(
                        c.status,
                        crate::economy::contracts::ContractStatus::Posted
                            | crate::economy::contracts::ContractStatus::Accepted
                            | crate::economy::contracts::ContractStatus::PickedUp
                    )
            })
            .count();
        if active >= CREW_MISSION_MAX_ACTIVE_PER_FACILITY {
            continue;
        }
        if !hash_flip(&cand.fac_id, tick, CREW_MISSION_POST_PROBABILITY) {
            continue;
        }
        // Pick a mission template — rotate through the facility's options
        // using tick as a selector so we don't always post the same one.
        let templates: Vec<&'static missions::Mission> =
            missions::for_facility_type(&cand.facility_type).collect();
        if templates.is_empty() {
            continue;
        }
        let idx = (tick as usize) % templates.len();
        let template = templates[idx];
        if cand.credits < template.base_payment {
            continue; // can't afford the payout
        }

        // Debit credits and post the mission.
        let fac_e = {
            let mut q = world.query::<(Entity, &FacilityIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.id == cand.fac_id)
                .map(|(e, _)| e)
        };
        if let Some(e) = fac_e {
            if let Some(mut ops) = world.get_mut::<FacilityOperations>(e) {
                if ops.credits < template.base_payment {
                    continue;
                }
                ops.credits -= template.base_payment;
                ops.dirty = true;
            }
        }

        contracts.post_crew_mission(
            cand.fac_id,
            template.category.to_string(),
            template.duration_ticks as u32,
            cand.location,
            template.base_payment,
            if cand.faction_id.is_empty() {
                None
            } else {
                Some(cand.faction_id)
            },
            tick,
            lifespan,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn docking_fee_scales_with_occupancy() {
        // Empty station, perfect condition → base fee.
        assert_eq!(docking_fee(50, 0, 4, 1.0), 50);
        // Half full → 1.5× base.
        assert_eq!(docking_fee(50, 2, 4, 1.0), 75);
        // Full station cannot be reached here (caller guards with at_capacity
        // before calling), but we check the math doesn't explode anyway.
        assert_eq!(docking_fee(50, 4, 4, 1.0), 100);
    }

    #[test]
    fn docking_fee_scales_with_condition() {
        // Ruined station (condition=0) doubles the fee on top of occupancy.
        // 50 × 1.0 × 2.0 = 100
        assert_eq!(docking_fee(50, 0, 4, 0.0), 100);
        // Half-condition station: 50 × 1.0 × 1.5 = 75
        assert_eq!(docking_fee(50, 0, 4, 0.5), 75);
    }

    #[test]
    fn docking_fee_guards_zero_capacity() {
        assert_eq!(docking_fee(50, 0, 0, 1.0), 50);
    }

    /// Bundle (J): test fake for the ConvoyPlan trait so we can
    /// exercise `bundle_convoy_plans` without standing up a hecs
    /// world.
    #[derive(Clone, Debug, PartialEq)]
    struct FakePlan {
        requestor_id: String,
        commodity: Commodity,
        destination: String,
        qty: u32,
        payment: i64,
    }

    impl ConvoyPlan for FakePlan {
        fn destination(&self) -> &str { &self.destination }
        fn commodity(&self) -> Commodity { self.commodity }
        fn qty(&self) -> u32 { self.qty }
        fn payment(&self) -> i64 { self.payment }
        fn requestor_id(&self) -> &str { &self.requestor_id }
        fn set_qty(&mut self, qty: u32) { self.qty = qty; }
        fn set_payment(&mut self, payment: i64) { self.payment = payment; }
    }

    fn mk_plan(reqid: &str, dest: &str, commodity: Commodity, qty: u32, payment: i64) -> FakePlan {
        FakePlan {
            requestor_id: reqid.into(),
            commodity,
            destination: dest.into(),
            qty,
            payment,
        }
    }

    #[test]
    fn convoy_bundle_single_plan_passes_through() {
        let plans = vec![mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000)];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out, plans);
    }

    #[test]
    fn convoy_bundle_merges_co_located_same_commodity() {
        // Two facilities at earth-station both wanting food.
        let plans = vec![
            mk_plan("fac-rich", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-poor", "earth-station", Commodity::Food, 50, 2000),
        ];
        let credits = |id: &str| match id {
            "fac-rich" => 10_000i64,
            _ => 500,
        };
        let out = bundle_convoy_plans(plans, credits);
        assert_eq!(out.len(), 1, "bundled into single plan");
        assert_eq!(out[0].qty, 100, "qty summed");
        assert_eq!(out[0].payment, 4000, "payment summed");
        assert_eq!(out[0].requestor_id, "fac-rich", "lead is the rich one");
    }

    #[test]
    fn convoy_bundle_passes_through_when_no_one_can_afford_merged() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 5000),
            mk_plan("fac-b", "earth-station", Commodity::Food, 50, 5000),
        ];
        // Both facilities have 6000 credits — enough for their OWN
        // payment (5000) but not the combined 10000. Should fall
        // back to unbundled.
        let out = bundle_convoy_plans(plans.clone(), |_| 6000);
        assert_eq!(out.len(), 2, "fallback to unbundled when no bundler can afford");
    }

    #[test]
    fn convoy_bundle_does_not_merge_different_commodities() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-b", "earth-station", Commodity::Fuel, 50, 3000),
        ];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out.len(), 2, "different commodities don't merge");
    }

    #[test]
    fn convoy_bundle_does_not_merge_different_destinations() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-b", "mars-station", Commodity::Food, 50, 2000),
        ];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out.len(), 2, "different destinations don't merge");
    }

    #[test]
    fn convoy_bundle_caps_combined_qty() {
        // Many plans summing to over 2×MAX should cap at 2×MAX.
        let plans: Vec<FakePlan> = (0..10)
            .map(|i| mk_plan(&format!("fac-{i}"), "earth-station", Commodity::Ore, 100, 1000))
            .collect();
        let credits = |id: &str| if id == "fac-0" { 1_000_000 } else { 0 };
        let out = bundle_convoy_plans(plans, credits);
        assert_eq!(out.len(), 1);
        assert!(out[0].qty <= MAX_DELIVERY_CONTRACT_QTY * 2);
    }

    #[test]
    fn delivery_qty_scales_with_shortage() {
        // Zero or just-triggered shortage → base qty.
        assert_eq!(delivery_qty_for_shortage(0), DELIVERY_CONTRACT_QTY);
        assert_eq!(delivery_qty_for_shortage(30), DELIVERY_CONTRACT_QTY);
        // One bucket (60 ticks) past trigger adds 25 units.
        assert_eq!(
            delivery_qty_for_shortage(60),
            DELIVERY_CONTRACT_QTY + 25,
        );
        // Two buckets (90 ticks) adds 50.
        assert_eq!(
            delivery_qty_for_shortage(90),
            DELIVERY_CONTRACT_QTY + 50,
        );
        // Deep / sustained shortage caps at MAX.
        assert_eq!(
            delivery_qty_for_shortage(10_000),
            MAX_DELIVERY_CONTRACT_QTY,
        );
    }

    #[test]
    fn delivery_qty_respects_floor_and_ceiling() {
        // Clamp bounds are respected for every input.
        for shortage in [0_u32, 1, 29, 30, 31, 100, 1000, u32::MAX / 2] {
            let qty = delivery_qty_for_shortage(shortage);
            assert!(
                (MIN_DELIVERY_CONTRACT_QTY..=MAX_DELIVERY_CONTRACT_QTY).contains(&qty),
                "qty {qty} out of bounds for shortage {shortage}",
            );
        }
    }

    #[test]
    fn lifecycle_levelup_threshold_scales() {
        let mut life = FacilityLifecycle::new();
        assert_eq!(life.next_level_threshold(), 100);
        life.level = 2;
        assert_eq!(life.next_level_threshold(), 200);
        life.level = 10;
        assert_eq!(life.next_level_threshold(), 1000);
    }

    #[test]
    fn level_scaled_batches_grows_with_level() {
        assert_eq!(level_scaled_max_batches(1), RECIPE_MAX_BATCHES);
        // Level 10 → RECIPE_MAX_BATCHES × 2.8 (rounded).
        let top = level_scaled_max_batches(10);
        assert!(top > RECIPE_MAX_BATCHES);
        assert!(top < RECIPE_MAX_BATCHES * 4);
    }

    #[test]
    fn grant_xp_levels_up_and_resets_xp() {
        use bevy_ecs::prelude::World;
        let mut world = World::new();
        let e = world.spawn((FacilityLifecycle::new(),)).id();
        // 150 XP → level to 2 (spend 100), leftover 50.
        grant_facility_xp(&mut world, e, 150);
        let life = world.get::<FacilityLifecycle>(e).unwrap();
        assert_eq!(life.level, 2);
        assert_eq!(life.xp, 50);
    }

    #[test]
    fn grant_xp_caps_at_facility_level_cap() {
        use bevy_ecs::prelude::World;
        let mut world = World::new();
        let e = world.spawn((FacilityLifecycle::new(),)).id();
        // Dump 1M XP — should hit FACILITY_LEVEL_CAP and stop leveling.
        grant_facility_xp(&mut world, e, 1_000_000);
        let life = world.get::<FacilityLifecycle>(e).unwrap();
        assert_eq!(life.level, FACILITY_LEVEL_CAP);
    }

    #[test]
    fn module_stock_add_and_take() {
        let mut s = ModuleStock::default();
        assert_eq!(s.count("engine_t2"), 0);
        assert!(!s.take_one("engine_t2"));

        s.add("engine_t2", 2);
        assert_eq!(s.count("engine_t2"), 2);
        assert!(s.dirty);

        s.dirty = false; // simulate post-flush
        assert!(s.take_one("engine_t2"));
        assert_eq!(s.count("engine_t2"), 1);
        assert!(s.dirty, "take_one should re-dirty the component");
    }

    #[test]
    fn tick_produce_modules_mints_one_from_market_supply() {
        use crate::agents::facility::tick_produce_modules;
        use crate::agents::market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing};
        use crate::economy::commodities::Commodity;
        use bevy_ecs::prelude::World;

        let mut world = World::new();

        // Spawn a market with plenty of supply for engine_t2 + cargo_bay_t2
        // (enough for tier-2 engines: 3 metals + 2 electronics + 1 tool).
        let market_entity = world.spawn((
            MarketIdentity {
                db_id: 1,
                id: "market-earth-station".into(),
                facility: Entity::PLACEHOLDER,
                facility_location: "earth-station".into(),
            },
            {
                let mut p = MarketPricing {
                    price_elasticity: 0.02,
                    spread: 0.10,
                    prices: Default::default(),
                    supply: Default::default(),
                    demand: Default::default(),
                };
                p.supply.insert(Commodity::Metals, 20.0);
                p.supply.insert(Commodity::Electronics, 20.0);
                p.supply.insert(Commodity::Tools, 5.0);
                p.supply.insert(Commodity::Polymers, 10.0);
                p
            },
            MarketFlow {
                production: Default::default(),
                consumption: Default::default(),
                consumption_window: Default::default(),
                seed_demand: Default::default(),
            },
            MarketOrders {
                pending_buys: vec![],
                pending_sells: vec![],
                reserved: Default::default(),
                next_order_id: 0,
                next_reserve_id: 0,
                order_expiry_ticks: 100,
            },
            MarketHistory {
                trend_samples: Default::default(),
                trade_volume: Default::default(),
                shortage_ticks: Default::default(),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
                crisis_notified: Default::default(),
            },
        )).id();
        let _ = market_entity;

        // Spawn a shipyard at the same location with an empty module stock.
        let shipyard_entity = world.spawn((
            FacilityIdentity {
                db_id: 2,
                id: "facility-earth-shipyard".into(),
                name: "Terra Shipyards".into(),
                facility_type: "shipyard".into(),
                faction_id: "terran-authority".into(),
                body_id: "earth".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "earth-station".into(),
            },
            FacilityLifecycle::new(),
            ModuleStock::default(),
        )).id();

        // Run the production phase — it should pick engine_t2 (first
        // under-stocked recipe whose inputs are covered) and mint 1.
        tick_produce_modules(&mut world);

        let stock = world.get::<ModuleStock>(shipyard_entity).unwrap();
        assert_eq!(
            stock.count("engine_t2"),
            1,
            "shipyard should mint one engine_t2 on the first pass",
        );
        let pricing = world.get::<MarketPricing>(market_entity).unwrap();
        // 20 − 3 metals consumed by engine_t2 recipe.
        assert!((pricing.supply[&Commodity::Metals] - 17.0).abs() < 0.001);
    }

    #[test]
    fn tick_produce_modules_skips_when_inputs_missing() {
        use crate::agents::facility::tick_produce_modules;
        use crate::agents::market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing};
        use bevy_ecs::prelude::World;

        let mut world = World::new();
        // Market has no supply at all.
        world.spawn((
            MarketIdentity {
                db_id: 1,
                id: "market-empty".into(),
                facility: Entity::PLACEHOLDER,
                facility_location: "empty".into(),
            },
            MarketPricing {
                price_elasticity: 0.02,
                spread: 0.10,
                prices: Default::default(),
                supply: Default::default(),
                demand: Default::default(),
            },
            MarketFlow {
                production: Default::default(),
                consumption: Default::default(),
                consumption_window: Default::default(),
                seed_demand: Default::default(),
            },
            MarketOrders {
                pending_buys: vec![],
                pending_sells: vec![],
                reserved: Default::default(),
                next_order_id: 0,
                next_reserve_id: 0,
                order_expiry_ticks: 100,
            },
            MarketHistory {
                trend_samples: Default::default(),
                trade_volume: Default::default(),
                shortage_ticks: Default::default(),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
                crisis_notified: Default::default(),
            },
        ));
        let yard = world.spawn((
            FacilityIdentity {
                db_id: 2,
                id: "facility-empty-yard".into(),
                name: "Empty Yard".into(),
                facility_type: "shipyard".into(),
                faction_id: "x".into(),
                body_id: "none".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "empty".into(),
            },
            FacilityLifecycle::new(),
            ModuleStock::default(),
        )).id();

        tick_produce_modules(&mut world);
        let stock = world.get::<ModuleStock>(yard).unwrap();
        assert!(
            stock.stock.is_empty(),
            "shipyard should mint nothing when the market can't cover any recipe",
        );
    }
}

#[cfg(test)]
mod salvage_field_tests {
    use super::*;

    #[test]
    fn salvage_is_three_times_slower_at_equal_richness() {
        let richness = 0.6;
        let (scrap, _) = salvage_extraction(richness, 1.0);
        let mine = MINING_YIELD_PER_CYCLE * richness;
        assert!((scrap * SALVAGE_SPEED_DIVISOR - mine).abs() < 0.0001);
    }

    #[test]
    fn finite_wreck_field_cannot_duplicate_resources() {
        let mut richness = 0.8;
        let starting_stock = richness * SALVAGE_UNITS_PER_RICHNESS;
        let mut extracted_total = 0.0;
        for _ in 0..100_000 {
            let (qty, remaining) = salvage_extraction(richness, 1.0);
            extracted_total += qty;
            assert!(remaining <= richness);
            richness = remaining;
            if richness == 0.0 { break; }
        }
        assert!(richness == 0.0, "salvage must deplete completely");
        assert!((extracted_total - starting_stock).abs() < 2.0);
        assert_eq!(salvage_extraction(0.0, 1.0), (0.0, 0.0));
    }
}
