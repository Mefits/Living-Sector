//! Population components.

use crate::economy::commodities::Commodity;
use bevy_ecs::prelude::{Component, Entity, World};
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone, Component)]
pub struct PopIdentity {
    pub db_id: i64,
    pub id: String,                  // "pop-earth-workers"
    pub label: String,
    pub demographic: String,         // workers, merchants, scientists, etc.
    pub facility: Entity,            // owning facility
    pub facility_location: String,
    pub faction_id: String,
}

/// Population size and demographic dynamics.
#[derive(Debug, Clone, Component)]
pub struct PopDemographics {
    pub population_count: i64,
    pub growth_rate: f32,
    pub employed_fraction: f32,
    pub migration_pressure: f32,
}

/// Economic activity.
#[derive(Debug, Clone, Component)]
pub struct PopEconomy {
    pub total_wealth: i64,
    pub spending_rate: f32,
    pub consumption: HashMap<Commodity, f32>,
    pub production_commodity: Option<Commodity>,
    pub production_amount: f32,
}

/// Sentiment / satisfaction axes. Touched less often than economy.
#[derive(Debug, Clone, Component)]
pub struct PopSentiment {
    pub overall_sentiment: i32,
    pub unrest: i32,
    pub food_satisfaction: i32,
    pub safety_satisfaction: i32,
    pub entertainment_satisfaction: i32,
    pub dirty: bool,
}

/// Snapshot for HTTP/WS.
#[derive(Debug, Clone, Serialize)]
pub struct PopSnapshot {
    pub employed_fraction: f32,
    pub id: String,
    pub label: String,
    pub demographic: String,
    pub facility_location: String,
    pub population_count: i64,
    pub overall_sentiment: i32,
    pub unrest: i32,
    pub total_wealth: i64,
    pub food_satisfaction: i32,
    /// Phase 19d: exposed so diagnostics + the UI can see this
    /// pop climbing toward a migration event. 0.0–2.0 scale,
    /// triggers at [`MIGRATION_PRESSURE_TRIGGER`].
    pub migration_pressure: f32,
}

impl PopSnapshot {
    pub fn build(
        identity: &PopIdentity,
        demographics: &PopDemographics,
        economy: &PopEconomy,
        sentiment: &PopSentiment,
    ) -> Self {
        let _ = demographics.growth_rate;
        Self {
            employed_fraction: demographics.employed_fraction,
            id: identity.id.clone(),
            label: identity.label.clone(),
            demographic: identity.demographic.clone(),
            facility_location: identity.facility_location.clone(),
            population_count: demographics.population_count,
            overall_sentiment: sentiment.overall_sentiment,
            unrest: sentiment.unrest,
            total_wealth: economy.total_wealth,
            food_satisfaction: sentiment.food_satisfaction,
            migration_pressure: demographics.migration_pressure,
        }
    }
}

// ============================================================================
// Population tick
// ============================================================================
//
// Each population represents thousands of people. Every N ticks they:
//   1. Consume food from their local market (drains supply).
//   2. Produce a commodity from their labor (adds to local market supply).
//   3. Update sentiment based on food_satisfaction.
//
// This closes the loop: markets gain stock from production + mining +
// facility recipes, and lose stock to population consumption and ship trades.

use crate::agents::market::{MarketIdentity, MarketPricing};

pub const CONSUMPTION_INTERVAL_BASE: u64 = 5;
pub const PRODUCTION_INTERVAL_BASE: u64 = 5;
/// Pops check whether to post a delivery contract every N base-ticks.
pub const CONTRACT_POST_INTERVAL_BASE: u64 = 25;
/// Passenger-contract posting cadence (base ticks). Matches Elixir's 60×mult.
pub const PASSENGER_CONTRACT_INTERVAL_BASE: u64 = 60;
/// Food satisfaction decays by this per unsatisfied cycle (clamped 0-100).
pub const FOOD_SAT_DROP_ON_SHORTAGE: i32 = 5;
pub const FOOD_SAT_RECOVER_ON_MET: i32 = 2;

