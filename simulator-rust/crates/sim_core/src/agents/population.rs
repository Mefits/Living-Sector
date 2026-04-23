//! Population components.

use crate::economy::commodities::Commodity;
use hecs::Entity;
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone)]
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
#[derive(Debug, Clone)]
pub struct PopDemographics {
    pub population_count: i64,
    pub growth_rate: f32,
    pub employed_fraction: f32,
    pub migration_pressure: f32,
}

/// Economic activity.
#[derive(Debug, Clone)]
pub struct PopEconomy {
    pub total_wealth: i64,
    pub spending_rate: f32,
    pub consumption: HashMap<Commodity, f32>,
    pub production_commodity: Option<Commodity>,
    pub production_amount: f32,
}

/// Sentiment / satisfaction axes. Touched less often than economy.
#[derive(Debug, Clone)]
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
    pub id: String,
    pub label: String,
    pub demographic: String,
    pub facility_location: String,
    pub population_count: i64,
    pub overall_sentiment: i32,
    pub unrest: i32,
    pub total_wealth: i64,
    pub food_satisfaction: i32,
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
            id: identity.id.clone(),
            label: identity.label.clone(),
            demographic: identity.demographic.clone(),
            facility_location: identity.facility_location.clone(),
            population_count: demographics.population_count,
            overall_sentiment: sentiment.overall_sentiment,
            unrest: sentiment.unrest,
            total_wealth: economy.total_wealth,
            food_satisfaction: sentiment.food_satisfaction,
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
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
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
    let _ = tick_scale; // reserved for sentiment inertia scaling below

    // Index markets by location
    let market_at_location: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (id.facility_location.clone(), e))
        .collect();

    // Pre-collect population entity list to avoid aliasing
    let pop_entities: Vec<hecs::Entity> = world
        .query::<&PopIdentity>()
        .iter()
        .map(|(e, _)| e)
        .collect();

    // Sentiment inertia exponent: slower world_speed = slower drift.
    let inertia_factor = SENTIMENT_INERTIA_BASE.powf(tick_scale.max(0.01));

    for entity in pop_entities {
        let (location, consumption, production_commodity, production_amount, pop_size, current_food_sat) = {
            let mut q = match world
                .query_one::<(&PopIdentity, &PopEconomy, &PopDemographics, &PopSentiment)>(entity)
            {
                Ok(q) => q,
                Err(_) => continue,
            };
            match q.get() {
                Some((id, econ, demo, sent)) => (
                    id.facility_location.clone(),
                    econ.consumption.clone(),
                    econ.production_commodity,
                    econ.production_amount,
                    demo.population_count,
                    sent.food_satisfaction,
                ),
                None => continue,
            }
        };

        let market_entity = match market_at_location.get(&location) {
            Some(&e) => e,
            None => continue,
        };

        let mut any_shortage = false;

        // Consume
        if tick % consumption_interval == 0 {
            if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                for (commodity, amount) in consumption {
                    let available = pricing.supply.get(&commodity).copied().unwrap_or(0.0);
                    let consumed = amount.min(available);
                    if consumed < amount {
                        any_shortage = true;
                    }
                    if consumed > 0.0 {
                        let entry = pricing.supply.entry(commodity).or_insert(0.0);
                        *entry = (*entry - consumed).max(0.0);
                    }
                }

                // Emergency water consumption — when food satisfaction is
                // critical (< 30) pops drink deeper into local reserves.
                // Models Elixir's water-buy branch that fires below the
                // same threshold.
                if current_food_sat < EMERGENCY_WATER_THRESHOLD && pop_size > 0 {
                    let extra =
                        EMERGENCY_WATER_RATE * (pop_size as f32 / 1000.0).max(1.0);
                    let avail = pricing
                        .supply
                        .get(&Commodity::Water)
                        .copied()
                        .unwrap_or(0.0);
                    let taken = extra.min(avail);
                    if taken > 0.0 {
                        let entry = pricing.supply.entry(Commodity::Water).or_insert(0.0);
                        *entry = (*entry - taken).max(0.0);
                    }
                }
            }
        }

        // Produce
        if tick % production_interval == 0 {
            if let Some(commodity) = production_commodity {
                if production_amount > 0.0 {
                    if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                        *pricing.supply.entry(commodity).or_insert(0.0) += production_amount;
                    }
                }
            }
        }

        // Update sentiment based on food supply — apply inertia so the
        // overall_sentiment value doesn't swing ±50 on a single frame.
        if tick % consumption_interval == 0 {
            if let Ok(mut sentiment) = world.get::<&mut PopSentiment>(entity) {
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
    // payment + relaxed rep gate before permanently expiring.
    let delivery_lifespan =
        crate::agents::facility::FACILITY_DELIVERY_LIFESPAN_BASE * mult;
    contracts.sweep_expiring(tick, delivery_lifespan);
    contracts.age_open_reputation(tick);
    contracts.age_escalate_payment(tick);
}

fn post_passenger_contracts(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u64,
) {
    struct Candidate {
        pop_id: String,
        origin: String,
    }
    let candidates: Vec<Candidate> = world
        .query::<(&PopIdentity, &PopSentiment, &PopDemographics)>()
        .iter()
        .filter(|(_, (_, sent, demo))| {
            sent.overall_sentiment >= PASSENGER_MIN_SENTIMENT
                && demo.population_count >= PASSENGER_MIN_POPULATION
        })
        .map(|(_, (id, _, _))| Candidate {
            pop_id: id.id.clone(),
            origin: id.facility_location.clone(),
        })
        .collect();
    if candidates.is_empty() {
        return;
    }

    let all_destinations: Vec<String> = world
        .query::<&PopIdentity>()
        .iter()
        .map(|(_, id)| id.facility_location.clone())
        .collect();

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
        contracts.post_passenger(
            cand.pop_id,
            PASSENGER_BATCH_SIZE,
            cand.origin,
            destination,
            payment,
            tick,
            CONTRACT_LIFESPAN_BASE * tick_multiplier,
        );
    }
}

/// For each food-stressed population, post a delivery contract from the
/// richest known food source. Skips pops that already have a posted
/// contract in-flight (one contract per destination at a time).
fn post_food_contracts(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u64,
) {
    use crate::economy::commodities::Commodity;

    // Snapshot: location → food supply (for picking source)
    let food_supply_by_loc: std::collections::HashMap<String, f32> = world
        .query::<(&MarketIdentity, &MarketPricing)>()
        .iter()
        .map(|(_, (id, pricing))| {
            (
                id.facility_location.clone(),
                pricing.supply.get(&Commodity::Food).copied().unwrap_or(0.0),
            )
        })
        .collect();

    // Collect pop → decision info
    struct PopDecision {
        pop_id: String,
        destination: String,
        satisfaction: i32,
        population_count: i64,
    }
    let decisions: Vec<PopDecision> = world
        .query::<(&PopIdentity, &PopSentiment, &PopDemographics)>()
        .iter()
        .map(|(_, (id, sent, demo))| PopDecision {
            pop_id: id.id.clone(),
            destination: id.facility_location.clone(),
            satisfaction: sent.food_satisfaction,
            population_count: demo.population_count,
        })
        .collect();

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

        contracts.post_delivery(
            dec.pop_id,
            Commodity::Food,
            quantity,
            source,
            dec.destination,
            payment,
            tick,
            lifespan,
        );
    }
}

