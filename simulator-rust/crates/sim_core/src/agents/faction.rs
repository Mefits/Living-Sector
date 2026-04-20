//! Faction components.
//!
//! Factions are small in count (~6) but referenced frequently by other agents.
//! Single combined component is fine — no cache-locality benefit to splitting.

use crate::ai::personality::Personality;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct FactionColors {
    pub primary: String,
    pub secondary: String,
}

#[derive(Debug, Clone)]
pub struct FactionData {
    pub id: String,
    pub name: String,
    pub faction_type: String,
    pub home_system: String,
    pub treasury: i64,
    pub personality: Personality,
    pub colors: FactionColors,
    pub dirty: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct FactionSnapshot {
    pub id: String,
    pub name: String,
    pub faction_type: String,
    pub home_system: String,
    pub treasury: i64,
    pub colors: FactionColors,
}

impl FactionSnapshot {
    pub fn build(data: &FactionData) -> Self {
        Self {
            id: data.id.clone(),
            name: data.name.clone(),
            faction_type: data.faction_type.clone(),
            home_system: data.home_system.clone(),
            treasury: data.treasury,
            colors: data.colors.clone(),
        }
    }
}
