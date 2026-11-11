//! Personality profiles that weight agent decision-making.
//!
//! Every ship and crew member carries a `Personality` — six 0.0–1.0 axes
//! (profit, safety, morale, exploration, loyalty, aggression) plus a
//! `prefer_goals` map for archetype bonuses.
//!
//! The utility scoring layer (see `ai::utility`) multiplies each consideration's
//! value by the matching axis weight, then adds any `prefer_goals` bonus, to
//! rank actions. Archetype functions (`cautious_trader`, `aggressive_trader`,
//! etc.) produce baseline personalities; `with_variation` perturbs each axis
//! by ±0.1 for individual variation at spawn time.

use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A ship or crew personality — 6 axes (0.0–1.0) plus optional goal bonuses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Personality {
    pub profit: f32,
    pub safety: f32,
    pub morale: f32,
    pub exploration: f32,
    pub loyalty: f32,
    pub aggression: f32,
    /// Archetype bonus added to specific goal scores to break ties.
    #[serde(default)]
    pub prefer_goals: HashMap<String, f32>,
}

/// Which personality axis a consideration targets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Axis {
    Profit,
    Safety,
    Morale,
    Exploration,
    Loyalty,
    Aggression,
}

impl Personality {
    pub fn weight(&self, axis: Axis) -> f32 {
        match axis {
            Axis::Profit => self.profit,
            Axis::Safety => self.safety,
            Axis::Morale => self.morale,
            Axis::Exploration => self.exploration,
            Axis::Loyalty => self.loyalty,
            Axis::Aggression => self.aggression,
        }
    }

    /// Bundle 1.4: nudge a single axis by `delta`, clamping to [0,1].
    /// Called from gameplay events (successful contract → +profit,
    /// near-death rest → +safety, etc.) so a ship's personality
    /// slowly drifts with its lived experience. Magnitudes are kept
    /// small (ε ≈ 0.001–0.01) so drift is only visible over hundreds
    /// of events — archetype identity stays stable over the short
    /// term.
    pub fn drift(&mut self, axis: Axis, delta: f32) {
        let v = match axis {
            Axis::Profit => &mut self.profit,
            Axis::Safety => &mut self.safety,
            Axis::Morale => &mut self.morale,
            Axis::Exploration => &mut self.exploration,
            Axis::Loyalty => &mut self.loyalty,
            Axis::Aggression => &mut self.aggression,
        };
        *v = (*v + delta).clamp(0.0, 1.0);
    }

    /// Perturbs each numeric axis by ±0.1 (clamped 0.0–1.0).
    pub fn with_variation<R: Rng>(&self, rng: &mut R) -> Self {
        let mut perturb = |v: f32| (v + rng.gen_range(-0.1..=0.1_f32)).clamp(0.0, 1.0);
        Self {
            profit: (perturb(self.profit) * 100.0).round() / 100.0,
            safety: (perturb(self.safety) * 100.0).round() / 100.0,
            morale: (perturb(self.morale) * 100.0).round() / 100.0,
            exploration: (perturb(self.exploration) * 100.0).round() / 100.0,
            loyalty: (perturb(self.loyalty) * 100.0).round() / 100.0,
            aggression: (perturb(self.aggression) * 100.0).round() / 100.0,
            prefer_goals: self.prefer_goals.clone(),
        }
    }

    // --- Ship archetypes ---

    pub fn cautious_trader() -> Self {
        Self {
            profit: 0.6,
            safety: 0.9,
            morale: 0.5,
            exploration: 0.1,
            loyalty: 0.7,
            aggression: 0.0,
            prefer_goals: [
                ("fulfill_contract".into(), 0.3),
                ("fulfill_delivery".into(), 0.3),
                ("station_job".into(), 0.2),
            ]
            .into(),
        }
    }

    pub fn aggressive_trader() -> Self {
        Self {
            profit: 0.95,
            safety: 0.2,
            morale: 0.2,
            exploration: 0.3,
            loyalty: 0.3,
            aggression: 0.1,
            prefer_goals: [("trade_run".into(), 0.3)].into(),
        }
    }