/// Food satisfaction below this triggers a delivery contract post.
pub const CONTRACT_FOOD_THRESHOLD: i32 = 40;
/// Food satisfaction below this triggers emergency water purchase too —
/// dehydration compounds the food shortage in Elixir's pop model.
pub const EMERGENCY_WATER_THRESHOLD: i32 = 30;
/// Below this satisfaction, the pop is actually starving (people dying,
/// not just hungry). Contracts go into emergency mode — higher payment
/// multiplier, bigger quantity, shorter lifespan — so the ship planner
/// treats them as the most attractive contracts on the board instead
/// of letting them rot behind better-paying subsidies.
pub const EMERGENCY_FOOD_THRESHOLD: i32 = 20;
/// Payment multiplier for `EMERGENCY_FOOD_THRESHOLD` contracts.
/// Effective pay = base × EMERGENCY_FOOD_PREMIUM × qty — outpaces
/// subsidy rates so ships with uncommitted capacity route to the
/// starving pop first.
pub const EMERGENCY_FOOD_PREMIUM: f32 = 6.0;
/// Extra water consumed per cycle during an emergency. Rate × pop size ÷ 1000.
pub const EMERGENCY_WATER_RATE: f32 = 0.5;
/// Contracts expire after this many base-ticks unposted.
pub const CONTRACT_LIFESPAN_BASE: u64 = 200;

// --- Phase 19d: population migration ---

/// Pops with `overall_sentiment` at or below this value accumulate
/// migration pressure. Above, pressure decays (happy populations
/// stay put). 30 matches Elixir's threshold.
pub const MIGRATION_SENTIMENT_FLOOR: i32 = 30;

/// Pressure added per consumption-tick when sentiment is under the
/// floor. Scaled by tick_scale so fast-forward gameplay doesn't
/// stack pressure artificially.
pub const MIGRATION_PRESSURE_RISE: f32 = 0.01;

/// Pressure shed per consumption-tick when sentiment is OK. Half
/// the rise rate so "briefly sad" pops don't trigger spurious
/// migrations.
pub const MIGRATION_PRESSURE_DECAY: f32 = 0.005;

/// When `migration_pressure` >= this value, the next migration
/// check fires a transfer and resets the pressure. 1.0 = roughly
/// 100 ticks of sustained low sentiment at tick_scale=1.0.
pub const MIGRATION_PRESSURE_TRIGGER: f32 = 1.0;

/// How often the migration transfer pass runs (base-ticks). Much
/// less frequent than the pressure accumulation — the idea is
/// "slowly leak population, not evacuate in one tick."
pub const MIGRATION_CHECK_INTERVAL_BASE: u64 = 200;

/// How many people transfer on one migration event. Clamped against
/// source pop size so small settlements don't collapse in a single
/// fire. Matches a loose "a few percent per trigger" pace.
pub const MIGRATION_HEAD_COUNT: i64 = 100;

/// Destination population must be at least this count higher than
/// the source — stops pop ping-pong between two equally-sentimental
/// neighbors.
pub const MIGRATION_MIN_DESTINATION_SENTIMENT: i32 = 50;
/// Pay multiplier over base price for delivery contracts.
pub const CONTRACT_PREMIUM: f32 = 1.8;
/// Max urgency multiplier on top of CONTRACT_PREMIUM. Matches Elixir:
/// pay = base × premium × (1 + (1 - sat/100) × 2). At sat=0 the pop pays 3×.
pub const CONTRACT_URGENCY_PEAK: f32 = 2.0;

/// Sentiment inertia factor. Each consumption cycle the stored
/// `overall_sentiment` is blended with the freshly-computed target using
/// `old × factor + target × (1 - factor)`. At tick_scale=1.0 the factor
/// is `0.9`; we exponentiate so behavior scales with world_speed (faster
/// speed = quicker convergence toward the food-driven target).
pub const SENTIMENT_INERTIA_BASE: f32 = 0.9;

