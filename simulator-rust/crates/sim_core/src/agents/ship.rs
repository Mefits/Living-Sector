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
    /// + current world_speed. Persist it for snapshot stability but don't
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
}

/// AI: personality + current goal + BT state (parameterized over ShipAction).
#[derive(Debug, Clone)]
pub struct ShipAI {
    pub personality: Personality,
    pub current_goal: String,
    pub current_bt: Option<BtNode<ShipAction>>,
}

/// Ship-specific BT leaf actions. Each variant carries the parameters it
/// needs — the dispatch closure in `ship::decide_and_act` reads them and
/// executes against the ship's components.
#[derive(Debug, Clone)]
pub enum ShipAction {
    /// Begin transit to a named location. Returns Running until arrival.
    Travel { destination: String },
    /// Mark the ship as docked at its current location.
    Dock,
    /// Undock (clear docked_at).
    Undock,
    /// Refill fuel to capacity (MVP: free refill at any location).
    Refuel,
    /// Buy up to `qty` units of `commodity` at the ship's current location.
    /// Returns Failure if no local price or ship can't afford any.
    Buy { commodity: Commodity, qty: u32 },
    /// Sell `qty` of `commodity` at the current location. `qty = 0` means "all".
    Sell { commodity: Commodity, qty: u32 },
    /// Sell every commodity in the hold.
    SellAll,
    /// Accept a delivery contract by id (Phase 8b).
    AcceptContract { contract_id: String },
    /// Pick up the cargo reserved for an accepted contract (Phase 8b).
    PickupCargo { contract_id: String },
    /// Deliver contract cargo and collect payment (Phase 8b).
    DeliverCargo { contract_id: String },
    /// Do nothing — always succeeds.
    Idle,
    /// Shore leave: dwell at current location until crew morale recovers.
    /// Returns Running until morale > CREW_REST_TARGET, then Success.
    Rest,
    /// Visible station dwell — "loading/unloading/paperwork/crew activity"
    /// time. Returns Running until `seconds` wall-clock seconds have
    /// elapsed (at TPS=8, that's `seconds × 8` base ticks), regardless of
    /// world_speed. Without this, the Dock→Refuel→Undock chain can
    /// complete in a few ticks and the ship visibly flickers off the pad.
    /// `dock_dwell_start_tick` on ShipEconomy tracks the deadline across
    /// ticks.
    DockDwell { seconds: u8 },
    /// Jump through a gate. Ship must be at `src_gate` location. Apply
    /// phase charges the gate fee (`flat + per_cargo × cargo_used`) and
    /// teleports the ship to `dest_gate`. Instant — no transit time.
    /// Fails if the ship can't afford the fee or isn't at the source
    /// gate.
    GateJump {
        src_gate: String,
        dest_gate: String,
    },
}

/// Learned memory — price knowledge, visited locations.
/// Rarely loaded except during trade decisions.
#[derive(Debug, Clone)]
pub struct ShipMemory {
    pub price_knowledge: PriceKnowledge,
    pub visited: Vec<String>,
}

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

/// Serializable snapshot for HTTP/WS clients — built by querying components.
///
/// Field names match what the Godot client reads. Position uses the `{x, y}`
/// dict shape (via `Position` wrapper); `location` is the string name of the
/// ship's current location (None = in transit).
#[derive(Debug, Clone, Serialize)]
pub struct ShipSnapshot {
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    /// Current location string (e.g. "earth-station"). `None` while in transit.
    /// Godot's `ship.gd` reads this as `data["location"]` for docked checks.
    #[serde(rename = "location")]
    pub location_name: Option<String>,
    pub docked: bool,
    pub transit: Option<Transit>,
    pub cargo: HashMap<String, u32>,
    pub cargo_capacity: u32,
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub credits: i64,
    pub current_goal: String,
    /// Contract currently being executed, if any — lets the UI pull the
    /// full contract record from `/api/contracts` for richer display.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_contract_id: Option<String>,
    /// Current BT action name (Debug-formatted enum variant). Godot UI
    /// panels display this under `current_bt`.
    #[serde(rename = "current_bt")]
    pub bt_action: Option<String>,
    pub position: super::Position,
    // Lifecycle counters — shown in the ship list UI
    pub broke_strikes: u8,
    pub hoard_strikes: u8,
    pub idle_ticks: u32,
    /// Aggregate crew stats (size/morale/fatigue), for the details panel.
    pub crew: ShipCrewSnapshot,
}

