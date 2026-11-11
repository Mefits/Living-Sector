"""Galaxy061 queued local-only player economic-mandate API.

This extends the existing control channel and read-only /api/strategy.
No HTTP task may mutate ECS, credits, contracts or station levels.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
server=root/"crates/sim_server/src"
def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy061 API source drift {path.name}: {n}: {old[:90]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

p=server/"control.rs"
one(p,
  """    PlayerClearResearchMandate {faction_id:String},
    AdminSetRelations {""",
  """    PlayerClearResearchMandate {faction_id:String},
    PlayerSetEconomicMandate {
        faction_id:String,
        mandate:sim_core::strategy::economic_mandate::EconomicMandate,
    },
    PlayerClearEconomicMandate {faction_id:String},
    AdminSetRelations {""")

p=server/"engine.rs"
one(p,
  """                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""",
  """                ControlCommand::PlayerSetEconomicMandate {faction_id,mandate} => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let res=sim_core::strategy::economic_mandate::set_mandate(
                        &mut world,&faction_id,mandate,now);
                    events.push(serde_json::json!({
                        "kind":"player_economic_mandate_applied",
                        "tick":now,"faction_id":faction_id,
                        "status":if res.is_ok(){"applied"}else{"rejected"},
                        "reason":res.err(),
                    }));
                }
                ControlCommand::PlayerClearEconomicMandate {faction_id} => {
                    let removed=sim_core::strategy::economic_mandate::clear_mandate(
                        &mut world,&faction_id);
                    events.push(serde_json::json!({
                        "kind":"player_economic_mandate_cleared",
                        "faction_id":faction_id,"removed":removed,
                    }));
                }
                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""")

p=server/"snapshot.rs"
one(p,
  """                snapshot.research_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.research_mandates.clone()).unwrap_or_default();""",
  """                snapshot.research_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.research_mandates.clone()).unwrap_or_default();
                snapshot.economic_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_mandates.clone()).unwrap_or_default();""")

p=server/"runtime.rs"
one(p,
  """        .route("/api/player/research-mandate/{faction_id}",
            delete(player::clear_research_mandate))""",
  """        .route("/api/player/research-mandate/{faction_id}",
            delete(player::clear_research_mandate))
        .route("/api/player/economic-mandate",post(player::set_economic_mandate))
        .route("/api/player/economic-mandate/{faction_id}",
            delete(player::clear_economic_mandate))""")

p=server/"http/player.rs"
s=p.read_text(encoding="utf8")
if "pub async fn set_economic_mandate" in s:raise RuntimeError("Economic API already exists")
s+=r'''

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
'''
p.write_text(s,encoding="utf8")
print("Galaxy061: local player economic API queues real control commands, persistent strategy readback")
