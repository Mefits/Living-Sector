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

// ============================================================================
// Faction tick
// ============================================================================
//
// Every N base-ticks, each faction collects a tax from its owned facilities
// and adds it to its treasury. Simple proportional skim (default 5%).
//
// Reputation decay and faction-posted contracts are future work (Phase 8c+).

use crate::agents::facility::{FacilityIdentity, FacilityOperations};

/// Base-tick interval for faction accounting.
pub const FACTION_INTERVAL_BASE: u64 = 50;
/// Fraction of each facility's credits moved to the faction each cycle.
pub const FACTION_TAX_RATE: f64 = 0.05;

pub fn tick_factions(world: &mut hecs::World, tick: u64, tick_multiplier: u32) {
    let interval = FACTION_INTERVAL_BASE * tick_multiplier as u64;
    if interval == 0 || tick % interval != 0 {
        return;
    }

    // Pass 1: collect taxes to remit per faction, deducting from facilities.
    let mut owed_by_faction: std::collections::HashMap<String, i64> =
        std::collections::HashMap::new();
    for (_e, (identity, ops)) in world
        .query::<(&FacilityIdentity, &mut FacilityOperations)>()
        .iter()
    {
        if identity.faction_id.is_empty() || ops.credits <= 0 {
            continue;
        }
        let tax = ((ops.credits as f64) * FACTION_TAX_RATE) as i64;
        if tax > 0 {
            ops.credits -= tax;
            *owed_by_faction.entry(identity.faction_id.clone()).or_insert(0) += tax;
        }
    }

    if owed_by_faction.is_empty() {
        return;
    }

    // Pass 2: deposit into faction treasuries.
    for (_e, data) in world.query_mut::<&mut FactionData>() {
        if let Some(&amount) = owed_by_faction.get(&data.id) {
            data.treasury += amount;
            data.dirty = true;
        }
    }
}
