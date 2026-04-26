//! Ship ECS components — pure data definitions for the hecs world.
//!
//! Every ship entity is spawned with the bundle below. Fields are grouped
//! by access pattern so that tick phases load only the data they need —
//! position updates don't pull cargo or AI into cache.
//!
//! Spawn a ship with:
//! ```ignore
//! world.spawn((
//!     ShipIdentity { ... },
//!     ShipPosition { ... },
//!     ShipTransit { transit: None },
//!     ShipCargo { ... },
//!     ShipFuel { ... },
//!     ShipEconomy { ... },
//!     ShipAI { ... },
//!     ShipMemory { ... },
//!     ShipLifecycle { ... },
//!     ShipCrew { ... },
//!     ShipCrewSkills { ... },
//!     ShipProgression { ... },
//!     ShipFitting { ... },
//! ));
//! ```
//!
//! Co-located here: the lifecycle / strike / explore / level constants
//! that the component impls reference (e.g. `ShipCrew::needs_shore_leave`
//! reads `CREW_SHORE_LEAVE_TRIGGER`, `ShipProgression::grant_xp` reads
//! `SHIP_LEVEL_CAP`). Tick-loop tuning constants stay in
//! `ship/mod.rs` next to the tick code that uses them.
//!
//! Extracted from `ship/mod.rs` in the Phase-21 god-module split.

use crate::ai::{
    behavior_tree::BtNode,
    personality::Personality,
};
use crate::economy::commodities::{Cargo, Commodity, PriceKnowledge};
use hecs::Entity;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use super::ShipAction;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transit {
    pub from: String,
    pub to: String,
    pub departure_tick: u64,
    /// Display-only estimate. Recomputed each tick from remaining distance
    /// and current world_speed. Persist it for snapshot stability but don't
    /// gate arrival on it.
    pub arrival_tick: u64,
    /// Universe-space position captured at departure. Interpolation uses this
    /// fixed origin instead of re-resolving the source body's live orbit
    /// position each tick — otherwise the source drifts out from under the
    /// ship and it gets visually yanked along the body's orbit arc instead
    /// of tracing a straight path to its destination.
    #[serde(default)]
    pub departure_position: Option<(f32, f32)>,
    /// Total distance (route units) to cover for this leg.
    #[serde(default)]
    pub distance_total: f32,
    /// Distance covered so far. Arrive when >= `distance_total`.
    #[serde(default)]
    pub distance_travelled: f32,
}


/// Stable identity — set at spawn, rarely mutated.
#[derive(Debug, Clone)]
pub struct ShipIdentity {
    pub db_id: i64,
    /// Human-readable agent id, e.g. "ship-artemis-7".
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    /// Scale tier (Phase 18f). Orthogonal to `class` — drives
    /// default sensor tier at spawn + cross-system contract
    /// visibility via the sensor-range check in `try_plan_contract`.
    pub size: crate::simulation::config::ShipSize,
}

/// Spatial state — changes every tick while in transit.
#[derive(Debug, Clone)]
pub struct ShipPosition {
    pub location_name: Option<String>, // None while in transit
    pub docked_at: Option<Entity>,      // facility entity if docked
    pub system_id: String,
    pub universe_offset: (f32, f32),
    pub position: (f32, f32),
}

/// Transit state. `None` when the ship is stationary (docked or idle at a location).
#[derive(Debug, Clone)]
pub struct ShipTransit {
    pub transit: Option<Transit>,
}

/// Cargo hold.
#[derive(Debug, Clone)]
pub struct ShipCargo {
    pub cargo: Cargo,
    pub capacity: u32,
    /// tick each commodity was first acquired (for hoard detection)
    pub cargo_age: HashMap<Commodity, u64>,
    /// Phase 20: where each commodity was bought and at what price,
    /// used by the Sell action to compute actual realised profit and
    /// feed it into `ShipMemory.route_performance`. Cleared when the
    /// commodity's cargo entry drops to zero.
    pub cargo_origin: HashMap<Commodity, (String, f32)>,
}

impl ShipCargo {
    pub fn used(&self) -> u32 {
        self.cargo.values().sum()
    }
    pub fn free(&self) -> u32 {
        self.capacity.saturating_sub(self.used())
    }
}

