//! Spatial level-of-detail gating.
//!
//! Every tick every agent is candidate for simulation, but only agents
//! whose `AgentLod.next_tick <= current_tick` actually run this time
//! around. When they do, they run with an `effective_tick_scale` scaled
//! by their `divisor` so state changes match the skipped-time window.
//!
//! Distance tiers are simple: within the observer radius, divisor 1
//! (every tick); at multiples of the radius, step up. Matches the
//! Elixir sim's chunk-divisor scale 1 / 2 / 5 / 10 / 20 / 50. No hard
//! cutoff — a ship at the edge of the galaxy still ticks, just
//! infrequently. When the camera pans back, the next-tick cursor fires
//! immediately on the first in-range tick and the ship picks up where
//! it left off.
//!
//! **Markets are never LOD'd.** They're the shared ledger every agent
//! writes to; gating them would introduce ordering glitches that are
//! almost impossible to reason about. 23 markets × ~8 phases is cheap.
//!
//! **Facilities + populations carry an `AgentLod` so the recompute pass
//! has numbers for debug views, but their per-tick phases don't gate on
//! it yet.** They're ~75 agents total (vs. 223 ships) and their phases
//! are already interval-driven (recipes every 5 ticks, contracts every
//! 50), so most of the compute win lives on the ship side. Phase 16
//! can plumb rate scaling into the recipe / sentiment / condition
//! paths if we need it.

use bevy_ecs::prelude::{Component, Entity, World};

/// Per-agent LOD cursor. `divisor` ∈ {1, 2, 5, 10, 20, 50}. `next_tick`
/// is the next real-tick value at which the agent should run its per-
/// tick phases.
#[derive(Debug, Clone, Component)]
pub struct AgentLod {
    pub divisor: u8,
    pub next_tick: u64,
}

impl AgentLod {
    pub fn new() -> Self {
        Self { divisor: 1, next_tick: 0 }
    }

    /// Can this agent run at `tick`? If yes, advance its cursor and
    /// return the `skipped_ticks` count for rate scaling.
    ///
    /// Call pattern:
    /// ```ignore
    /// if let Some(n) = lod.try_fire(tick) {
    ///     let scale = tick_scale * n as f32;
    ///     // run tick phase with scaled rates
    /// }
    /// ```
    pub fn try_fire(&mut self, tick: u64) -> Option<u32> {
        if tick < self.next_tick {
            return None;
        }
        let divisor = self.divisor.max(1) as u64;
        // Number of real ticks since we last fired. First fire at t=0
        // reports 1 (the current tick) so rates don't blow up.
        let last_fire = self.next_tick.saturating_sub(divisor);
        let skipped = (tick - last_fire).max(1) as u32;
        self.next_tick = tick + divisor;
        Some(skipped)
    }

    /// Update the divisor based on distance, preserving the phase of the
    /// `next_tick` cursor so we don't desync between divisor tiers.
    pub fn set_divisor(&mut self, divisor: u8, tick: u64) {
        let d = divisor.max(1);
        if d == self.divisor {
            return;
        }
        self.divisor = d;
        // Re-anchor: next fire is either ASAP (if we upgraded to a finer
        // divisor and the old cursor sits in the future) or the nearest
        // multiple of the new divisor after the current tick.
        if self.next_tick <= tick {
            self.next_tick = tick;
        } else {
            self.next_tick = tick + d as u64;
        }
    }
}

impl Default for AgentLod {
    fn default() -> Self {
        Self::new()
    }
}

/// Bucket a squared distance (saves a sqrt) against an observer's
/// radius into a divisor tier. Anything within the radius is divisor 1.
/// Outside, the divisor steps up at multiples of the radius so "just
/// off-screen" stays responsive while "across the system" throttles.
pub fn divisor_for_distance_sq(dist_sq: f32, radius: f32) -> u8 {
    let r = radius.max(0.01);
    let rsq = r * r;
    if dist_sq <= rsq {
        return 1;
    }
    // Compare against (n*r)^2 = n² * rsq to skip the sqrt.
    if dist_sq <= 4.0 * rsq {
        2   // within 2× radius
    } else if dist_sq <= 25.0 * rsq {
        5   // within 5× radius
    } else if dist_sq <= 100.0 * rsq {
        10  // within 10× radius
    } else if dist_sq <= 400.0 * rsq {
        20  // within 20× radius
    } else {
        50  // far-field — still ticks, just once every 50 real ticks
    }
}

/// Compute divisor for an agent at `pos` given the nearest of `observers`.
/// If no observers exist, everything is divisor 1 (the headless sim or
/// pre-client-connect case should tick everything).
pub fn divisor_for_position(
    pos: (f32, f32),
    observers: &[(f32, f32, f32)],
) -> u8 {
    if observers.is_empty() {
        return 1;
    }
    let mut best: (f32, f32) = (f32::INFINITY, 1.0);
    for &(ox, oy, r) in observers {
        let dx = pos.0 - ox;
        let dy = pos.1 - oy;
        let d2 = dx * dx + dy * dy;
        if d2 < best.0 {
            best = (d2, r);
        }
    }
    divisor_for_distance_sq(best.0, best.1)
}

