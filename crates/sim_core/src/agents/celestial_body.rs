//! Celestial body components.
//!
//! ## Bundle D — territorial control
//!
//! Each body carries a [`BodyTerritory`] derived from the factions
//! that own facilities at the body's location. A faction "controls"
//! a body when it owns more facilities there than any rival; the
//! body is `contested` when ≥2 distinct factions each own ≥1
//! non-gate facility there. Gates are excluded from the count
//! because both ends of a paired gate share the same body but the
//! facility's "owner" is the faction whose system the gate enters,
//! which would otherwise inflate every gate-host body's faction
//! count by one.
//!
//! Tiebreak: when two factions are tied on facility count, the one
//! with higher total facility credits wins. Richer presence reads as
//! stronger claim.
//!
//! [`derive_territorial_control`] runs alongside [`crate::agents::faction::tick_factions`]
//! (called by `engine::run_tick_loop` once per faction cycle), writing the
//! derived state back to the body's `BodyTerritory` component. Reads in
//! [`crate::agents::faction::run_subsidy_cycle`] (urgency bump for contested
//! destinations) and [`crate::agents::ship::behavior::score_strategic`]
//! (aggression-weighted score bonus for contracts pulling toward
//! contested zones).

use crate::economy::commodities::Commodity;
use bevy_ecs::prelude::{Component, Entity, World};
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone, Component)]
pub struct BodyIdentity {
    pub db_id: i64,
    pub body_id: String,     // "earth"
    pub name: String,
    pub body_type: String,   // planet, moon, belt
    pub star_system_id: i64,
    pub system_name: String,
}

/// Orbital parameters and current angle. Advanced every tick (or every Nth).
#[derive(Debug, Clone, Component)]
pub struct BodyOrbit {
    pub orbit_radius: f32,
    pub orbit_period: u32,
    /// Current orbital angle in degrees (0–360).
    pub current_angle: f32,
    pub universe_offset: (f32, f32),
    pub dirty: bool,
}

impl BodyOrbit {
    /// Advance orbit by one tick. Returns new angle.
    pub fn advance(&mut self, tick_scale: f32) -> f32 {
        let deg_per_tick = (360.0 / self.orbit_period as f32) * tick_scale;
        self.current_angle = (self.current_angle + deg_per_tick).rem_euclid(360.0);
        self.dirty = true;
        self.current_angle
    }

    /// System-local 2D position.
    pub fn position(&self) -> (f32, f32) {
        let r = self.current_angle.to_radians();
        (self.orbit_radius * r.cos(), self.orbit_radius * r.sin())
    }

    /// Position in universe coordinates (system offset applied).
    pub fn universe_position(&self) -> (f32, f32) {
        let (x, y) = self.position();
        (x + self.universe_offset.0, y + self.universe_offset.1)
    }
}

/// Resource richness — set at spawn, decreases via mining, regens toward
/// `max_resources` each biome-tick.
#[derive(Debug, Clone, Default, Component)]
pub struct BodyResources {
    /// Commodity → current richness (0.0–1.0).
    pub resources: HashMap<Commodity, f32>,
    /// Commodity → seed richness (used as the regen ceiling). Populated at
    /// spawn from the same JSON that seeds `resources`.
    pub max_resources: HashMap<Commodity, f32>,
}

/// Biome classification and food-availability modifier. Populations at
/// this body read `food_multiplier` to scale their growth rate. Matches
/// Elixir's `body_agent.ex` biome → food_availability_multiplier table.
#[derive(Debug, Clone, Component)]
pub struct BodyBiome {
    pub biome: String,
    /// 0.5–1.5 multiplier applied to pop growth rate. Temperate/terrestrial
    /// biomes peak; lifeless/molten/asteroid biomes bottom out. 1.0 is the
    /// neutral default for unknown biomes.
    pub food_multiplier: f32,
}

impl BodyBiome {
    /// Map a biome name (as stored in the world JSON) to a food
    /// availability multiplier. Matches Elixir's table.
    pub fn food_multiplier_for(biome: &str) -> f32 {
        match biome {
            "terrestrial" | "temperate" | "earthlike" => 1.5,
            "ocean" | "aquatic" => 1.3,
            "forest" | "jungle" => 1.4,
            "tundra" | "arctic" => 0.7,
            "desert" | "arid" => 0.5,
            "volcanic" | "molten" => 0.3,
            "lifeless" | "barren" | "rock" | "moon" => 0.2,
            "asteroid" | "belt" => 0.1,
            "ice" | "frozen" => 0.6,
            _ => 1.0,
        }
    }

