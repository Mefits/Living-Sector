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
// Bundle B: dock-fee + burn modifiers per treaty state. Consumed by
// `commit_dock` in the engine. A `(fee_mult, burn_mult)` tuple —
// apply as `fee × fee_mult`, `burn_pct × burn_mult`. Neutral /
// missing / same-faction all resolve to (1.0, 1.0).
//
// Numbers chosen so TradePact feels like a real perk without making
// Allied-only routes economically obvious: a ship pays 80% of the
// base fee with a halved burn at TradePact, 60% with zero burn at
// Allied. Hostile reverses the sign (see Bundle E).
// ----------------------------------------------------------------------------

/// Returns `(fee_factor, burn_factor)` for a ship of `ship_faction`
/// docking at a facility owned by `fac_faction`. Both default to 1.0
/// when either side is missing or the pair is the same faction.
pub fn trade_pact_dock_modifier(
    relations: &FactionRelations,
    ship_faction: &str,
    fac_faction: &str,
) -> (f32, f32) {
    if ship_faction.is_empty() || fac_faction.is_empty() || ship_faction == fac_faction {
        return (1.0, 1.0);
    }
    let Some(state) = relations.state(ship_faction, fac_faction) else {
        return (1.0, 1.0);
    };
    match state.treaty {
        TreatyKind::TradePact => (0.8, 0.5),
        TreatyKind::Allied => (0.6, 0.0),
        _ => (1.0, 1.0),
    }
}

/// Returns the delivery-payment multiplier between a ship and a
/// contract's requestor faction. TradePact = +10%, Allied = +15%,
/// anything else = 1.0. Missing / same-faction short-circuits to 1.0.
pub fn trade_pact_payment_multiplier(
    relations: &FactionRelations,
    ship_faction: &str,
    requestor_faction: &str,
) -> f32 {
    if ship_faction.is_empty() || requestor_faction.is_empty() || ship_faction == requestor_faction {
        return 1.0;
    }
    let Some(state) = relations.state(ship_faction, requestor_faction) else {
        return 1.0;
    };
    match state.treaty {
        TreatyKind::TradePact => 1.10,
        TreatyKind::Allied => 1.15,
        _ => 1.0,
    }
}

/// True when `ship_faction` should see contracts tagged with
/// `requestor_faction` regardless of stored reputation. Bundle B:
/// TradePact + Allied = yes. Callers still OR this with the
/// per-ship rep-tier scan so explicit rep above 0 stays the
/// primary gate.
pub fn trade_pact_grants_visibility(
    relations: &FactionRelations,
    ship_faction: &str,
    requestor_faction: &str,
) -> bool {
    if ship_faction.is_empty() || requestor_faction.is_empty() || ship_faction == requestor_faction {
        // Same-faction always visible — same as the existing
        // behaviour when posted_by_faction buckets on the ship's
        // own id.
        return ship_faction == requestor_faction;
    }
    let Some(state) = relations.state(ship_faction, requestor_faction) else {
        return false;
    };
    matches!(state.treaty, TreatyKind::TradePact | TreatyKind::Allied)
}

/// Bundle B: "implied" reputation floor per counterpart faction
/// granted by an active treaty. TradePact lets the ship see the
/// allied tier (50), Allied lets the ship see the faction-only
/// tier (70). Callers merge this with `ShipEconomy.faction_reputation`
/// via `max()` so explicit rep above the treaty floor still wins.
///
/// Returned map keys are counterpart faction ids (never `ship_faction`).
/// Empty when the ship has no active positive treaties, which short-
/// circuits the caller's merge.
pub fn treaty_rep_floors(
    relations: &FactionRelations,
    ship_faction: &str,
) -> std::collections::HashMap<String, u8> {
    use std::collections::HashMap;
    let mut out = HashMap::new();
    if ship_faction.is_empty() {
        return out;
    }
    for (pair, state) in relations.iter() {
        let counterpart = if pair.0 == ship_faction {
            pair.1.as_str()
        } else if pair.1 == ship_faction {
            pair.0.as_str()
        } else {
            continue;
        };
        let floor = match state.treaty {
            TreatyKind::TradePact => 50,
            TreatyKind::Allied => 70,
            _ => continue,
        };
        out.insert(counterpart.to_string(), floor);
    }
    out
}

