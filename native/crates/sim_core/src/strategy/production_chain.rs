//! Read-only causal stages for an existing native construction/prod target.
//! Contract board, physical sites, payroll receipts and actual ECS markets own
//! the truth. This view never creates stock, workers, orders or money.
use super::{construction::{self, ConstructionView},production_dependencies};
use crate::agents::{
    construction::ConstructionSite,
    facility::{FacilityCrew,FacilityIdentity,FacilityLocation},
    market::{MarketIdentity,MarketPricing},
};
use crate::economy::{
    commodities::Commodity,
    contracts::{ContractBoard,ContractStatus},
    recipes,
};
use bevy_ecs::prelude::World;
use serde::Serialize;
use std::collections::HashMap;

#[derive(Clone,Debug,Serialize)]
pub struct Stage {
    pub key:&'static str,
    pub status:&'static str,
    pub administrator:&'static str,
    pub reason:String,
    pub actual:u64,
    pub required:u64,
    #[serde(skip_serializing_if="Option::is_none")]
    pub contract_id:Option<String>,
}
#[derive(Clone,Debug,Serialize)]
pub struct Sequence {
    pub commodity:Commodity,
    pub destination:String,
    pub facility_type:String,
    /// First *uncompleted* native step. A queued step is not a paid order.
    pub next_stage:&'static str,
    pub next_administrator:&'static str,
    pub steps:Vec<Stage>,
    pub local_inputs:Option<production_dependencies::LocalInputReadiness>,
    /// A real, persisted recipe receipt; these are cumulative quantities
    /// for one producer, not quantities attributable to this one decision.
    pub last_output_tick:Option<u64>,
    pub cumulative_produced_units:Option<f64>,
}
fn stage(key:&'static str,status:&'static str,administrator:&'static str,
    reason:impl Into<String>,actual:u64,required:u64,contract_id:Option<String>)->Stage{
    Stage{key,status,administrator,reason:reason.into(),actual,required,contract_id}
}

/// The first missing input that an EXISTING co-located producer can actually
/// manufacture from present local stock in one native recipe batch.
/// This is a station-admin *priority*, not an instruction to mint its output.
/// We do not recurse into imaginary future factories.
pub fn available_local_precursor(
    product:Commodity,final_facility:&str,stock:&HashMap<Commodity,u64>,
    installed_types:&[&str],
)->Option<Commodity>{
    let final_batch=production_dependencies::local_inputs_for_one_batch(
        product,final_facility,stock)?;
    if final_batch.ready_for_one_batch{return None;}
    for missing in final_batch.inputs.iter().filter(|g|g.missing>0){
        let mut kinds=installed_types.to_vec();
        kinds.sort_unstable();kinds.dedup();
        for kind in kinds {
            if kind==final_facility && missing.commodity==product {continue;}
            if production_dependencies::local_inputs_for_one_batch(
                missing.commodity,kind,stock
            ).is_some_and(|p|p.ready_for_one_batch){
                return Some(missing.commodity);
            }
        }
    }
    None
}