    pub fn new(biome: impl Into<String>) -> Self {
        let biome = biome.into();
        let food_multiplier = Self::food_multiplier_for(&biome);
        Self { biome, food_multiplier }
    }
}

/// Bundle D: territorial-control state, recomputed every faction cycle.
/// Default = empty (no controller, not contested) so newly-spawned
/// bodies have a stable initial state before the first derivation
/// pass runs. Always present on every body entity once
/// [`derive_territorial_control`] has been called at least once.
#[derive(Debug, Clone, Default, PartialEq, Eq, Component)]
pub struct BodyTerritory {
    /// Faction with the most non-gate facilities at this body.
    /// `None` for unsettled bodies (no facilities, or every facility
    /// has an empty `faction_id`).
    pub controlling_faction: Option<String>,
    /// `true` when at least two distinct factions each own ≥1 non-gate
    /// facility here. The incumbent (controller) faction's subsidy
    /// urgency multiplier and the planner's aggressive-personality
    /// score bonus both key on this flag.
    pub contested: bool,
}

/// Recompute [`BodyTerritory`] for every body and the per-system
/// rollup. Counts non-gate facility ownership per body; ties on count
/// fall to whichever faction has higher aggregate facility credits at
/// that body. Skips facilities with `facility_type == "gate"` so a
/// gate's nominal owner doesn't double-count for the body that hosts
/// the other end of a paired link.
///
/// Returns `system_name → controlling_faction` map for the system-level
/// rollup. Caller stores it on `AgentStore.system_control` (live data,
/// not persisted — re-derived every cycle from the current world state).
pub fn derive_territorial_control(world: &mut World) -> HashMap<String, Option<String>> {
    use crate::agents::facility::{FacilityIdentity, FacilityOperations};

    // Tally per body: body_id → faction_id → (facility_count, total_credits).
    let mut tally: HashMap<String, HashMap<String, (u32, i64)>> = HashMap::new();
    {
        let mut q = world.query::<(&FacilityIdentity, &FacilityOperations)>();
        for (id, ops) in q.iter(&world) {
            if id.faction_id.is_empty() || id.facility_type == "gate" {
                continue;
            }
            let entry = tally
                .entry(id.body_id.clone())
                .or_default()
                .entry(id.faction_id.clone())
                .or_insert((0, 0));
            entry.0 += 1;
            entry.1 = entry.1.saturating_add(ops.credits);
        }
    }

    // Resolve per-body controller + contested flag. body_id → derived state.
    let mut by_body: HashMap<String, BodyTerritory> = HashMap::new();
    for (body_id, factions) in &tally {
        // Sort factions by (facility_count DESC, credits DESC) for a
        // deterministic tiebreak. `.max_by` would also work but the
        // sort lets us pick the leader and inspect runner-up in the
        // same pass.
        let mut ranked: Vec<(&String, u32, i64)> = factions
            .iter()
            .map(|(f, (c, cr))| (f, *c, *cr))
            .collect();
        ranked.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| b.2.cmp(&a.2)));
        let controlling = ranked.first().map(|(f, _, _)| (*f).clone());
        let contested = ranked.len() >= 2;
        by_body.insert(
            body_id.clone(),
            BodyTerritory {
                controlling_faction: controlling,
                contested,
            },
        );
    }

    // Map body_id → system_name once so we can build the per-system
    // rollup without re-querying. Body identities are tiny so this is
    // a couple-of-microseconds operation at any reasonable fleet scale.
    let body_to_system: HashMap<String, String> = {
        let mut q = world.query::<&BodyIdentity>();
        q.iter(&world)
            .map(|id| (id.body_id.clone(), id.system_name.clone()))
            .collect()
    };

    // Write the per-body component back. Insert if missing (newly-
    // spawned bodies that didn't have a BodyTerritory yet); update if
    // the derived state changed. Idempotent — running twice on the
    // same world produces the same components.
    let entities: Vec<(Entity, String)> = {
        let mut q = world.query::<(Entity, &BodyIdentity)>();
        q.iter(&world)
            .map(|(e, id)| (e, id.body_id.clone()))
            .collect()
    };
    for (entity, body_id) in entities {
        let derived = by_body.remove(&body_id).unwrap_or_default();
        // The Result<RefMut> guard from `world.get` outlives the
        // `if let` block under hecs's drop semantics, so the implicit
        // immutable borrow on `world` would block `insert_one` in the
        // `else` arm. Scoping the guard's lifetime + a flag for the
        // miss path side-steps the issue without a second pass.
        let updated = {
            if let Some(mut current) = world.get_mut::<BodyTerritory>(entity) {
                *current = derived.clone();
                true
            } else {
                false
            }
        };
        if !updated {
            world.entity_mut(entity).insert(derived);
        }
    }

    // Per-system rollup. For each system, count which faction controls
    // the most bodies; tie → the system stays None (genuinely contested
    // at the system scale rather than picking arbitrarily). This is
    // looser than the body-level derivation by design — system-level
    // posture is a coarser signal that should only point one way when
    // the answer is clear.
    let mut system_body_counts: HashMap<String, HashMap<Option<String>, u32>> = HashMap::new();
    let body_entities: Vec<(Entity, String)> = {
        let mut q = world.query::<(Entity, &BodyIdentity)>();
        q.iter(&world)
            .map(|(e, id)| (e, id.body_id.clone()))
            .collect()
    };
    for (entity, body_id) in body_entities {
        let Some(system) = body_to_system.get(&body_id).cloned() else {
            continue;
        };
        let controller = world
            .get::<BodyTerritory>(entity)
            .and_then(|t| t.controlling_faction.clone());
        *system_body_counts
            .entry(system)
            .or_default()
            .entry(controller)
            .or_insert(0) += 1;
    }
    let mut system_control: HashMap<String, Option<String>> = HashMap::new();
    for (system, counts) in system_body_counts {
        let mut best: Option<(Option<String>, u32)> = None;
        let mut tied = false;
        for (controller, n) in counts {
            // Skip None (uncontrolled bodies) when picking the system
            // controller — only count factions, not absences.
            if controller.is_none() {
                continue;
            }
            match best.as_ref() {
                None => best = Some((controller, n)),
                Some((_, top)) if n > *top => {
                    best = Some((controller, n));
                    tied = false;
                }
                Some((_, top)) if n == *top => tied = true,
                _ => {}
            }
        }
        let controller = if tied {
            None
        } else {
            best.and_then(|(c, _)| c)
        };
        system_control.insert(system, controller);
    }
    system_control
}

