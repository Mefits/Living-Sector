//! Inter-faction relations matrix — Bundle A of the faction-interaction arc.
//!
//! Every ordered pair of factions gets a single [`RelationState`]: a
//! signed standing score in `-100..=100`, a [`TreatyKind`] treaty
//! state, and the tick timestamps needed to gate "sustained N ticks"
//! treaty transitions. Pairs are canonicalised by lexical order
//! (`a_id < b_id`) so a lookup for either direction resolves to the
//! same bucket.
//!
//! ## Reading vs writing
//!
//! All reads go through [`FactionRelations::state`] (canonicalises for
//! you). Writes go through [`FactionRelations::bump_standing`] or
//! [`FactionRelations::set_treaty`] — never mutate the map directly
//! from outside this module; the threshold-transition logic in
//! `tick_relations` relies on the canonical-pair invariant.
//!
//! ## Why a singleton, not per-faction data
//!
//! Relations are inherently pairwise. Storing on one side and not the
//! other risks divergence on restart or persistence rebuild. A single
//! owning map pinned to `AgentStore` keeps the invariant "there is one
//! canonical standing between X and Y, regardless of who asks first."
//! Mirrors the `ContractBoard` pattern already on `AgentStore`.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Treaty state between two factions. Starts at `Neutral`, drifts up
/// or down through the threshold states based on the running
/// `standing` score and time-gated transitions in `tick_relations`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TreatyKind {
    /// Default. No formal agreement — baseline economic + contract behaviour.
    Neutral,
    /// Bundle B consumer. Discounted dock fees, shared contract visibility,
    /// payment bonus. Requires sustained positive standing.
    TradePact,
    /// Strongest positive. Bundle G will add forced mutual-aid on war.
    Allied,
    /// Cooling-off state — negative standing but no formal hostility.
    /// Soft signals only (slightly higher fees, reduced contract payout).
    Tense,
    /// Bundle E consumer. Docking refused between member factions,
    /// contract auto-cancel, gate surcharges.
    Hostile,
    /// Bundle G consumer. Explicit — never auto-entered. Always manual
    /// or AI-driven declaration from `Hostile`.
    War,
}

impl TreatyKind {
    pub fn as_str(self) -> &'static str {
        match self {
            TreatyKind::Neutral => "neutral",
            TreatyKind::TradePact => "trade_pact",
            TreatyKind::Allied => "allied",
            TreatyKind::Tense => "tense",
            TreatyKind::Hostile => "hostile",
            TreatyKind::War => "war",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "neutral" => Some(TreatyKind::Neutral),
            "trade_pact" => Some(TreatyKind::TradePact),
            "allied" => Some(TreatyKind::Allied),
            "tense" => Some(TreatyKind::Tense),
            "hostile" => Some(TreatyKind::Hostile),
            "war" => Some(TreatyKind::War),
            _ => None,
        }
    }
}

/// Live state for one canonical faction pair.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct RelationState {
    /// Running standing score. Positive = friendly, negative = rival.
    /// Clamped to `-100..=100` on every mutation.
    pub standing: i32,
    pub treaty: TreatyKind,
    /// Tick at which the current treaty state was entered. Used to
    /// gate "must hold this threshold for N ticks" upgrades.
    pub since_tick: u64,
    /// Tick of the last standing-moving event. Decay skips pairs that
    /// just moved so a noisy delivery stream doesn't race the decay.
    pub last_event_tick: u64,
}

impl Default for RelationState {
    fn default() -> Self {
        Self {
            standing: 0,
            treaty: TreatyKind::Neutral,
            since_tick: 0,
            last_event_tick: 0,
        }
    }
}

impl RelationState {
    pub const STANDING_MIN: i32 = -100;
    pub const STANDING_MAX: i32 = 100;

    pub fn new(tick: u64) -> Self {
        Self {
            standing: 0,
            treaty: TreatyKind::Neutral,
            since_tick: tick,
            last_event_tick: tick,
        }
    }
}

