"""Galaxy 0.5 E1: native-tier domain for FUTURE ECS integrations.

This overlay only adds a pure rules module. It does NOT grant tech,
spawn facilities, alter money, or pretend that the proposed T2/T3
recipes are live. Real world integration belongs to E2–E7.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
path=root/"crates/sim_core/src/strategy.rs"
before="pub mod director;\npub mod planning;"
after="pub mod director;\npub mod progression;\npub mod planning;"
content=path.read_text(encoding="utf8")
if content.count(before)!=1:
    raise RuntimeError("Galaxy 0.5 progression module anchor changed")
path.write_text(content.replace(before,after,1),encoding="utf8")
module=root/"crates/sim_core/src/strategy/progression.rs"
if module.exists():
    raise RuntimeError("Galaxy 0.5 progression Rust module already exists")
module.write_text(r'''//! Galaxy 0.5 domain rules for *real* station tier upgrades.
 //!
 //! This module is deliberately pure: it knows no ECS, credits,
 //! stock ledgers, construction receipts, docking capacity, or
 //! artificial progress. A higher tier is never inferred from
 //! how many building glyphs are rendered on the Observer map.
 //!
 //! E2–E7 will read the actual world and native paid construction
 //! receipts before persisting an upgrade. T2/T3 resources still
 //! require their own real production implementation.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StationTier {
    #[default] T1,
    T2,
    T3,
}

impl StationTier {
    pub const fn max_modules(self) -> usize {
        match self {Self::T1=>4, Self::T2=>5, Self::T3=>6}
    }

    pub const fn next(self) -> Option<Self> {
        match self {Self::T1=>Some(Self::T2), Self::T2=>Some(Self::T3), Self::T3=>None}
    }

    pub const fn research_gate(self) -> Option<&'static str> {
        match self {
            Self::T1=>None,
            Self::T2=>Some("structuretech2"),
            Self::T3=>Some("structuretech3"),
        }
    }
}

/// This only checks counts passed by the caller. It is NOT a
/// building-spawn capability and does not create a reserved slot.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SlotAvailability {
    Available{remaining:usize},
    Full{capacity:usize},
    InvalidCounts,
}

pub fn available_slot(tier:StationTier, built:usize, native_in_progress:usize)->SlotAvailability {
    let Some(occupied)=built.checked_add(native_in_progress) else {
        return SlotAvailability::InvalidCounts;
    };
    let cap=tier.max_modules();
    if occupied>=cap {SlotAvailability::Full{capacity:cap}}
    else {SlotAvailability::Available{remaining:cap-occupied}}
}

/// The research gate may only be consulted BEFORE a real funded site starts.
/// Actual paid goods and labor are checked by the native executor and
/// must be revalidated again before commitment; this function never
/// upgrades or creates station tiers.
pub fn upgrade_research_ready(
    current:StationTier, target:StationTier, completed:&[String]
)->bool {
    current.next()==Some(target) &&
    target.research_gate().is_some_and(|id|completed.iter().any(|t|t==id))
}

/// Design-mapping metadata, not recipes that Genesis is allowed to execute.
pub struct CampaignDependency {
    pub milestone:&'static str,
    pub must_follow:&'static [&'static str],
    pub tier:StationTier,
    pub native:bool,
}
pub const CAMPAIGN_DEPENDENCIES:&[CampaignDependency]=&[
    CampaignDependency{milestone:"alloytech2", must_follow:&["automation"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"drilltech2", must_follow:&["alloytech2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"rare_ore", must_follow:&["drilltech2","survey2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"alloys", must_follow:&["rare_ore","alloyplant2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"station2", must_follow:&["alloys","structuretech2"],tier:StationTier::T2,native:false},
    CampaignDependency{milestone:"crystal_ore", must_follow:&["drill3","survey3"],tier:StationTier::T3,native:false},
    CampaignDependency{milestone:"quantum_cores", must_follow:&["crystal_ore","qfab3"],tier:StationTier::T3,native:false},
    CampaignDependency{milestone:"station3", must_follow:&["quantum_cores","structuretech3"],tier:StationTier::T3,native:false},
];

#[cfg(test)]
mod galaxy05_progression_tests {
    use super::*;

    #[test]
    fn tier_slot_limits_and_old_save_default() {
        assert_eq!(StationTier::default(), StationTier::T1);
        assert_eq!(StationTier::T1.max_modules(),4);
        assert_eq!(StationTier::T2.max_modules(),5);
        assert_eq!(StationTier::T3.max_modules(),6);
        assert_eq!(serde_json::from_str::<StationTier>(r#""t2""#).unwrap(),StationTier::T2);
        assert_eq!(serde_json::to_string(&StationTier::T3).unwrap(),r#""t3""#);
    }

    #[test]
    fn construction_is_an_occupied_slot_before_completion() {
        assert_eq!(available_slot(StationTier::T1,3,1),SlotAvailability::Full{capacity:4});
        assert_eq!(available_slot(StationTier::T1,3,0),SlotAvailability::Available{remaining:1});
        assert_eq!(available_slot(StationTier::T2,3,1),SlotAvailability::Available{remaining:1});
        assert_eq!(available_slot(StationTier::T3,3,1),SlotAvailability::Available{remaining:2});
        assert_eq!(available_slot(StationTier::T1,usize::MAX,5),SlotAvailability::InvalidCounts);
    }

    #[test]
    fn research_without_a_paid_build_does_not_change_tier() {
        let unlocked=vec!["structuretech2".into(),"structuretech3".into()];
        assert!(upgrade_research_ready(StationTier::T1,StationTier::T2,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T1,StationTier::T3,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T2,StationTier::T2,&unlocked));
        assert!(!upgrade_research_ready(StationTier::T2,StationTier::T3,&[]));
        // Function only returns a gate verdict; there is no upgrade side effect.
        assert_eq!(StationTier::default(),StationTier::T1);
    }

    #[test]
    fn all_design_nodes_still_explicitly_marked_unimplemented() {
        assert!(CAMPAIGN_DEPENDENCIES.iter().all(|entry|!entry.native));
        assert!(CAMPAIGN_DEPENDENCIES.iter().any(|d|d.milestone=="station3" &&
            d.must_follow.contains(&"quantum_cores")));
    }
}
''',encoding="utf8")
print("Galaxy 0.5 E1: pure tier and slot rules compiled into sim_core, without fictional goods/tech")