/// Passenger contract preconditions. Matches Elixir thresholds.
pub const PASSENGER_MIN_POPULATION: i64 = 5_000;
pub const PASSENGER_MIN_SENTIMENT: i32 = 50;
/// Passenger contract batch size (people per ship-load).
pub const PASSENGER_BATCH_SIZE: u32 = 50;
/// Payment per passenger on a passenger-transport contract. Treated as
/// credits the destination pays the ship on arrival.
pub const PASSENGER_PAYMENT_PER_HEAD: i64 = 80;

pub fn tick_populations(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let mult = tick_multiplier as u64;
    let consumption_interval = CONSUMPTION_INTERVAL_BASE * mult;
    let production_interval = PRODUCTION_INTERVAL_BASE * mult;

    if tick % consumption_interval != 0 && tick % production_interval != 0 {
        return;
    }

    // Bundle 1.5: LOD gate. Build once, filter the main loop below.
    // Off-screen populations skip consumption/production this tick.
    // Rate-scaling of consumption / sentiment drift is deferred; for
    // now off-screen pops consume less (proportional to LOD divisor),
    // which matches the player's "these worlds are idling" expectation.
    use crate::simulation::lod::AgentLod;
    let pop_with_lod: std::collections::HashSet<Entity> = {
        let mut q = world.query::<(Entity, &PopIdentity, &AgentLod)>();
        q.iter(&world).map(|(e, _, _)| e).collect()
    };
    let mut pop_lod_gate: std::collections::HashMap<Entity, u32> =
        std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<(Entity, &mut AgentLod)>();
        for (e, mut lod) in lod_q.iter_mut(world) {
            if !pop_with_lod.contains(&e) {
                continue;
            }
            if let Some(skipped) = lod.try_fire(tick) {
                pop_lod_gate.insert(e, skipped);
            }
        }
    }
    // Pops without AgentLod fire every tick.
    let pop_no_lod: Vec<Entity> = {
        let mut q = world.query::<(Entity, &PopIdentity)>();
        q.iter(&world)
            .map(|(e, _)| e)
            .filter(|e| !pop_with_lod.contains(e))
            .collect()
    };
    for e in pop_no_lod {
        pop_lod_gate.insert(e, 1);
    }
    let _ = tick_scale; // reserved for sentiment inertia scaling below

    // Index markets by location
    let market_at_location: std::collections::HashMap<String, Entity> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(&world).map(|(e, id)| (id.facility_location.clone(), e)).collect()
    };

    // Pre-collect population entity list to avoid aliasing
    let pop_entities: Vec<Entity> = {
        let mut q = world.query::<(Entity, &PopIdentity)>();
        q.iter(&world).map(|(e, _)| e).collect()
    };

    // Sentiment inertia exponent: slower world_speed = slower drift.
    let inertia_factor = SENTIMENT_INERTIA_BASE.powf(tick_scale.max(0.01));

    for entity in pop_entities {
        // Bundle 1.5: LOD filter — skip off-screen pops on ticks they
        // aren't firing.
        if !pop_lod_gate.contains_key(&entity) {
            continue;
        }
        let (location, consumption, production_commodity, production_amount, pop_size, current_food_sat) = {
            let mut q = world.query::<(&PopIdentity, &PopEconomy, &PopDemographics, &PopSentiment)>();
            let Ok((id, econ, demo, sent)) = q.get(world, entity) else { continue };
            (
                id.facility_location.clone(),
                econ.consumption.clone(),
                econ.production_commodity,
                econ.production_amount,
                demo.population_count,
                sent.food_satisfaction,
            )
        };

        let market_entity = match market_at_location.get(&location) {
            Some(&e) => e,
            None => continue,
        };

        let mut any_shortage = false;
        // Consumption is an actual purchase from the market's owner. A
        // household without cash remains unsupplied, even with stock nearby.
        if tick % consumption_interval == 0 {
            let mut needs: Vec<_> = consumption.into_iter()
                .map(|(c, rate)| (c, rate * pop_size.max(0) as f32 / 1000.0))
                .filter(|(_, amount)| *amount > 0.0).collect();
            if current_food_sat < EMERGENCY_WATER_THRESHOLD && pop_size > 0 {
                needs.push((Commodity::Water, EMERGENCY_WATER_RATE * (pop_size as f32 / 1000.0).max(1.0)));
            }
            needs.sort_by_key(|(c, _)| match c {
                Commodity::Food => (0, c.as_str()), Commodity::Water => (1, c.as_str()), _ => (2, c.as_str()),
            });
            for (commodity, needed) in needs {
                let result = purchase_consumption(world, entity, market_entity, commodity, needed, tick);
                if result.as_ref().map(|(qty, _)| *qty < needed).unwrap_or(true) { any_shortage = true; }
                events.push(serde_json::json!({"kind":"population_purchase", "tick":tick,
                    "population_id":world.get::<PopIdentity>(entity).map(|p| &p.id),
                    "commodity":commodity.as_str(), "needed":needed,
                    "quantity":result.as_ref().map(|v| v.0).unwrap_or(0.0),
                    "payment":result.as_ref().map(|v| v.1).unwrap_or(0), "reason":result.err()}));
            }
        }
        // The legacy household production bypassed recipes/resources and paid
        // itself invented revenue. Native facilities remain the producers.
        // Workforce integration is the next block; do not silently mint output.
        if tick % production_interval == 0 && production_commodity.is_some() && production_amount > 0.0 {
            events.push(serde_json::json!({"kind":"population_production_blocked", "tick":tick,
                "reason":"requires_native_employer", "location":location}));
        }

        // Update sentiment based on food supply — apply inertia so the
        // overall_sentiment value doesn't swing ±50 on a single frame.
        if tick % consumption_interval == 0 {
            if let Some(mut sentiment) = world.get_mut::<PopSentiment>(entity) {
                if any_shortage {
                    sentiment.food_satisfaction =
                        (sentiment.food_satisfaction - FOOD_SAT_DROP_ON_SHORTAGE).max(0);
                } else {
                    sentiment.food_satisfaction =
                        (sentiment.food_satisfaction + FOOD_SAT_RECOVER_ON_MET).min(100);
                }
                let target = (sentiment.food_satisfaction * 6
                    + sentiment.safety_satisfaction * 2
                    + sentiment.entertainment_satisfaction * 2)
                    / 10;
                // Weighted blend `old * factor + target * (1 - factor)` in
                // integer arithmetic — multiply before dividing to avoid
                // losing precision.
                let old = sentiment.overall_sentiment as f32;
                let blended = old * inertia_factor + target as f32 * (1.0 - inertia_factor);
                sentiment.overall_sentiment = blended.round() as i32;
                sentiment.unrest = (100 - sentiment.overall_sentiment).clamp(0, 100);
                sentiment.dirty = true;
            }
        }

        // Phase 19d: accumulate migration pressure when sentiment is
        // in the "we want out of here" band. Rises slowly — the real
        // check + transfer happens on the migration cadence below.
        if tick % consumption_interval == 0 {
            let cur_sentiment = world
                .get::<PopSentiment>(entity)
                .map(|s| s.overall_sentiment)
                .unwrap_or(50);
            if let Some(mut demo) = world.get_mut::<PopDemographics>(entity) {
                let delta = if cur_sentiment < MIGRATION_SENTIMENT_FLOOR {
                    MIGRATION_PRESSURE_RISE * tick_scale
                } else {
                    -MIGRATION_PRESSURE_DECAY * tick_scale
                };
                demo.migration_pressure = (demo.migration_pressure + delta).clamp(0.0, 2.0);
            }
        }
    }

    // Migration transfer pass (Phase 19d). Runs on its own interval
    // so pops don't migrate every single tick they're unhappy — a
    // slow outflow keeps the numbers readable.
    let migration_interval = MIGRATION_CHECK_INTERVAL_BASE * mult;
    if tick % migration_interval == 0 {
        run_population_migration(world, events);
    }

    // Contract posting — delivery contracts for food shortages.
    let contract_interval = CONTRACT_POST_INTERVAL_BASE * mult;
    if tick % contract_interval == 0 {
        post_food_contracts(world, contracts, tick, mult);
    }

    // Passenger-transport contract posting — happy + populous pops ship
    // batches of passengers to peer locations. Uses the dedicated
    // `ContractType::Passenger` kind so the apply phase (in engine) bumps
    // destination population instead of market supply.
    let passenger_interval = PASSENGER_CONTRACT_INTERVAL_BASE * mult;
    if tick % passenger_interval == 0 {
        post_passenger_contracts(world, contracts, tick, mult);
    }

    // Expire old unfilled contracts + decay reputation gates so
    // faction-posted subsidies age open to the public + escalate
    // payment on long-posted contracts (Phase 18j) so desperate
    // requestors get picked up instead of expiring. Phase 19b:
    // delivery contracts get up to 3 auto-renewals with escalating
    // payment + relaxed rep gate before permanently expiring. Each
    // renewal / expiry emits a ticker event so players can see the
    // economy dynamics without opening a details panel.
    let delivery_lifespan =
        crate::agents::facility::FACILITY_DELIVERY_LIFESPAN_BASE * mult;
    let sweep = contracts.sweep_expiring(tick, delivery_lifespan);
    for r in &sweep.renewed {
        events.push(serde_json::json!({
            "kind": "contract_renewed",
            "contract_id": r.id,
            "commodity": r.commodity.as_str(),
            "destination": r.destination,
            "payment": r.new_payment,
            "min_reputation": r.new_min_rep,
            "renewal_count": r.renewal_count,
        }));
    }
    for e in &sweep.expired {
        events.push(serde_json::json!({
            "kind": "contract_expired",
            "contract_id": e.id,
            "contract_type": e.contract_type.as_str(),
            "commodity": e.commodity.as_str(),
            "destination": e.destination,
            "final_payment": e.final_payment,
        }));
    }
    contracts.age_open_reputation(tick);
    contracts.age_escalate_payment(tick);
}

