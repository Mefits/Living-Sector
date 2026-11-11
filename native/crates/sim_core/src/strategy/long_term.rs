//! Faction head's persistent native production intent.
//! The intent survives head priority changes and director checkpoints, but is
//! NOT a second HTN ledger or a second source of contracts, payroll or stock.
//! Every milestone is derived again from ECS, native receipts and the board.
use super::{construction::{self,ConstructionView},director::Director,
    production_chain,Goal,StrategyState,Mode};
use crate::agents::faction::FactionData;
use crate::economy::{commodities::Commodity,contracts::{ContractBoard,ContractStatus}};
use bevy_ecs::prelude::*;
use serde::{Serialize,Deserialize};
use std::collections::BTreeMap;

#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
pub struct ProductionObjective {
    pub goal_id:String,
    pub commodity:Commodity,
    pub location:String,
    pub facility_type:String,
    pub created_tick:u64,
    #[serde(default)]
    pub last_observed_tick:u64,
    #[serde(default)]
    pub site_id:Option<String>,
    #[serde(default)]
    pub contract_id:Option<String>,
    #[serde(default)]
    pub next_stage:String,
    #[serde(default)]
    pub status:String,
    #[serde(default)]
    pub reason:String,
    /// The first verifiable native production event observed after this
    /// objective began, never a hypothetical market balance.
    #[serde(default)]
    pub verified_output_tick:Option<u64>,
    #[serde(default)]
    pub verified_output_units:Option<f64>,
}

impl ProductionObjective {
    pub fn from_native(view:&ConstructionView,tick:u64)->Option<Self>{
        let g=view.selected_goal.as_ref()?;
        Some(Self{
            goal_id:g.goal_id.clone(),commodity:g.commodity,
            location:g.destination.clone(),
            facility_type:view.facility_type.clone()?,
            created_tick:tick,last_observed_tick:tick,
            site_id:view.site_id.clone(),
            contract_id:view.contract_id.clone(),
            next_stage:"materials".into(),status:"active".into(),
            reason:"native_construction_committed".into(),
            verified_output_tick:None,verified_output_units:None,
        })
    }
    pub fn matches(&self,view:&ConstructionView)->bool{
        view.selected_goal.as_ref().is_some_and(|g|
            self.commodity==g.commodity && self.location==g.destination &&
            view.facility_type.as_deref()==Some(self.facility_type.as_str()))
    }
    pub fn terminal(&self)->bool{self.status=="completed"}
    pub fn can_reoffer(&self,crisis:bool)->bool{
        !self.terminal() && !crisis && !self.goal_id.starts_with("player_")
    }
    fn update(&mut self, chain:&production_chain::Sequence,tick:u64,crisis:bool){
        self.last_observed_tick=tick;
        self.next_stage=chain.next_stage.into();
        // Ignore a recipe receipt from before the project was authorized.
        let receipt=chain.last_output_tick.filter(|output_tick|
            *output_tick>=self.created_tick && chain.next_stage=="complete");
        if let Some(real_tick)=receipt {
            self.verified_output_tick=Some(real_tick);
            self.verified_output_units=chain.cumulative_produced_units;
            self.status="completed".into();
            self.reason="native_paid_output_confirmed".into();
        }else if crisis {
            self.status="paused".into();self.reason="survival_override".into();
        }else {
            let current=chain.steps.iter().find(|s|s.status!="complete");
            self.status=if current.is_some_and(|s|s.status=="blocked"){"blocked"}
                else{"active"}.into();
            self.reason=current.map_or("native_physical_plan_waiting",
                |s|s.reason.as_str()).into();
        }
    }
}

/// A persistent objective may only be CREATED after a real paid site or a
/// native construction contract. A shadow proposal is never a commitment.
fn committed(view:&ConstructionView,board:&ContractBoard,faction:&str)->bool{
    view.site_id.is_some() || view.contract_id.as_ref()
        .and_then(|id|board.get(id))
        .is_some_and(|c|c.requestor_id==faction &&
            c.mission_category.as_deref()==Some(construction::PROJECT_TAG) &&
            c.funding.as_ref().is_some_and(|f|f.reserved>0) &&
            !matches!(c.status,ContractStatus::Expired))
}