/// Fuel and propulsion.
#[derive(Debug, Clone)]
pub struct ShipFuel {
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub fuel_consumption_rate: f32,
    pub speed_modifier: f32,
}

impl ShipFuel {
    pub fn fraction(&self) -> f32 {
        if self.fuel_capacity > 0.0 { self.fuel / self.fuel_capacity } else { 0.0 }
    }
}

/// Economic state.
#[derive(Debug, Clone)]
pub struct ShipEconomy {
    pub credits: i64,
    pub efficiency: f32,
    pub active_contract_id: Option<String>,
    pub faction_reputation: HashMap<String, u8>,
    /// Tick at which the ship entered its current `DockDwell` step.
    /// Ephemeral — not persisted. `None` while not dwelling.
    pub dock_dwell_start_tick: Option<u64>,
    /// Tick at which the ship entered its current `Rest` action.
    /// Ephemeral — not persisted. `None` while not resting. Used by
    /// the Rest action to time out after `MAX_REST_TICKS_BASE × mult`
    /// ticks so a crew that can't actually dock (e.g. facility
    /// full) doesn't stay on the Rest BT indefinitely with morale
    /// pinned at 0.
    pub rest_start_tick: Option<u64>,
    /// Tick at which the ship first requested the current `Dock`.
    /// Ephemeral — not persisted. `None` while not attempting to
    /// dock. Used by the Dock action to give up after a context-
    /// dependent wait budget (shorter for ships with no contract
    /// or low morale — "docks are jammed, we can't afford to
    /// wait — head to another station").
    pub dock_attempt_start_tick: Option<u64>,
}

/// AI: personality + current goal + BT state (parameterized over ShipAction).
#[derive(Debug, Clone)]
pub struct ShipAI {
    pub personality: Personality,
    pub current_goal: String,
    pub current_bt: Option<BtNode<ShipAction>>,
    /// Bundle 2.2: score the planner assigned to `current_goal`
    /// when it picked the plan. Used by the mid-action replan
    /// check: a fresh candidate's score must beat this by
    /// `REPLAN_SCORE_RATIO` to interrupt the running BT.
    pub current_goal_score: f32,
    /// Bundle 2.2: tick at which the running plan was chosen.
    /// Replan checks gate on `tick - last_plan_tick >= REPLAN_MIN_COMMIT_TICKS`
    /// to prevent thrashing — ships commit to a plan for a minimum
    /// dwell before reconsidering.
    pub last_plan_tick: u64,
}


/// Learned memory — price knowledge, visited locations.
/// Rarely loaded except during trade decisions.
#[derive(Debug, Clone)]
pub struct ShipMemory {
    pub price_knowledge: PriceKnowledge,
    pub visited: Vec<String>,
    /// Phase 19h: ring buffer of recently-visited star systems. Used by
    /// the explore goal to pick a target the ship hasn't been to
    /// lately — prevents gate yo-yo (A → B → A → B) when the
    /// exploration heuristic keeps picking the same neighbor. Capped
    /// at [`RECENT_SYSTEMS_CAP`]; oldest entries evict when it overflows.
    pub recent_systems: std::collections::VecDeque<String>,
    /// Phase 20: learned outcomes for (from, to, commodity) trade
    /// routes. Populated by the Sell action when it can match the
    /// sold commodity to a remembered origin (see
    /// `ShipCargo.cargo_origin`). `best_trade_route` applies a
    /// penalty when a ship's actual avg profit on a route is far
    /// below what current price memory suggests — lets individual
    /// ships drift away from saturated runs instead of all
    /// competing for the same Earth↔Mars margin.
    pub route_performance: HashMap<(String, String, Commodity), RouteStats>,
}

/// Running aggregate of trade-route outcomes for a single
/// (from, to, commodity) triple. The planner reads
/// `total_profit_per_unit / attempts` as an average margin the ship
/// has actually realised; compare to the current
/// `(sell_price - buy_price)` projection to detect stale memory /
/// competitor saturation. Plain struct so it round-trips through
/// future persistence migrations trivially.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RouteStats {
    pub attempts: u32,
    pub total_profit_per_unit: f32,
}

