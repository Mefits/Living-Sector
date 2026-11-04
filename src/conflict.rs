use serde::{Deserialize, Serialize};

pub const PIRATE_BASE: &str = "pirate-outpost";
pub const PATROL_METAL: u32 = 8;
pub const PIRATE_SEED_METAL: u32 = 16;
pub const PATROL_SEED_FUEL: u32 = 4;
pub const PATROL_DURATION: f64 = 28.0;
pub const RAID_APPROACH: f64 = 9.0;
pub const RAID_RETURN: f64 = 12.0;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Patrol {
    #[default]
    None,
    Delivering,
    Building,
    Ready,
    Destroyed,
    Rebuilding,
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
    pub pirate_fuel_stock: u32,
    pub pirate_metal: u32,
    pub raider_damaged: bool,
    pub raid_elapsed: f64,
    pub contact: f64,
    pub patrol_cycle: f64,
    pub patrol_cooldown: f64,
    pub patrol_sorties: u32,
    pub lost_ore: u32,
    pub intercepted_raids: u32,
    pub retreat_from: f64,
    pub raider_destroyed: bool,
    pub raider_damage: u32,
    pub patrol_damage: u32,
    pub rebuild_elapsed: f64,
    pub raid_approach: f64,
    pub raid_return_time: f64,
    pub raid_target: Option<String>,
    pub raid_source: Option<String>,
    pub raid_order: Option<String>,
    pub patrol_generation: u32,
    pub raider_generation: u32,
}

impl Conflict {
    pub fn approach_duration(&self) -> f64 {
        if self.raid_approach > 0.0 {
            self.raid_approach
        } else {
            RAID_APPROACH
        }
    }

    pub fn return_duration(&self) -> f64 {
        if self.raid_return_time > 0.0 {
            self.raid_return_time
        } else {
            RAID_RETURN
        }
    }

    pub fn patrol_progress(&self) -> f64 {
        self.patrol_cycle / PATROL_DURATION
    }

    pub fn near_intercept(&self) -> bool {
        (0.31..=0.74).contains(&self.patrol_progress())
    }

    pub fn heightened_alert(&self) -> bool {
        self.lost_ore > self.intercepted_raids.saturating_mul(10)
    }
}