/// Per-tick resource regen fraction. Each regen-cycle adds `rate × max`
/// to current, capped at max. Matches Elixir's `0.0005 × tick_scale`.
pub const BODY_RESOURCE_REGEN_RATE: f32 = 0.0005;
/// Regen-cycle interval (base ticks). Matches `body_agent.ex` `5 × mult`.
pub const BODY_REGEN_INTERVAL_BASE: u64 = 5;

/// Tick phase for bodies. Advances orbits (done in engine), regenerates
/// resources toward `max_resources`. Food biome multipliers are read by
/// `tick_populations` directly from `BodyBiome` — no broadcast needed.
pub fn tick_bodies_regen(
    world: &mut World,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let interval = BODY_REGEN_INTERVAL_BASE * tick_multiplier as u64;
    if interval == 0 || tick % interval != 0 {
        return;
    }
    let rate = BODY_RESOURCE_REGEN_RATE * tick_scale * interval as f32;
    let mut q = world.query::<&mut BodyResources>();
    for mut resources in q.iter_mut(world) {
        let resources = resources.as_mut();
        for (commodity, current) in resources.resources.iter_mut() {
            if let Some(&max) = resources.max_resources.get(commodity) {
                let bumped = *current + rate * max;
                *current = bumped.min(max);
            }
        }
    }
}

/// Snapshot for HTTP/WS.
#[derive(Debug, Clone, Serialize)]
pub struct BodySnapshot {
    pub body_id: String,
    pub name: String,
    pub body_type: String,
    pub position: super::Position,
    pub universe_position: super::Position,
    pub current_angle: f32,
    /// Orbital radius in AU-like units. Godot uses this to draw orbit rings.
    pub orbit_radius: f32,
    /// Orbital period (days at 1x world speed). Godot uses this to animate orbit.
    pub orbit_period: u32,
    /// Biome string ("terrestrial", "molten", etc.). Godot's planet catalog
    /// picks procedural palettes from this.
    pub biome: String,
    /// Bundle D: faction with the most non-gate facilities here, or
    /// `None` for unsettled bodies. Drives faction-tinted body labels.
    pub controlling_faction: Option<String>,
    /// Bundle D: ≥2 distinct factions each own ≥1 facility here.
    /// Surfaces in HUD overlays so contested zones read at a glance.
    pub contested: bool,
}

