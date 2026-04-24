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
    /// Rolling per-commodity consumption entries (tick, qty). Entries older
    /// than the demand window are trimmed each tick.
    pub consumption_window: HashMap<Commodity, Vec<(u64, f32)>>,
    /// Original seed demand — used as a cold-start floor during warmup.
    pub seed_demand: HashMap<Commodity, f32>,
}

/// Pending orders and escrowed reservations. Touched every market tick.
#[derive(Debug, Clone, Default)]
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

/// Historical/telemetry data — rarely touched by core logic.
#[derive(Debug, Clone, Default)]
pub struct MarketHistory {
    pub price_history: VecDeque<HashMap<Commodity, f32>>,
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
    order_book::{match_orders as match_fn, OrderType},
    price_engine,
};
use crate::simulation::commands::{CommandBuffer, SimCommand};

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

/// Essential commodities: (threshold, order_qty, premium_multiplier).
/// When supply < threshold, market posts an emergency buy order at premium price.
fn essential_commodities() -> &'static [(_Commodity, f32, u32, f32)] {
    use _Commodity::*;
    &[
        (Fuel, 50.0, 500, 1.5),
        (Food, 50.0, 300, 1.5),
        (Water, 30.0, 200, 1.3),
        (Metals, 30.0, 200, 1.3),
        (Tools, 20.0, 100, 1.4),
        (Ore, 50.0, 300, 1.2),
        (Ice, 50.0, 300, 1.2),
    ]
}