// ----------------------------------------------------------------------------
// Bundle C: market-posture price multipliers. Applied at the
// transaction point in `ShipAction::Buy` / `Sell` / `SellAll` —
// the market's posted price stays neutral, but every individual
// trade is adjusted by the specific ship's standing with whoever
// controls the market. Hostile relations amplify any surcharge
// (but never erode a discount that the ship earned through rep).
//
// Curve: +0.5% per rep-point below 50 (stranger pays more),
// -0.5% per rep-point above 50 (friend pays less). Clamped to
// [0.75, 1.25] so the posture can't run away.
// ----------------------------------------------------------------------------

/// Posture buy-price multiplier for a ship of `ship_faction`
/// trading at a market controlled by `controller_faction`, with
/// `rep_with_controller` as the ship's stored rep for that faction
/// (0..=100). Same-faction (ship buying at its own station) uses
/// 100 implicitly — you trust yourself.
pub fn market_buy_multiplier(
    relations: &FactionRelations,
    ship_faction: &str,
    rep_with_controller: u8,
    controller_faction: &str,
) -> f32 {
    // Treat own-faction as perfect rep (discount at the bulkhead).
    // Empty controller = wild / unowned market — neutral prices.
    let effective_rep: u8 = if controller_faction.is_empty() {
        50
    } else if !ship_faction.is_empty() && ship_faction == controller_faction {
        100
    } else {
        rep_with_controller
    };
    let base = (1.0 + (50.0 - effective_rep as f32) * 0.005).clamp(0.75, 1.25);

    let hostile = if ship_faction.is_empty() || controller_faction.is_empty() {
        false
    } else {
        relations
            .state(ship_faction, controller_faction)
            .map(|s| matches!(s.treaty, TreatyKind::Hostile | TreatyKind::War))
            .unwrap_or(false)
    };
    // Hostile doubles any surcharge (>1.0) but leaves earned
    // discounts alone — a high-personal-rep ship in a diplomatic
    // blow-up still benefits from the personal relationship at
    // the counter.
    if hostile && base > 1.0 {
        1.0 + (base - 1.0) * 2.0
    } else {
        base
    }
}

