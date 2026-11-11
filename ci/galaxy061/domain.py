"""Galaxy 0.6.1 — durable economic mandate policy, no independent economy.

An approved player directive chooses a priority and limits NEW native
contract commitments. Neither this policy nor the HTTP handler creates
money, stock, construction, ships or artificial production receipts.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy061 domain anchor drift {path.name}: {n} {old[:100]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(core/"strategy.rs",
    "pub mod governance;\npub mod planning;",
    "pub mod governance;\npub mod economic_mandate;\npub mod planning;")

one(core/"strategy/director.rs",
    """    pub research_mandates:BTreeMap<String,super::governance::ResearchMandate>,
}""",
    """    pub research_mandates:BTreeMap<String,super::governance::ResearchMandate>,
    /// The player can authorize one real economic goal per faction.
    #[serde(default)]
    pub economic_mandates:BTreeMap<String,super::economic_mandate::EconomicMandate>,
}""")

one(core/"strategy.rs",
    """    pub research_mandates: BTreeMap<String,governance::ResearchMandate>,
    /// Read-only persisted plan ledger""",
    """    pub research_mandates: BTreeMap<String,governance::ResearchMandate>,
    #[serde(default)]
    pub economic_mandates: BTreeMap<String,economic_mandate::EconomicMandate>,
    /// Read-only persisted plan ledger""")
one(core/"strategy.rs",
    """            research_mandates:BTreeMap::new(), ai_execution:None }""",
    """            research_mandates:BTreeMap::new(),
            economic_mandates:BTreeMap::new(), ai_execution:None }""")