/// Canonicalise a `(a, b)` pair to `(min, max)` so queries in either
/// direction hit the same bucket. Returns the pair ordered lexically.
///
/// Public so snapshot / API layers can emit in a stable order too.
pub fn canonical_pair(a: &str, b: &str) -> (String, String) {
    if a <= b {
        (a.to_string(), b.to_string())
    } else {
        (b.to_string(), a.to_string())
    }
}

/// Singleton pinned to `AgentStore`. Maps canonical faction-id pair →
/// live relation state. See module docs for invariants.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FactionRelations {
    by_pair: HashMap<(String, String), RelationState>,
}

impl FactionRelations {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn len(&self) -> usize {
        self.by_pair.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_pair.is_empty()
    }

    /// Read the relation between `a` and `b`, if present. Returns `None`
    /// when the pair has never been touched — callers may treat that
    /// as `RelationState::default()` implicitly.
    pub fn state(&self, a: &str, b: &str) -> Option<&RelationState> {
        if a == b {
            return None;
        }
        self.by_pair.get(&canonical_pair(a, b))
    }

    /// Read-or-default — saves callers the `.unwrap_or_default()` dance.
    pub fn state_or_default(&self, a: &str, b: &str) -> RelationState {
        self.state(a, b).copied().unwrap_or_default()
    }

    /// Shift the standing by `delta`, clamping into
    /// `[STANDING_MIN, STANDING_MAX]`. Creates the pair at `tick` if
    /// absent. Self-pairs are a no-op (no meaningful standing with
    /// yourself).
    ///
    /// Returns the new standing. Does NOT update treaty — that's the
    /// job of `tick_relations` which runs on cadence and can make the
    /// "sustained N ticks" judgement.
    pub fn bump_standing(&mut self, a: &str, b: &str, delta: i32, tick: u64) -> i32 {
        if a == b {
            return 0;
        }
        let key = canonical_pair(a, b);
        let entry = self.by_pair.entry(key).or_insert_with(|| RelationState::new(tick));
        entry.standing = (entry.standing + delta).clamp(RelationState::STANDING_MIN, RelationState::STANDING_MAX);
        entry.last_event_tick = tick;
        entry.standing
    }

    /// Directly set the treaty — called by `tick_relations` when a
    /// threshold-sustained condition fires, or by the admin endpoint.
    /// Resets `since_tick` so the next upgrade gate starts fresh.
    pub fn set_treaty(&mut self, a: &str, b: &str, treaty: TreatyKind, tick: u64) {
        if a == b {
            return;
        }
        let key = canonical_pair(a, b);
        let entry = self.by_pair.entry(key).or_insert_with(|| RelationState::new(tick));
        if entry.treaty == treaty {
            return;
        }
        entry.treaty = treaty;
        entry.since_tick = tick;
        entry.last_event_tick = tick;
    }

    /// Admin-override: set both standing and treaty in one shot.
    /// Preserves `since_tick` semantics — if the treaty changes, the
    /// clock resets; otherwise only the standing moves.
    pub fn set_state(&mut self, a: &str, b: &str, standing: i32, treaty: TreatyKind, tick: u64) {
        if a == b {
            return;
        }
        let key = canonical_pair(a, b);
        let entry = self.by_pair.entry(key).or_insert_with(|| RelationState::new(tick));
        let treaty_changed = entry.treaty != treaty;
        entry.standing = standing.clamp(RelationState::STANDING_MIN, RelationState::STANDING_MAX);
        entry.treaty = treaty;
        entry.last_event_tick = tick;
        if treaty_changed {
            entry.since_tick = tick;
        }
    }

    /// Iterate canonical pairs (mostly for snapshot / API dumps).
    pub fn iter(&self) -> impl Iterator<Item = (&(String, String), &RelationState)> {
        self.by_pair.iter()
    }
}

// ============================================================================
// Tick update — decay + threshold-driven treaty transitions
// ============================================================================

// ----------------------------------------------------------------------------
// Standing-change magnitudes consumed by the `DeliverContract` /
// `ReleaseContract` apply hooks. Small integers so decay can dominate
// noise: ~50 successful cross-faction deliveries to reach TradePact
// threshold, ~17 breaches to flip to Tense.
// ----------------------------------------------------------------------------

