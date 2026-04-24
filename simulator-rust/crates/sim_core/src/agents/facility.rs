//! Facility components.

use crate::economy::commodities::Commodity;
use hecs::Entity;
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone)]
pub struct FacilityIdentity {
    pub db_id: i64,
    pub id: String,                  // "facility-earth-station"
    pub name: String,
    pub facility_type: String,       // station, refinery, farm, etc.
    pub faction_id: String,
    pub body_id: String,
}

/// Spatial anchor.
#[derive(Debug, Clone)]
pub struct FacilityLocation {
    pub location_id: i64,
    pub location_name: String,
}

/// Operations — docking, condition, finances.
#[derive(Debug, Clone)]
pub struct FacilityOperations {
    pub docking_capacity: u32,
    pub services: Vec<String>,
    pub condition: f32,      // 0.0–1.0
    pub reputation: i32,     // 0–100
    pub credits: i64,
    pub dirty: bool,
    /// Bundle (S): set true when condition crossed
    /// `FACILITY_STARVING_CONDITION` and a `facility_starving`
    /// event was emitted. Cleared when condition recovers above
    /// `FACILITY_STARVING_RECOVERY` so a later slide into the
    /// same state re-emits the event. Prevents duplicate events
    /// each tick while condition hovers near the threshold.
    pub starving_notified: bool,
}

/// Bundle (S): condition below this → emit `facility_starving`
/// event and set `starving_notified`. Tracks the point where
/// self-repair has failed (which is the point the ship planner
/// starts preferring alternate docks).
pub const FACILITY_STARVING_CONDITION: f32 = 0.3;

/// Bundle (S): condition above this → clear `starving_notified`.
/// Hysteresis window with `FACILITY_STARVING_CONDITION` so a
/// jittering condition doesn't emit repeated events.
pub const FACILITY_STARVING_RECOVERY: f32 = 0.5;

impl FacilityOperations {
    pub fn has_service(&self, service: &str) -> bool {
        self.services.iter().any(|s| s == service)
    }
}

/// Lifecycle counters — level/XP, abandonment tracking, repair cooldown.
/// Kept separate from `FacilityOperations` so the hot recipe-tick path
/// doesn't load these rarely-changing fields into cache.
///
/// Matches Elixir `FacilityAgent` state fields:
///   `level`, `xp`, `abandoned`, `abandon_counter`.
#[derive(Debug, Clone)]
pub struct FacilityLifecycle {
    /// 1..=FACILITY_LEVEL_CAP. Higher level → more recipe batches per cycle.
    pub level: u8,
    /// Earned each recipe execution; spent to cross `level × 100` threshold.
    pub xp: u32,
    /// Ticks where {condition<0.1, tools==0, credits<100} all hold. Resets
    /// to 0 if any condition becomes false; flips `abandoned` at
    /// `FACILITY_ABANDON_THRESHOLD_TICKS`.
    pub abandon_counter: u32,
    /// When true, `tick_facilities` skips this facility entirely. Renders
    /// as grey/dim on Godot (services list gets cleared in the snapshot).
    pub abandoned: bool,
    pub dirty: bool,
}

/// Jump-gate pair info. Attached only to facilities whose
/// `facility_type == "gate"`. Links this gate to its counterpart in
/// another system and carries the pricing + throughput knobs.
///
/// **Fee model**: `flat_fee + per_cargo_unit × ship.cargo.used()`. Small
/// ships with light cargo pay close to the flat fee; loaded haulers pay
/// more. A ship that can't afford the fee fails its plan and has to
/// pick a shorter route — the point being that gate travel isn't
/// automatically worth it for every contract.
///
/// **Throughput** is the number of ships the gate can jump per tick.
/// A queue (Phase 18+) will back up when saturated; MVP drops the cap
/// so a popular trade lane has traffic delays. Today the field is
/// stored but the queue logic is deferred.
#[derive(Debug, Clone)]
pub struct GateLink {
    /// Agent-id of the paired gate on the other side. Mirror-paired —
    /// both entries point at each other.
    pub paired_gate_id: String,
    /// Flat fee in credits every ship pays to transit.
    pub fee_flat: i64,
    /// Additional credits per unit of cargo currently on board.
    pub fee_per_cargo_unit: i64,
    /// Max simultaneous jumpers per tick. Queue when exceeded.
    /// Deferred — not yet enforced; seed conservative defaults.
    pub throughput_cap: u32,
}

impl FacilityLifecycle {
    pub fn new() -> Self {
        Self {
            level: 1,
            xp: 0,
            abandon_counter: 0,
            abandoned: false,
            dirty: false,
        }
    }

    /// XP required to ding to `level + 1`. Matches Elixir `level * 100`.
    pub fn next_level_threshold(&self) -> u32 {
        self.level as u32 * 100
    }
}

impl Default for FacilityLifecycle {
    fn default() -> Self {
        Self::new()
    }
}

/// Storage: resource reserves + currently docked ships + pending deliveries.
#[derive(Debug, Clone, Default)]
pub struct FacilityStorage {
    pub reserves: HashMap<Commodity, f32>,
    pub docked_ships: Vec<Entity>,
    pub pending_deliveries: Vec<String>, // contract ids
    /// FIFO dock queue. A ship whose `RequestDock` apply would have
    /// been rejected for capacity now gets pushed here; subsequent
    /// `RequestDock` emits from that ship admit it once it reaches
    /// the head AND a slot frees up. Without this, a waiting ship
    /// could get jumped by a later arrival — ship #1 sits outside
    /// while ships #2..N fire RequestDock the same tick a slot
    /// opens and any of them wins the race.
    pub dock_queue: Vec<Entity>,
}

impl FacilityStorage {
    pub fn has_dock_space(&self, capacity: u32) -> bool {
        self.docked_ships.len() < capacity as usize
    }
}

/// Facility subsystem fitting (Phase 18e). Parallel of `ShipFitting`
/// but with 2 slots: Production (recipe output multiplier) +
/// Automation (max-batches bonus). Present on every non-gate
/// facility; derived stats are baked on mutation.
///
/// Gates skip it because they don't run recipes — the loader and
/// admin spawn paths filter by facility type.
#[derive(Debug, Clone)]
pub struct FacilityFitting {
    pub slots: [Option<&'static str>; crate::facility_modules::NUM_FACILITY_SLOTS],
    pub derived: crate::facility_modules::FacilityDerivedStats,
    /// Set whenever slots change — makes the persistence flush
    /// know to include this facility's row.
    pub dirty: bool,
}

impl Default for FacilityFitting {
    fn default() -> Self {
        Self::new_default()
    }
}

impl FacilityFitting {
    pub fn new_default() -> Self {
        let slots = crate::facility_modules::default_fitting();
        let derived = crate::facility_modules::combine_effects(&slots);
        Self {
            slots,
            derived,
            dirty: false,
        }
    }

    pub fn from_slugs(
        raw: &[Option<String>; crate::facility_modules::NUM_FACILITY_SLOTS],
    ) -> Self {
        let mut slots: [Option<&'static str>; crate::facility_modules::NUM_FACILITY_SLOTS] =
            [None; crate::facility_modules::NUM_FACILITY_SLOTS];
        for slot in crate::facility_modules::FACILITY_SLOTS.iter().copied() {
            let i = slot.index();
            slots[i] = match &raw[i] {
                Some(s) => crate::facility_modules::intern_slug(s)
                    .or(Some(crate::facility_modules::default_for_slot(slot))),
                None => None,
            };
        }
        let derived = crate::facility_modules::combine_effects(&slots);
        Self {
            slots,
            derived,
            dirty: false,
        }
    }

    pub fn set(
        &mut self,
        slot: crate::facility_modules::FacilitySlot,
        slug: Option<&'static str>,
    ) {
        self.slots[slot.index()] = slug;
        self.derived = crate::facility_modules::combine_effects(&self.slots);
        self.dirty = true;
    }

    pub fn slot_slug(
        &self,
        slot: crate::facility_modules::FacilitySlot,
    ) -> Option<&'static str> {
        self.slots[slot.index()]
    }
}

/// Facility crew complement (Phase 19a).
///
/// Aggregate crew — a single struct on the facility entity, not
/// per-crew-member entities. That was tried in the Elixir port and
/// made crew 60% of all agents; the aggregate pattern mirrors
/// [`crate::agents::ship::ShipCrew`] and stays cheap.
///
/// Models the station's operations staff: engineers, techs, dock
/// handlers. Fed crew keep production running at full efficiency;
/// starving crew slow recipes down. The lever is `efficiency()`,
/// which is multiplied into the recipe output path alongside
/// condition + facility level.
///
/// ## Food draw
///
/// Each tick, the facility consumes `crew_count × FOOD_PER_CREW_TICK`
/// food from `FacilityStorage.reserves[Food]`. Empty reserves mean
/// no food gets consumed but hunger continues to climb — morale
/// degrades and efficiency drops. Tuned small (0.02/crew/tick) so
/// that at fleet scale (~90 facilities × ~10 avg crew) the fleet-
/// wide draw stays well under population food consumption.
///
/// ## Morale / hunger / efficiency
///
/// - `hunger` rises each tick; eating resets it
/// - `morale` drifts toward target based on hunger satisfaction
/// - `efficiency() = 0.5 + 0.5 × (morale/100)` — full morale = 1.0×
///   production, zero morale = 0.5× production. Never zero; a
///   skeleton crew keeps the lights on.
#[derive(Debug, Clone)]
pub struct FacilityCrew {
    /// Number of crew members. Seeded from facility type at spawn.
    /// Doesn't change during play yet (no hiring / firing mechanic);
    /// if we add one later, events adjust this in-place.
    pub crew_count: u16,
    /// 0..=100. Starts at 80 (cheerful open), decays when hungry.
    pub morale: f32,
    /// 0..=100. Rises per tick; `consume_meal` resets it when food
    /// is available. Above `HUNGER_MORALE_HIT_THRESHOLD` (60) the
    /// crew starts losing morale.
    pub hunger: f32,
    /// Accumulated food "credit" — we consume food from reserves
    /// per tick but per-tick draw is fractional (0.02 × crew_count),
    /// so we batch: hold fractional draw in this accumulator, debit
    /// reserves when it crosses 1.0. Keeps the reserves math on
    /// integer units even though the rate is < 1/tick.
    pub food_debt: f32,
    /// Set whenever any field changes — persistence flush reads it.
    pub dirty: bool,
}

impl FacilityCrew {
    /// Default crew count by facility type. Tuned so the fleet-wide
    /// food draw lands near our 20/tick target. Values aim for the
    /// "small but meaningful" range (4..=20) — a station's crew
    /// shouldn't rival a population in headcount.
    ///
    /// Unknown types get a conservative 6 so new facility types
    /// don't accidentally starve markets.
    pub fn default_count_for_type(facility_type: &str) -> u16 {
        match facility_type {
            "station" => 20,
            "shipyard" => 16,
            "refinery" => 12,
            "factory" => 12,
            "farm" => 6,
            "mining_rig" => 8,
            "outpost" => 6,
            // Gates are automated — no crew, no food draw. They sit
            // at locations without markets, so a staffed crew would
            // never be able to restock food. Easier to model them as
            // pure infrastructure than to invent a supply path just
            // for gate feeding.
            "gate" => 0,
            _ => 6,
        }
    }

    pub fn new_for_type(facility_type: &str) -> Self {
        Self {
            crew_count: Self::default_count_for_type(facility_type),
            morale: CREW_MORALE_START,
            hunger: 0.0,
            food_debt: 0.0,
            dirty: false,
        }
    }

