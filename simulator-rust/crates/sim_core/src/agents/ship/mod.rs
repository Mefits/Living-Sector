//! Ship components for hecs storage.
//!
//! A ship entity is spawned with the full bundle of components below. Fields
//! are grouped by access pattern so that tick phases load only the data they
//! need — position updates don't pull cargo or AI into cache.
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
//! ));
//! ```

use crate::{
    ai::{
        behavior_tree::{Blackboard, BtNode, BtStatus},
        personality::Personality,
    },
    economy::commodities::{Cargo, Commodity, PriceKnowledge},
};
use hecs::Entity;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// In-transit data for a ship traveling between locations.
///
/// Progress is tracked as `distance_travelled` accumulating toward
/// `distance_total` each tick. That's distance covered per tick =
/// `speed_modifier × tick_scale`, so when the player changes `world_speed`
/// mid-flight, the ship's per-tick progress rescales automatically — you
/// don't get stuck watching an old `arrival_tick` count down at the old
/// rate. `arrival_tick` is kept as a display estimate; it's recomputed
/// each tick from `(distance_total − distance_travelled) × tick_mult /
/// speed_mod + current_tick`.
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

pub mod actions;
pub use actions::ShipAction;
use actions::execute_ship_action;


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

// Snapshot types (wire format for HTTP/WS) live in their own submodule
// after the Phase-20 `ship.rs` split. Re-exported at the module root
// so external callers (sim_server snapshot builder, persistence)
// continue to reference them as `sim_core::agents::ship::ShipSnapshot`.
pub mod snapshot;
pub use snapshot::{
    ShipCrewSkillsSnapshot, ShipCrewSnapshot, ShipDerivedStatsSnapshot,
    ShipFittingSnapshot, ShipProgressionSnapshot, ShipSnapshot,
};


// ============================================================================
// Tick logic — Phase 4 MVP
// ============================================================================
//
// Direct state-machine approach rather than full BT execution. The BT engine
// from Phase 1 is still available for Phase 4.5 when we want more elaborate
// goal chains, but for the MVP we use a simple decision tree each tick:
//
//   1. Advance transit (if in transit). Arrive → set location, clear transit.
//   2. Observe local market prices (if at a location, not in transit).
//   3. Decide:
//      - in transit? consume fuel, position interpolation
//      - fuel below 25%? instant refill (facility-based later)
//      - at location with cargo? sell locally at known price
//      - at location with empty cargo + known margin? buy locally → travel to sell
//      - at location without profitable route? idle (or explore later)
//
// Market supply changes emit SimCommand::AddSupply / RemoveSupply to the
// buffer. Credits move in-place (within the ship) because self-transfers
// don't need cross-agent coordination.

use crate::economy::commodities::PriceMemory;
use crate::simulation::commands::{CommandBuffer, SimCommand};
use crate::world::{pathfinder::{LegKind, PathfinderCtx}, registry::WorldRegistry};
use std::collections::HashMap as StdHashMap;

/// Estimate gate fees a contract route will cost. Used by the contract
/// planner to reject unprofitable cross-system runs before committing
/// to them. Counts the number of gate hops across all provided
/// (from, to) pairs and multiplies by the default per-gate fee using a
/// conservative cargo estimate.
///
/// Uses only `gate_pairs` (not a full registry) — the assumption is
/// that every cross-system trip crosses exactly one gate pair, which
/// is true for our 3-system topology today. A richer pathfinder-based
/// estimate can drop in later if we add intermediate systems.
fn estimate_route_gate_fees(
    pairs: &[(&str, &str)],
    gate_pairs: &StdHashMap<String, String>,
    cargo_estimate: u32,
) -> i64 {
    if gate_pairs.is_empty() {
        return 0;
    }
    // Build a cheap "system-of" lookup from gate location prefixes. Our
    // gate locations follow `{sys}-{dest_sys}-gate` — extract the first
    // two chars (the source system token) as a system tag.
    //
    // This is brittle (naming-dependent) but fast and contained. When
    // we add new systems, revisit.
    let system_tag = |loc: &str| -> String {
        // "sol-ac-gate" → "sol". "earth-station" → "earth-station" (no match).
        // We want to categorise *any* location by system; cheap proxy:
        // if the location is itself a gate, strip the dest-and-suffix;
        // else treat as a generic intra-system location and rely on
        // gate_pairs lookup below.
        if gate_pairs.contains_key(loc) {
            loc.split('-').next().unwrap_or(loc).to_string()
        } else {
            // Non-gate location; we'll handle it in the gate_pairs
            // walk below.
            String::from("_other_")
        }
    };
    let mut total: i64 = 0;
    // For each (from, to) pair, count 1 gate hop if they're in
    // different systems. We proxy "different systems" by checking the
    // gate_pairs map for any overlapping entry.
    for (from, to) in pairs {
        // Quick heuristic: if either endpoint is a known gate location,
        // there's a gate hop in this segment. Otherwise assume intra.
        let either_is_gate = gate_pairs.contains_key(*from) || gate_pairs.contains_key(*to);
        if either_is_gate {
            // Assume one gate hop per segment.
            total += crate::agents::facility::DEFAULT_GATE_FEE_FLAT
                + (crate::agents::facility::DEFAULT_GATE_FEE_PER_CARGO
                    * cargo_estimate as i64);
        } else {
            // System-tag heuristic as a fallback.
            let (a, b) = (system_tag(from), system_tag(to));
            if a != b && a != "_other_" && b != "_other_" {
                total += crate::agents::facility::DEFAULT_GATE_FEE_FLAT
                    + (crate::agents::facility::DEFAULT_GATE_FEE_PER_CARGO
                        * cargo_estimate as i64);
            }
        }
    }
    total
}

/// Expand a (from, to) request into the sequence of `ShipAction`s that
/// actually flies it. Intra-system trips return a single `Travel`;
/// cross-system trips fan out into `Travel → GateJump → Travel`.
///
/// Used by every BT builder so the planner doesn't have to think about
/// whether a destination is local or across a gate — the pathfinder
/// does it at plan time, and the BT just executes the chain.
fn route_actions(
    from: &str,
    to: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Vec<ShipAction> {
    if from == to {
        return Vec::new();
    }
    let ctx = PathfinderCtx { registry, gate_pairs };
    let legs = match ctx.find_route(from, to) {
        Some(v) => v,
        None => {
            // No route — fall back to a direct Travel. The action's
            // executor will pick a default distance and the ship just
            // flies in a straight line. Better than stalling the plan.
            return vec![ShipAction::Travel { destination: to.to_string() }];
        }
    };
    let mut out: Vec<ShipAction> = Vec::with_capacity(legs.len());
    for leg in legs {
        match leg.kind {
            LegKind::Travel => {
                out.push(ShipAction::Travel { destination: leg.to });
            }
            LegKind::Gate => {
                out.push(ShipAction::GateJump {
                    src_gate: leg.from,
                    dest_gate: leg.to,
                });
            }
        }
    }
    out
}

const MIN_TRADE_MARGIN: f32 = 0.10; // 10% minimum margin
const TRADE_QTY_DEFAULT: u32 = 50;

/// Bundle 1.4: per-event personality-drift magnitudes. Tiny so
/// archetype identity stays stable over the short term; visible only
/// over tens-to-hundreds of events. Hundred successful deliveries
/// shifts a ship's `profit` axis by ~+0.2; ten rest-timeouts (real
/// trauma) shift `safety` by ~+0.2.
pub const DRIFT_DELIVERY_PROFIT: f32 = 0.002;
pub const DRIFT_REST_TIMEOUT_SAFETY: f32 = 0.02;

/// Half-life (in base ticks) of a remembered price's weight when
/// scoring trade routes. At age=0 a price contributes fully; at
/// HALF_LIFE it's worth 50%; asymptotes toward a floor so even very
/// old observations still weakly count. ~1500 base ticks ≈ 3 minutes
/// of game time at `WORLD_SPEED=1.0`. Prevents ships from routing
/// on stale prices after long exploration tours. Paired floor keeps
/// early-game sims (few observations) from scoring everything at 0.
pub const PRICE_MEMORY_HALF_LIFE_TICKS: u64 = 1500;
pub const PRICE_MEMORY_FRESHNESS_FLOOR: f32 = 0.10;

/// Exponential-decay weight for a price observed at `observed_tick`
/// being scored at `current_tick`. Returns 1.0 for same-tick, 0.5
/// at HALF_LIFE, clamped to `[FRESHNESS_FLOOR, 1.0]`.
pub fn price_freshness_weight(observed_tick: u64, current_tick: u64) -> f32 {
    let age = current_tick.saturating_sub(observed_tick) as f32;
    let half = PRICE_MEMORY_HALF_LIFE_TICKS as f32;
    let raw = (-age / half).exp2();
    raw.clamp(PRICE_MEMORY_FRESHNESS_FLOOR, 1.0)
}

/// Sensor range (universe-units) required to see cross-system
/// contracts in the planner. 2.0 matches the tier-2 `sensors_t2`
/// baseline — tier-1 tiny sensors (1.0 au) can't pick up
/// interstellar traffic, so small ships that haven't upgraded
/// sensors are effectively restricted to intra-system trade. Size
/// ≥ 5 hulls (Huge / Massive) ship with tier-2 sensors as their
/// default loadout; size-4 (Large) ships roll 50% tier-2 at spawn.
pub const CROSS_SYSTEM_SENSOR_RANGE_AU: f32 = 2.0;

// --- Crew constants (match Elixir CrewComplement rates) ---

/// Base per-tick hunger gain (before tick_scale). Elixir `@hunger_rate 2`.
/// Scaled down from 2.0 → 1.0 alongside fatigue: at the old rates, a
/// crew hit the morale-penalty hunger threshold (60) halfway through
/// a typical inter-system trip, which then cascaded into rest_crew
/// lockouts on the next replan.
pub const CREW_HUNGER_RATE_BASE: f32 = 1.0;
/// Base per-tick fatigue gain while active. Dropped 1.0 → 0.4: at 1.0,
/// a pilot on a 300-tick voyage arrives past the fatigue-morale penalty
/// threshold (70) with no recovery window between legs, and the planner
/// sends them straight to shore leave — contracts never get considered.
/// 0.4 gives roughly 3× longer voyages before burnout trips.
pub const CREW_FATIGUE_RATE_ACTIVE_BASE: f32 = 0.4;
/// Base per-tick fatigue recovery while resting (negative = recovery).
pub const CREW_FATIGUE_RATE_REST_BASE: f32 = -5.0;
/// Base per-tick morale decay toward 50.
pub const CREW_MORALE_DECAY_BASE: f32 = 0.5;
/// Base morale recovery bump applied docked/resting (per check interval).
/// Morale recovery applied each morale-check interval when docked but
/// not actively resting (i.e. during refuel/load/unload). Bumped 3 → 6
/// so a ship that arrives drained climbs back to sustainable morale
/// during a normal trade visit, no shore leave required.
pub const CREW_MORALE_RECOVERY_DOCKED: f32 = 6.0;
pub const CREW_MORALE_RECOVERY_RESTING: f32 = 8.0;

/// Hunger threshold that triggers Eating task + morale penalty zone.
pub const CREW_HUNGER_EAT_THRESHOLD: f32 = 55.0;
/// Hunger threshold above which morale drops on check.
pub const CREW_HUNGER_MORALE_PENALTY: f32 = 60.0;
/// Fatigue threshold that triggers Resting task.
pub const CREW_FATIGUE_REST_THRESHOLD: f32 = 65.0;
/// Fatigue threshold above which morale drops on check.
pub const CREW_FATIGUE_MORALE_PENALTY: f32 = 70.0;

/// Morale below this triggers the `rest_crew` planner goal (shore leave).
pub const CREW_SHORE_LEAVE_TRIGGER: f32 = 50.0;
/// Morale at/above this ends shore leave. Elixir requires full 100.
pub const CREW_SHORE_LEAVE_TARGET: f32 = 100.0;

/// Morale floor the legacy `Rest` action uses to return Success. Keeps
/// short-rest semantics separate from shore leave.
pub const CREW_REST_TARGET: f32 = 80.0;

/// Phase 18k: cap on how long a ship will stay in the `Rest` BT action
/// before giving up and returning `Success` regardless of morale. Guards
/// against a facility-full-dock → "speculative" Dock → Rest-forever
/// death spiral where a crew that couldn't actually dock can't get
/// the docked-state recovery boost and stays pinned at morale=0.
///
/// 300 base ticks = ~38 s at default `WORLD_SPEED=0.25` (mult=32) or
/// ~9 s at `WORLD_SPEED=4` (mult=2). Long enough for a legitimate
/// shore-leave to complete, short enough that a stuck ship unwinds
/// its BT within a visible window.
pub const MAX_REST_TICKS_BASE: u64 = 300;

/// Phase 18L: how long a ship will sit in the `Dock` action waiting
/// for the apply phase to actually put it in a slot before deciding
/// "docks are jammed — let's try elsewhere." Expressed in BASE ticks
/// (scaled by `tick_multiplier` at wait-check time). The effective
/// budget depends on ship context:
///  - Has an active contract (a ship with a job to finish is willing
///    to wait longer for the 'right' dock): `DOCK_WAIT_WITH_CONTRACT`.
///  - Low-morale shore-leave candidate (needs relief urgently, can't
///    afford to sit in line): `DOCK_WAIT_LOW_MORALE`.
///  - Everything else (default — mid-patience): `DOCK_WAIT_DEFAULT`.
pub const DOCK_WAIT_WITH_CONTRACT: u64 = 150;
pub const DOCK_WAIT_DEFAULT: u64 = 60;
pub const DOCK_WAIT_LOW_MORALE: u64 = 30;
/// Morale threshold below which a ship gets the impatient wait budget.
pub const DOCK_WAIT_LOW_MORALE_THRESHOLD: f32 = 40.0;
/// Legacy alias for planner-side rest trigger kept for existing call sites.
/// Morale threshold below which the planner switches the ship into
/// rest_crew mode, overriding every other goal (including accepting a
/// contract). Dropped from 35 → 15 — at 35 the rest_crew rule was
/// firing so aggressively on ships between trade runs that contracts
/// never got accepted. At 15, a ship has to be genuinely burned out
/// (starving + exhausted + broke) to trigger shore leave.
pub const CREW_REST_TRIGGER: f32 = 15.0;

/// Base wage per crew member per pay cycle. Paid out every WAGE_INTERVAL
/// base-ticks from ShipEconomy.credits; unpaid wages drop morale.
pub const CREW_WAGE_PER_HEAD: i64 = 5;
pub const CREW_WAGE_INTERVAL_BASE: u64 = 50;
pub const CREW_WAGE_UNPAID_MORALE_DROP: f32 = 5.0;

/// Morale-check cadence (base ticks, pre-mult). Matches Elixir's 5×mult.
pub const CREW_MORALE_CHECK_INTERVAL_BASE: u64 = 5;

/// Food units one crew consumes per Eating task. Consumes `size × 1` food.
pub const CREW_FOOD_PER_CREW_PER_MEAL: u32 = 1;
/// Hunger reduction when a meal is successfully consumed.
pub const CREW_HUNGER_MEAL_REDUCTION: f32 = 25.0;

/// Tick all ships in 4 passes to keep hecs borrows clean.
#[allow(clippy::too_many_arguments)]
pub fn tick_ships(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    contracts: &crate::economy::contracts::ContractBoard,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    // Pass 1: LOD gate. Fire each ship's cursor once, collect the set
    // of entities that should tick this round with their rate multiplier
    // (skipped-ticks since last fire). Subsequent phases filter on this
    // map — it's the single source of truth for "should ship X run?".
    // Ships without an AgentLod component default to "every tick".
    //
    // Bundle 1.5: restrict advancement to ship entities only. Prior
    // to this the query advanced every AgentLod cursor in the world
    // (facilities + populations included), which defeats facility /
    // population LOD gates downstream because their cursors would
    // already have been advanced this tick.
    use crate::simulation::lod::AgentLod;
    let ship_entities: std::collections::HashSet<hecs::Entity> = world
        .query::<(&ShipIdentity, &AgentLod)>()
        .iter()
        .map(|(e, _)| e)
        .collect();
    let mut active: std::collections::HashMap<hecs::Entity, u32> =
        std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<&mut AgentLod>();
        for (e, lod) in lod_q.iter() {
            if !ship_entities.contains(&e) {
                continue;
            }
            if let Some(skipped) = lod.try_fire(tick) {
                active.insert(e, skipped);
            }
        }
    }
    // Any ship without an AgentLod component runs every tick.
    let ids_with_lod: std::collections::HashSet<hecs::Entity> = {
        world
            .query::<&AgentLod>()
            .iter()
            .map(|(e, _)| e)
            .collect()
    };
    let no_lod_ships: Vec<hecs::Entity> = world
        .query::<&ShipIdentity>()
        .iter()
        .map(|(e, _)| e)
        .filter(|e| !ids_with_lod.contains(e))
        .collect();
    for e in no_lod_ships {
        active.insert(e, 1);
    }

    advance_transits(world, registry, tick, tick_scale, tick_multiplier, &active);
    observe_prices(world, tick, &active, gate_pairs, registry);
    tick_crew(world, tick, tick_scale, tick_multiplier, &active);
    decide_and_act(
        world,
        registry,
        gate_pairs,
        contracts,
        commands,
        tick,
        tick_multiplier,
        &active,
    );
}