/// Base-tick interval between LOD recomputes. Matches Elixir's chunk
/// manager cadence — agents don't change tier often, so re-evaluating
/// every 50 base-ticks is plenty.
pub const LOD_RECOMPUTE_INTERVAL_BASE: u64 = 50;

/// Distribution of divisors across a tick. Useful for the perf HUD
/// ("how many ships are at d=1 vs d=50?") and for benchmarking the LOD
/// rollout. Each slot is `(divisor, count)`.
#[derive(Debug, Clone, Default)]
pub struct LodStats {
    pub d1: u32,
    pub d2: u32,
    pub d5: u32,
    pub d10: u32,
    pub d20: u32,
    pub d50: u32,
    pub other: u32,
}

impl LodStats {
    pub fn total(&self) -> u32 {
        self.d1 + self.d2 + self.d5 + self.d10 + self.d20 + self.d50 + self.other
    }

    pub fn bump(&mut self, divisor: u8) {
        match divisor {
            1 => self.d1 += 1,
            2 => self.d2 += 1,
            5 => self.d5 += 1,
            10 => self.d10 += 1,
            20 => self.d20 += 1,
            50 => self.d50 += 1,
            _ => self.other += 1,
        }
    }
}

/// Run the LOD recompute pass over all agents that carry `AgentLod` +
/// a position. Returns a distribution snapshot for observability.
///
/// Positions come from:
/// - Ships: `ShipPosition.position` (live, changes every tick).
/// - Facilities: they don't have a position component directly, so we
///   plumb a resolver in as a `pos_by_entity` map. Caller populates it.
/// - Populations: same (populations inherit their facility's location).
///
/// This keeps `sim_core::simulation::lod` free of agent-module
/// dependencies — the caller does the lookup.
pub fn tick_lod_recompute(
    world: &mut World,
    pos_by_entity: &std::collections::HashMap<Entity, (f32, f32)>,
    observers: &[(f32, f32, f32)],
    tick: u64,
) -> LodStats {
    let mut stats = LodStats::default();
    let mut q = world.query::<(Entity, &mut AgentLod)>();
    for (e, mut lod) in q.iter_mut(world) {
        let pos = match pos_by_entity.get(&e) {
            Some(&p) => p,
            None => continue, // no position known → leave divisor alone
        };
        let divisor = divisor_for_position(pos, observers);
        lod.set_divisor(divisor, tick);
        stats.bump(divisor);
    }
    stats
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn in_radius_is_divisor_1() {
        assert_eq!(divisor_for_distance_sq(0.0, 5.0), 1);
        assert_eq!(divisor_for_distance_sq(24.0, 5.0), 1);
        // exactly on the edge still counts
        assert_eq!(divisor_for_distance_sq(25.0, 5.0), 1);
    }

    #[test]
    fn tiers_scale_outward() {
        let r = 5.0;
        assert_eq!(divisor_for_distance_sq(26.0, r), 2);
        assert_eq!(divisor_for_distance_sq(4.0 * 25.0, r), 2);
        assert_eq!(divisor_for_distance_sq(25.0 * 25.0, r), 5);
        assert_eq!(divisor_for_distance_sq(100.0 * 25.0, r), 10);
        assert_eq!(divisor_for_distance_sq(400.0 * 25.0, r), 20);
        assert_eq!(divisor_for_distance_sq(500.0 * 25.0, r), 50);
    }

    #[test]
    fn no_observers_means_full_detail() {
        assert_eq!(divisor_for_position((100.0, 100.0), &[]), 1);
    }

    #[test]
    fn nearest_observer_wins() {
        let obs = [(0.0, 0.0, 1.0), (10.0, 0.0, 5.0)];
        // (6, 0) is 6 from origin (divisor 50+ @ r=1) but 4 from
        // (10,0) with r=5 → within radius.
        assert_eq!(divisor_for_position((6.0, 0.0), &obs), 1);
    }

    #[test]
    fn try_fire_respects_cursor() {
        let mut lod = AgentLod { divisor: 5, next_tick: 10 };
        assert!(lod.try_fire(9).is_none());
        let skipped = lod.try_fire(10).unwrap();
        assert!(skipped >= 1);
        assert_eq!(lod.next_tick, 15);
        // 11..14 should be skipped
        assert!(lod.try_fire(11).is_none());
        assert!(lod.try_fire(14).is_none());
        assert!(lod.try_fire(15).is_some());
    }

    #[test]
    fn set_divisor_noop_if_unchanged() {
        let mut lod = AgentLod { divisor: 5, next_tick: 100 };
        lod.set_divisor(5, 90);
        assert_eq!(lod.next_tick, 100);
    }

    #[test]
    fn set_divisor_rephrases_cursor_in_past() {
        let mut lod = AgentLod { divisor: 50, next_tick: 95 };
        // Tick is 100 — cursor already passed. Downgrade to divisor 1:
        // fire now.
        lod.set_divisor(1, 100);
        assert_eq!(lod.next_tick, 100);
    }

    #[test]
    fn set_divisor_rephrases_cursor_in_future() {
        let mut lod = AgentLod { divisor: 1, next_tick: 101 };
        // Tick 100, cursor at 101. Upgrade to divisor 10: push to 110.
        lod.set_divisor(10, 100);
        assert_eq!(lod.next_tick, 110);
    }
}
