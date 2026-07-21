//! Pure consideration functions used by the utility AI.
//!
//! Each function takes one or more ship components and returns a `Consideration`
//! (value 0.0–1.0 paired with the personality axis it targets). The utility
//! scorer multiplies values by personality weights to rank goals.

use crate::agents::ship::{ShipCargo, ShipEconomy, ShipFuel, ShipMemory, ShipPosition};
use crate::ai::personality::Axis;
use crate::ai::utility::Consideration;

fn clamp(v: f32) -> f32 {
    v.clamp(0.0, 1.0)
}

// --- Fuel & basic safety ---

pub fn fuel_urgency(fuel: &ShipFuel) -> Consideration {
    Consideration::new(clamp(1.0 - fuel.fraction()), Axis::Safety)
}

// --- Economy / profit ---

/// Best known profit margin across the ship's price memory, with
/// freshness decay (Bundle 1.2). 2.0+ margin clamps to 1.0. Pass
/// the current sim tick so stale observations weigh less; callers
/// that don't track ticks can pass the observation's own tick
/// (yielding the legacy no-decay behaviour).
pub fn trade_opportunity(memory: &ShipMemory, current_tick: u64) -> Consideration {
    if memory.price_knowledge.len() < 2 {
        return Consideration::new(0.0, Axis::Profit);
    }

    let mut max_margin = 0.0_f32;
    let locations: Vec<_> = memory.price_knowledge.iter().collect();
    for (i, (_loc_a, prices_a)) in locations.iter().enumerate() {
        for (_loc_b, prices_b) in locations.iter().skip(i + 1) {
            for (commodity, price_a) in prices_a.iter() {
                if let Some(price_b) = prices_b.get(commodity) {
                    let (lo, hi) = if price_a.price < price_b.price {
                        (price_a.price, price_b.price)
                    } else {
                        (price_b.price, price_a.price)
                    };
                    let freshness = crate::agents::ship::price_freshness_weight(
                        price_a.tick,
                        current_tick,
                    )
                    .min(crate::agents::ship::price_freshness_weight(
                        price_b.tick,
                        current_tick,
                    ));
                    let margin = (hi - lo) / lo.max(1.0) * freshness;
                    if margin > max_margin {
                        max_margin = margin;
                    }
                }
            }
        }
    }

    Consideration::new(clamp(max_margin / 2.0), Axis::Profit)
}

/// Available cargo capacity as a fraction of total. Maps to `:profit` (opportunity to buy).
pub fn cargo_opportunity(cargo: &ShipCargo) -> Consideration {
    let used: u32 = cargo.cargo.values().sum();
    let free = cargo.capacity.saturating_sub(used);
    Consideration::new(free as f32 / cargo.capacity.max(1) as f32, Axis::Profit)
}

/// How much cargo is on board to unload. Maps to `:profit`.
pub fn cargo_to_sell(cargo: &ShipCargo) -> Consideration {
    let used: u32 = cargo.cargo.values().sum();
    let fraction = used as f32 / cargo.capacity.max(1) as f32;
    Consideration::new(clamp(fraction), Axis::Profit)
}

/// Financial distress. 0 = wealthy, 1.0 = broke.
pub fn financial_pressure(economy: &ShipEconomy) -> Consideration {
    let credits = economy.credits;
    let pressure = if credits <= 0 {
        1.0
    } else if credits < 500 {
        0.8
    } else if credits < 2_000 {
        0.4
    } else if credits < 10_000 {
        0.1
    } else {
        0.0
    };
    Consideration::new(pressure, Axis::Safety)
}

/// Exploration desire: how much of the ship's known-price universe is unvisited.
pub fn exploration_desire(memory: &ShipMemory) -> Consideration {
    if memory.visited.is_empty() {
        return Consideration::new(0.3, Axis::Exploration);
    }
    let visited: std::collections::HashSet<_> = memory.visited.iter().collect();
    let known = memory.price_knowledge.len();
    if known == 0 {
        return Consideration::new(0.3, Axis::Exploration);
    }
    let unvisited = memory
        .price_knowledge
        .keys()
        .filter(|k| !visited.contains(k))
        .count();
    Consideration::new(clamp(unvisited as f32 / known as f32), Axis::Exploration)
}

/// Locality consideration: is the ship currently docked?
pub fn docked_at_facility(position: &ShipPosition) -> Consideration {
    if position.docked_at.is_some() {
        Consideration::new(1.0, Axis::Safety)
    } else {
        Consideration::new(0.0, Axis::Safety)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::personality::Axis;
    use std::collections::HashMap;

    fn make_fuel(fuel: f32, capacity: f32) -> ShipFuel {
        ShipFuel {
            fuel,
            fuel_capacity: capacity,
            fuel_consumption_rate: 0.05,
            speed_modifier: 1.0,
        }
    }

    #[test]
    fn fuel_urgency_full_tank() {
        let c = fuel_urgency(&make_fuel(100.0, 100.0));
        assert!(c.value < 0.01);
        assert_eq!(c.axis, Axis::Safety);
    }

    #[test]
    fn fuel_urgency_empty_tank() {
        let c = fuel_urgency(&make_fuel(0.0, 100.0));
        assert!(c.value > 0.99);
    }

    #[test]
    fn cargo_opportunity_empty_ship() {
        let c = cargo_opportunity(&ShipCargo {
            cargo: HashMap::new(),
            capacity: 500,
            cargo_age: HashMap::new(),
            cargo_origin: HashMap::new(),
        });
        assert!((c.value - 1.0).abs() < 0.01);
    }

    #[test]
    fn cargo_opportunity_full_ship() {
        let mut cargo = HashMap::new();
        cargo.insert(crate::economy::commodities::Commodity::Ore, 500_u32);
        let c = cargo_opportunity(&ShipCargo {
            cargo,
            capacity: 500,
            cargo_age: HashMap::new(),
            cargo_origin: HashMap::new(),
        });
        assert!(c.value < 0.01);
    }

    #[test]
    fn financial_pressure_broke_high() {
        let c = financial_pressure(&ShipEconomy {
            credits: 0,
            efficiency: 1.0,
            active_contract_id: None,
            faction_reputation: HashMap::new(),
            dock_dwell_start_tick: None,
                rest_start_tick: None,
                dock_attempt_start_tick: None,
        });
        assert!((c.value - 1.0).abs() < 0.01);
    }

    #[test]
    fn financial_pressure_wealthy_low() {
        let c = financial_pressure(&ShipEconomy {
            credits: 100_000,
            efficiency: 1.0,
            active_contract_id: None,
            faction_reputation: HashMap::new(),
            dock_dwell_start_tick: None,
                rest_start_tick: None,
                dock_attempt_start_tick: None,
        });
        assert!(c.value < 0.01);
    }
}
