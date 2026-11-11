//! Control commands sent from HTTP/WS handlers → tick loop.
//!
//! Two *independent* time knobs:
//! - `ticks_per_second` (aka tick resolution) — how often the tick loop fires.
//!   Higher = smoother client interpolation. Purely a rendering/cadence
//!   concern; does NOT change how much game-time passes per tick.
//! - `world_speed` — game-time multiplier. 1.0 = real-time, 0.25 = 4× slower
//!   (the shipping default), 4.0 = 4× faster. Tunes how much game-clock
//!   passes per wall-clock second. Does NOT change tick cadence.
//!
//! `tick_scale` (used by orbital physics, fuel burn, travel time) is derived:
//!   `tick_scale = world_speed / ticks_per_second`
//!
//! Keeping the two knobs separate means you can run at 8 tps × 0.25 speed for
//! normal play, bump ticks_per_second to 16 for smoother client interpolation
//! without speeding up the game, or bump world_speed to 4.0 for a smoke
//! test without making the client's packet rate jittery.

use sim_core::economy::commodities::Commodity;

/// Payload for admin-driven ship creation. HTTP handler populates this
/// from the request body + a freshly-inserted DB row; engine consumes it
/// in the next drain of the control channel and spawns the hecs entity.
#[derive(Debug, Clone)]
pub struct AdminSpawnShipPayload {
    pub db_id: i64,
    pub agent_id: String,
    pub name: String,
    pub class: String,
    pub location_name: String,
    pub faction_id: String,
    pub universe_offset: (f32, f32),
    pub position: (f32, f32),
    pub credits: i64,
}

/// Payload for admin-driven facility creation.
#[derive(Debug, Clone)]
pub struct AdminSpawnFacilityPayload {
    pub db_id: i64,
    pub agent_id: String,
    pub name: String,
    pub facility_type: String,
    pub body_id: String,
    pub faction_id: String,
    pub location_name: String,
    pub location_id: i64,
    pub docking_capacity: u32,
    pub condition: f32,
    pub reputation: i32,
    pub credits: i64,
}

#[derive(Debug, Clone)]
pub enum ControlCommand {
    /// Freeze the tick loop. Preserves current world_speed / tps.
    Pause,
    /// Unfreeze.
    Resume,
    /// Change tick resolution (interval_ms = 1000 / tps). Does NOT touch
    /// world_speed.
    SetTicksPerSecond { tps: u32 },
    /// Change game-time multiplier. Does NOT touch ticks_per_second.
    /// Accepts 0.0..=16.0; 0.0 is equivalent to pause.
    SetWorldSpeed { world_speed: f32 },
    /// Spatial-LOD observer (reserved — Phase 13+ will consume these).
    #[allow(dead_code)]
    MoveObserver { id: String, x: f32, y: f32, radius: f32 },
    /// Step the tick loop forward `ticks` iterations while paused. When
    /// `ticks` reaches 0 the sim pauses again. `0` is a no-op.
    Step { ticks: u32 },
    /// Admin: spawn a new ship from a pre-inserted DB row.
    AdminSpawnShip(AdminSpawnShipPayload),
    /// Admin: remove a ship by agent id.
    AdminRemoveShip { id: String },
    /// Admin: spawn a new facility from a pre-inserted DB row.
    AdminSpawnFacility(AdminSpawnFacilityPayload),
    /// Admin: remove a facility by agent id.
    AdminRemoveFacility { id: String },
    /// Admin: add/subtract a market's supply for one or more commodities.
    /// The engine resolves `location` to a market entity and applies each
    /// delta to that market's `supply` map (floored at 0).
    AdminMarketSupplyDelta {
        location: String,
        deltas: Vec<(Commodity, f32)>,
    },
    /// Admin (Phase 18d): grant ship XP directly — levels up + banks
    /// retrofit points as usual. Used for smoke tests and for manual
    /// god-mode nudges when a ship needs a retrofit push.
    AdminGrantShipXp { id: String, amount: u32 },
    /// Admin (Phase 18e): swap a facility-side subsystem module
    /// (Production or Automation slot). Pure admin override today —
    /// no economy interaction. Engine validates slot + slug + facility
    /// existence, then rebakes the derived stats so the next recipe
    /// tick reads the new multiplier.
    AdminRefitFacility {
        id: String,
        slot: sim_core::facility_modules::FacilitySlot,
        slug: Option<String>,
    },
    /// Admin: swap a subsystem module in one slot on a ship. `slug = None`
    /// clears the slot. Engine validates the slug is in the catalog and
    /// matches the slot, then recomputes derived stats + rebakes
    /// `ShipCargo.capacity` / `ShipFuel.speed_modifier` from the class
    /// base × new multipliers. Marks the ship dirty for persistence.
    ///
    /// When `via_shipyard` is true, the engine additionally requires
    /// the ship to be docked at a `facility_type = "shipyard"` with
    /// the target slug in stock and the ship to carry enough credits
    /// to cover [`sim_core::economy::module_production::ModuleRecipe::base_cost_credits`];
    /// the apply path debits the ship, credits the shipyard, and
    /// decrements the shipyard's `ModuleStock` by one. On any
    /// validation failure the apply silently aborts with no refit —
    /// the HTTP layer validates as much as it can before enqueueing.
    AdminRefitShip {
        id: String,
        slot: sim_core::modules::Slot,
        slug: Option<String>,
        via_shipyard: bool,
    },
    /// Admin (Bundle A): set the relations-matrix entry between two
    /// factions. Either `standing`, `treaty`, or both may be present
    /// — `None` preserves the existing value. The engine applies via
    /// `FactionRelations::set_state` so invariants (canonical pair
    /// ordering, standing clamp, since_tick reset on treaty change)
    /// hold.
    PlayerSetResearchMandate {
        faction_id:String,
        mandate:sim_core::strategy::governance::ResearchMandate,
    },
    PlayerClearResearchMandate {faction_id:String},
    PlayerSetEconomicMandate {
        faction_id:String,
        mandate:sim_core::strategy::economic_mandate::EconomicMandate,
    },
    PlayerClearEconomicMandate {faction_id:String},
    PlayerSetFactionCharter {
        faction_id:String,
        charter:sim_core::strategy::charter::FactionCharter,
    },
    PlayerDecideEconomicProposal {
        faction_id:String,
        proposal_id:String,
        approve:bool,
    },
    AdminSetRelations {
        a: String,
        b: String,
        standing: Option<i32>,
        treaty: Option<sim_core::agents::faction_relations::TreatyKind>,
    },
}