    /// Production efficiency multiplier derived from morale. Range
    /// `[0.5, 1.0]`. Zero-crew facilities return 0.5 — a skeleton
    /// crew keeps things limping along rather than halting outright.
    pub fn efficiency(&self) -> f32 {
        if self.crew_count == 0 {
            return 0.5;
        }
        0.5 + 0.5 * (self.morale / 100.0)
    }
}

impl Default for FacilityCrew {
    fn default() -> Self {
        Self::new_for_type("station")
    }
}

/// Serialized form for DB + WS.
#[derive(Debug, Clone, Serialize, serde::Deserialize, Default)]
pub struct FacilityCrewSnapshot {
    pub crew_count: u16,
    pub morale: f32,
    pub hunger: f32,
    #[serde(default)]
    pub food_debt: f32,
}

impl From<&FacilityCrew> for FacilityCrewSnapshot {
    fn from(c: &FacilityCrew) -> Self {
        Self {
            crew_count: c.crew_count,
            morale: c.morale,
            hunger: c.hunger,
            food_debt: c.food_debt,
        }
    }
}

impl From<FacilityCrewSnapshot> for FacilityCrew {
    fn from(s: FacilityCrewSnapshot) -> Self {
        Self {
            crew_count: s.crew_count,
            morale: s.morale,
            hunger: s.hunger,
            food_debt: s.food_debt,
            dirty: false,
        }
    }
}

/// Shipyard module inventory (Phase 18c). One per shipyard facility.
/// `stock[slug]` is how many installable units the shipyard currently
/// has on hand. Ticks increment it via the production recipe; refits
/// decrement it when a ship installs a module.
///
/// Absent on every non-shipyard facility — the facility tick keys on
/// `facility_type == "shipyard"` before querying for it, and the refit
/// apply phase treats a missing component the same as empty stock.
#[derive(Debug, Clone, Default)]
pub struct ModuleStock {
    /// Module slug (from [`crate::modules::CATALOG`]) → units on hand.
    pub stock: HashMap<String, u32>,
    /// Set whenever stock changes so the persistence sweep knows to
    /// flush. Clear on flush, same pattern as FacilityLifecycle.dirty.
    pub dirty: bool,
}

impl ModuleStock {
    pub fn count(&self, slug: &str) -> u32 {
        self.stock.get(slug).copied().unwrap_or(0)
    }

    pub fn add(&mut self, slug: &str, qty: u32) {
        let entry = self.stock.entry(slug.to_string()).or_insert(0);
        *entry = entry.saturating_add(qty);
        self.dirty = true;
    }

    /// Remove one unit of `slug`. Returns true on success, false when
    /// stock was already empty.
    pub fn take_one(&mut self, slug: &str) -> bool {
        match self.stock.get_mut(slug) {
            Some(v) if *v > 0 => {
                *v -= 1;
                self.dirty = true;
                true
            }
            _ => false,
        }
    }
}

/// Snapshot for HTTP/WS.
///
/// Field names match what Godot reads: `type` (not `facility_type`),
/// `location` (not `location_name`), `docked_ships` as an array of ship
/// agent-ids (not just a count — `facility.gd` checks `is Array`).
#[derive(Debug, Clone, Serialize)]
pub struct FacilitySnapshot {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub facility_type: String,
    #[serde(rename = "location")]
    pub location_name: String,
    /// Body this facility sits on (e.g. "earth", "mars", "belt"). Godot's
    /// `facility.gd` reads this to group facilities under a star_system.
    pub body_id: String,
    pub faction_id: String,
    pub condition: f32,
    pub reputation: i32,
    pub credits: i64,
    /// Ship agent-ids currently docked here (e.g. `["ship-artemis-7"]`).
    /// Godot's facility.gd uses `.size()` for its docking glow animation.
    pub docked_ships: Vec<String>,
    /// Ship agent-ids waiting in the FIFO dock queue (position 0 =
    /// front of line). Populated by `apply_request_dock` when a ship
    /// tries to dock at a full facility. Godot's details panel
    /// reads this to render queue length + position for a selected
    /// ship.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dock_queue: Vec<String>,
    pub docking_capacity: u32,
    pub services: Vec<String>,
    /// Commodity → qty dict for this facility's on-hand reserves.
    /// Rendered in the details panel; reserves are kept per-facility
    /// separate from market supply.
    pub reserves: std::collections::HashMap<String, f32>,
    /// Universe-space position, inherited from the facility's body.
    pub position: super::Position,
    /// Facility level (1..=10). Higher levels run more recipe batches
    /// per cycle. Progression is XP-driven.
    pub level: u8,
    pub xp: u32,
    /// True when the facility has been broke + without tools + barely
    /// maintained for `FACILITY_ABANDON_THRESHOLD_TICKS`. Godot greys out
    /// abandoned stations and disables their services.
    pub abandoned: bool,
    /// Present only for gate facilities. Godot renders gates with a
    /// distinct model and can draw the paired-gate arc for navigation.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gate_link: Option<GateLinkSnapshot>,
    /// Module inventory for shipyards (Phase 18c). Absent on every
    /// non-shipyard; when present, maps module slug → units available.
    /// Godot's details panel shows this under "Shipyard stock".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub module_stock: Option<HashMap<String, u32>>,
    /// Installed facility subsystems (Phase 18e). Present on every
    /// non-gate facility; carries the two slots (Production +
    /// Automation) + their derived rollup so Godot can render it
    /// the same way ship subsystems are rendered.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fitting: Option<FacilityFittingSnapshot>,
    /// Crew complement (Phase 19a). Count + morale + hunger. Godot
    /// reads this in the facility details panel so players can see
    /// "station understaffed / hungry" at a glance.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub crew: Option<FacilityCrewSnapshot>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct FacilityFittingSnapshot {
    /// slot_name → module_slug (None → slot is empty).
    pub modules: HashMap<String, Option<String>>,
    pub stats: FacilityDerivedStatsSnapshot,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct FacilityDerivedStatsSnapshot {
    pub recipe_output_mult: f32,
    pub max_batches_bonus: u32,
}

impl From<&FacilityFitting> for FacilityFittingSnapshot {
    fn from(fit: &FacilityFitting) -> Self {
        let mut modules: HashMap<String, Option<String>> = HashMap::new();
        for slot in crate::facility_modules::FACILITY_SLOTS.iter().copied() {
            modules.insert(
                slot.as_str().to_string(),
                fit.slot_slug(slot).map(|s| s.to_string()),
            );
        }
        Self {
            modules,
            stats: FacilityDerivedStatsSnapshot {
                recipe_output_mult: fit.derived.recipe_output_mult,
                max_batches_bonus: fit.derived.max_batches_bonus,
            },
        }
    }
}

/// Wire-facing shape of `GateLink`. Kept flat so Godot can consume
/// without reimplementing the component type.
#[derive(Debug, Clone, Serialize)]
pub struct GateLinkSnapshot {
    pub paired_gate_id: String,
    pub fee_flat: i64,
    pub fee_per_cargo_unit: i64,
    pub throughput_cap: u32,
}

/// Radial offset (universe units) each facility sits from its body center.
/// Matches the Elixir sim's 0.15 value. Small enough that facilities visually
/// cluster around the planet, large enough to be distinct at gameplay zoom.
pub const FACILITY_ORBIT_RADIUS: f32 = 0.15;

/// Base docking fee charged when a ship docks. The final fee is scaled by
/// occupancy (busier station = higher fee) and inversely by condition
/// (run-down station = discount). Matches Elixir's `base_fee = 50`.
pub const DOCKING_FEE_BASE: i64 = 50;

/// Default flat gate transit fee. Every ship pays this on a jump.
pub const DEFAULT_GATE_FEE_FLAT: i64 = 200;
/// Default per-cargo-unit gate fee. Loaded haulers pay more; couriers
/// near-empty pay almost just the flat fee. This is the knob that
/// pressures small ships toward shorter multi-hop runs vs cross-system.
pub const DEFAULT_GATE_FEE_PER_CARGO: i64 = 2;
/// Default gate throughput (ships per tick). MVP: not enforced yet.
pub const DEFAULT_GATE_THROUGHPUT: u32 = 3;

/// Compute the transit fee a ship pays this gate based on cargo load.
pub fn gate_transit_fee(link: &GateLink, cargo_used: u32) -> i64 {
    link.fee_flat + link.fee_per_cargo_unit * cargo_used as i64
}

/// Fuel units transferred per refuel tick. Each Refuel action call drains
/// this much from the facility's reserves and adds it to the ship's tank.
/// At fuel_capacity=100 a full tank takes ~50 ticks (~6 s @ default tps=8)
/// — slow enough that you can watch the fuel gauge tick up while the
/// ship sits at the pad, which is the point.
pub const REFUEL_UNITS_PER_TICK: f32 = 2.0;

/// Price in credits per unit of fuel charged by a facility. Matches the
/// Elixir station-fuel base price. Ships pay this to refuel from a
/// facility's reserves.
pub const REFUEL_PRICE_PER_UNIT: i64 = 2;

/// Compute the docking fee the facility charges a ship.
///
/// Formula mirrors Elixir's `facility_agent.ex:request_dock`:
///     fee = base × occupancy_multiplier × (2 - condition)
/// where `occupancy_multiplier = 1 + docked_count / capacity` (full station
/// doubles the fee) and a condition of 1.0 yields a 1× multiplier while
/// 0.0 (ruin) doubles the fee.
pub fn docking_fee(
    base: i64,
    docked_count: u32,
    capacity: u32,
    condition: f32,
) -> i64 {
    if capacity == 0 {
        return base;
    }
    let occupancy_mult = 1.0 + (docked_count as f32) / (capacity as f32);
    let condition_mult = (2.0 - condition.clamp(0.0, 1.0)).max(0.5);
    ((base as f32) * occupancy_mult * condition_mult).round() as i64
}

/// Deterministic facility position around a body center.
///
/// Angle comes from a stable hash of the facility's agent id, so the same
/// facility always lands at the same spot relative to its body. Multiple
/// facilities at the same body spread out around it instead of stacking.
///
/// Shared by:
/// - `sim_server::snapshot::update_facilities` (for the published position)
/// - `sim_core::agents::ship::advance_transits` (so ships aim at the same spot)
///
/// The two callers MUST use this same function so ship transit endpoints
/// match where the client renders facilities — otherwise ships visually
/// overshoot/undershoot the station by ~0.15 units.
pub fn facility_offset_position(body_center: (f32, f32), facility_id: &str) -> (f32, f32) {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    facility_id.hash(&mut h);
    let angle_deg = (h.finish() % 360) as f32;
    let angle = angle_deg.to_radians();
    (
        body_center.0 + FACILITY_ORBIT_RADIUS * angle.cos(),
        body_center.1 + FACILITY_ORBIT_RADIUS * angle.sin(),
    )
}

impl FacilitySnapshot {
    #[allow(clippy::too_many_arguments)]
    #[allow(clippy::too_many_arguments)]
    pub fn build(
        identity: &FacilityIdentity,
        location: &FacilityLocation,
        ops: &FacilityOperations,
        storage: &FacilityStorage,
        lifecycle: Option<&FacilityLifecycle>,
        gate: Option<&GateLink>,
        module_stock: Option<&ModuleStock>,
        fitting: Option<&FacilityFitting>,
        crew: Option<&FacilityCrew>,
        position: super::Position,
        docked_ship_ids: Vec<String>,
        dock_queue_ids: Vec<String>,
    ) -> Self {
        let reserves: std::collections::HashMap<String, f32> = storage
            .reserves
            .iter()
            .map(|(c, &v)| (c.as_str().to_string(), v))
            .collect();
        let (level, xp, abandoned) = lifecycle
            .map(|l| (l.level, l.xp, l.abandoned))
            .unwrap_or((1, 0, false));
        // Abandoned stations quietly drop services so Godot stops showing
        // them as destinations; the data is still readable to ships/UI
        // that want to display "decommissioned".
        let services = if abandoned {
            Vec::new()
        } else {
            ops.services.clone()
        };
        let gate_link = gate.map(|g| GateLinkSnapshot {
            paired_gate_id: g.paired_gate_id.clone(),
            fee_flat: g.fee_flat,
            fee_per_cargo_unit: g.fee_per_cargo_unit,
            throughput_cap: g.throughput_cap,
        });
        let module_stock = module_stock.map(|m| m.stock.clone());
        let fitting_snap = fitting.map(FacilityFittingSnapshot::from);
        let crew_snap = crew.map(FacilityCrewSnapshot::from);
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            facility_type: identity.facility_type.clone(),
            location_name: location.location_name.clone(),
            body_id: identity.body_id.clone(),
            faction_id: identity.faction_id.clone(),
            condition: ops.condition,
            reputation: ops.reputation,
            credits: ops.credits,
            docked_ships: docked_ship_ids,
            dock_queue: dock_queue_ids,
            docking_capacity: ops.docking_capacity,
            services,
            reserves,
            position,
            level,
            xp,
            abandoned,
            gate_link,
            module_stock,
            fitting: fitting_snap,
            crew: crew_snap,
        }
    }
}

// ============================================================================
// Facility tick
// ============================================================================
//
// Each tick (on an interval) the facility:
//   1. Executes any recipes available for its facility_type against the
//      local market's supply (pulls inputs, pushes outputs).
//   2. If a mining_rig, extracts resources from its celestial body into
//      the local market supply.
//
// Recipes operate directly on market supply (source of truth) rather than
// a separate facility-reserves ledger — simpler and the Elixir model does
// the same effectively.

use crate::agents::celestial_body::{BodyIdentity, BodyResources};
use crate::agents::market::{MarketIdentity, MarketPricing};
use crate::economy::recipes;

/// How often facilities run recipes. Base ticks at 1x world speed = 5 ticks.
/// At default 0.25 speed (mult=32) this is every 160 ticks (~20s).
pub const RECIPE_INTERVAL_BASE: u64 = 5;
pub const MINING_INTERVAL_BASE: u64 = 5;

/// Max batches a facility can run in a single cycle. Prevents one refinery
/// from draining all ore in one tick.
pub const RECIPE_MAX_BATCHES: u32 = 20;

/// Mining yield per cycle = body_resource_richness × RESOURCE_YIELD_PER_TICK
/// Units of commodity added to market supply per cycle.
pub const MINING_YIELD_PER_CYCLE: f32 = 80.0;

// --- Phase 11c: condition / restock / contracts / leveling / abandonment ---

/// Per-tick condition loss. Matches Elixir `0.0002 * tick_scale`.
pub const CONDITION_DEGRADE_PER_TICK: f32 = 0.0002;
/// Condition below this invites self-repair if tools available.
pub const CONDITION_REPAIR_THRESHOLD: f32 = 0.8;
/// Condition bump per tool consumed during self-repair.
pub const CONDITION_REPAIR_PER_TOOL: f32 = 0.01;
/// Interval (base-ticks) at which self-repair runs. Every 20×mult ticks.
pub const REPAIR_INTERVAL_BASE: u64 = 20;

// --- Phase 19a: facility crew complement ---

/// Morale the crew spawns with. High enough that well-stocked
/// facilities start at full production efficiency; low enough that a
/// brief food outage at tick 0 causes a visible drop rather than
/// clamping at 100 for hours.
pub const CREW_MORALE_START: f32 = 80.0;

/// Fractional food units drawn from reserves per crew per base-tick.
/// Intentionally tiny — at ~90 facilities × ~10 crew average, this
/// nets to roughly 18 food/tick fleet-wide, vs ~300/tick from
/// populations. Facility crew is < 10% of total food demand.
pub const FOOD_PER_CREW_TICK: f32 = 0.02;

/// Hunger rise per base-tick (per crew). Crew hits the morale-hit
/// threshold (60) after ~200 ticks unfed at tick_scale=1, so a
/// facility can coast briefly through a food shortage without
/// immediately tanking production.
pub const CREW_HUNGER_RATE_PER_TICK: f32 = 0.3;

/// Hunger above this causes morale to slip each tick. Below it,
/// crew is content and morale drifts back toward full.
pub const HUNGER_MORALE_HIT_THRESHOLD: f32 = 60.0;

/// How fast morale moves each tick toward its target (either a
/// hunger-driven sag or a fed-crew recovery). Matches the pace of
/// ship-crew morale math loosely — recovery should be slower than
/// decay so "starving → fed" doesn't instantly snap production back.
pub const CREW_MORALE_HUNGRY_DECAY: f32 = 0.8;
pub const CREW_MORALE_RECOVERY: f32 = 0.3;

/// Morale at or below this emits the `facility_crew_starving` event.
/// Used only for UI signaling; the gameplay drag happens through
/// `efficiency()` continuously.
pub const CREW_STARVING_MORALE: f32 = 30.0;

/// Hunger reduction per meal successfully eaten. Crew eats one
/// "meal" whenever `food_debt` accumulates to ≥ 1 and there's food
/// in reserves. Meal size aligns with FOOD_PER_CREW_TICK so a fed
/// facility runs at hunger ≈ 0.
pub const CREW_MEAL_HUNGER_DECREASE: f32 = 20.0;

/// Interval (base-ticks) between crew morale checks + food draws.
/// Ties into the existing facility-tick cadence — cheap enough to
/// run every 5 base-ticks so the morale curve is smooth.
pub const FACILITY_CREW_TICK_INTERVAL_BASE: u64 = 5;

/// Reserve floor below which the restock phase tries to top up.
pub const RESERVE_RESTOCK_THRESHOLD: f32 = 100.0;
/// Reserve ceiling the restock phase targets (caps restock quantity).
pub const RESERVE_RESTOCK_TARGET: f32 = 500.0;
/// Interval (base-ticks) between restock passes.
pub const RESTOCK_INTERVAL_BASE: u64 = 20;
/// Commodities a facility tries to keep in reserve. Elixir stores fuel /
/// food / tools / water as the crew-essentials set.
pub const RESTOCK_COMMODITIES: &[Commodity] = &[
    Commodity::Fuel,
    Commodity::Food,
    Commodity::Tools,
    Commodity::Water,
];

/// Recipe input commodities a facility posts *market-supply* delivery
/// contracts for (distinct from `RESTOCK_COMMODITIES`, which are for the
/// facility's own reserves). Keyed by `facility_type`. When the local
/// market has been chronically short on one of these — meaning the
/// facility's recipes are starving — the facility posts a delivery
/// contract to pull supply in from elsewhere. Without this, mining
/// outputs pile up at the source but never reach the refiners/factories
/// that need them, and the upper-tier supply chain collapses.
///
/// Mining rigs aren't listed — they produce, not consume.
pub fn recipe_input_commodities(facility_type: &str) -> &'static [Commodity] {
    use Commodity::*;
    match facility_type {
        "refinery" => &[Ore, Gas, Fuel],
        "factory" => &[Metals, Polymers, Ice],
        "farm" => &[Water, Fuel],
        _ => &[],
    }
}