/// Phase 19d: transfer population from a chronically-unhappy pop
/// (migration_pressure ≥ trigger) to a happier destination. One
/// transfer per call — the unhappiest source pop "wins" the move
/// each cycle, and picks the destination with the highest
/// sentiment across all other pops.
///
/// Resets the source's pressure to 0 on transfer so it has to
/// re-accumulate a full cycle of discontent before migrating again.
/// Emits `population_migrated` for the ticker.
fn run_population_migration(
    world: &mut World,
    events: &mut Vec<serde_json::Value>,
) {
    // Collect (entity, id, pop, sentiment, pressure) for every pop.
    #[derive(Clone)]
    struct PopRef {
        entity: Entity,
        id: String,
        label: String,
        location: String,
        population: i64,
        sentiment: i32,
        pressure: f32,
    }
    let mut pops: Vec<PopRef> = Vec::new();
    {
        let mut q = world.query::<(Entity, &PopIdentity, &PopDemographics, &PopSentiment)>();
        for (e, identity, demo, sentiment) in q.iter(&world) {
            pops.push(PopRef {
                entity: e,
                id: identity.id.clone(),
                label: identity.label.clone(),
                location: identity.facility_location.clone(),
                population: demo.population_count,
                sentiment: sentiment.overall_sentiment,
                pressure: demo.migration_pressure,
            });
        }
    }

    // Pick the unhappiest pop with pressure over trigger as the
    // source. Skip pops too small to lose headcount meaningfully.
    let source = pops
        .iter()
        .filter(|p| p.pressure >= MIGRATION_PRESSURE_TRIGGER)
        .filter(|p| p.population > MIGRATION_HEAD_COUNT * 3)
        .max_by(|a, b| a.pressure.partial_cmp(&b.pressure).unwrap_or(std::cmp::Ordering::Equal))
        .cloned();
    let Some(source) = source else { return };

    // Destination: different pop, at a different location, sentiment
    // at least `MIGRATION_MIN_DESTINATION_SENTIMENT`. Pick the
    // happiest to route the flow toward a real improvement.
    let destination = pops
        .iter()
        .filter(|p| p.entity != source.entity)
        .filter(|p| p.location != source.location)
        .filter(|p| p.sentiment >= MIGRATION_MIN_DESTINATION_SENTIMENT)
        .max_by_key(|p| p.sentiment)
        .cloned();
    let Some(destination) = destination else { return };

    // Transfer: clamp against source pop so we don't underflow.
    let moved = MIGRATION_HEAD_COUNT.min(source.population.saturating_sub(100));
    if moved <= 0 {
        return;
    }

    let Some(source_cash) = world.get::<PopEconomy>(source.entity).map(|e| e.total_wealth) else { return };
    let Some(destination_cash) = world.get::<PopEconomy>(destination.entity).map(|e| e.total_wealth) else { return };
    if source_cash < 0 { return; }
    let transfer = (source_cash as i128 * moved as i128 / source.population as i128) as i64;
    let Some(after) = destination_cash.checked_add(transfer) else { return };
    world.get_mut::<PopEconomy>(source.entity).unwrap().total_wealth -= transfer;
    world.get_mut::<PopEconomy>(destination.entity).unwrap().total_wealth = after;
    for entity in [source.entity, destination.entity] {
        if let Some(mut sent) = world.get_mut::<PopSentiment>(entity) { sent.dirty = true; }
    }

    if let Some(mut demo) = world.get_mut::<PopDemographics>(source.entity) {
        demo.population_count = demo.population_count.saturating_sub(moved);
        demo.migration_pressure = 0.0;
    }
    if let Some(mut demo) = world.get_mut::<PopDemographics>(destination.entity) {
        demo.population_count = demo.population_count.saturating_add(moved);
    }

    events.push(serde_json::json!({
        "kind": "population_migrated",
        "source_id": source.id,
        "source_label": source.label,
        "source_location": source.location,
        "destination_id": destination.id,
        "destination_label": destination.label,
        "destination_location": destination.location,
        "count": moved,
        "source_sentiment": source.sentiment,
        "destination_sentiment": destination.sentiment,
    }));
}

