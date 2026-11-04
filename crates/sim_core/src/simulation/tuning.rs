//! Runtime-tunable world constants.
//!
//! Collects magic numbers that tune simulation behaviour into one
//! struct so they can be (a) inspected via `GET /api/admin/tuning`,
//! (b) loaded from a JSON file at boot, and (c) eventually live-
//! adjusted via `POST /api/admin/tuning`. Keeping them in one place
//! is valuable even before the live-edit path exists — a single
//! file to scan when tuning balance, a single place to audit when
//! perf or economics drift.
//!
//! ## Migration pattern
//!
//! Old code pattern (keep the module-level const for compile-time
//! constants like buffer sizes):
//! ```ignore
//! pub const MARKET_CRISIS_SHORTAGE_TICKS: u32 = 200;
//! ```
//!
//! New code pattern for behaviour tuning knobs:
//! ```ignore
//! // Keep the const as the authoritative default (used by
//! // `WorldTuning::default`) and a legacy fallback for tests that
//! // don't initialise the global tuning.
//! pub const MARKET_CRISIS_SHORTAGE_TICKS_DEFAULT: u32 = 200;
//!
//! // Call sites read from the live tuning.
//! let threshold = WorldTuning::current().market_crisis_shortage_ticks;
//! ```
//!
//! Not every constant deserves a tuning knob — structural invariants
//! (e.g. the 10-bucket fuel resolution in the GOAP planner) should
//! stay `const`. The heuristics that drive balance (thresholds,
//! ratios, cadences) are the candidates.
//!
//! ## Concurrency model
//!
//! `TUNING` is a `OnceLock<WorldTuning>` — set once at boot, read
//! freely thereafter. If tests need a distinct tuning, they
//! construct a `WorldTuning` locally and pass it explicitly rather
//! than relying on the global. The live-edit endpoint will replace
//! this with an `ArcSwap<WorldTuning>` when built.

use std::sync::OnceLock;

/// Tunable world constants. See the module docstring for the
/// migration pattern and the commit log (Bundle (Q)) for context.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct WorldTuning {
    /// Genesis runs extraction and transport before enabling upkeep or contracts.
    pub genesis_ore_loop: bool,
    // --- Bundle (H): recipe profitability gate ---
    /// Recipes skip production when
    /// `output_value < input_value × min_recipe_margin_ratio`
    /// at local market prices. 0.5 = "skip on ≥50% loss"; leaves
    /// headroom for normal fluctuation.
    pub min_recipe_margin_ratio: f32,

    // --- Bundle (G): money sink ---
    /// Fraction of each docking fee burned as a licensing tax.
    /// Remainder is paid to the facility as before. 0.30 = 30%
    /// burned. Primary lever against long-run credit inflation.
    pub dock_fee_burn_pct: f32,

    // --- Bundle (S): market crisis events ---
    /// Consecutive short-ticks after which a `market_crisis` event
    /// fires. Paired with `market_crisis_recovery_ticks` for
    /// hysteresis (prevents flapping).
    pub market_crisis_shortage_ticks: u32,
    /// Drop to at-or-below this to clear the crisis flag.
    pub market_crisis_recovery_ticks: u32,

    // --- Bundle (S): facility starving events ---
    /// Condition below this → emit `facility_starving`. Paired with
    /// `facility_starving_recovery` for hysteresis.
    pub facility_starving_condition: f32,
    /// Condition above this → clear `starving_notified`.
    pub facility_starving_recovery: f32,

    // --- Bundle 2: unified utility scorer ---
    /// Fuel fraction below this → `refuel` candidate generated
    /// with urgency rising as fuel → 0.
    pub fuel_urgency_onset: f32,

    // --- Bundle 2.2: mid-action replan ---
    /// Min dwell before a running plan can be interrupted. Prevents
    /// thrashing on near-equal alternatives.
    pub replan_min_commit_ticks: u64,
    /// Cadence of the mid-action replan check.
    pub replan_check_interval_ticks: u64,
    /// Alternative must beat current score by this ratio to
    /// interrupt. 1.30 = require 30%+ improvement.
    pub replan_score_ratio: f32,
}

impl Default for WorldTuning {
    fn default() -> Self {
        Self {
            genesis_ore_loop: false,
            min_recipe_margin_ratio: 0.5,
            dock_fee_burn_pct: 0.30,
            market_crisis_shortage_ticks: 200,
            market_crisis_recovery_ticks: 50,
            facility_starving_condition: 0.3,
            facility_starving_recovery: 0.5,
            fuel_urgency_onset: 0.45,
            replan_min_commit_ticks: 40,
            replan_check_interval_ticks: 20,
            replan_score_ratio: 1.30,
        }
    }
}

static TUNING: OnceLock<WorldTuning> = OnceLock::new();

impl WorldTuning {
    /// Install the world tuning. Intended to be called once at
    /// boot (optionally loading from a JSON file). Subsequent
    /// calls are silently ignored — live edit needs an ArcSwap
    /// variant (future work).
    pub fn set(tuning: WorldTuning) {
        let _ = TUNING.set(tuning);
    }

    /// Get the current tuning. Initialises to `Default::default()`
    /// if no `set` has been called yet, so tests and pure units
    /// never need to stand up the full sim to get sensible values.
    pub fn current() -> &'static WorldTuning {
        TUNING.get_or_init(WorldTuning::default)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_values_are_sane() {
        let t = WorldTuning::default();
        assert!(t.min_recipe_margin_ratio > 0.0 && t.min_recipe_margin_ratio <= 1.0);
        assert!(t.dock_fee_burn_pct >= 0.0 && t.dock_fee_burn_pct < 1.0);
        assert!(t.market_crisis_recovery_ticks < t.market_crisis_shortage_ticks);
        assert!(t.facility_starving_recovery > t.facility_starving_condition);
        assert!(t.replan_score_ratio > 1.0);
    }

    #[test]
    fn current_returns_defaults_without_set() {
        // Note: after any previous test ran `set`, `current` may
        // return that value. This test is tolerant — just checks
        // the fields are populated, not their exact values.
        let t = WorldTuning::current();
        assert!(t.min_recipe_margin_ratio > 0.0);
    }

    #[test]
    fn serde_round_trip() {
        let t = WorldTuning::default();
        let json = serde_json::to_string(&t).unwrap();
        let back: WorldTuning = serde_json::from_str(&json).unwrap();
        assert!((back.dock_fee_burn_pct - t.dock_fee_burn_pct).abs() < 1e-6);
        assert_eq!(
            back.market_crisis_shortage_ticks,
            t.market_crisis_shortage_ticks
        );
    }

    #[test]
    fn serde_partial_json_uses_defaults_for_missing_fields() {
        // The `#[serde(default)]` attribute means missing JSON
        // fields fall back to Default — so a tuning file can
        // override just what it needs.
        let partial = r#"{ "dock_fee_burn_pct": 0.5 }"#;
        let t: WorldTuning = serde_json::from_str(partial).unwrap();
        assert!((t.dock_fee_burn_pct - 0.5).abs() < 1e-6);
        // Everything else should be default.
        assert_eq!(t.market_crisis_shortage_ticks, 200);
    }
}