/// Type alias for the LOD gate table shared across ship tick phases.
/// Maps `entity → skipped_ticks_since_last_fire`. Entities not in the
/// map skip this round entirely.
type ShipLodGate = std::collections::HashMap<hecs::Entity, u32>;

/// Crew tick — matches Elixir `CrewComplement.tick` behavior:
///   1. Decay: hunger rises, fatigue rises (active) or falls (resting/idle)
///   2. Morale adjust every 5×mult ticks (penalties + recovery + drift)
///   3. `auto_manage_needs`: sets `current_task` to Eating/Resting when
///      needs are past threshold, else back to the crew's `primary_task`
///   4. Pay wages every 50×mult ticks: deduct from ShipEconomy.credits;
///      if insufficient, drop morale (unpaid wages sting)
///   5. Push `efficiency()` back into ShipEconomy so trade math uses it.
///
/// Food consumption when Eating: consumes `size × 1` food from cargo. The
/// old `rest_crew` goal path still works — it now simply picks
/// `CrewTask::Resting` via the same auto-manage logic.
fn tick_crew(
    world: &mut hecs::World,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    let morale_check_interval =
        CREW_MORALE_CHECK_INTERVAL_BASE * tick_multiplier as u64;
    let wage_interval = CREW_WAGE_INTERVAL_BASE * tick_multiplier as u64;

    // Collect per-ship snapshot info we need: class (for crew roles), transit
    // state, docked state. Done in a read pass so the mutable pass can close
    // over static data without hecs borrow conflicts.
    #[derive(Clone)]
    struct CrewCtx {
        entity: hecs::Entity,
        roles: &'static [&'static str],
        in_transit: bool,
        docked: bool,
    }
    let contexts: Vec<CrewCtx> = world
        .query::<(&ShipIdentity, &ShipTransit, &ShipPosition, &ShipCrew)>()
        .iter()
        .map(|(e, (id, transit, position, _crew))| {
            let roles = crate::simulation::config::ship_class(&id.class)
                .map(|c| c.crew_roles)
                .unwrap_or(&[]);
            CrewCtx {
                entity: e,
                roles,
                in_transit: transit.transit.is_some(),
                docked: position.docked_at.is_some(),
            }
        })
        .collect();

    for ctx in contexts {
        // LOD gate — skipped_ticks scales the crew rates so a ship that
        // fires every 10 real ticks still ages its hunger/fatigue by the
        // right amount when it does fire.
        let skipped = match active.get(&ctx.entity).copied() {
            Some(n) => n,
            None => continue,
        };
        let effective_scale = tick_scale * skipped as f32;

        // Read-mutate ShipCrew + ShipEconomy + ShipCargo via query_one.
        let mut q = match world.query_one::<(&mut ShipCrew, &mut ShipEconomy, &mut ShipCargo)>(
            ctx.entity,
        ) {
            Ok(q) => q,
            Err(_) => continue,
        };
        let (crew, economy, cargo) = match q.get() {
            Some(t) => t,
            None => continue,
        };

        // --- 1. Decay ---
        // While docked, the station provides food service and off-shift
        // rotation for the crew. Recovery rates are deliberately much
        // higher than in-transit drain (5× hunger, ~12× fatigue) so a
        // short visit clears most of the deficit — otherwise a ship
        // that's spent 200 ticks in transit can only recover a tiny
        // fraction during a brief dock dwell, cascades into morale
        // crisis, and the planner locks it into `rest_crew` for the
        // next N replans instead of accepting contracts.
        const CREW_HUNGER_DOCKED_RECOVERY: f32 = 5.0;
        const CREW_FATIGUE_DOCKED_RECOVERY: f32 = 5.0;
        let hunger_delta = if ctx.docked {
            -CREW_HUNGER_DOCKED_RECOVERY * effective_scale
        } else {
            CREW_HUNGER_RATE_BASE * effective_scale
        };
        crew.hunger = (crew.hunger + hunger_delta).clamp(0.0, 100.0);
        let fatigue_delta = match crew.current_task {
            CrewTask::Resting => CREW_FATIGUE_RATE_REST_BASE * effective_scale,
            CrewTask::Idle if !ctx.in_transit => -1.0 * effective_scale,
            _ if ctx.docked => -CREW_FATIGUE_DOCKED_RECOVERY * effective_scale,
            _ => CREW_FATIGUE_RATE_ACTIVE_BASE * effective_scale,
        };
        crew.fatigue = (crew.fatigue + fatigue_delta).clamp(0.0, 100.0);

        // --- 2. Morale check (every 5×mult ticks) ---
        if morale_check_interval > 0 && tick % morale_check_interval == 0 {
            // Hunger / fatigue penalties only apply OFF-STATION. A docked
            // ship's crew can eat and rotate shifts, so the signal to
            // the morale system is "they're coping"; the penalties would
            // otherwise keep firing even while the crew is actively
            // recovering, which stalls climb-out of rest_crew.
            let penalty: f32 = if ctx.docked {
                if crew.health < 50.0 { -2.0 } else { 0.0 }
            } else if crew.hunger > CREW_HUNGER_MORALE_PENALTY {
                -3.0
            } else if crew.fatigue > CREW_FATIGUE_MORALE_PENALTY {
                -2.0
            } else if crew.health < 50.0 {
                -4.0
            } else {
                0.0
            };
            // Docked + Resting gives the biggest bump. Plain docked also
            // gives meaningful recovery (up from 3) so a ship that
            // arrives drained can climb morale quickly during its
            // DockDwell + Refuel window without needing a full shore
            // leave.
            let recovery: f32 = if ctx.docked && crew.current_task == CrewTask::Resting {
                CREW_MORALE_RECOVERY_RESTING
            } else if ctx.docked {
                CREW_MORALE_RECOVERY_DOCKED
            } else if crew.current_task == CrewTask::Resting {
                // Phase 18k: bump the non-docked Resting recovery from
                // 0.5× docked-baseline to the full docked-baseline so
                // a crew caught on the Rest BT without having actually
                // docked (capacity-full station, broke ship, etc) can
                // still outpace hunger/fatigue penalties. Combined
                // with the Rest-action timeout this breaks the
                // morale-pinned-at-zero death spiral that stalled
                // ~50% of the fleet in Phase 18j smokes.
                CREW_MORALE_RECOVERY_DOCKED
            } else {
                0.0
            };
            let drift = if crew.morale > 50.0 {
                -CREW_MORALE_DECAY_BASE
            } else {
                CREW_MORALE_DECAY_BASE
            };
            crew.morale = (crew.morale + penalty + recovery + drift).clamp(0.0, 100.0);
        }

        // --- 3. Auto-manage needs → set current_task ---
        if crew.hunger > CREW_HUNGER_EAT_THRESHOLD {
            // Try to eat: consume `size × 1` food from cargo if available.
            let needed = crew.size * CREW_FOOD_PER_CREW_PER_MEAL;
            let have = cargo.cargo.get(&Commodity::Food).copied().unwrap_or(0);
            if have >= needed {
                *cargo.cargo.entry(Commodity::Food).or_insert(0) -= needed;
                if cargo.cargo.get(&Commodity::Food).copied().unwrap_or(0) == 0 {
                    cargo.cargo.remove(&Commodity::Food);
                    cargo.cargo_age.remove(&Commodity::Food);
                }
                crew.hunger = (crew.hunger - CREW_HUNGER_MEAL_REDUCTION).max(0.0);
            }
            crew.current_task = CrewTask::Eating;
        } else if crew.fatigue > CREW_FATIGUE_REST_THRESHOLD {
            crew.current_task = CrewTask::Resting;
        } else {
            // Fall-throughs that all pick `primary_task(roles, in_transit)`:
            //  1. Coming out of Eating/Resting — needs satisfied, back to work.
            //  2. Currently Idle — needs a real task.
            //  3. In transit but not yet piloting — UI should show the
            //     transition after refueling/ doching completes.
            let needs_refresh = (matches!(
                crew.current_task,
                CrewTask::Eating | CrewTask::Resting
            ) && crew.hunger < CREW_HUNGER_EAT_THRESHOLD
                && crew.fatigue < CREW_FATIGUE_REST_THRESHOLD)
                || crew.current_task == CrewTask::Idle
                || (ctx.in_transit && crew.current_task != CrewTask::Piloting);
            if needs_refresh {
                crew.current_task = primary_task(ctx.roles, ctx.in_transit);
            }
        }

        // --- 4. Pay wages (every 50×mult ticks) ---
        if wage_interval > 0 && tick % wage_interval == 0 && crew.size > 0 {
            let owed = CREW_WAGE_PER_HEAD * crew.size as i64;
            if economy.credits >= owed {
                economy.credits -= owed;
                crew.wages_credits = crew.wages_credits.saturating_add(owed);
            } else {
                crew.morale = (crew.morale - CREW_WAGE_UNPAID_MORALE_DROP).max(0.0);
            }
        }

        // --- 5. Push efficiency back to economy for trade math ---
        economy.efficiency = crew.efficiency();
        crew.dirty = true;
    }
}

/// Primary task derived from crew roles. If the ship is in transit and
/// there's a pilot on board, piloting overrides role-priority so Godot
/// UI shows "piloting" instead of "trading" while underway.
fn primary_task(roles: &[&str], in_transit: bool) -> CrewTask {
    let has_pilot = roles.contains(&"pilot");
    let has_engineer = roles.contains(&"engineer");
    let has_trader = roles.contains(&"trader");
    if in_transit {
        if has_pilot {
            return CrewTask::Piloting;
        }
        if has_engineer {
            return CrewTask::Engineering;
        }
        if has_trader {
            return CrewTask::Trading;
        }
        return CrewTask::Idle;
    }
    // Docked / stationary: the pilot isn't flying. Whoever runs the
    // station-side work gets the task.
    if has_trader {
        return CrewTask::Trading;
    }
    if has_engineer {
        return CrewTask::Engineering;
    }
    CrewTask::Idle
}

/// Pass 1: advance transit clocks, interpolate position, consume fuel.
fn advance_transits(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    use crate::agents::facility::{
        facility_offset_position, FacilityIdentity, FacilityLocation, FacilityOperations,
    };

    // Snapshot body positions for location→position lookups.
    let body_positions: std::collections::HashMap<i64, (f32, f32)> = world
        .query::<(
            &crate::agents::celestial_body::BodyIdentity,
            &crate::agents::celestial_body::BodyOrbit,
        )>()
        .iter()
        .map(|(_e, (id, orbit))| (id.db_id, orbit.universe_position()))
        .collect();

    // Pick one "primary" facility id per location — the highest-capacity
    // dockable facility there. Ships aim at this facility's offset
    // position so they visually arrive at the station they'll actually
    // try to dock at (matches the server-side `primary_dock_at_location`
    // heuristic). The snapshot layer uses the same
    // `facility_offset_position` function so ship and station agree on
    // where the "dock" is.
    //
    // Pre-18M this picked by hecs iteration order, which at co-located
    // clusters (earth-station has 5 facilities) would sometimes land
    // on the farm or the refinery — ships visibly drifted to
    // "Terra Hydroponics" even when the contract destination was the
    // main station.
    let mut primary_facility_by_location: std::collections::HashMap<String, (String, u32)> =
        std::collections::HashMap::new();
    for (_e, (fac_id, fac_loc, ops)) in world
        .query::<(&FacilityIdentity, &FacilityLocation, &FacilityOperations)>()
        .iter()
    {
        let cap = ops.docking_capacity;
        if cap == 0 {
            continue;
        }
        let entry = primary_facility_by_location
            .entry(fac_loc.location_name.clone())
            .or_insert_with(|| (fac_id.id.clone(), cap));
        if cap > entry.1 {
            *entry = (fac_id.id.clone(), cap);
        }
    }

    let location_to_pos = |loc: &str| -> Option<(f32, f32)> {
        let info = registry.locations.get(loc)?;
        let body_pos = body_positions.get(&info.celestial_body_id).copied()?;
        // If there's a facility at this location, target its offset position
        // (where the client renders the station). Otherwise fall back to
        // body center (locations with no facility still need a position).
        if let Some((fac_id, _)) = primary_facility_by_location.get(loc) {
            Some(facility_offset_position(body_pos, fac_id))
        } else {
            Some(body_pos)
        }
    };

    for (entity, (position, transit, fuel, memory, lifecycle)) in world
        .query_mut::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipFuel,
            &mut ShipMemory,
            &mut ShipLifecycle,
        )>()
    {
        // LOD gate: skip ships whose divisor cursor hasn't fired this
        // round. Ships that do fire scale their fuel burn by skipped
        // ticks so total consumption over wall-clock is preserved.
        let skipped = match active.get(&entity).copied() {
            Some(n) => n,
            None => continue,
        };
        let effective_scale = tick_scale * skipped as f32;
        if let Some(mut t) = transit.transit.clone() {
            // Lazily snapshot the departure world position for legacy rows
            // (pre-Phase-18 transits persisted without it).
            if t.departure_position.is_none() {
                t.departure_position = Some(position.position);
            }

            // Ships drive themselves. Each tick the ship moves `velocity`
            // world-units directly toward its destination's *current* world
            // position. No rails, no precomputed tick budget. Total travel
            // time is emergent: distance-to-target divided by velocity,
            // recomputed every tick. This means a ship chasing a body
            // that's orbiting away naturally takes longer; a ship cutting
            // across to a closer body arrives sooner. It also means the
            // visual trail follows wherever the ship is actually going,
            // which is what you'd want when we later add combat / evasion
            // / fleeing — the ship just has a waypoint, not a rail.
            let target = match location_to_pos(&t.to) {
                Some(p) => p,
                None => {
                    transit.transit = Some(t);
                    continue;
                }
            };
            let dx = target.0 - position.position.0;
            let dy = target.1 - position.position.1;
            let dist = (dx * dx + dy * dy).sqrt();

            let velocity = SHIP_BASE_VELOCITY * fuel.speed_modifier * effective_scale;
            // Cap the per-tick step so a ship LOD'd heavily (large
            // `skipped`) doesn't teleport past its destination.
            let step = velocity.min(dist);

            if dist <= velocity.max(SHIP_ARRIVAL_THRESHOLD) {
                // Arrive.
                position.location_name = Some(t.to.clone());
                position.docked_at = None;
                position.position = target;
                transit.transit = None;
                if !memory.visited.contains(&t.to) {
                    memory.visited.push(t.to.clone());
                }
                lifecycle.dirty = true;
            } else {
                let norm = if dist > 0.0 { step / dist } else { 0.0 };
                position.position = (
                    position.position.0 + dx * norm,
                    position.position.1 + dy * norm,
                );
                // Initial total is set from the departure-time Euclidean
                // distance, used for progress fraction display. It never
                // changes — ongoing distance to target is dist, which
                // may exceed the original if a moving destination pulls
                // away, but the progress bar clamps.
                if t.distance_total <= 0.0 {
                    t.distance_total = dist + (step * 0.5).max(0.0001);
                }
                t.distance_travelled =
                    (t.distance_total - dist).clamp(0.0, t.distance_total);

                let consumption = fuel.fuel_consumption_rate * effective_scale;
                fuel.fuel = (fuel.fuel - consumption).max(0.0);

                // Display ETA (ticks): distance / per-tick step.
                let per_tick =
                    SHIP_BASE_VELOCITY * fuel.speed_modifier * tick_scale.max(0.00001);
                let ticks_left = (dist / per_tick.max(0.00001)) as u64;
                t.arrival_tick = tick.saturating_add(ticks_left);

                transit.transit = Some(t);
            }
        } else if position.location_name.is_some() {
            // Pin the ship to its location's current world coordinates.
            //
            // Covers two cases:
            //   1. Docked (`docked_at = Some`). Godot hides docked
            //      ships in the normal render, but click-to-follow
            //      still reads `position` — without this anchor,
            //      following a docked ship snaps the camera to the
            //      ship's last in-space position (often the approach
            //      point several ticks before docking).
            //   2. Waiting to dock (`docked_at = None` but location
            //      set after transit completion). Previously the ship
            //      arrived at the station's tick-N coordinates and
            //      stayed there while the station continued orbiting
            //      — the player saw "At: haven-station" in the details
            //      panel but the station had drifted out of frame.
            //      Pinning here keeps waiting ships parked alongside
            //      their station.
            if let Some(loc) = position.location_name.clone() {
                if let Some(p) = location_to_pos(&loc) {
                    position.position = p;
                }
            }
        }
    }
    // Placate the linter — tick_multiplier is no longer needed in the
    // velocity-based model but we keep the signature for now.
    let _ = tick_multiplier;
}