/// Standing bump between ship's faction and contract requestor's
/// faction on a successful delivery. Small — individual deliveries
/// should nudge, not slingshot, the relationship.
pub const DELIVERY_STANDING_BUMP: i32 = 1;
/// Standing penalty when a ship breaches (releases) a contract tied
/// to a faction. Larger magnitude than the delivery reward so
/// repeated flakes erode standing faster than honest trade rebuilds it.
pub const BREACH_STANDING_PENALTY: i32 = -3;

/// How often the relations tick runs (base ticks). 200 matches the
/// faction-tax cadence — relations are low-frequency state, a rebuild
/// once per "faction period" is plenty.
pub const RELATIONS_TICK_INTERVAL_BASE: u64 = 200;

/// Standing drifts this many points toward 0 each tick pass. Pair
/// moving ~+0.2/cycle means old grudges fade over thousands of ticks,
/// not minutes — which is what you want for persistent diplomacy.
/// Applied as a signed integer step (+1 or -1 per pass, only if far
/// enough from zero that one step won't oscillate).
pub const STANDING_DECAY_PER_PASS: i32 = 1;
/// Pairs within this magnitude of zero skip decay (no point creating
/// tick churn once they're already neutral).
pub const STANDING_DECAY_DEADBAND: i32 = 1;
/// Freshness grace period — pairs whose last event landed within this
/// many ticks skip decay this pass. Keeps a steady trade stream from
/// racing decay; long gaps let drift back toward neutral win.
pub const STANDING_DECAY_FRESHNESS_GRACE_BASE: u64 = 1_000;

/// Standing threshold above which two factions upgrade from Neutral
/// to TradePact (once sustained for `TRADE_PACT_SUSTAIN_BASE` ticks).
pub const TRADE_PACT_STANDING: i32 = 50;
/// Treaty upgrade sustain requirement: standing must have been ≥
/// `TRADE_PACT_STANDING` continuously for at least this many base
/// ticks before Neutral → TradePact fires. Measured as
/// `tick - since_tick`, which is why `bump_standing` does NOT reset
/// `since_tick` (only treaty changes do).
pub const TRADE_PACT_SUSTAIN_BASE: u64 = 500;
pub const ALLIED_STANDING: i32 = 75;
pub const ALLIED_SUSTAIN_BASE: u64 = 1_000;

/// Negative-side transitions. -50 → Tense, -70 → Hostile.
/// No sustain requirement for degradation: hostility compounds quickly.
pub const TENSE_STANDING: i32 = -50;
pub const HOSTILE_STANDING: i32 = -70;

/// Downgrade recovery: if standing improves past these floors the
/// pair walks back up the treaty ladder. Applied opportunistically
/// in the same pass as upgrades.
pub const TENSE_RECOVER_STANDING: i32 = -20;
pub const HOSTILE_RECOVER_STANDING: i32 = -40;
pub const TRADE_PACT_BREAK_STANDING: i32 = 20;
pub const ALLIED_BREAK_STANDING: i32 = 50;

/// Outcome of a single relations tick — returned so the caller can
/// push corresponding events. Keeps the pure `tick_relations`
/// reasoning out of the event-emitting layer in `sim_server`.
#[derive(Debug, Clone)]
pub struct RelationsTickEvents {
    /// Pairs that transitioned to a new treaty this pass. Emit
    /// `treaty_changed` (or the specific `treaty_signed` / `treaty_broken`)
    /// in the engine event Vec.
    pub treaty_changes: Vec<TreatyChange>,
}

#[derive(Debug, Clone)]
pub struct TreatyChange {
    pub a: String,
    pub b: String,
    pub from: TreatyKind,
    pub to: TreatyKind,
    pub standing: i32,
}

