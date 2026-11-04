use serde::{Deserialize, Serialize};

pub const SITE: &str = "earth-yard";
pub const YARD_METAL: u32 = 16;
pub const SHIP_METAL: u32 = 8;
pub const COMMISSION_FUEL: u32 = 8;
pub const TRAVEL: f64 = 4.0;
pub const ASSEMBLY: f64 = 6.0;
pub const SHIP_BUILD: f64 = 8.0;
pub const TRANSFER: f64 = 8.0;
pub const BUILDER_FUEL: u32 = 4;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Project {
    #[default]
    WaitingMaterials,
    Hauling,
    Assembling,
    Returning,
    WaitingShip,
    BuildingShip,
    TransferringShip,
    Complete,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct Construction {
    pub phase: Project,
    pub elapsed: f64,
    pub active_second: bool,
    pub parked_fuel: u32,
}

impl Construction {
    pub fn builder_fuel(&self) -> u32 {
        match self.phase {
            Project::WaitingMaterials => BUILDER_FUEL * 2,
            Project::Hauling | Project::Assembling => BUILDER_FUEL,
            _ => 0,
        }
    }

    pub fn duration(&self) -> f64 {
        match self.phase {
            Project::Hauling | Project::Returning => TRAVEL,
            Project::Assembling => ASSEMBLY,
            Project::BuildingShip => SHIP_BUILD,
            Project::TransferringShip => TRANSFER,
            _ => f64::INFINITY,
        }
    }

    pub fn yard_ready(&self) -> bool {
        matches!(
            self.phase,
            Project::Returning
                | Project::WaitingShip
                | Project::BuildingShip
                | Project::TransferringShip
                | Project::Complete
        )
    }
}
