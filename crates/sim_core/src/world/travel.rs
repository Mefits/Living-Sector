//! Travel time calculations and transit-progress interpolation.
//!
//! Travel time in ticks depends on distance, ship speed_modifier, and the
//! world-speed-scaled tick_multiplier. At default config (world_speed=0.25,
//! 8 tps), distance 60 units ≈ 1920 ticks ≈ 4 minutes of wall-clock time.
//! Set `WORLD_SPEED=4.0` in the env for faster smoke tests.

use crate::simulation::config::TickConfig;

/// Travel time in ticks between two locations given distance and ship speed.
///
/// `distance` is in arbitrary "space units". At default tick config and
/// speed_modifier=1.0, distance 60 ≈ 4800 ticks ≈ 10 minutes.
pub fn travel_ticks(distance: u32, speed_modifier: f32, config: &TickConfig) -> u64 {
    // base_ticks_per_unit = tick_multiplier (32 at default speed)
    // actual = (distance * base) / speed_modifier
    let base = config.tick_multiplier() as f32;
    ((distance as f32 * base) / speed_modifier.max(0.1)) as u64
}

/// Arrival tick given departure_tick, distance, and speed.
pub fn arrival_tick(
    departure_tick: u64,
    distance: u32,
    speed_modifier: f32,
    config: &TickConfig,
) -> u64 {
    departure_tick + travel_ticks(distance, speed_modifier, config)
}

/// Linear interpolation of position during transit (0.0 at departure, 1.0 at arrival).
pub fn transit_progress(current_tick: u64, departure_tick: u64, arrival_tick: u64) -> f32 {
    if arrival_tick <= departure_tick {
        return 1.0;
    }
    let elapsed = current_tick.saturating_sub(departure_tick) as f32;
    let total = (arrival_tick - departure_tick) as f32;
    (elapsed / total).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::simulation::config::TickConfig;

    #[test]
    fn travel_ticks_positive() {
        let t = travel_ticks(60, 1.0, &TickConfig::DEFAULT);
        assert!(t > 0, "travel time should be positive");
    }

    #[test]
    fn faster_ship_arrives_sooner() {
        let slow = travel_ticks(60, 0.6, &TickConfig::DEFAULT);
        let fast = travel_ticks(60, 1.5, &TickConfig::DEFAULT);
        assert!(fast < slow, "faster ship should take fewer ticks");
    }

    #[test]
    fn transit_progress_interpolates() {
        assert!((transit_progress(0, 0, 100) - 0.0).abs() < 0.01);
        assert!((transit_progress(50, 0, 100) - 0.5).abs() < 0.01);
        assert!((transit_progress(100, 0, 100) - 1.0).abs() < 0.01);
        assert!((transit_progress(150, 0, 100) - 1.0).abs() < 0.01); // clamped
    }
}