fn post_passenger_contracts(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u64,
) {
    struct Candidate {
        pop_id: String,
        origin: String,
        faction_id: String,
    }
    let candidates: Vec<Candidate> = {
        let mut q = world.query::<(&PopIdentity, &PopSentiment, &PopDemographics)>();
        q.iter(&world)
            .filter(|(_, sent, demo)| {
                sent.overall_sentiment >= PASSENGER_MIN_SENTIMENT
                    && demo.population_count >= PASSENGER_MIN_POPULATION
            })
            .map(|(id, _, _)| Candidate {
                pop_id: id.id.clone(),
                origin: id.facility_location.clone(),
                faction_id: id.faction_id.clone(),
            })
            .collect()
    };
    if candidates.is_empty() {
        return;
    }

    let all_destinations: Vec<String> = {
        let mut q = world.query::<&PopIdentity>();
        q.iter(&world).map(|id| id.facility_location.clone()).collect()
    };

    for cand in candidates {
        let Some(destination) = all_destinations
            .iter()
            .find(|d| **d != cand.origin)
            .cloned()
        else {
            continue;
        };
        // One passenger contract per origin at a time — the board's
        // destination index makes this cheap.
        let has_active = contracts
            .iter()
            .any(|c| c.requestor_id == cand.pop_id && c.contract_type == crate::economy::contracts::ContractType::Passenger
                && matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                ));
        if has_active {
            continue;
        }
        let payment = PASSENGER_PAYMENT_PER_HEAD * PASSENGER_BATCH_SIZE as i64;
        let faction_tag = if cand.faction_id.is_empty() {
            None
        } else {
            Some(cand.faction_id.clone())
        };
        // Passenger contracts need an actual embarkation/reserved-headcount
        // transfer first. Legacy arrival created residents at every destination
        // group. Keep ordinary migration, do not publish unfounded travel here.
        let _ = (payment, faction_tag, destination, tick, tick_multiplier);

    }
}