path=core/"strategy/economic_mandate.rs"
if path.exists():raise RuntimeError("economic mandate module already installed")
path.write_text(r'''//! Player economic intent, converted to an ordinary native shortage or
//! production goal. The same head, administrators, contracts, escrow and
//! cargo-delivery receipts remain responsible for all execution.

use bevy_ecs::prelude::World;
use serde::{Serialize,Deserialize};
use crate::economy::commodities::Commodity;
use super::{Goal,director::Director,governance::MandateMode};

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum EconomicKind {
    Supply,
    Industry,
}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct EconomicMandate {
    pub kind:EconomicKind,
    pub location:String,
    pub commodity:Commodity,
    pub min_stock:u32,
    pub mode:MandateMode,
    pub budget_ceiling_cr:i64,
    pub treasury_floor_cr:i64,
    #[serde(default)]
    pub spent_cr:i64,
    #[serde(default)]
    pub created_tick:u64,
    #[serde(default)]
    pub last_commitment_tick:Option<u64>,
    #[serde(default)]
    pub last_reason:String,
}
impl EconomicMandate {
    pub fn validate(&self)->Result<(),&'static str>{
        if self.location.is_empty()||self.location.len()>160
           || self.location.bytes().any(|b|b<32) {
            return Err("invalid_station_location");
        }
        if self.min_stock<10||self.min_stock>5_000 {
            return Err("invalid_stock_target");
        }
        if self.budget_ceiling_cr<100||self.budget_ceiling_cr>1_000_000_000
            ||self.treasury_floor_cr<10_000||self.treasury_floor_cr>1_000_000_000 {
            return Err("invalid_mandate_finances");
        }
        if self.spent_cr<0||self.spent_cr>self.budget_ceiling_cr {
            return Err("invalid_committed_amount");
        }
        if self.kind==EconomicKind::Supply &&
           !matches!(self.commodity,Commodity::Food|Commodity::Water|Commodity::Fuel|
                Commodity::Metals|Commodity::Components|Commodity::Electronics|
                Commodity::Tools|Commodity::Alloys) {
            return Err("unsupported_supply_commodity");
        }
        if self.kind==EconomicKind::Industry &&
           !matches!(self.commodity,Commodity::Food|Commodity::Water|Commodity::Fuel|
                Commodity::Metals|Commodity::Components|Commodity::Electronics|
                Commodity::Tools|Commodity::Alloys|Commodity::QuantumCores) {
            return Err("unsupported_industry_commodity");
        }
        Ok(())
    }
    pub fn goal_id(&self)->&'static str {
        match self.kind {
            EconomicKind::Supply=>"player_supply",
            EconomicKind::Industry=>"player_industry",
        }
    }
    pub fn key(&self)->(&str,&str,Commodity,EconomicKind){
        (&self.location,self.goal_id(),self.commodity,self.kind)
    }
    pub fn active(&self)->bool {self.mode==MandateMode::Delegated}
    pub fn requested(&self,stock:f32)->bool {
        stock.is_finite() && stock>=0.0 && stock<(self.min_stock as f32)
    }
    pub fn goal(&self,stock:f32)->Option<Goal>{
        (self.active()&&(self.kind==EconomicKind::Industry||self.requested(stock))).then(||Goal{
            goal_id:self.goal_id().into(),
            commodity:self.commodity,
            destination:self.location.clone(),
            // Existing urgency field remains for native shortage priority.
            shortage_ticks:1000,
            score:150.0,
        })
    }
}
/// A *built* native facility with a matching real recipe exists at the
/// station. This is NOT proof of paid production: input goods, staffing,
/// faction research and actual shift receipts are separate requirements.
pub fn native_producer_exists(
    world:&mut World,faction:&str,location:&str,commodity:Commodity
)->bool{
    use crate::agents::facility::{FacilityIdentity,FacilityLocation};
    world.query::<(&FacilityIdentity,&FacilityLocation)>().iter(world).any(
        |(id,loc)|id.faction_id==faction &&
            loc.location_name==location &&
            crate::economy::recipes::RECIPES.iter().any(
                |recipe|recipe.facility_type==id.facility_type &&
                    recipe.outputs.iter().any(|&(c,_)|c==commodity))
    )
}
/// Existing per-shift/reward/escrow spending remains in Genesis. This
/// is only authorization for an additional *mandated* native proposal.
pub fn may_commission(m:&EconomicMandate,treasury:i64,payment:i64)->Result<(),&'static str>{
    if !m.active(){return Err("player_mandate_not_delegated");}
    if payment<=0{return Err("invalid_mandated_native_payment");}
    if m.spent_cr.checked_add(payment).is_none_or(|v|v>m.budget_ceiling_cr) {
        return Err("player_mandate_budget_exhausted");
    }
    if treasury.checked_sub(payment).is_none_or(|v|v<m.treasury_floor_cr){
        return Err("player_mandate_treasury_floor");
    }
    Ok(())
}
/// The game tick validates location ownership against actual ECS market
/// control. Never trust a player's submitted location name alone.
pub fn set_mandate(
    world:&mut World,faction:&str,mut incoming:EconomicMandate,tick:u64
)->Result<(),&'static str>{
    incoming.validate()?;
    let valid_location=world.query::<(
        &crate::agents::facility::FacilityIdentity,
        &crate::agents::facility::FacilityLocation
    )>().iter(world).any(|(id,loc)|id.faction_id==faction &&
        id.facility_type=="station"&&loc.location_name==incoming.location);
    if !valid_location{return Err("station_not_owned_by_faction");}
    let Some(mut d)=world.get_resource_mut::<Director>() else {
        return Err("director_not_ready");
    };
    if !d.commanders.contains_key(faction){return Err("unknown_faction");}
    if let Some(old)=d.economic_mandates.get(faction).filter(|old|old.key()==incoming.key()){
        // Reconfiguration must not reset the amount already committed to
        // actual native contracts. Lowering budget below spend is rejected.
        incoming.spent_cr=old.spent_cr;
        incoming.created_tick=old.created_tick;
        incoming.last_commitment_tick=old.last_commitment_tick;
    }else {
        incoming.spent_cr=0;
        incoming.created_tick=tick;
        incoming.last_commitment_tick=None;
    }
    incoming.validate()?;
    incoming.last_reason="approved_native_governance".into();
    d.economic_mandates.insert(faction.to_owned(),incoming);
    Ok(())
}
pub fn clear_mandate(world:&mut World,faction:&str)->bool{
    world.get_resource_mut::<Director>()
        .and_then(|mut d|d.economic_mandates.remove(faction))
        .is_some()
}
pub fn actual_commit(world:&mut World,faction:&str,amount:i64,tick:u64){
    if amount<=0{return;}
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.economic_mandates.get_mut(faction){
            if m.last_commitment_tick==Some(tick){return;}
            m.spent_cr=m.spent_cr.saturating_add(amount);
            m.last_commitment_tick=Some(tick);
            m.last_reason="native_contract_funded_not_yet_delivered".into();
        }
    }
}
pub fn status(world:&mut World,faction:&str,reason:&str){
    if let Some(mut d)=world.get_resource_mut::<Director>(){
        if let Some(m)=d.economic_mandates.get_mut(faction) {
            if m.last_reason!=reason{m.last_reason=reason.into();}
        }
    }
}
#[cfg(test)]
mod galaxy061_economic_mandates_tests {
    use super::*;
    fn directive(kind:EconomicKind,commodity:Commodity)->EconomicMandate {
        EconomicMandate{kind,commodity,location:"colony".into(),min_stock:200,
            mode:MandateMode::Delegated,budget_ceiling_cr:600,
            treasury_floor_cr:10000,spent_cr:0,created_tick:0,
            last_commitment_tick:None,last_reason:String::new()}
    }
    #[test]
    fn target_requires_real_market_stock_not_a_year_gate(){
        let m=directive(EconomicKind::Supply,Commodity::Water);
        assert_eq!(m.goal(0.0).unwrap().goal_id,"player_supply");
        assert!(m.goal(200.0).is_none());
        assert!(m.goal(f32::NAN).is_none());
        assert_eq!(m.goal_id(),"player_supply");
    }
    #[test]
    fn industrial_capacity_goal_is_not_confused_with_current_stock(){
        let m=directive(EconomicKind::Industry,Commodity::Electronics);
        assert!(m.goal(400.0).is_some());
        assert_eq!(m.goal(400.0).unwrap().goal_id,"player_industry");
        // Whether this target has already been built is checked against
        // real ECS facilities by the coordinator before granting orders.
    }
    #[test]
    fn mandated_native_credit_cap_never_mints_money(){
        let mut m=directive(EconomicKind::Industry,Commodity::Electronics);
        assert!(may_commission(&m,20000,450).is_ok());
        m.spent_cr=450;
        assert_eq!(may_commission(&m,20000,151),
            Err("player_mandate_budget_exhausted"));
        assert_eq!(may_commission(&m,10020,100),
            Err("player_mandate_treasury_floor"));
        assert_eq!(may_commission(&m,20000,0),
            Err("invalid_mandated_native_payment"));
    }
    #[test]
    fn type_and_amount_validation_is_explicit(){
        let mut m=directive(EconomicKind::Supply,Commodity::Ore);
        assert_eq!(m.validate(),Err("unsupported_supply_commodity"));
        m.commodity=Commodity::Water;
        assert!(m.validate().is_ok());
        m.spent_cr=601;
        assert_eq!(m.validate(),Err("invalid_committed_amount"));
    }
    #[test]
    fn pause_and_advice_do_not_create_directive_goals(){
        let mut m=directive(EconomicKind::Supply,Commodity::Food);
        m.mode=MandateMode::Advise;
        assert!(m.goal(0.0).is_none());
        m.mode=MandateMode::Hold;
        assert!(m.goal(0.0).is_none());
    }
}
''',encoding="utf8")
print("Galaxy 0.6.1: economic mandates with goal validation, preserved limits, real station ownership and unit tests")
