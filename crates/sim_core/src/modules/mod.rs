//! Ship subsystem / module catalog.
//!
//! Every ship carries a fixed 5-slot fitting: Engine, CargoBay, Sensors,
//! Reactor, Comms. Each slot holds an optional module picked from the
//! static [`CATALOG`] below, keyed by a `&'static str` slug. A `ShipFitting`
//! component on the ship stores the chosen slugs and a cached
//! [`DerivedStats`] rollup; the rollup is recomputed whenever the fit
//! changes and consumed by the tick loop (transit speed, cargo capacity)
//! or by the snapshot layer (sensor range, comms bonus, power budget).
//!
//! Tier 1 is the neutral baseline (all multipliers 1.0, no absolute bonus);
//! tiers 2 and 3 improve a single stat along the slot's axis. Phase 18a
//! seeds every ship with the tier-1 default — gameplay unchanged until
//! refit mechanics (Phase 18b) let operators swap to higher tiers.
//!
//! Combat-related slots (hull, shields, weapons) are intentionally absent
//! from the catalog. They land when the combat mechanic lands; the slot
//! grid here is the economic-modifier spine it plugs into.

use serde::{Deserialize, Serialize};

/// Fixed slot types on every ship. Order matters — it's the index into
/// [`ShipFitting::slots`] arrays.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Slot {
    Engine,
    CargoBay,
    Sensors,
    Reactor,
    Comms,
}

/// Number of slots on every ship. Keeps `[Option<_>; NUM_SLOTS]` arrays
/// coherent across the codebase.
pub const NUM_SLOTS: usize = 5;

/// Canonical slot order — the one we iterate in when we need all slots.
pub const SLOTS: [Slot; NUM_SLOTS] = [
    Slot::Engine,
    Slot::CargoBay,
    Slot::Sensors,
    Slot::Reactor,
    Slot::Comms,
];

impl Slot {
    /// Index into a `[T; NUM_SLOTS]` array using canonical slot order.
    pub fn index(self) -> usize {
        match self {
            Slot::Engine => 0,
            Slot::CargoBay => 1,
            Slot::Sensors => 2,
            Slot::Reactor => 3,
            Slot::Comms => 4,
        }
    }

    /// Snake-case tag used on the wire (matches serde's rename).
    pub fn as_str(self) -> &'static str {
        match self {
            Slot::Engine => "engine",
            Slot::CargoBay => "cargo_bay",
            Slot::Sensors => "sensors",
            Slot::Reactor => "reactor",
            Slot::Comms => "comms",
        }
    }
}

/// Effects a single module contributes. Multipliers compose multiplicatively
/// across slots; additives sum.
#[derive(Debug, Clone, Copy)]
pub struct ModuleEffects {
    /// Multiplicative on transit speed. 1.0 = neutral.
    pub speed_mult: f32,
    /// Multiplicative on cargo capacity. 1.0 = neutral.
    pub cargo_capacity_mult: f32,
    /// Multiplicative on fuel consumption rate. 1.0 = neutral, <1 = saves fuel.
    pub fuel_efficiency_mult: f32,
    /// Additive sensor range in universe units. 0.0 = neutral.
    pub sensor_range_au: f32,
    /// Additive comms bonus (fraction). 0.0 = neutral; 0.05 = +5% (reserved
    /// for Phase 18f where we gate something on comms — payment bump, rep
    /// gain, contract visibility, TBD).
    pub comms_bonus: f32,
    /// Power draw from the reactor budget.
    pub power_draw: u16,
    /// Power the module provides (reactors only; 0 elsewhere).
    pub power_provided: u16,
}

pub const NEUTRAL_EFFECTS: ModuleEffects = ModuleEffects {
    speed_mult: 1.0,
    cargo_capacity_mult: 1.0,
    fuel_efficiency_mult: 1.0,
    sensor_range_au: 0.0,
    comms_bonus: 0.0,
    power_draw: 0,
    power_provided: 0,
};