/// Crew section of `ShipSnapshot`. Small-enough to inline; Godot displays
/// it on the ship details panel. Godot reads `current_task` to render
/// "3 piloting, 1 eating" style labels; `skills` is shown on mission
/// eligibility tooltips.
#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipCrewSnapshot {
    pub size: u32,
    /// Rounded for UI display — underlying state is f32 for smooth decay.
    pub morale: u8,
    pub fatigue: u8,
    pub hunger: u8,
    pub health: u8,
    pub current_task: &'static str,
    pub wages_credits: i64,
    /// Optional skills map (nav/eng/trade/combat), defaulting to None when
    /// the ship hasn't had a ShipCrewSkills component attached yet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skills: Option<ShipCrewSkillsSnapshot>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ShipCrewSkillsSnapshot {
    pub navigation: u8,
    pub engineering: u8,
    pub trading: u8,
    pub combat: u8,
}

impl ShipSnapshot {
    #[allow(clippy::too_many_arguments)]
    pub fn build(
        identity: &ShipIdentity,
        position: &ShipPosition,
        transit: &ShipTransit,
        cargo: &ShipCargo,
        fuel: &ShipFuel,
        economy: &ShipEconomy,
        ai: &ShipAI,
        lifecycle: &ShipLifecycle,
        crew: Option<&ShipCrew>,
        skills: Option<&ShipCrewSkills>,
    ) -> Self {
        let cargo_map: HashMap<String, u32> = cargo
            .cargo
            .iter()
            .map(|(c, &qty)| (c.as_str().to_string(), qty))
            .collect();
        let crew_snap = crew
            .map(|c| ShipCrewSnapshot {
                size: c.size,
                morale: c.morale.round().clamp(0.0, 255.0) as u8,
                fatigue: c.fatigue.round().clamp(0.0, 255.0) as u8,
                hunger: c.hunger.round().clamp(0.0, 255.0) as u8,
                health: c.health.round().clamp(0.0, 255.0) as u8,
                current_task: c.current_task.as_str(),
                wages_credits: c.wages_credits,
                skills: skills.map(|s| ShipCrewSkillsSnapshot {
                    navigation: s.navigation,
                    engineering: s.engineering,
                    trading: s.trading,
                    combat: s.combat,
                }),
            })
            .unwrap_or_default();
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            class: identity.class.clone(),
            faction_id: identity.faction_id.clone(),
            location_name: position.location_name.clone(),
            docked: position.docked_at.is_some(),
            transit: transit.transit.clone(),
            cargo: cargo_map,
            cargo_capacity: cargo.capacity,
            fuel: fuel.fuel,
            fuel_capacity: fuel.fuel_capacity,
            credits: economy.credits,
            current_goal: ai.current_goal.clone(),
            active_contract_id: economy.active_contract_id.clone(),
            bt_action: ai.current_bt.as_ref().and_then(|bt| bt.current_action()),
            position: super::Position::from(position.position),
            broke_strikes: lifecycle.broke_strikes,
            hoard_strikes: lifecycle.hoard_strikes,
            idle_ticks: lifecycle.idle_ticks,
            crew: crew_snap,
        }
    }
}

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
use crate::world::{pathfinder::{LegKind, PathfinderCtx}, registry::WorldRegistry, travel};
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

const FUEL_CRITICAL_FRACTION: f32 = 0.25;
const MIN_TRADE_MARGIN: f32 = 0.10; // 10% minimum margin
const TRADE_QTY_DEFAULT: u32 = 50;

// --- Crew constants (match Elixir CrewComplement rates) ---

