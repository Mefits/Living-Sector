//! Price recalculation from supply & demand.
//!
//! Coverage model: price pressure is driven by how many ticks of demand the
//! current supply covers, not by a raw supply/demand ratio. Large stockpiles
//! are treated as stability buffers, not oversupply signals.
//!
//! Shortage urgency amplifies upward pressure after sustained scarcity so
//! prices can climb out of the per-tick elasticity cap.

pub const ABSOLUTE_PRICE_CEILING: f32 = 500.0;
pub const URGENCY_ONSET_TICKS: u32 = 20;
pub const URGENCY_RAMP_TICKS: u32 = 30;
pub const URGENCY_MAX_MULTIPLIER: f32 = 4.0;

/// Urgency multiplier applied to upward pressure when a commodity has been
/// in shortage for `shortage_ticks` consecutive ticks.
pub fn urgency_multiplier(shortage_ticks: u32) -> f32 {
    if shortage_ticks <= URGENCY_ONSET_TICKS {
        return 1.0;
    }
    let raw = 1.0 + (shortage_ticks - URGENCY_ONSET_TICKS) as f32 / URGENCY_RAMP_TICKS as f32;
    raw.min(URGENCY_MAX_MULTIPLIER)
}

/// Map coverage (ticks of supply at current demand) → pressure (-1.0 to +1.0).
/// Positive = price wants to go up, negative = wants to go down.
fn coverage_to_pressure(coverage: f32) -> f32 {
    if coverage < 1.0 {
        1.0
    } else if coverage < 5.0 {
        0.5 + (5.0 - coverage) / 8.0
    } else if coverage < 20.0 {
        (20.0 - coverage) / 30.0
    } else if coverage < 100.0 {
        0.0
    } else if coverage < 500.0 {
        -0.3
    } else if coverage < 5000.0 {
        -0.6
    } else {
        -1.0
    }
}

/// Recalculate a single commodity price for one tick.
pub fn recalculate(
    current_price: f32,
    supply: f32,
    demand: f32,
    elasticity: f32,
    shortage_ticks: u32,
) -> f32 {
    let effective_demand = demand.max(1.0);
    let coverage = supply / effective_demand;
    let pressure = coverage_to_pressure(coverage);

    // Urgency only accelerates upward movement
    let urgency = urgency_multiplier(shortage_ticks);
    let effective_elasticity = if pressure > 0.0 {
        elasticity * urgency
    } else {
        elasticity
    };
    let clamped_pressure = pressure * effective_elasticity;

    let new_price = current_price * (1.0 + clamped_pressure);
    let rounded = (new_price * 100.0).round() / 100.0;
    rounded.clamp(1.0, ABSOLUTE_PRICE_CEILING)
}

/// Apply market spread, returning (buy_price, sell_price).
pub fn apply_spread(base_price: f32, spread: f32) -> (f32, f32) {
    let half = spread / 2.0;
    let buy = ((base_price * (1.0 + half)) * 100.0).round() / 100.0;
    let sell = ((base_price * (1.0 - half)) * 100.0).round() / 100.0;
    (buy, sell)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abundant_supply_drifts_down() {
        // coverage 1000 → -0.3 pressure → elasticity*0.3 downward
        let new_price = recalculate(100.0, 1000.0, 1.0, 0.02, 0);
        assert!(new_price < 100.0, "abundant supply should lower price");
    }

    #[test]
    fn critical_shortage_pushes_up() {
        // coverage 0.5 → 1.0 pressure → elasticity upward
        let new_price = recalculate(100.0, 5.0, 10.0, 0.02, 0);
        assert!(new_price > 100.0, "critical shortage should raise price");
    }

    #[test]
    fn stable_zone_no_movement() {
        // coverage 50 → 0 pressure
        let new_price = recalculate(50.0, 500.0, 10.0, 0.02, 0);
        assert!((new_price - 50.0).abs() < 0.01, "stable zone should not move");
    }

    #[test]
    fn urgency_amplifies_upward_pressure() {
        let without = recalculate(100.0, 5.0, 100.0, 0.02, 0);
        let with_urgency = recalculate(100.0, 5.0, 100.0, 0.02, 50);
        assert!(with_urgency > without, "urgency should push price higher");
    }

    #[test]
    fn price_capped_at_ceiling() {
        let p = recalculate(ABSOLUTE_PRICE_CEILING - 1.0, 0.0, 1000.0, 0.99, 100);
        assert!(p <= ABSOLUTE_PRICE_CEILING);
    }

    #[test]
    fn price_floored_at_one() {
        let p = recalculate(2.0, 100000.0, 1.0, 0.99, 0);
        assert!(p >= 1.0);
    }

    #[test]
    fn urgency_below_onset_is_one() {
        assert_eq!(urgency_multiplier(0), 1.0);
        assert_eq!(urgency_multiplier(20), 1.0);
    }

    #[test]
    fn urgency_caps_at_max() {
        assert!((urgency_multiplier(1000) - URGENCY_MAX_MULTIPLIER).abs() < 0.01);
    }

    #[test]
    fn spread_creates_buy_sell_gap() {
        let (buy, sell) = apply_spread(100.0, 0.10);
        assert!(buy > 100.0);
        assert!(sell < 100.0);
        assert!(buy - sell > 0.0);
    }
}