/// Run a single relations pass at `tick`. Applies standing decay and
/// evaluates every pair against the treaty thresholds.
///
/// Pure over the matrix — no world/ECS access. The caller is expected
/// to gate this behind a cadence check (see [`RELATIONS_TICK_INTERVAL_BASE`])
/// and to forward the returned events.
pub fn tick_relations(
    relations: &mut FactionRelations,
    tick: u64,
    tick_multiplier: u32,
) -> RelationsTickEvents {
    let mut changes = Vec::new();
    let freshness_grace =
        STANDING_DECAY_FRESHNESS_GRACE_BASE * tick_multiplier.max(1) as u64;
    let trade_pact_sustain = TRADE_PACT_SUSTAIN_BASE * tick_multiplier.max(1) as u64;
    let allied_sustain = ALLIED_SUSTAIN_BASE * tick_multiplier.max(1) as u64;

    for (pair, state) in relations.by_pair.iter_mut() {
        // --- Decay toward zero (skip fresh pairs) ---
        let fresh = tick.saturating_sub(state.last_event_tick) < freshness_grace;
        if !fresh && state.standing.abs() > STANDING_DECAY_DEADBAND {
            let step = STANDING_DECAY_PER_PASS.min(state.standing.abs());
            state.standing += if state.standing > 0 { -step } else { step };
        }

        // --- Treaty evaluation ---
        let from = state.treaty;
        let sustained_ticks = tick.saturating_sub(state.since_tick);
        let new_treaty = next_treaty(state.treaty, state.standing, sustained_ticks, trade_pact_sustain, allied_sustain);
        if new_treaty != from {
            state.treaty = new_treaty;
            state.since_tick = tick;
            // last_event_tick intentionally not updated — treaty change
            // doesn't make decay "fresh"; decay is driven by standing events.
            changes.push(TreatyChange {
                a: pair.0.clone(),
                b: pair.1.clone(),
                from,
                to: new_treaty,
                standing: state.standing,
            });
        }
    }

    RelationsTickEvents { treaty_changes: changes }
}

