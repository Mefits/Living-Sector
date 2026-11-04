use serde::{Deserialize, Serialize};

pub const PIRATE_BASE: &str = "pirate-outpost";
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
    #[serde(skip_serializing)]
    pub pirate_loot: u32,
    #[serde(skip_serializing)]
    pub raider_cargo: u32,
    #[serde(skip_serializing)]
    pub raider_return: f64,
    #[serde(skip_serializing)]
    pub raider_fuel: u32,
    #[serde(skip_serializing)]
    pub patrol: Patrol,
    #[serde(skip_serializing)]
    pub patrol_elapsed: f64,
    #[serde(skip_serializing)]
    pub patrol_fuel: u32,
    #[serde(skip_serializing)]
    pub pirate_fuel_stock: u32,
    #[serde(skip_serializing)]
    pub pirate_metal: u32,
    #[serde(skip_serializing)]
    pub raider_damaged: bool,
    #[serde(skip_serializing)]
    pub raid_elapsed: f64,
    #[serde(skip_serializing)]
    pub contact: f64,
    #[serde(skip_serializing)]
    pub patrol_cycle: f64,
    #[serde(skip_serializing)]
    pub patrol_cooldown: f64,
    #[serde(skip_serializing)]
    pub patrol_sorties: u32,
    pub lost_ore: u32,
    pub intercepted_raids: u32,
    #[serde(skip_serializing)]
    pub retreat_from: f64,
    #[serde(skip_serializing)]
    pub raider_destroyed: bool,
    #[serde(skip_serializing)]
    pub raider_damage: u32,
    #[serde(skip_serializing)]
    pub patrol_damage: u32,
    #[serde(skip_serializing)]
    pub rebuild_elapsed: f64,
    #[serde(skip_serializing)]
    pub raid_approach: f64,
    #[serde(skip_serializing)]
    pub raid_return_time: f64,
    #[serde(skip_serializing)]
    pub raid_target: Option<String>,
    #[serde(skip_serializing)]
    pub raid_source: Option<String>,
    #[serde(skip_serializing)]
    pub raid_order: Option<String>,
    #[serde(skip_serializing)]
    pub patrol_generation: u32,
    #[serde(skip_serializing)]
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
}
