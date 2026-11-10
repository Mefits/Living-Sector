"""Galaxy05 E5: persistent station tier and upgrade construction state.

The E1 tier rules get a real durable project representation. Existing
Director SQLite frame persists this together with the native economy.
Snapshot projects are actual receipts, not proposed milestones.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
server=root/"crates/sim_server/src"
def one(path,old,new):
    s=path.read_text(encoding="utf8")
    if s.count(old)!=1:raise RuntimeError(f"Galaxy05 E5 anchor drift {path}: {old[:60]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

p=core/"strategy/director.rs"
one(p,
  """    pub ai_execution: planning::NativeExecution,
}""",
  """    pub ai_execution: planning::NativeExecution,
    /// Saved atomically with native credits, stock and receipts.
    #[serde(default)]
    pub station_progress: BTreeMap<String,super::progression::StationDevelopment>,
}""")
p=core/"strategy.rs"
one(p,
  """    pub technologies: Vec<director::Technology>,
    /// Read-only persisted plan ledger""",
  """    pub technologies: Vec<director::Technology>,
    #[serde(default)]
    pub station_progress: BTreeMap<String,progression::StationDevelopment>,
    /// Read-only persisted plan ledger""")
one(p,
  """            technologies:director::TECHNOLOGIES.to_vec(), ai_execution:None }""",
  """            technologies:director::TECHNOLOGIES.to_vec(),
            station_progress:BTreeMap::new(), ai_execution:None }""")
p=server/"snapshot.rs"
one(p,
  """                snapshot.commanders = world.get_resource::<sim_core::strategy::director::Director>().map(|d|d.commanders.clone()).unwrap_or_default();""",
  """                snapshot.commanders = world.get_resource::<sim_core::strategy::director::Director>().map(|d|d.commanders.clone()).unwrap_or_default();
                snapshot.station_progress = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.station_progress.clone()).unwrap_or_default();""")
p=core/"strategy/progression.rs"
s=p.read_text(encoding="utf8")
if "struct StationDevelopment" in s:raise RuntimeError("E5 already installed")
s+=r'''

/// Persistent native upgrade state, not the XP level of an individual
/// facility. The absent record on old saves means a T1 core.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct StationDevelopment {
    pub tier:StationTier,
    pub target:Option<StationTier>,
    pub materials_installed:bool,
    pub labor_completed:u32,
    pub last_labor_tick:Option<u64>,
    pub last_receipt_tick:Option<u64>,
    pub blocked_reason:String,
}
pub const fn native_upgrade_bill(target:StationTier)->&'static [(crate::economy::commodities::Commodity,u32)]{
    use crate::economy::commodities::Commodity as C;
    match target {
        StationTier::T1=>&[],
        StationTier::T2=>&[(C::Metals,240),(C::Components,100),(C::Alloys,40)],
        StationTier::T3=>&[(C::Alloys,160),(C::Electronics,80),(C::QuantumCores,36)],
    }
}
pub const fn upgrade_work(target:StationTier)->u32{
    match target {StationTier::T1=>0,StationTier::T2=>150,StationTier::T3=>250}
}
pub fn core_tier(world:&bevy_ecs::prelude::World,id:&str)->StationTier{
    world.get_resource::<super::director::Director>()
        .and_then(|d|d.station_progress.get(id))
        .map_or(StationTier::T1,|state|state.tier)
}
#[cfg(test)]
mod galaxy05_core_progress_tests {
    use super::*;
    #[test]
    fn old_world_t1_and_native_material_bills_are_nonempty() {
        let old:StationDevelopment=serde_json::from_str("{}").unwrap();
        assert_eq!(old.tier,StationTier::T1);
        assert!(!old.materials_installed);
        assert_eq!(upgrade_work(StationTier::T2),150);
        assert_eq!(upgrade_work(StationTier::T3),250);
        assert_eq!(native_upgrade_bill(StationTier::T2).len(),3);
        assert_eq!(native_upgrade_bill(StationTier::T3).len(),3);
    }
}
'''
p.write_text(s,encoding="utf8")
print("Galaxy05 E5: native station tier and upgrade status persist in Director and /api/strategy")