/// Base per-tick hunger gain (before tick_scale). Elixir `@hunger_rate 2`.
pub const CREW_HUNGER_RATE_BASE: f32 = 2.0;
/// Base per-tick fatigue gain while active (not resting/idle).
pub const CREW_FATIGUE_RATE_ACTIVE_BASE: f32 = 1.0;
/// Base per-tick fatigue recovery while resting (negative = recovery).
pub const CREW_FATIGUE_RATE_REST_BASE: f32 = -5.0;
/// Base per-tick morale decay toward 50.
pub const CREW_MORALE_DECAY_BASE: f32 = 0.5;
/// Base morale recovery bump applied docked/resting (per check interval).
pub const CREW_MORALE_RECOVERY_DOCKED: f32 = 3.0;
pub const CREW_MORALE_RECOVERY_RESTING: f32 = 5.0;

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
    use crate::simulation::lod::AgentLod;
    let mut active: std::collections::HashMap<hecs::Entity, u32> =
        std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<&mut AgentLod>();
        for (e, lod) in lod_q.iter() {
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
    observe_prices(world, tick, &active);
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
        // While docked, the station provides food and lodging for the
        // crew — hunger falls and fatigue recovers even without an
        // explicit Rest/Eat task. Without this, ships on long trade
        // routes starve their crews between ports, morale drops below
        // 35, and the planner permanently picks `rest_crew` over the
        // contract board — contracts never get accepted.
        let hunger_delta = if ctx.docked {
            -CREW_HUNGER_RATE_BASE * effective_scale
        } else {
            CREW_HUNGER_RATE_BASE * effective_scale
        };
        crew.hunger = (crew.hunger + hunger_delta).clamp(0.0, 100.0);
        let fatigue_delta = match crew.current_task {
            CrewTask::Resting => CREW_FATIGUE_RATE_REST_BASE * effective_scale,
            CrewTask::Idle if !ctx.in_transit => -1.0 * effective_scale,
            _ if ctx.docked => -2.0 * effective_scale, // docked recovery
            _ => CREW_FATIGUE_RATE_ACTIVE_BASE * effective_scale,
        };
        crew.fatigue = (crew.fatigue + fatigue_delta).clamp(0.0, 100.0);

        // --- 2. Morale check (every 5×mult ticks) ---
        if morale_check_interval > 0 && tick % morale_check_interval == 0 {
            let penalty: f32 = if crew.hunger > CREW_HUNGER_MORALE_PENALTY {
                -3.0
            } else if crew.fatigue > CREW_FATIGUE_MORALE_PENALTY {
                -2.0
            } else if crew.health < 50.0 {
                -4.0
            } else {
                0.0
            };
            // Docked + Resting gives the biggest bump; docked-alone and
            // in-transit-but-Resting both give the medium recovery.
            let recovery: f32 = if ctx.docked && crew.current_task == CrewTask::Resting {
                CREW_MORALE_RECOVERY_RESTING
            } else if ctx.docked || crew.current_task == CrewTask::Resting {
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
    use crate::agents::facility::{facility_offset_position, FacilityIdentity, FacilityLocation};

    // Snapshot body positions for location→position lookups.
    let body_positions: std::collections::HashMap<i64, (f32, f32)> = world
        .query::<(
            &crate::agents::celestial_body::BodyIdentity,
            &crate::agents::celestial_body::BodyOrbit,
        )>()
        .iter()
        .map(|(_e, (id, orbit))| (id.db_id, orbit.universe_position()))
        .collect();

    // Pick one "primary" facility id per location (first by hecs iteration
    // order — stable within a run). Ships aim at this facility's offset
    // position so they visually arrive at the station, not at the planet
    // center. The snapshot layer uses the same `facility_offset_position`
    // function so the ship and the station agree on where the station is.
    let mut primary_facility_by_location: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for (_e, (fac_id, fac_loc)) in world.query::<(&FacilityIdentity, &FacilityLocation)>().iter() {
        primary_facility_by_location
            .entry(fac_loc.location_name.clone())
            .or_insert_with(|| fac_id.id.clone());
    }

    let location_to_pos = |loc: &str| -> Option<(f32, f32)> {
        let info = registry.locations.get(loc)?;
        let body_pos = body_positions.get(&info.celestial_body_id).copied()?;
        // If there's a facility at this location, target its offset position
        // (where the client renders the station). Otherwise fall back to
        // body center (locations with no facility still need a position).
        if let Some(fac_id) = primary_facility_by_location.get(loc) {
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
fn observe_prices(world: &mut hecs::World, tick: u64, active: &ShipLodGate) {
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

    for (e, (position, memory)) in world.query_mut::<(&ShipPosition, &mut ShipMemory)>() {
        // LOD gate — LOD'd-out ships skip the price scan this round.
        // Knowledge is slightly stale but not incorrect; the ship's
        // memory will refresh on its next fire.
        if !active.contains_key(&e) {
            continue;
        }
        if let Some(loc) = &position.location_name {
            if let Some(prices) = market_prices.get(loc) {
                let entry = memory.price_knowledge.entry(loc.clone()).or_default();
                for (&commodity, &price) in prices {
                    entry.insert(commodity, PriceMemory { price, tick });
                }
            }
        }
    }
}

/// Find the best profitable trade route from memory.
pub fn best_trade_route(memory: &ShipMemory) -> Option<(Commodity, String, String, f32)> {
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
                    let margin = (hi - lo) / lo.max(1.0);
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

        let needs_plan = ai.current_bt.is_none();
        if needs_plan {
            let (goal, bt) = plan_goal(
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
            );
            ai.current_goal = goal.into();
            ai.current_bt = bt;
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

            match status {
                BtStatus::Running => ai.current_bt = Some(bt),
                BtStatus::Success | BtStatus::Failure => {
                    // Plan done — clear. Next tick replans.
                    ai.current_bt = None;
                }
            }
        }

        lifecycle.dirty = true;
    }
}

/// Planner: pick a goal + build its BT.
///
/// Rule order:
/// 1. Crew morale critical → rest_crew BT (shore leave)
/// 2. Fuel critical → refuel BT
/// 3. Cargo onboard → sell_cargo BT (unload before replanning)
/// 4. Posted contract matching the ship's capacity and price memory → fulfill_delivery BT
/// 5. Known profitable trade route → trade_run BT
/// 6. Else → idle
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
) -> (&'static str, Option<BtNode<ShipAction>>) {
    let at_loc = match &position.location_name {
        Some(l) => l.clone(),
        None => return ("idle", Some(BtNode::action(ShipAction::Idle))),
    };

    // 1. Crew morale critical
    if let Some(c) = crew {
        if c.morale < CREW_REST_TRIGGER {
            return ("rest_crew", Some(build_rest_crew_bt()));
        }
    }

    // 2. Fuel critical
    if fuel.fraction() < FUEL_CRITICAL_FRACTION {
        return ("refuel", Some(build_refuel_bt()));
    }

    // 3. Cargo onboard — sell
    if cargo.used() > 0 {
        return ("sell_cargo", Some(build_sell_cargo_bt()));
    }

    // 4. Contract?
    if let Some(bt) = try_plan_contract(
        &at_loc,
        cargo,
        economy,
        memory,
        contracts,
        ship_id,
        registry,
        gate_pairs,
    ) {
        return ("fulfill_delivery", Some(bt));
    }

    // 5. Speculative trade route
    if let Some((commodity, buy_loc, sell_loc, _margin)) = best_trade_route(memory) {
        let bt = build_trade_run_bt(
            &at_loc, &buy_loc, &sell_loc, commodity, registry, gate_pairs,
        );
        return ("trade_run", Some(bt));
    }

    ("idle", Some(BtNode::action(ShipAction::Idle)))
}

/// Try to find a profitable fulfill plan from the board. Handles both
/// delivery contracts (ship must pre-buy the commodity at source, must
/// profit after cost) and passenger / courier contracts (no buy step —
/// the ship just shuttles between source and destination).
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
) -> Option<BtNode<ShipAction>> {
    use crate::economy::contracts::ContractType;

    #[derive(Clone)]
    struct Candidate {
        id: String,
        source: String,
        destination: String,
        commodity: Commodity,
        qty: u32,
        payment: i64,
        cost: i64,
        kind: ContractType,
    }
    let mut best: Option<Candidate> = None;
    let debugging = std::env::var("SIM_DEBUG_CONTRACTS").is_ok();
    if debugging {
        let posted_total = contracts.posted().len();
        let count = contracts.posted_for_ship(&economy.faction_reputation).len();
        eprintln!(
            "[contract-debug] ship={} cr={} cap={} at={} posted_total={} visible={}",
            _ship_id, economy.credits, cargo.capacity, at_loc, posted_total, count
        );
    }

    for c in contracts.posted_for_ship(&economy.faction_reputation) {
        // Passenger / courier / crew-mission contracts don't occupy cargo
        // slots — treat them as "hop-around" jobs in the planner.
        let is_passenger = c.contract_type == ContractType::Passenger;
        let is_courier = c.contract_type == ContractType::Courier;
        let is_mission = c.contract_type == ContractType::CrewMission;
        if !is_passenger && !is_mission && c.quantity > cargo.capacity {
            if debugging {
                eprintln!(
                    "[contract-debug]   skip {}: qty {} > cap {}",
                    c.id, c.quantity, cargo.capacity
                );
            }
            continue;
        }

        let buy_cost: i64 = if is_passenger || is_courier || is_mission {
            // No pre-buy for these kinds. Passenger pickup is implicit;
            // courier's cargo is supplied by the poster; crew missions
            // have no cargo at all — the ship just dwells at the posting
            // station for the mission's duration_ticks and collects pay.
            0
        } else {
            let src_price = memory
                .price_knowledge
                .get(&c.source_location)
                .and_then(|m| m.get(&c.commodity))
                .map(|p| p.price);
            match src_price {
                Some(p) => (p * c.quantity as f32) as i64,
                None => {
                    if debugging {
                        eprintln!(
                            "[contract-debug]   skip {}: no price memory for {:?} at {}",
                            c.id, c.commodity, c.source_location
                        );
                    }
                    continue;
                }
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
            if debugging {
                eprintln!(
                    "[contract-debug]   skip {}: cost {} >= pay {} (buy={} gate={})",
                    c.id, cost, c.payment, buy_cost, gate_fees
                );
            }
            continue;
        }
        if economy.credits < cost {
            if debugging {
                eprintln!(
                    "[contract-debug]   skip {}: credits {} < cost {}",
                    c.id, economy.credits, cost
                );
            }
            continue;
        }
        if debugging {
            eprintln!(
                "[contract-debug]   ok {}: {:?} qty={} {} -> {} cost={} pay={} profit={}",
                c.id, c.contract_type, c.quantity, c.source_location,
                c.destination_location, cost, c.payment, c.payment - cost
            );
        }
        let profit = c.payment - cost;
        let better = best
            .as_ref()
            .is_none_or(|b| profit > (b.payment - b.cost));
        if better {
            best = Some(Candidate {
                id: c.id.clone(),
                source: c.source_location.clone(),
                destination: c.destination_location.clone(),
                commodity: c.commodity,
                qty: c.quantity,
                payment: c.payment,
                cost,
                kind: c.contract_type,
            });
        }
    }
    let cand = best?;

    // Build the BT. Passenger/courier variants skip the Buy step;
    // CrewMission is a dwell-at-station job (Dock → Rest N ticks → Deliver).
    match cand.kind {
        ContractType::CrewMission => Some(build_fulfill_crew_mission_bt(
            at_loc,
            &cand.source,
            cand.id,
            registry,
            gate_pairs,
        )),
        ContractType::Passenger | ContractType::Courier => Some(build_fulfill_passenger_bt(
            at_loc,
            &cand.source,
            &cand.destination,
            cand.id,
            registry,
            gate_pairs,
        )),
        _ => Some(build_fulfill_delivery_bt(
            at_loc,
            &cand.source,
            &cand.destination,
            cand.commodity,
            cand.qty,
            cand.id,
            registry,
            gate_pairs,
        )),
    }
}

/// Build a crew-mission BT. Travel to the station, dock, refuel, rest
/// (the dwell — Rest returns Running until morale >= target, which
/// approximates the mission's duration_ticks). Then Deliver claims the
/// payout; Undock.
fn build_fulfill_crew_mission_bt(
    current: &str,
    station: &str,
    contract_id: String,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps: Vec<BtNode<ShipAction>> = Vec::with_capacity(8);
    steps.push(BtNode::action(ShipAction::AcceptContract {
        contract_id: contract_id.clone(),
    }));
    for a in route_actions(current, station, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Refuel));
    steps.push(BtNode::action(ShipAction::Rest));
    steps.push(BtNode::action(ShipAction::DeliverCargo { contract_id }));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    BtNode::sequence(steps)
}

/// Build a passenger/courier BT. No Buy step; the ship just hops between
/// source and destination and collects payment on Deliver.
fn build_fulfill_passenger_bt(
    current: &str,
    source: &str,
    destination: &str,
    contract_id: String,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps: Vec<BtNode<ShipAction>> = Vec::with_capacity(12);
    steps.push(BtNode::action(ShipAction::AcceptContract {
        contract_id: contract_id.clone(),
    }));
    for a in route_actions(current, source, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Refuel));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    for a in route_actions(source, destination, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::DeliverCargo { contract_id }));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    BtNode::sequence(steps)
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

/// Build a trade_run BT. Start at `current`, visit `buy_loc`, buy `commodity`,
/// travel to `sell_loc`, sell, end at sell_loc.
///
/// If `current == buy_loc`, skip the initial travel leg.
fn build_trade_run_bt(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps = Vec::with_capacity(12);
    for a in route_actions(current, buy_loc, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Refuel));
    steps.push(BtNode::action(ShipAction::Buy { commodity, qty: TRADE_QTY_DEFAULT }));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    for a in route_actions(buy_loc, sell_loc, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::SellAll));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    BtNode::sequence(steps)
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
    registry: &WorldRegistry,
    gate_pairs: &StdHashMap<String, String>,
) -> BtNode<ShipAction> {
    let mut steps: Vec<BtNode<ShipAction>> = Vec::with_capacity(16);
    steps.push(BtNode::action(ShipAction::AcceptContract {
        contract_id: contract_id.clone(),
    }));
    for a in route_actions(current, source, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Refuel));
    steps.push(BtNode::action(ShipAction::Buy { commodity, qty: quantity }));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    for a in route_actions(source, destination, registry, gate_pairs) {
        steps.push(BtNode::action(a));
    }
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_ARRIVE_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::DeliverCargo { contract_id }));
    steps.push(BtNode::action(ShipAction::DockDwell { seconds: DOCK_DEPART_DWELL_SECS }));
    steps.push(BtNode::action(ShipAction::Undock));
    BtNode::sequence(steps)
}

