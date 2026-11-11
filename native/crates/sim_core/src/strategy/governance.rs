//! Galaxy 0.6 — player-defined research goal with accountable real spending.
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
/// Changing delegation mode or raising a ceiling for the SAME objective
/// must not reset amounts already paid for that objective. New research
/// target is a separately approved new mandate.
fn inherit_approved_budget(old:Option<&ResearchMandate>,new:&mut ResearchMandate,tick:u64){
    match old.filter(|previous|previous.target_technology==new.target_technology){
        Some(previous)=>{
            new.spent_cr=previous.spent_cr;
            new.created_tick=previous.created_tick;
            new.last_reason="player_policy_updated_preserving_spend".into();
        },
        None=>{
            new.spent_cr=0;
            new.created_tick=tick;
            new.last_reason="approved_in_native_director".into();
        }
    }
}
/// Engine-thread only. Always validate target against real native science.
pub fn set_mandate(
    world:&mut World,faction:&str,mut mandate:ResearchMandate,tick:u64,
)->Result<(),&'static str> {
    let Some(mut d)=world.get_resource_mut::<Director>() else{
        return Err("director_not_ready");
    };
    if !d.commanders.contains_key(faction){return Err("unknown_faction");}
    inherit_approved_budget(d.research_mandates.get(faction),&mut mandate,tick);
    mandate.validate()?;
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
    (m.mode==MandateMode::Hold || !m.completed(&commander.technologies))
        .then_some(m)
}
/// Authorization check BEFORE the native paid research shift.
pub fn authorize_research(world:&World,faction:&str,cost:i64,treasury:i64)
->Result<(),&'static str>{
    if !super::charter::may_direct(world,faction,super::charter::Department::Research){
        return Ok(()); // ordinary Genesis AI science remains independent
    }
    let Some(m)=active(world,faction) else{return Ok(());};
    match m.mode {
        MandateMode::Advise=>Ok(()),
        MandateMode::Hold=>Err("player_research_hold"),
        MandateMode::Delegated=>{
            mandate_spending_gate(m,cost,treasury)?;
            super::charter::authorize(world,faction,
                super::charter::Department::Research,cost,treasury)
        }
    }
}
fn mandate_spending_gate(m:&ResearchMandate,cost:i64,treasury:i64)
->Result<(),&'static str>{
    if cost<=0{return Err("invalid_research_charge");}
    if m.spent_cr.checked_add(cost).is_none_or(|v|v>m.budget_ceiling_cr){
        return Err("player_mandate_budget_exhausted");
    }
    if treasury.checked_sub(cost).is_none_or(|v|v<m.treasury_floor_cr){
        return Err("player_mandate_treasury_floor");
    }
    Ok(())
}
/// Call only AFTER native ECS transfer succeeded; mirror actual charge,
/// not predicted spend. The Director checkpoint persists both this
/// receipt and the existing research shift receipt together.
pub fn paid_research(world:&mut World,faction:&str,cost:i64,mandated_shift:bool){
    if !mandated_shift||cost<=0 {return;}
    let mut recorded=false;
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.research_mandates.get_mut(faction){
            if m.mode==MandateMode::Delegated {
                m.spent_cr=m.spent_cr.saturating_add(cost);
                m.last_reason="native_research_shift_paid".into();
                recorded=true;
            }
        }
    }
    if recorded {
        super::charter::record_paid(world,faction,super::charter::Department::Research,cost);
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
        let mut m=ResearchMandate{target_technology:"automation".into(),
            mode:MandateMode::Delegated,budget_ceiling_cr:260,
            treasury_floor_cr:10_000,spent_cr:0,created_tick:0,last_reason:String::new()};
        assert!(m.validate().is_ok());
        assert!(mandate_spending_gate(&m,120,20_000).is_ok());
        m.spent_cr=120;
        assert_eq!(mandate_spending_gate(&m,141,20_000),
            Err("player_mandate_budget_exhausted"));
        assert_eq!(mandate_spending_gate(&m,120,10_010),
            Err("player_mandate_treasury_floor"));
        m.budget_ceiling_cr=99;
        assert_eq!(m.validate(),Err("invalid_mandate_budget"));
    }
    #[test]
    fn switching_mode_cannot_erase_approved_research_spending(){
        let old=ResearchMandate{target_technology:"automation".into(),
            mode:MandateMode::Delegated,budget_ceiling_cr:300,
            treasury_floor_cr:10_000,spent_cr:180,
            created_tick:25,last_reason:"native_research_shift_paid".into()};
        let mut new=old.clone();
        new.mode=MandateMode::Hold;
        new.spent_cr=0;
        inherit_approved_budget(Some(&old),&mut new,50);
        assert_eq!(new.spent_cr,180);
        assert_eq!(new.created_tick,25);
        let mut smaller=new.clone();
        smaller.budget_ceiling_cr=100;
        assert_eq!(smaller.validate(),Err("invalid_committed_amount"));
        let mut next=old.clone();
        next.target_technology="deep_navigation".into();
        inherit_approved_budget(Some(&old),&mut next,70);
        assert_eq!(next.spent_cr,0);
        assert_eq!(next.created_tick,70);
    }
    #[test]
    fn old_checkpoints_read_empty_research_directives(){
        let empty=Director::default();
        let text=serde_json::to_value(&empty).unwrap();
        let copy:Director=serde_json::from_value(text).unwrap();
        assert!(copy.research_mandates.is_empty());
    }
}