/// Construct the current physical execution sequence. Called after normal
/// native refresh, never from the contract posting path.
pub fn inspect(world:&mut World, board:&ContractBoard, faction:&str,
    construction:&ConstructionView)->Option<Sequence>{
    let goal=construction.selected_goal.as_ref()?;
    let kind=construction.facility_type.clone().unwrap_or_else(||{
        crate::agents::construction::facility_type_for_commodity(goal.commodity).into()
    });
    let site=world.query::<&ConstructionSite>().iter(world)
        .find(|s|s.faction_id==faction && s.location_name==goal.destination &&
            s.facility_type==kind && !s.completed &&
            construction.site_id.as_ref().is_none_or(|id|*id==s.id))
        .cloned();
    let producer=world.query::<(&FacilityIdentity,&FacilityLocation,&FacilityCrew)>()
        .iter(world)
        .find(|(id,loc,_)|id.faction_id==faction &&
            loc.location_name==goal.destination && id.facility_type==kind &&
            (kind=="mining_rig" || recipes::for_facility_type(&kind)
                .any(|r|r.outputs.iter().any(|(c,n)|*c==goal.commodity && *n>0))))
        .map(|(_,_,crew)|crew.clone());
    let built=producer.is_some();
    let contract=construction.contract_id.as_ref()
        .and_then(|id|board.get(id))
        .filter(|c|c.requestor_id==faction &&
            c.destination_location==goal.destination &&
            c.mission_category.as_deref()==Some(construction::PROJECT_TAG));
    let local=world.query::<(&MarketIdentity,&MarketPricing)>()
        .iter(world).find(|(i,_)|i.facility_location==goal.destination)
        .map(|(_,m)|m.supply.iter()
            .filter(|(_,v)|v.is_finite()&&**v>=0.0)
            .map(|(&c,&v)|(c,v.floor() as u64))
            .collect::<HashMap<_,_>>());
    let inputs=local.as_ref().and_then(|stock|
        production_dependencies::local_inputs_for_one_batch(goal.commodity,&kind,stock));
    let mut receipt:Option<(u64,f64)>=None;
    if let Some(shift)=producer.as_ref().and_then(|crew|crew.work_shift.as_ref()){
        for recipe in recipes::for_facility_type(&kind).filter(|r|
            r.outputs.iter().any(|(c,n)|*c==goal.commodity && *n>0)){
            if let Some((&tick,&units))=shift.last_recipe_ticks.get(recipe.id)
                .zip(shift.produced_outputs.get(recipe.id)
                    .and_then(|v|v.get(goal.commodity.as_str()))){
                if units>0.0 && units.is_finite() &&
                    receipt.is_none_or(|(old,_)|tick>old){receipt=Some((tick,units));}
            }
        }
    }
    let mut steps=Vec::with_capacity(5);
    let commissioning=if built||site.is_some(){"complete"}
        else if construction.status=="blocked"{"blocked"}
        else if construction.status=="commissioned"{"active"}else{"queued"};
    steps.push(stage("commission",commissioning,"construction",
        if built{"native_producer_exists"}else if site.is_some(){"native_site_exists"}
        else{construction.reason.as_str()},u64::from(built||site.is_some()),1,None));
    let (cargo_status,cargo_reason)=if built ||
        site.as_ref().is_some_and(|s|s.progress_delivered>=s.progress_required){
        ("complete","native_material_progress_satisfied".to_string())
    }else if site.is_none(){
        ("queued","native_site_not_created".into())
    }else if let Some(c)=contract {
        match c.status {
            ContractStatus::Posted=>("active",
                if c.fulfiller_id.is_none(){"native_contract_unassigned"}
                else{"native_contract_assigned"}.into()),
            ContractStatus::Accepted|ContractStatus::PickedUp=>("active","native_carrier_in_flight".into()),
            ContractStatus::Delivered=>("active","delivery_arrived_progress_unverified".into()),
            ContractStatus::Paid|ContractStatus::Expired=>("queued","awaiting_next_native_delivery".into()),
        }
    }else{
        ("queued","awaiting_native_delivery_contract".into())
    };
    let (cargo_actual,cargo_required)=site.as_ref()
        .map_or((u64::from(built),u64::from(built)),|s|
            (u64::from(s.progress_delivered),u64::from(s.progress_required)));
    steps.push(stage("materials",cargo_status,"logistics",
        construction.delivery_block_reason.as_deref()
            .filter(|_|cargo_status!="complete").unwrap_or(&cargo_reason),
        cargo_actual,cargo_required,contract.map(|c|c.id.clone())));
    let (labor_actual,labor_required)=site.as_ref()
        .map_or((u64::from(built),u64::from(built)),|s|
            (u64::from(s.labor.completed),u64::from(s.labor.required)));
    let labor_state=if built||site.as_ref().is_some_and(|s|
        s.labor.completed>=s.labor.required){"complete"}
        else if site.is_none()||cargo_status!="complete"{"queued"}
        else if site.as_ref().is_some_and(|s|s.labor.blocked_reason.is_some()){"blocked"}
        else{"active"};
    steps.push(stage("labor",labor_state,"construction",
        if labor_state=="blocked"{
            site.as_ref().and_then(|s|s.labor.blocked_reason.as_deref())
                .unwrap_or("native_labor_blocked")
        }else if labor_state=="complete"{"native_paid_labor_complete"}
        else if labor_state=="active"{"awaiting_native_paid_worker_shifts"}
        else{"waiting_for_materials"},labor_actual,labor_required,None));
    let (input_status,input_reason):(&'static str,String)=if !built {("queued","producer_not_materialized".into())}
        else if let Some(readiness)=&inputs {
            if readiness.ready_for_one_batch {("complete","local_inputs_for_one_batch_present".into())}
            else {("blocked","local_recipe_input_shortage".into())}
        } else if local.is_none(){("blocked","local_market_unavailable".into())}
        else {("complete","native_extractor_no_recipe_inputs".into())};
    steps.push(stage("inputs",input_status,"logistics",
        input_reason,0,0,None));
    let work_status=if receipt.is_some(){"complete"}
        else if !built||input_status!="complete"{"queued"}
        else if producer.as_ref().and_then(|c|c.work_blocked_reason.as_deref()).is_some(){"blocked"}
        else{"active"};
    steps.push(stage("first_output",work_status,"station",
        if receipt.is_some(){"real_native_recipe_output_receipt"}
        else if work_status=="blocked"{
            producer.as_ref().and_then(|c|c.work_blocked_reason.as_deref())
                .unwrap_or("native_workforce_blocked")
        }else if work_status=="active"{"awaiting_actual_paid_production_shift"}
        else{"waiting_for_producer_or_inputs"},u64::from(receipt.is_some()),1,None));
    let (next_stage,next_administrator)=steps.iter()
        .find(|s|s.status!="complete")
        .map_or(("complete","none"),|s|(s.key,s.administrator));
    Some(Sequence{commodity:goal.commodity,destination:goal.destination.clone(),
        facility_type:kind,next_stage,next_administrator,steps,
        local_inputs:inputs,last_output_tick:receipt.map(|v|v.0),
        cumulative_produced_units:receipt.map(|v|v.1)})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn galaxy066_existing_refinery_unlocks_water_precursor_without_creating_stock(){
        let stock=HashMap::from([(Commodity::Ice,8)]);
        assert_eq!(available_local_precursor(Commodity::Food,"farm",&stock,
            &["farm","refinery"]),Some(Commodity::Water));
        assert_eq!(available_local_precursor(Commodity::Food,"farm",&stock,
            &["farm"]),None);
        assert_eq!(stock.get(&Commodity::Water),None);
    }
    #[test]
    fn galaxy066_production_priority_stops_when_final_inputs_available(){
        let stock=HashMap::from([(Commodity::Water,3),(Commodity::Ice,8)]);
        assert_eq!(available_local_precursor(Commodity::Food,"farm",&stock,
            &["farm","refinery"]),None);
    }
}
