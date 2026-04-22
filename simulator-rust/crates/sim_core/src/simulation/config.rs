/// Simulation timing constants.
pub struct TickConfig {
    /// Real-time tick rate (ticks per second).
    pub ticks_per_second: u32,
    /// Gameplay speed factor. 1.0 = real-time, 0.25 = 4x slower (default).
    pub world_speed: f32,
}

impl TickConfig {
    pub const DEFAULT: TickConfig = TickConfig {
        ticks_per_second: 8,
        // 0.25 = chill interactive pace. Earth↔Mars ≈ 4 min. Set WORLD_SPEED
        // env var to override at startup (e.g. `WORLD_SPEED=4` for smoke
        // tests) or POST /api/sim/speed {world_speed: X} at runtime.
        world_speed: 0.25,
    };

    /// Milliseconds between ticks.
    pub fn tick_interval_ms(&self) -> u64 {
        1000 / self.ticks_per_second as u64
    }

    /// Per-tick rate multiplier. Multiply base rates (per-second at 1x speed) by this.
    pub fn tick_scale(&self) -> f32 {
        self.world_speed / self.ticks_per_second as f32
    }

    /// Interval multiplier. Multiply base intervals (in ticks at 1x speed) by this.
    pub fn tick_multiplier(&self) -> u32 {
        (self.ticks_per_second as f32 / self.world_speed).round() as u32
    }
}

/// Ship scale tier (Phase 18f). Orthogonal to `ShipClass` — a
/// size-3 miner and a size-3 tanker are both "Medium" hulls while
/// serving different economic roles. Phase 18f treats size as a
/// tag that drives default sensor tier (and downstream cross-system
/// visibility); a follow-up phase moves cargo/fuel/speed off class
/// and onto a size-driven table so size-2 tankers physically differ
/// from size-5 tankers.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize,
)]
#[serde(rename_all = "snake_case")]
pub enum ShipSize {
    Tiny,
    Small,
    Medium,
    Large,
    Huge,
    Massive,
}

impl ShipSize {
    /// 1..=6 scale tier (wire-friendly form).
    pub fn tier(self) -> u8 {
        match self {
            ShipSize::Tiny => 1,
            ShipSize::Small => 2,
            ShipSize::Medium => 3,
            ShipSize::Large => 4,
            ShipSize::Huge => 5,
            ShipSize::Massive => 6,
        }
    }

    /// Canonical string key (matches the serde snake_case name).
    pub fn as_str(self) -> &'static str {
        match self {
            ShipSize::Tiny => "tiny",
            ShipSize::Small => "small",
            ShipSize::Medium => "medium",
            ShipSize::Large => "large",
            ShipSize::Huge => "huge",
            ShipSize::Massive => "massive",
        }
    }

    /// Parse a wire-form snake-case string. Returns `None` for
    /// unknown values so callers can fall back to a default.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "tiny" => Some(ShipSize::Tiny),
            "small" => Some(ShipSize::Small),
            "medium" => Some(ShipSize::Medium),
            "large" => Some(ShipSize::Large),
            "huge" => Some(ShipSize::Huge),
            "massive" => Some(ShipSize::Massive),
            _ => None,
        }
    }

    /// Parse a numeric tier 1..=6 back into a `ShipSize`.
    pub fn from_tier(tier: u8) -> Option<Self> {
        match tier {
            1 => Some(ShipSize::Tiny),
            2 => Some(ShipSize::Small),
            3 => Some(ShipSize::Medium),
            4 => Some(ShipSize::Large),
            5 => Some(ShipSize::Huge),
            6 => Some(ShipSize::Massive),
            _ => None,
        }
    }
}

/// Ship class definitions with base stats.
#[derive(Debug, Clone)]
pub struct ShipClass {
    pub name: &'static str,
    pub cargo_capacity: u32,
    pub passenger_capacity: u32,
    pub fuel_capacity: f32,
    /// Base fuel consumption per second at 1x world speed. Scale by tick_scale().
    pub fuel_consumption_base: f32,
    pub speed_modifier: f32,
    pub crew_size: u32,
    pub crew_roles: &'static [&'static str],
    /// Default scale tier for this class when no explicit size is
    /// set in seed data. Migration-time backfill uses this too.
    pub default_size: ShipSize,
}

