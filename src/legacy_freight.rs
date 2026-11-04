use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FreightPhase {
    #[default]
    Waiting,
    Loading,
    Outbound,
    Unloading,
    Returning,
    NoFuelAtBelt,
    NoFuelAtEarth,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Freighter {
    pub phase: FreightPhase,
    pub elapsed: f64,
    pub fuel: u32,
    pub cargo: u32,
    pub fuel_cargo: u32,
    pub fuel_order: bool,
    pub outbound_duration: f64,
    pub return_duration: f64,
}
