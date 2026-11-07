//! Facility ECS components, snapshot types, and small geometry helpers.
//!
//! A facility entity carries the bundle below (`FacilityIdentity`,
//! `FacilityLocation`, `FacilityOperations`, `FacilityLifecycle`,
//! `FacilityStorage`, `FacilityFitting`, `FacilityCrew`, `ModuleStock`).
//! Snapshot wire-types (`FacilitySnapshot`, `FacilityFittingSnapshot`,
//! `FacilityDerivedStatsSnapshot`, `FacilityCrewSnapshot`,
//! `GateLinkSnapshot`) round-trip the bundle through HTTP / WS readers
//! and the persistence worker.
//!
//! Co-located helpers:
//!   * [`gate_transit_fee`] — per-jump fee scaled by cargo size.
//!   * [`docking_fee`] — per-dock fee × occupancy × (2 − condition).
//!   * [`facility_offset_position`] — deterministic per-id orbit
//!     offset so two facilities at the same body don't z-fight.
//!
//! Tick logic (recipes, crew, self-repair, abandonment, restock,
//! contract / crew-mission posting) lives in `facility/mod.rs`'s
//! tick module — components stay free of side-effects so they can be
//! consumed from snapshots and admin paths without pulling in
//! market / contract dependencies.
//!
//! Extracted from `facility.rs` in the Phase-21 god-module split.

use crate::economy::commodities::Commodity;
use bevy_ecs::prelude::{Component, Entity};
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone, Component)]
pub struct FacilityIdentity {
    pub db_id: i64,
    pub id: String,                  // "facility-earth-station"
    pub name: String,
    pub facility_type: String,       // station, refinery, farm, etc.
    pub faction_id: String,
    pub body_id: String,
}

/// Spatial anchor.
#[derive(Debug, Clone, Component)]
pub struct FacilityLocation {
    pub location_id: i64,
    pub location_name: String,
}

/// Operations — docking, condition, finances.
#[derive(Debug, Clone, Component)]
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
#[derive(Debug, Clone, Component)]
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
#[derive(Debug, Clone, Component)]
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
#[derive(Debug, Clone, Default, Component)]
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
#[derive(Debug, Clone, Component)]
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
#[derive(Debug, Clone, Component)]
pub struct FacilityCrew {
    pub work_shift: Option<super::workforce::WorkShift>,
    pub work_blocked_reason: Option<String>,
    /// Required workers for a production shift. Residents are hired locally;
    /// this count is jobs, not a separate population.
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
            work_shift: None,
            work_blocked_reason: None,
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

/// Morale the crew spawns with. High enough that well-stocked
/// facilities start at full production efficiency; low enough that a
/// brief food outage at tick 0 causes a visible drop rather than
/// clamping at 100 for hours.
pub const CREW_MORALE_START: f32 = 80.0;

impl Default for FacilityCrew {
    fn default() -> Self {
        Self::new_for_type("station")
    }
}

/// Serialized form for DB + WS.
#[derive(Debug, Clone, Serialize, serde::Deserialize, Default)]
pub struct FacilityCrewSnapshot {
    #[serde(default)]
    pub work_shift: Option<super::workforce::WorkShift>,
    #[serde(default)]
    pub work_blocked_reason: Option<String>,
    pub crew_count: u16,
    pub morale: f32,
    pub hunger: f32,
    #[serde(default)]
    pub food_debt: f32,
}

impl From<&FacilityCrew> for FacilityCrewSnapshot {
    fn from(c: &FacilityCrew) -> Self {
        Self {
            work_shift: c.work_shift.clone(),
            work_blocked_reason: c.work_blocked_reason.clone(),
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
            work_shift: s.work_shift,
            work_blocked_reason: s.work_blocked_reason,
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
#[derive(Debug, Clone, Default, Component)]
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
    pub position: crate::agents::Position,
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
pub const FACILITY_ORBIT_RADIUS: f32 = 0.55;

/// The station's orbit is a genuine, slowly evolving world coordinate around
/// its parent body. Moon-like visual movement, but deliberately much slower
/// than the compact starter-system moons. Units are simulation-time seconds.
pub const FACILITY_ORBIT_PERIOD: f32 = 8_000.0;

/// Every facility at a shared location participates in the *same* orbital
/// anchor. That makes modules physically co-located with their station.
#[derive(Debug, Clone, Component)]
pub struct FacilityOrbit {
    pub angle_degrees: f32,
    pub dirty: bool,
}

impl FacilityOrbit {
    pub fn new(location: &str, persisted: Option<f32>) -> Self {
        Self { angle_degrees: persisted.filter(|v| v.is_finite())
            .unwrap_or_else(|| facility_orbit_initial_angle(location)).rem_euclid(360.0),
            dirty: false }
    }
    pub fn advance(&mut self, tick_scale: f32) {
        if tick_scale.is_finite() && tick_scale > 0.0 {
            self.angle_degrees = (self.angle_degrees
                + 360.0 * tick_scale / FACILITY_ORBIT_PERIOD).rem_euclid(360.0);
        }
    }
}

/// Stable initial phase, identical for every module in a station location.
/// A deterministic byte hash avoids platform-dependent DefaultHasher seeds.
pub fn facility_orbit_initial_angle(location: &str) -> f32 {
    let hash = location.as_bytes().iter().fold(2166136261u32, |h,b|
        (h ^ (*b as u32)).wrapping_mul(16777619));
    (hash % 360) as f32
}

pub fn facility_orbit_position(body: (f32, f32), angle_degrees: f32) -> (f32, f32) {
    let theta = angle_degrees.to_radians();
    (body.0 + FACILITY_ORBIT_RADIUS * theta.cos(),
     body.1 + FACILITY_ORBIT_RADIUS * theta.sin())
}

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

#[cfg(test)]
mod physical_orbit_tests {
    use super::*;
    #[test]
    fn modules_same_location_share_a_physical_orbital_anchor() {
        let a = FacilityOrbit::new("earth-station", None);
        let b = FacilityOrbit::new("earth-station", None);
        assert_eq!(a.angle_degrees,b.angle_degrees);
        assert_eq!(facility_orbit_position((2.0, -4.0),a.angle_degrees),
                   facility_orbit_position((2.0, -4.0),b.angle_degrees));
    }
    #[test]
    fn station_rotation_is_slow_and_persistent() {
        let mut orbit = FacilityOrbit::new("earth-station",Some(90.0));
        orbit.advance(1.0);
        assert!(orbit.angle_degrees > 90.0 && orbit.angle_degrees < 90.1);
        let restored = FacilityOrbit::new("earth-station",Some(orbit.angle_degrees));
        assert_eq!(restored.angle_degrees,orbit.angle_degrees);
    }
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
        position: crate::agents::Position,
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