/// Tick all markets in the world. Serial iteration — 23 markets is trivial.
/// Phase 3 implementation. Adds to `commands` for cross-agent effects.
pub fn tick_markets(
    world: &mut hecs::World,
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
    let market_entities: Vec<hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, _)| e)
        .collect();

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
    world: &mut hecs::World,
    entity: hecs::Entity,
    commands: &mut CommandBuffer,
    tick: u64,
    prod_interval: u64,
    emerg_interval: u64,
    demand_window: u64,
    demand_warmup: u64,
    reserve_expiry: u64,
) {
    // Pull all the components we'll mutate. hecs's query_one_mut is ideal for
    // operating on a single entity with multiple component refs.
    let mut query = world
        .query_one::<(
            &MarketIdentity,
            &mut MarketPricing,
            &mut MarketFlow,
            &mut MarketOrders,
            &mut MarketHistory,
        )>(entity)
        .expect("market entity should have all 5 components");

    let (identity, pricing, flow, orders, history) = match query.get() {
        Some(tuple) => tuple,
        None => return,
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
            record_consumption(flow, commodity, amount, tick);
        }
    }

    // --- 3. Emergency orders ---
    if tick % emerg_interval == 0 {
        for (commodity, threshold, qty, premium) in essential_commodities() {
            let supply = pricing.supply.get(commodity).copied().unwrap_or(0.0);
            let demand = pricing.demand.get(commodity).copied().unwrap_or(0.0);

            if supply < *threshold && demand > 0.0 {
                let has_emergency = orders
                    .pending_buys
                    .iter()
                    .any(|o| o.commodity == *commodity && o.agent_id == "market-emergency");
                if !has_emergency {
                    let base_price = pricing.prices.get(commodity).copied().unwrap_or(50.0);
                    let price = base_price * premium;
                    orders.next_order_id += 1;
                    orders.pending_buys.push(crate::economy::order_book::Order {
                        id: orders.next_order_id,
                        agent_id: "market-emergency".into(),
                        order_type: OrderType::Buy,
                        commodity: *commodity,
                        quantity: *qty,
                        price,
                        placed_at_tick: tick,
                    });
                }
            }
        }
    }

    // --- 4. Surplus orders ---
    if tick % emerg_interval == 0 {
        let commodities: Vec<_Commodity> = pricing.supply.keys().copied().collect();
        for commodity in commodities {
            let supply = pricing.supply.get(&commodity).copied().unwrap_or(0.0);
            let demand = pricing.demand.get(&commodity).copied().unwrap_or(0.0);
            let threshold = (demand * SURPLUS_THRESHOLD_MULTIPLIER).max(500.0);

            if supply > threshold {
                let has_surplus = orders
                    .pending_sells
                    .iter()
                    .any(|o| o.commodity == commodity && o.agent_id == "market-surplus");
                if !has_surplus {
                    let base_price = pricing.prices.get(&commodity).copied().unwrap_or(10.0);
                    let price = base_price * SURPLUS_DISCOUNT;
                    // Offer up to 20% of excess supply
                    let excess = supply - (threshold / 2.0);
                    let qty = ((excess * 0.2).min(500.0) as u32).max(1);
                    if qty > 0 {
                        orders.next_order_id += 1;
                        orders.pending_sells.push(crate::economy::order_book::Order {
                            id: orders.next_order_id,
                            agent_id: "market-surplus".into(),
                            order_type: OrderType::Sell,
                            commodity,
                            quantity: qty,
                            price,
                            placed_at_tick: tick,
                        });
                    }
                }
            }
        }
    }

    // --- 5. Match orders ---
    // Group by commodity, match each, collect trades for cross-agent effects.
    let spread = pricing.spread;
    let all_buys = std::mem::take(&mut orders.pending_buys);
    let all_sells = std::mem::take(&mut orders.pending_sells);

    let mut remaining_buys: Vec<_> = Vec::new();
    let mut remaining_sells: Vec<_> = Vec::new();

    for commodity in _Commodity::ALL {
        let buys: Vec<_> = all_buys.iter().filter(|o| o.commodity == *commodity).cloned().collect();
        let sells: Vec<_> = all_sells.iter().filter(|o| o.commodity == *commodity).cloned().collect();

        if buys.is_empty() && sells.is_empty() {
            continue;
        }

        let (trades, rem_b, rem_s) = match_fn(buys, sells, spread);

        for trade in &trades {
            // Track volume
            *history.trade_volume.entry(*commodity).or_insert(0.0) += trade.quantity as f32;

            // Normal buyers: supply decreases. Emergency market buys: supply increases (restocking).
            if trade.buyer_id == "market-emergency" {
                // Market bought to restock — supply goes UP
                *pricing.supply.entry(*commodity).or_insert(0.0) += trade.quantity as f32;
            } else {
                // Normal buyer — supply goes down, record as real consumption signal
                let entry = pricing.supply.entry(*commodity).or_insert(0.0);
                *entry = (*entry - trade.quantity as f32).max(0.0);
                record_consumption(flow, *commodity, trade.quantity as f32, tick);
            }

            // Spread revenue to owning facility (via command buffer for deterministic timing)
            let spread_revenue = (trade.quantity as f32 * trade.price * spread / 2.0) as i64;
            if spread_revenue > 0 {
                commands.push(SimCommand::TransferCredits {
                    from: entity, // placeholder: market entity isn't a real credit-holder
                    to: identity.facility,
                    amount: spread_revenue,
                });
            }
        }

        // Non-market-internal trades should settle cargo/credits between real agents.
        // For Phase 3 there are no ships yet; commands are emitted but no real
        // participants. Phase 4 adds the settlement path via ExecuteTrade.
        for trade in trades {
            if !trade.buyer_id.starts_with("market-") && !trade.seller_id.starts_with("market-") {
                // We only have string ids at this layer; real Entity resolution
                // happens in the engine apply-phase for Phase 4.
                // For now, record as executed trade for logging/analytics.
                let _ = trade;
            }
        }

        remaining_buys.extend(rem_b);
        remaining_sells.extend(rem_s);
    }

    orders.pending_buys = remaining_buys;
    orders.pending_sells = remaining_sells;

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

    // Push price snapshot onto history (keep last N)
    history.price_history.push_back(new_prices);
    while history.price_history.len() > PRICE_HISTORY_KEEP {
        history.price_history.pop_front();
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

fn record_consumption(flow: &mut MarketFlow, commodity: _Commodity, qty: f32, tick: u64) {
    if qty <= 0.0 {
        return;
    }
    flow.consumption_window
        .entry(commodity)
        .or_default()
        .push((tick, qty));
}