/// A single catalog entry. Static — allocates nothing.
#[derive(Debug, Clone, Copy)]
pub struct ModuleDef {
    pub slug: &'static str,
    pub display_name: &'static str,
    pub slot: Slot,
    pub tier: u8,
    pub effects: ModuleEffects,
}

/// The canonical subsystem catalog.
///
/// Order: grouped by slot (Engine, CargoBay, Sensors, Reactor, Comms),
/// tiers ascending inside each group. Tier 1 of every slot is neutral
/// (1.0 multipliers, 0 additive bonus) — a ship fitted entirely at
/// tier 1 behaves identically to a pre-Phase-18 ship.
pub const CATALOG: &[ModuleDef] = &[
    // --- Engine ---
    ModuleDef {
        slug: "engine_t1",
        display_name: "Standard Drive",
        slot: Slot::Engine,
        tier: 1,
        effects: ModuleEffects {
            speed_mult: 1.0,
            fuel_efficiency_mult: 1.0,
            power_draw: 2,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "engine_t2",
        display_name: "Tuned Drive",
        slot: Slot::Engine,
        tier: 2,
        effects: ModuleEffects {
            speed_mult: 1.15,
            fuel_efficiency_mult: 0.95,
            power_draw: 4,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "engine_t3",
        display_name: "Military Drive",
        slot: Slot::Engine,
        tier: 3,
        effects: ModuleEffects {
            speed_mult: 1.30,
            fuel_efficiency_mult: 0.90,
            power_draw: 6,
            ..NEUTRAL_EFFECTS
        },
    },
    // --- Cargo Bay ---
    ModuleDef {
        slug: "cargo_bay_t1",
        display_name: "Standard Hold",
        slot: Slot::CargoBay,
        tier: 1,
        effects: ModuleEffects {
            cargo_capacity_mult: 1.0,
            power_draw: 0,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "cargo_bay_t2",
        display_name: "Expanded Hold",
        slot: Slot::CargoBay,
        tier: 2,
        effects: ModuleEffects {
            cargo_capacity_mult: 1.20,
            power_draw: 1,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "cargo_bay_t3",
        display_name: "Reinforced Hold",
        slot: Slot::CargoBay,
        tier: 3,
        effects: ModuleEffects {
            cargo_capacity_mult: 1.40,
            power_draw: 2,
            ..NEUTRAL_EFFECTS
        },
    },
    // --- Sensors ---
    ModuleDef {
        slug: "sensors_t1",
        display_name: "Basic Scanners",
        slot: Slot::Sensors,
        tier: 1,
        effects: ModuleEffects {
            sensor_range_au: 1.0,
            power_draw: 1,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "sensors_t2",
        display_name: "Long-Range Array",
        slot: Slot::Sensors,
        tier: 2,
        effects: ModuleEffects {
            sensor_range_au: 2.0,
            power_draw: 2,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "sensors_t3",
        display_name: "Survey-Grade Sensors",
        slot: Slot::Sensors,
        tier: 3,
        effects: ModuleEffects {
            sensor_range_au: 3.5,
            power_draw: 4,
            ..NEUTRAL_EFFECTS
        },
    },
    // --- Reactor ---
    ModuleDef {
        slug: "reactor_t1",
        display_name: "Fission Core",
        slot: Slot::Reactor,
        tier: 1,
        effects: ModuleEffects {
            power_provided: 10,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "reactor_t2",
        display_name: "Fusion Core",
        slot: Slot::Reactor,
        tier: 2,
        effects: ModuleEffects {
            power_provided: 15,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "reactor_t3",
        display_name: "Compact Fusion Core",
        slot: Slot::Reactor,
        tier: 3,
        effects: ModuleEffects {
            power_provided: 22,
            ..NEUTRAL_EFFECTS
        },
    },
    // --- Comms ---
    ModuleDef {
        slug: "comms_t1",
        display_name: "Standard Comms",
        slot: Slot::Comms,
        tier: 1,
        effects: ModuleEffects {
            comms_bonus: 0.0,
            power_draw: 1,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "comms_t2",
        display_name: "Encrypted Comms Suite",
        slot: Slot::Comms,
        tier: 2,
        effects: ModuleEffects {
            comms_bonus: 0.05,
            power_draw: 2,
            ..NEUTRAL_EFFECTS
        },
    },
    ModuleDef {
        slug: "comms_t3",
        display_name: "Fleet-Grade Relay",
        slot: Slot::Comms,
        tier: 3,
        effects: ModuleEffects {
            comms_bonus: 0.10,
            power_draw: 3,
            ..NEUTRAL_EFFECTS
        },
    },
];

/// Look up a module by its slug. Returns `None` if the slug isn't in the catalog
/// (e.g. stale save from before a rename).
pub fn get(slug: &str) -> Option<&'static ModuleDef> {
    CATALOG.iter().find(|m| m.slug == slug)
}

/// Intern a runtime string as a `&'static str` pointing into the catalog.
/// Used by persistence/admin paths that receive a `String` off the wire.
/// Unknown slugs return `None` so the caller can decide whether to fall
/// back to the tier-1 default.
pub fn intern_slug(slug: &str) -> Option<&'static str> {
    get(slug).map(|m| m.slug)
}

/// Return the tier-1 default slug for a slot. Panics if the catalog is
/// somehow missing a tier-1 for a slot — that's a catalog authoring bug
/// and should fail loudly in tests.
pub fn default_for_slot(slot: Slot) -> &'static str {
    CATALOG
        .iter()
        .find(|m| m.slot == slot && m.tier == 1)
        .map(|m| m.slug)
        .expect("catalog missing tier-1 entry for slot")
}

/// Build a fresh tier-1 fitting — every slot filled with the baseline
/// module. Used as the spawn default.
pub fn default_fitting() -> [Option<&'static str>; NUM_SLOTS] {
    let mut out: [Option<&'static str>; NUM_SLOTS] = [None; NUM_SLOTS];
    for slot in SLOTS.iter().copied() {
        out[slot.index()] = Some(default_for_slot(slot));
    }
    out
}

/// Iterate every module the catalog offers for `slot` — Phase 18b refit
/// UI / contract generation can list alternatives this way.
pub fn modules_for_slot(slot: Slot) -> impl Iterator<Item = &'static ModuleDef> {
    CATALOG.iter().filter(move |m| m.slot == slot)
}

/// Rolled-up effect of a full fitting. Multipliers compose
/// multiplicatively; additives sum; power draw and provision sum into
/// use/cap. Empty slots contribute nothing (neutral).
#[derive(Debug, Clone, Copy, Serialize)]
pub struct DerivedStats {
    pub speed_mult: f32,
    pub cargo_capacity_mult: f32,
    pub fuel_efficiency_mult: f32,
    pub sensor_range_au: f32,
    pub comms_bonus: f32,
    pub power_use: u16,
    pub power_cap: u16,
}

impl DerivedStats {
    pub const NEUTRAL: DerivedStats = DerivedStats {
        speed_mult: 1.0,
        cargo_capacity_mult: 1.0,
        fuel_efficiency_mult: 1.0,
        sensor_range_au: 0.0,
        comms_bonus: 0.0,
        power_use: 0,
        power_cap: 0,
    };

    /// True if total module power draw fits inside the reactor budget.
    /// Not enforced in Phase 18a (default fit fits comfortably); exposed
    /// for the UI to display an indicator and for future refit validation.
    pub fn power_ok(&self) -> bool {
        self.power_use <= self.power_cap
    }
}

/// Combine the per-slot modules into a single rollup.
pub fn combine_effects(slots: &[Option<&'static str>; NUM_SLOTS]) -> DerivedStats {
    let mut out = DerivedStats::NEUTRAL;
    for slug in slots.iter().flatten() {
        let Some(def) = get(slug) else { continue };
        out.speed_mult *= def.effects.speed_mult;
        out.cargo_capacity_mult *= def.effects.cargo_capacity_mult;
        out.fuel_efficiency_mult *= def.effects.fuel_efficiency_mult;
        out.sensor_range_au += def.effects.sensor_range_au;
        out.comms_bonus += def.effects.comms_bonus;
        out.power_use = out.power_use.saturating_add(def.effects.power_draw);
        out.power_cap = out.power_cap.saturating_add(def.effects.power_provided);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_three_tiers_per_slot() {
        for slot in SLOTS.iter().copied() {
            let count = modules_for_slot(slot).count();
            assert_eq!(count, 3, "{:?} should have 3 tiers", slot);
            for tier in 1..=3u8 {
                assert!(
                    modules_for_slot(slot).any(|m| m.tier == tier),
                    "{:?} missing tier {}",
                    slot,
                    tier
                );
            }
        }
    }

    #[test]
    fn default_fitting_is_all_tier_one() {
        let fit = default_fitting();
        for slot in SLOTS.iter().copied() {
            let slug = fit[slot.index()].expect("default fit has every slot filled");
            let def = get(slug).expect("default slug in catalog");
            assert_eq!(def.tier, 1, "default should be tier 1 for {:?}", slot);
            assert_eq!(def.slot, slot);
        }
    }

    #[test]
    fn default_fit_derived_is_neutral() {
        let fit = default_fitting();
        let d = combine_effects(&fit);
        assert!((d.speed_mult - 1.0).abs() < 1e-6);
        assert!((d.cargo_capacity_mult - 1.0).abs() < 1e-6);
        assert!((d.fuel_efficiency_mult - 1.0).abs() < 1e-6);
        assert_eq!(d.sensor_range_au, 1.0);
        assert_eq!(d.comms_bonus, 0.0);
        // power_use = 2 (engine) + 0 (cargo) + 1 (sensors) + 0 (reactor) + 1 (comms) = 4
        assert_eq!(d.power_use, 4);
        // power_cap = reactor_t1 = 10
        assert_eq!(d.power_cap, 10);
        assert!(d.power_ok());
    }

    #[test]
    fn tier_three_engine_boosts_speed() {
        let mut fit = default_fitting();
        fit[Slot::Engine.index()] = Some("engine_t3");
        let d = combine_effects(&fit);
        assert!((d.speed_mult - 1.30).abs() < 1e-6);
        assert!((d.fuel_efficiency_mult - 0.90).abs() < 1e-6);
    }

    #[test]
    fn tier_three_cargo_boosts_capacity() {
        let mut fit = default_fitting();
        fit[Slot::CargoBay.index()] = Some("cargo_bay_t3");
        let d = combine_effects(&fit);
        assert!((d.cargo_capacity_mult - 1.40).abs() < 1e-6);
    }

    #[test]
    fn empty_slot_is_neutral() {
        let mut fit = default_fitting();
        fit[Slot::Engine.index()] = None;
        let d = combine_effects(&fit);
        // With engine removed, speed_mult falls back to 1.0 (no engine
        // bonus, no penalty either at the catalog layer). Gameplay would
        // want to penalise, but that's a balancing concern, not catalog.
        assert!((d.speed_mult - 1.0).abs() < 1e-6);
    }

    #[test]
    fn intern_slug_round_trips() {
        let s = intern_slug("engine_t2").unwrap();
        assert_eq!(s, "engine_t2");
        assert!(intern_slug("does_not_exist").is_none());
    }

    #[test]
    fn slot_index_round_trips() {
        for (i, slot) in SLOTS.iter().copied().enumerate() {
            assert_eq!(slot.index(), i);
        }
    }

    #[test]
    fn power_ok_flips_when_overloaded() {
        let mut fit = default_fitting();
        fit[Slot::Engine.index()] = Some("engine_t3");
        fit[Slot::CargoBay.index()] = Some("cargo_bay_t3");
        fit[Slot::Sensors.index()] = Some("sensors_t3");
        fit[Slot::Comms.index()] = Some("comms_t3");
        // Reactor left at t1 (10 cap) while draws total 6+2+4+3 = 15.
        let d = combine_effects(&fit);
        assert!(d.power_use > d.power_cap);
        assert!(!d.power_ok());
    }
}