/// Interval (base-ticks) between contract-posting passes. Every 50×mult.
pub const CONTRACT_POST_INTERVAL_BASE: u64 = 50;
/// Max delivery contracts a facility can have posted at once. Bumped from
/// 2 → 4 when we added recipe-input contracts on top of crew-essential
/// contracts — otherwise refineries hit the cap posting ore and can't
/// post fuel/food contracts too.
pub const MAX_ACTIVE_DELIVERIES_PER_FACILITY: usize = 4;
/// Contract lifespan (base ticks) before Expired. Matches Elixir's 500×mult.
/// Phase 18j: trimmed from 500 → 300 so unaccepted contracts churn
/// out the board faster and get re-posted at a fresh age-escalated
/// premium. Shorter churn + payment escalation together push the
/// fleet toward actually fulfilling supply-chain deliveries
/// instead of letting prices pin at ceiling while contracts
/// expire unclaimed.
pub const FACILITY_DELIVERY_LIFESPAN_BASE: u64 = 300;
/// Baseline delivery contract quantity. Facilities now scale up from
/// this when the triggering shortage has persisted (Bundle 1.3) —
/// shallow shortages still get ~50-unit contracts that couriers can
/// handle; deep / sustained shortages get larger orders that reward
/// bigger hulls with a single trip instead of many small ones.
pub const DELIVERY_CONTRACT_QTY: u32 = 50;
/// Floor on delivery contract qty (Bundle 1.3). Even if affordability
/// caps the order size, we never post a contract below this because
/// sub-25 quantities under-price transit/gate-fuel overhead.
pub const MIN_DELIVERY_CONTRACT_QTY: u32 = 25;
/// Ceiling on delivery contract qty (Bundle 1.3). 200 units fits a
/// medium freighter in one trip and matches the top of typical ship
/// cargo capacities. Caps pathological quantities during extreme
/// shortages that would otherwise exclude every ship in the fleet.
pub const MAX_DELIVERY_CONTRACT_QTY: u32 = 200;
/// Bucket size for shortage-driven qty scaling. Every extra
/// `SHORTAGE_QTY_BUCKET_TICKS` beyond the 30-tick trigger adds 25 units
/// to the requested quantity, so a 30-tick shortage → ~50 units, a
/// 90-tick shortage → ~100 units, a 200-tick shortage → ~175 units.
pub const SHORTAGE_QTY_BUCKET_TICKS: u32 = 30;

/// Bundle 1.3: scale delivery contract quantity by how long the
/// triggering shortage has persisted. `shortage_ticks` is 0 when
/// supply is healthy and grows while the market is short, so a deeper
/// / older shortage yields a larger order. Clamped to
/// `[MIN_DELIVERY_CONTRACT_QTY, MAX_DELIVERY_CONTRACT_QTY]`.
pub fn delivery_qty_for_shortage(shortage_ticks: u32) -> u32 {
    let bonus = shortage_ticks
        .saturating_sub(30)
        .saturating_div(SHORTAGE_QTY_BUCKET_TICKS)
        .saturating_mul(25);
    DELIVERY_CONTRACT_QTY
        .saturating_add(bonus)
        .clamp(MIN_DELIVERY_CONTRACT_QTY, MAX_DELIVERY_CONTRACT_QTY)
}
/// Base payment-per-unit floor. The real payment for a contract is
/// `max(QTY × BASE, src_price × QTY × delivery_multiplier)` — the flat
/// floor only wins when source prices are unusually cheap. Tuned to 40
/// so a commodity at the price floor (1.0) still produces a reasonable
/// 2k-cr contract.
pub const DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT: i64 = 40;
/// How much shortage a market needs to show before the facility's
/// recipe-input contract fires. Lower than the crew-essentials threshold
/// because refinery starvation cascades into the tier-2/tier-3 supply
/// chain quickly; we want to react before the chain breaks.
pub const RECIPE_INPUT_SHORTAGE_THRESHOLD: u32 = 15;

/// Facility XP threshold multiplier (level × 100) — see `next_level_threshold`.
pub const FACILITY_LEVEL_CAP: u8 = 10;
/// XP granted per recipe batch executed. Elixir: +recipe_count per tick.
pub const FACILITY_XP_PER_RECIPE: u32 = 1;

/// Interval (base-ticks) for crew-mission posting attempts. Matches
/// Elixir's `maybe_post_crew_missions` cadence (one shot per facility
/// tick pass, gated by a probability check).
pub const CREW_MISSION_POST_INTERVAL_BASE: u64 = 100;
/// Fraction of facilities that post a crew mission per cycle. Keeps the
/// board from being flooded with short-burst mission fodder.
pub const CREW_MISSION_POST_PROBABILITY: f32 = 0.25;
/// Max active crew missions per facility. Elixir uses 1.
pub const CREW_MISSION_MAX_ACTIVE_PER_FACILITY: usize = 1;

/// Interval (base-ticks) for abandonment-check bumps.
pub const ABANDON_CHECK_INTERVAL_BASE: u64 = 10;

/// Interval (base-ticks) between shipyard module-production passes.
/// Chosen so that at `WORLD_SPEED=4` (mult=2) a shipyard can top up a
/// module slot inside a 30s smoke, and at default 0.25 (mult=32)
/// produces modules at a slower, harder-to-stack cadence — aligns
/// with the "retrofit is rare" design intent.
pub const MODULE_PRODUCTION_INTERVAL_BASE: u64 = 15;
/// Ticks of triple-failure (low condition + no tools + low credits) before
/// the facility flips to `abandoned = true`. Matches Elixir's `200`.
pub const FACILITY_ABANDON_THRESHOLD_TICKS: u32 = 200;

