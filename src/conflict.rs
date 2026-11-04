use serde::{Deserialize, Serialize};

pub const PIRATE_BASE: &str = "pirate-outpost";
pub const PATROL_METAL: u32 = 8;
pub const PIRATE_SEED_METAL: u32 = 16;
pub const PATROL_SEED_FUEL: u32 = 4;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Patrol {
    #[default]
    None,
    Delivering,
    Building,
    Ready,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct Conflict {
    pub base_ready: bool,
    pub base_progress: f64,
    pub pirate_loot: u32,
    pub raider_cargo: u32,
    pub raider_return: f64,
    pub raider_fuel: u32,
    pub patrol: Patrol,
    pub patrol_elapsed: f64,
    pub patrol_fuel: u32,
    pub escorted: bool,
    pub patrol_home_earth: bool,
    pub intercepted: bool,
}
