//! Construction sites (Phase 19c-b).
//!
//! A `ConstructionSite` is a half-built facility that sits in the
//! world from the moment the demand analyzer decides "we need a
//! polymer refinery at Kuiper Station" until enough construction
//! deliveries arrive to complete it. At `progress == 1.0` the site
//! despawns and a real `Facility*` entity materialises at the same
//! position.
//!
//! ## Lifecycle
//!
//! 1. `run_construction_cycle` (faction.rs) detects chronic shortage,
//!    spawns a `ConstructionSite` via `spawn_site()`, then posts a
//!    `ContractType::Construction` contract targeting the site.
//! 2. Ships fulfil the delivery contract normally.
//! 3. `apply_deliver_construction` (engine.rs) bumps the site's
//!    `progress_delivered` by the delivered quantity (capped at
//!    `progress_required`).
//! 4. If `progress >= 1.0` the site materialises. If not, the next
//!    demand analyzer cycle posts another contract (up to a cap).
//!
//! The site is **not** a facility — ships don't dock at it, it has
//! no market, it doesn't run recipes. It's a placeholder entity that
//! Godot renders as a scaffold/wireframe so the player sees
//! something visible happening at the starved location.

use crate::economy::commodities::Commodity;
use bevy_ecs::prelude::{Component, Entity, World};
use serde::Serialize;

/// Units of commodity needed to finish a construction site. Sized so
/// ~3 standard Construction deliveries (200 each) complete the build.
pub const CONSTRUCTION_PROGRESS_REQUIRED: u32 = 600;

/// Maximum rendered scale of a site (Godot reads this to animate
/// growth 0→1 as progress climbs). Set cosmetically.
pub const SITE_MAX_SCALE: f32 = 1.0;

/// Canonical facility type the site materialises into. One-to-one
/// with the commodity it's been accreting, so players see a natural
/// "metals shortage → refinery being built" causal chain.
pub fn facility_type_for_commodity(c: Commodity) -> &'static str {
    use Commodity::*;
    match c {
        // Raw extractors
        Ore | Ice | Gas => "mining_rig",
        // Basic / intermediate refining
        Metals | Water | Polymers | Fuel => "refinery",
        // Finished-goods factories
        Components | Electronics | Tools | Luxury => "factory",
        // Food / water producers
        Food => "farm",
        // Medical is specialist; treat as factory for now
        Medical => "factory",
    }
}

/// Flat ECS component for the construction site entity. Kept
/// deliberately small so rendering + progress-update passes are cheap.
#[derive(Debug, Clone, Component)]
pub struct ConstructionSite {
    /// Stable agent-id. Format: `site-<commodity>-<location>-<tick>`.
    pub id: String,
    /// Human-readable name for UI. e.g. "Kuiper Polymer Works".
    pub name: String,
    /// Target facility type this site becomes at completion.
    pub facility_type: String,
    /// Faction sponsoring the build.
    pub faction_id: String,
    /// Body the site orbits — materialisation inherits this.
    pub body_id: String,
    /// Destination location slug this site pegs to (e.g.
    /// "kuiper-station"). Delivery contracts routed here count
    /// toward progress.
    pub location_name: String,
    /// Commodity each delivery supplies toward the build.
    pub commodity: Commodity,
    /// Units accumulated so far (monotonically increasing; capped at
    /// `progress_required`).
    pub progress_delivered: u32,
    /// Units needed to complete (default
    /// [`CONSTRUCTION_PROGRESS_REQUIRED`]).
    pub progress_required: u32,
    /// Universe-space position (matches a facility orbit offset
    /// around `body_id`). Godot renders the site here.
    pub position: (f32, f32),
    /// Tick when the site was spawned — used by the demand analyzer
    /// to decide whether to post another top-up contract.
    pub spawned_at_tick: u64,
    /// Flipped true once the site has materialised into a real
    /// facility. The despawn happens the same tick; the flag exists
    /// so we can emit a `construction_completed` event without a
    /// separate side-channel.
    pub completed: bool,
    /// Persistence flag. Set to true when any field changes, then
    /// cleared by the engine's flush sweep. Sites aren't persisted
    /// to DB yet (MVP — they live only in RAM), so this is unused
    /// for now but wired so adding a migration is mechanical.
    pub dirty: bool,
}

impl ConstructionSite {
    /// Progress fraction 0.0..=1.0, clamped.
    pub fn progress(&self) -> f32 {
        if self.progress_required == 0 {
            return 1.0;
        }
        (self.progress_delivered as f32 / self.progress_required as f32).clamp(0.0, 1.0)
    }

    /// How much more is needed to finish the build.
    pub fn remaining(&self) -> u32 {
        self.progress_required.saturating_sub(self.progress_delivered)
    }
}

/// WS / HTTP snapshot. Godot reads this to render scaffolds.
#[derive(Debug, Clone, Serialize)]
pub struct ConstructionSiteSnapshot {
    pub id: String,
    pub name: String,
    pub facility_type: String,
    pub faction_id: String,
    pub body_id: String,
    #[serde(rename = "location")]
    pub location_name: String,
    pub commodity: String,
    pub progress: f32,
    pub progress_required: u32,
    pub progress_delivered: u32,
    pub position: super::Position,
}

impl From<&ConstructionSite> for ConstructionSiteSnapshot {
    fn from(s: &ConstructionSite) -> Self {
        Self {
            id: s.id.clone(),
            name: s.name.clone(),
            facility_type: s.facility_type.clone(),
            faction_id: s.faction_id.clone(),
            body_id: s.body_id.clone(),
            location_name: s.location_name.clone(),
            commodity: s.commodity.as_str().to_string(),
            progress: s.progress(),
            progress_required: s.progress_required,
            progress_delivered: s.progress_delivered,
            position: super::Position::from(s.position),
        }
    }
}

/// Is there already a site for this commodity at this location?
/// Prevents the demand analyzer from double-spawning.
pub fn site_exists_for(
    world: &mut World,
    location_name: &str,
    commodity: Commodity,
) -> bool {
    let mut q = world.query::<&ConstructionSite>();
    q.iter(world)
        .any(|s| s.location_name == location_name && s.commodity == commodity)
}

/// Find the site at `location` accepting deliveries of `commodity`.
/// Used by the delivery apply phase to route progress toward the
/// right site. Returns the entity + a clone of the site state so the
/// caller can mutate without borrow conflicts.
pub fn find_site(
    world: &mut World,
    location_name: &str,
    commodity: Commodity,
) -> Option<Entity> {
    let mut q = world.query::<(Entity, &ConstructionSite)>();
    q.iter(world)
        .find(|(_, s)| {
            s.location_name == location_name && s.commodity == commodity && !s.completed
        })
        .map(|(e, _)| e)
}