/// Base movement rate in world units, scaled by `speed_modifier` and
/// `tick_scale`. Tuned so a courier (speed_mod=1.5) at default
/// world_speed=0.25 covers ~1 AU in about 500 ticks (~60s) and a tanker
/// (0.4) takes ~4× longer. Adjust here if play-feel wants faster ships.
pub const SHIP_BASE_VELOCITY: f32 = 0.05;
/// Arrival snap radius. If the ship would step onto (or inside) this
/// radius around the destination, we call it arrived. Prevents
/// hovering-just-outside when velocity is tiny and the target orbits.
pub const SHIP_ARRIVAL_THRESHOLD: f32 = 0.01;

/// Pass 2: observe local market prices into ship memory.
/// Comms-tier-scaled price observation.
///
/// When a ship is "landed" (position has a location_name — i.e. docked
/// or in-station space, not mid-transit), its comms module determines
/// how far the local-station data mesh reaches:
///
/// - **tier 1 (default)**: same celestial body — stations orbiting
///   the same planet/moon share a comms pool.
/// - **tier 2**: the full star system — system-wide relay network.
/// - **tier 3+**: system + gate-adjacent neighbor systems.
///
/// This is the information-access axis that lets tier-1 ships still
/// participate in contracts (prices for their immediate body) while
/// making comms upgrades meaningfully scale visibility. Cross-system
/// contract gating still applies separately via sensor range.
///
/// All observations land at `tick = current tick` — we don't model
/// relay lag here. If we ever add staleness-based confidence in
/// planning, PriceMemory.tick is the hook (currently unused by
/// planners beyond "is this entry present at all").
fn observe_prices(
    world: &mut hecs::World,
    tick: u64,
    active: &ShipLodGate,
    gate_pairs: &StdHashMap<String, String>,
    registry: &WorldRegistry,
) {
    use crate::agents::celestial_body::BodyIdentity;
    use crate::agents::facility::{FacilityIdentity, FacilityLocation};

    // market prices indexed by location
    let market_prices: std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, f32>,
    > = world
        .query::<(
            &crate::agents::market::MarketIdentity,
            &crate::agents::market::MarketPricing,
        )>()
        .iter()
        .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.prices.clone()))
        .collect();

    // location -> body_id (the string body id like "earth" or "frostheim")
    let loc_to_body: std::collections::HashMap<String, String> = world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .map(|(_, (id, loc))| (loc.location_name.clone(), id.body_id.clone()))
        .collect();

    // body_id -> locations on that body
    let mut body_to_locs: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for (loc, body) in &loc_to_body {
        body_to_locs
            .entry(body.clone())
            .or_default()
            .push(loc.clone());
    }

    // location -> system name (via body -> system via registry)
    let body_db_to_system: std::collections::HashMap<i64, String> = world
        .query::<&BodyIdentity>()
        .iter()
        .map(|(_, id)| (id.db_id, id.system_name.clone()))
        .collect();
    let location_to_system: std::collections::HashMap<String, String> = registry
        .locations
        .iter()
        .filter_map(|(name, info)| {
            let sys = body_db_to_system.get(&info.celestial_body_id)?;
            Some((name.clone(), sys.clone()))
        })
        .collect();

    // system -> locations in system
    let mut system_to_locs: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for (loc, sys) in &location_to_system {
        system_to_locs
            .entry(sys.clone())
            .or_default()
            .push(loc.clone());
    }

    // system -> set of gate-adjacent neighbor systems
    let mut system_neighbors: std::collections::HashMap<
        String,
        std::collections::HashSet<String>,
    > = std::collections::HashMap::new();
    for (a_loc, b_loc) in gate_pairs {
        if let (Some(a_sys), Some(b_sys)) = (
            location_to_system.get(a_loc),
            location_to_system.get(b_loc),
        ) {
            if a_sys != b_sys {
                system_neighbors
                    .entry(a_sys.clone())
                    .or_default()
                    .insert(b_sys.clone());
                system_neighbors
                    .entry(b_sys.clone())
                    .or_default()
                    .insert(a_sys.clone());
            }
        }
    }

    for (e, (position, fitting, memory)) in
        world.query_mut::<(&ShipPosition, &ShipFitting, &mut ShipMemory)>()
    {
        if !active.contains_key(&e) {
            continue;
        }
        let Some(loc) = position.location_name.as_ref() else {
            continue;
        };

        // Read the comms tier from the fitted module. Default to 1 if
        // the slug isn't in the catalog (shouldn't happen — new_default
        // fills every slot).
        let comms_slug = fitting.slots[crate::modules::Slot::Comms.index()];
        let comms_tier = comms_slug
            .and_then(crate::modules::get)
            .map(|m| m.tier)
            .unwrap_or(1);

        // Pick the visibility set based on tier.
        let mut visible: std::collections::HashSet<&str> =
            std::collections::HashSet::new();

        // Always include the ship's own location (covers edge cases
        // where loc isn't on a body, e.g. free-space placeholders).
        visible.insert(loc.as_str());

        // Tier 1: same body.
        if let Some(body) = loc_to_body.get(loc) {
            if let Some(locs) = body_to_locs.get(body) {
                for l in locs {
                    visible.insert(l.as_str());
                }
            }
        }

        if comms_tier >= 2 {
            // Tier 2: whole system.
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(locs) = system_to_locs.get(sys) {
                    for l in locs {
                        visible.insert(l.as_str());
                    }
                }
            }
        }

        if comms_tier >= 3 {
            // Tier 3+: neighbor systems (one gate hop). A future tier
            // bump can walk `system_neighbors` transitively for 2-hop
            // reach; not needed yet.
            if let Some(sys) = location_to_system.get(loc) {
                if let Some(neighbors) = system_neighbors.get(sys) {
                    for n in neighbors {
                        if let Some(locs) = system_to_locs.get(n) {
                            for l in locs {
                                visible.insert(l.as_str());
                            }
                        }
                    }
                }
            }
        }

        for v_loc in visible {
            if let Some(prices) = market_prices.get(v_loc) {
                let entry = memory.price_knowledge.entry(v_loc.to_string()).or_default();
                for (&commodity, &price) in prices {
                    entry.insert(commodity, PriceMemory { price, tick });
                }
            }
        }
    }
}

/// Find the best profitable trade route from memory.
/// Result of a successful trade-run plan — parallel shape to
/// [`ContractCandidate`] so `plan_goal` can score the two options
/// against each other via the ship's personality. Phase 18i.
pub struct TradeRunCandidate {
    pub profit: i64,
    pub bt: BtNode<ShipAction>,
    /// Raw trade-run params so callers can re-synthesise a combined
    /// trade_run+retrofit BT without re-computing `best_trade_route`.
    pub buy_loc: String,
    pub sell_loc: String,
    pub commodity: Commodity,
}

/// Try to build a trade_run BT + estimate its profit. Returns `None`
/// when no margin-positive route exists in the ship's price memory.
#[allow(clippy::too_many_arguments)]
fn try_plan_trade_run(
    at_loc: &str,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    current_tick: u64,
    fuel_bucket: u8,
) -> Option<TradeRunCandidate> {
    let (commodity, buy_loc, sell_loc, _margin) = best_trade_route(memory, current_tick)?;
    let buy_price = memory
        .price_knowledge
        .get(&buy_loc)
        .and_then(|m| m.get(&commodity))
        .map(|p| p.price)
        .unwrap_or(1.0);
    let sell_price = memory
        .price_knowledge
        .get(&sell_loc)
        .and_then(|m| m.get(&commodity))
        .map(|p| p.price)
        .unwrap_or(0.0);
    let profit = ((sell_price - buy_price) * TRADE_QTY_DEFAULT as f32).round() as i64;
    let bt = build_trade_run_bt(
        at_loc,
        &buy_loc,
        &sell_loc,
        commodity,
        fuel_bucket,
        registry,
        gate_pairs,
    );
    Some(TradeRunCandidate {
        profit,
        bt,
        buy_loc,
        sell_loc,
        commodity,
    })
}

/// Phase 19h: median of every remembered price for `commodity`
/// across the ship's `price_knowledge`. Used by `try_plan_contract`
/// as a "reasonable guess" when the ship has never observed the
/// contract's source location directly. Returns None when the ship
/// has no memory of this commodity anywhere — then the planner
/// falls back to skipping the contract.
pub fn median_known_price(memory: &ShipMemory, commodity: Commodity) -> Option<f32> {
    let mut prices: Vec<f32> = memory
        .price_knowledge
        .values()
        .filter_map(|m| m.get(&commodity).map(|p| p.price))
        .collect();
    if prices.is_empty() {
        return None;
    }
    prices.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mid = prices.len() / 2;
    Some(prices[mid])
}

pub fn best_trade_route(
    memory: &ShipMemory,
    current_tick: u64,
) -> Option<(Commodity, String, String, f32)> {
    let mut best: Option<(Commodity, String, String, f32)> = None;
    let locs: Vec<_> = memory.price_knowledge.iter().collect();
    for (i, (loc_a, prices_a)) in locs.iter().enumerate() {
        for (loc_b, prices_b) in locs.iter().skip(i + 1) {
            for (commodity, pa) in prices_a.iter() {
                if let Some(pb) = prices_b.get(commodity) {
                    let (buy, sell, lo, hi) = if pa.price < pb.price {
                        ((*loc_a).clone(), (*loc_b).clone(), pa.price, pb.price)
                    } else {
                        ((*loc_b).clone(), (*loc_a).clone(), pb.price, pa.price)
                    };
                    // Bundle 1.2: freshness decay — discount routes
                    // whose endpoint prices are stale. The route is
                    // only as fresh as the older of its two
                    // observations, so use the minimum of the two
                    // weights.
                    let freshness = price_freshness_weight(pa.tick, current_tick)
                        .min(price_freshness_weight(pb.tick, current_tick));
                    let raw_margin = (hi - lo) / lo.max(1.0) * freshness;
                    // Phase 20: discount the margin when this ship's
                    // actual history on (buy → sell, commodity)
                    // underperforms what the current prices project.
                    // After 3 attempts we trust the learned average;
                    // if it's < 50% of the projected per-unit gap we
                    // apply a strong (0.3×) penalty so the ship drifts
                    // toward less-saturated routes. Ships with no
                    // history keep the full raw margin — nothing
                    // penalises an untried route.
                    let expected_per_unit = hi - lo;
                    let learned_mult = memory
                        .route_performance
                        .get(&(buy.clone(), sell.clone(), *commodity))
                        .and_then(|stats| {
                            if stats.attempts < 3 {
                                return None;
                            }
                            let avg = stats.avg_profit_per_unit();
                            if avg < expected_per_unit * 0.5 {
                                Some(0.3_f32)
                            } else {
                                Some(1.0_f32)
                            }
                        })
                        .unwrap_or(1.0);
                    let margin = raw_margin * learned_mult;
                    if margin > MIN_TRADE_MARGIN && best.as_ref().is_none_or(|b| margin > b.3) {
                        best = Some((*commodity, buy, sell, margin));
                    }
                }
            }
        }
    }
    best
}

