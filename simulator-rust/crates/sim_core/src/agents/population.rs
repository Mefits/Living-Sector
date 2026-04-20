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
/// Food satisfaction decays by this per unsatisfied cycle (clamped 0-100).
pub const FOOD_SAT_DROP_ON_SHORTAGE: i32 = 5;
pub const FOOD_SAT_RECOVER_ON_MET: i32 = 2;

/// Food satisfaction below this triggers a delivery contract post.
pub const CONTRACT_FOOD_THRESHOLD: i32 = 40;
/// Contracts expire after this many base-ticks unposted.
pub const CONTRACT_LIFESPAN_BASE: u64 = 200;
/// Pay multiplier over base price for delivery contracts.
pub const CONTRACT_PREMIUM: f32 = 1.8;

pub fn tick_populations(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u32,
) {
    let mult = tick_multiplier as u64;
    let consumption_interval = CONSUMPTION_INTERVAL_BASE * mult;
    let production_interval = PRODUCTION_INTERVAL_BASE * mult;

    if tick % consumption_interval != 0 && tick % production_interval != 0 {
        return;
    }

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

    for entity in pop_entities {
        let (location, consumption, production_commodity, production_amount) = {
            let mut q = match world
                .query_one::<(&PopIdentity, &PopEconomy)>(entity)
            {
                Ok(q) => q,
                Err(_) => continue,
            };
            match q.get() {
                Some((id, econ)) => (
                    id.facility_location.clone(),
                    econ.consumption.clone(),
                    econ.production_commodity,
                    econ.production_amount,
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

        // Update sentiment based on food supply
        if tick % consumption_interval == 0 {
            if let Ok(mut sentiment) = world.get::<&mut PopSentiment>(entity) {
                if any_shortage {
                    sentiment.food_satisfaction =
                        (sentiment.food_satisfaction - FOOD_SAT_DROP_ON_SHORTAGE).max(0);
                } else {
                    sentiment.food_satisfaction =
                        (sentiment.food_satisfaction + FOOD_SAT_RECOVER_ON_MET).min(100);
                }
                sentiment.overall_sentiment = (sentiment.food_satisfaction * 6
                    + sentiment.safety_satisfaction * 2
                    + sentiment.entertainment_satisfaction * 2)
                    / 10;
                sentiment.unrest = (100 - sentiment.overall_sentiment).clamp(0, 100);
                sentiment.dirty = true;
            }
        }
    }

    // Separate pass for contract posting — populations stressed on food
    // post delivery contracts. We do this after the consumption pass so
    // food_satisfaction is up-to-date, and we read the board state that's
    // already been updated above.
    let contract_interval = CONTRACT_POST_INTERVAL_BASE * mult;
    if tick % contract_interval == 0 {
        post_food_contracts(world, contracts, tick, mult);
    }

    // Expire old unfilled contracts
    contracts.expire(tick);
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

        // Scale order size to population (more people → bigger need),
        // capped at a reasonable ship-load.
        let quantity = (dec.population_count / 1000).clamp(20, 300) as u32;
        // Payment scales with commodity base price × premium × quantity.
        let payment =
            (Commodity::Food.base_price() * CONTRACT_PREMIUM * quantity as f32) as i64;

        contracts.post_delivery(
            dec.pop_id,
            Commodity::Food,
            quantity,
            source,
            dec.destination,
            payment,
            tick,
            CONTRACT_LIFESPAN_BASE * tick_multiplier,
        );
    }
}
