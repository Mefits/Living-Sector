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
        let _ = economy; // economy not exposed in snapshot currently
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
