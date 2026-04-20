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

/// Resource richness — set at spawn, decreases via mining.
#[derive(Debug, Clone, Default)]
pub struct BodyResources {
    /// Commodity → richness (0.0–1.0).
    pub resources: HashMap<Commodity, f32>,
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
}

impl BodySnapshot {
    pub fn build(identity: &BodyIdentity, orbit: &BodyOrbit) -> Self {
        Self {
            body_id: identity.body_id.clone(),
            name: identity.name.clone(),
            body_type: identity.body_type.clone(),
            position: super::Position::from(orbit.position()),
            universe_position: super::Position::from(orbit.universe_position()),
            current_angle: orbit.current_angle,
        }
    }
}