    pub fn balanced_trader() -> Self {
        Self {
            profit: 0.7,
            safety: 0.5,
            morale: 0.4,
            exploration: 0.3,
            loyalty: 0.5,
            aggression: 0.0,
            prefer_goals: HashMap::new(),
        }
    }

    pub fn explorer() -> Self {
        Self {
            profit: 0.3,
            safety: 0.5,
            morale: 0.4,
            exploration: 0.9,
            loyalty: 0.2,
            aggression: 0.0,
            prefer_goals: [("explore".into(), 0.4)].into(),
        }
    }

    pub fn reliable_trucker() -> Self {
        Self {
            profit: 0.5,
            safety: 0.7,
            morale: 0.5,
            exploration: 0.1,
            loyalty: 0.9,
            aggression: 0.0,
            prefer_goals: [
                ("fulfill_delivery".into(), 0.4),
                ("fulfill_contract".into(), 0.3),
            ]
            .into(),
        }
    }

    pub fn opportunistic_trucker() -> Self {
        Self {
            profit: 0.7,
            safety: 0.4,
            morale: 0.3,
            exploration: 0.2,
            loyalty: 0.7,
            aggression: 0.1,
            prefer_goals: [
                ("fulfill_delivery".into(), 0.25),
                ("trade_run".into(), 0.2),
            ]
            .into(),
        }
    }

    pub fn courier() -> Self {
        Self {
            profit: 0.6,
            safety: 0.8,
            morale: 0.7,
            exploration: 0.2,
            loyalty: 0.8,
            aggression: 0.0,
            prefer_goals: [
                ("fulfill_passenger_transport".into(), 0.35),
                ("fulfill_courier".into(), 0.30),
                ("fulfill_delivery".into(), 0.25),
                ("station_job".into(), 0.15),
            ]
            .into(),
        }
    }

    /// Industrial archetype — miners prefer station work (mining
    /// isn't its own goal yet; when it lands it'll pick up the
    /// "mine" bonus here). Leans toward ore/metals delivery
    /// contracts since that's their natural cargo.
    pub fn miner() -> Self {
        Self {
            profit: 0.5,
            safety: 0.6,
            morale: 0.4,
            exploration: 0.3,
            loyalty: 0.6,
            aggression: 0.0,
            prefer_goals: [
                ("mine".into(), 0.4),
                ("fulfill_delivery".into(), 0.2),
                ("station_job".into(), 0.15),
            ]
            .into(),
        }
    }

    /// Class-appropriate default personality for a ship class.
    /// Used by admin_spawn_ship and the seeder fallback so new
    /// ships start with a role-biased archetype instead of a flat
    /// balanced_trader. Existing seeded ships keep whatever
    /// `random_ship` gave them — their persisted personality wins.
    pub fn for_class(class: &str) -> Self {
        match class {
            "courier" | "colonizer" => Self::courier(),
            "freighter" => Self::reliable_trucker(),
            "hauler" => Self::opportunistic_trucker(),
            "tanker" => Self::reliable_trucker(),
            "miner" => Self::miner(),
            _ => Self::balanced_trader(),
        }
    }

    // --- Crew archetypes ---

    pub fn diligent() -> Self {
        Self {
            profit: 0.3,
            safety: 0.4,
            morale: 0.3,
            exploration: 0.1,
            loyalty: 0.9,
            aggression: 0.0,
            prefer_goals: HashMap::new(),
        }
    }

    pub fn self_preserving() -> Self {
        Self {
            profit: 0.5,
            safety: 0.9,
            morale: 0.8,
            exploration: 0.2,
            loyalty: 0.2,
            aggression: 0.1,
            prefer_goals: HashMap::new(),
        }
    }