/// Type alias for the facility LOD gate — matches the ship-side one
/// (`ShipLodGate`). `Entity → skipped_ticks`. Entities not in the
/// map should skip this tick's heaviest sub-phases.
pub type FacilityLodGate = std::collections::HashMap<hecs::Entity, u32>;

/// Bundle 1.5: build the facility LOD gate for this tick. Advances
/// each facility's own `AgentLod` cursor (ship-side passes are now
/// filtered to ship entities, so facility cursors belong to us
/// here). Facilities without an `AgentLod` default to "fires every
/// tick, skipped=1" so missing-component fallback matches the ship
/// behaviour.
fn build_facility_lod_gate(world: &mut hecs::World, tick: u64) -> FacilityLodGate {
    use crate::simulation::lod::AgentLod;
    let fac_with_lod: std::collections::HashSet<hecs::Entity> = world
        .query::<(&FacilityIdentity, &AgentLod)>()
        .iter()
        .map(|(e, _)| e)
        .collect();
    let mut gate: FacilityLodGate = std::collections::HashMap::new();
    {
        let mut lod_q = world.query::<&mut AgentLod>();
        for (e, lod) in lod_q.iter() {
            if !fac_with_lod.contains(&e) {
                continue;
            }
            if let Some(skipped) = lod.try_fire(tick) {
                gate.insert(e, skipped);
            }
        }
    }
    // Fallback: facilities without an AgentLod fire every tick.
    let fac_no_lod: Vec<hecs::Entity> = world
        .query::<&FacilityIdentity>()
        .iter()
        .map(|(e, _)| e)
        .filter(|e| !fac_with_lod.contains(e))
        .collect();
    for e in fac_no_lod {
        gate.insert(e, 1);
    }
    gate
}

pub fn tick_facilities(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let mult = tick_multiplier as u64;
    let recipe_interval = RECIPE_INTERVAL_BASE * mult;
    let mining_interval = MINING_INTERVAL_BASE * mult;
    let repair_interval = REPAIR_INTERVAL_BASE * mult;
    let restock_interval = RESTOCK_INTERVAL_BASE * mult;
    let contract_interval = CONTRACT_POST_INTERVAL_BASE * mult;
    let abandon_interval = ABANDON_CHECK_INTERVAL_BASE * mult;

    // Bundle 1.5: LOD gate so off-screen facilities skip the heavy
    // sub-phases on most ticks. Built once per tick, consumed by
    // tick_recipes_and_mining for now; remaining sub-phases (restock
    // / condition / abandonment / contract-post) stay on their
    // existing global intervals because they're cheap per-facility.
    // Rate-scaling of recipe output per divisor is deferred — for
    // now off-screen facilities produce ~1/divisor of their
    // on-screen throughput, which is acceptable since the player
    // isn't looking.
    let facility_lod_gate = build_facility_lod_gate(world, tick);

    // Phase 1: condition degrade (every tick; cheap — one field write).
    tick_degrade_condition(world, tick_scale);

    // Phase 1a: dock-queue sweep. Purges entries whose ship has left
    // (location_name != this facility's location) or has been
    // despawned. Runs every 10×mult ticks — frequent enough to keep
    // queues responsive but cheap (one query + a short per-facility
    // retain). Without this, a ship that departs without docking
    // leaves a zombie at the head and every ship behind it starves.
    let queue_sweep_interval = 10 * mult;
    if queue_sweep_interval > 0 && tick % queue_sweep_interval == 0 {
        tick_dock_queue_sweep(world);
    }

    // Phase 1b (Phase 19a): crew complement — food draw, hunger,
    // morale. Runs on its own 5×mult cadence so the morale curve
    // is smooth without hammering the tick loop every frame.
    let crew_interval = FACILITY_CREW_TICK_INTERVAL_BASE * mult;
    if crew_interval > 0 && tick % crew_interval == 0 {
        tick_facility_crew(world, events, tick_scale, tick_multiplier);
    }

    // Phase 2: self-repair (every 20×mult ticks).
    if repair_interval > 0 && tick % repair_interval == 0 {
        tick_self_repair(world);
    }

    // Phase 3: abandonment check (every 10×mult ticks).
    if abandon_interval > 0 && tick % abandon_interval == 0 {
        tick_abandonment(world, events);
    }

    // Phase 4: restock reserves from local market (every 20×mult ticks).
    if restock_interval > 0 && tick % restock_interval == 0 {
        tick_restock(world);
    }

    // Phase 5: recipes + mining + XP (every 5×mult ticks).
    if tick % recipe_interval == 0 || tick % mining_interval == 0 {
        tick_recipes_and_mining(world, tick, tick_multiplier, &facility_lod_gate);
    }

    // Phase 6: post delivery + courier contracts (every 50×mult ticks).
    if contract_interval > 0 && tick % contract_interval == 0 {
        tick_post_contracts(world, contracts, tick, tick_multiplier);
    }

    // Phase 6b (Phase 18c): shipyards mint modules from local market
    // supply into their `ModuleStock`. Runs on its own interval —
    // decoupled from recipe_interval so module cadence is a separate
    // tuning knob.
    let module_production_interval = MODULE_PRODUCTION_INTERVAL_BASE * mult;
    if module_production_interval > 0 && tick % module_production_interval == 0 {
        tick_produce_modules(world);
    }

    // Phase 7: post crew missions (every 100×mult ticks, probabilistic).
    let crew_mission_interval = CREW_MISSION_POST_INTERVAL_BASE * mult;
    if crew_mission_interval > 0 && tick % crew_mission_interval == 0 {
        tick_post_crew_missions(world, contracts, tick, tick_multiplier);
    }
}

/// Phase 1: condition drifts down every tick. Abandoned facilities are
/// already dead and skip this.
fn tick_degrade_condition(world: &mut hecs::World, tick_scale: f32) {
    let delta = CONDITION_DEGRADE_PER_TICK * tick_scale;
    for (_e, (ops, life)) in world
        .query_mut::<(&mut FacilityOperations, &FacilityLifecycle)>()
    {
        if life.abandoned {
            continue;
        }
        ops.condition = (ops.condition - delta).max(0.0);
    }
}

/// Phase 19a: crew complement tick — food consumption, hunger,
/// morale. Runs every `FACILITY_CREW_TICK_INTERVAL_BASE × mult`
/// ticks. Abandoned facilities skip (no one's home).
///
/// ## Flow per facility
///
/// 1. **Hunger** climbs by `CREW_HUNGER_RATE_PER_TICK × interval ×
///    tick_scale` (higher world-speed = hunger rises faster).
/// 2. **Food debt** accumulates at `crew_count × FOOD_PER_CREW_TICK
///    × interval`. Integer food units are deducted from reserves
///    whenever debt ≥ 1.0; successful deductions trim `hunger` via
///    `CREW_MEAL_HUNGER_DECREASE / crew_count` so larger crews eat
///    proportionally more to feel full.
/// 3. **Morale** drifts toward its target: well-fed crews
///    (`hunger < HUNGER_MORALE_HIT_THRESHOLD`) recover toward 100;
///    hungry crews lose morale. Both movements use the interval so
///    cadence is tick-scale-independent.
///
/// The crew's `efficiency()` is read by `tick_recipes_and_mining`
/// on its own interval and multiplies into recipe output + mining
/// yield.
/// Dock-queue sweep — runs on a slow cadence inside `tick_facilities`.
/// Each facility's queue is trimmed to entries whose ship is still
/// at this facility's location. Ships that started a Travel action
/// (location_name → None) get dropped; despawned entities get dropped
/// (the `ShipPosition` query fails). Head-of-line starvation is what
/// this prevents: without this sweep, a single departed ship wedges
/// everyone behind it.
fn tick_dock_queue_sweep(world: &mut hecs::World) {
    use crate::agents::ship::ShipPosition;
    // Collect facility (entity, location_string) up front so we can
    // check ship positions without double-borrowing the world.
    let facilities: Vec<(hecs::Entity, String)> = world
        .query::<(&FacilityLocation, &FacilityStorage)>()
        .iter()
        .filter(|(_, (_, s))| !s.dock_queue.is_empty())
        .map(|(e, (loc, _))| (e, loc.location_name.clone()))
        .collect();
    for (entity, loc_name) in facilities {
        let queue_snapshot = match world.get::<&FacilityStorage>(entity) {
            Ok(s) => s.dock_queue.clone(),
            Err(_) => continue,
        };
        let mut keep: Vec<Entity> = Vec::with_capacity(queue_snapshot.len());
        for e in queue_snapshot {
            let still_here = world
                .get::<&ShipPosition>(e)
                .map(|p| p.location_name.as_deref() == Some(loc_name.as_str()))
                .unwrap_or(false);
            if still_here {
                keep.push(e);
            }
        }
        if let Ok(mut storage) = world.get::<&mut FacilityStorage>(entity) {
            if storage.dock_queue.len() != keep.len() {
                storage.dock_queue = keep;
            }
        }
    }
}

fn tick_facility_crew(
    world: &mut hecs::World,
    events: &mut Vec<serde_json::Value>,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let interval = (FACILITY_CREW_TICK_INTERVAL_BASE * tick_multiplier as u64) as f32;
    let hunger_delta = CREW_HUNGER_RATE_PER_TICK * interval * tick_scale;

    // Need the identity/location for starving events — collect here
    // rather than querying again later so we don't fight hecs borrows.
    for (_e, (identity, loc, crew, storage, life)) in world.query_mut::<(
        &FacilityIdentity,
        &FacilityLocation,
        &mut FacilityCrew,
        &mut FacilityStorage,
        &FacilityLifecycle,
    )>() {
        if life.abandoned || crew.crew_count == 0 {
            continue;
        }
        let before_morale = crew.morale;

        // Hunger rises uniformly per tick.
        crew.hunger = (crew.hunger + hunger_delta).clamp(0.0, 100.0);

        // Accumulate fractional food draw. Crew eats whole food units
        // from reserves only when the debt crosses 1.0, so the integer
        // reserves math stays clean even at 0.02/crew/tick.
        crew.food_debt += crew.crew_count as f32 * FOOD_PER_CREW_TICK * interval;
        while crew.food_debt >= 1.0 {
            let food = storage.reserves.entry(Commodity::Food).or_insert(0.0);
            if *food >= 1.0 {
                *food -= 1.0;
                crew.food_debt -= 1.0;
                // Per-meal hunger relief — scaled down for large crews
                // so 20 crew eating 20 food/tick doesn't all-clear
                // hunger from one meal. In practice debt-driven meals
                // at steady state keep hunger pinned near 0.
                let relief = CREW_MEAL_HUNGER_DECREASE / (crew.crew_count as f32).max(1.0);
                crew.hunger = (crew.hunger - relief).max(0.0);
            } else {
                // No food in reserves — leave debt accumulated so
                // the next tick with food will catch up.
                break;
            }
        }

        // Morale — hungry crews decay, fed crews recover.
        let morale_target = if crew.hunger > HUNGER_MORALE_HIT_THRESHOLD {
            0.0
        } else {
            100.0
        };
        let rate = if morale_target < crew.morale {
            CREW_MORALE_HUNGRY_DECAY
        } else {
            CREW_MORALE_RECOVERY
        };
        let step = rate * interval;
        if morale_target < crew.morale {
            crew.morale = (crew.morale - step).max(morale_target);
        } else if morale_target > crew.morale {
            crew.morale = (crew.morale + step).min(morale_target);
        }
        crew.morale = crew.morale.clamp(0.0, 100.0);

        // Emit a one-shot `facility_crew_starving` event only when
        // morale CROSSES the starving threshold going down. Tracking
        // the prior value avoids spamming the ticker every crew-tick
        // while morale hovers in the danger zone.
        if before_morale > CREW_STARVING_MORALE && crew.morale <= CREW_STARVING_MORALE {
            events.push(serde_json::json!({
                "kind": "facility_crew_starving",
                "facility_id": identity.id,
                "location": loc.location_name,
                "facility_type": identity.facility_type,
                "crew_count": crew.crew_count,
                "morale": crew.morale,
            }));
        }

        let changed = (crew.morale - before_morale).abs() > f32::EPSILON
            || crew.hunger > 0.0
            || crew.food_debt > 0.0;
        if changed {
            crew.dirty = true;
        }
    }
}

