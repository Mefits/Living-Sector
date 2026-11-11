"""Galaxy06: science-mandate HTTP routed through engine control queue.

The HTTP handler does not touch SQL or ECS. A successful HTTP response
says only queued; next native strategy snapshot confirms application.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
SERVER=ROOT/"crates/sim_server/src"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy06 API drift: {path.name}: {n} for {old[:85]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(SERVER/"http/mod.rs", "pub mod api;", "pub mod api;\npub mod player;")
one(SERVER/"control.rs",
  """    AdminSetRelations {
        a: String,""",
  """    PlayerSetResearchMandate {
        faction_id:String,
        mandate:sim_core::strategy::governance::ResearchMandate,
    },
    PlayerClearResearchMandate {faction_id:String},
    AdminSetRelations {
        a: String,""")

one(SERVER/"engine.rs",
  """                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""",
  """                ControlCommand::PlayerSetResearchMandate {faction_id,mandate} => {
                    let tick=tick_counter.load(Ordering::Relaxed);
                    let res=sim_core::strategy::governance::set_mandate(
                        &mut world,&faction_id,mandate,tick);
                    events.push(serde_json::json!({
                        "kind":"player_research_mandate_applied",
                        "tick":tick,"faction_id":faction_id,
                        "status":if res.is_ok(){"applied"}else{"rejected"},
                        "reason":res.err(),
                    }));
                }
                ControlCommand::PlayerClearResearchMandate {faction_id} => {
                    let removed=sim_core::strategy::governance::clear_mandate(
                        &mut world,&faction_id);
                    events.push(serde_json::json!({
                        "kind":"player_research_mandate_cleared",
                        "faction_id":faction_id,"removed":removed,
                    }));
                }
                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""")

one(SERVER/"runtime.rs", """    use http::{admin, api};""",
                       """    use http::{admin, api, player};""")
one(SERVER/"runtime.rs",
  """        .route("/api/strategy", get(api::strategy))""",
  """        .route("/api/strategy", get(api::strategy))
        .route("/api/player/research-mandate", post(player::set_research_mandate))
        .route("/api/player/research-mandate/{faction_id}",
            delete(player::clear_research_mandate))""")

path=SERVER/"http/player.rs"
if path.exists():raise RuntimeError("player HTTP module already exists")
path.write_text(r'''//! Single-player research governance; control-thread only, no ECS from HTTP.
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
''',encoding="utf8")
print("Galaxy06: queued-only player mandate API and engine-side native policy")