impl RouteStats {
    pub fn avg_profit_per_unit(&self) -> f32 {
        if self.attempts == 0 {
            0.0
        } else {
            self.total_profit_per_unit / self.attempts as f32
        }
    }

    pub fn record(&mut self, profit_per_unit: f32) {
        self.attempts = self.attempts.saturating_add(1);
        self.total_profit_per_unit += profit_per_unit;
    }
}

/// Max length of `ShipMemory.recent_systems`. 5 gives a ship enough
/// memory to avoid immediate back-tracking across a 6-system network
/// while still rotating through every system over a long run.
pub const RECENT_SYSTEMS_CAP: usize = 5;

/// How many ticks of idle-at-location before a ship escalates from
/// plain `idle` into `explore`. Scales roughly with world_speed — at
/// tick_scale=0.25, ~240 base ticks is a minute of real time of
/// sitting still. Below the threshold, the ship chills.
pub const IDLE_EXPLORE_TICKS: u32 = 240;

/// Ticks a ship dwells at an explored destination before re-planning
/// ("check the board"). Ensures they see a cycle of local contract
/// postings before they leave. 5 seconds at TPS=8 = 40 base ticks.
pub const EXPLORE_CHECK_BOARD_SECONDS: u8 = 5;

/// Minimum credits + fuel-budget (as fraction of capacity) a ship
/// must have to plan an explore. Covers a gate fee + a bit of return
/// headroom so we don't strand broke ships in strange systems.
pub const EXPLORE_MIN_CREDITS: i64 = 2_500;
pub const EXPLORE_MIN_FUEL_FRACTION: f32 = 0.40;

// --- Strike / retirement rules (Phase 19-tail "adaptive fleet") ---
//
// Strikes accumulate on a slow cadence so a ship has time to recover
// before being retired. Two classes:
//   * `broke_strike` — credits < FLOOR AND no cargo AND no active
//     contract. Reset when credits climb above RECOVERY. Captures the
//     ship-is-stuck-and-starving case.
//   * `hoard_strike` — credits > CEILING AND idle for a long time.
//     Reset on any contract completion (see `reset_hoard_strikes`).
//     Captures the ship-is-rich-but-parked case that locks credits
//     out of the economy.
//
// At MAX_STRIKES of either type the ship is decommissioned and the
// engine queues a replacement ship spawn (see `pending_respawns`).

/// How often strikes are evaluated (base ticks). Slow enough that a
/// ship can work its way back to solvency or a delivery between
/// checks — ~60 s at world_speed 1.
pub const STRIKE_CHECK_INTERVAL_BASE: u64 = 500;

/// Strikes of either type required to trigger retirement.
pub const MAX_STRIKES: u8 = 3;

/// Credits ceiling that earns a broke strike per check cycle.
pub const BROKE_CREDITS_THRESHOLD: i64 = 500;
/// Credits floor that clears accumulated broke strikes. Set higher than
/// the strike threshold so a ship hovering at the line doesn't oscillate.
pub const BROKE_RECOVERY_THRESHOLD: i64 = 5_000;

/// Credits floor that earns a hoard strike when combined with long
/// idle. Sized so only genuinely-stuck wealthy ships get flagged.
pub const HOARD_CREDITS_THRESHOLD: i64 = 200_000;
/// Minimum `idle_ticks` accumulated alongside `HOARD_CREDITS_THRESHOLD`
/// before a hoard strike increments.
pub const HOARD_IDLE_THRESHOLD: u32 = 500;

/// Lifecycle counters and dirty flag for persistence.
#[derive(Debug, Clone)]
pub struct ShipLifecycle {
    pub broke_strikes: u8,
    pub hoard_strikes: u8,
    pub idle_ticks: u32,
    pub dirty: bool,
}