/// Pass 3: decide + act on each ship.
#[allow(clippy::too_many_arguments)]
fn decide_and_act(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    contracts: &crate::economy::contracts::ContractBoard,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_multiplier: u32,
    active: &ShipLodGate,
) {
    let config = crate::simulation::config::TickConfig {
        ticks_per_second: 8,
        world_speed: if tick_multiplier == 0 { 0.25 } else { 8.0 / tick_multiplier as f32 },
    };

    // Phase 18f: one location → system name index, used by
    // - shipyard inventory tagging (retrofit proximity)
    // - cross-system contract gating in try_plan_contract
    let location_to_system: std::collections::HashMap<String, String> = {
        use crate::agents::celestial_body::BodyIdentity;
        let body_db_to_system: std::collections::HashMap<i64, String> = world
            .query::<&BodyIdentity>()
            .iter()
            .map(|(_, id)| (id.db_id, id.system_name.clone()))
            .collect();
        registry
            .locations
            .iter()
            .filter_map(|(name, info)| {
                let sys = body_db_to_system.get(&info.celestial_body_id)?;
                Some((name.clone(), sys.clone()))
            })
            .collect()
    };

    // Phase 18L: per-location dock congestion snapshot.
    // `(total_capacity, total_docked_count)` summed across every
    // non-gate facility at the location. Used by the congestion-
    // aware rest planner so ships with low morale don't route to
    // a fully-saturated station when a nearby one has space.
    //
    // Read-only; built once per call. Gates are excluded (they're
    // not meant to host resting crews).
    let dock_congestion: std::collections::HashMap<String, (u32, u32)> = {
        use crate::agents::facility::{
            FacilityIdentity, FacilityLocation, FacilityOperations, FacilityStorage,
        };
        let mut out: std::collections::HashMap<String, (u32, u32)> =
            std::collections::HashMap::new();
        for (_e, (id, loc, ops, storage)) in world
            .query::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
            )>()
            .iter()
        {
            if id.facility_type == "gate" || ops.docking_capacity == 0 {
                continue;
            }
            let entry = out.entry(loc.location_name.clone()).or_insert((0, 0));
            entry.0 = entry.0.saturating_add(ops.docking_capacity);
            entry.1 = entry.1.saturating_add(storage.docked_ships.len() as u32);
        }
        out
    };

    // Phase 18d: snapshot shipyard inventories once per call so per-ship
    // retrofit planning doesn't re-query hecs. Each entry is (location,
    // system_id, slug → qty). Skipping abandoned shipyards matches the
    // existing "abandoned facilities don't service ships" pattern. The
    // system tag lets `find_retrofit_opportunity` prefer same-system
    // yards so Tau Ceti ships don't fly across gates for a tier-2
    // engine when their local Anvil yard has one in stock.
    let shipyard_inventory: ShipyardInventorySnapshot = {
        use crate::agents::facility::{
            FacilityIdentity, FacilityLifecycle, FacilityLocation, ModuleStock,
        };
        world
            .query::<(&FacilityIdentity, &FacilityLocation, &FacilityLifecycle, &ModuleStock)>()
            .iter()
            .filter(|(_, (id, _, life, _))| id.facility_type == "shipyard" && !life.abandoned)
            .map(|(_, (_, loc, _, stock))| {
                let system = location_to_system
                    .get(&loc.location_name)
                    .cloned()
                    .unwrap_or_default();
                (loc.location_name.clone(), system, stock.stock.clone())
            })
            .collect()
    };

    let entities: Vec<hecs::Entity> = world
        .query::<&ShipIdentity>()
        .iter()
        .map(|(e, _)| e)
        .collect();

    for entity in entities {
        // LOD gate — LOD'd-out ships don't replan or execute BT steps
        // this round. They'll pick back up on their next fire.
        if !active.contains_key(&entity) {
            continue;
        }

        // Fetch ship's string id (used for contract acceptance)
        let ship_id: String = match world.get::<&ShipIdentity>(entity) {
            Ok(id) => id.id.clone(),
            Err(_) => continue,
        };

        // Snapshot crew state before the main mut borrow (needed for the planner).
        let crew_snapshot: Option<ShipCrew> = world
            .get::<&ShipCrew>(entity)
            .ok()
            .map(|c| (*c).clone());

        // Phase 18d: compute a retrofit opportunity before the main mut
        // borrow. Requires a banked retrofit point AND the usual
        // fitting + credits + stock gates. None if any check fails —
        // the ship will plan normally.
        let retrofit_plan: Option<RetrofitPlan> = (|| {
            let prog = world.get::<&ShipProgression>(entity).ok()?;
            if prog.retrofit_points == 0 {
                return None;
            }
            let fitting = world.get::<&ShipFitting>(entity).ok()?;
            let economy = world.get::<&ShipEconomy>(entity).ok()?;
            let position = world.get::<&ShipPosition>(entity).ok()?;
            let ship_location = position.location_name.clone().unwrap_or_default();
            let ship_system = position.system_id.clone();
            find_retrofit_opportunity(
                &fitting,
                &shipyard_inventory,
                economy.credits,
                &ship_location,
                &ship_system,
            )
        })();

        // Phase 18f: sensor range determines whether the contract
        // planner can see cross-system contracts. Read before the
        // main mut borrow so plan_goal doesn't need mutable access
        // to the fitting. Default to 0.0 for pre-18f ships (they'll
        // be treated as myopic and skip cross-system contracts).
        let sensor_range_au: f32 = world
            .get::<&ShipFitting>(entity)
            .map(|f| f.derived.sensor_range_au)
            .unwrap_or(0.0);

        let mut q = match world.query_one::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipCargo,
            &mut ShipFuel,
            &mut ShipEconomy,
            &mut ShipAI,
            &mut ShipMemory,
            &mut ShipLifecycle,
            &mut ShipCrew,
        )>(entity) {
            Ok(q) => q,
            Err(_) => continue,
        };
        let (position, transit, cargo, fuel, economy, ai, memory, lifecycle, crew) = match q.get() {
            Some(t) => t,
            None => continue,
        };

        if transit.transit.is_some() {
            // Keep `current_goal` as whatever the plan picked (e.g.
            // "fulfill_delivery") so the UI can show what the ship is
            // actually doing mid-flight. The BT's Travel node returns
            // Running, so we don't re-tick the BT here.
            continue;
        }

        // Sanity-clean stale active_contract_id before planning.
        // Covers three cases:
        //   1. The contract finalised (Paid / Expired) but the Deliver
        //      action never ran (BT ended before reaching it).
        //   2. A speculative-accept race: the ship set its id locally
        //      but another ship won the AcceptContract apply, so the
        //      contract's fulfiller_id isn't us.
        //   3. **Phase 19h**: ghost contract — status=Accepted, we're
        //      the fulfiller, but `current_bt = None` (BT finished
        //      early via Success without reaching Deliver). Without
        //      this branch the ship sits idle holding a contract
        //      nobody else can take. Release + clear so a re-planner
        //      picks it up fresh next cycle.
        //
        // In cases 1 + 2 we just clear locally (the contract is either
        // gone or not ours to release). Case 3 emits a
        // `ReleaseContract` so the board moves Accepted → Posted and
        // another ship can accept it.
        if let Some(cid) = economy.active_contract_id.clone() {
            enum StaleKind { Drop, Release, Keep }
            let kind = match contracts.get(&cid) {
                None => StaleKind::Drop,
                Some(c) => {
                    use crate::economy::contracts::ContractStatus;
                    let finalized = matches!(
                        c.status,
                        ContractStatus::Paid | ContractStatus::Expired
                    );
                    let not_ours = c.fulfiller_id.as_deref() != Some(ship_id.as_str());
                    let ghost = matches!(c.status, ContractStatus::Accepted)
                        && !not_ours
                        && ai.current_bt.is_none();
                    if finalized || not_ours {
                        StaleKind::Drop
                    } else if ghost {
                        StaleKind::Release
                    } else {
                        StaleKind::Keep
                    }
                }
            };
            match kind {
                StaleKind::Drop => {
                    economy.active_contract_id = None;
                    ai.current_bt = None;
                }
                StaleKind::Release => {
                    economy.active_contract_id = None;
                    ai.current_bt = None;
                    commands.push(SimCommand::ReleaseContract {
                        ship_id: ship_id.clone(),
                        contract_id: cid,
                    });
                }
                StaleKind::Keep => {}
            }
        }

        let needs_plan = ai.current_bt.is_none();
        // Bundle 2.2: mid-action replan check. If the current goal is
        // replan-eligible, we've been committed for the minimum dwell,
        // and it's a check-interval tick, re-run the planner and
        // switch if the new top candidate clears the
        // REPLAN_SCORE_RATIO bar. Prevents ships from locking into
        // stale trade runs when a juicy subsidy lands mid-flight.
        let elapsed_since_plan = tick.saturating_sub(ai.last_plan_tick);
        let replan_check_due = !needs_plan
            && is_replan_eligible(&ai.current_goal)
            && elapsed_since_plan >= REPLAN_MIN_COMMIT_TICKS
            && tick % REPLAN_CHECK_INTERVAL_TICKS == 0;

        if needs_plan || replan_check_due {
            let candidate = plan_goal(
                position,
                cargo,
                fuel,
                economy,
                memory,
                crew_snapshot.as_ref(),
                contracts,
                &ship_id,
                registry,
                gate_pairs,
                retrofit_plan.as_ref(),
                sensor_range_au,
                &location_to_system,
                &ai.personality,
                &dock_congestion,
                lifecycle.idle_ticks,
                tick,
            );
            let accept = needs_plan
                || candidate.score >= ai.current_goal_score * REPLAN_SCORE_RATIO;
            if accept {
                // Release any active contract we were committed to
                // before swapping plans — otherwise the ship can end
                // up with an active_contract_id that no current BT is
                // working. ReleaseContract apply phase tolerates
                // stale ids safely.
                if replan_check_due {
                    if let Some(cid) = economy.active_contract_id.take() {
                        commands.push(SimCommand::ReleaseContract {
                            ship_id: ship_id.clone(),
                            contract_id: cid,
                        });
                    }
                }
                ai.current_goal = candidate.name.into();
                ai.current_goal_score = candidate.score;
                ai.current_bt = Some(candidate.bt);
                ai.last_plan_tick = tick;
            }
        }

        // Phase 19h: track how long the ship has been in an idle-ish
        // state so the explore escalation fires at the right time.
        // Any goal starting with "idle" counts; anything else resets.
        // Using starts_with lets future variants ("idle_seek_station")
        // share the counter without manual enumeration.
        if ai.current_goal.starts_with("idle") {
            lifecycle.idle_ticks = lifecycle.idle_ticks.saturating_add(1);
        } else {
            lifecycle.idle_ticks = 0;
        }

        // --- Strike accumulation (adaptive-fleet retirement, Phase 19-tail) ---
        //
        // Evaluated on a slow cadence so a ship that briefly dips below
        // the credits floor doesn't take a strike on every tick. Strikes
        // reset when the ship recovers; 3 of either kind triggers
        // decommission via SimCommand::DecommissionShip (engine emits the
        // retirement row + queues a replacement spawn).
        let strike_interval = STRIKE_CHECK_INTERVAL_BASE * tick_multiplier as u64;
        if strike_interval > 0 && tick % strike_interval == 0 {
            // Broke strike: nothing to sell, no one paying us, no cash.
            let cargo_empty = cargo.used() == 0;
            let no_contract = economy.active_contract_id.is_none();
            if economy.credits < BROKE_CREDITS_THRESHOLD && cargo_empty && no_contract {
                lifecycle.broke_strikes = lifecycle.broke_strikes.saturating_add(1);
            } else if economy.credits >= BROKE_RECOVERY_THRESHOLD {
                lifecycle.broke_strikes = 0;
            }
            // Hoard strike: lots of credits, long idle window. Reset
            // happens on DeliverContract apply (see engine.rs).
            if economy.credits > HOARD_CREDITS_THRESHOLD
                && lifecycle.idle_ticks > HOARD_IDLE_THRESHOLD
            {
                lifecycle.hoard_strikes = lifecycle.hoard_strikes.saturating_add(1);
            }

            if lifecycle.broke_strikes >= MAX_STRIKES {
                commands.push(SimCommand::DecommissionShip {
                    ship: entity,
                    reason: "bankruptcy",
                });
            } else if lifecycle.hoard_strikes >= MAX_STRIKES {
                commands.push(SimCommand::DecommissionShip {
                    ship: entity,
                    reason: "stagnation",
                });
            }
        }

        // --- Execute one BT step ---
        if let Some(mut bt) = ai.current_bt.take() {
            let mut bb = Blackboard::new();
            let status = {
                let ship_id_ref = &ship_id;
                let mut dispatch = |action: &ShipAction, bb: &mut Blackboard| -> BtStatus {
                    execute_ship_action(
                        action,
                        entity,
                        ship_id_ref,
                        crew,
                        position,
                        transit,
                        cargo,
                        fuel,
                        economy,
                        memory,
                        registry,
                        commands,
                        tick,
                        &config,
                        bb,
                    )
                };
                bt.tick(&mut bb, &mut dispatch)
            };

            // Bundle 1.4: drift personality in response to BT events
            // surfaced via the blackboard. Only `rest_timed_out`
            // today; delivery-success drift happens in the engine
            // apply phase (direct world access on DeliverContract).
            if bb.get_bool("rest_timed_out") {
                ai.personality
                    .drift(crate::ai::personality::Axis::Safety, DRIFT_REST_TIMEOUT_SAFETY);
            }

            match status {
                BtStatus::Running => ai.current_bt = Some(bt),
                BtStatus::Success => {
                    // Plan done — clear. Next tick replans.
                    ai.current_bt = None;
                }
                BtStatus::Failure => {
                    ai.current_bt = None;
                    // If the failing plan was a contract run, release
                    // the contract back to the board so another ship
                    // can pick it up (and we can re-plan freely). The
                    // guarded `ReleaseContract` apply is a no-op if
                    // we aren't actually the named fulfiller — which
                    // protects against losing-speculative-accept
                    // ships yanking contracts the winning ship is
                    // still working.
                    if let Some(cid) = economy.active_contract_id.take() {
                        commands.push(SimCommand::ReleaseContract {
                            ship_id: ship_id.clone(),
                            contract_id: cid,
                        });
                    }
                }
            }
        }

        lifecycle.dirty = true;
    }
}

/// Bundle 2.1: tier weights for the unified utility scorer. Each
/// candidate goal's raw signal is multiplied by the matching tier
/// weight, so biological needs (rest, refuel) dominate when urgency
/// is high, housekeeping (sell_cargo, retrofit) beats strategic
/// when present, and strategic goals (contracts, trades, explore)
/// compete among themselves on their natural log-profit scale. The
/// waterfall is *emergent* rather than hardcoded — a 1% fuel reading
/// produces a score so high no trade can out-bid it, but a 40% fuel
/// reading leaves room for contracts to win if they're profitable.
pub const TIER_BIO_WEIGHT: f32 = 100.0;
pub const TIER_HOUSEKEEPING_WEIGHT: f32 = 40.0;
pub const TIER_STRATEGIC_WEIGHT: f32 = 3.0;
pub const TIER_EXPLORE_WEIGHT: f32 = 6.0;
pub const TIER_IDLE_FLOOR: f32 = 0.5;

/// Onset threshold for the refuel urgency curve. Below this the ship
/// increasingly prioritises refuel; above it, the refuel score goes
/// to 0 (no candidate). Set higher than the former `FUEL_CRITICAL_FRACTION`
/// so the scorer sees the pressure building earlier but only actually
/// dominates when fuel is genuinely low.
pub const FUEL_URGENCY_ONSET: f32 = 0.45;

/// Produced by the per-tick planner for each goal a ship could pursue
/// this tick. The max-scored candidate wins. `score` ≥ 0; 0 means
/// "don't pick this candidate".
#[derive(Debug, Clone)]
pub struct ScoredGoal {
    pub name: &'static str,
    pub score: f32,
    pub bt: BtNode<ShipAction>,
}

/// Bundle 2.2: minimum-commit dwell before a ship may re-plan mid-
/// action. Prevents thrashing when two goals have near-equal scores
/// and the scorer narrowly flips one way then the other.
pub const REPLAN_MIN_COMMIT_TICKS: u64 = 40;

/// Bundle 2.2: cadence for the mid-action replan check. At 8 tps
/// this fires every ~2.5 seconds of wall-clock — often enough to
/// catch a fresh opportunity, rare enough to keep overhead low
/// (a replan check rebuilds candidate BTs, which isn't free).
pub const REPLAN_CHECK_INTERVAL_TICKS: u64 = 20;

/// Bundle 2.2: how much better the best alternative needs to be
/// before we interrupt the current plan. 1.30 = +30% — enough to
/// tell signal from noise in the personality-weighted score.
pub const REPLAN_SCORE_RATIO: f32 = 1.30;

/// Bundle 2.2: which goals may be interrupted mid-execution.
/// Biological needs (rest_crew, refuel) stay committed — the BT
/// self-terminates on recovery anyway, so interrupting mid-action
/// just loses progress. Housekeeping and retrofit are long-horizon
/// investments the ship shouldn't abandon. Strategic + idle goals
/// are fair game.
pub fn is_replan_eligible(goal: &str) -> bool {
    !matches!(
        goal,
        "rest_crew"
            | "refuel"
            | "seek_retrofit"
            | "sell_cargo"
            | "fulfill_delivery_with_retrofit"
            | "trade_run_with_retrofit"
    )
}