/// Phase 2: consume one Tool to bump condition. Only if condition is
/// already below REPAIR_THRESHOLD and reserves[Tools] > 0. Matches Elixir
/// `facility_agent.ex:maybe_self_repair`.
fn tick_self_repair(world: &mut hecs::World) {
    for (_e, (ops, storage, life)) in world
        .query_mut::<(
            &mut FacilityOperations,
            &mut FacilityStorage,
            &mut FacilityLifecycle,
        )>()
    {
        if life.abandoned || ops.condition >= CONDITION_REPAIR_THRESHOLD {
            continue;
        }
        let tools = storage.reserves.get(&Commodity::Tools).copied().unwrap_or(0.0);
        if tools < 1.0 {
            continue;
        }
        *storage.reserves.entry(Commodity::Tools).or_insert(0.0) = (tools - 1.0).max(0.0);
        ops.condition = (ops.condition + CONDITION_REPAIR_PER_TOOL).min(1.0);
        ops.dirty = true;
        life.dirty = true;
    }
}

/// Phase 3: advance abandonment countdown. A facility is "dying" if
/// condition < 0.1 AND no tools AND credits < 100. Hold the dying state
/// for ABANDON_THRESHOLD_TICKS and it flips to `abandoned`. Any recovery
/// (tools restock, credits returning, repair) resets the counter.
fn tick_abandonment(
    world: &mut hecs::World,
    events: &mut Vec<serde_json::Value>,
) {
    for (_e, (identity, loc, ops, storage, life)) in world
        .query_mut::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityOperations,
            &FacilityStorage,
            &mut FacilityLifecycle,
        )>()
    {
        if life.abandoned {
            continue;
        }
        let tools = storage.reserves.get(&Commodity::Tools).copied().unwrap_or(0.0);
        let dying = ops.condition < 0.1 && tools < 1.0 && ops.credits < 100;
        if dying {
            let was_below = life.abandon_counter;
            life.abandon_counter = life.abandon_counter.saturating_add(1);
            if life.abandon_counter >= FACILITY_ABANDON_THRESHOLD_TICKS && !life.abandoned {
                life.abandoned = true;
                // One-shot event on the exact tick that flips abandoned
                // true — threshold crossing, not every tick below.
                events.push(serde_json::json!({
                    "kind": "facility_abandoned",
                    "facility_id": identity.id,
                    "facility_type": identity.facility_type,
                    "location": loc.location_name,
                    "condition": ops.condition,
                    "credits": ops.credits,
                }));
            }
            life.dirty = true;
            let _ = was_below;
        } else if life.abandon_counter > 0 {
            life.abandon_counter = 0;
            life.dirty = true;
        }
    }
}

/// Phase 4: restock reserves from the local market. For each target
/// commodity below RESERVE_RESTOCK_THRESHOLD, buy up to
/// (RESTOCK_TARGET - current) at market price, capped by facility credits.
/// Deducts market supply, pays the facility's credits out, adds to reserves.
/// This is in-process (facility + market in same world), so we can do it
/// directly rather than via SimCommand.
fn tick_restock(world: &mut hecs::World) {
    // Collect facility entities + their locations first to avoid borrow
    // conflicts while reading both facility and market components.
    let facility_entries: Vec<(hecs::Entity, String)> = world
        .query::<(&FacilityLocation, &FacilityLifecycle)>()
        .iter()
        .filter_map(|(e, (loc, life))| {
            if life.abandoned {
                None
            } else {
                Some((e, loc.location_name.clone()))
            }
        })
        .collect();

    // Build location → market_entity map once.
    let market_at_location: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (id.facility_location.clone(), e))
        .collect();

    for (fac_entity, loc) in facility_entries {
        let market_entity = match market_at_location.get(&loc) {
            Some(&e) => e,
            None => continue,
        };

        // Snapshot the market's prices + supply (read).
        let prices: std::collections::HashMap<Commodity, (f32, f32)> = match world
            .get::<&MarketPricing>(market_entity)
        {
            Ok(p) => RESTOCK_COMMODITIES
                .iter()
                .filter_map(|&c| {
                    let price = p.prices.get(&c).copied().unwrap_or(0.0);
                    let supply = p.supply.get(&c).copied().unwrap_or(0.0);
                    if price > 0.0 {
                        Some((c, (price, supply)))
                    } else {
                        None
                    }
                })
                .collect(),
            Err(_) => continue,
        };
        if prices.is_empty() {
            continue;
        }

        // Compute each commodity's purchase for this facility.
        #[derive(Clone)]
        struct Buy {
            commodity: Commodity,
            qty: f32,
            cost: i64,
        }
        let purchases: Vec<Buy> = {
            let mut out: Vec<Buy> = Vec::new();
            let storage = match world.get::<&FacilityStorage>(fac_entity) {
                Ok(s) => s,
                Err(_) => continue,
            };
            let ops = match world.get::<&FacilityOperations>(fac_entity) {
                Ok(o) => o,
                Err(_) => continue,
            };
            let mut remaining = ops.credits;
            for (commodity, (price, market_supply)) in prices.iter() {
                let current = storage.reserves.get(commodity).copied().unwrap_or(0.0);
                if current >= RESERVE_RESTOCK_THRESHOLD {
                    continue;
                }
                let need = RESERVE_RESTOCK_TARGET - current;
                let max_affordable = (remaining as f32 / price).max(0.0);
                let available = market_supply.max(0.0);
                let qty = need.min(max_affordable).min(available).floor();
                if qty < 1.0 {
                    continue;
                }
                let cost = (price * qty).round() as i64;
                if cost <= 0 || cost > remaining {
                    continue;
                }
                remaining -= cost;
                out.push(Buy {
                    commodity: *commodity,
                    qty,
                    cost,
                });
            }
            out
        };
        if purchases.is_empty() {
            continue;
        }

        // Apply: debit facility credits, increment reserves, debit market supply.
        let total_cost: i64 = purchases.iter().map(|b| b.cost).sum();
        if let Ok(mut ops) = world.get::<&mut FacilityOperations>(fac_entity) {
            if ops.credits < total_cost {
                continue;
            }
            ops.credits -= total_cost;
            ops.dirty = true;
        }
        if let Ok(mut storage) = world.get::<&mut FacilityStorage>(fac_entity) {
            for buy in &purchases {
                *storage.reserves.entry(buy.commodity).or_insert(0.0) += buy.qty;
            }
        }
        if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
            for buy in &purchases {
                let s = pricing.supply.entry(buy.commodity).or_insert(0.0);
                *s = (*s - buy.qty).max(0.0);
            }
        }
    }
}

/// Phase 5: recipes + mining + XP. Runs every 5×mult ticks. Skips
/// abandoned facilities. Each recipe batch executed grants XP; crossing
/// the level × 100 threshold increments level (capped at
/// `FACILITY_LEVEL_CAP`) and boosts `max_batches` future runs via the
/// `level_scaled_max_batches` helper.
fn tick_recipes_and_mining(
    world: &mut hecs::World,
    tick: u64,
    tick_multiplier: u32,
    lod_gate: &FacilityLodGate,
) {
    let mult = tick_multiplier as u64;
    let recipe_interval = RECIPE_INTERVAL_BASE * mult;
    let mining_interval = MINING_INTERVAL_BASE * mult;

    // Location → market_entity and body_id → body_entity indexes.
    let market_at_location: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (id.facility_location.clone(), e))
        .collect();
    let body_by_string_id: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&BodyIdentity>()
        .iter()
        .map(|(e, id)| (id.body_id.clone(), e))
        .collect();

    // Facility snapshot — include entity so we can update XP in place.
    #[derive(Clone)]
    struct FacilityInfo {
        entity: hecs::Entity,
        facility_type: String,
        location_name: String,
        body_id: String,
        level: u8,
        abandoned: bool,
    }
    let facilities: Vec<FacilityInfo> = world
        .query::<(&FacilityIdentity, &FacilityLocation, &FacilityLifecycle)>()
        .iter()
        .map(|(e, (id, loc, life))| FacilityInfo {
            entity: e,
            facility_type: id.facility_type.clone(),
            location_name: loc.location_name.clone(),
            body_id: id.body_id.clone(),
            level: life.level,
            abandoned: life.abandoned,
        })
        .collect();

    if tick % recipe_interval == 0 {
        for fac in &facilities {
            if fac.abandoned {
                continue;
            }
            // Bundle 1.5: LOD gate — off-screen facilities skip
            // recipes on ticks they aren't firing. No rate-scaling
            // yet; see comment in tick_facilities.
            if !lod_gate.contains_key(&fac.entity) {
                continue;
            }
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            // Phase 18e: fold the facility's FacilityFitting into the
            // recipe run. recipe_output_mult rides through `efficiency`
            // on `recipes::execute`; max_batches_bonus adds flat
            // capacity on top of the level-scaled base. Facilities
            // without a fitting (shouldn't happen post-Phase-18e spawn
            // but defend against hand-rolled DB rows) fall back to
            // neutral stats.
            let (output_mult_fitting, batches_bonus) = world
                .get::<&FacilityFitting>(fac.entity)
                .ok()
                .map(|f| (f.derived.recipe_output_mult, f.derived.max_batches_bonus))
                .unwrap_or((1.0, 0));
            // Phase 19a: crew efficiency multiplies into the output
            // mult alongside fitting. Starving crew → half production.
            let crew_efficiency = world
                .get::<&FacilityCrew>(fac.entity)
                .ok()
                .map(|c| c.efficiency())
                .unwrap_or(1.0);
            let output_mult = output_mult_fitting * crew_efficiency;
            let max_batches = level_scaled_max_batches(fac.level).saturating_add(batches_bonus);
            // Count recipes that actually produced output — XP only grows
            // when real work happens. Elixir increments XP by the number
            // of recipes that ran successfully each cycle.
            let mut recipes_run: u32 = 0;
            if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                // Bundle (H): snapshot prices for the profitability
                // gate. Clone is cheap (HashMap<Commodity, f32>,
                // ~13 entries) and lets us keep the mutable supply
                // borrow below.
                let prices_snap = pricing.prices.clone();
                for recipe in recipes::for_facility_type(&fac.facility_type) {
                    let produced = recipes::execute(
                        recipe,
                        &mut pricing.supply,
                        output_mult,
                        max_batches,
                        Some(&prices_snap),
                    );
                    if !produced.is_empty() {
                        recipes_run += 1;
                    }
                }
            }
            if recipes_run > 0 {
                grant_facility_xp(world, fac.entity, recipes_run);
            }
        }
    }

    if tick % mining_interval == 0 {
        for fac in &facilities {
            if fac.abandoned || fac.facility_type != "mining_rig" {
                continue;
            }
            // Bundle 1.5: LOD gate for mining too.
            if !lod_gate.contains_key(&fac.entity) {
                continue;
            }
            let market_entity = match market_at_location.get(&fac.location_name) {
                Some(&e) => e,
                None => continue,
            };
            let body_entity = match body_by_string_id.get(&fac.body_id) {
                Some(&e) => e,
                None => continue,
            };
            let body_resources: Vec<(Commodity, f32)> =
                match world.get::<&BodyResources>(body_entity) {
                    Ok(r) => r.resources.iter().map(|(&c, &v)| (c, v)).collect(),
                    Err(_) => continue,
                };
            // Mining rigs honour the Production slot too — a tier-3
            // production module boosts extracted yield 1.3×. Phase 19a
            // also folds crew efficiency in: a starved mining crew
            // extracts half as much per cycle.
            let yield_fitting = world
                .get::<&FacilityFitting>(fac.entity)
                .ok()
                .map(|f| f.derived.recipe_output_mult)
                .unwrap_or(1.0);
            let crew_efficiency = world
                .get::<&FacilityCrew>(fac.entity)
                .ok()
                .map(|c| c.efficiency())
                .unwrap_or(1.0);
            let yield_mult = yield_fitting * crew_efficiency;
            if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
                for (commodity, richness) in body_resources {
                    if richness <= 0.0 {
                        continue;
                    }
                    let extracted = MINING_YIELD_PER_CYCLE * richness * yield_mult;
                    *pricing.supply.entry(commodity).or_insert(0.0) += extracted;
                }
            }
        }
    }
}

