"""Galaxy 0.6: durable player governance of real Genesis research.

Only science is executable in this FIRST vertical slice. All ordinary
ship, facility, colony, and market decisions remain autonomous.
The player's directive constrains actual treasury expense; a selected
research goal never creates resources, ships, or fictional receipts.
"""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
CORE=ROOT/"crates/sim_core/src"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy06 source drift {path} found {n}: {old[:85]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(CORE/"strategy.rs",
    "pub mod director;\npub mod progression;\npub mod planning;",
    "pub mod director;\npub mod progression;\npub mod governance;\npub mod planning;")

path=CORE/"strategy/governance.rs"
if path.exists():raise RuntimeError("Governance module already exists")
path.write_text(r'''//! Galaxy 0.6 — player-defined research goal with accountable real spending.
//!
//! One active research mandate per faction for the first integration.
//! This is not an AI planner: it only authorizes and prioritizes goals.
//! Native Director::research remains the sole executor of CR, electronics,
//! staff shifts and research receipts. No second treasury or parallel world.

use bevy_ecs::prelude::World;
use serde::{Serialize,Deserialize};
use super::director::{Director,Technology,TECHNOLOGIES};

#[derive(Copy,Clone,Debug,PartialEq,Eq,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum MandateMode {
    Delegated,
    Advise,
    Hold,
}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct ResearchMandate {
    /// Final long-horizon tech. Missing prerequisites are pursued first.
    pub target_technology:String,
    pub mode:MandateMode,
    /// Maximum cumulative paid CR for THIS approved directive.
    pub budget_ceiling_cr:i64,
    /// Hard reserve, applied when this mandate is making paid shifts.
    pub treasury_floor_cr:i64,
    #[serde(default)]
    pub spent_cr:i64,
    #[serde(default)]
    pub created_tick:u64,
    #[serde(default)]
    pub last_reason:String,
}
impl ResearchMandate {
    pub fn validate(&self)->Result<(),&'static str>{
        if self.budget_ceiling_cr<100 || self.budget_ceiling_cr>1_000_000_000 {
            return Err("invalid_mandate_budget");
        }
        if self.treasury_floor_cr<10_000||self.treasury_floor_cr>1_000_000_000{
            return Err("invalid_treasury_floor");
        }
        if !TECHNOLOGIES.iter().any(|t|t.id==self.target_technology) {
            return Err("unknown_technology");
        }
        if self.spent_cr<0||self.spent_cr>self.budget_ceiling_cr {
            return Err("invalid_committed_amount");
        }
        Ok(())
    }
    pub fn completed(&self,known:&[String])->bool{
        known.iter().any(|x|x==&self.target_technology)
    }
}
/// Resolve a final long-term goal into the next legally researchable
/// prerequisite. No annual unlock dates; only the actual native tech graph.
pub fn next_technology(
    target:&str, known:&[String]
)->Result<Option<&'static Technology>, &'static str> {
    let mut next=TECHNOLOGIES.iter().find(|t|t.id==target)
        .ok_or("unknown_technology")?;
    for _ in 0..TECHNOLOGIES.len() {
        if known.iter().any(|x|x==next.id) {return Ok(None);}
        if let Some(needed)=next.prerequisite {
            if !known.iter().any(|x|x==needed) {
                next=TECHNOLOGIES.iter().find(|t|t.id==needed)
                    .ok_or("invalid_technology_graph")?;
                continue;
            }
        }
        return Ok(Some(next));
    }
    Err("technology_dependency_cycle")
}
/// Engine-thread only. Always validate target against real native science.
pub fn set_mandate(
    world:&mut World,faction:&str,mut mandate:ResearchMandate,tick:u64,
)->Result<(),&'static str> {
    mandate.spent_cr=0;
    mandate.created_tick=tick;
    mandate.last_reason="approved_in_native_director".into();
    mandate.validate()?;
    let Some(mut d)=world.get_resource_mut::<Director>() else{
        return Err("director_not_ready");
    };
    if !d.commanders.contains_key(faction){return Err("unknown_faction");}
    d.research_mandates.insert(faction.to_string(),mandate);
    Ok(())
}
pub fn clear_mandate(world:&mut World,faction:&str)->bool{
    world.get_resource_mut::<Director>()
        .and_then(|mut d|d.research_mandates.remove(faction))
        .is_some()
}
pub fn active<'a>(world:&'a World,faction:&str)->Option<&'a ResearchMandate>{
    let d=world.get_resource::<Director>()?;
    let m=d.research_mandates.get(faction)?;
    let commander=d.commanders.get(faction)?;
    (!m.completed(&commander.technologies)).then_some(m)
}
/// Authorization check BEFORE the native paid research shift.
pub fn authorize_research(world:&World,faction:&str,cost:i64,treasury:i64)
->Result<(),&'static str>{
    let Some(m)=active(world,faction) else{return Ok(());};
    match m.mode {
        MandateMode::Advise=>Ok(()),
        MandateMode::Hold=>Err("player_research_hold"),
        MandateMode::Delegated=>{
            if cost<=0{return Err("invalid_research_charge");}
            if m.spent_cr.checked_add(cost).is_none_or(|v|v>m.budget_ceiling_cr){
                return Err("player_mandate_budget_exhausted");
            }
            if treasury.checked_sub(cost).is_none_or(|v|v<m.treasury_floor_cr){
                return Err("player_mandate_treasury_floor");
            }
            Ok(())
        }
    }
}
/// Call only AFTER native ECS transfer succeeded; mirror actual charge,
/// not predicted spend. The Director checkpoint persists both this
/// receipt and the existing research shift receipt together.
pub fn paid_research(world:&mut World,faction:&str,cost:i64){
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.research_mandates.get_mut(faction){
            if m.mode==MandateMode::Delegated {
                m.spent_cr=m.spent_cr.saturating_add(cost);
                m.last_reason="native_research_shift_paid".into();
            }
        }
    }
}

#[cfg(test)]
mod galaxy06_mandates_tests {
    use super::*;

    #[test]
    fn no_year_gates_and_technology_prerequisites_are_real(){
        let tech=TECHNOLOGIES.iter().find(|x|x.id=="automation").unwrap();
        let next=next_technology("automation",&[]).unwrap().unwrap();
        assert_eq!(next.id,"industrial_methods");
        assert_eq!(next_technology("automation",&["industrial_methods".into()])
            .unwrap().unwrap().id,"automation");
        assert!(next_technology("automation",&["industrial_methods".into(),
            "automation".into()]).unwrap().is_none());
        assert_eq!(tech.field,"industry");
    }
    #[test]
    fn delegated_budget_and_reserve_are_enforced_without_creating_cash(){
        let mut world=World::new();
        let mut d=Director::default();
        // Minimal commander data: active() reads only its real tech list.
        // Full native observer/science payment is exercised by existing tests.
        let fixture=crate::strategy::tests::fixture(super::super::Mode::Execute);
        world=fixture.0;
        world.insert_resource(d.clone());
        super::super::director::observe(&mut world,&fixture.1,60,1);
        d=world.resource::<Director>().clone();
        assert!(d.commanders.contains_key("own"));
        let directive=ResearchMandate{target_technology:"automation".into(),
            mode:MandateMode::Delegated,budget_ceiling_cr:260,
            treasury_floor_cr:10_000,spent_cr:0,created_tick:0,last_reason:String::new()};
        set_mandate(&mut world,"own",directive,61).unwrap();
        assert!(authorize_research(&world,"own",120,20_000).is_ok());
        paid_research(&mut world,"own",120);
        assert_eq!(world.resource::<Director>().research_mandates["own"].spent_cr,120);
        assert_eq!(authorize_research(&world,"own",141,20_000),
            Err("player_mandate_budget_exhausted"));
        assert_eq!(authorize_research(&world,"own",120,10_010),
            Err("player_mandate_treasury_floor"));
        let mut h=world.resource::<Director>().research_mandates["own"].clone();
        h.mode=MandateMode::Hold;
        set_mandate(&mut world,"own",h,62).unwrap();
        assert_eq!(authorize_research(&world,"own",100,20_000),
            Err("player_research_hold"));
    }
    #[test]
    fn old_checkpoints_read_empty_research_directives(){
        let empty=Director::default();
        let text=serde_json::to_value(&empty).unwrap();
        let copy:Director=serde_json::from_value(text).unwrap();
        assert!(copy.research_mandates.is_empty());
    }
}
''',encoding="utf8")
print("Galaxy06: durable budgeted research mandate domain with real prerequisite resolver and tests")
