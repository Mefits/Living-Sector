use crate::builds::Faction;
use crate::freight::ShipRole;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Leader {
    #[default]
    Cautious,
    Industrial,
}

impl Leader {
    pub fn label(self) -> &'static str {
        match self {
            Self::Cautious => "Осторожный",
            Self::Industrial => "Промышленник",
        }
    }

    pub fn reserve(self) -> u32 {
        match self {
            Self::Cautious => 48,
            Self::Industrial => 24,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Policy {
    #[default]
    Output,
    Reserve,
}

impl Policy {
    pub fn label(self) -> &'static str {
        match self {
            Self::Output => "Промышленный выпуск",
            Self::Reserve => "Сохранение резерва",
        }
    }

    pub fn ore_target(self) -> u32 {
        match self {
            Self::Output => 20,
            Self::Reserve => 10,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct Governance {
    pub leader: Leader,
    pub policy: Policy,
    pub ore_requested: bool,
    pub last_decision: Option<String>,
    pressure: f64,
    pub assessments: BTreeMap<Faction, Assessment>,
    pub economies: BTreeMap<Faction, EconomyPolicy>,
}

impl Governance {
    pub fn review(&mut self, fuel: u32, step: f64) -> Option<String> {
        let threshold = self.leader.reserve();
        let next = match self.policy {
            Policy::Output if fuel <= threshold => Some(Policy::Reserve),
            Policy::Reserve if fuel >= threshold + 4 => Some(Policy::Output),
            _ => None,
        };
        if let Some(policy) = next {
            self.pressure += step;
            if self.pressure >= 2.0 {
                self.pressure = 0.0;
                self.policy = policy;
                let reason = format!("Топливо {fuel}. Курс: {}", policy.label());
                self.last_decision = Some(reason.clone());
                return Some(reason);
            }
        } else {
            self.pressure = 0.0;
        }
        None
    }

    pub fn fuel_floor(&self) -> u32 {
        match self.policy {
            Policy::Output => 0,
            Policy::Reserve => self.leader.reserve(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct EconomyPolicy {
    pub home: String,
    pub fuel_reserve: u32,
    pub fuel_target: u32,
    #[serde(default)]
    pub military: Option<ShipRole>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct Assessment {
    pub open_cargo: u64,
    pub missing_freighters: u64,
    pub damage: u32,
    pub threat: bool,
    pub military_demand: bool,
    pub ore_need: bool,
    pub ore_stock: u32,
    pub metal_stock: u32,
    pub fuel_stock: u32,
    pub storage_blocked: bool,
    pub reserve_fuel: u32,
    pub priority: String,
    pub blockers: Vec<String>,
}