/// Aggregated crew stats — one per ship, not per crew member.
///
/// Rather than spawning ~1000 individual crew entities (4× the agent count),
/// we track aggregate morale/fatigue/hunger + a single `current_task`
/// that describes what the crew is collectively doing this tick. This
/// matches the Elixir `CrewComplement` model 1:1 while keeping a single
/// component per ship.
///
/// Floats (not u8) because rates are fractional per tick_scale and integer
/// rounding would gradually erode values at low world_speed.
///
/// Co-located shore-leave constants (used by [`ShipCrew::needs_shore_leave`]
/// and [`ShipCrew::shore_leave_complete`]). Other crew tuning constants
/// (hunger / fatigue rates, wage interval, etc.) live in `ship/mod.rs`
/// alongside the tick code that consumes them — these two are here
/// because the impl methods on `ShipCrew` reference them directly.
#[derive(Debug, Clone)]
pub struct ShipCrew {
    pub size: u32,
    /// 0–100. Rises every tick; `> 55` triggers `Eating` when food is
    /// available. `> 60` penalises morale.
    pub hunger: f32,
    /// 0–100. Low morale → efficiency drops; shore-leave target resets to 100.
    pub morale: f32,
    /// 0–100. Rises in transit/active, drops while resting. `> 70` penalises morale.
    pub fatigue: f32,
    /// 0–100. Damage system isn't live yet — stays near 100 for now.
    pub health: f32,
    /// Accumulated unpaid wages (credits). Settled into ShipEconomy.credits
    /// on docked wage payouts or deducted as morale penalty if unpaid.
    pub wages_credits: i64,
    /// What the crew is doing right now. Aggregate — the whole crew does
    /// the same thing each tick, matching the Elixir aggregate model.
    pub current_task: CrewTask,
    pub dirty: bool,
}

/// Crew's current task. Set by `tick_crew` based on ship state + needs.
/// Matches Elixir's `:idle | :piloting | :engineering | :trading |
/// :eating | :resting | :on_mission` atoms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CrewTask {
    Idle,
    Piloting,
    Engineering,
    Trading,
    /// Bringing cargo on-board at a station (Buy / cargo pickup).
    Loading,
    /// Offloading cargo at a station (SellAll / DeliverCargo).
    Unloading,
    Eating,
    Resting,
    OnMission,
}

impl CrewTask {
    pub fn as_str(&self) -> &'static str {
        match self {
            CrewTask::Idle => "idle",
            CrewTask::Piloting => "piloting",
            CrewTask::Engineering => "engineering",
            CrewTask::Trading => "trading",
            CrewTask::Loading => "loading",
            CrewTask::Unloading => "unloading",
            CrewTask::Eating => "eating",
            CrewTask::Resting => "resting",
            CrewTask::OnMission => "on_mission",
        }
    }
}

impl ShipCrew {
    /// Efficiency multiplier derived from morale + health, floor 0.1.
    /// Matches Elixir `efficiency/1`: `health/100 × 0.6 + morale/100 × 0.4`.
    pub fn efficiency(&self) -> f32 {
        let e = self.health / 100.0 * 0.6 + self.morale / 100.0 * 0.4;
        e.clamp(0.1, 1.0)
    }

    pub fn needs_shore_leave(&self) -> bool {
        self.morale < CREW_SHORE_LEAVE_TRIGGER
    }

    pub fn shore_leave_complete(&self) -> bool {
        self.morale >= CREW_SHORE_LEAVE_TARGET
    }
}

/// Morale below this triggers the `rest_crew` planner goal (shore leave).
pub const CREW_SHORE_LEAVE_TRIGGER: f32 = 50.0;
/// Morale at/above this ends shore leave. Elixir requires full 100.
pub const CREW_SHORE_LEAVE_TARGET: f32 = 100.0;

/// Skill ratings (0–100) aggregated over the crew. Granted as XP through
/// `SimCommand::GrantCrewXp` after missions, deliveries, and trades.
/// Matches Elixir `crew.skills: %{navigation, engineering, trading, combat}`.
#[derive(Debug, Clone)]
pub struct ShipCrewSkills {
    pub navigation: u8,
    pub engineering: u8,
    pub trading: u8,
    pub combat: u8,
}

impl ShipCrewSkills {
    pub const CAP: u8 = 100;

