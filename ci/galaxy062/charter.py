"""Galaxy 0.6.2: persisted faction charter and shared mandate arbiter.

Run AFTER Galaxy 0.6.1. All mutations are to extracted CI source;
main/stable and the immutable ZIP inputs are untouched.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:
        raise RuntimeError(f"Galaxy062 charter anchor drift {path}: {n} {old[:90]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(core/"strategy.rs",
    "pub mod economic_mandate;\npub mod planning;",
    "pub mod economic_mandate;\npub mod charter;\npub mod planning;")
one(core/"strategy/director.rs",
    """    pub economic_mandates:BTreeMap<String,super::economic_mandate::EconomicMandate>,
}""",
    """    pub economic_mandates:BTreeMap<String,super::economic_mandate::EconomicMandate>,
    /// Optional player charter. No charter preserves Galaxy 0.6.1 behaviour.
    #[serde(default)]
    pub faction_charters:BTreeMap<String,super::charter::FactionCharter>,
}""")
one(core/"strategy.rs",
    """    pub economic_mandates: BTreeMap<String,economic_mandate::EconomicMandate>,
    /// Read-only persisted plan ledger""",
    """    pub economic_mandates: BTreeMap<String,economic_mandate::EconomicMandate>,
    #[serde(default)]
    pub faction_charters: BTreeMap<String,charter::FactionCharter>,
    /// Read-only persisted plan ledger""")
one(core/"strategy.rs",
    """            economic_mandates:BTreeMap::new(), ai_execution:None }""",
    """            economic_mandates:BTreeMap::new(),
            faction_charters:BTreeMap::new(), ai_execution:None }""")