/// Scale `RECIPE_MAX_BATCHES` by facility level. Level 1 → base; level 10 →
/// 2.9× base. Prevents a maxed-out factory from drowning the market in
/// one tick.
pub fn level_scaled_max_batches(level: u8) -> u32 {
    let lvl = level.clamp(1, FACILITY_LEVEL_CAP) as f32;
    ((RECIPE_MAX_BATCHES as f32) * (1.0 + (lvl - 1.0) * 0.2)).round() as u32
}

/// Grant XP to a facility; level up when `xp >= next_level_threshold`.
pub fn grant_facility_xp(world: &mut hecs::World, entity: hecs::Entity, batches: u32) {
    if let Ok(mut life) = world.get::<&mut FacilityLifecycle>(entity) {
        if life.abandoned {
            return;
        }
        life.xp = life.xp.saturating_add(batches * FACILITY_XP_PER_RECIPE);
        while life.xp >= life.next_level_threshold() && life.level < FACILITY_LEVEL_CAP {
            life.xp -= life.next_level_threshold();
            life.level += 1;
            life.dirty = true;
        }
        life.dirty = true;
    }
}

/// Phase 6b (Phase 18c): shipyards mint modules from their local
/// market's supply.
///
/// Each shipyard iterates [`crate::economy::module_production::MODULE_RECIPES`],
/// skipping slugs already at `SHIPYARD_STOCK_TARGET`, and tries to
/// produce one unit of the first under-stock recipe whose inputs are
/// fully covered by the market supply. On success, inputs are consumed
/// from the market and stock is incremented. Stopping after one module
/// per tick keeps a single shipyard from hoovering the local
/// electronics/metals/components supply in a single phase — slower
/// cadence, more elastic market prices, retrofit stays a scarce event.
fn tick_produce_modules(world: &mut hecs::World) {
    use crate::economy::module_production::{
        consume_inputs, inputs_available, MODULE_RECIPES, SHIPYARD_STOCK_TARGET,
    };

    // Build a location → market_entity index once per call — same pattern
    // as tick_recipes_and_mining. Shipyards pull from their local
    // market's supply, NOT their own reserves, matching refinery/factory
    // behavior.
    let market_at_location: std::collections::HashMap<String, hecs::Entity> = world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (id.facility_location.clone(), e))
        .collect();

    // Collect the shipyard (entity, location, abandoned) tuple so we can
    // mutate components without the query's borrow hanging around.
    struct ShipyardRef {
        entity: hecs::Entity,
        location: String,
    }
    let shipyards: Vec<ShipyardRef> = world
        .query::<(&FacilityIdentity, &FacilityLocation, &FacilityLifecycle)>()
        .iter()
        .filter_map(|(e, (id, loc, life))| {
            if life.abandoned || id.facility_type != "shipyard" {
                return None;
            }
            Some(ShipyardRef {
                entity: e,
                location: loc.location_name.clone(),
            })
        })
        .collect();

    for yard in shipyards {
        let market_entity = match market_at_location.get(&yard.location) {
            Some(&e) => e,
            None => continue,
        };

        // Ensure the shipyard actually has a ModuleStock component.
        // We'd expect one on every shipyard (seeder/admin-spawn attach
        // it), but defend against hand-rolled DB rows that didn't.
        if world.get::<&ModuleStock>(yard.entity).is_err() {
            world.insert_one(yard.entity, ModuleStock::default()).ok();
        }

        // Find the first under-stock recipe whose inputs are covered.
        // Walk recipes in catalog order so production distribution is
        // deterministic run-over-run.
        let chosen_slug: Option<&'static str> = {
            let pricing = match world.get::<&MarketPricing>(market_entity) {
                Ok(p) => p,
                Err(_) => continue,
            };
            let stock = match world.get::<&ModuleStock>(yard.entity) {
                Ok(s) => s,
                Err(_) => continue,
            };
            MODULE_RECIPES.iter().find_map(|recipe| {
                if stock.count(recipe.slug) >= SHIPYARD_STOCK_TARGET {
                    return None;
                }
                if inputs_available(recipe, &pricing.supply) {
                    Some(recipe.slug)
                } else {
                    None
                }
            })
        };

        let Some(slug) = chosen_slug else { continue };
        let recipe = match crate::economy::module_production::get(slug) {
            Some(r) => r,
            None => continue,
        };

        // Consume inputs from the market and bump stock.
        if let Ok(mut pricing) = world.get::<&mut MarketPricing>(market_entity) {
            consume_inputs(recipe, &mut pricing.supply);
        }
        if let Ok(mut stock) = world.get::<&mut ModuleStock>(yard.entity) {
            stock.add(slug, 1);
        }
    }
}

/// Phase 6: post delivery contracts when a commodity has been short for
/// long enough. Each facility posts at most `MAX_ACTIVE_DELIVERIES_PER_FACILITY`
/// contracts at a time. Source is left open (the ship planner looks at
/// price memory to pick where to buy). Payment scales with quantity.
pub fn tick_post_contracts(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u32,
) {
    use crate::agents::market::MarketHistory;
    let lifespan = FACILITY_DELIVERY_LIFESPAN_BASE * tick_multiplier as u64;

    // Snapshot facility + market data to decide postings, then call the
    // mutable ContractBoard at the end.
    #[derive(Clone)]
    struct Plan {
        requestor_id: String,
        // Phase 19e: the facility's owning faction is tagged onto the
        // posted delivery so completing it awards +1 rep with that
        // faction. Without this, facility deliveries were all
        // faction-neutral and rep never grew organically (only subsidy
        // / crew mission deliveries carried a faction, and those are
        // rep-gated to begin with — a chicken-and-egg).
        faction_id: Option<String>,
        commodity: Commodity,
        destination: String,
        source: String,
        payment: i64,
        qty: u32,
    }

    impl ConvoyPlan for Plan {
        fn destination(&self) -> &str { &self.destination }
        fn commodity(&self) -> Commodity { self.commodity }
        fn qty(&self) -> u32 { self.qty }
        fn payment(&self) -> i64 { self.payment }
        fn requestor_id(&self) -> &str { &self.requestor_id }
        fn set_qty(&mut self, qty: u32) { self.qty = qty; }
        fn set_payment(&mut self, payment: i64) { self.payment = payment; }
    }

    // location → market_history for shortage lookup. Elixir's
    // shortage_ticks is a tick counter; we use u32 to match `MarketHistory`.
    let shortage_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, u32>> =
        world
            .query::<(&MarketIdentity, &MarketHistory)>()
            .iter()
            .map(|(_e, (id, hist))| (id.facility_location.clone(), hist.shortage_ticks.clone()))
            .collect();
    let supply_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> =
        world
            .query::<(&MarketIdentity, &MarketPricing)>()
            .iter()
            .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.supply.clone()))
            .collect();
    let price_by_location: std::collections::HashMap<String, std::collections::HashMap<Commodity, f32>> =
        world
            .query::<(&MarketIdentity, &MarketPricing)>()
            .iter()
            .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.prices.clone()))
            .collect();

    // Pick a fallback source location per commodity: the location with the
    // highest current supply for that commodity.
    let source_for_commodity = |commodity: Commodity| -> Option<String> {
        supply_by_location
            .iter()
            .map(|(loc, sup)| (loc, sup.get(&commodity).copied().unwrap_or(0.0)))
            .filter(|(_, s)| *s > 50.0)
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(loc, _)| loc.clone())
    };

    // Compute the payment the facility offers for a delivery contract.
    // Must be high enough that a ship's `buy_cost` at the CURRENT source
    // market price, plus gate fees, leaves a meaningful profit — otherwise
    // the ship planner's `cost >= payment` check rejects every contract
    // and nothing ever gets accepted. We take the MAX of:
    //   1. The flat base payment (`QTY × BASE_PAYMENT_PER_UNIT`).
    //   2. `src_price × QTY × delivery_multiplier` — covers the market
    //      cost of buying at source plus a 30% delivery premium.
    // Cap at what the facility can pay (else we'd post contracts we
    // can't honor).
    let compute_delivery_payment = |commodity: Commodity,
                                    source: &str,
                                    fac_credits: i64,
                                    qty: u32|
     -> i64 {
        let flat = (qty as i64) * DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT;
        let src_price = price_by_location
            .get(source)
            .and_then(|m| m.get(&commodity))
            .copied()
            .unwrap_or(0.0);
        let market_based =
            (src_price * qty as f32 * 1.3).round() as i64;
        flat.max(market_based).min(fac_credits)
    };

    let mut plans: Vec<Plan> = Vec::new();
    for (_e, (id, loc, life, storage, ops)) in world
        .query::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityLifecycle,
            &FacilityStorage,
            &FacilityOperations,
        )>()
        .iter()
    {
        if life.abandoned {
            continue;
        }
        // Skip if facility already has too many active deliveries.
        let active = contracts
            .iter()
            .filter(|c| c.requestor_id == id.id)
            .filter(|c| {
                matches!(
                    c.status,
                    crate::economy::contracts::ContractStatus::Posted
                        | crate::economy::contracts::ContractStatus::Accepted
                        | crate::economy::contracts::ContractStatus::PickedUp
                )
            })
            .count();
        if active >= MAX_ACTIVE_DELIVERIES_PER_FACILITY {
            continue;
        }

        // Look at each tracked-reserve commodity. A facility posts a
        // delivery contract when BOTH its own reserve is critically low
        // AND the local market has been short for sustained ticks.
        let market_shortage = shortage_by_location
            .get(&loc.location_name)
            .cloned()
            .unwrap_or_default();

        // Minimum-qty affordability gate — if the facility can't
        // cover even a floor-sized contract at the flat base rate,
        // don't bother scaling by shortage.
        let can_afford = ops.credits
            >= (MIN_DELIVERY_CONTRACT_QTY as i64) * DELIVERY_CONTRACT_BASE_PAYMENT_PER_UNIT;

        // --- Crew-essentials contracts (fuel/food/tools/water) ---
        // Fires when the facility's OWN RESERVES are low AND the local
        // market is chronically short, so docking ships can't refuel
        // either. Note: we DON'T early-exit after this cycle so a
        // refinery can post both a fuel-restock contract AND a recipe-
        // input contract in the same cycle (up to
        // `MAX_ACTIVE_DELIVERIES_PER_FACILITY`).
        if can_afford {
            for &commodity in RESTOCK_COMMODITIES {
                let reserve = storage.reserves.get(&commodity).copied().unwrap_or(0.0);
                if reserve >= RESERVE_RESTOCK_THRESHOLD {
                    continue;
                }
                let shortage: u32 = market_shortage.get(&commodity).copied().unwrap_or(0);
                // Phase 19f: urgency override for tools when the
                // facility is decaying. Condition < 0.8 triggers the
                // self-repair loop (consume 1 tool → +0.01 condition),
                // so running out of tools in that state is a death
                // spiral. Skip the normal 30-tick shortage wait — the
                // facility needs the tools yesterday.
                let urgent_tools = commodity == Commodity::Tools
                    && ops.condition < CONDITION_REPAIR_THRESHOLD
                    && reserve < 10.0;
                if !urgent_tools && shortage < 30 {
                    continue;
                }
                let Some(source) = source_for_commodity(commodity) else {
                    continue;
                };
                if source == loc.location_name {
                    continue;
                }
                // Bundle 1.3: scale qty by how long this market has been
                // short. Urgent-tools path bypasses the 30-tick wait but
                // still gets the base qty (shortage may be 0).
                let qty = delivery_qty_for_shortage(shortage);
                let payment = compute_delivery_payment(commodity, &source, ops.credits, qty);
                if payment <= 0 {
                    continue;
                }
                plans.push(Plan {
                    requestor_id: id.id.clone(),
                    // Empty string = unowned ("independent"); treat as
                    // None so the rep grant on delivery no-ops rather
                    // than trying to +1 a bogus faction.
                    faction_id: if id.faction_id.is_empty() {
                        None
                    } else {
                        Some(id.faction_id.clone())
                    },
                    commodity,
                    destination: loc.location_name.clone(),
                    source,
                    payment,
                    qty,
                });
                break;
            }
        }

        // --- Recipe-input contracts (ore/gas/metals/polymers/...) ---
        // For producer facility types (refinery/factory/farm), post
        // contracts pulling RAW MATERIALS into the LOCAL MARKET so the
        // recipe tick actually has supply to consume. This is the fix for
        // the "ore piles up at the mine but refineries starve" failure
        // mode. No reserve check — recipes eat directly from market
        // supply — only a market-supply + shortage check.
        if can_afford {
            let local_supply = supply_by_location
                .get(&loc.location_name)
                .cloned()
                .unwrap_or_default();
            for &commodity in recipe_input_commodities(&id.facility_type) {
                let on_market = local_supply.get(&commodity).copied().unwrap_or(0.0);
                // "Short" is market supply well below a recipe-batch's
                // worth, so buying only restores a few cycles of input.
                if on_market >= 100.0 {
                    continue;
                }
                let shortage: u32 = market_shortage.get(&commodity).copied().unwrap_or(0);
                if shortage < RECIPE_INPUT_SHORTAGE_THRESHOLD {
                    continue;
                }
                let Some(source) = source_for_commodity(commodity) else {
                    continue;
                };
                if source == loc.location_name {
                    continue;
                }
                // Bundle 1.3: scale qty by shortage persistence, same
                // policy as crew-essentials above.
                let qty = delivery_qty_for_shortage(shortage);
                let payment = compute_delivery_payment(commodity, &source, ops.credits, qty);
                if payment <= 0 {
                    continue;
                }
                plans.push(Plan {
                    requestor_id: id.id.clone(),
                    // Empty string = unowned ("independent"); treat as
                    // None so the rep grant on delivery no-ops rather
                    // than trying to +1 a bogus faction.
                    faction_id: if id.faction_id.is_empty() {
                        None
                    } else {
                        Some(id.faction_id.clone())
                    },
                    commodity,
                    destination: loc.location_name.clone(),
                    source,
                    payment,
                    qty,
                });
                break;
            }
        }
    }

    // Bundle (J): merge plans whose (destination, commodity) match
    // into a single larger contract. Multiple co-located facilities
    // wanting the same thing → one bigger delivery instead of N
    // small ones. Delivery lands in the shared market supply so
    // everyone at the location benefits; the lead (highest-credits)
    // facility fronts the combined payment. Plans whose lead can't
    // cover the combined payment fall back to unbundled.
    let plans = {
        let credits_by_fac_id: std::collections::HashMap<String, i64> = world
            .query::<(&FacilityIdentity, &FacilityOperations)>()
            .iter()
            .map(|(_, (id, ops))| (id.id.clone(), ops.credits))
            .collect();
        bundle_convoy_plans(plans, |fid| credits_by_fac_id.get(fid).copied().unwrap_or(0))
    };

    // Apply the plans by posting to the board + debiting facility credits.
    // Iterate plans, resolve requestor facility entity, deduct payment.
    for plan in plans {
        // Find facility by requestor_id (= FacilityIdentity.id).
        let fac_entity = world
            .query::<&FacilityIdentity>()
            .iter()
            .find(|(_, id)| id.id == plan.requestor_id)
            .map(|(e, _)| e);
        let Some(fac_entity) = fac_entity else { continue };
        if let Ok(mut ops) = world.get::<&mut FacilityOperations>(fac_entity) {
            if ops.credits < plan.payment {
                continue;
            }
            ops.credits -= plan.payment;
            ops.dirty = true;
        }
        contracts.post_delivery_for(
            plan.requestor_id,
            plan.faction_id,
            plan.commodity,
            plan.qty,
            plan.source,
            plan.destination,
            plan.payment,
            tick,
            lifespan,
        );
    }
}