    /// Default skill levels for a crew of `roles` (e.g. `["pilot",
    /// "engineer", "trader"]`). Base 30/30/30/20, +10 per role.
    pub fn for_roles(roles: &[&str]) -> Self {
        let mut s = Self {
            navigation: 30,
            engineering: 30,
            trading: 30,
            combat: 20,
        };
        for role in roles {
            match *role {
                "pilot" => s.navigation = (s.navigation + 10).min(Self::CAP),
                "engineer" => s.engineering = (s.engineering + 10).min(Self::CAP),
                "trader" => s.trading = (s.trading + 10).min(Self::CAP),
                _ => {}
            }
        }
        s
    }

    /// Add XP to a named skill, capped at 100. Unknown skill names no-op.
    pub fn grant(&mut self, skill: &str, amount: u8) {
        match skill {
            "navigation" => self.navigation = self.navigation.saturating_add(amount).min(Self::CAP),
            "engineering" => {
                self.engineering = self.engineering.saturating_add(amount).min(Self::CAP)
            }
            "trading" => self.trading = self.trading.saturating_add(amount).min(Self::CAP),
            "combat" => self.combat = self.combat.saturating_add(amount).min(Self::CAP),
            _ => {}
        }
    }
}

/// Ship-level progression (Phase 18d).
///
/// Mirrors `FacilityLifecycle.level/xp`: the ship earns XP from
/// meaningful accomplishments (contract deliveries today, maybe more
/// sources later) and levels up when XP crosses `level × 100`. Each
/// level-up banks one `retrofit_point` — the agent-side gate for
/// autonomous refits. A ship never buys a module it hasn't earned,
/// which matches the "retrofit is rare" design intent: a seed-fleet
/// level-1 ship needs ~5 deliveries of XP to level up once, and it
/// still needs credits + a reachable shipyard with stock before any
/// swap happens.
#[derive(Debug, Clone)]
pub struct ShipProgression {
    pub level: u8,
    pub xp: u32,
    /// Unspent retrofit points. One is banked per level-up; one is
    /// consumed by a successful `SimCommand::RequestRefit` apply.
    pub retrofit_points: u8,
    pub dirty: bool,
}

/// Ship XP cap — same shape as the facility level cap.
pub const SHIP_LEVEL_CAP: u8 = 10;
/// XP granted per successful contract delivery. Tuning knob — slower
/// = rarer retrofits. 15 gets roughly one retrofit point per 7
/// deliveries (threshold is level × 100 ⇒ first ding at 100 XP).
pub const SHIP_XP_PER_DELIVERY: u32 = 15;

impl Default for ShipProgression {
    fn default() -> Self {
        Self::new()
    }
}

impl ShipProgression {
    pub fn new() -> Self {
        Self {
            level: 1,
            xp: 0,
            retrofit_points: 0,
            dirty: false,
        }
    }

    pub fn next_level_threshold(&self) -> u32 {
        self.level as u32 * 100
    }

    /// Grant `amount` XP, cascading level-ups. Each level earned banks
    /// one retrofit point. Returns the number of levels gained this
    /// call (for events / tests).
    pub fn grant_xp(&mut self, amount: u32) -> u8 {
        if amount == 0 {
            return 0;
        }
        self.xp = self.xp.saturating_add(amount);
        let mut gained = 0u8;
        while self.level < SHIP_LEVEL_CAP && self.xp >= self.next_level_threshold() {
            self.xp -= self.next_level_threshold();
            self.level += 1;
            self.retrofit_points = self.retrofit_points.saturating_add(1);
            gained += 1;
        }
        self.dirty = true;
        gained
    }

    /// Attempt to spend one retrofit point. Returns true on success.
    pub fn spend_retrofit_point(&mut self) -> bool {
        if self.retrofit_points > 0 {
            self.retrofit_points -= 1;
            self.dirty = true;
            true
        } else {
            false
        }
    }
}