// --- Action executor (the dispatch closure's body) ---

#[allow(clippy::too_many_arguments)]
fn execute_ship_action(
    action: &ShipAction,
    entity: hecs::Entity,
    ship_id: &str,
    crew: &mut ShipCrew,
    position: &mut ShipPosition,
    transit: &mut ShipTransit,
    cargo: &mut ShipCargo,
    fuel: &mut ShipFuel,
    economy: &mut ShipEconomy,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    commands: &mut CommandBuffer,
    tick: u64,
    config: &crate::simulation::config::TickConfig,
    _bb: &mut Blackboard,
) -> BtStatus {
    match action {
        ShipAction::Idle => BtStatus::Success,

        ShipAction::DockDwell { seconds } => {
            // Wall-clock timed dwell. Uses TPS (ticks_per_second) directly
            // so `seconds` always means real seconds at the pad, regardless
            // of `world_speed`. `economy.dock_dwell_start_tick` is set on
            // first entry and cleared on completion so a BT re-tick of the
            // same node continues its countdown instead of restarting.
            let total_ticks = (*seconds as u64) * config.ticks_per_second as u64;
            let start = match economy.dock_dwell_start_tick {
                Some(t) => t,
                None => {
                    economy.dock_dwell_start_tick = Some(tick);
                    tick
                }
            };
            if tick.saturating_sub(start) >= total_ticks {
                economy.dock_dwell_start_tick = None;
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Rest => {
            // Returns Running until morale has recovered to
            // CREW_REST_TARGET. `tick_crew` handles the actual recovery
            // via CrewTask::Resting (triggered automatically when fatigue
            // is high).
            if crew.morale >= CREW_REST_TARGET {
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Dock => {
            // Emit a RequestDock command. The apply phase looks up the
            // primary facility at this location, checks capacity, deducts
            // the docking fee, and appends this ship entity to the
            // facility's `docked_ships` list. We return Success
            // immediately — if the facility rejects the dock (full or
            // fee too high), the refuel/sell actions that follow will
            // simply fail softly and the ship moves on.
            let loc = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            commands.push(SimCommand::RequestDock {
                ship: entity,
                facility_location: loc,
            });
            BtStatus::Success
        }

        ShipAction::Undock => {
            // Release our slot on the facility's docked_ships list.
            // Clear our own docked_at in-place so we don't re-request dock
            // next tick before the apply phase runs.
            if let Some(loc) = position.location_name.clone() {
                commands.push(SimCommand::ReleaseDock {
                    ship: entity,
                    facility_location: loc,
                });
            }
            position.docked_at = None;
            BtStatus::Success
        }

        ShipAction::Refuel => {
            // Multi-tick refuel. Each call drains one REFUEL_UNITS_PER_TICK
            // chunk from the facility's fuel reserves and charges the ship.
            // Returns Running until the tank is full, then Success. If the
            // ship can't afford the next increment, returns Failure so the
            // BT falls through to a different plan (station job, etc.).
            use crate::agents::facility::{REFUEL_PRICE_PER_UNIT, REFUEL_UNITS_PER_TICK};
            if fuel.fuel >= fuel.fuel_capacity - 0.001 {
                return BtStatus::Success;
            }
            let loc = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let amount = REFUEL_UNITS_PER_TICK.min(fuel.fuel_capacity - fuel.fuel);
            let payment = (amount.ceil() as i64) * REFUEL_PRICE_PER_UNIT;
            if economy.credits < payment {
                return BtStatus::Failure;
            }
            fuel.fuel += amount;
            economy.credits -= payment;
            commands.push(SimCommand::FacilityRefuel {
                ship: entity,
                facility_location: loc,
                amount,
                payment,
            });
            if fuel.fuel >= fuel.fuel_capacity - 0.001 {
                BtStatus::Success
            } else {
                BtStatus::Running
            }
        }

        ShipAction::Travel { destination } => {
            // If we're already at the destination, step succeeds immediately
            if position.location_name.as_deref() == Some(destination.as_str()) {
                return BtStatus::Success;
            }
            // If already in transit, return Running until arrival
            if let Some(t) = &transit.transit {
                if tick >= t.arrival_tick {
                    // Arrival handled by advance_transits; this is the step completion
                    return BtStatus::Success;
                }
                return BtStatus::Running;
            }
            // Start the transit
            let from = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let distance = registry
                .travel_distance(&from, destination)
                .or_else(|| registry.travel_distance(destination, &from))
                .unwrap_or(60);
            let arrival = travel::arrival_tick(tick, distance, fuel.speed_modifier, config);
            transit.transit = Some(Transit {
                from,
                to: destination.clone(),
                departure_tick: tick,
                arrival_tick: arrival,
                departure_position: Some(position.position),
                distance_total: distance as f32,
                distance_travelled: 0.0,
            });
            position.location_name = None;
            position.docked_at = None;
            BtStatus::Running
        }

        ShipAction::Buy { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let want = affordable_quantity(economy.credits, price, cargo.free()).min(*qty);
            if want == 0 {
                return BtStatus::Failure;
            }
            let cost = (price * want as f32) as i64;
            economy.credits -= cost;
            *cargo.cargo.entry(*commodity).or_insert(0) += want;
            cargo.cargo_age.insert(*commodity, tick);
            commands.push(SimCommand::RemoveSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: want as f32,
            });
            // A successful trade grows the crew's trading skill by 1 (cap 100).
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "trading",
                amount: 1,
            });
            crew.current_task = CrewTask::Loading;
            BtStatus::Success
        }

        ShipAction::Sell { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let have = cargo.cargo.get(commodity).copied().unwrap_or(0);
            let amount = if *qty == 0 { have } else { (*qty).min(have) };
            if amount == 0 {
                return BtStatus::Failure;
            }
            let revenue = (price * amount as f32) as i64;
            economy.credits += revenue;
            let new_remaining = have - amount;
            if new_remaining == 0 {
                cargo.cargo.remove(commodity);
                cargo.cargo_age.remove(commodity);
            } else {
                cargo.cargo.insert(*commodity, new_remaining);
            }
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: amount as f32,
            });
            BtStatus::Success
        }

        ShipAction::SellAll => {
            // Multi-tick unload — each call sells one commodity from the
            // hold. Returns Running if more cargo remains after selling
            // this commodity, Success when the hold is empty. Makes a
            // full unload visibly take N ticks where N = distinct
            // commodities in cargo.
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let prices = match memory.price_knowledge.get(&at) {
                Some(p) => p,
                None => return BtStatus::Failure,
            };
            // Pick a deterministic commodity (lowest as_str order) so
            // repeated calls progress through the hold in a stable order.
            let next = cargo
                .cargo
                .iter()
                .filter(|(_, &q)| q > 0)
                .filter(|(c, _)| prices.contains_key(c))
                .map(|(&c, &q)| (c, q))
                .min_by_key(|(c, _)| c.as_str());
            let (commodity, qty) = match next {
                Some(pair) => pair,
                None => return BtStatus::Success, // nothing sellable left
            };
            let price = prices
                .get(&commodity)
                .map(|pm| pm.price)
                .unwrap_or(0.0);
            let revenue = (price * qty as f32) as i64;
            economy.credits += revenue;
            cargo.cargo.remove(&commodity);
            cargo.cargo_age.remove(&commodity);
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity,
                quantity: qty as f32,
            });
            crew.current_task = CrewTask::Unloading;
            // Running if more cargo remains; otherwise Success.
            if cargo.cargo.values().any(|&q| q > 0) {
                BtStatus::Running
            } else {
                BtStatus::Success
            }
        }

        ShipAction::AcceptContract { contract_id } => {
            // Set the ship's active contract (own state) and emit a command
            // that the engine's apply phase will use to mutate the board.
            economy.active_contract_id = Some(contract_id.clone());
            commands.push(SimCommand::AcceptContract {
                ship: entity,
                ship_id: ship_id.to_string(),
                contract_id: contract_id.clone(),
            });
            BtStatus::Success
        }

        ShipAction::PickupCargo { .. } => {
            // Phase 8b doesn't use this variant (pickup is implicit via Buy).
            // Kept for future "pre-reserved cargo" contracts in Phase 8c.
            BtStatus::Success
        }

        ShipAction::GateJump { src_gate, dest_gate } => {
            // Must be at the source gate's location.
            if position.location_name.as_deref() != Some(src_gate.as_str()) {
                return BtStatus::Failure;
            }
            // Optimistic client-side fee estimate — the gate might charge
            // a different amount in apply, but this prevents the ship
            // from emitting jumps it clearly can't afford. Conservative
            // default fee of 300 (base flat 200 + some cargo surcharge).
            // The apply phase does the real deduction.
            if economy.credits < 50 {
                return BtStatus::Failure;
            }
            commands.push(SimCommand::RequestGateJump {
                ship: entity,
                src_gate_location: src_gate.clone(),
                dest_gate_location: dest_gate.clone(),
            });
            // Speculatively update our local position to the dest gate —
            // apply phase will confirm. This keeps the BT moving forward
            // this tick rather than stalling for one tick on every jump.
            position.location_name = Some(dest_gate.clone());
            position.docked_at = None;
            BtStatus::Success
        }

        ShipAction::DeliverCargo { contract_id } => {
            // Ship must be at a location (destination) and must have cargo.
            // The engine apply phase will: pay the ship, reduce cargo, add
            // supply at the destination market, and mark the contract Paid.
            if position.location_name.is_none() {
                return BtStatus::Failure;
            }
            commands.push(SimCommand::DeliverContract {
                ship: entity,
                contract_id: contract_id.clone(),
            });
            // Navigation + trading skill bumps for a successful delivery.
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "navigation",
                amount: 1,
            });
            commands.push(SimCommand::GrantCrewXp {
                ship: entity,
                skill: "trading",
                amount: 1,
            });
            economy.active_contract_id = None;
            crew.current_task = CrewTask::Unloading;
            BtStatus::Success
        }
    }
}

fn affordable_quantity(credits: i64, price: f32, capacity: u32) -> u32 {
    if price <= 0.0 || credits <= 0 {
        return 0;
    }
    let by_credits = (credits as f32 / price) as u32;
    by_credits.min(capacity)
}


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
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("belt".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 50.0, tick: 1 });
        memory.price_knowledge.insert("earth".into(), b);
        let route = best_trade_route(&memory).unwrap();
        assert_eq!(route.0, Commodity::Ore);
        assert_eq!(route.1, "belt");
        assert_eq!(route.2, "earth");
    }

    #[test]
    fn best_trade_route_none_for_thin_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("a".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 105.0, tick: 1 });
        memory.price_knowledge.insert("b".into(), b);
        assert!(best_trade_route(&memory).is_none());
    }
}
