//! Market components.

use crate::economy::{commodities::Commodity, order_book::Order};
use bevy_ecs::prelude::{Component, Entity, World};
use serde::Serialize;
use std::collections::{HashMap, VecDeque};

/// Stable identity.
#[derive(Debug, Clone, Component)]
pub struct MarketIdentity {
    pub db_id: i64,
    pub id: String,                   // "market-earth-station"
    pub facility: Entity,             // owning facility entity
    pub facility_location: String,    // "earth-station"
}

/// Pricing parameters and current prices.
#[derive(Debug, Clone, Component)]
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
#[derive(Debug, Clone, Component)]
pub struct MarketFlow {
    pub production: HashMap<Commodity, f32>,
    pub consumption: HashMap<Commodity, f32>,
    /// Rolling per-commodity consumption entries (tick, qty). Entries older
    /// than the demand window are trimmed each tick.
    pub consumption_window: HashMap<Commodity, Vec<(u64, f32)>>,
    /// Original seed demand — used as a cold-start floor during warmup.
    pub seed_demand: HashMap<Commodity, f32>,
}

/// Pending orders and escrowed reservations. Touched every market tick.
#[derive(Debug, Clone, Default, Component)]
pub struct MarketOrders {
    pub pending_buys: Vec<Order>,
    pub pending_sells: Vec<Order>,
    /// Goods reserved for remote buyers: commodity → (agent_id → qty).
    pub reserved: HashMap<Commodity, HashMap<String, f32>>,
    /// Monotonic counter for order ids issued by this market.
    pub next_order_id: u64,
    /// Monotonic counter for reserve ids.
    pub next_reserve_id: u64,
    /// Base expiry ticks for unmatched orders. Distance-aware expiry can extend it.
    pub order_expiry_ticks: u64,
}

/// Phase 20d: one trend snapshot for a market — captured every
/// `MARKET_TREND_SAMPLE_INTERVAL_BASE` base ticks. Carries tick timestamp
/// + per-commodity price + per-commodity supply so the UI can draw
/// "market watch" charts and supply-chain inspectors can see whether
/// a stuck production sub is on a long decline or a brief dip.
#[derive(Debug, Clone, Default)]
pub struct MarketTrendSample {
    pub tick: u64,
    pub prices: HashMap<Commodity, f32>,
    pub supply: HashMap<Commodity, f32>,
}

/// Historical/telemetry data — rarely touched by core logic.
#[derive(Debug, Clone, Default, Component)]
pub struct MarketHistory {
    /// Phase 20d: rolling time-series ring of `MarketTrendSample`s.
    /// Sampled every `MARKET_TREND_SAMPLE_INTERVAL_BASE` base ticks
    /// inside `tick_one_market`'s price recompute, capped at
    /// `MARKET_TREND_KEEP` entries. Replaces the older untimed
    /// per-tick `price_history` (no callers read it; this richer
    /// shape is what the UI needs).
    pub trend_samples: VecDeque<MarketTrendSample>,
    pub trade_volume: HashMap<Commodity, f32>,
    pub shortage_ticks: HashMap<Commodity, u32>,
    pub last_tick: u64,
    /// Tick the market was spawned at — demand warmup expires after the first
    /// `DEMAND_WARMUP_TICKS` so cold-start seed demand holds the floor.
    pub spawned_at_tick: Option<u64>,
    pub dirty: bool,
    /// Bundle (S): per-commodity crisis notification flag. Set to
    /// true when shortage crosses `MARKET_CRISIS_SHORTAGE_TICKS`,
    /// cleared when shortage recovers below
    /// `MARKET_CRISIS_RECOVERY_TICKS`. Prevents the scan pass from
    /// emitting duplicate `market_crisis` events every tick once
    /// the flag is raised.
    pub crisis_notified: HashMap<Commodity, bool>,
}

/// Bundle (S): a commodity has been short on this market for this
/// many consecutive ticks → structural shortage, emit a
/// `market_crisis` event. Set well above the facility-contract
/// threshold (30) and the subsidy threshold (600) so crises mark
/// the point where market self-repair has clearly failed.
pub const MARKET_CRISIS_SHORTAGE_TICKS: u32 = 200;

/// Bundle (S): shortage_ticks drop to at-or-below this → clear the
/// crisis-notified flag so a future recurrence fires again. Gap
/// vs `MARKET_CRISIS_SHORTAGE_TICKS` is the hysteresis window —
/// prevents flapping events around the threshold boundary.
pub const MARKET_CRISIS_RECOVERY_TICKS: u32 = 50;