/// For each food-stressed population, post a delivery contract from the
/// richest known food source. Skips pops that already have a posted
/// contract in-flight (one contract per destination at a time).
fn post_food_contracts(
    world: &mut World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u64,
) {
    use crate::economy::commodities::Commodity;

    // Snapshot: location → food supply (for picking source)
    let food_supply_by_loc: std::collections::HashMap<String, f32> = {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing)>();
        q.iter(&world)
            .map(|(id, pricing)| {
                (
                    id.facility_location.clone(),
                    pricing.supply.get(&Commodity::Food).copied().unwrap_or(0.0),
                )
            })
            .collect()
    };

    // Collect pop → decision info
    struct PopDecision {
        pop_id: String,
        destination: String,
        satisfaction: i32,
        population_count: i64,
        faction_id: String,
    }
    let decisions: Vec<PopDecision> = {
        let mut q = world.query::<(&PopIdentity, &PopSentiment, &PopDemographics)>();
        q.iter(&world)
            .map(|(id, sent, demo)| PopDecision {
                pop_id: id.id.clone(),
                destination: id.facility_location.clone(),
                satisfaction: sent.food_satisfaction,
                population_count: demo.population_count,
                faction_id: id.faction_id.clone(),
            })
            .collect()
    };

    for dec in decisions {
        if dec.satisfaction >= CONTRACT_FOOD_THRESHOLD {
            continue;
        }
        // Skip if the destination already has a posted food contract
        let already_posted = contracts
            .posted_with_destination(&dec.destination)
            .iter()
            .any(|c| c.commodity == Commodity::Food);
        if already_posted {
            continue;
        }

        // Pick the richest source (not the pop's own location)
        let source = food_supply_by_loc
            .iter()
            .filter(|(loc, &supply)| **loc != dec.destination && supply > 100.0)
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(loc, _)| loc.clone());
        let source = match source {
            Some(s) => s,
            None => continue, // nowhere to ship food from
        };

        // Starving pops post an EMERGENCY contract: larger order, much
        // higher payment, shorter lifespan. Below the normal threshold
        // but above the emergency one, we post the regular "pop is
        // peckish" contract.
        let is_emergency = dec.satisfaction < EMERGENCY_FOOD_THRESHOLD;
        let quantity: u32 = if is_emergency {
            (dec.population_count / 500).clamp(50, 500) as u32
        } else {
            (dec.population_count / 1000).clamp(20, 300) as u32
        };
        let payment = if is_emergency {
            (Commodity::Food.base_price() * EMERGENCY_FOOD_PREMIUM * quantity as f32) as i64
        } else {
            let sat_ratio = (dec.satisfaction as f32 / 100.0).clamp(0.0, 1.0);
            let urgency = 1.0 + (1.0 - sat_ratio) * CONTRACT_URGENCY_PEAK;
            (Commodity::Food.base_price() * CONTRACT_PREMIUM * urgency * quantity as f32) as i64
        };
        let lifespan = if is_emergency {
            // Half the normal lifespan — the pop either gets fed fast or
            // it's reposting with fresh urgency.
            (CONTRACT_LIFESPAN_BASE / 2).max(50) * tick_multiplier
        } else {
            CONTRACT_LIFESPAN_BASE * tick_multiplier
        };

        let faction_tag = if dec.faction_id.is_empty() {
            None
        } else {
            Some(dec.faction_id.clone())
        };
        if !reserve_population_payment(world, &dec.pop_id, payment) { continue; }
        let id = contracts.post_delivery_for(
            dec.pop_id,
            faction_tag,
            Commodity::Food,
            quantity,
            source,
            dec.destination,
            payment,
            tick,
            lifespan,
        );
        contracts.register_prepaid(&id, crate::economy::contracts::FundingSource::Population);
    }
}