    /// Picks a random ship archetype and applies variation.
    pub fn random_ship<R: Rng>(rng: &mut R) -> Self {
        let archetypes: &[fn() -> Personality] = &[
            Personality::cautious_trader,
            Personality::aggressive_trader,
            Personality::balanced_trader,
            Personality::explorer,
            Personality::reliable_trucker,
            Personality::opportunistic_trucker,
            Personality::courier,
        ];
        let idx = rng.gen_range(0..archetypes.len());
        archetypes[idx]().with_variation(rng)
    }

    /// Picks a random crew archetype and applies variation.
    pub fn random_crew<R: Rng>(rng: &mut R) -> Self {
        let archetypes: &[fn() -> Personality] = &[
            Personality::diligent,
            Personality::self_preserving,
            Personality::balanced_trader,
        ];
        let idx = rng.gen_range(0..archetypes.len());
        archetypes[idx]().with_variation(rng)
    }

    /// Random personality with all axes between 0.1–1.0.
    pub fn random_pure<R: Rng>(rng: &mut R) -> Self {
        Self {
            profit: rng.gen_range(0.1..=1.0_f32),
            safety: rng.gen_range(0.1..=1.0_f32),
            morale: rng.gen_range(0.1..=1.0_f32),
            exploration: rng.gen_range(0.1..=1.0_f32),
            loyalty: rng.gen_range(0.1..=1.0_f32),
            aggression: rng.gen_range(0.1..=1.0_f32),
            prefer_goals: HashMap::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::{rngs::StdRng, SeedableRng};

    #[test]
    fn variation_stays_in_bounds() {
        let mut rng = StdRng::seed_from_u64(42);
        let base = Personality::cautious_trader();
        for _ in 0..100 {
            let varied = base.with_variation(&mut rng);
            assert!(varied.profit >= 0.0 && varied.profit <= 1.0);
            assert!(varied.safety >= 0.0 && varied.safety <= 1.0);
            assert!(varied.morale >= 0.0 && varied.morale <= 1.0);
            assert!(varied.exploration >= 0.0 && varied.exploration <= 1.0);
            assert!(varied.loyalty >= 0.0 && varied.loyalty <= 1.0);
            assert!(varied.aggression >= 0.0 && varied.aggression <= 1.0);
        }
    }

    #[test]
    fn random_ship_returns_valid_personality() {
        let mut rng = StdRng::seed_from_u64(99);
        let p = Personality::random_ship(&mut rng);
        assert!(p.profit >= 0.0 && p.profit <= 1.0);
    }

    #[test]
    fn serde_round_trip() {
        let p = Personality::balanced_trader();
        let json = serde_json::to_string(&p).unwrap();
        let back: Personality = serde_json::from_str(&json).unwrap();
        assert!((back.profit - p.profit).abs() < 0.001);
    }

    #[test]
    fn drift_nudges_single_axis_and_clamps() {
        let mut p = Personality::balanced_trader();
        let start_profit = p.profit;
        p.drift(Axis::Profit, 0.05);
        assert!((p.profit - (start_profit + 0.05)).abs() < 1e-5);
        // Other axes untouched.
        assert_eq!(p.safety, Personality::balanced_trader().safety);
        // Clamps at upper bound.
        p.drift(Axis::Profit, 10.0);
        assert!((p.profit - 1.0).abs() < 1e-5);
        // Clamps at lower bound.
        p.drift(Axis::Profit, -10.0);
        assert!(p.profit.abs() < 1e-5);
    }

    #[test]
    fn drift_accumulates_over_many_events() {
        // Simulate 100 deliveries each nudging profit by 0.002.
        let mut p = Personality::cautious_trader();
        let start = p.profit;
        for _ in 0..100 {
            p.drift(Axis::Profit, 0.002);
        }
        // Expect ~+0.2 after 100 events (0.6 → ~0.8 on cautious_trader).
        let delta = p.profit - start;
        assert!(
            (delta - 0.2).abs() < 0.01,
            "expected ~+0.2 drift after 100 events, got {delta}",
        );
    }
}
