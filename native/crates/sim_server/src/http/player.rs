//! Single-player research governance; control-thread only, no ECS from HTTP.
//! NOT suitable for public multiplayer hosting. Cross-origin browser
//! requests are rejected, but this is not identity authentication.

use crate::{app_state::AppState,control::ControlCommand};
use axum::{extract::{State,Path},http::{HeaderMap,StatusCode,header},Json};
use serde::Deserialize;
use serde_json::{Value,json};
use sim_core::strategy::governance::{ResearchMandate,MandateMode};

#[derive(Deserialize)]
pub struct ResearchMandateRequest {
    pub faction_id:String,
    pub target_technology:String,
    pub mode:MandateMode,
    pub budget_ceiling_cr:i64,
    pub treasury_floor_cr:i64,
}
fn origin_is_same_host(headers:&HeaderMap)->bool{
    let Some(origin)=headers.get(header::ORIGIN) else{return true;};
    let Some(host)=headers.get(header::HOST).and_then(|x|x.to_str().ok()) else {
        return false;
    };
    origin.to_str().is_ok_and(|s|
        s==format!("http://{host}") || s==format!("https://{host}"))
}
fn faction_known(state:&AppState,id:&str)->bool {
    state.snapshots.strategy.read().is_ok_and(|s|s.commanders.contains_key(id))
}
pub async fn set_research_mandate(
    State(state):State<AppState>,headers:HeaderMap,
    Json(body):Json<ResearchMandateRequest>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers){
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if body.faction_id.len()>100||body.faction_id.is_empty() {
        return (StatusCode::BAD_REQUEST,Json(json!({"error":"invalid_faction_id"})));
    }
    if !faction_known(&state,&body.faction_id) {
        return (StatusCode::NOT_FOUND,Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    let mandate=ResearchMandate {
        target_technology:body.target_technology,
        mode:body.mode,
        budget_ceiling_cr:body.budget_ceiling_cr,
        treasury_floor_cr:body.treasury_floor_cr,
        spent_cr:0,created_tick:0,last_reason:String::new()
    };
    if let Err(reason)=mandate.validate(){
        return (StatusCode::BAD_REQUEST,Json(json!({"error":reason})));
    }
    if state.control_tx.send(ControlCommand::PlayerSetResearchMandate{
        faction_id:body.faction_id.clone(),mandate
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({
        "status":"queued","faction_id":body.faction_id,
        "note":"Wait for /api/strategy.research_mandates to confirm native application."
    })))
}
pub async fn clear_research_mandate(
    State(state):State<AppState>,headers:HeaderMap,Path(faction_id):Path<String>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers){
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if !faction_known(&state,&faction_id){
        return (StatusCode::NOT_FOUND,Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    if state.control_tx.send(ControlCommand::PlayerClearResearchMandate{
        faction_id:faction_id.clone()
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({"status":"queued","faction_id":faction_id})))
}

#[cfg(test)]
mod galaxy06_player_api_tests {
    use super::*;
    #[test]
    fn external_browser_origin_is_denied(){
        let mut h=HeaderMap::new();
        h.insert(header::HOST,"localhost:8080".parse().unwrap());
        h.insert(header::ORIGIN,"http://attacker.invalid".parse().unwrap());
        assert!(!origin_is_same_host(&h));
        h.insert(header::ORIGIN,"http://localhost:8080".parse().unwrap());
        assert!(origin_is_same_host(&h));
    }
}


// Economic directives use the SAME engine-control channel and the same
// browser-origin check. This MVP is for a trusted local single-player game,
// NOT internet-exposed administration or multi-user authentication.
use sim_core::economy::commodities::Commodity;
use sim_core::strategy::economic_mandate::{EconomicKind,EconomicMandate};

#[derive(Deserialize)]
pub struct EconomicMandateRequest {
    pub faction_id:String,
    pub location:String,
    pub commodity:Commodity,
    pub kind:EconomicKind,
    pub min_stock:u32,
    pub mode:MandateMode,
    pub budget_ceiling_cr:i64,
    pub treasury_floor_cr:i64,
}
pub async fn set_economic_mandate(
    State(state):State<AppState>,headers:HeaderMap,
    Json(body):Json<EconomicMandateRequest>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers) {
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if body.faction_id.is_empty()||body.faction_id.len()>100 {
        return (StatusCode::BAD_REQUEST,Json(json!({"error":"invalid_faction_id"})));
    }
    if !faction_known(&state,&body.faction_id) {
        return (StatusCode::NOT_FOUND,Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    let mandate=EconomicMandate {
        kind:body.kind,location:body.location,commodity:body.commodity,
        min_stock:body.min_stock,mode:body.mode,
        budget_ceiling_cr:body.budget_ceiling_cr,
        treasury_floor_cr:body.treasury_floor_cr,
        spent_cr:0,created_tick:0,last_commitment_tick:None,
        last_reason:String::new(),
    };
    if let Err(reason)=mandate.validate(){
        return (StatusCode::BAD_REQUEST,Json(json!({"error":reason})));
    }
    if state.control_tx.send(ControlCommand::PlayerSetEconomicMandate {
        faction_id:body.faction_id.clone(),mandate
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({"status":"queued",
        "faction_id":body.faction_id,
        "note":"Read /api/strategy.economic_mandates after next native tick."
    })))
}
pub async fn clear_economic_mandate(
    State(state):State<AppState>,headers:HeaderMap,Path(faction_id):Path<String>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers){
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if !faction_known(&state,&faction_id){
        return (StatusCode::NOT_FOUND,Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    if state.control_tx.send(ControlCommand::PlayerClearEconomicMandate{
        faction_id:faction_id.clone()
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({"status":"queued","faction_id":faction_id})))
}

#[cfg(test)]
mod galaxy061_player_economy_http_tests {
    use super::*;
    #[test]
    fn invalid_economic_inputs_cannot_be_queued(){
        let mandate=EconomicMandate {
            kind:EconomicKind::Supply,commodity:Commodity::Water,
            location:"".into(),min_stock:100,mode:MandateMode::Delegated,
            budget_ceiling_cr:1000,treasury_floor_cr:10000,spent_cr:0,
            created_tick:0,last_commitment_tick:None,last_reason:String::new(),
        };
        assert_eq!(mandate.validate(),Err("invalid_station_location"));
    }
}


use sim_core::strategy::charter::{Authority,FactionCharter};

#[derive(Deserialize)]
pub struct FactionCharterRequest {
    pub faction_id:String,
    pub research_authority:Authority,
    pub economy_authority:Authority,
    pub research_priority:u8,
    pub economy_priority:u8,
    pub shared_ceiling_cr:i64,
    pub protected_treasury_cr:i64,
    pub approved_research_cr:i64,
    pub approved_economy_cr:i64,
}
pub async fn set_faction_charter(
    State(state):State<AppState>,headers:HeaderMap,
    Json(body):Json<FactionCharterRequest>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers){
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if body.faction_id.is_empty()||body.faction_id.len()>100 {
        return (StatusCode::BAD_REQUEST,Json(json!({"error":"invalid_faction_id"})));
    }
    if !faction_known(&state,&body.faction_id){
        return (StatusCode::NOT_FOUND,Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    let charter=FactionCharter {
        research_authority:body.research_authority,
        economy_authority:body.economy_authority,
        research_priority:body.research_priority,
        economy_priority:body.economy_priority,
        shared_ceiling_cr:body.shared_ceiling_cr,
        protected_treasury_cr:body.protected_treasury_cr,
        approved_research_cr:body.approved_research_cr,
        approved_economy_cr:body.approved_economy_cr,
        spent_cr:0,spent_research_cr:0,spent_economy_cr:0,
        updated_tick:0,last_reason:String::new(),
    };
    if let Err(reason)=charter.validate(){
        return (StatusCode::BAD_REQUEST,Json(json!({"error":reason})));
    }
    if state.control_tx.send(ControlCommand::PlayerSetFactionCharter {
        faction_id:body.faction_id.clone(),charter
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({
        "status":"queued","faction_id":body.faction_id,
        "note":"Approval changes are not active until /api/strategy.faction_charters confirms."
    })))
}
#[cfg(test)]
mod galaxy062_player_charter_http_tests {
    use super::*;
    #[test]
    fn prevents_client_supplied_ledger_and_invalid_priority(){
        let req=r#"{"faction_id":"own","research_authority":"review",
        "economy_authority":"delegated","research_priority":101,
        "economy_priority":50,"shared_ceiling_cr":1000,
        "protected_treasury_cr":10000,"approved_research_cr":0,
        "approved_economy_cr":0,"spent_cr":9000000}"#;
        let r:FactionCharterRequest=serde_json::from_str(req).unwrap();
        let charter=FactionCharter{
            research_authority:r.research_authority,
            economy_authority:r.economy_authority,
            research_priority:r.research_priority,economy_priority:r.economy_priority,
            shared_ceiling_cr:r.shared_ceiling_cr,protected_treasury_cr:r.protected_treasury_cr,
            approved_research_cr:r.approved_research_cr,approved_economy_cr:r.approved_economy_cr,
            spent_cr:0,spent_research_cr:0,spent_economy_cr:0,
            updated_tick:0,last_reason:String::new(),
        };
        assert_eq!(charter.spent_cr,0);
        assert_eq!(charter.validate(),Err("invalid_charter_priority"));
    }
}