pub const SHIP_CLASSES: &[ShipClass] = &[
    ShipClass {
        name: "courier",
        cargo_capacity: 50,
        passenger_capacity: 20,
        fuel_capacity: 80.0,
        fuel_consumption_base: 0.03,
        speed_modifier: 1.5,
        crew_size: 2,
        crew_roles: &["pilot", "general"],
        default_size: ShipSize::Small,
    },
    ShipClass {
        name: "freighter",
        cargo_capacity: 500,
        passenger_capacity: 10,
        fuel_capacity: 100.0,
        fuel_consumption_base: 0.05,
        speed_modifier: 1.0,
        crew_size: 5,
        crew_roles: &["pilot", "engineer", "trader", "medic", "general"],
        default_size: ShipSize::Medium,
    },
    ShipClass {
        name: "hauler",
        cargo_capacity: 2000,
        passenger_capacity: 5,
        fuel_capacity: 200.0,
        fuel_consumption_base: 0.10,
        speed_modifier: 0.6,
        crew_size: 8,
        crew_roles: &[
            "pilot", "pilot", "engineer", "engineer", "trader", "medic", "general", "general",
        ],
        default_size: ShipSize::Huge,
    },
    ShipClass {
        name: "tanker",
        cargo_capacity: 1500,
        passenger_capacity: 0,
        fuel_capacity: 300.0,
        fuel_consumption_base: 0.08,
        speed_modifier: 0.7,
        crew_size: 6,
        crew_roles: &["pilot", "engineer", "engineer", "trader", "medic", "general"],
        default_size: ShipSize::Large,
    },
    ShipClass {
        name: "miner",
        cargo_capacity: 200,
        passenger_capacity: 0,
        fuel_capacity: 120.0,
        fuel_consumption_base: 0.04,
        speed_modifier: 0.8,
        crew_size: 3,
        crew_roles: &["pilot", "engineer", "general"],
        default_size: ShipSize::Small,
    },
];

pub fn ship_class(name: &str) -> Option<&'static ShipClass> {
    SHIP_CLASSES.iter().find(|c| c.name == name)
}

/// Spatial LOD: max divisor for tick gating of distant agents.
pub const MAX_TICK_DIVISOR: u32 = 50;
/// Broadcast intervals in ticks.
pub const BROADCAST_POSITIONS_EVERY: u64 = 1;
pub const BROADCAST_SHIP_STATES_EVERY: u64 = 8;
pub const BROADCAST_MARKET_STATES_EVERY: u64 = 16;
/// Persistence sweep interval in seconds.
pub const PERSIST_SWEEP_SECS: u64 = 5;
/// Market order spread default.
pub const DEFAULT_MARKET_SPREAD: f32 = 0.10;
pub const DEFAULT_PRICE_ELASTICITY: f32 = 0.02;
/// Starting reputation for own faction vs others.
pub const OWN_FACTION_REPUTATION: u8 = 70;
pub const OTHER_FACTION_REPUTATION: u8 = 30;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tick_interval_default() {
        assert_eq!(TickConfig::DEFAULT.tick_interval_ms(), 125);
    }

    #[test]
    fn tick_scale_default() {
        let scale = TickConfig::DEFAULT.tick_scale();
        // 0.25 / 8 = 0.03125
        assert!((scale - 0.03125).abs() < 1e-6);
    }

    #[test]
    fn tick_multiplier_default() {
        // 8 / 0.25 = 32
        assert_eq!(TickConfig::DEFAULT.tick_multiplier(), 32);
    }

    #[test]
    fn all_ship_classes_have_positive_capacity() {
        for class in SHIP_CLASSES {
            assert!(class.cargo_capacity > 0, "{} cargo_capacity must be > 0", class.name);
            assert!(class.fuel_capacity > 0.0, "{} fuel_capacity must be > 0", class.name);
            assert!(class.crew_size > 0, "{} crew_size must be > 0", class.name);
            assert_eq!(
                class.crew_roles.len(),
                class.crew_size as usize,
                "{} crew_roles count must match crew_size",
                class.name
            );
        }
    }

    #[test]
    fn ship_class_lookup() {
        assert!(ship_class("freighter").is_some());
        assert!(ship_class("unknown").is_none());
    }
}