p=core/"strategy/charter.rs"
if p.exists(): raise RuntimeError("Galaxy062 charter already present")
p.write_text(r'''//! Galaxy 0.6.2 — conservative player charter over NATIVE mandates.
//! Explicitly not a second economy or authority over survival AI.
//! Only NEW paid research shifts or contracts ATTRIBUTED to delegated
//! player mandates consume the charter envelope. Emergency food/water,
//! autonomous wages, and existing prepaid contracts stay with Genesis.
use bevy_ecs::prelude::World;
use serde::{Deserialize,Serialize};
use super::director::Director;

#[derive(Copy,Clone,Debug,PartialEq,Eq,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum Department { Research, Economy }

#[derive(Copy,Clone,Debug,PartialEq,Eq,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum Authority { Delegated, Review, Autonomous }

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct FactionCharter {
    pub research_authority:Authority,
    pub economy_authority:Authority,
    /// 0..100: ranks competing *player* goals, never survival or paid plans.
    pub research_priority:u8,
    pub economy_priority:u8,
    /// A shared cumulative CR limit on NEW player-mandated commitments.
    pub shared_ceiling_cr:i64,
    pub protected_treasury_cr:i64,
    /// In review mode the player explicitly approves a cumulative tranche.
    /// Increasing the tranche is the approval action; never a new purse.
    pub approved_research_cr:i64,
    pub approved_economy_cr:i64,
    #[serde(default)] pub spent_cr:i64,
    #[serde(default)] pub spent_research_cr:i64,
    #[serde(default)] pub spent_economy_cr:i64,
    #[serde(default)] pub updated_tick:u64,
    #[serde(default)] pub last_reason:String,
}
impl FactionCharter {
    pub fn validate(&self)->Result<(),&'static str>{
        if self.shared_ceiling_cr<100||self.shared_ceiling_cr>1_000_000_000 ||
           self.protected_treasury_cr<10_000||
           self.protected_treasury_cr>1_000_000_000 {
            return Err("invalid_charter_budget_or_reserve");
        }
        if self.research_priority>100||self.economy_priority>100 {
            return Err("invalid_charter_priority");
        }
        if self.approved_research_cr<0||self.approved_economy_cr<0||
            self.approved_research_cr>1_000_000_000||
            self.approved_economy_cr>1_000_000_000 {
            return Err("invalid_approval_tranche");
        }
        if self.spent_cr<0||self.spent_research_cr<0||self.spent_economy_cr<0||
            self.spent_research_cr.checked_add(self.spent_economy_cr)!=Some(self.spent_cr)||
            self.spent_cr>self.shared_ceiling_cr {
            return Err("invalid_charter_ledger");
        }
        if self.research_authority==Authority::Review &&
            self.approved_research_cr<self.spent_research_cr {
            return Err("research_approval_below_paid_receipts");
        }
        if self.economy_authority==Authority::Review &&
            self.approved_economy_cr<self.spent_economy_cr {
            return Err("economy_approval_below_paid_receipts");
        }
        Ok(())
    }
    fn authority(&self,dept:Department)->Authority{
        match dept {
            Department::Research=>self.research_authority,
            Department::Economy=>self.economy_authority,
        }
    }
    fn approval_left(&self,dept:Department)->i64{
        match dept {
            Department::Research=>self.approved_research_cr-self.spent_research_cr,
            Department::Economy=>self.approved_economy_cr-self.spent_economy_cr,
        }
    }
    pub fn gate(&self,dept:Department,payment:i64,treasury:i64)
        ->Result<(),&'static str>{
        if self.authority(dept)==Authority::Autonomous{
            return Err("player_mandates_disabled_in_charter");
        }
        if payment<=0 {return Err("invalid_native_payment");}
        if self.spent_cr.checked_add(payment)
            .is_none_or(|n|n>self.shared_ceiling_cr) {
            return Err("shared_mandate_budget_exhausted");
        }
        if treasury.checked_sub(payment)
            .is_none_or(|n|n<self.protected_treasury_cr) {
            return Err("charter_treasury_reserve");
        }
        if self.authority(dept)==Authority::Review &&
            payment>self.approval_left(dept) {
            return Err("player_approval_required");
        }
        Ok(())
    }
}
/// Immutable checkpoint-free default: the original 0.6.1 mandates work
/// as before until a player explicitly installs a charter.
pub fn authorize(world:&World,faction:&str,dept:Department,payment:i64,treasury:i64)
    ->Result<(),&'static str> {
    world.get_resource::<Director>()
        .and_then(|d|d.faction_charters.get(faction))
        .map_or(Ok(()),|c|c.gate(dept,payment,treasury))
}
pub fn may_direct(world:&World,faction:&str,dept:Department)->bool{
    world.get_resource::<Director>()
        .and_then(|d|d.faction_charters.get(faction))
        .is_none_or(|c|c.authority(dept)!=Authority::Autonomous)
}
pub fn priority_score(world:&World,faction:&str,dept:Department,default:f64)->f64{
    let priority=world.get_resource::<Director>()
        .and_then(|d|d.faction_charters.get(faction))
        .map(|c|match dept{
            Department::Research=>c.research_priority,
            Department::Economy=>c.economy_priority,
        });
    priority.map_or(default,|p|default+2.0*(f64::from(p)-50.0))
}
/// Only the engine control thread may apply a charter. Reconfiguration
/// cannot erase previous paid commitments even if priorities change.
pub fn set_charter(world:&mut World,faction:&str,mut incoming:FactionCharter,tick:u64)
    ->Result<(),&'static str>{
    let Some(mut director)=world.get_resource_mut::<Director>() else {
        return Err("director_not_ready");
    };
    if !director.commanders.contains_key(faction){return Err("unknown_faction");}
    if let Some(old)=director.faction_charters.get(faction){
        incoming.spent_cr=old.spent_cr;
        incoming.spent_research_cr=old.spent_research_cr;
        incoming.spent_economy_cr=old.spent_economy_cr;
    }else {
        incoming.spent_cr=0;
        incoming.spent_research_cr=0;
        incoming.spent_economy_cr=0;
    }
    incoming.updated_tick=tick;
    incoming.validate()?;
    incoming.last_reason="charter_applied_native_engine".into();
    director.faction_charters.insert(faction.into(),incoming);
    Ok(())
}
/// Called only after the original native executor reports money paid.
/// Never mutate treasury, a contract, a research shift or a ship here.
pub fn record_paid(world:&mut World,faction:&str,dept:Department,amount:i64){
    if amount<=0{return;}
    if let Some(mut director)=world.get_resource_mut::<Director>(){
        if let Some(c)=director.faction_charters.get_mut(faction){
            c.spent_cr=c.spent_cr.saturating_add(amount);
            match dept {
                Department::Research=>{
                    c.spent_research_cr=c.spent_research_cr.saturating_add(amount);
                },
                Department::Economy=>{
                    c.spent_economy_cr=c.spent_economy_cr.saturating_add(amount);
                },
            }
            c.last_reason="native_paid_receipt_recorded".into();
        }
    }
}
#[cfg(test)]
mod galaxy062_charter_tests {
    use super::*;
    fn charter()->FactionCharter {
        FactionCharter{
            research_authority:Authority::Review,
            economy_authority:Authority::Delegated,
            research_priority:80,economy_priority:35,
            shared_ceiling_cr:1000,protected_treasury_cr:10000,
            approved_research_cr:200,approved_economy_cr:0,
            spent_cr:0,spent_research_cr:0,spent_economy_cr:0,
            updated_tick:0,last_reason:String::new(),
        }
    }
    #[test]
    fn review_requires_an_explicit_funded_tranche(){
        let mut c=charter();
        assert!(c.gate(Department::Research,180,20000).is_ok());
        assert_eq!(c.gate(Department::Research,220,20000),
            Err("player_approval_required"));
        c.spent_cr=180;c.spent_research_cr=180;
        assert_eq!(c.gate(Department::Research,50,20000),
            Err("player_approval_required"));
        c.approved_research_cr=300;
        assert!(c.gate(Department::Research,50,20000).is_ok());
        assert_eq!(c.gate(Department::Economy,900,20000),
            Err("shared_mandate_budget_exhausted"));
    }
    #[test]
    fn protected_treasury_wins_over_player_priority(){
        let mut c=charter();
        assert_eq!(c.gate(Department::Economy,100,10020),
            Err("charter_treasury_reserve"));
        c.economy_authority=Authority::Autonomous;
        assert_eq!(c.gate(Department::Economy,10,20000),
            Err("player_mandates_disabled_in_charter"));
        c.economy_priority=101;
        assert_eq!(c.validate(),Err("invalid_charter_priority"));
    }
    #[test]
    fn never_accept_reset_or_retroactive_lowering(){
        let mut c=charter();
        c.spent_cr=300;c.spent_research_cr=300;
        assert_eq!(c.validate(),Err("research_approval_below_paid_receipts"));
        c.approved_research_cr=350;
        assert!(c.validate().is_ok());
        c.shared_ceiling_cr=250;
        assert_eq!(c.validate(),Err("invalid_charter_ledger"));
        c.shared_ceiling_cr=400;
        c.spent_economy_cr=20;
        assert_eq!(c.validate(),Err("invalid_charter_ledger"));
    }
    #[test]
    fn old_checkpoint_has_no_new_charter(){
        let d=Director::default();
        let copy:Director=serde_json::from_value(serde_json::to_value(&d).unwrap()).unwrap();
        assert!(copy.faction_charters.is_empty());
    }
}
''',encoding="utf8")
print("Galaxy062: native persistent faction charter with shared receipts and review approvals")
