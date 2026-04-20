use crate::economy::commodities::Commodity;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Order {
    pub id: u64,
    pub agent_id: String,
    pub order_type: OrderType,
    pub commodity: Commodity,
    pub quantity: u32,
    /// Max price buyer will pay, or min price seller will accept.
    pub price: f32,
    pub placed_at_tick: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OrderType {
    Buy,
    Sell,
}

#[derive(Debug, Clone)]
pub struct Trade {
    pub buyer_id: String,
    pub seller_id: String,
    pub commodity: Commodity,
    pub quantity: u32,
    pub price: f32,
    pub total_cost: f32,
}

/// Pure functional order matching engine.
///
/// Matches buy orders against sell orders when buyer's max price ≥ seller's min price.
/// Trade executes at the midpoint minus the market spread.
/// Supports partial fills — orders with remaining quantity are returned as remainders.
///
/// Returns `(trades, remaining_buys, remaining_sells)`.
pub fn match_orders(
    mut buy_orders: Vec<Order>,
    mut sell_orders: Vec<Order>,
    spread: f32,
) -> (Vec<Trade>, Vec<Order>, Vec<Order>) {
    // Most aggressive buyer first; cheapest seller first
    buy_orders.sort_by(|a, b| b.price.partial_cmp(&a.price).unwrap_or(std::cmp::Ordering::Equal));
    sell_orders.sort_by(|a, b| a.price.partial_cmp(&b.price).unwrap_or(std::cmp::Ordering::Equal));

    let mut trades = Vec::new();
    let mut buy_iter = buy_orders.into_iter().peekable();
    let mut sell_iter = sell_orders.into_iter().peekable();

    let mut current_buy: Option<Order> = buy_iter.next();
    let mut current_sell: Option<Order> = sell_iter.next();

    while let (Some(buy), Some(sell)) = (current_buy.as_mut(), current_sell.as_mut()) {
        if buy.price < sell.price {
            // Best buy can't meet cheapest sell — no more matches possible
            break;
        }

        let midpoint = (buy.price + sell.price) / 2.0;
        let trade_price = midpoint * (1.0 - spread / 2.0);
        let trade_qty = buy.quantity.min(sell.quantity);

        trades.push(Trade {
            buyer_id: buy.agent_id.clone(),
            seller_id: sell.agent_id.clone(),
            commodity: buy.commodity,
            quantity: trade_qty,
            price: trade_price,
            total_cost: trade_price * trade_qty as f32,
        });

        buy.quantity -= trade_qty;
        sell.quantity -= trade_qty;

        if buy.quantity == 0 {
            current_buy = buy_iter.next();
        }
        if sell.quantity == 0 {
            current_sell = sell_iter.next();
        }
    }

    // Collect remaining unfilled orders
    let mut remaining_buys: Vec<Order> = Vec::new();
    if let Some(b) = current_buy {
        remaining_buys.push(b);
    }
    remaining_buys.extend(buy_iter);

    let mut remaining_sells: Vec<Order> = Vec::new();
    if let Some(s) = current_sell {
        remaining_sells.push(s);
    }
    remaining_sells.extend(sell_iter);

    (trades, remaining_buys, remaining_sells)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn buy(id: u64, agent: &str, qty: u32, price: f32) -> Order {
        Order {
            id,
            agent_id: agent.into(),
            order_type: OrderType::Buy,
            commodity: Commodity::Ore,
            quantity: qty,
            price,
            placed_at_tick: 1,
        }
    }

    fn sell(id: u64, agent: &str, qty: u32, price: f32) -> Order {
        Order {
            id,
            agent_id: agent.into(),
            order_type: OrderType::Sell,
            commodity: Commodity::Ore,
            quantity: qty,
            price,
            placed_at_tick: 1,
        }
    }

    #[test]
    fn single_full_match() {
        let buys = vec![buy(1, "ship1", 100, 50.0)];
        let sells = vec![sell(2, "miner", 100, 40.0)];
        let (trades, rem_b, rem_s) = match_orders(buys, sells, 0.10);
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].quantity, 100);
        assert!(rem_b.is_empty());
        assert!(rem_s.is_empty());
        // midpoint = 45.0, trade_price = 45.0 * (1 - 0.05) = 42.75
        assert!((trades[0].price - 42.75).abs() < 0.01);
    }

    #[test]
    fn partial_fill_buy_larger() {
        let buys = vec![buy(1, "ship1", 200, 50.0)];
        let sells = vec![sell(2, "miner", 80, 40.0)];
        let (trades, rem_b, rem_s) = match_orders(buys, sells, 0.0);
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].quantity, 80);
        assert_eq!(rem_b.len(), 1);
        assert_eq!(rem_b[0].quantity, 120); // 200 - 80 remaining
        assert!(rem_s.is_empty());
    }

    #[test]
    fn partial_fill_sell_larger() {
        let buys = vec![buy(1, "ship1", 50, 50.0)];
        let sells = vec![sell(2, "miner", 200, 40.0)];
        let (trades, rem_b, rem_s) = match_orders(buys, sells, 0.0);
        assert_eq!(trades[0].quantity, 50);
        assert!(rem_b.is_empty());
        assert_eq!(rem_s[0].quantity, 150);
    }

    #[test]
    fn no_match_when_prices_dont_cross() {
        let buys = vec![buy(1, "ship1", 100, 30.0)];
        let sells = vec![sell(2, "miner", 100, 40.0)];
        let (trades, rem_b, rem_s) = match_orders(buys, sells, 0.0);
        assert!(trades.is_empty());
        assert_eq!(rem_b.len(), 1);
        assert_eq!(rem_s.len(), 1);
    }

    #[test]
    fn multiple_orders_sorted_correctly() {
        // Two buyers: one at 60, one at 45
        // Two sellers: one at 50, one at 35
        // Expected: buyer@60 matches seller@35 first (cheapest sell), then seller@50
        let buys = vec![buy(1, "b1", 100, 45.0), buy(2, "b2", 100, 60.0)];
        let sells = vec![sell(3, "s1", 100, 50.0), sell(4, "s2", 100, 35.0)];
        let (trades, _rem_b, _rem_s) = match_orders(buys, sells, 0.0);
        // b2@60 vs s2@35 → match (midpoint 47.5)
        // b1@45 vs s1@50 → no match (buy < sell)
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].buyer_id, "b2");
        assert_eq!(trades[0].seller_id, "s2");
    }

    #[test]
    fn empty_inputs_return_empty() {
        let (t, b, s) = match_orders(vec![], vec![], 0.1);
        assert!(t.is_empty());
        assert!(b.is_empty());
        assert!(s.is_empty());
    }

    #[test]
    fn spread_reduces_trade_price() {
        let buys = vec![buy(1, "b", 10, 100.0)];
        let sells = vec![sell(2, "s", 10, 100.0)];
        // midpoint = 100, with 10% spread: 100 * (1 - 0.05) = 95
        let (trades_with, _, _) = match_orders(buys.clone(), sells.clone(), 0.10);
        let (trades_no, _, _) = match_orders(buys, sells, 0.0);
        assert!(trades_with[0].price < trades_no[0].price);
        assert!((trades_with[0].price - 95.0).abs() < 0.01);
    }
}
