//! Facility subsystem / module catalog (Phase 18e).
//!
//! The parallel of `crate::modules` for facilities. Every non-gate
//! facility carries a `FacilityFitting` with two slots (Production
//! and Automation); modules in those slots multiply recipe output
//! and boost max-batches-per-cycle respectively. Gates are skipped
//! because they don't run recipes.
//!
//! Tier 1 is the neutral baseline (no effect) so pre-Phase-18e
//! seeds behave identically once upgraded to this shape. Tiers 2
//! and 3 improve a single stat along the slot's axis.
//!
//! Facilities don't earn XP → retrofit points the way ships do
//! yet — facility upgrades land via the admin refit endpoint
//! today. When facility-side retrofit behaviour arrives it'll
//! mirror the ship model (bank-one-per-level, spend when credits
//! allow), just without the "travel to a yard" leg.

use serde::{Deserialize, Serialize};

/// Slot grid every facility carries. Kept short on purpose — more
/// slots can be added once the two live ones are exercised.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FacilitySlot {
    /// Multiplies recipe output per cycle. Mining rigs use it for
    /// extraction yield; refineries, factories, farms, shipyards
    /// use it for recipe produce.
    Production,
    /// Adds to `max_batches` per recipe cycle — a level-3
    /// automation module lets a refinery smelt 2 more batches of
    /// metal each cycle without climbing the facility level track.
    Automation,
}

pub const NUM_FACILITY_SLOTS: usize = 2;
pub const FACILITY_SLOTS: [FacilitySlot; NUM_FACILITY_SLOTS] =
    [FacilitySlot::Production, FacilitySlot::Automation];

impl FacilitySlot {
    pub fn index(self) -> usize {
        match self {
            FacilitySlot::Production => 0,
            FacilitySlot::Automation => 1,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            FacilitySlot::Production => "production",
            FacilitySlot::Automation => "automation",
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct FacilityModuleEffects {
    /// Multiplies every recipe's output. 1.0 = neutral.
    pub recipe_output_mult: f32,
    /// Adds to `max_batches` per recipe cycle. 0 = neutral.
    pub max_batches_bonus: u32,
}

pub const FACILITY_NEUTRAL_EFFECTS: FacilityModuleEffects = FacilityModuleEffects {
    recipe_output_mult: 1.0,
    max_batches_bonus: 0,
};

#[derive(Debug, Clone, Copy)]
pub struct FacilityModuleDef {
    pub slug: &'static str,
    pub display_name: &'static str,
    pub slot: FacilitySlot,
    pub tier: u8,
    pub effects: FacilityModuleEffects,
}

pub const FACILITY_CATALOG: &[FacilityModuleDef] = &[
    // --- Production (recipe output multiplier) ---
    FacilityModuleDef {
        slug: "production_t1",
        display_name: "Standard Production Line",
        slot: FacilitySlot::Production,
        tier: 1,
        effects: FacilityModuleEffects {
            recipe_output_mult: 1.0,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
    FacilityModuleDef {
        slug: "production_t2",
        display_name: "Tuned Production Line",
        slot: FacilitySlot::Production,
        tier: 2,
        effects: FacilityModuleEffects {
            recipe_output_mult: 1.15,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
    FacilityModuleDef {
        slug: "production_t3",
        display_name: "Precision Production Suite",
        slot: FacilitySlot::Production,
        tier: 3,
        effects: FacilityModuleEffects {
            recipe_output_mult: 1.30,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
    // --- Automation (max_batches bonus) ---
    FacilityModuleDef {
        slug: "automation_t1",
        display_name: "Manual Controls",
        slot: FacilitySlot::Automation,
        tier: 1,
        effects: FacilityModuleEffects {
            max_batches_bonus: 0,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
    FacilityModuleDef {
        slug: "automation_t2",
        display_name: "Supervised Automation",
        slot: FacilitySlot::Automation,
        tier: 2,
        effects: FacilityModuleEffects {
            max_batches_bonus: 1,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
    FacilityModuleDef {
        slug: "automation_t3",
        display_name: "Full Automation Suite",
        slot: FacilitySlot::Automation,
        tier: 3,
        effects: FacilityModuleEffects {
            max_batches_bonus: 2,
            ..FACILITY_NEUTRAL_EFFECTS
        },
    },
];

pub fn get(slug: &str) -> Option<&'static FacilityModuleDef> {
    FACILITY_CATALOG.iter().find(|m| m.slug == slug)
}

pub fn intern_slug(slug: &str) -> Option<&'static str> {
    get(slug).map(|m| m.slug)
}

pub fn default_for_slot(slot: FacilitySlot) -> &'static str {
    FACILITY_CATALOG
        .iter()
        .find(|m| m.slot == slot && m.tier == 1)
        .map(|m| m.slug)
        .expect("facility catalog missing tier-1 entry for slot")
}

pub fn default_fitting() -> [Option<&'static str>; NUM_FACILITY_SLOTS] {
    let mut out: [Option<&'static str>; NUM_FACILITY_SLOTS] = [None; NUM_FACILITY_SLOTS];
    for slot in FACILITY_SLOTS.iter().copied() {
        out[slot.index()] = Some(default_for_slot(slot));
    }
    out
}

pub fn modules_for_slot(slot: FacilitySlot) -> impl Iterator<Item = &'static FacilityModuleDef> {
    FACILITY_CATALOG.iter().filter(move |m| m.slot == slot)
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct FacilityDerivedStats {
    pub recipe_output_mult: f32,
    pub max_batches_bonus: u32,
}

impl FacilityDerivedStats {
    pub const NEUTRAL: FacilityDerivedStats = FacilityDerivedStats {
        recipe_output_mult: 1.0,
        max_batches_bonus: 0,
    };
}

pub fn combine_effects(
    slots: &[Option<&'static str>; NUM_FACILITY_SLOTS],
) -> FacilityDerivedStats {
    let mut out = FacilityDerivedStats::NEUTRAL;
    for slug in slots.iter().flatten() {
        let Some(def) = get(slug) else { continue };
        out.recipe_output_mult *= def.effects.recipe_output_mult;
        out.max_batches_bonus = out
            .max_batches_bonus
            .saturating_add(def.effects.max_batches_bonus);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_three_tiers_per_slot() {
        for slot in FACILITY_SLOTS.iter().copied() {
            assert_eq!(modules_for_slot(slot).count(), 3);
            for tier in 1..=3u8 {
                assert!(modules_for_slot(slot).any(|m| m.tier == tier));
            }
        }
    }

    #[test]
    fn default_fitting_is_neutral() {
        let fit = default_fitting();
        let d = combine_effects(&fit);
        assert!((d.recipe_output_mult - 1.0).abs() < 1e-6);
        assert_eq!(d.max_batches_bonus, 0);
    }

    #[test]
    fn tier_three_production_boosts_output() {
        let mut fit = default_fitting();
        fit[FacilitySlot::Production.index()] = Some("production_t3");
        let d = combine_effects(&fit);
        assert!((d.recipe_output_mult - 1.30).abs() < 1e-6);
    }

    #[test]
    fn tier_three_automation_adds_two_batches() {
        let mut fit = default_fitting();
        fit[FacilitySlot::Automation.index()] = Some("automation_t3");
        let d = combine_effects(&fit);
        assert_eq!(d.max_batches_bonus, 2);
    }

    #[test]
    fn empty_slot_is_neutral() {
        let mut fit = default_fitting();
        fit[FacilitySlot::Production.index()] = None;
        let d = combine_effects(&fit);
        assert!((d.recipe_output_mult - 1.0).abs() < 1e-6);
    }
}