/// Sync after normal StrategyState / ConstructionView refresh. A plan remains
/// present even if the head selected research, an emergency or another project.
pub fn refresh(world:&mut World,board:&ContractBoard,tick:u64){
    if world.get_resource::<Director>().is_none(){return;}
    let views:Vec<_>=world.get_resource::<StrategyState>().map(|s|
        s.factions.iter().filter_map(|(id,v)|v.construction.as_ref()
            .map(|build|(id.clone(),build.clone()))).collect()
    ).unwrap_or_default();
    let mode=world.get_resource::<StrategyState>().map_or(Mode::Shadow,|s|s.mode);
    let (mut objectives,crises)={
        let d=world.resource::<Director>();
        (d.production_objectives.clone(),d.commanders.iter()
            .map(|(id,c)|(id.clone(),c.crisis)).collect::<BTreeMap<_,_>>())
    };
    // A newly paid real site may start an objective, but never replace an
    // active incumbent just because the head changed its short-term choice.
    for (id,view) in &views {
        if !objectives.get(id).is_some_and(|p|!p.terminal()) &&
            (mode==Mode::Execute || view.site_id.is_some()) &&
            committed(view,board,id) {
            if let Some(p)=ProductionObjective::from_native(view,tick){
                objectives.insert(id.clone(),p);
            }
        }
    }
    let faction_ids:Vec<_>=world.query::<&FactionData>().iter(world)
        .map(|f|f.id.clone()).collect();
    objectives.retain(|id,_|faction_ids.contains(id));
    for (id,objective) in &mut objectives {
        if objective.terminal(){continue;}
        let view=views.iter().find(|(owner,v)|owner==id && objective.matches(v))
            .map(|(_,v)|v.clone())
            .unwrap_or_else(||{
                // Use the remembered goal for OBSERVATION only. No grant is
                // issued here; actual retry goes through construction::run_cycle.
                let mut fallback=ConstructionView::new(tick);
                fallback.selected_goal=Some(Goal{goal_id:objective.goal_id.clone(),
                    commodity:objective.commodity,destination:objective.location.clone(),
                    shortage_ticks:0,score:0.0});
                fallback.facility_type=Some(objective.facility_type.clone());
                fallback.contract_id=objective.contract_id.clone();
                fallback
            });
        if let Some(chain)=production_chain::inspect(world,board,id,&view){
            objective.update(&chain,tick,*crises.get(id).unwrap_or(&false));
            if let Some(view_id)=view.site_id {objective.site_id=Some(view_id);}
            if let Some(contract)=view.contract_id {objective.contract_id=Some(contract);}
        }
    }
    world.resource_mut::<Director>().production_objectives=objectives;
}

#[cfg(test)]
mod tests {
    use super::*;
    fn goal()->ProductionObjective{
        ProductionObjective{goal_id:"expand_production".into(),
            commodity:Commodity::Food,location:"port".into(),
            facility_type:"farm".into(),created_tick:100,last_observed_tick:100,
            site_id:Some("site-food-port-100".into()),contract_id:Some("ctr-1".into()),
            next_stage:"materials".into(),status:"active".into(),
            reason:"native_construction_committed".into(),
            verified_output_tick:None,verified_output_units:None}
    }
    #[test]
    fn galaxy067_objective_survives_checkpoint_and_blocks_duplicate_until_terminal(){
        let plan=goal();
        let json=serde_json::to_string(&plan).unwrap();
        let restored:ProductionObjective=serde_json::from_str(&json).unwrap();
        assert_eq!(restored,plan);
        assert!(restored.can_reoffer(false));
        assert!(!restored.can_reoffer(true));
        let mut terminal=restored;
        terminal.status="completed".into();
        assert!(!terminal.can_reoffer(false));
    }
    #[test]
    fn galaxy067_only_verified_paid_output_completes_remembered_goal(){
        let mut plan=goal();
        let mut sequence=production_chain::Sequence{
            commodity:Commodity::Food,destination:"port".into(),
            facility_type:"farm".into(),next_stage:"first_output",
            next_administrator:"station",steps:vec![],local_inputs:None,
            last_output_tick:Some(99),cumulative_produced_units:Some(20.0)};
        plan.update(&sequence,200,false);
        assert_ne!(plan.status,"completed");
        sequence.next_stage="complete";
        plan.update(&sequence,210,false);
        assert_ne!(plan.status,"completed","old pre-project output cannot finish a new goal");
        sequence.last_output_tick=Some(205);
        plan.update(&sequence,210,false);
        assert_eq!(plan.status,"completed");
        assert_eq!(plan.verified_output_tick,Some(205));
        assert_eq!(plan.verified_output_units,Some(20.0));
    }
    #[test]
    fn galaxy067_crisis_pauses_without_discarding_goal_or_contract(){
        let mut plan=goal();
        let chain=production_chain::Sequence{
            commodity:Commodity::Food,destination:"port".into(),
            facility_type:"farm".into(),next_stage:"labor",
            next_administrator:"construction",steps:vec![],local_inputs:None,
            last_output_tick:None,cumulative_produced_units:None};
        let id=plan.contract_id.clone();
        plan.update(&chain,200,true);
        assert_eq!(plan.status,"paused");
        assert!(!plan.can_reoffer(true));
        plan.update(&chain,250,false);
        assert_eq!(plan.status,"active");
        assert_eq!(plan.contract_id,id);
        assert!(plan.can_reoffer(false));
    }
}