/// Bundle (J): group delivery plans by (destination, commodity)
/// and merge groups of 2+ into a single larger "convoy" contract.
/// The lead (highest-credits facility that can cover the combined
/// payment) becomes the requestor; non-lead plans are discarded
/// because delivery lands in the shared market supply at the
/// destination — everyone benefits from the one bigger order.
///
/// If no participant in a group can afford the combined payment,
/// the group is unbundled: all original plans pass through
/// individually so at least the best-funded facility still posts
/// its own (smaller) contract.
fn bundle_convoy_plans<P, F>(plans: Vec<P>, credits_for: F) -> Vec<P>
where
    P: ConvoyPlan,
    F: Fn(&str) -> i64,
{
    // Group plans by (destination_location, commodity). HashMap
    // ordering doesn't matter — each group is merged independently
    // and the apply loop processes the resulting Vec serially.
    let mut groups: std::collections::HashMap<(String, Commodity), Vec<P>> =
        std::collections::HashMap::new();
    for plan in plans {
        groups
            .entry((plan.destination().to_string(), plan.commodity()))
            .or_default()
            .push(plan);
    }

    let mut out: Vec<P> = Vec::new();
    for ((_dest, _com), group) in groups {
        if group.len() <= 1 {
            out.extend(group);
            continue;
        }
        let combined_qty: u32 = group
            .iter()
            .map(|p| p.qty())
            .fold(0u32, |acc, q| acc.saturating_add(q))
            .min(MAX_DELIVERY_CONTRACT_QTY * 2); // cap merged qty
        let combined_payment: i64 = group.iter().map(|p| p.payment()).sum();

        // Pick lead: the plan whose requestor has the most credits
        // AND can cover the combined payment alone. Fall back to
        // unbundled if nobody can afford it.
        let lead_idx = group
            .iter()
            .enumerate()
            .filter(|(_, p)| {
                credits_for(p.requestor_id())
                    >= combined_payment
            })
            .max_by_key(|(_, p)| {
                credits_for(p.requestor_id())
            })
            .map(|(i, _)| i);
        let Some(lead_idx) = lead_idx else {
            // No bundler rich enough — pass through unbundled.
            out.extend(group);
            continue;
        };
        let mut group = group;
        let mut lead = group.swap_remove(lead_idx);
        lead.set_qty(combined_qty);
        lead.set_payment(combined_payment);
        out.push(lead);
        // Other group members are discarded — the bundled contract
        // serves everyone at the destination through shared market
        // supply.
    }
    out
}

/// Trait the local Plan struct impls so `bundle_convoy_plans` can
/// be written generically and stay unit-testable against a tiny
/// fake. Kept in this module so the `Plan` struct is the only
/// implementor.
trait ConvoyPlan {
    fn destination(&self) -> &str;
    fn commodity(&self) -> Commodity;
    fn qty(&self) -> u32;
    fn payment(&self) -> i64;
    fn requestor_id(&self) -> &str;
    fn set_qty(&mut self, qty: u32);
    fn set_payment(&mut self, payment: i64);
}

