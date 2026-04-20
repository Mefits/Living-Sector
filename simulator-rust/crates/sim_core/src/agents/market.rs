//! Market components.

use crate::economy::{commodities::Commodity, order_book::Order};
use hecs::Entity;
use serde::Serialize;
use std::collections::{HashMap, VecDeque};

/// Stable identity.
#[derive(Debug, Clone)]
pub struct MarketIdentity {
    pub db_id: i64,
    pub id: String,                   // "market-earth-station"
    pub facility: Entity,             // owning facility entity
    pub facility_location: String,    // "earth-station"
}

/// Pricing parameters and current prices.
#[derive(Debug, Clone)]
pub struct MarketPricing {
    pub price_elasticity: f32,
    pub spread: f32,
    pub prices: HashMap<Commodity, f32>,
    pub supply: HashMap<Commodity, f32>,
    pub demand: HashMap<Commodity, f32>,
}

impl MarketPricing {
    pub fn price(&self, commodity: Commodity) -> f32 {
        self.prices.get(&commodity).copied().unwrap_or(commodity.base_price())
    }
}

/// Production & consumption rates plus rolling window for demand estimation.
#[derive(Debug, Clone)]
pub struct MarketFlow {
    pub production: HashMap<Commodity, f32>,
    pub consumption: HashMap<Commodity, f32>,
    /// Last ~100 ticks of consumption; used to smooth demand estimates.
    pub consumption_window: VecDeque<HashMap<Commodity, f32>>,
}

/// Pending orders and escrowed reservations. Touched every market tick.
#[derive(Debug, Clone, Default)]
pub struct MarketOrders {
    pub pending_buys: Vec<Order>,
    pub pending_sells: Vec<Order>,
    /// Goods reserved for remote buyers: commodity → (agent_id → qty).
    pub reserved: HashMap<Commodity, HashMap<String, f32>>,
}

/// Historical/telemetry data — rarely touched by core logic.
#[derive(Debug, Clone, Default)]
pub struct MarketHistory {
    pub price_history: VecDeque<HashMap<Commodity, f32>>,
    pub trade_volume: HashMap<Commodity, f32>,
    pub shortage_ticks: HashMap<Commodity, u32>,
    pub last_tick: u64,
    pub dirty: bool,
}

/// Snapshot for HTTP/WS — built from components.
#[derive(Debug, Clone, Serialize)]
pub struct MarketSnapshot {
    pub id: String,
    pub facility_location: String,
    pub prices: HashMap<String, f32>,
    pub supply: HashMap<String, f32>,
    pub demand: HashMap<String, f32>,
    pub shortage_ticks: HashMap<String, u32>,
}

impl MarketSnapshot {
    pub fn build(
        identity: &MarketIdentity,
        pricing: &MarketPricing,
        history: &MarketHistory,
    ) -> Self {
        let f_map = |m: &HashMap<Commodity, f32>| {
            m.iter().map(|(c, &v)| (c.as_str().to_string(), v)).collect()
        };
        let u_map = |m: &HashMap<Commodity, u32>| {
            m.iter().map(|(c, &v)| (c.as_str().to_string(), v)).collect()
        };
        Self {
            id: identity.id.clone(),
            facility_location: identity.facility_location.clone(),
            prices: f_map(&pricing.prices),
            supply: f_map(&pricing.supply),
            demand: f_map(&pricing.demand),
            shortage_ticks: u_map(&history.shortage_ticks),
        }
    }
}