/// All validation precedes mutation; callers hold exclusive World access.
pub fn purchase_consumption(world: &mut World, population: Entity, market: Entity,
    commodity: Commodity, needed: f32, tick: u64) -> Result<(f32, i64), &'static str> {
    use crate::agents::{facility::FacilityOperations, market::{MarketHistory, MarketFlow}};
    let identity = world.get::<MarketIdentity>(market).ok_or("missing_market")?;
    let seller = identity.facility;
    if world.get::<PopIdentity>(population).ok_or("missing_population")?.facility_location != identity.facility_location {
        return Err("wrong_location");
    }
    let pricing = world.get::<MarketPricing>(market).ok_or("missing_pricing")?;
    let price = pricing.price(commodity) as f64;
    let stock = pricing.supply.get(&commodity).copied().unwrap_or(0.0);
    let cash = world.get::<PopEconomy>(population).ok_or("missing_wallet")?.total_wealth;
    if !needed.is_finite() || needed <= 0.0 || !price.is_finite() || price <= 0.0 || !stock.is_finite() || stock < 0.0 {
        return Err("invalid_quote");
    }
    if stock == 0.0 { return Err("insufficient_stock"); }
    if cash <= 0 { return Err("insufficient_household_credits"); }
    // Fractional physical units are valid; round payment upward, never give
    // free fractional purchases. Recheck after the f32 conversion.
    let quantity = (needed as f64).min(stock as f64).min(cash as f64 / price) as f32;
    if quantity <= 0.0 { return Err("insufficient_household_credits"); }
    let payment = (quantity as f64 * price).ceil();
    if payment >= i64::MAX as f64 || payment as i64 > cash { return Err("invalid_payment"); }
    let payment = payment as i64;
    let after = world.get::<FacilityOperations>(seller).ok_or("missing_seller_economy")?.credits
        .checked_add(payment).ok_or("credit_overflow")?;
    world.get_mut::<PopEconomy>(population).unwrap().total_wealth -= payment;
    if let Some(mut sent) = world.get_mut::<PopSentiment>(population) { sent.dirty = true; }
    let mut ops = world.get_mut::<FacilityOperations>(seller).unwrap(); ops.credits = after; ops.dirty = true;
    world.get_mut::<MarketPricing>(market).unwrap().supply.insert(commodity, stock - quantity);
    if let Some(mut history) = world.get_mut::<MarketHistory>(market) { history.dirty = true; }
    if let Some(mut flow) = world.get_mut::<MarketFlow>(market) {
        crate::agents::market::record_consumption(&mut flow, commodity, quantity, tick);
    }
    Ok((quantity, payment))
}

fn reserve_population_payment(world: &mut World, id: &str, payment: i64) -> bool {
    let entity = world.query::<(Entity, &PopIdentity)>().iter(world)
        .find(|(_, p)| p.id == id).map(|(e, _)| e);
    let Some(entity) = entity else { return false };
    let Some(mut economy) = world.get_mut::<PopEconomy>(entity) else { return false };
    if payment < 0 || economy.total_wealth < payment { return false; }
    economy.total_wealth -= payment;
    if let Some(mut sent) = world.get_mut::<PopSentiment>(entity) { sent.dirty = true; }
    true
}