/// Planner: pick a goal + build its BT.
///
/// Bundle 2.1 (A): unified utility scoring. Instead of a hardcoded
/// priority cascade, every candidate goal is scored this tick and
/// the highest-scoring one wins. Scale is set by tier weights above
/// so biological needs at high urgency beat anything strategic, but
/// at modest urgency contracts can compete. Ties and edge cases
/// resolve deterministically by candidate order.
///
/// The goal set is:
/// - **rest_crew** — when morale below CREW_REST_TRIGGER
/// - **refuel** — when fuel below FUEL_URGENCY_ONSET
/// - **sell_cargo** — when cargo onboard
/// - **seek_retrofit** — when caller produced a RetrofitPlan
/// - **fulfill_delivery / contract / passenger / courier / crew_mission** —
///   from `try_plan_contract`, log-profit scored with `prefer_goals` bonus
/// - **trade_run** — from `try_plan_trade_run`, same scoring
/// - **explore / idle_seek_station / idle** — from `smart_idle_fallback`
#[allow(clippy::too_many_arguments)]
fn plan_goal(
    position: &ShipPosition,
    cargo: &ShipCargo,
    fuel: &ShipFuel,
    economy: &ShipEconomy,
    memory: &ShipMemory,
    crew: Option<&ShipCrew>,
    contracts: &crate::economy::contracts::ContractBoard,
    ship_id: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    retrofit: Option<&RetrofitPlan>,
    sensor_range_au: f32,
    location_to_system: &StdHashMap<String, String>,
    personality: &crate::ai::personality::Personality,
    dock_congestion: &StdHashMap<String, (u32, u32)>,
    idle_ticks: u32,
    current_tick: u64,
) -> ScoredGoal {
    let at_loc = match &position.location_name {
        Some(l) => l.clone(),
        None => {
            return ScoredGoal {
                name: "idle",
                score: TIER_IDLE_FLOOR,
                bt: BtNode::action(ShipAction::Idle),
            };
        }
    };

    let mut candidates: Vec<ScoredGoal> = Vec::new();
    // Compute the ship's fuel bucket once — passed into every
    // planner BT builder so synthesised plans reason about real
    // fuel state rather than a full-tank assumption.
    let fuel_bucket = crate::ai::planner::fuel_fraction_to_bucket(fuel.fraction());

    // --- Biological tier: rest + refuel ---
    // Urgency is in [0, 1], steepest near 1.0 so a near-crisis
    // reading blows past housekeeping scores. Personality's
    // morale / safety axes scale how strongly a ship reacts.
    if let Some(c) = crew {
        if c.morale < CREW_REST_TRIGGER {
            let urgency = (1.0 - c.morale / CREW_REST_TRIGGER).clamp(0.0, 1.0);
            let score = urgency * personality.morale.max(0.2) * TIER_BIO_WEIGHT;
            // Phase 18L: congestion-aware rest target lookup.
            let target = pick_rest_destination(&at_loc, dock_congestion, location_to_system);
            candidates.push(ScoredGoal {
                name: "rest_crew",
                score,
                bt: build_rest_crew_bt_to(&at_loc, &target, fuel_bucket, registry, gate_pairs),
            });
        }
    }
    if fuel.fraction() < FUEL_URGENCY_ONSET {
        let urgency = (1.0 - fuel.fraction() / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let score = urgency * personality.safety.max(0.2) * TIER_BIO_WEIGHT;
        candidates.push(ScoredGoal {
            name: "refuel",
            score,
            bt: build_refuel_bt(),
        });
    }

    // --- Housekeeping tier: sell_cargo + retrofit ---
    // Strong enough to beat strategic when present (ships unload
    // before chasing new contracts), weak enough that a biological
    // crisis still wins. Cargo-fraction scaling means a ship with
    // only a trickle of cargo can still opt to chase a hot
    // contract instead of selling early.
    if cargo.used() > 0 {
        let frac = cargo.used() as f32 / cargo.capacity.max(1) as f32;
        // Scale starts at ~0.5 even for tiny cargo so a bit of
        // cargo is still a reason to unload; asymptotes to 1.0 as
        // the hold fills.
        let scaled = 0.5 + frac.clamp(0.0, 1.0) * 0.5;
        candidates.push(ScoredGoal {
            name: "sell_cargo",
            score: scaled * personality.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT,
            bt: build_sell_cargo_bt(),
        });
    }
    // 4. Retrofit opportunity (Phase 18d). The caller already checked
    //    retrofit_points > 0 + credits + stock + fitting-tier.
    if let Some(plan) = retrofit {
        // Retrofit is a long-horizon investment: score moderately
        // so it only fires when nothing more urgent exists. The
        // ship's profit axis reflects "I want to grow my business."
        let score = 0.9 * personality.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        candidates.push(ScoredGoal {
            name: "seek_retrofit",
            score,
            bt: build_retrofit_bt(&at_loc, plan, fuel_bucket, registry, gate_pairs),
        });
    }

    // --- Strategic tier: contracts + trade_run ---
    // Log-scaled profit × (1 + prefer_goals bonus) × strategic
    // weight. Archetype `prefer_goals` entries tilt the pick so
    // the fleet fans out instead of every ship running the same
    // waterfall.
    if let Some(c) = try_plan_contract(
        &at_loc,
        cargo,
        economy,
        memory,
        contracts,
        ship_id,
        registry,
        gate_pairs,
        sensor_range_au,
        fuel_bucket,
        location_to_system,
    ) {
        let score = score_strategic(c.profit, c.goal_name, personality);
        // GOAP combined goal: if we have a retrofit plan AND the
        // contract is delivery-class, try to synthesise a single
        // BT that picks up cargo, detours through the shipyard,
        // delivers. When the planner succeeds, register the
        // combined candidate with a small bonus — the ship
        // accomplishes two goals in one trip. Fall through to the
        // plain contract + separate seek_retrofit candidates when
        // the planner bails, so nothing is worse than before.
        if let (Some(rp), Some(dp)) = (retrofit, c.delivery_params.as_ref()) {
            if let Some(combo_bt) = try_build_fulfill_delivery_with_retrofit_planned(
                &at_loc,
                &dp.source,
                &dp.destination,
                dp.commodity,
                dp.quantity,
                &dp.contract_id,
                rp,
                fuel_bucket,
                registry,
                gate_pairs,
            ) {
                // Bonus is small (~20%) — we want combined plans
                // to win when roughly on par, not dominate when
                // delivery alone is clearly better.
                let combo_score = score * 1.20
                    + score_strategic(rp.cost / 5, "seek_retrofit", personality);
                candidates.push(ScoredGoal {
                    name: "fulfill_delivery_with_retrofit",
                    score: combo_score,
                    bt: combo_bt,
                });
            }
        }
        candidates.push(ScoredGoal {
            name: c.goal_name,
            score,
            bt: c.bt,
        });
    }
    if let Some(t) = try_plan_trade_run(&at_loc, memory, registry, gate_pairs, current_tick, fuel_bucket) {
        let score = score_strategic(t.profit, "trade_run", personality);
        // GOAP combined goal: trade_run + retrofit. Same pattern as
        // delivery + retrofit. When the planner folds refit into
        // the trade-run path it wins on two fronts in one trip.
        if let Some(rp) = retrofit {
            if let Some(combo_bt) = try_build_trade_run_with_retrofit_planned(
                &at_loc,
                &t.buy_loc,
                &t.sell_loc,
                t.commodity,
                rp,
                fuel_bucket,
                registry,
                gate_pairs,
            ) {
                let combo_score = score * 1.20
                    + score_strategic(rp.cost / 5, "seek_retrofit", personality);
                candidates.push(ScoredGoal {
                    name: "trade_run_with_retrofit",
                    score: combo_score,
                    bt: combo_bt,
                });
            }
        }
        candidates.push(ScoredGoal {
            name: "trade_run",
            score,
            bt: t.bt,
        });
    }

    // --- Exploration / idle fallback tier ---
    // smart_idle_fallback's ladder (explore → idle_seek_station →
    // plain idle) is always at least a low-score baseline so
    // something is always pickable. Exploration scores a bit
    // higher when the ship's personality actually wants it.
    let (idle_name, idle_bt) = smart_idle_fallback(
        &at_loc,
        position,
        economy,
        fuel,
        memory,
        registry,
        gate_pairs,
        location_to_system,
        personality,
        idle_ticks,
    );
    let idle_score = match idle_name {
        "explore" => personality.exploration.max(0.2) * TIER_EXPLORE_WEIGHT,
        "idle_seek_station" => 0.8 * TIER_EXPLORE_WEIGHT,
        _ => TIER_IDLE_FLOOR,
    };
    if let Some(bt) = idle_bt {
        candidates.push(ScoredGoal {
            name: idle_name,
            score: idle_score,
            bt,
        });
    } else {
        // Shouldn't happen (smart_idle_fallback always returns a BT)
        // but keep a belt-and-braces fallback so we always return
        // something pickable.
        candidates.push(ScoredGoal {
            name: "idle",
            score: TIER_IDLE_FLOOR,
            bt: BtNode::action(ShipAction::Idle),
        });
    }

    // Pick max-score candidate. Ties resolve by earliest-pushed
    // (biological / housekeeping / strategic / idle order above),
    // which matches the Phase-18i waterfall's tie-breaks.
    candidates
        .into_iter()
        .max_by(|a, b| a.score.partial_cmp(&b.score).unwrap_or(std::cmp::Ordering::Equal))
        .expect("idle fallback guarantees at least one candidate")
}

/// Bundle 2.1: shared scoring for the strategic tier (contracts,
/// trade_run). Log-scales profit so a 100k-credit subsidy doesn't
/// automatically swamp a 1.5k courier run, multiplies by
/// `1.0 + prefer_goals[goal]` so archetype bonuses tilt the pick,
/// then by the ship's profit axis and the tier weight.
fn score_strategic(
    profit: i64,
    goal_name: &str,
    personality: &crate::ai::personality::Personality,
) -> f32 {
    if profit <= 0 {
        return 0.0;
    }
    let log_profit = (profit as f32).max(1.0).ln();
    let bonus = personality
        .prefer_goals
        .get(goal_name)
        .copied()
        .unwrap_or(0.0);
    log_profit * (1.0 + bonus) * personality.profit.max(0.3) * TIER_STRATEGIC_WEIGHT
}

/// Phase 19h: smart idle branch. When the contract / trade_run
/// planners both struck out, we pick from a ladder:
///
///   1. **Ship has been idling at a station a while + fuel + credits
///      OK + personality leans adventurous**: pick a neighbour system
///      not in `recent_systems`, build an explore BT that travels to
///      the outbound gate, jumps, travels to a station in the new
///      system, docks, dwells ~5s to catch a posting cycle, undocks.
///      Goal = `"explore"`.
///   2. **At a location without any dockable facility** (weird spawn
///      or gate-only locations): travel to the nearest same-system
///      dockable station. Goal = `"idle_seek_station"`. Gives the
///      ship a chance to observe prices + refuel while resting.
///   3. **Otherwise**: plain Idle — the ship stays where it is. Some
///      captains just want quiet.
#[allow(clippy::too_many_arguments)]
fn smart_idle_fallback(
    at_loc: &str,
    position: &ShipPosition,
    economy: &ShipEconomy,
    fuel: &ShipFuel,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    location_to_system: &StdHashMap<String, String>,
    personality: &crate::ai::personality::Personality,
    idle_ticks: u32,
) -> (&'static str, Option<BtNode<ShipAction>>) {
    let fuel_ok = fuel.fraction() >= EXPLORE_MIN_FUEL_FRACTION;
    let credits_ok = economy.credits >= EXPLORE_MIN_CREDITS;

    // Personality tilts the idle-duration trigger. High `exploration`
    // → leaves sooner; high `safety` → lingers longer; low credits
    // also bias toward desperation.
    let explore_bonus = personality.exploration - personality.safety * 0.5;
    let desperation = if economy.credits < 5000 { 0.3 } else { 0.0 };
    let trigger_scale = (1.0 - explore_bonus - desperation).max(0.25);
    let effective_trigger = (IDLE_EXPLORE_TICKS as f32 * trigger_scale) as u32;

    let should_explore = idle_ticks >= effective_trigger && fuel_ok && credits_ok;

    if should_explore {
        if let Some(bt) =
            try_build_explore_bt(at_loc, memory, registry, gate_pairs, location_to_system)
        {
            return ("explore", Some(bt));
        }
    }

    // Dock-less location? Travel to a same-system station.
    if position.docked_at.is_none() && !has_dockable_here(at_loc, registry) {
        if let Some(station) = pick_same_system_station(at_loc, registry, location_to_system) {
            let mut steps: Vec<BtNode<ShipAction>> = Vec::new();
            for a in route_actions(at_loc, &station, registry, gate_pairs) {
                steps.push(BtNode::action(a));
            }
            steps.push(BtNode::action(ShipAction::Dock));
            steps.push(BtNode::action(ShipAction::DockDwell {
                seconds: EXPLORE_CHECK_BOARD_SECONDS,
            }));
            steps.push(BtNode::action(ShipAction::Undock));
            return ("idle_seek_station", Some(BtNode::sequence(steps)));
        }
    }

    // Default: stay put.
    ("idle", Some(BtNode::action(ShipAction::Idle)))
}

/// Pick an adjacent star system not in `memory.recent_systems` and
/// build the explore BT to reach it. Returns `None` when the ship has
/// no outbound gate or every neighbor is already in the recent-visits
/// set (the rare deep-exploration case — we'll re-plan next cycle).
fn try_build_explore_bt(
    at_loc: &str,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    location_to_system: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    let current_system = location_to_system.get(at_loc)?;

    // Walk this system's gates, find ones whose paired gate lands in
    // a system not currently in the ship's recent-systems window.
    // Fall back to any neighbour if every candidate is on the list
    // (prevents total stall when memory has cycled through the
    // whole connected graph).
    let mut preferred: Vec<(String, String, String)> = Vec::new();
    let mut any: Vec<(String, String, String)> = Vec::new();
    for (src_gate, dst_gate) in gate_pairs {
        let Some(src_sys) = location_to_system.get(src_gate) else {
            continue;
        };
        if src_sys != current_system {
            continue;
        }
        let Some(dst_sys) = location_to_system.get(dst_gate) else {
            continue;
        };
        let entry = (src_gate.clone(), dst_gate.clone(), dst_sys.clone());
        if !memory.recent_systems.iter().any(|s| s == dst_sys) {
            preferred.push(entry.clone());
        }
        any.push(entry);
    }
    let (src_gate, dst_gate, dst_system) = if let Some(p) = preferred.first() {
        p.clone()
    } else {
        any.first()?.clone()
    };

    // Landing target: a dockable station in the destination system
    // (not the gate itself — gates aren't where contracts are). Pick
    // the first station we find; `pick_same_system_station` handles
    // the has-dockable check for us.
    let landing_station = pick_same_system_station(&dst_gate, registry, location_to_system)
        .unwrap_or_else(|| dst_gate.clone());

    let mut steps: Vec<BtNode<ShipAction>> = Vec::new();
    // Travel to the outbound gate.
    for a in route_actions(at_loc, &src_gate, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    // Gate jump.
    steps.push(BtNode::action(ShipAction::GateJump {
        src_gate,
        dest_gate: dst_gate.clone(),
    }));
    // Travel to the landing station + dwell "check the board".
    for a in route_actions(&dst_gate, &landing_station, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell {
        seconds: EXPLORE_CHECK_BOARD_SECONDS,
    }));
    steps.push(BtNode::action(ShipAction::Undock));

    let _ = dst_system; // silence warnings if we later use it for events
    Some(BtNode::sequence(steps))
}

/// Is there a dockable (non-gate, capacity > 0) facility at this
/// location? Used by the idle-at-station logic to decide whether the
/// ship should wander to a real port.
fn has_dockable_here(at_loc: &str, registry: &WorldRegistry) -> bool {
    registry
        .locations
        .contains_key(at_loc)
}

/// Pick any non-gate station in the same star system as `at_loc`.
/// First-match rather than optimised — idle-seeking doesn't need the
/// best pick, just a pick. Skips the caller's current location so
/// the ship actually goes somewhere.
fn pick_same_system_station(
    at_loc: &str,
    registry: &WorldRegistry,
    location_to_system: &StdHashMap<String, String>,
) -> Option<String> {
    let current_system = location_to_system.get(at_loc)?;
    for (name, _info) in registry.locations.iter() {
        if name == at_loc {
            continue;
        }
        if name.contains("gate") {
            // Gates are technically locations but they don't host
            // contracts or markets — bad "chill here" targets.
            continue;
        }
        if let Some(sys) = location_to_system.get(name) {
            if sys == current_system {
                return Some(name.clone());
            }
        }
    }
    None
}

/// Try to find a profitable fulfill plan from the board. Handles both
/// delivery contracts (ship must pre-buy the commodity at source, must
/// profit after cost) and passenger / courier contracts (no buy step —
/// the ship just shuttles between source and destination).
/// Result of a successful contract plan: the personality-facing goal
/// name (matches archetype `prefer_goals` keys), the profit the planner
/// thinks the ship can collect after cost, and the BT to execute.
/// Phase 18i: returned instead of just a BT so `plan_goal` can score it
/// against competing goals (trade_run) via the ship's personality.
pub struct ContractCandidate {
    pub goal_name: &'static str,
    pub profit: i64,
    pub bt: BtNode<ShipAction>,
    /// Raw delivery params when the contract is a delivery-class
    /// kind (Delivery / Subsidy / Construction). Used by `plan_goal`
    /// to re-synthesise a combined delivery+retrofit BT when both
    /// opportunities align. `None` for Passenger / Courier /
    /// CrewMission / other non-delivery variants.
    pub delivery_params: Option<DeliveryParams>,
}

/// Raw delivery parameters for combined-goal BT synthesis. Mirrors
/// the args `build_fulfill_delivery_bt` takes so a caller can build
/// an alternate BT (retrofit-on-route, e.g.) without threading the
/// entire contract board through.
#[derive(Debug, Clone)]
pub struct DeliveryParams {
    pub source: String,
    pub destination: String,
    pub commodity: Commodity,
    pub quantity: u32,
    pub contract_id: String,
}

#[allow(clippy::too_many_arguments)]
fn try_plan_contract(
    at_loc: &str,
    cargo: &ShipCargo,
    economy: &ShipEconomy,
    memory: &ShipMemory,
    contracts: &crate::economy::contracts::ContractBoard,
    _ship_id: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
    sensor_range_au: f32,
    fuel_bucket: u8,
    location_to_system: &StdHashMap<String, String>,
) -> Option<ContractCandidate> {
    use crate::economy::contracts::ContractType;

    // Phase 18f: cross-system contracts are invisible to ships with
    // short-range sensors. A contract counts as cross-system when its
    // source + destination resolve to different star systems; ships
    // below the threshold skip those, simulating "the comms relay
    // just isn't picking up interstellar job boards." Larger hulls
    // (size ≥ 5) ship with tier-2 sensors by default and see them
    // day one; small ships need a sensor retrofit.
    let ship_system = location_to_system.get(at_loc);

    #[derive(Clone)]
    struct Candidate {
        id: String,
        source: String,
        destination: String,
        commodity: Commodity,
        qty: u32,
        payment: i64,
        cost: i64,
        /// Phase 19f: effective profit used for comparison — raw
        /// profit adjusted by a fill-ratio quality multiplier for
        /// delivery kinds. The `profit` passed to the planner's
        /// `score_goal` scoring still uses raw profit, so the
        /// cross-goal (trade_run vs delivery) comparison stays
        /// consistent with the old rules.
        score: i64,
        kind: ContractType,
    }
    let mut best: Option<Candidate> = None;

    for c in contracts.posted_for_ship(&economy.faction_reputation) {
        // Phase 18f: sensor-range gate for cross-system contracts.
        // If the contract's source and destination span different
        // systems (or leave the ship's system) and the ship's
        // sensor range is below the cross-system threshold, skip.
        if sensor_range_au < CROSS_SYSTEM_SENSOR_RANGE_AU {
            let src_sys = location_to_system.get(&c.source_location);
            let dst_sys = location_to_system.get(&c.destination_location);
            let is_cross_system = match (ship_system, src_sys, dst_sys) {
                (Some(ship), Some(src), Some(dst)) => ship != src || src != dst,
                // Missing system data for any of the three means we
                // can't prove same-system — fall back to "visible"
                // rather than blocking everything during startup.
                _ => false,
            };
            if is_cross_system {
                continue;
            }
        }
        // Passenger / courier / crew-mission contracts don't occupy cargo
        // slots — treat them as "hop-around" jobs in the planner.
        let is_passenger = c.contract_type == ContractType::Passenger;
        let is_courier = c.contract_type == ContractType::Courier;
        let is_mission = c.contract_type == ContractType::CrewMission;
        if !is_passenger && !is_mission && c.quantity > cargo.capacity {
            continue;
        }

        let buy_cost: i64 = if is_passenger || is_courier || is_mission {
            // No pre-buy for these kinds. Passenger pickup is implicit;
            // courier's cargo is supplied by the poster; crew missions
            // have no cargo at all — the ship just dwells at the posting
            // station for the mission's duration_ticks and collects pay.
            0
        } else {
            // Prefer the ship's direct memory of the source market.
            // Phase 19h: when memory is missing (comms-tier-limited
            // ships rarely know far-flung markets), fall back to a
            // median across the ship's OTHER remembered markets for
            // this commodity — a heuristic "prices are probably
            // similar" guess. That lets tier-1 comms ships
            // speculatively price cross-system contracts instead of
            // skipping every one. Buy cost is still validated on
            // arrival at the source market, so a bad guess just
            // means the BT might bail on Buy (Failure → release
            // contract). No new state threading required.
            let src_price_known = memory
                .price_knowledge
                .get(&c.source_location)
                .and_then(|m| m.get(&c.commodity))
                .map(|p| p.price);
            let src_price = src_price_known
                .or_else(|| median_known_price(memory, c.commodity));
            match src_price {
                Some(p) => (p * c.quantity as f32) as i64,
                // No memory of this commodity at ANY market → can't
                // even guess. Skip as before.
                None => continue,
            }
        };
        // Rough upper-bound estimate of gate fees along the full route
        // (current → source → destination). Uses default fees; real
        // fees are whatever the gate facility carries. We don't know
        // cargo-at-pickup yet, so approximate with contract quantity.
        let gate_fees = estimate_route_gate_fees(
            &[
                (at_loc, &c.source_location),
                (&c.source_location, &c.destination_location),
            ],
            gate_pairs,
            c.quantity,
        );
        let cost: i64 = buy_cost + gate_fees;
        if cost >= c.payment {
            continue;
        }
        if economy.credits < cost {
            continue;
        }
        let profit = c.payment - cost;

        // Phase 19f: fill-ratio scoring. For delivery contracts, reward
        // runs that make good use of the ship's cargo capacity. A
        // hauler with capacity 2000 picking up a 50-unit delivery
        // wastes 97.5% of the hold — sqrt(0.025) ≈ 0.16, so that
        // delivery scores only ~16% of its raw profit in the planner
        // comparison. Applied only to kinds that actually load cargo.
        let fill_quality: f32 = if matches!(
            c.contract_type,
            ContractType::Delivery | ContractType::Construction
        ) && cargo.capacity > 0
        {
            let ratio = (c.quantity as f32 / cargo.capacity as f32).clamp(0.0, 1.0);
            // sqrt curve: gentle at the top (90% fill → 0.95), steep
            // at the bottom (5% fill → 0.22). Small contracts on big
            // hulls are still takeable, just unattractive compared
            // to better-fitting alternatives.
            ratio.sqrt().max(0.1)
        } else {
            1.0
        };
        let effective_profit: i64 = ((profit as f32) * fill_quality).round() as i64;

        let better = best
            .as_ref()
            .is_none_or(|b| effective_profit > b.score);
        if better {
            best = Some(Candidate {
                id: c.id.clone(),
                source: c.source_location.clone(),
                destination: c.destination_location.clone(),
                commodity: c.commodity,
                qty: c.quantity,
                payment: c.payment,
                cost,
                score: effective_profit,
                kind: c.contract_type,
            });
        }
    }
    let cand = best?;
    let profit = cand.payment - cand.cost;

    // Snapshot delivery params before `cand.id` gets moved into the
    // BT builder below — we need them for the `delivery_params`
    // field on `ContractCandidate` so downstream callers can
    // re-synthesise a combined delivery+retrofit BT.
    let delivery_params = match cand.kind {
        ContractType::Delivery | ContractType::Subsidy | ContractType::Construction => {
            Some(DeliveryParams {
                source: cand.source.clone(),
                destination: cand.destination.clone(),
                commodity: cand.commodity,
                quantity: cand.qty,
                contract_id: cand.id.clone(),
            })
        }
        _ => None,
    };

    // Kind-specific goal name — matches the personality archetype
    // `prefer_goals` keys (e.g. `courier` archetype weights
    // `fulfill_passenger_transport`, `reliable_trucker` weights
    // `fulfill_delivery`, etc). Phase 18i.
    let (goal_name, bt) = match cand.kind {
        ContractType::CrewMission => (
            "do_crew_mission",
            build_fulfill_crew_mission_bt(
                at_loc,
                &cand.source,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Passenger => (
            "fulfill_passenger_transport",
            build_fulfill_passenger_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Courier => (
            "fulfill_courier",
            build_fulfill_passenger_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Subsidy => (
            "fulfill_contract",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        ContractType::Construction => (
            "fulfill_construction",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
        _ => (
            "fulfill_delivery",
            build_fulfill_delivery_bt(
                at_loc,
                &cand.source,
                &cand.destination,
                cand.commodity,
                cand.qty,
                cand.id,
                fuel_bucket,
                registry,
                gate_pairs,
            ),
        ),
    };
    Some(ContractCandidate {
        goal_name,
        profit,
        bt,
        delivery_params,
    })
}

/// Build a crew-mission BT. Travel to the station, dock, refuel, rest
/// (the dwell — Rest returns Running until morale >= target, which
/// approximates the mission's duration_ticks). Then Deliver claims the
/// payout; Undock.
#[allow(clippy::too_many_arguments)]
fn build_fulfill_crew_mission_bt(
    current: &str,
    station: &str,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    // Hand-authored fallback retired — the planner owns this goal.
    // If the planner somehow fails (bug, depth cap exceeded), the
    // ship returns an Idle BT for one tick and replans next tick
    // with whatever state has changed. See the GOAP arc commits.
    try_build_fulfill_crew_mission_bt_planned(
        current,
        station,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: crew-mission planner. Single-station mission (travel →
/// dock → refuel → rest → deliver payout → undock). Ordering is
/// enforced by the Rest precondition and the
/// `delivered && rested` goal predicate.
fn try_build_fulfill_crew_mission_bt_planned(
    current: &str,
    station: &str,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused by crew_mission_catalog)
        station.to_string(),
        Commodity::Food,
        0,
        contract_id.to_string(),
        0,
        0,
        cost(current, station),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.rested && s.fuel_bucket >= 2,
        Operator::crew_mission_catalog(),
        &map,
        20,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Build a passenger/courier BT. No Buy step; the ship just hops between
/// source and destination and collects payment on Deliver.
#[allow(clippy::too_many_arguments)]
fn build_fulfill_passenger_bt(
    current: &str,
    source: &str,
    destination: &str,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_fulfill_passenger_bt_planned(
        current,
        source,
        destination,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: forward planner for passenger / courier contracts. No
/// cargo mechanics — goal is `delivered && fuel_bucket >= 2`, and
/// the `passenger_catalog` has no Buy / SellAll / Refit operators
/// so plans are naturally compact (just dock at source, undock,
/// travel, dock at dest, deliver).
fn try_build_fulfill_passenger_bt_planned(
    current: &str,
    source: &str,
    destination: &str,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    // Passenger contracts ignore commodity + quantity; pass a
    // sentinel to satisfy LocMap's delivery constructor.
    let map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        Commodity::Food,
        0,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.fuel_bucket >= 2,
        Operator::passenger_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

// --- BT builders ---

/// Wall-clock dwell (seconds) injected after Dock and before Undock so
/// the ship visibly sits at the pad doing "station business" — cargo
/// handling, crew embark/disembark, paperwork — instead of the whole
/// dock sequence rattling through in 3 ticks. Kept small so it doesn't
/// cripple the economy; refuel + sell multi-tick actions do most of the
/// real dwell work.
const DOCK_ARRIVE_DWELL_SECS: u8 = 2;
const DOCK_DEPART_DWELL_SECS: u8 = 2;

fn build_refuel_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::Refuel),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

fn build_sell_cargo_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::SellAll),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

#[allow(dead_code)]
fn build_rest_crew_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }),
        BtNode::action(ShipAction::Refuel),
        BtNode::action(ShipAction::Rest),
        BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }),
        BtNode::action(ShipAction::Undock),
    ])
}

/// Phase 18L: congestion-aware rest-crew BT. Routes to `target`
/// (which may differ from `current` when the current location is
/// saturated), then dock + refuel + rest + undock. If target ==
/// current, the route leg is empty — identical behavior to the
/// pre-18L flat sequence.
#[allow(clippy::too_many_arguments)]
fn build_rest_crew_bt_to(
    current: &str,
    target: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_rest_crew_bt_to_planned(current, target, fuel_bucket, registry, gate_pairs)
        .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: rest_crew planner. Goal =
/// `rested && !docked && at == Dest && fuel_bucket >= 2`. The
/// `rest_crew_catalog` has no cargo / contract ops so plans are
/// tightly scoped to travel-dock-rest-undock.
fn try_build_rest_crew_bt_to_planned(
    current: &str,
    target: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused by rest_crew_catalog)
        target.to_string(),
        Commodity::Food,
        0,
        String::new(), // no contract
        0,
        0,
        cost(current, target),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.rested && !s.docked && s.at == Loc::Dest && s.fuel_bucket >= 2,
        Operator::rest_crew_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Phase 18L: pick the best rest destination given current location
/// and a per-location congestion snapshot. Prefers the current
/// location if it has any free dock slot; otherwise picks the
/// least-congested station in the same system. Falls back to
/// current if no better option exists (ship will still try, hit
/// the Dock wait budget, unwind, and retry — better than nothing).
///
/// Congestion scored as `docked / capacity` (saturation ratio).
/// Same-system constraint so ships don't pathfind across gates
/// just for shore leave — that's for a later phase if needed.
pub fn pick_rest_destination(
    current: &str,
    congestion: &StdHashMap<String, (u32, u32)>,
    location_to_system: &StdHashMap<String, String>,
) -> String {
    let current_load = congestion.get(current);
    let has_free_here = match current_load {
        Some(&(cap, docked)) => cap > 0 && docked < cap,
        None => false,
    };
    if has_free_here {
        return current.to_string();
    }
    let ship_sys = location_to_system.get(current);
    // Find the least-saturated location in the same system.
    let mut best: Option<(String, f32)> = None;
    for (loc, &(cap, docked)) in congestion.iter() {
        if cap == 0 {
            continue;
        }
        if docked >= cap {
            continue; // still saturated
        }
        // Same-system only.
        let loc_sys = location_to_system.get(loc);
        if ship_sys.is_some() && ship_sys != loc_sys {
            continue;
        }
        let saturation = docked as f32 / cap as f32;
        let better = best.as_ref().is_none_or(|(_, s)| saturation < *s);
        if better {
            best = Some((loc.clone(), saturation));
        }
    }
    best.map(|(loc, _)| loc).unwrap_or_else(|| current.to_string())
}

/// Build a trade_run BT. Start at `current`, visit `buy_loc`, buy `commodity`,
/// travel to `sell_loc`, sell, end at sell_loc.
///
/// If `current == buy_loc`, skip the initial travel leg.
/// Proposed retrofit the planner has already costed and located. Built
/// by [`find_retrofit_opportunity`] from a ship's fitting + a per-tick
/// snapshot of shipyard inventories. The planner turns this into a
/// `build_retrofit_bt` goal when the ship qualifies (has points +
/// credits + isn't in a higher-priority state).
#[derive(Debug, Clone)]
pub struct RetrofitPlan {
    pub shipyard_location: String,
    pub slot: crate::modules::Slot,
    pub slug: &'static str,
    pub cost: i64,
}

/// Snapshot of every shipyard's available inventory, built once per
/// `decide_and_act` call so each ship's planner can consult it without
/// re-querying hecs. `Vec` keeps order deterministic run-over-run.
///
/// Each entry is `(location_name, system_id, stock)` — system is
/// derived from the yard's body via `BodyIdentity.system_name` and
/// powers the "same-system first" retrofit preference.
pub type ShipyardInventorySnapshot =
    Vec<(String, String, std::collections::HashMap<String, u32>)>;

/// Credits floor a ship keeps in reserve before considering an
/// autonomous retrofit. Refits are meant to be rare; no ship burns
/// its last coins on a cargo-bay upgrade. Keep well above the
/// cheapest tier-2 module (5500 cr) so the ship still has operating
/// credits after a purchase.
pub const RETROFIT_CREDIT_RESERVE: i64 = 12_000;

/// Given a ship's current fitting and the global shipyard inventory
/// snapshot, pick at most one concrete retrofit target: which slot to
/// upgrade, to which slug, and where. Returns `None` if no eligible
/// swap exists — every slot already at tier 3, or no shipyard carries
/// a matching upgrade in stock.
///
/// Selection policy:
///  - Walk slots in canonical order (engine, cargo, sensors, reactor, comms).
///  - Target `current_tier + 1` (skip if already at 3).
///  - Among yards carrying the target slug, prefer (in order): same
///    location (no travel), same system (no gate hop), any other.
///    Keeps Tau Ceti ships from flying to Earth for a routine refit
///    when their home yard has stock.
pub fn find_retrofit_opportunity(
    fitting: &ShipFitting,
    inventory: &ShipyardInventorySnapshot,
    ship_credits: i64,
    ship_location: &str,
    ship_system: &str,
) -> Option<RetrofitPlan> {
    if ship_credits < RETROFIT_CREDIT_RESERVE {
        return None;
    }
    for slot in crate::modules::SLOTS.iter().copied() {
        // Determine current tier in this slot (1 when empty — nothing
        // to upgrade toward past 3).
        let current_tier = fitting
            .slot_slug(slot)
            .and_then(crate::modules::get)
            .map(|d| d.tier)
            .unwrap_or(1);
        if current_tier >= 3 {
            continue;
        }
        let target_tier = current_tier + 1;
        // Canonical slug for {slot}_t{target_tier} — matches how the
        // catalog names entries. A richer catalog (same slot, multiple
        // same-tier variants) would need a lookup; keep it simple.
        let slug_owned = format!("{}_t{}", slot.as_str(), target_tier);
        let Some(def) = crate::modules::get(&slug_owned) else {
            continue;
        };
        let Some(recipe) = crate::economy::module_production::get(def.slug) else {
            continue;
        };
        // Need to afford the purchase AND stay above reserve afterwards.
        if ship_credits - recipe.base_cost_credits < RETROFIT_CREDIT_RESERVE {
            continue;
        }
        // Rank yards carrying this slug by proximity: same location
        // first, then same system, then anywhere else. `min_by_key`
        // picks the lowest score; ties broken by Vec iteration order
        // (deterministic per run).
        let Some((loc, _, _)) = inventory
            .iter()
            .filter(|(_, _, stock)| stock.get(def.slug).copied().unwrap_or(0) > 0)
            .min_by_key(|(loc, system, _)| {
                if loc == ship_location {
                    0u8
                } else if !ship_system.is_empty() && system == ship_system {
                    1
                } else {
                    2
                }
            })
        else {
            continue;
        };
        return Some(RetrofitPlan {
            shipyard_location: loc.clone(),
            slot,
            slug: def.slug,
            cost: recipe.base_cost_credits,
        });
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn build_retrofit_bt(
    current: &str,
    plan: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_retrofit_bt_planned(current, plan, fuel_bucket, registry, gate_pairs)
        .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP: forward planner for standalone retrofit. Uses the
/// `retrofit_catalog` which has no cargo operators. Goal =
/// `retrofitted && fuel_bucket >= 2`. Travel is only meaningful
/// to the shipyard, so we populate only origin + shipyard costs.
fn try_build_retrofit_bt_planned(
    current: &str,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan as plan_search, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    // Retrofit-only LocMap — Source/Dest are unused by the
    // retrofit_catalog so their strings and costs don't matter.
    // Shipyard fields carry the real target.
    let mut map = LocMap::delivery(
        current.to_string(),
        current.to_string(), // Source placeholder (unused)
        current.to_string(), // Dest placeholder (unused)
        Commodity::Food,
        0,
        String::new(), // no contract
        0,
        0,
        0,
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = 0;
    map.cost_shipyard_to_dest = 0;

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan_search(
        initial,
        |s| s.retrofitted && s.fuel_bucket >= 2,
        Operator::retrofit_catalog(),
        &map,
        16,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

#[allow(clippy::too_many_arguments)]
fn build_trade_run_bt(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_trade_run_bt_planned(
        current,
        buy_loc,
        sell_loc,
        commodity,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP expansion: run the forward planner for a trade run. Goal =
/// `sold && fuel_bucket >= 2`. `trade_run_catalog` swaps DeliverCargo
/// for SellAll at the destination — no contract, just a market sell.
/// Takes the ship's real `fuel_bucket` so fuel-aware optimisations
/// can emerge: a flush ship skips refuels, a thirsty ship forces
/// one in at the first dockable stop.
#[allow(clippy::too_many_arguments)]
fn try_build_trade_run_bt_planned(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };
    let map = LocMap::trade_run(
        current.to_string(),
        buy_loc.to_string(),
        sell_loc.to_string(),
        commodity,
        TRADE_QTY_DEFAULT,
        cost(current, buy_loc),
        cost(buy_loc, sell_loc),
        cost(current, sell_loc),
    );
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.sold && s.fuel_bucket >= 2,
        Operator::trade_run_catalog(),
        &map,
        20,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Shared fuel-bucket cost estimator used by planned BT builders.
/// Walks the real leg sequence via the pathfinder and rolls the
/// summed distance into fuel buckets (~50 units per bucket).
fn estimate_fuel_bucket_cost(
    from: &str,
    to: &str,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> u8 {
    if from == to {
        return 0;
    }
    let ctx = crate::world::pathfinder::PathfinderCtx { registry, gate_pairs };
    let legs = match ctx.find_route(from, to) {
        Some(l) => l,
        None => return 1,
    };
    let total_distance: u32 = legs.iter().map(|l| l.distance.max(1)).sum();
    let buckets = ((total_distance as f32) / 50.0).ceil().max(1.0) as u32;
    buckets.min(10) as u8
}

/// Build a fulfill_delivery BT:
///   accept → travel to source → dock → refuel → buy → undock →
///   travel to destination → dock → deliver → undock
#[allow(clippy::too_many_arguments)]
fn build_fulfill_delivery_bt(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: String,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    try_build_fulfill_delivery_bt_planned(
        current,
        source,
        destination,
        commodity,
        quantity,
        &contract_id,
        fuel_bucket,
        registry,
        gate_pairs,
    )
    .unwrap_or_else(|| BtNode::action(ShipAction::Idle))
}

/// GOAP MVP: run the forward planner to synthesise a delivery BT.
/// Returns `None` when the planner can't find a plan within its
/// depth cap (caller falls back to the hand-authored sequence).
///
/// This is where combined goals will live as the MVP expands. For
/// now the goal is simple `delivered == true AND fuel_bucket ≥ 2`
/// so the planner decides whether to insert a Refuel based on
/// travel-cost budgets — same emergent behaviour the hand-authored
/// builder has hardcoded, but derived rather than asserted.
#[allow(clippy::too_many_arguments)]
fn try_build_fulfill_delivery_bt_planned(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: &str,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, LocMap, Loc, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        commodity,
        quantity,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );

    // Start state uses the ship's real fuel bucket so fuel-aware
    // optimisations can emerge — a flush ship skips unnecessary
    // refuels, a thirsty ship forces one at the first dockable
    // stop. The BT's real executors still re-check fuel at
    // execution time as a belt-and-braces.
    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.fuel_bucket >= 2,
        Operator::delivery_catalog(),
        &map,
        20,
    )?;

    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// Expand a planner-emitted action sequence into a real BT. Abstract
/// `Travel { destination }` steps get resolved to the actual multi-
/// leg pathfinder output (gate jumps etc.); `Dock` / `DockAtShipyard` /
/// `Undock` steps are wrapped with `DockDwell` so the visual pacing
/// matches the hand-authored builders. `AcceptContract` is prepended
/// only when the map carries a contract_id — trade-run plans skip
/// it entirely.
fn compile_plan_to_bt(
    plan_actions: &[ShipAction],
    map: &crate::ai::planner::LocMap,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps: Vec<BtNode<ShipAction>> = Vec::with_capacity(plan_actions.len() * 2 + 2);
    if !map.contract_id.is_empty() {
        steps.push(BtNode::action(ShipAction::AcceptContract {
            contract_id: map.contract_id.clone(),
        }));
    }
    let mut current_loc = map.origin.clone();
    for a in plan_actions {
        match a {
            ShipAction::Travel { destination } => {
                for leg in route_actions(&current_loc, destination, registry, gate_pairs) {
                    steps.push(BtNode::action(leg));
                }
                current_loc = destination.clone();
            }
            ShipAction::Dock | ShipAction::DockAtShipyard => {
                steps.push(BtNode::action(a.clone()));
                steps.push(BtNode::action(ShipAction::DockDwell {
                    seconds: DOCK_ARRIVE_DWELL_SECS,
                }));
            }
            ShipAction::Undock => {
                steps.push(BtNode::action(ShipAction::DockDwell {
                    seconds: DOCK_DEPART_DWELL_SECS,
                }));
                steps.push(BtNode::action(ShipAction::Undock));
            }
            other => steps.push(BtNode::action(other.clone())),
        }
    }
    BtNode::sequence(steps)
}

/// GOAP expansion: synthesise a combined delivery+retrofit plan.
/// Returns `None` when the planner can't fold both goals within its
/// depth cap — caller falls back to the plain delivery builder,
/// meaning the retrofit runs as a separate plan later. This is the
/// first plan the hand-authored BTs literally cannot produce: a
/// single BT that picks up contract cargo, detours through a
/// shipyard for a refit, then delivers.
#[allow(clippy::too_many_arguments)]
fn try_build_fulfill_delivery_with_retrofit_planned(
    current: &str,
    source: &str,
    destination: &str,
    commodity: Commodity,
    quantity: u32,
    contract_id: &str,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let mut map = LocMap::delivery(
        current.to_string(),
        source.to_string(),
        destination.to_string(),
        commodity,
        quantity,
        contract_id.to_string(),
        cost(current, source),
        cost(source, destination),
        cost(current, destination),
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = cost(source, &retrofit.shipyard_location);
    map.cost_shipyard_to_dest = cost(&retrofit.shipyard_location, destination);

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.delivered && s.retrofitted && s.fuel_bucket >= 2,
        Operator::delivery_catalog(),
        &map,
        28,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

/// GOAP: combined trade_run + retrofit. Mirror of the delivery+retrofit
/// variant for trade-class plans — ship buys at source, detours
/// through the shipyard for a refit, sells at dest. Uses
/// `trade_run_catalog` (SellAll at dest instead of DeliverCargo).
#[allow(clippy::too_many_arguments)]
fn try_build_trade_run_with_retrofit_planned(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    retrofit: &RetrofitPlan,
    fuel_bucket: u8,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> Option<BtNode<ShipAction>> {
    use crate::ai::planner::{plan, Loc, LocMap, Operator, WorldState};
    let cost = |from: &str, to: &str| -> u8 { estimate_fuel_bucket_cost(from, to, registry, gate_pairs) };

    let mut map = LocMap::trade_run(
        current.to_string(),
        buy_loc.to_string(),
        sell_loc.to_string(),
        commodity,
        TRADE_QTY_DEFAULT,
        cost(current, buy_loc),
        cost(buy_loc, sell_loc),
        cost(current, sell_loc),
    );
    map.shipyard = Some(retrofit.shipyard_location.clone());
    map.refit_slot = Some(retrofit.slot);
    map.refit_slug = Some(retrofit.slug);
    map.cost_origin_to_shipyard = cost(current, &retrofit.shipyard_location);
    map.cost_source_to_shipyard = cost(buy_loc, &retrofit.shipyard_location);
    map.cost_shipyard_to_dest = cost(&retrofit.shipyard_location, sell_loc);

    let initial = WorldState::new(Loc::Origin, fuel_bucket);
    let synth = plan(
        initial,
        |s| s.sold && s.retrofitted && s.fuel_bucket >= 2,
        Operator::trade_run_catalog(),
        &map,
        28,
    )?;
    Some(compile_plan_to_bt(&synth.actions, &map, registry, gate_pairs))
}

// --- Action executor (the dispatch closure's body) ---

#[cfg(test)]
mod crew_tests {
    use super::*;

    #[test]
    fn crew_efficiency_floors_at_0_1() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 0.0,
            fatigue: 0.0,
            health: 0.0,
            wages_credits: 0,
            current_task: CrewTask::Idle,
            dirty: false,
        };
        assert!((c.efficiency() - 0.1).abs() < 1e-4);
    }

    #[test]
    fn crew_efficiency_at_full_health_and_morale_is_one() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 100.0,
            fatigue: 0.0,
            health: 100.0,
            wages_credits: 0,
            current_task: CrewTask::Piloting,
            dirty: false,
        };
        assert!((c.efficiency() - 1.0).abs() < 1e-4);
    }

    #[test]
    fn crew_needs_shore_leave_below_50() {
        let c = ShipCrew {
            size: 3,
            hunger: 0.0,
            morale: 49.0,
            fatigue: 0.0,
            health: 100.0,
            wages_credits: 0,
            current_task: CrewTask::Idle,
            dirty: false,
        };
        assert!(c.needs_shore_leave());
        assert!(!c.shore_leave_complete());
    }

    #[test]
    fn skills_default_for_pilot_engineer_trader() {
        let s = ShipCrewSkills::for_roles(&["pilot", "engineer", "trader"]);
        assert_eq!(s.navigation, 40);
        assert_eq!(s.engineering, 40);
        assert_eq!(s.trading, 40);
        assert_eq!(s.combat, 20);
    }

    #[test]
    fn skills_grant_caps_at_100() {
        let mut s = ShipCrewSkills::for_roles(&["pilot"]);
        s.grant("navigation", 70);
        assert_eq!(s.navigation, 100); // 40 + 70 → capped
        s.grant("trading", 50);
        assert_eq!(s.trading, 80);
        s.grant("combat", 200);
        assert_eq!(s.combat, 100);
        // Unknown skill name is a no-op
        s.grant("telepathy", 10);
        assert_eq!(s.navigation, 100);
    }

    #[test]
    fn primary_task_prefers_piloting_in_transit() {
        assert_eq!(
            primary_task(&["pilot", "engineer", "trader"], true),
            CrewTask::Piloting
        );
        assert_eq!(
            primary_task(&["engineer", "trader"], true),
            CrewTask::Engineering
        );
        assert_eq!(primary_task(&["trader"], false), CrewTask::Trading);
        assert_eq!(primary_task(&[], false), CrewTask::Idle);
    }
}

#[cfg(test)]
mod tick_tests {
    use super::*;
    use super::actions::affordable_quantity;

    #[test]
    fn affordable_quantity_respects_credits_and_capacity() {
        assert_eq!(affordable_quantity(100, 10.0, 1000), 10);
        assert_eq!(affordable_quantity(0, 10.0, 1000), 0);
        assert_eq!(affordable_quantity(1000, 10.0, 50), 50);
        assert_eq!(affordable_quantity(50, 10.0, 100), 5);
    }

    #[test]
    fn best_trade_route_finds_best_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("belt".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 50.0, tick: 1 });
        memory.price_knowledge.insert("earth".into(), b);
        let route = best_trade_route(&memory, 1).unwrap();
        assert_eq!(route.0, Commodity::Ore);
        assert_eq!(route.1, "belt");
        assert_eq!(route.2, "earth");
    }

    #[test]
    fn best_trade_route_prefers_fresher_over_slightly_better_stale() {
        // Stale huge-margin route at tick 1 vs fresh good-margin route
        // at tick 10_000. The fresh route should win even though the
        // stale one has a nominally larger raw margin.
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut stale_a = std::collections::HashMap::new();
        stale_a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("stale-belt".into(), stale_a);
        let mut stale_b = std::collections::HashMap::new();
        stale_b.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("stale-hub".into(), stale_b);
        // 900% raw margin, but 10_000 ticks old → heavily decayed.

        let mut fresh_a = std::collections::HashMap::new();
        fresh_a.insert(
            Commodity::Fuel,
            PriceMemory { price: 50.0, tick: 10_000 },
        );
        memory.price_knowledge.insert("fresh-belt".into(), fresh_a);
        let mut fresh_b = std::collections::HashMap::new();
        fresh_b.insert(
            Commodity::Fuel,
            PriceMemory { price: 150.0, tick: 10_000 },
        );
        memory.price_knowledge.insert("fresh-hub".into(), fresh_b);
        // 200% raw margin, freshly observed at tick 10_000.

        let route = best_trade_route(&memory, 10_000).unwrap();
        assert_eq!(
            route.0,
            Commodity::Fuel,
            "fresh fuel route should beat 10k-tick-stale ore route",
        );
    }

    #[test]
    fn price_freshness_weight_decays_monotonically() {
        // Sanity check the decay curve: fresh = 1.0, half-life = 0.5,
        // 2× half-life = 0.25, ancient floors at FRESHNESS_FLOOR.
        let fresh = price_freshness_weight(1000, 1000);
        assert!((fresh - 1.0).abs() < 1e-5);
        let half = price_freshness_weight(0, PRICE_MEMORY_HALF_LIFE_TICKS);
        assert!((half - 0.5).abs() < 1e-5, "half-life should halve weight, got {half}");
        let ancient = price_freshness_weight(0, 1_000_000);
        assert!(
            (ancient - PRICE_MEMORY_FRESHNESS_FLOOR).abs() < 1e-5,
            "very old should floor, got {ancient}",
        );
    }

    #[test]
    fn pick_rest_destination_prefers_current_when_free() {
        let mut cong: StdHashMap<String, (u32, u32)> = StdHashMap::new();
        cong.insert("earth-station".into(), (23, 5)); // 21% full
        cong.insert("mars-station".into(), (10, 1));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("earth-station".into(), "Sol".into());
        sys.insert("mars-station".into(), "Sol".into());
        // Current has free slots → stay.
        assert_eq!(
            pick_rest_destination("earth-station", &cong, &sys),
            "earth-station",
        );
    }

    #[test]
    fn pick_rest_destination_routes_away_from_saturated() {
        let mut cong: StdHashMap<String, (u32, u32)> = StdHashMap::new();
        cong.insert("haven-station".into(), (19, 19)); // 100% full
        cong.insert("proxima-outpost".into(), (8, 2)); // 25%
        cong.insert("refuge-station".into(), (6, 1));  // 17%
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("haven-station".into(), "Alpha Centauri".into());
        sys.insert("proxima-outpost".into(), "Alpha Centauri".into());
        sys.insert("refuge-station".into(), "Alpha Centauri".into());
        // Current saturated → pick least-saturated same-system option.
        assert_eq!(
            pick_rest_destination("haven-station", &cong, &sys),
            "refuge-station",
        );
    }

    #[test]
    fn pick_rest_destination_stays_in_same_system() {
        let mut cong: StdHashMap<String, (u32, u32)> = StdHashMap::new();
        cong.insert("haven-station".into(), (19, 19)); // AC saturated
        cong.insert("earth-station".into(), (23, 0));  // Sol wide open
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("haven-station".into(), "Alpha Centauri".into());
        sys.insert("earth-station".into(), "Sol".into());
        // Even though earth has tons of space, it's cross-system.
        // Fall back to current saturated location.
        assert_eq!(
            pick_rest_destination("haven-station", &cong, &sys),
            "haven-station",
        );
    }

    #[test]
    fn pick_rest_destination_falls_back_when_all_full() {
        let mut cong: StdHashMap<String, (u32, u32)> = StdHashMap::new();
        cong.insert("a".into(), (10, 10));
        cong.insert("b".into(), (5, 5));
        let mut sys: StdHashMap<String, String> = StdHashMap::new();
        sys.insert("a".into(), "Sol".into());
        sys.insert("b".into(), "Sol".into());
        // All saturated → stick with current. Ship will still try,
        // hit the Dock wait budget, and replan — better than None.
        assert_eq!(pick_rest_destination("a", &cong, &sys), "a");
    }

    #[test]
    fn score_goal_positive_profit_scales_with_personality_bonus() {
        let p = crate::ai::personality::Personality::cautious_trader();
        // cautious_trader likes fulfill_delivery (+0.3) and
        // fulfill_contract (+0.3), flat on trade_run.
        let contract = score_strategic(1600, "fulfill_delivery", &p);
        let trade = score_strategic(1600, "trade_run", &p);
        assert!(
            contract > trade,
            "cautious_trader should favor fulfill_delivery over trade_run (got {contract} vs {trade})",
        );
    }

    #[test]
    fn score_goal_aggressive_trader_picks_trade_over_contract() {
        let p = crate::ai::personality::Personality::aggressive_trader();
        // aggressive_trader has prefer_goals[trade_run] = 0.3.
        let contract = score_strategic(1600, "fulfill_delivery", &p);
        let trade = score_strategic(1600, "trade_run", &p);
        assert!(
            trade > contract,
            "aggressive_trader should pick trade_run over equal-profit contract",
        );
    }

    #[test]
    fn score_goal_courier_picks_passenger_over_trade() {
        let p = crate::ai::personality::Personality::courier();
        let passenger = score_strategic(1200, "fulfill_passenger_transport", &p);
        let trade = score_strategic(1200, "trade_run", &p);
        assert!(passenger > trade, "courier should favor passenger work");
    }

    #[test]
    fn score_goal_zero_when_no_profit() {
        let p = crate::ai::personality::Personality::balanced_trader();
        assert_eq!(score_strategic(0, "fulfill_delivery", &p), 0.0);
        assert_eq!(score_strategic(-500, "trade_run", &p), 0.0);
    }

    #[test]
    fn score_goal_log_scales_so_small_bonus_can_flip_picks() {
        // Huge trade-run profit (50000) vs modest contract (2000)
        // — without bonus trade wins. With a strong contract bonus
        // (>0.7), contract might still lose because log-scale
        // compresses. This test documents the expected behaviour.
        let p_flat = crate::ai::personality::Personality::balanced_trader();
        assert!(score_strategic(50000, "trade_run", &p_flat) > score_strategic(2000, "fulfill_delivery", &p_flat));
        // With a modest contract preference it still doesn't win
        // a 25× profit gap (as designed — log-scaling prevents
        // personality from completely overriding profit).
        let mut p_biased = crate::ai::personality::Personality::balanced_trader();
        p_biased.prefer_goals.insert("fulfill_delivery".into(), 0.3);
        assert!(score_strategic(50000, "trade_run", &p_biased) > score_strategic(2000, "fulfill_delivery", &p_biased));
    }

    #[test]
    fn best_trade_route_none_for_thin_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
            recent_systems: std::collections::VecDeque::new(),
            route_performance: std::collections::HashMap::new(),
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("a".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 105.0, tick: 1 });
        memory.price_knowledge.insert("b".into(), b);
        assert!(best_trade_route(&memory, 1).is_none());
    }

    // --- Bundle 2.1 unified utility scorer tests ---

    #[test]
    fn unified_scorer_biological_dominates_strategic_when_critical() {
        // Critical fuel (5%) on a cautious trader must outscore a
        // 50k-credit trade. This is the "ship at 1% fuel shouldn't
        // pursue a distant contract" invariant.
        let p = crate::ai::personality::Personality::cautious_trader();
        let fuel_urgency = (1.0 - 0.05 / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let refuel_score = fuel_urgency * p.safety.max(0.2) * TIER_BIO_WEIGHT;
        let trade_score = score_strategic(50_000, "trade_run", &p);
        assert!(
            refuel_score > trade_score,
            "refuel at 5% fuel (score {refuel_score}) must beat 50k trade (score {trade_score})",
        );
    }

    #[test]
    fn unified_scorer_strategic_can_win_when_fuel_is_fine() {
        // With fuel at 60% (above FUEL_URGENCY_ONSET=0.45) there's no
        // refuel candidate at all, so a profitable trade is free to
        // win. Housekeeping-tier sell_cargo with empty hold also
        // scores 0. Strategic gets the nod.
        let p = crate::ai::personality::Personality::aggressive_trader();
        let trade_score = score_strategic(10_000, "trade_run", &p);
        // Arbitrary but low idle baseline — strategic should easily
        // clear it.
        let idle_floor = TIER_IDLE_FLOOR;
        assert!(
            trade_score > idle_floor,
            "10k trade (score {trade_score}) must beat idle baseline ({idle_floor})",
        );
    }

    #[test]
    fn unified_scorer_housekeeping_beats_strategic_when_cargo_onboard() {
        // A ship with 80% cargo on a balanced trader should prefer
        // sell_cargo to starting a 5k-credit trade run. Today's
        // waterfall has this invariant; scoring must preserve it.
        let p = crate::ai::personality::Personality::balanced_trader();
        let cargo_frac = 0.8_f32;
        let sell_score =
            (0.5 + cargo_frac * 0.5) * p.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        let trade_score = score_strategic(5_000, "trade_run", &p);
        assert!(
            sell_score > trade_score,
            "sell_cargo at 80% full (score {sell_score}) must beat 5k trade (score {trade_score})",
        );
    }

    #[test]
    fn replan_eligible_only_for_strategic_and_idle() {
        // Protect committed goals from mid-action replan.
        assert!(!is_replan_eligible("rest_crew"));
        assert!(!is_replan_eligible("refuel"));
        assert!(!is_replan_eligible("seek_retrofit"));
        assert!(!is_replan_eligible("sell_cargo"));
        // Combined delivery+retrofit is also committed — interrupting
        // mid-detour loses both the delivery and the retrofit.
        assert!(!is_replan_eligible("fulfill_delivery_with_retrofit"));
        // Same for combined trade_run+retrofit.
        assert!(!is_replan_eligible("trade_run_with_retrofit"));
        // Strategic + idle are fair game.
        assert!(is_replan_eligible("fulfill_delivery"));
        assert!(is_replan_eligible("fulfill_contract"));
        assert!(is_replan_eligible("fulfill_passenger_transport"));
        assert!(is_replan_eligible("trade_run"));
        assert!(is_replan_eligible("explore"));
        assert!(is_replan_eligible("idle"));
        assert!(is_replan_eligible("idle_seek_station"));
    }

    #[test]
    fn replan_ratio_requires_meaningful_improvement() {
        // Sanity check the threshold: a candidate must beat the
        // running plan by REPLAN_SCORE_RATIO (1.30) to interrupt.
        // Noise-level improvements (5-10%) don't trigger thrash.
        let current = 10.0_f32;
        let noise = 10.5_f32;       // +5%
        let solid_win = 14.0_f32;   // +40%
        assert!(noise < current * REPLAN_SCORE_RATIO);
        assert!(solid_win >= current * REPLAN_SCORE_RATIO);
    }

    #[test]
    fn unified_scorer_housekeeping_loses_to_critical_biological() {
        // A ship at 5% fuel with cargo onboard should still refuel
        // rather than chase a sale. Biological > housekeeping.
        let p = crate::ai::personality::Personality::balanced_trader();
        let fuel_urgency = (1.0 - 0.05 / FUEL_URGENCY_ONSET).clamp(0.0, 1.0);
        let refuel_score = fuel_urgency * p.safety.max(0.2) * TIER_BIO_WEIGHT;
        let sell_score = 1.0 * p.profit.max(0.3) * TIER_HOUSEKEEPING_WEIGHT;
        assert!(
            refuel_score > sell_score,
            "critical refuel (score {refuel_score}) must beat full-hold sell (score {sell_score})",
        );
    }

    #[test]
    fn fitting_set_swaps_slug_and_recomputes() {
        use crate::modules::Slot;

        let mut fit = ShipFitting::new_default();
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t1"));
        assert!((fit.derived.speed_mult - 1.0).abs() < 1e-6);

        fit.set(Slot::Engine, Some("engine_t3"));
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t3"));
        assert!((fit.derived.speed_mult - 1.30).abs() < 1e-6);
        assert!((fit.derived.fuel_efficiency_mult - 0.90).abs() < 1e-6);
    }

    #[test]
    fn fitting_clear_slot_drops_to_neutral_mult() {
        use crate::modules::Slot;

        let mut fit = ShipFitting::new_default();
        fit.set(Slot::Engine, Some("engine_t3"));
        assert!(fit.derived.speed_mult > 1.0);
        // Clearing the slot removes the boost without penalising the
        // ship at the catalog layer — gameplay can layer a penalty on
        // top if it wants.
        fit.set(Slot::Engine, None);
        assert!((fit.derived.speed_mult - 1.0).abs() < 1e-6);
    }

    #[test]
    fn fitting_from_slugs_round_trips_valid_slugs() {
        use crate::modules::{Slot, NUM_SLOTS};
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_t2".into()),
            Some("cargo_bay_t2".into()),
            Some("sensors_t1".into()),
            Some("reactor_t1".into()),
            Some("comms_t1".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t2"));
        assert_eq!(fit.slot_slug(Slot::CargoBay), Some("cargo_bay_t2"));
        // Derived reflects the two tier-2 upgrades: 1.15 × 1.0 = 1.15
        // speed, 1.20 cargo mult.
        assert!((fit.derived.speed_mult - 1.15).abs() < 1e-6);
        assert!((fit.derived.cargo_capacity_mult - 1.20).abs() < 1e-6);
    }

    #[test]
    fn progression_levels_up_and_banks_point() {
        let mut p = ShipProgression::new();
        assert_eq!(p.level, 1);
        assert_eq!(p.retrofit_points, 0);

        // First threshold is 100 xp. 99 shouldn't level.
        assert_eq!(p.grant_xp(99), 0);
        assert_eq!(p.level, 1);
        assert_eq!(p.xp, 99);

        // 50 more → crosses 100, banks one point, leaves 49 xp.
        assert_eq!(p.grant_xp(50), 1);
        assert_eq!(p.level, 2);
        assert_eq!(p.retrofit_points, 1);
        assert_eq!(p.xp, 49);
        assert!(p.dirty);
    }

    #[test]
    fn progression_xp_cascades_multiple_levels() {
        let mut p = ShipProgression::new();
        // 600 xp from level 1: 100 → lvl2, 200 → lvl3, 300 → lvl4, no leftover.
        let gained = p.grant_xp(600);
        assert_eq!(gained, 3);
        assert_eq!(p.level, 4);
        assert_eq!(p.retrofit_points, 3);
        assert_eq!(p.xp, 0);
    }

    #[test]
    fn progression_stops_at_level_cap() {
        let mut p = ShipProgression::new();
        p.grant_xp(u32::MAX);
        assert_eq!(p.level, SHIP_LEVEL_CAP);
        // Points banked exactly equal levels gained past 1.
        assert_eq!(p.retrofit_points, SHIP_LEVEL_CAP - 1);
    }

    #[test]
    fn progression_spend_retrofit_point() {
        let mut p = ShipProgression::new();
        assert!(!p.spend_retrofit_point());
        p.retrofit_points = 2;
        assert!(p.spend_retrofit_point());
        assert_eq!(p.retrofit_points, 1);
        assert!(p.spend_retrofit_point());
        assert_eq!(p.retrofit_points, 0);
        assert!(!p.spend_retrofit_point());
    }

    fn yard(
        loc: &str,
        system: &str,
        slug: &str,
        qty: u32,
    ) -> (String, String, std::collections::HashMap<String, u32>) {
        let mut s: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
        s.insert(slug.into(), qty);
        (loc.into(), system.into(), s)
    }

    #[test]
    fn find_retrofit_opportunity_picks_first_upgradable_slot() {
        use crate::modules::Slot;
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("earth-station", "Sol", "engine_t2", 2)];
        let plan = find_retrofit_opportunity(&fit, &inventory, 50_000, "luna-base", "Sol").unwrap();
        assert_eq!(plan.slot, Slot::Engine);
        assert_eq!(plan.slug, "engine_t2");
        assert_eq!(plan.shipyard_location, "earth-station");
    }

    #[test]
    fn find_retrofit_opportunity_rejects_below_credit_reserve() {
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("earth-station", "Sol", "engine_t2", 2)];
        // 12k reserve - can't afford 8k engine_t2 AND keep reserve intact.
        assert!(find_retrofit_opportunity(&fit, &inventory, 15_000, "", "").is_none());
        assert!(find_retrofit_opportunity(&fit, &inventory, 50_000, "", "").is_some());
    }

    #[test]
    fn find_retrofit_opportunity_skips_slot_when_no_stock_and_tries_next() {
        use crate::modules::Slot;
        let fit = ShipFitting::new_default();
        let inventory = vec![yard("mars-station", "Sol", "cargo_bay_t2", 1)];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "mars-station", "Sol").unwrap();
        assert_eq!(plan.slot, Slot::CargoBay);
    }

    #[test]
    fn find_retrofit_opportunity_none_when_fully_tiered() {
        use crate::modules::NUM_SLOTS;
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_t3".into()),
            Some("cargo_bay_t3".into()),
            Some("sensors_t3".into()),
            Some("reactor_t3".into()),
            Some("comms_t3".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        let inventory = vec![yard("anywhere", "Sol", "engine_t3", 5)];
        assert!(find_retrofit_opportunity(&fit, &inventory, 100_000, "", "").is_none());
    }

    #[test]
    fn find_retrofit_opportunity_prefers_same_location() {
        let fit = ShipFitting::new_default();
        // Same slug in two yards; ship is at earth-station, so
        // earth-station should win over haven-station.
        let inventory = vec![
            yard("haven-station", "Alpha Centauri", "engine_t2", 3),
            yard("earth-station", "Sol", "engine_t2", 1),
        ];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "earth-station", "Sol").unwrap();
        assert_eq!(plan.shipyard_location, "earth-station");
    }

    #[test]
    fn find_retrofit_opportunity_prefers_same_system_when_not_at_a_yard() {
        let fit = ShipFitting::new_default();
        // Ship is at anvil-depot (Tau Ceti). Same-system Anvil yard
        // vs cross-gate Earth yard — Anvil should win.
        let inventory = vec![
            yard("earth-station", "Sol", "engine_t2", 5),
            yard("anvil-depot", "Tau Ceti", "engine_t2", 1),
        ];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "anvil-depot", "Tau Ceti").unwrap();
        assert_eq!(plan.shipyard_location, "anvil-depot");
    }

    #[test]
    fn new_for_size_tiny_small_medium_gets_tier1_sensors() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        for sz in [ShipSize::Tiny, ShipSize::Small, ShipSize::Medium] {
            let fit = ShipFitting::new_for_size(sz, "ship-test");
            let slug = fit.slot_slug(Slot::Sensors).unwrap();
            assert_eq!(get(slug).unwrap().tier, 1, "size {:?}", sz);
        }
    }

    #[test]
    fn new_for_size_huge_and_massive_always_get_tier2_sensors() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        for sz in [ShipSize::Huge, ShipSize::Massive] {
            // Any ship id should yield tier-2 sensors.
            for id in ["ship-a", "ship-zzz", "whatever"] {
                let fit = ShipFitting::new_for_size(sz, id);
                let slug = fit.slot_slug(Slot::Sensors).unwrap();
                assert_eq!(
                    get(slug).unwrap().tier,
                    2,
                    "{:?} ship {} should have tier-2 sensors",
                    sz,
                    id,
                );
            }
        }
    }

    #[test]
    fn new_for_size_large_rolls_deterministically_and_mixes() {
        use crate::modules::{get, Slot};
        use crate::simulation::config::ShipSize;
        let mut tier1 = 0;
        let mut tier2 = 0;
        for i in 0..40 {
            let id = format!("ship-fleet-{:03}", i);
            let fit = ShipFitting::new_for_size(ShipSize::Large, &id);
            let tier = get(fit.slot_slug(Slot::Sensors).unwrap())
                .unwrap()
                .tier;
            match tier {
                1 => tier1 += 1,
                2 => tier2 += 1,
                _ => panic!("unexpected tier"),
            }
            // Same id → same result every call (deterministic roll).
            let again = ShipFitting::new_for_size(ShipSize::Large, &id);
            assert_eq!(fit.slot_slug(Slot::Sensors), again.slot_slug(Slot::Sensors));
        }
        assert!(tier1 > 0 && tier2 > 0, "large roll should mix across 40 ships (got t1={} t2={})", tier1, tier2);
    }

    #[test]
    fn find_retrofit_opportunity_falls_back_when_no_local_match() {
        let fit = ShipFitting::new_default();
        // Ship in Sol, engine_t2 only stocked in Tau Ceti — still
        // picks it (cross-system retrofit beats no retrofit).
        let inventory = vec![yard("anvil-depot", "Tau Ceti", "engine_t2", 1)];
        let plan =
            find_retrofit_opportunity(&fit, &inventory, 50_000, "earth-station", "Sol").unwrap();
        assert_eq!(plan.shipyard_location, "anvil-depot");
    }

    #[test]
    fn fitting_from_slugs_falls_back_to_default_on_unknown() {
        use crate::modules::{Slot, NUM_SLOTS};
        let raw: [Option<String>; NUM_SLOTS] = [
            Some("engine_mystery_xyz".into()), // unknown slug
            Some("cargo_bay_t1".into()),
            Some("sensors_t1".into()),
            Some("reactor_t1".into()),
            Some("comms_t1".into()),
        ];
        let fit = ShipFitting::from_slugs(&raw);
        // Unknown slug falls back to the tier-1 default — rehydration
        // from a stale DB row never yields an empty engine.
        assert_eq!(fit.slot_slug(Slot::Engine), Some("engine_t1"));
    }
}