impl BodySnapshot {
    pub fn build(
        identity: &BodyIdentity,
        orbit: &BodyOrbit,
        biome: &BodyBiome,
        territory: Option<&BodyTerritory>,
    ) -> Self {
        Self {
            body_id: identity.body_id.clone(),
            name: identity.name.clone(),
            body_type: identity.body_type.clone(),
            position: super::Position::from(orbit.position()),
            universe_position: super::Position::from(orbit.universe_position()),
            current_angle: orbit.current_angle,
            orbit_radius: orbit.orbit_radius,
            orbit_period: orbit.orbit_period,
            biome: biome.biome.clone(),
            controlling_faction: territory.and_then(|t| t.controlling_faction.clone()),
            contested: territory.map(|t| t.contested).unwrap_or(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn biome_food_multiplier_lookup() {
        assert_eq!(BodyBiome::food_multiplier_for("terrestrial"), 1.5);
        assert_eq!(BodyBiome::food_multiplier_for("molten"), 0.3);
        assert_eq!(BodyBiome::food_multiplier_for("asteroid"), 0.1);
        // Unknown biome neutral default.
        assert_eq!(BodyBiome::food_multiplier_for("xenomorph"), 1.0);
    }

    fn fac_id(id: &str, faction: &str, body: &str) -> crate::agents::facility::FacilityIdentity {
        crate::agents::facility::FacilityIdentity {
            db_id: 0,
            id: id.into(),
            name: id.into(),
            facility_type: "station".into(),
            faction_id: faction.into(),
            body_id: body.into(),
        }
    }
    fn fac_ops(credits: i64) -> crate::agents::facility::FacilityOperations {
        crate::agents::facility::FacilityOperations {
            docking_capacity: 10,
            services: vec![],
            condition: 1.0,
            reputation: 0,
            credits,
            dirty: false,
            starving_notified: false,
        }
    }
    fn body_id(name: &str, system: &str) -> BodyIdentity {
        BodyIdentity {
            db_id: 0,
            body_id: name.into(),
            name: name.into(),
            body_type: "planet".into(),
            star_system_id: 0,
            system_name: system.into(),
        }
    }

    #[test]
    fn territorial_majority_wins_with_no_tie() {
        // 3 X facilities + 1 Y facility on body "earth" → controller=X, contested=true.
        let mut world = World::new();
        world.spawn((body_id("earth", "sol"),));
        world.spawn((fac_id("a", "x", "earth"), fac_ops(100)));
        world.spawn((fac_id("b", "x", "earth"), fac_ops(100)));
        world.spawn((fac_id("c", "x", "earth"), fac_ops(100)));
        world.spawn((fac_id("d", "y", "earth"), fac_ops(100)));
        let _systems = derive_territorial_control(&mut world);
        let entity = {
            let mut q = world.query::<(Entity, &BodyIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.body_id == "earth")
                .map(|(e, _)| e)
                .unwrap()
        };
        let t = world.get::<BodyTerritory>(entity).unwrap().clone();
        assert_eq!(t.controlling_faction.as_deref(), Some("x"));
        assert!(t.contested);
    }

    #[test]
    fn territorial_unsettled_body_has_no_controller() {
        // A body with no facilities → controlling_faction None, not contested.
        let mut world = World::new();
        world.spawn((body_id("pluto", "sol"),));
        derive_territorial_control(&mut world);
        let entity = {
            let mut q = world.query::<(Entity, &BodyIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.body_id == "pluto")
                .map(|(e, _)| e)
                .unwrap()
        };
        let t = world.get::<BodyTerritory>(entity).unwrap().clone();
        assert_eq!(t.controlling_faction, None);
        assert!(!t.contested);
    }

    #[test]
    fn territorial_count_tie_breaks_on_credits() {
        // 1 X facility worth 1000 + 1 Y facility worth 5000 on body "mars"
        // → controller = Y (richer presence wins the tie), still contested.
        let mut world = World::new();
        world.spawn((body_id("mars", "sol"),));
        world.spawn((fac_id("a", "x", "mars"), fac_ops(1000)));
        world.spawn((fac_id("b", "y", "mars"), fac_ops(5000)));
        derive_territorial_control(&mut world);
        let entity = {
            let mut q = world.query::<(Entity, &BodyIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.body_id == "mars")
                .map(|(e, _)| e)
                .unwrap()
        };
        let t = world.get::<BodyTerritory>(entity).unwrap().clone();
        assert_eq!(t.controlling_faction.as_deref(), Some("y"));
        assert!(t.contested);
    }

    #[test]
    fn territorial_gate_facilities_are_excluded_from_count() {
        // 1 station of X + 1 GATE of Y at the same body → not contested:
        // gates don't count toward territorial control, so X is sole owner.
        let mut world = World::new();
        world.spawn((body_id("haven", "haven_system"),));
        world.spawn((fac_id("a", "x", "haven"), fac_ops(500)));
        let mut gate = fac_id("g", "y", "haven");
        gate.facility_type = "gate".into();
        world.spawn((gate, fac_ops(0)));
        derive_territorial_control(&mut world);
        let entity = {
            let mut q = world.query::<(Entity, &BodyIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.body_id == "haven")
                .map(|(e, _)| e)
                .unwrap()
        };
        let t = world.get::<BodyTerritory>(entity).unwrap().clone();
        assert_eq!(t.controlling_faction.as_deref(), Some("x"));
        assert!(!t.contested, "gate of rival faction must not flag contested");
    }

    #[test]
    fn territorial_idempotent_runs() {
        // Running the derivation twice on the same world produces the
        // same components (no extra inserts, no field drift).
        let mut world = World::new();
        world.spawn((body_id("earth", "sol"),));
        world.spawn((fac_id("a", "x", "earth"), fac_ops(100)));
        let s1 = derive_territorial_control(&mut world);
        let s2 = derive_territorial_control(&mut world);
        assert_eq!(s1, s2);
        let entity = {
            let mut q = world.query::<(Entity, &BodyIdentity)>();
            q.iter(&world)
                .find(|(_, id)| id.body_id == "earth")
                .map(|(e, _)| e)
                .unwrap()
        };
        let t = world.get::<BodyTerritory>(entity).unwrap().clone();
        assert_eq!(t.controlling_faction.as_deref(), Some("x"));
        assert!(!t.contested);
    }

    #[test]
    fn system_rollup_picks_majority_body_controller() {
        // Sol system: earth + mars controlled by X, pluto unsettled.
        // System controller should be X.
        let mut world = World::new();
        world.spawn((body_id("earth", "sol"),));
        world.spawn((body_id("mars", "sol"),));
        world.spawn((body_id("pluto", "sol"),));
        world.spawn((fac_id("a", "x", "earth"), fac_ops(100)));
        world.spawn((fac_id("b", "x", "mars"), fac_ops(100)));
        let systems = derive_territorial_control(&mut world);
        assert_eq!(systems.get("sol"), Some(&Some("x".to_string())));
    }

    #[test]
    fn system_rollup_tie_yields_no_controller() {
        // Sol: earth → X, mars → Y. Tie at the system level → None.
        let mut world = World::new();
        world.spawn((body_id("earth", "sol"),));
        world.spawn((body_id("mars", "sol"),));
        world.spawn((fac_id("a", "x", "earth"), fac_ops(100)));
        world.spawn((fac_id("b", "y", "mars"), fac_ops(100)));
        let systems = derive_territorial_control(&mut world);
        assert_eq!(systems.get("sol"), Some(&None));
    }

    #[test]
    fn body_resources_regen_toward_max() {
        let mut world = World::new();
        let mut resources = HashMap::new();
        resources.insert(Commodity::Ore, 0.3);
        let mut max_resources = HashMap::new();
        max_resources.insert(Commodity::Ore, 1.0);
        world.spawn((BodyResources {
            resources,
            max_resources,
        },));
        // Interval-aligned tick: regen kicks in.
        tick_bodies_regen(&mut world, BODY_REGEN_INTERVAL_BASE, 1.0, 1);
        let post = {
            let mut q = world.query::<&BodyResources>();
            q.iter(&world)
                .map(|r| r.resources.get(&Commodity::Ore).copied().unwrap_or(0.0))
                .next()
                .unwrap()
        };
        assert!(post > 0.3, "expected regen, got {}", post);
        assert!(post <= 1.0);
    }
}
