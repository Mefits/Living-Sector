//! Static catalog of crew-mission templates.
//!
//! Each facility type has a set of missions it can post — a mining rig
//! looks for heavy maintenance, a station books security details, a farm
//! needs harvest help. Each template carries everything `facility_agent`
//! needs at post time (duration / payment / required skill) and what the
//! apply phase needs at completion (skill XP to grant).
//!
//! Catalog is code-driven for the same reason Elixir's was: it's small
//! enough today that a JSON layer would be churn without payoff.
//! Promoted to a data file later if the list grows or authors want to
//! hand-tune.
//!
//! ## Shape
//!
//! A `Mission` holds:
//!  * `category` — stable slug (e.g. `"security_detail"`), serialized on the
//!    wire and used as a foreign key
//!  * `display_name` — Godot shows this in the contracts list
//!  * `posted_by` — facility types that can post this mission
//!  * `duration_ticks` — base ticks before completion (scaled by mult at post)
//!  * `base_payment` — credits paid to the ship on completion
//!  * `required_skill` — which `ShipCrewSkills` field grows
//!  * `skill_gain` — XP amount granted to that skill
//!
//! Mirrors `simulator/lib/simulator/economy/mission_catalog.ex` 1:1.

/// A single mission template. Static — does not allocate.
#[derive(Debug, Clone, Copy)]
pub struct Mission {
    pub category: &'static str,
    pub display_name: &'static str,
    pub posted_by: &'static [&'static str],
    pub duration_ticks: u64,
    pub base_payment: i64,
    /// Skill name on `ShipCrewSkills` that grows on completion. One of
    /// "navigation", "engineering", "trading", "combat".
    pub required_skill: &'static str,
    pub skill_gain: u8,
}

/// All mission templates. Order is stable; don't reshuffle without
/// checking callers that pick by index.
pub const CATALOG: &[Mission] = &[
    Mission {
        category: "security_detail",
        display_name: "Security Detail",
        posted_by: &["station"],
        duration_ticks: 30,
        base_payment: 1500,
        required_skill: "combat",
        skill_gain: 3,
    },
    Mission {
        category: "vip_escort",
        display_name: "VIP Escort",
        posted_by: &["station"],
        duration_ticks: 20,
        base_payment: 1200,
        required_skill: "navigation",
        skill_gain: 2,
    },
    Mission {
        category: "customs_assist",
        display_name: "Customs Assist",
        posted_by: &["station"],
        duration_ticks: 15,
        base_payment: 800,
        required_skill: "trading",
        skill_gain: 2,
    },
    Mission {
        category: "heavy_maintenance",
        display_name: "Heavy Maintenance",
        posted_by: &["mining_rig", "refinery"],
        duration_ticks: 40,
        base_payment: 2000,
        required_skill: "engineering",
        skill_gain: 3,
    },
    Mission {
        category: "salvage_operation",
        display_name: "Salvage Operation",
        posted_by: &["mining_rig"],
        duration_ticks: 35,
        base_payment: 1800,
        required_skill: "engineering",
        skill_gain: 2,
    },
    Mission {
        category: "production_assist",
        display_name: "Production Assist",
        posted_by: &["factory"],
        duration_ticks: 25,
        base_payment: 1400,
        required_skill: "engineering",
        skill_gain: 2,
    },
    Mission {
        category: "equipment_calibration",
        display_name: "Equipment Calibration",
        posted_by: &["factory", "refinery"],
        duration_ticks: 20,
        base_payment: 1100,
        required_skill: "engineering",
        skill_gain: 2,
    },
    Mission {
        category: "harvest_help",
        display_name: "Harvest Help",
        posted_by: &["farm"],
        duration_ticks: 30,
        base_payment: 1200,
        required_skill: "navigation", // "general" skill maps to navigation
        skill_gain: 1,
    },
    Mission {
        category: "safety_audit",
        display_name: "Safety Audit",
        posted_by: &["refinery"],
        duration_ticks: 25,
        base_payment: 1500,
        required_skill: "engineering",
        skill_gain: 2,
    },
];

/// Return every mission a facility of `facility_type` can post.
/// Unknown types yield an empty iterator.
pub fn for_facility_type(
    facility_type: &str,
) -> impl Iterator<Item = &'static Mission> + use<'_> {
    CATALOG
        .iter()
        .filter(move |m| m.posted_by.contains(&facility_type))
}

/// Look up a mission template by its stable `category` slug. Round-trips
/// a contract string → template on apply.
pub fn get(category: &str) -> Option<&'static Mission> {
    CATALOG.iter().find(|m| m.category == category)
}

/// Unique facility types that post at least one mission.
pub fn supported_facility_types() -> Vec<&'static str> {
    let mut seen: Vec<&'static str> = Vec::new();
    for m in CATALOG {
        for t in m.posted_by {
            if !seen.contains(t) {
                seen.push(*t);
            }
        }
    }
    seen
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_nine_templates() {
        // Covers the Elixir catalog 1:1 — any additions should be mirrored here.
        assert_eq!(CATALOG.len(), 9);
    }

    #[test]
    fn mining_rig_missions() {
        let m: Vec<_> = for_facility_type("mining_rig").collect();
        assert!(m.iter().any(|x| x.category == "heavy_maintenance"));
        assert!(m.iter().any(|x| x.category == "salvage_operation"));
    }

    #[test]
    fn unknown_facility_has_no_missions() {
        assert_eq!(for_facility_type("xenomorph_hive").count(), 0);
    }

    #[test]
    fn get_by_category() {
        assert_eq!(get("security_detail").unwrap().base_payment, 1500);
        assert!(get("not_a_real_category").is_none());
    }

    #[test]
    fn supported_types_list_covers_catalog() {
        let types = supported_facility_types();
        assert!(types.contains(&"station"));
        assert!(types.contains(&"mining_rig"));
        assert!(types.contains(&"farm"));
    }
}
