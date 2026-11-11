//! Galaxy 0.6.3 — individually quoted approvals for real native economics.
//!
//! Proposals are NOT orders. Approval only authorizes a very specific,
//! time-limited opportunity that must be quoted again by the real Genesis
//! administrators. No ECS money, cargo, ships or facilities are changed
//! during submission, review or approval. Only after a native paid receipt
//! do both the charter and proposal ledgers change.
//!
//! MVP: one economic review proposal/faction. No batch approval, no global
//! faction financial control. Existing delegated/research modes unchanged.

use bevy_ecs::prelude::World;
use serde::{Deserialize,Serialize};
use crate::economy::commodities::Commodity;
use super::{
    charter::{self,Authority,Department},
    director::Director,
    economic_mandate::{self,EconomicKind,EconomicMandate},
};

const QUOTE_TTL_TICKS:u64=600;
const REPEAT_AFTER_TICKS:u64=120;

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum ProposalStatus {
    Pending,
    Approved,
    Rejected,
    Consumed,
    Expired,
}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct EconomicProposal {
    /// Unique for each proposal issuance; never a client-provided price.
    pub proposal_id:String,
    pub location:String,
    pub commodity:Commodity,
    pub kind:EconomicKind,
    /// The native alternative, e.g. buy/build, never a browser command.
    pub action:String,
    /// Native comparator's total commitment (>= first payment).
    pub quoted_commitment_cr:i64,
    pub created_tick:u64,
    pub valid_until_tick:u64,
    pub status:ProposalStatus,
    pub last_reason:String,
    /// Exact native contract that spent this one-shot approval.
    /// Optional for pre-0.6.3 checkpoints and pending/rejected offers.
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub funded_contract_id:Option<String>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub funded_tick:Option<u64>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub funded_payment_cr:Option<i64>,
}
impl EconomicProposal {
    pub fn matches(&self,m:&EconomicMandate,action:&str,quote:i64,tick:u64)->bool{
        self.location==m.location && self.kind==m.kind &&
        self.commodity==m.commodity && self.action==action &&
        self.quoted_commitment_cr==quote && tick<=self.valid_until_tick
    }
    pub fn can_spend(&self,m:&EconomicMandate,action:&str,quote:i64,tick:u64)
        ->Result<(),&'static str>{
        if tick>self.valid_until_tick{return Err("approval_quote_expired");}
        if !self.matches(m,action,quote,tick) {
            return Err("approval_quote_changed");
        }
        if self.status!=ProposalStatus::Approved{
            return Err("specific_action_not_approved");
        }
        Ok(())
    }
}
pub fn needs_review(world:&World,faction:&str)->bool{
    world.get_resource::<Director>()
        .and_then(|d|d.faction_charters.get(faction))
        .is_some_and(|c|c.economy_authority==Authority::Review)
}
/// A proposal must refer to a REAL feasible native quote, validated by
/// the original mandate and charter limits even before showing a button.
pub fn can_offer(world:&World,faction:&str,m:&EconomicMandate,
                 quote:i64,treasury:i64)->bool{
    if !needs_review(world,faction) ||
        economic_mandate::may_commission(m,treasury,quote).is_err(){
        return false;
    }
    world.get_resource::<Director>()
        .and_then(|d|d.faction_charters.get(faction))
        .is_some_and(|c|quote>0 &&
            c.spent_cr.checked_add(quote).is_some_and(|v|v<=c.shared_ceiling_cr) &&
            treasury.checked_sub(quote)
                .is_some_and(|v|v>=c.protected_treasury_cr))
}
/// Call only after options::compare_director_target found a READY native
/// alternative. Keep an already approved/pending/rejected matching quote
/// until expiry; a funded one is briefly shown before asking again.
pub fn publish(world:&mut World,faction:&str,m:&EconomicMandate,
               action:&str,quote:i64,treasury:i64,tick:u64){
    if action.is_empty()||action.len()>48 || !can_offer(world,faction,m,quote,treasury){
        return;
    }
    let Some(mut d)=world.get_resource_mut::<Director>() else{return;};
    if let Some(old)=d.economic_proposals.get(faction) {
        if old.matches(m,action,quote,tick) {
            match old.status {
                ProposalStatus::Pending|ProposalStatus::Approved|ProposalStatus::Rejected
                    =>return,
                ProposalStatus::Consumed
                    if tick<old.created_tick.saturating_add(REPEAT_AFTER_TICKS)
                    =>return,
                _=>{},
            }
        }
    }
    let p=EconomicProposal {
        proposal_id:format!("economic-{}-{}",faction,tick),
        location:m.location.clone(),commodity:m.commodity,kind:m.kind,
        action:action.into(),quoted_commitment_cr:quote,
        created_tick:tick,
        valid_until_tick:tick.saturating_add(QUOTE_TTL_TICKS),
        status:ProposalStatus::Pending,
        last_reason:"awaiting_player_decision_no_contract_funded".into(),
        funded_contract_id:None,funded_tick:None,funded_payment_cr:None,
    };
    d.economic_proposals.insert(faction.into(),p);
}
/// Executable review uses BOTH cumulative charter tranche and a token
/// matching faction, resource, destination, action, exact quoted payment
/// and expiry. Switching the quote or objective cannot reuse an approval.
pub fn authorize_action(
    world:&World,faction:&str,m:&EconomicMandate,action:&str,
    quote:i64,treasury:i64,tick:u64,
)->Result<(),&'static str>{
    if !needs_review(world,faction){
        return charter::authorize(world,faction,Department::Economy,quote,treasury);
    }
    let p=world.get_resource::<Director>()
        .and_then(|d|d.economic_proposals.get(faction))
        .ok_or("specific_action_approval_required")?;
    p.can_spend(m,action,quote,tick)?;
    charter::authorize(world,faction,Department::Economy,quote,treasury)
}
/// The approval action runs on the native engine thread. The HTTP caller
/// can supply ONLY faction/id/decision, not quote, action, tranche or CR.
pub fn decide(
    world:&mut World,faction:&str,proposal_id:&str,approve:bool,tick:u64,
)->Result<(),&'static str>{
    let Some(mut d)=world.get_resource_mut::<Director>() else {
        return Err("director_not_ready");
    };
    if !d.commanders.contains_key(faction){return Err("unknown_faction");}
    // Validate from immutable state first. Mutate the charter and proposal
    // in separate steps; ResourceMut<Director> cannot hold simultaneous
    // immutable/mutable borrows via its DerefMut (Rust E0502).
    let m=d.economic_mandates.get(faction).ok_or("economic_mandate_missing")?;
    if !m.active(){return Err("mandate_is_not_delegated");}
    let c=d.faction_charters.get(faction).ok_or("faction_charter_missing")?;
    if c.economy_authority!=Authority::Review{
        return Err("charter_not_in_economic_review");
    }
    let p=d.economic_proposals.get(faction)
        .ok_or("specific_proposal_missing")?;
    if p.proposal_id!=proposal_id{return Err("stale_proposal_id");}
    if p.status!=ProposalStatus::Pending{return Err("proposal_already_decided");}
    if tick>p.valid_until_tick {
        let p=d.economic_proposals.get_mut(faction).unwrap();
        p.status=ProposalStatus::Expired;
        p.last_reason="proposal_expired_before_player_decision".into();
        return Err("approval_quote_expired");
    }
    if p.location!=m.location||p.kind!=m.kind||p.commodity!=m.commodity {
        return Err("proposal_target_changed");
    }
    if !approve{
        let p=d.economic_proposals.get_mut(faction).unwrap();
        p.status=ProposalStatus::Rejected;
        p.last_reason="player_rejected_specific_action".into();
        return Ok(());
    }
    let quote=p.quoted_commitment_cr;
    if quote<=0 || m.spent_cr.checked_add(quote)
        .is_none_or(|v|v>m.budget_ceiling_cr){
        return Err("mandate_limit_changed_since_quote");
    }
    if c.spent_cr.checked_add(quote).is_none_or(|v|v>c.shared_ceiling_cr){
        return Err("charter_limit_changed_since_quote");
    }
    // Approval is not payment. An already approved tranche can only be
    // consumed through the matching one-shot proposal and native receipt.
    let allowed=c.spent_economy_cr.checked_add(quote)
        .ok_or("approval_tranche_overflow")?;
    if allowed>1_000_000_000{return Err("approval_tranche_out_of_bounds");}
    let approved=c.approved_economy_cr.max(allowed);
    d.faction_charters.get_mut(faction).unwrap().approved_economy_cr=approved;
    let p=d.economic_proposals.get_mut(faction).unwrap();
    p.status=ProposalStatus::Approved;
    p.last_reason="player_approved_exact_native_quote_not_funded".into();
    Ok(())
}
/// A funded *specific* native contract, verified by the coordinator.
/// Never consume an approval on a faction-wide aggregate, a research
/// charge, an unrelated project, or a contract with a different action.
pub fn native_paid(
    world:&mut World,faction:&str,amount:i64,contract_id:&str,action:&str,tick:u64
){
    if amount<=0||contract_id.is_empty(){return;}
    if let Some(mut d)=world.get_resource_mut::<Director>() {
        let target_matches=d.economic_mandates.get(faction)
            .zip(d.economic_proposals.get(faction))
            .is_some_and(|(m,p)|p.location==m.location &&
                p.kind==m.kind && p.commodity==m.commodity);
        if !target_matches {return;}
        if let Some(p)=d.economic_proposals.get_mut(faction) {
            if p.status==ProposalStatus::Approved &&
                tick<=p.valid_until_tick && p.action==action &&
                amount<=p.quoted_commitment_cr {
                p.status=ProposalStatus::Consumed;
                p.funded_contract_id=Some(contract_id.into());
                p.funded_tick=Some(tick);
                p.funded_payment_cr=Some(amount);
                p.last_reason="native_faction_contract_receipt_linked".into();
            }
        }
    }
}
pub fn expire(world:&mut World,tick:u64){
    if let Some(mut d)=world.get_resource_mut::<Director>() {
        for p in d.economic_proposals.values_mut() {
            if tick>p.valid_until_tick &&
                matches!(p.status,ProposalStatus::Pending|ProposalStatus::Approved) {
                p.status=ProposalStatus::Expired;
                p.last_reason="native_quote_expired_recheck_required".into();
            }
        }
    }
}
#[cfg(test)]
mod galaxy063_specific_approvals_tests {
    use super::*;
    fn mandate()->EconomicMandate{
        EconomicMandate{
            kind:EconomicKind::Industry,location:"Mars".into(),
            commodity:Commodity::Electronics,min_stock:200,
            mode:super::super::governance::MandateMode::Delegated,
            budget_ceiling_cr:30000,treasury_floor_cr:10000,
            spent_cr:0,created_tick:0,last_commitment_tick:None,last_reason:String::new(),
        }
    }
    fn proposal()->EconomicProposal{
        EconomicProposal{
            proposal_id:"economic-own-120".into(),
            location:"Mars".into(),commodity:Commodity::Electronics,
            kind:EconomicKind::Industry,action:"build".into(),
            quoted_commitment_cr:25000,created_tick:120,
            valid_until_tick:720,status:ProposalStatus::Pending,
            last_reason:String::new(),
            funded_contract_id:None,funded_tick:None,funded_payment_cr:None,
        }
    }
    #[test]
    fn approval_requires_exact_action_and_quote_and_faction_scoped_lookup(){
        let mut p=proposal();
        let m=mandate();
        assert_eq!(p.can_spend(&m,"build",25000,121),
            Err("specific_action_not_approved"));
        p.status=ProposalStatus::Approved;
        assert!(p.can_spend(&m,"build",25000,122).is_ok());
        assert_eq!(p.can_spend(&m,"buy",25000,122),
            Err("approval_quote_changed"));
        assert_eq!(p.can_spend(&m,"build",25001,122),
            Err("approval_quote_changed"));
        assert_eq!(p.can_spend(&m,"build",25000,721),
            Err("approval_quote_expired"));
        let mut altered=m.clone();
        altered.location="Earth".into();
        assert_eq!(p.can_spend(&altered,"build",25000,122),
            Err("approval_quote_changed"));
    }
    #[test]
    fn denial_or_consumption_never_authorizes_new_native_contract(){
        let mut p=proposal();let m=mandate();
        p.status=ProposalStatus::Rejected;
        assert_eq!(p.can_spend(&m,"build",25000,122),
            Err("specific_action_not_approved"));
        p.status=ProposalStatus::Consumed;
        assert_eq!(p.can_spend(&m,"build",25000,123),
            Err("specific_action_not_approved"));
    }
    #[test]
    fn native_receipt_links_only_the_approved_action_and_real_contract(){
        let mut world=World::new();
        let mut director=Director::default();
        director.economic_mandates.insert("own".into(),mandate());
        let mut approval=proposal();
        approval.status=ProposalStatus::Approved;
        director.economic_proposals.insert("own".into(),approval);
        world.insert_resource(director);
        native_paid(&mut world,"own",10000,"contract-other","deliver",125);
        assert_eq!(world.resource::<Director>().economic_proposals["own"].status,
            ProposalStatus::Approved);
        native_paid(&mut world,"other",10000,"contract-other","build",125);
        assert_eq!(world.resource::<Director>().economic_proposals["own"].status,
            ProposalStatus::Approved);
        native_paid(&mut world,"own",26000,"contract-overspend","build",125);
        assert_eq!(world.resource::<Director>().economic_proposals["own"].status,
            ProposalStatus::Approved);
        native_paid(&mut world,"own",10000,"contract-verified","build",125);
        let receipt=&world.resource::<Director>().economic_proposals["own"];
        assert_eq!(receipt.status,ProposalStatus::Consumed);
        assert_eq!(receipt.funded_contract_id.as_deref(),Some("contract-verified"));
        assert_eq!(receipt.funded_payment_cr,Some(10000));
        assert_eq!(receipt.funded_tick,Some(125));
        native_paid(&mut world,"own",10000,"contract-repeat","build",126);
        assert_eq!(world.resource::<Director>().economic_proposals["own"]
            .funded_contract_id.as_deref(),Some("contract-verified"));
    }
    #[test]
    fn pre_receipt_json_still_deserializes_without_new_fields(){
        let mut old=serde_json::to_value(proposal()).unwrap();
        let obj=old.as_object_mut().unwrap();
        obj.remove("funded_contract_id");obj.remove("funded_tick");
        obj.remove("funded_payment_cr");
        let loaded:EconomicProposal=serde_json::from_value(old).unwrap();
        assert!(loaded.funded_contract_id.is_none());
    }
    #[test]
    fn old_save_contains_no_approval_tokens(){
        let d=Director::default();
        let copy:Director=serde_json::from_value(serde_json::to_value(&d).unwrap()).unwrap();
        assert!(copy.economic_proposals.is_empty());
    }
}