/// Phase 20d: per-tick trend point flattened to string-keyed maps for
/// JSON / WS clients. Mirrors `MarketTrendSample` but with `String`
/// commodity keys so it serialises cleanly without depending on
/// `Commodity`'s ad-hoc `as_str` everywhere.
#[derive(Debug, Clone, Serialize)]
pub struct MarketTrendSnapshot {
    pub tick: u64,
    pub prices: HashMap<String, f32>,
    pub supply: HashMap<String, f32>,
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
    /// Phase 20d: rolling time-series samples drained from the
    /// in-memory `MarketHistory.trend_samples` ring. Capped at
    /// `MARKET_TREND_KEEP` entries; oldest at index 0, newest at the
    /// end. Drives the `/api/markets/:loc/trends` endpoint and the
    /// embedded Bevy markets panel's sparkline view.
    pub trend_samples: Vec<MarketTrendSnapshot>,
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
        let trend_samples = history
            .trend_samples
            .iter()
            .map(|s| MarketTrendSnapshot {
                tick: s.tick,
                prices: f_map(&s.prices),
                supply: f_map(&s.supply),
            })
            .collect();
        Self {
            id: identity.id.clone(),
            facility_location: identity.facility_location.clone(),
            prices: f_map(&pricing.prices),
            supply: f_map(&pricing.supply),
            demand: f_map(&pricing.demand),
            shortage_ticks: u_map(&history.shortage_ticks),
            trend_samples,
        }
    }
}

// ============================================================================
// Tick logic
// ============================================================================
//
// Mirrors the Elixir MarketAgent 8-phase tick:
//   1. production    — add production output (on interval)
//   2. consumption   — subtract local consumption (on interval), record to window
//   3. emergency     — market-internal buy orders for critical commodities
//   4. surplus       — market-internal sell orders for oversupplied commodities
//   5. match_orders  — OrderBook matches buys vs sells, supply/volume updated
//   6. update_demand — recompute demand from rolling consumption window
//   7. track_shortage — per-commodity consecutive-ticks-under-threshold counter
//   8. update_prices  — PriceEngine applies supply-vs-demand pressure with urgency
// Followed by cleanup: expire orders, expire reservations.

use crate::economy::{
    commodities::Commodity as _Commodity,

    price_engine,
};
use crate::simulation::commands::CommandBuffer;

/// How many ticks between production/consumption cycles at the default tick rate.
/// Actual interval in ticks = PROD_CONS_INTERVAL_BASE * tick_multiplier (32 = every 160 ticks).
pub const PROD_CONS_INTERVAL_BASE: u64 = 5;
/// How many ticks between emergency/surplus order placements.
pub const EMERGENCY_INTERVAL_BASE: u64 = 10;
/// Demand estimation window, in base ticks at 1x world speed.
pub const DEMAND_WINDOW_BASE: u64 = 100;
/// Warmup period during which seed demand holds as a floor.
pub const DEMAND_WARMUP_BASE: u64 = 50;
/// Reserve expiry, in base ticks at 1x world speed.
pub const RESERVE_EXPIRY_BASE: u64 = 200;

pub const SHORTAGE_SUPPLY_RATIO: f32 = 0.1;
pub const SHORTAGE_MIN_FLOOR: f32 = 10.0;
pub const SURPLUS_THRESHOLD_MULTIPLIER: f32 = 5.0;
pub const SURPLUS_DISCOUNT: f32 = 0.8;
pub const PRICE_HISTORY_KEEP: usize = 100;

/// Phase 20d: how often `tick_one_market` writes a fresh
/// `MarketTrendSample` into the rolling history ring. 16 base ticks =
/// one sample every two simulated seconds at the default 8 tps, which
/// yields readable line plots without flooding the buffer. Aligns
/// with the WS `market_states` broadcast cadence so trend data lands
/// on the same beats clients already expect.
pub const MARKET_TREND_SAMPLE_INTERVAL_BASE: u64 = 16;

/// Phase 20d: trend ring depth. 200 entries × 16-tick interval =
/// 3200 base ticks of history (~6.6 min at 1× WORLD_SPEED, ~100 s
/// at 4×). Memory cost: ~200 samples × ~6 commodities × 12 bytes
/// per (price + supply) value × 39 markets ≈ 1.1 MB for the whole
/// world — well under any concern.
pub const MARKET_TREND_KEEP: usize = 200;