/// Compute the next treaty from current state, standing, and
/// time-in-current-state. Never transitions to `War` — that's an
/// explicit act, handled by Bundle G.
fn next_treaty(
    current: TreatyKind,
    standing: i32,
    sustained: u64,
    trade_pact_sustain: u64,
    allied_sustain: u64,
) -> TreatyKind {
    // Negative side dominates — a pair that crashes from TradePact
    // straight through to Hostile should land on Hostile, not walk
    // back through Neutral.
    if standing <= HOSTILE_STANDING {
        return TreatyKind::Hostile;
    }
    if standing <= TENSE_STANDING && matches!(current, TreatyKind::Neutral | TreatyKind::TradePact | TreatyKind::Allied) {
        return TreatyKind::Tense;
    }

    match current {
        TreatyKind::War => TreatyKind::War, // only Bundle G ends this
        TreatyKind::Hostile => {
            if standing >= HOSTILE_RECOVER_STANDING { TreatyKind::Tense } else { TreatyKind::Hostile }
        }
        TreatyKind::Tense => {
            if standing >= TENSE_RECOVER_STANDING { TreatyKind::Neutral } else { TreatyKind::Tense }
        }
        TreatyKind::Neutral => {
            if standing >= TRADE_PACT_STANDING && sustained >= trade_pact_sustain {
                TreatyKind::TradePact
            } else {
                TreatyKind::Neutral
            }
        }
        TreatyKind::TradePact => {
            if standing >= ALLIED_STANDING && sustained >= allied_sustain {
                TreatyKind::Allied
            } else if standing < TRADE_PACT_BREAK_STANDING {
                TreatyKind::Neutral
            } else {
                TreatyKind::TradePact
            }
        }
        TreatyKind::Allied => {
            if standing < ALLIED_BREAK_STANDING { TreatyKind::TradePact } else { TreatyKind::Allied }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_pair_orders_lexically() {
        assert_eq!(canonical_pair("a", "b"), ("a".into(), "b".into()));
        assert_eq!(canonical_pair("b", "a"), ("a".into(), "b".into()));
    }

    #[test]
    fn lookup_is_symmetric() {
        let mut r = FactionRelations::new();
        r.bump_standing("alpha", "beta", 10, 0);
        assert_eq!(r.state("alpha", "beta").unwrap().standing, 10);
        assert_eq!(r.state("beta", "alpha").unwrap().standing, 10);
    }

    #[test]
    fn bump_clamps_to_bounds() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", 500, 0);
        assert_eq!(r.state("a", "b").unwrap().standing, RelationState::STANDING_MAX);
        r.bump_standing("a", "b", -500, 0);
        assert_eq!(r.state("a", "b").unwrap().standing, RelationState::STANDING_MIN);
    }

    #[test]
    fn self_pair_is_noop() {
        let mut r = FactionRelations::new();
        r.bump_standing("alpha", "alpha", 50, 0);
        assert!(r.state("alpha", "alpha").is_none());
        assert_eq!(r.len(), 0);
    }

    #[test]
    fn set_treaty_resets_since_tick() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", 10, 100);
        r.set_treaty("a", "b", TreatyKind::TradePact, 500);
        let s = r.state("a", "b").unwrap();
        assert_eq!(s.treaty, TreatyKind::TradePact);
        assert_eq!(s.since_tick, 500);
    }

    #[test]
    fn decay_pulls_toward_zero_after_freshness_grace() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", 10, 0);
        // Tick well past the freshness grace period.
        let tick = STANDING_DECAY_FRESHNESS_GRACE_BASE + 1;
        tick_relations(&mut r, tick, 1);
        let after = r.state("a", "b").unwrap().standing;
        assert!(after < 10, "expected decay, got {after}");
    }

    #[test]
    fn decay_skips_fresh_pairs() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", 10, 900);
        tick_relations(&mut r, 1000, 1); // within grace window
        assert_eq!(r.state("a", "b").unwrap().standing, 10);
    }

    #[test]
    fn trade_pact_requires_sustained_standing() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", 60, 0);
        // Insufficient time at threshold.
        tick_relations(&mut r, 100, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::Neutral);
        // Enough time — should fire. Use a short tick_multiplier=1 so
        // TRADE_PACT_SUSTAIN_BASE is the literal tick count.
        // Restamp the standing to defer decay past the event moment.
        r.bump_standing("a", "b", 0, TRADE_PACT_SUSTAIN_BASE + 1);
        tick_relations(&mut r, TRADE_PACT_SUSTAIN_BASE + 2, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::TradePact);
    }

    #[test]
    fn hostile_fires_on_deep_negative() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", -80, 0);
        let ev = tick_relations(&mut r, 10, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::Hostile);
        assert!(ev.treaty_changes.iter().any(|c| c.to == TreatyKind::Hostile));
    }

    #[test]
    fn tense_fires_on_moderate_negative() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", -55, 0);
        tick_relations(&mut r, 10, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::Tense);
    }

    #[test]
    fn hostile_recovers_to_tense_when_standing_improves() {
        let mut r = FactionRelations::new();
        r.bump_standing("a", "b", -80, 0);
        tick_relations(&mut r, 10, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::Hostile);
        // Improve standing past recovery threshold.
        r.bump_standing("a", "b", 45, 20); // -80 + 45 = -35, past HOSTILE_RECOVER_STANDING(-40)
        tick_relations(&mut r, 30, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::Tense);
    }

    #[test]
    fn war_is_sticky() {
        let mut r = FactionRelations::new();
        r.set_treaty("a", "b", TreatyKind::War, 0);
        // Standing improvement doesn't end war — Bundle G owns truce.
        r.bump_standing("a", "b", 100, 10);
        tick_relations(&mut r, 20, 1);
        assert_eq!(r.state("a", "b").unwrap().treaty, TreatyKind::War);
    }

    #[test]
    fn admin_set_state_clamps_standing() {
        let mut r = FactionRelations::new();
        r.set_state("a", "b", 999, TreatyKind::Allied, 0);
        let s = r.state("a", "b").unwrap();
        assert_eq!(s.standing, RelationState::STANDING_MAX);
        assert_eq!(s.treaty, TreatyKind::Allied);
    }
}