/// Subsystem / module fitting. Stored per-ship, mutated when the ship
/// refits (Phase 18b+). The cached `derived` rollup is recomputed on
/// every write via `recompute()` and consumed at read sites that want
/// a post-fitting view of the ship (transit speed, cargo capacity,
/// sensor range). Base values for cargo capacity and fuel `speed_modifier`
/// still live on `ShipCargo` / `ShipFuel` — they get *baked* with the
/// fitting's multipliers at spawn / refit time, so tick-loop code reads
/// the same field it always did.
#[derive(Debug, Clone)]
pub struct ShipFitting {
    /// Chosen module in each slot. Indexed by [`crate::modules::Slot::index`];
    /// array length is [`crate::modules::NUM_SLOTS`].
    pub slots: [Option<&'static str>; crate::modules::NUM_SLOTS],
    /// Cached rollup of all fitted modules' effects. Always kept in sync
    /// with `slots` via `recompute()`.
    pub derived: crate::modules::DerivedStats,
}

impl Default for ShipFitting {
    fn default() -> Self {
        Self::new_default()
    }
}

impl ShipFitting {
    /// Tier-1-default fitting — every slot filled with the baseline
    /// neutral module. Gameplay-identical to a pre-Phase-18 ship.
    pub fn new_default() -> Self {
        let slots = crate::modules::default_fitting();
        let derived = crate::modules::combine_effects(&slots);
        Self { slots, derived }
    }

    /// Size-aware default fitting (Phase 18f). Large-and-above hulls
    /// start with better sensors as part of their baseline so the
    /// intended cross-system traders (tankers, haulers, anything
    /// Huge/Massive) can see interstellar contracts day one.
    ///
    /// - Size ≥ 5 (Huge / Massive): always `sensors_t2`.
    /// - Size = 4 (Large): deterministic 50% roll by ship-id hash
    ///   — so the same ship always rolls the same way on reload.
    /// - Size ≤ 3: `sensors_t1` (pre-18f baseline).
    ///
    /// Other slots (engine / cargo_bay / reactor / comms) stay at
    /// tier 1 — upgrades come from retrofit, not default loadout.
    pub fn new_for_size(
        size: crate::simulation::config::ShipSize,
        ship_id: &str,
    ) -> Self {
        let mut slots = crate::modules::default_fitting();
        let wants_tier2_sensors = match size.tier() {
            t if t >= 5 => true,
            4 => {
                // Deterministic per-ship coin flip. A simple FNV-1a
                // variant keeps us off the rand crate dep for a
                // one-shot decision.
                let mut h: u64 = 0xcbf2_9ce4_8422_2325;
                for b in ship_id.bytes() {
                    h ^= b as u64;
                    h = h.wrapping_mul(0x100_0000_01b3);
                }
                h % 2 == 0
            }
            _ => false,
        };
        if wants_tier2_sensors {
            slots[crate::modules::Slot::Sensors.index()] = Some("sensors_t2");
        }
        let derived = crate::modules::combine_effects(&slots);
        Self { slots, derived }
    }

    /// Build a fitting from runtime slug strings (e.g. off a DB row).
    /// Unknown slugs fall back to the tier-1 default for that slot.
    pub fn from_slugs(raw: &[Option<String>; crate::modules::NUM_SLOTS]) -> Self {
        let mut slots: [Option<&'static str>; crate::modules::NUM_SLOTS] =
            [None; crate::modules::NUM_SLOTS];
        for slot in crate::modules::SLOTS.iter().copied() {
            let i = slot.index();
            slots[i] = match &raw[i] {
                Some(s) => crate::modules::intern_slug(s)
                    .or(Some(crate::modules::default_for_slot(slot))),
                None => None,
            };
        }
        let derived = crate::modules::combine_effects(&slots);
        Self { slots, derived }
    }

    /// Replace the module in one slot, recomputing the derived rollup.
    pub fn set(&mut self, slot: crate::modules::Slot, slug: Option<&'static str>) {
        self.slots[slot.index()] = slug;
        self.recompute();
    }

    /// Recompute `derived` from the current `slots`. Callers that reach
    /// into `slots` directly (e.g. bulk-populate from a save) must call
    /// this before the next tick reads `derived`.
    pub fn recompute(&mut self) {
        self.derived = crate::modules::combine_effects(&self.slots);
    }

    /// Return the slug in `slot`, if any.
    pub fn slot_slug(&self, slot: crate::modules::Slot) -> Option<&'static str> {
        self.slots[slot.index()]
    }
}