/// Tick all markets in the world. Serial iteration — 23 markets is trivial.
/// Phase 3 implementation. Adds to `commands` for cross-agent effects.
pub fn tick_markets(
    world: &mut World,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_multiplier: u32,
) {
    let mult = tick_multiplier as u64;
    let prod_interval = PROD_CONS_INTERVAL_BASE * mult;
    let emerg_interval = EMERGENCY_INTERVAL_BASE * mult;
    let demand_window = DEMAND_WINDOW_BASE * mult;
    let demand_warmup = DEMAND_WARMUP_BASE * mult;
    let reserve_expiry = RESERVE_EXPIRY_BASE * mult;

    // Collect entity IDs first to avoid aliasing issues while we iterate.
    let market_entities: Vec<Entity> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(&world).map(|(e, _)| e).collect()
    };

    for entity in market_entities {
        tick_one_market(
            world,
            entity,
            commands,
            tick,
            prod_interval,
            emerg_interval,
            demand_window,
            demand_warmup,
            reserve_expiry,
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn tick_one_market(
    world: &mut World,
    entity: Entity,
    _commands: &mut CommandBuffer,
    tick: u64,
    prod_interval: u64,
    _emerg_interval: u64,
    demand_window: u64,
    demand_warmup: u64,
    reserve_expiry: u64,
) {
    // Pull all the components we'll mutate. hecs's query_one_mut is ideal for
    // operating on a single entity with multiple component refs.
    let mut q = world.query::<(
        &MarketIdentity,
        &mut MarketPricing,
        &mut MarketFlow,
        &mut MarketOrders,
        &mut MarketHistory,
    )>();
    let Ok((_identity, mut pricing, mut flow, mut orders, mut history)) = q.get_mut(world, entity)
    else {
        return;
    };

    // Initialize spawned_at_tick on first tick
    if history.spawned_at_tick.is_none() {
        history.spawned_at_tick = Some(tick);
        // Capture seed demand on first tick if not already set
        if flow.seed_demand.is_empty() {
            flow.seed_demand = pricing.demand.clone();
        }
    }
    history.last_tick = tick;

    // --- 1. Production ---
    if tick % prod_interval == 0 {
        for (&commodity, &amount) in &flow.production {
            *pricing.supply.entry(commodity).or_insert(0.0) += amount;
        }
    }

    // --- 2. Consumption ---
    if tick % prod_interval == 0 {
        for (&commodity, &amount) in &flow.consumption.clone() {
            let entry = pricing.supply.entry(commodity).or_insert(0.0);
            *entry = (*entry - amount).max(0.0);
            record_consumption(&mut flow, commodity, amount, tick);
        }
    }

    // Legacy anonymous orders have neither a cash payer nor a cargo owner.
    // Do not "settle" them by mutating supply or minting spread revenue.
    // Actual exchanges commit through native ship/facility transactions.
    orders.pending_buys.retain(|o| !o.agent_id.starts_with("market-"));
    orders.pending_sells.retain(|o| !o.agent_id.starts_with("market-"));

    // --- 6. Update demand ---
    let cutoff = tick.saturating_sub(demand_window);
    let warming_up = tick.saturating_sub(history.spawned_at_tick.unwrap_or(tick)) < demand_warmup;

    // Trim stale window entries and compute observed qty
    let mut observed: HashMap<_Commodity, f32> = HashMap::new();
    for (&commodity, entries) in flow.consumption_window.iter_mut() {
        entries.retain(|(t, _)| *t >= cutoff);
        let sum: f32 = entries.iter().map(|(_, q)| q).sum();
        if sum > 0.0 {
            observed.insert(commodity, sum);
        }
    }

    // Merge seed + observed
    let all_commodities: std::collections::HashSet<_Commodity> = flow
        .seed_demand
        .keys()
        .copied()
        .chain(observed.keys().copied())
        .collect();

    let mut new_demand: HashMap<_Commodity, f32> = HashMap::new();
    for commodity in all_commodities {
        let obs = observed.get(&commodity).copied().unwrap_or(0.0);
        let seed = flow.seed_demand.get(&commodity).copied().unwrap_or(0.0);
        let value = if warming_up {
            obs.max(seed)
        } else if obs > 0.0 {
            obs
        } else {
            seed
        };
        new_demand.insert(commodity, value);
    }
    pricing.demand = new_demand;

    // --- 7. Track shortage ---
    let supply_snapshot: HashMap<_Commodity, f32> = pricing.supply.clone();
    let demand_snapshot: HashMap<_Commodity, f32> = pricing.demand.clone();
    let prices_snapshot: Vec<_Commodity> = pricing.prices.keys().copied().collect();
    for commodity in prices_snapshot {
        let supply = supply_snapshot.get(&commodity).copied().unwrap_or(0.0);
        let demand = demand_snapshot.get(&commodity).copied().unwrap_or(0.0);
        let threshold = (demand * SHORTAGE_SUPPLY_RATIO).max(SHORTAGE_MIN_FLOOR);

        if supply < threshold && demand > 0.0 {
            *history.shortage_ticks.entry(commodity).or_insert(0) += 1;
        } else {
            history.shortage_ticks.insert(commodity, 0);
        }
    }

    // --- 8. Update prices ---
    let elasticity = pricing.price_elasticity;
    let new_prices: HashMap<_Commodity, f32> = pricing
        .prices
        .iter()
        .map(|(&commodity, &current_price)| {
            let supply = supply_snapshot.get(&commodity).copied().unwrap_or(0.0);
            let demand = demand_snapshot.get(&commodity).copied().unwrap_or(0.0);
            let urgency = history.shortage_ticks.get(&commodity).copied().unwrap_or(0);
            let new = price_engine::recalculate(current_price, supply, demand, elasticity, urgency);
            (commodity, new)
        })
        .collect();
    pricing.prices = new_prices.clone();

    // Phase 20d: sample the trend ring every
    // `MARKET_TREND_SAMPLE_INTERVAL_BASE` base ticks. The price
    // recompute itself fires every tick, so we gate sample insertion
    // here rather than the call site to keep the cadence local.
    if tick.is_multiple_of(MARKET_TREND_SAMPLE_INTERVAL_BASE) {
        history.trend_samples.push_back(MarketTrendSample {
            tick,
            prices: new_prices,
            supply: pricing.supply.clone(),
        });
        while history.trend_samples.len() > MARKET_TREND_KEEP {
            history.trend_samples.pop_front();
        }
    }

    // --- Cleanup: expire old orders ---
    let expiry = orders.order_expiry_ticks.max(50);
    orders
        .pending_buys
        .retain(|o| tick < o.placed_at_tick + expiry);
    orders
        .pending_sells
        .retain(|o| tick < o.placed_at_tick + expiry);

    // --- Cleanup: expire reservations ---
    // Reserved goods map: commodity -> (owner_id -> qty). We track reserve age
    // elsewhere (pending design for Phase 4). For now, use a simple time-to-live
    // based on `reserve_expiry` relative to tick — returning released goods to supply.
    // Placeholder: no reserve TTL yet.
    let _ = reserve_expiry;

    history.dirty = true;
}

pub(crate) fn record_consumption(flow: &mut MarketFlow, commodity: _Commodity, qty: f32, tick: u64) {
    if qty <= 0.0 {
        return;
    }
    flow.consumption_window
        .entry(commodity)
        .or_default()
        .push((tick, qty));
}

#[cfg(test)]
mod trend_tests {
    use super::*;

    /// Push 250 trend samples — the deque must cap at MARKET_TREND_KEEP
    /// and drop the oldest entries. Failure here means the sampling
    /// loop in `tick_one_market` could grow the buffer without bound.
    #[test]
    fn trend_ring_caps_at_keep_constant() {
        let mut h = MarketHistory::default();
        for t in 0..250u64 {
            h.trend_samples.push_back(MarketTrendSample {
                tick: t,
                prices: HashMap::new(),
                supply: HashMap::new(),
            });
            while h.trend_samples.len() > MARKET_TREND_KEEP {
                h.trend_samples.pop_front();
            }
        }
        assert_eq!(h.trend_samples.len(), MARKET_TREND_KEEP);
        // Newest sample is the last tick we pushed.
        assert_eq!(h.trend_samples.back().unwrap().tick, 249);
        // Oldest is `250 - KEEP`.
        assert_eq!(
            h.trend_samples.front().unwrap().tick,
            250 - MARKET_TREND_KEEP as u64
        );
    }

    /// Sample interval must be ≥ the production cycle so each sample
    /// captures the effect of at least one full prod/consumption pass.
    /// 16 / 5 = 3.2 prod cycles per sample is fine; the warning
    /// guards against someone slashing the interval below the prod
    /// cadence and getting flat-line charts.
    #[test]
    fn trend_interval_observes_at_least_one_prod_cycle() {
        assert!(MARKET_TREND_SAMPLE_INTERVAL_BASE >= PROD_CONS_INTERVAL_BASE);
    }

    /// Trend ring captures both price + supply per commodity. Verifies
    /// the field shape — guards against an accidental drop of the
    /// `supply` field during a future refactor (the UI would silently
    /// stop drawing the supply line).
    #[test]
    fn trend_sample_records_both_price_and_supply() {
        let s = MarketTrendSample {
            tick: 100,
            prices: HashMap::from([(Commodity::Fuel, 12.5)]),
            supply: HashMap::from([(Commodity::Fuel, 480.0)]),
        };
        assert_eq!(s.prices.get(&Commodity::Fuel), Some(&12.5));
        assert_eq!(s.supply.get(&Commodity::Fuel), Some(&480.0));
    }
}