/// Phase 7: post crew missions. Each eligible facility has a 25% chance
/// per cycle to post a new mission (if it has <MAX_ACTIVE active and
/// enough treasury). Mission templates come from `economy::missions`;
/// the picked template's `duration_ticks` becomes the contract's
/// quantity field, and the category slug rides along in
/// `Contract.mission_category` so the apply phase can look it back up.
pub fn tick_post_crew_missions(
    world: &mut hecs::World,
    contracts: &mut crate::economy::contracts::ContractBoard,
    tick: u64,
    tick_multiplier: u32,
) {
    use crate::economy::missions;

    #[derive(Clone)]
    struct Candidate {
        fac_id: String,
        faction_id: String,
        facility_type: String,
        location: String,
        credits: i64,
    }
    // Deterministic "coin flip" using (facility_id + tick) hash so the
    // behavior stays reproducible in tests. Matches sim_core's no-rand
    // convention for tick logic.
    fn hash_flip(key: &str, tick: u64, prob: f32) -> bool {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        key.hash(&mut h);
        tick.hash(&mut h);
        let roll = (h.finish() % 1000) as f32 / 1000.0;
        roll < prob
    }

    let candidates: Vec<Candidate> = world
        .query::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityLifecycle,
            &FacilityOperations,
        )>()
        .iter()
        .filter(|(_, (_, _, life, _))| !life.abandoned)
        .filter_map(|(_, (id, loc, _, ops))| {
            missions::for_facility_type(&id.facility_type).next()?;
            Some(Candidate {
                fac_id: id.id.clone(),
                faction_id: id.faction_id.clone(),
                facility_type: id.facility_type.clone(),
                location: loc.location_name.clone(),
                credits: ops.credits,
            })
        })
        .collect();

    let lifespan = 200 * tick_multiplier as u64; // short-lived gigs

    for cand in candidates {
        // Active mission cap.
        let active = contracts
            .iter()
            .filter(|c| {
                c.requestor_id == cand.fac_id
                    && c.contract_type == crate::economy::contracts::ContractType::CrewMission
                    && matches!(
                        c.status,
                        crate::economy::contracts::ContractStatus::Posted
                            | crate::economy::contracts::ContractStatus::Accepted
                            | crate::economy::contracts::ContractStatus::PickedUp
                    )
            })
            .count();
        if active >= CREW_MISSION_MAX_ACTIVE_PER_FACILITY {
            continue;
        }
        if !hash_flip(&cand.fac_id, tick, CREW_MISSION_POST_PROBABILITY) {
            continue;
        }
        // Pick a mission template — rotate through the facility's options
        // using tick as a selector so we don't always post the same one.
        let templates: Vec<&'static missions::Mission> =
            missions::for_facility_type(&cand.facility_type).collect();
        if templates.is_empty() {
            continue;
        }
        let idx = (tick as usize) % templates.len();
        let template = templates[idx];
        if cand.credits < template.base_payment {
            continue; // can't afford the payout
        }

        // Debit credits and post the mission.
        if let Some(e) = world
            .query::<&FacilityIdentity>()
            .iter()
            .find(|(_, id)| id.id == cand.fac_id)
            .map(|(e, _)| e)
        {
            if let Ok(mut ops) = world.get::<&mut FacilityOperations>(e) {
                if ops.credits < template.base_payment {
                    continue;
                }
                ops.credits -= template.base_payment;
                ops.dirty = true;
            }
        }

        contracts.post_crew_mission(
            cand.fac_id,
            template.category.to_string(),
            template.duration_ticks as u32,
            cand.location,
            template.base_payment,
            if cand.faction_id.is_empty() {
                None
            } else {
                Some(cand.faction_id)
            },
            tick,
            lifespan,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn docking_fee_scales_with_occupancy() {
        // Empty station, perfect condition → base fee.
        assert_eq!(docking_fee(50, 0, 4, 1.0), 50);
        // Half full → 1.5× base.
        assert_eq!(docking_fee(50, 2, 4, 1.0), 75);
        // Full station cannot be reached here (caller guards with at_capacity
        // before calling), but we check the math doesn't explode anyway.
        assert_eq!(docking_fee(50, 4, 4, 1.0), 100);
    }

    #[test]
    fn docking_fee_scales_with_condition() {
        // Ruined station (condition=0) doubles the fee on top of occupancy.
        // 50 × 1.0 × 2.0 = 100
        assert_eq!(docking_fee(50, 0, 4, 0.0), 100);
        // Half-condition station: 50 × 1.0 × 1.5 = 75
        assert_eq!(docking_fee(50, 0, 4, 0.5), 75);
    }

    #[test]
    fn docking_fee_guards_zero_capacity() {
        assert_eq!(docking_fee(50, 0, 0, 1.0), 50);
    }

    /// Bundle (J): test fake for the ConvoyPlan trait so we can
    /// exercise `bundle_convoy_plans` without standing up a hecs
    /// world.
    #[derive(Clone, Debug, PartialEq)]
    struct FakePlan {
        requestor_id: String,
        commodity: Commodity,
        destination: String,
        qty: u32,
        payment: i64,
    }

    impl ConvoyPlan for FakePlan {
        fn destination(&self) -> &str { &self.destination }
        fn commodity(&self) -> Commodity { self.commodity }
        fn qty(&self) -> u32 { self.qty }
        fn payment(&self) -> i64 { self.payment }
        fn requestor_id(&self) -> &str { &self.requestor_id }
        fn set_qty(&mut self, qty: u32) { self.qty = qty; }
        fn set_payment(&mut self, payment: i64) { self.payment = payment; }
    }

    fn mk_plan(reqid: &str, dest: &str, commodity: Commodity, qty: u32, payment: i64) -> FakePlan {
        FakePlan {
            requestor_id: reqid.into(),
            commodity,
            destination: dest.into(),
            qty,
            payment,
        }
    }

    #[test]
    fn convoy_bundle_single_plan_passes_through() {
        let plans = vec![mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000)];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out, plans);
    }

    #[test]
    fn convoy_bundle_merges_co_located_same_commodity() {
        // Two facilities at earth-station both wanting food.
        let plans = vec![
            mk_plan("fac-rich", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-poor", "earth-station", Commodity::Food, 50, 2000),
        ];
        let credits = |id: &str| match id {
            "fac-rich" => 10_000i64,
            _ => 500,
        };
        let out = bundle_convoy_plans(plans, credits);
        assert_eq!(out.len(), 1, "bundled into single plan");
        assert_eq!(out[0].qty, 100, "qty summed");
        assert_eq!(out[0].payment, 4000, "payment summed");
        assert_eq!(out[0].requestor_id, "fac-rich", "lead is the rich one");
    }

    #[test]
    fn convoy_bundle_passes_through_when_no_one_can_afford_merged() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 5000),
            mk_plan("fac-b", "earth-station", Commodity::Food, 50, 5000),
        ];
        // Both facilities have 6000 credits — enough for their OWN
        // payment (5000) but not the combined 10000. Should fall
        // back to unbundled.
        let out = bundle_convoy_plans(plans.clone(), |_| 6000);
        assert_eq!(out.len(), 2, "fallback to unbundled when no bundler can afford");
    }

    #[test]
    fn convoy_bundle_does_not_merge_different_commodities() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-b", "earth-station", Commodity::Fuel, 50, 3000),
        ];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out.len(), 2, "different commodities don't merge");
    }

    #[test]
    fn convoy_bundle_does_not_merge_different_destinations() {
        let plans = vec![
            mk_plan("fac-a", "earth-station", Commodity::Food, 50, 2000),
            mk_plan("fac-b", "mars-station", Commodity::Food, 50, 2000),
        ];
        let out = bundle_convoy_plans(plans.clone(), |_| 100_000);
        assert_eq!(out.len(), 2, "different destinations don't merge");
    }

    #[test]
    fn convoy_bundle_caps_combined_qty() {
        // Many plans summing to over 2×MAX should cap at 2×MAX.
        let plans: Vec<FakePlan> = (0..10)
            .map(|i| mk_plan(&format!("fac-{i}"), "earth-station", Commodity::Ore, 100, 1000))
            .collect();
        let credits = |id: &str| if id == "fac-0" { 1_000_000 } else { 0 };
        let out = bundle_convoy_plans(plans, credits);
        assert_eq!(out.len(), 1);
        assert!(out[0].qty <= MAX_DELIVERY_CONTRACT_QTY * 2);
    }

    #[test]
    fn delivery_qty_scales_with_shortage() {
        // Zero or just-triggered shortage → base qty.
        assert_eq!(delivery_qty_for_shortage(0), DELIVERY_CONTRACT_QTY);
        assert_eq!(delivery_qty_for_shortage(30), DELIVERY_CONTRACT_QTY);
        // One bucket (60 ticks) past trigger adds 25 units.
        assert_eq!(
            delivery_qty_for_shortage(60),
            DELIVERY_CONTRACT_QTY + 25,
        );
        // Two buckets (90 ticks) adds 50.
        assert_eq!(
            delivery_qty_for_shortage(90),
            DELIVERY_CONTRACT_QTY + 50,
        );
        // Deep / sustained shortage caps at MAX.
        assert_eq!(
            delivery_qty_for_shortage(10_000),
            MAX_DELIVERY_CONTRACT_QTY,
        );
    }

    #[test]
    fn delivery_qty_respects_floor_and_ceiling() {
        // Clamp bounds are respected for every input.
        for shortage in [0_u32, 1, 29, 30, 31, 100, 1000, u32::MAX / 2] {
            let qty = delivery_qty_for_shortage(shortage);
            assert!(
                (MIN_DELIVERY_CONTRACT_QTY..=MAX_DELIVERY_CONTRACT_QTY).contains(&qty),
                "qty {qty} out of bounds for shortage {shortage}",
            );
        }
    }

    #[test]
    fn lifecycle_levelup_threshold_scales() {
        let mut life = FacilityLifecycle::new();
        assert_eq!(life.next_level_threshold(), 100);
        life.level = 2;
        assert_eq!(life.next_level_threshold(), 200);
        life.level = 10;
        assert_eq!(life.next_level_threshold(), 1000);
    }

    #[test]
    fn level_scaled_batches_grows_with_level() {
        assert_eq!(level_scaled_max_batches(1), RECIPE_MAX_BATCHES);
        // Level 10 → RECIPE_MAX_BATCHES × 2.8 (rounded).
        let top = level_scaled_max_batches(10);
        assert!(top > RECIPE_MAX_BATCHES);
        assert!(top < RECIPE_MAX_BATCHES * 4);
    }

    #[test]
    fn grant_xp_levels_up_and_resets_xp() {
        use hecs::World;
        let mut world = World::new();
        let e = world.spawn((FacilityLifecycle::new(),));
        // 150 XP → level to 2 (spend 100), leftover 50.
        grant_facility_xp(&mut world, e, 150);
        let life = world.get::<&FacilityLifecycle>(e).unwrap();
        assert_eq!(life.level, 2);
        assert_eq!(life.xp, 50);
    }

    #[test]
    fn grant_xp_caps_at_facility_level_cap() {
        use hecs::World;
        let mut world = World::new();
        let e = world.spawn((FacilityLifecycle::new(),));
        // Dump 1M XP — should hit FACILITY_LEVEL_CAP and stop leveling.
        grant_facility_xp(&mut world, e, 1_000_000);
        let life = world.get::<&FacilityLifecycle>(e).unwrap();
        assert_eq!(life.level, FACILITY_LEVEL_CAP);
    }

    #[test]
    fn module_stock_add_and_take() {
        let mut s = ModuleStock::default();
        assert_eq!(s.count("engine_t2"), 0);
        assert!(!s.take_one("engine_t2"));

        s.add("engine_t2", 2);
        assert_eq!(s.count("engine_t2"), 2);
        assert!(s.dirty);

        s.dirty = false; // simulate post-flush
        assert!(s.take_one("engine_t2"));
        assert_eq!(s.count("engine_t2"), 1);
        assert!(s.dirty, "take_one should re-dirty the component");
    }

    #[test]
    fn tick_produce_modules_mints_one_from_market_supply() {
        use crate::agents::facility::tick_produce_modules;
        use crate::agents::market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing};
        use crate::economy::commodities::Commodity;
        use hecs::World;

        let mut world = World::new();

        // Spawn a market with plenty of supply for engine_t2 + cargo_bay_t2
        // (enough for tier-2 engines: 3 metals + 2 electronics + 1 tool).
        let market_entity = world.spawn((
            MarketIdentity {
                db_id: 1,
                id: "market-earth-station".into(),
                facility: hecs::Entity::from_bits(1).unwrap_or(hecs::Entity::DANGLING),
                facility_location: "earth-station".into(),
            },
            {
                let mut p = MarketPricing {
                    price_elasticity: 0.02,
                    spread: 0.10,
                    prices: Default::default(),
                    supply: Default::default(),
                    demand: Default::default(),
                };
                p.supply.insert(Commodity::Metals, 20.0);
                p.supply.insert(Commodity::Electronics, 20.0);
                p.supply.insert(Commodity::Tools, 5.0);
                p.supply.insert(Commodity::Polymers, 10.0);
                p
            },
            MarketFlow {
                production: Default::default(),
                consumption: Default::default(),
                consumption_window: Default::default(),
                seed_demand: Default::default(),
            },
            MarketOrders {
                pending_buys: vec![],
                pending_sells: vec![],
                reserved: Default::default(),
                next_order_id: 0,
                next_reserve_id: 0,
                order_expiry_ticks: 100,
            },
            MarketHistory {
                price_history: Default::default(),
                trade_volume: Default::default(),
                shortage_ticks: Default::default(),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
                crisis_notified: Default::default(),
            },
        ));
        let _ = market_entity;

        // Spawn a shipyard at the same location with an empty module stock.
        let shipyard_entity = world.spawn((
            FacilityIdentity {
                db_id: 2,
                id: "facility-earth-shipyard".into(),
                name: "Terra Shipyards".into(),
                facility_type: "shipyard".into(),
                faction_id: "terran-authority".into(),
                body_id: "earth".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "earth-station".into(),
            },
            FacilityLifecycle::new(),
            ModuleStock::default(),
        ));

        // Run the production phase — it should pick engine_t2 (first
        // under-stocked recipe whose inputs are covered) and mint 1.
        tick_produce_modules(&mut world);

        let stock = world.get::<&ModuleStock>(shipyard_entity).unwrap();
        assert_eq!(
            stock.count("engine_t2"),
            1,
            "shipyard should mint one engine_t2 on the first pass",
        );
        let pricing = world.get::<&MarketPricing>(market_entity).unwrap();
        // 20 − 3 metals consumed by engine_t2 recipe.
        assert!((pricing.supply[&Commodity::Metals] - 17.0).abs() < 0.001);
    }

    #[test]
    fn tick_produce_modules_skips_when_inputs_missing() {
        use crate::agents::facility::tick_produce_modules;
        use crate::agents::market::{MarketFlow, MarketHistory, MarketIdentity, MarketOrders, MarketPricing};
        use hecs::World;

        let mut world = World::new();
        // Market has no supply at all.
        world.spawn((
            MarketIdentity {
                db_id: 1,
                id: "market-empty".into(),
                facility: hecs::Entity::DANGLING,
                facility_location: "empty".into(),
            },
            MarketPricing {
                price_elasticity: 0.02,
                spread: 0.10,
                prices: Default::default(),
                supply: Default::default(),
                demand: Default::default(),
            },
            MarketFlow {
                production: Default::default(),
                consumption: Default::default(),
                consumption_window: Default::default(),
                seed_demand: Default::default(),
            },
            MarketOrders {
                pending_buys: vec![],
                pending_sells: vec![],
                reserved: Default::default(),
                next_order_id: 0,
                next_reserve_id: 0,
                order_expiry_ticks: 100,
            },
            MarketHistory {
                price_history: Default::default(),
                trade_volume: Default::default(),
                shortage_ticks: Default::default(),
                last_tick: 0,
                spawned_at_tick: None,
                dirty: false,
                crisis_notified: Default::default(),
            },
        ));
        let yard = world.spawn((
            FacilityIdentity {
                db_id: 2,
                id: "facility-empty-yard".into(),
                name: "Empty Yard".into(),
                facility_type: "shipyard".into(),
                faction_id: "x".into(),
                body_id: "none".into(),
            },
            FacilityLocation {
                location_id: 1,
                location_name: "empty".into(),
            },
            FacilityLifecycle::new(),
            ModuleStock::default(),
        ));

        tick_produce_modules(&mut world);
        let stock = world.get::<&ModuleStock>(yard).unwrap();
        assert!(
            stock.stock.is_empty(),
            "shipyard should mint nothing when the market can't cover any recipe",
        );
    }
}
