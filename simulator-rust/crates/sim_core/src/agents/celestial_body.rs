//! Celestial body components.

use crate::economy::commodities::Commodity;
use serde::Serialize;
use std::collections::HashMap;

/// Stable identity.
#[derive(Debug, Clone)]
pub struct BodyIdentity {
    pub db_id: i64,
    pub body_id: String,     // "earth"
    pub name: String,
    pub body_type: String,   // planet, moon, belt
    pub star_system_id: i64,
    pub system_name: String,
}

/// Orbital parameters and current angle. Advanced every tick (or every Nth).
#[derive(Debug, Clone)]
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
#[derive(Debug, Clone, Default)]
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
#[derive(Debug, Clone)]
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

/// Per-tick resource regen fraction. Each regen-cycle adds `rate × max`
/// to current, capped at max. Matches Elixir's `0.0005 × tick_scale`.
pub const BODY_RESOURCE_REGEN_RATE: f32 = 0.0005;
/// Regen-cycle interval (base ticks). Matches `body_agent.ex` `5 × mult`.
pub const BODY_REGEN_INTERVAL_BASE: u64 = 5;

/// Tick phase for bodies. Advances orbits (done in engine), regenerates
/// resources toward `max_resources`. Food biome multipliers are read by
/// `tick_populations` directly from `BodyBiome` — no broadcast needed.
pub fn tick_bodies_regen(
    world: &mut hecs::World,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    let interval = BODY_REGEN_INTERVAL_BASE * tick_multiplier as u64;
    if interval == 0 || tick % interval != 0 {
        return;
    }
    let rate = BODY_RESOURCE_REGEN_RATE * tick_scale * interval as f32;
    for (_e, resources) in world.query_mut::<&mut BodyResources>() {
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
}

impl BodySnapshot {
    pub fn build(identity: &BodyIdentity, orbit: &BodyOrbit, biome: &BodyBiome) -> Self {
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

    #[test]
    fn body_resources_regen_toward_max() {
        use hecs::World;
        let mut world = World::new();
        let mut resources = HashMap::new();
        resources.insert(Commodity::Ore, 0.3);
        let mut max_resources = HashMap::new();
        max_resources.insert(Commodity::Ore, 1.0);
        let _e = world.spawn((BodyResources {
            resources,
            max_resources,
        },));
        // Interval-aligned tick: regen kicks in.
        tick_bodies_regen(&mut world, BODY_REGEN_INTERVAL_BASE, 1.0, 1);
        let post = world
            .query::<&BodyResources>()
            .iter()
            .map(|(_, r)| r.resources.get(&Commodity::Ore).copied().unwrap_or(0.0))
            .next()
            .unwrap();
        assert!(post > 0.3, "expected regen, got {}", post);
        assert!(post <= 1.0);
    }
}