/// Sell-side posture multiplier — reciprocal of the buy multiplier
/// so a friend who pays 0.75× on buys also gets ~1.33× on sells.
/// Hostile amplification still applies via `market_buy_multiplier`.
pub fn market_sell_multiplier(
    relations: &FactionRelations,
    ship_faction: &str,
    rep_with_controller: u8,
    controller_faction: &str,
) -> f32 {
    let m = market_buy_multiplier(relations, ship_faction, rep_with_controller, controller_faction);
    1.0 / m
}

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
    fn trade_pact_dock_modifier_neutral_is_passthrough() {
        let r = FactionRelations::new();
        assert_eq!(trade_pact_dock_modifier(&r, "a", "b"), (1.0, 1.0));
    }

    #[test]
    fn trade_pact_dock_modifier_applies_by_treaty() {
        let mut r = FactionRelations::new();
        r.set_treaty("a", "b", TreatyKind::TradePact, 0);
        assert_eq!(trade_pact_dock_modifier(&r, "a", "b"), (0.8, 0.5));
        r.set_treaty("a", "b", TreatyKind::Allied, 10);
        assert_eq!(trade_pact_dock_modifier(&r, "a", "b"), (0.6, 0.0));
    }

    #[test]
    fn trade_pact_payment_multiplier_applies_by_treaty() {
        let mut r = FactionRelations::new();
        assert_eq!(trade_pact_payment_multiplier(&r, "a", "b"), 1.0);
        r.set_treaty("a", "b", TreatyKind::TradePact, 0);
        assert!((trade_pact_payment_multiplier(&r, "a", "b") - 1.10).abs() < 1e-6);
        r.set_treaty("a", "b", TreatyKind::Allied, 10);
        assert!((trade_pact_payment_multiplier(&r, "a", "b") - 1.15).abs() < 1e-6);
    }

    #[test]
    fn treaty_rep_floors_lifts_trade_pact_to_50() {
        let mut r = FactionRelations::new();
        r.set_treaty("alpha", "beta", TreatyKind::TradePact, 0);
        let floors = treaty_rep_floors(&r, "alpha");
        assert_eq!(floors.get("beta"), Some(&50));
        // Direction-insensitive — querying from the other side works too.
        let floors = treaty_rep_floors(&r, "beta");
        assert_eq!(floors.get("alpha"), Some(&50));
    }

    #[test]
    fn treaty_rep_floors_lifts_allied_to_70() {
        let mut r = FactionRelations::new();
        r.set_treaty("alpha", "beta", TreatyKind::Allied, 0);
        let floors = treaty_rep_floors(&r, "alpha");
        assert_eq!(floors.get("beta"), Some(&70));
    }

    #[test]
    fn treaty_rep_floors_ignores_non_positive_treaties() {
        let mut r = FactionRelations::new();
        r.set_treaty("alpha", "beta", TreatyKind::Tense, 0);
        r.set_treaty("alpha", "gamma", TreatyKind::Hostile, 0);
        r.set_treaty("alpha", "delta", TreatyKind::War, 0);
        assert!(treaty_rep_floors(&r, "alpha").is_empty());
    }

    #[test]
    fn market_buy_multiplier_stranger_is_neutral() {
        let r = FactionRelations::new();
        let m = market_buy_multiplier(&r, "alpha", 50, "beta");
        assert!((m - 1.0).abs() < 1e-6);
    }

    #[test]
    fn market_buy_multiplier_friend_discounts() {
        let r = FactionRelations::new();
        let m = market_buy_multiplier(&r, "alpha", 100, "beta");
        assert!((m - 0.75).abs() < 1e-6);
    }

    #[test]
    fn market_buy_multiplier_enemy_surcharges() {
        let r = FactionRelations::new();
        let m = market_buy_multiplier(&r, "alpha", 0, "beta");
        assert!((m - 1.25).abs() < 1e-6);
    }

    #[test]
    fn market_buy_multiplier_own_faction_auto_friendly() {
        let r = FactionRelations::new();
        let m = market_buy_multiplier(&r, "alpha", 0, "alpha");
        assert!((m - 0.75).abs() < 1e-6, "got {m}");
    }

    #[test]
    fn market_buy_multiplier_unowned_is_neutral() {
        let r = FactionRelations::new();
        let m = market_buy_multiplier(&r, "alpha", 100, "");
        assert!((m - 1.0).abs() < 1e-6);
    }

    #[test]
    fn market_buy_multiplier_hostile_doubles_surcharge() {
        let mut r = FactionRelations::new();
        r.set_treaty("alpha", "beta", TreatyKind::Hostile, 0);
        // rep=0 → base 1.25; hostile doubles surcharge → 1.5
        let m = market_buy_multiplier(&r, "alpha", 0, "beta");
        assert!((m - 1.5).abs() < 1e-6, "got {m}");
    }

    #[test]
    fn market_buy_multiplier_hostile_preserves_discount() {
        let mut r = FactionRelations::new();
        r.set_treaty("alpha", "beta", TreatyKind::Hostile, 0);
        // rep=100 → base 0.75; hostile amplification only hits surcharges
        let m = market_buy_multiplier(&r, "alpha", 100, "beta");
        assert!((m - 0.75).abs() < 1e-6, "got {m}");
    }

    #[test]
    fn market_sell_multiplier_is_reciprocal() {
        let r = FactionRelations::new();
        let buy = market_buy_multiplier(&r, "alpha", 100, "beta");
        let sell = market_sell_multiplier(&r, "alpha", 100, "beta");
        assert!((buy * sell - 1.0).abs() < 1e-6);
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
