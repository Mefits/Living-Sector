"""Galaxy 0.6.3 — decide one quoted economic action via native engine queue.

No HTTP handler modifies ECS or CR. Browser accepts only a server-made
proposal_id. A real trade/construction is still executed by Genesis.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
server=root/"crates/sim_server/src"
observer=root/"observer"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:
        raise RuntimeError(f"Galaxy063 API/UI anchor drift {path}: {n} {old[:95]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(server/"control.rs",
    """    PlayerSetFactionCharter {
        faction_id:String,
        charter:sim_core::strategy::charter::FactionCharter,
    },
    AdminSetRelations {""",
    """    PlayerSetFactionCharter {
        faction_id:String,
        charter:sim_core::strategy::charter::FactionCharter,
    },
    PlayerDecideEconomicProposal {
        faction_id:String,
        proposal_id:String,
        approve:bool,
    },
    AdminSetRelations {""")
one(server/"engine.rs",
    """                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""",
    """                ControlCommand::PlayerDecideEconomicProposal {
                    faction_id,proposal_id,approve
                } => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let result=sim_core::strategy::economic_proposal::decide(
                        &mut world,&faction_id,&proposal_id,approve,now);
                    events.push(serde_json::json!({
                        "kind":"player_economic_proposal_reviewed",
                        "tick":now,"faction_id":faction_id,
                        "proposal_id":proposal_id,"approve":approve,
                        "status":if result.is_ok(){"applied"}else{"rejected"},
                        "reason":result.err(),
                    }));
                }
                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""")
one(server/"snapshot.rs",
    """                snapshot.faction_charters = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.faction_charters.clone()).unwrap_or_default();""",
    """                snapshot.faction_charters = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.faction_charters.clone()).unwrap_or_default();
                snapshot.economic_proposals = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_proposals.clone()).unwrap_or_default();""")
one(server/"runtime.rs",
    """        .route("/api/player/faction-charter",post(player::set_faction_charter))""",
    """        .route("/api/player/faction-charter",post(player::set_faction_charter))
        .route("/api/player/economic-proposal/decision",
            post(player::decide_economic_proposal))""")

p=server/"http/player.rs"
s=p.read_text(encoding="utf8")
if "pub async fn decide_economic_proposal" in s:
    raise RuntimeError("Galaxy063 approval handler already exists")
s+=r'''

#[derive(Deserialize)]
pub struct EconomicProposalDecisionRequest {
    pub faction_id:String,
    pub proposal_id:String,
    pub approve:bool,
}
pub async fn decide_economic_proposal(
    State(state):State<AppState>,headers:HeaderMap,
    Json(body):Json<EconomicProposalDecisionRequest>
)->(StatusCode,Json<Value>){
    if !origin_is_same_host(&headers){
        return (StatusCode::FORBIDDEN,Json(json!({"error":"foreign_origin"})));
    }
    if body.faction_id.is_empty()||body.faction_id.len()>100 {
        return (StatusCode::BAD_REQUEST,Json(json!({"error":"invalid_faction_id"})));
    }
    if body.proposal_id.is_empty()||body.proposal_id.len()>240||
        body.proposal_id.bytes().any(|c|c<33||c>126) {
        return (StatusCode::BAD_REQUEST,Json(json!({"error":"invalid_proposal_id"})));
    }
    if !faction_known(&state,&body.faction_id){
        return (StatusCode::NOT_FOUND,
            Json(json!({"error":"unknown_faction_or_world_not_ready"})));
    }
    if state.control_tx.send(ControlCommand::PlayerDecideEconomicProposal{
        faction_id:body.faction_id.clone(),
        proposal_id:body.proposal_id.clone(),
        approve:body.approve,
    }).await.is_err(){
        return (StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"engine_unavailable"})));
    }
    (StatusCode::ACCEPTED,Json(json!({
        "status":"queued","faction_id":body.faction_id,
        "proposal_id":body.proposal_id,
        "note":"Only engine confirmation in /api/strategy.economic_proposals changes the proposal state."
    })))
}
#[cfg(test)]
mod galaxy063_player_specific_action_http_tests {
    use super::*;
    #[test]
    fn request_does_not_contain_client_selected_price_or_action(){
        let request=r#"{"faction_id":"own","proposal_id":"economic-own-120",
            "approve":true,"quoted_commitment_cr":1,"action":"build"}"#;
        let p:EconomicProposalDecisionRequest=serde_json::from_str(request).unwrap();
        assert_eq!(p.proposal_id,"economic-own-120");
        assert!(p.approve);
        // Extra browser keys are ignored by the DTO; the native engine
        // reads the original persisted proposal's exact quote instead.
    }
}
'''
p.write_text(s,encoding="utf8")

page=observer/"governance-approvals.html"
if page.exists():raise RuntimeError("approval console already exists")
page.write_text(r'''<!doctype html>
<html lang="ru">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Living Sector — Решения, требующие согласования</title>
<style>
:root{color-scheme:dark;font:14px system-ui,sans-serif;background:#0e1823;color:#e1ecf3}
*{box-sizing:border-box}body{margin:0}
header{padding:18px 25px;border-bottom:1px solid #314554;background:#142331;
display:flex;align-items:center;justify-content:space-between;gap:15px;flex-wrap:wrap}
h1{font-size:20px;margin:0 0 5px}h2{font-size:17px;margin:0 0 12px}
small,.hint{color:#a9bfcd}a{color:#94d3df;text-decoration:none}
main{max-width:1180px;display:grid;grid-template-columns:minmax(320px,1.15fr) minmax(300px,1fr);
gap:16px;margin:auto;padding:20px}
article{background:#16293a;border:1px solid #314c5f;border-radius:9px;padding:19px;margin-bottom:15px}
label{display:block;color:#afc5d1;margin-bottom:7px}
select,button{background:#213b4d;color:#e3f0f6;border:1px solid #476174;border-radius:6px;
font:inherit;padding:11px;cursor:pointer}
select{width:100%}button{font-weight:600;flex:1}
button:disabled{opacity:.5;cursor:default}
button.approve{background:#286879}button.deny{background:#3a4555}
.buttons{display:flex;gap:9px;margin-top:18px}
.row{padding:10px 0;border-bottom:1px solid #2b4455;display:flex;
justify-content:space-between;gap:14px}
.row strong{text-align:right;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.note{color:#a7c0cc;line-height:1.55;font-size:13px}
.msg{padding:12px;background:#203a4b;border-left:3px solid #79b9c5;line-height:1.5}
.err{border-color:#e88d83}
@media(max-width:840px){main{grid-template-columns:1fr;padding:12px}}
</style></head>
<body>
<header><div><h1>Совет фракции · Согласование</h1>
<small>Предложения главы на основе реальных вариантов Genesis</small></div>
<nav><a href="/observer/">Галактика</a> ·
<a href="/observer/governance-charter.html">Устав</a> ·
<a href="/observer/governance-economy.html">Мандаты</a></nav>
</header>
<main>
<section>
 <article><label for="faction">Выбранная фракция</label><select id="faction"></select></article>
 <article>
  <h2>Решение администрации</h2>
  <div id="offer"></div>
  <div class="buttons"><button class="approve" id="approve">Одобрить это предложение</button>
  <button class="deny" id="reject">Отклонить</button></div>
  <p id="message" class="msg" role="status">Получаем данные Genesis…</p>
 </article>
 <article><h2>Что означает одобрение</h2>
  <p class="note">Разрешается только один конкретный вариант с указанной ценой,
  станцией, ресурсом и действием. При смене цены или условий требуется новое предложение.
  Сервер затем самостоятельно проверяет ресурсы, технологии, маршрут, работников,
  бюджет и состояние станции. Это не команда конкретному кораблю.</p>
 </article>
</section>
<section>
 <article><h2>Полномочия и деньги</h2><div id="charter"></div></article>
 <article><h2>Контроль выполнения</h2><div id="execution"></div>
  <p class="note">«Одобрено» ещё не значит «контракт оплачен».
  «Оплачено» не значит «товар доставлен» или «завод производит».
  Получение денег, поставки и производство всегда подтверждаются реальным Genesis.</p>
 </article>
</section>
</main>
<script>
"use strict";
const el=id=>document.getElementById(id);
let live=null,pending=null,selectedFaction=null;
const fmt=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("ru-RU")+" CR":"—";
const s=v=>v==null?"—":String(v);
const kindNames={industry:"Строительство местного производства",
supply:"Снабжение станции"};
const stateNames={pending:"Ожидает вашего решения",
approved:"Одобрено, ожидает настоящего исполнения",
rejected:"Отклонено",
consumed:"Есть оплаченный нативный контракт",
expired:"Предложение устарело"};
function row(target,name,value){
 const d=document.createElement("div");d.className="row";
 const a=document.createElement("span"),b=document.createElement("strong");
 a.textContent=name;b.textContent=s(value);d.append(a,b);target.append(d);
}
function notice(message,error=false){el("message").textContent=message;
 el("message").classList.toggle("err",error)}
async function request(path,method,body){
 const o={cache:"no-store"};
 if(method){o.method=method;if(body){
  o.headers={"Content-Type":"application/json"};o.body=JSON.stringify(body)}}
 const r=await fetch(path,o);let data={};try{data=await r.json()}catch{}
 if(!r.ok)throw Error(data.error||("HTTP "+r.status));
 return {status:r.status,data};
}
function selection(){
 const factions=live?.report?.factions||[];
 const ids=Object.keys(live?.strategy?.commanders||{});
 const available=factions.filter(f=>ids.includes(f.id));
 const old=el("faction").value;
 el("faction").replaceChildren();
 for(const f of available){const opt=document.createElement("option");
 opt.value=f.id;opt.textContent=f.name||f.id;el("faction").append(opt)}
 if(available.some(f=>f.id===old))el("faction").value=old;
 return el("faction").value;
}
function render(){
 if(!live)return;
 const id=selection();
 const p=live.strategy.economic_proposals?.[id];
 const charter=live.strategy.faction_charters?.[id];
 const mandate=live.strategy.economic_mandates?.[id];
 const fact=(live.report.factions||[]).find(f=>f.id===id);
 const offer=el("offer");offer.replaceChildren();
 row(offer,"Фракция",fact?.name||id);
 if(p){
  row(offer,"Задача",kindNames[p.kind]||p.kind);
  row(offer,"Станция",p.location);
  row(offer,"Ресурс",p.commodity);
  row(offer,"Действие Genesis",p.action);
  row(offer,"Цена предложения",fmt(p.quoted_commitment_cr));
  row(offer,"Статус",stateNames[p.status]||p.status);
  row(offer,"ID",p.proposal_id);
  row(offer,"Действует до тика",p.valid_until_tick);
  row(offer,"Причина",p.last_reason);
 }else{row(offer,"Предложение","Нет подходящей готовой нативной альтернативы")}
 const canChoose=p?.status==="pending" && charter?.economy_authority==="review" &&
    mandate?.mode==="delegated";
 el("approve").disabled=!canChoose;
 el("reject").disabled=!canChoose;
 const c=el("charter");c.replaceChildren();
 row(c,"Казна",fmt(fact?.treasury));
 row(c,"Полномочия экономики",charter?.economy_authority||"Устав не назначен");
 row(c,"Общий лимит поручений",fmt(charter?.shared_ceiling_cr));
 row(c,"Уже оплачено по уставу",fmt(charter?.spent_cr));
 row(c,"Защищённая казна",fmt(charter?.protected_treasury_cr));
 row(c,"Экономический лимит мандата",fmt(mandate?.budget_ceiling_cr));
 row(c,"Оплачено по мандату",fmt(mandate?.spent_cr));
 const x=el("execution");x.replaceChildren();
 row(x,"Режим мандата",mandate?.mode);
 row(x,"Последний статус",mandate?.last_reason);
 row(x,"Статус предложения",p?.last_reason);
 const head=live.strategy.factions?.find(v=>v.faction_id===id)?.head;
 row(x,"Выбор главы",head?.selected_option);
 row(x,"Причина выбора",head?.reason);
 row(x,"Факт списаний главы",fmt(head?.committed_spend));
 if(pending&&pending.faction_id===id&&p?.proposal_id===pending.proposal_id&&
    p.status===(pending.approve?"approved":"rejected")){
    notice(pending.approve?
      "Решение подтверждено движком. Фактическое исполнение ещё не гарантировано.":
      "Отказ подтверждён движком; контракт по этому разрешению не создаётся.");
    pending=null;
 }
 if(selectedFaction!==id){selectedFaction=id;
   if(!pending)notice("Предложения появляются только при наличии допустимого экономического плана.");}
}
async function choose(approve){
 const faction_id=el("faction").value;
 const proposal_id=live?.strategy.economic_proposals?.[faction_id]?.proposal_id;
 if(!proposal_id)return;
 try{
  el("approve").disabled=true;el("reject").disabled=true;
  const r=await request("/api/player/economic-proposal/decision","POST",
   {faction_id,proposal_id,approve});
  if(r.status!==202)throw Error("Не получен ответ очереди 202");
  pending={faction_id,proposal_id,approve};
  notice("Отправлено на рассмотрение игрового движка. Ответ 202 ещё не означает принятие.");
  await poll();
 }catch(e){notice("Запрос отклонён: "+e.message,true)}
 finally{render()}
}
el("approve").onclick=()=>choose(true);
el("reject").onclick=()=>choose(false);
el("faction").onchange=render;
let polling=false;
async function poll(){
 if(polling)return;polling=true;
 try{
  const [a,b]=await Promise.all([request("/api/strategy"),request("/api/report")]);
  live={strategy:a.data,report:b.data};render();
 }catch(e){notice("Ошибка связи с Genesis: "+e.message,true)}
 finally{polling=false}
}
poll();setInterval(poll,2500);
</script></body></html>''',encoding="utf8")

one(server/"http/api.rs",
    """/// Native faction-wide charter screen: all data read from real strategy.""",
    """/// Live specific-action review from native quote and engine-approved state.
pub async fn observer_economic_approvals_page() -> impl IntoResponse {
    (
        [(axum::http::header::CACHE_CONTROL, "no-store")],
        axum::response::Html(observer_asset(
            "governance-approvals.html",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../observer/governance-approvals.html")),
        )),
    )
}

/// Native faction-wide charter screen: all data read from real strategy.""")
one(server/"runtime.rs",
    """        .route("/observer/governance-charter.html",
            get(api::observer_faction_charter_page))""",
    """        .route("/observer/governance-charter.html",
            get(api::observer_faction_charter_page))
        .route("/observer/governance-approvals.html",
            get(api::observer_economic_approvals_page))""")
one(observer/"governance-charter.html",
    """<a href="/observer/governance-economy.html">Экономика</a>""",
    """<a href="/observer/governance-economy.html">Экономика</a> ·
<a href="/observer/governance-approvals.html">Согласования</a>""")
one(observer/"governance-economy.html",
    """<a href="/observer/governance-charter.html">Устав фракции</a>""",
    """<a href="/observer/governance-charter.html">Устав фракции</a>　<a href="/observer/governance-approvals.html">Согласования</a>""")
one(observer/"governance.html",
    """<a href="/observer/governance-charter.html">Устав</a>""",
    """<a href="/observer/governance-charter.html">Устав</a>　<a href="/observer/governance-approvals.html">Согласования</a>""")
print("Galaxy063: queued player decision, real strategy readback and Observer review screen")
