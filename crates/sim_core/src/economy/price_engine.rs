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
pub const URGENCY_RAMP_TICKS: u32 = 50;
/// Capped lower than the original 4.0 so urgent shortages don't sprint
/// prices to the ceiling in a dozen ticks; supply-chain response has
/// more time to catch up before the market saturates and every planner
/// converges on "this commodity is king, buy everything".
pub const URGENCY_MAX_MULTIPLIER: f32 = 2.5;

/// Hard cap on per-tick price change as a fraction. Without this, a
/// commodity with elasticity 0.05 × urgency 2.5 = 0.125 can leap 12.5%
/// per tick, and at 8 tps that's a 100× price swing in one in-game
/// minute. Rate-limits move prices realistically regardless of the
/// seed `price_elasticity`.
pub const MAX_PRICE_CHANGE_PER_TICK: f32 = 0.05;

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
///
/// Softer curve than the original: the stable zone is wider (no
/// pressure from coverage 10–200) and the climb out of shortage is
/// gentler, so a single tick of bad coverage doesn't spike the price.
/// Keeps the extreme signal (coverage < 0.5 = max upward pressure)
/// because truly empty markets genuinely are urgent.
fn coverage_to_pressure(coverage: f32) -> f32 {
    if coverage < 0.5 {
        1.0
    } else if coverage < 2.0 {
        0.6 + (2.0 - coverage) / 4.0 * 0.4
    } else if coverage < 10.0 {
        (10.0 - coverage) / 20.0
    } else if coverage < 200.0 {
        0.0
    } else if coverage < 1000.0 {
        -0.2
    } else if coverage < 10000.0 {
        -0.5
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
    let raw_change = pressure * effective_elasticity;
    let change = raw_change.clamp(-MAX_PRICE_CHANGE_PER_TICK, MAX_PRICE_CHANGE_PER_TICK);

    let new_price = current_price * (1.0 + change);
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
