"""Galaxy 0.6.2 — queued engine API and live Observer charter console.

No Javascript or HTTP handler edits ECS/treasury. Player-visible approval
is a CUMULATIVE allowance of real committed CR for the relevant mandate.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
server=root/"crates/sim_server/src"
observer=root/"observer"

def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy062 API/UI anchor drift {path}: {n} {old[:90]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

one(server/"control.rs",
    """    PlayerClearEconomicMandate {faction_id:String},
    AdminSetRelations {""",
    """    PlayerClearEconomicMandate {faction_id:String},
    PlayerSetFactionCharter {
        faction_id:String,
        charter:sim_core::strategy::charter::FactionCharter,
    },
    AdminSetRelations {""")
one(server/"engine.rs",
    """                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""",
    """                ControlCommand::PlayerSetFactionCharter {faction_id,charter} => {
                    let now=tick_counter.load(Ordering::Relaxed);
                    let result=sim_core::strategy::charter::set_charter(
                        &mut world,&faction_id,charter,now);
                    events.push(serde_json::json!({
                        "kind":"player_faction_charter_applied",
                        "tick":now,"faction_id":faction_id,
                        "status":if result.is_ok(){"applied"}else{"rejected"},
                        "reason":result.err(),
                    }));
                }
                ControlCommand::AdminSetRelations { a, b, standing, treaty } => {""")
one(server/"snapshot.rs",
    """                snapshot.economic_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_mandates.clone()).unwrap_or_default();""",
    """                snapshot.economic_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.economic_mandates.clone()).unwrap_or_default();
                snapshot.faction_charters = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.faction_charters.clone()).unwrap_or_default();""")
one(server/"runtime.rs",
    """        .route("/api/player/economic-mandate/{faction_id}",
            delete(player::clear_economic_mandate))""",
    """        .route("/api/player/economic-mandate/{faction_id}",
            delete(player::clear_economic_mandate))
        .route("/api/player/faction-charter",post(player::set_faction_charter))""")

# A strict request DTO prevents a forged request from rewriting saved CR
# receipts: the engine side will inherit all actual payments from Director.
p=server/"http/player.rs"
s=p.read_text(encoding="utf8")
if "pub async fn set_faction_charter" in s: raise RuntimeError("Charter API already installed")
s+=r'''

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
'''
p.write_text(s,encoding="utf8")

page=observer/"governance-charter.html"
if page.exists():raise RuntimeError("Charter UI already exists")
page.write_text(r'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Living Sector — Устав фракции</title>
<style>
:root{color-scheme:dark;font:14px system-ui,sans-serif;background:#101923;color:#e1edf4}
*{box-sizing:border-box}body{margin:0}
header{background:#152333;border-bottom:1px solid #30485a;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:17px 25px;flex-wrap:wrap}
h1{font-size:19px;margin:0 0 5px}h2{font-size:16px;margin:0 0 15px}
p{line-height:1.5}small,.hint{color:#a6bdc9}a{color:#89cfdf;text-decoration:none}
main{max-width:1240px;margin:auto;padding:20px;display:grid;grid-template-columns:minmax(320px,450px) minmax(330px,1fr);gap:20px}
article{background:#172839;border:1px solid #324b5d;border-radius:9px;padding:18px;margin-bottom:16px}
label{display:block;margin:13px 0 5px;color:#c3d5df}
input,select,button{font:inherit;color:#f0f8fb;background:#203649;border:1px solid #486073;border-radius:6px;padding:10px;width:100%}
button{background:#276575;cursor:pointer;margin-top:17px;font-weight:600}
button:disabled{opacity:.55}
.twocol{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.line{display:flex;justify-content:space-between;gap:10px;padding:9px 0;border-bottom:1px solid #304658}
.line strong{text-align:right;font-variant-numeric:tabular-nums}
.hint{font-size:12px;line-height:1.6}
.alert{padding:12px;background:#20394a;border-left:3px solid #81bfcc}
.error{border-color:#de847d}
progress{width:100%;height:14px;accent-color:#8cc4cb}
@media(max-width:800px){main{grid-template-columns:1fr;padding:12px}.twocol{grid-template-columns:1fr}}
</style>
</head>
<body>
<header>
 <div><h1>Устав фракции</h1><small>Полномочия главы, приоритеты и общее финансирование поручений</small></div>
 <nav><a href="/observer/">Галактика</a> · <a href="/observer/governance.html">Наука</a> · <a href="/observer/governance-economy.html">Экономика</a></nav>
</header>
<main>
<section>
 <article>
 <h2>Политика игрока</h2>
 <form id="form">
  <label for="faction">Фракция</label><select id="faction" required></select>
  <div class="twocol">
   <div><label for="research_authority">Научные мандаты</label><select id="research_authority">
    <option value="delegated">Делегировать</option><option value="review">Согласовывать расходы</option><option value="autonomous">Не направлять</option></select></div>
   <div><label for="economy_authority">Экономические мандаты</label><select id="economy_authority">
    <option value="delegated">Делегировать</option><option value="review">Согласовывать расходы</option><option value="autonomous">Не направлять</option></select></div>
  </div>
  <div class="twocol">
   <div><label for="research_priority">Приоритет науки (0–100)</label><input id="research_priority" type="number" min="0" max="100" step="1" value="50"></div>
   <div><label for="economy_priority">Приоритет экономики (0–100)</label><input id="economy_priority" type="number" min="0" max="100" step="1" value="50"></div>
  </div>
  <div class="twocol">
   <div><label for="shared_ceiling_cr">Общий лимит, CR</label><input id="shared_ceiling_cr" type="number" min="100" max="1000000000" step="100" value="60000"></div>
   <div><label for="protected_treasury_cr">Резерв казны, CR</label><input id="protected_treasury_cr" type="number" min="10000" max="1000000000" step="1000" value="10000"></div>
  </div>
  <div class="twocol">
   <div><label for="approved_research_cr">Одобрено на науку, CR</label><input id="approved_research_cr" type="number" min="0" max="1000000000" step="100" value="0"></div>
   <div><label for="approved_economy_cr">Одобрено на экономику, CR</label><input id="approved_economy_cr" type="number" min="0" max="1000000000" step="100" value="0"></div>
  </div>
  <p class="hint">В режиме «Согласовывать расходы» ИИ может потратить только заранее одобренную совокупную сумму. Увеличение суммы = новое разрешение, уже потраченная часть не обнуляется. Это не автоматическая заявка с кнопкой «Одобрить один контракт».</p>
  <button type="submit" id="submit">Отправить устав главе</button>
 </form>
 <p id="notice" role="status" class="alert">Подключение к серверу…</p>
 </article>
 <article><h2>Жёсткие ограничения</h2>
  <p class="hint">Устав регулирует только новые расходы по мандатам игрока. Неприкосновенный резерв и общая сумма здесь не останавливают обычные зарплаты, аварийное обеспечение водой и пищей, уже оплаченные доставки и самостоятельную экономику Genesis. Устав не создаёт ресурсы и не отменяет контракты.</p>
 </article>
</section>
<section>
 <article><h2>Применённый устав</h2><div id="state"></div><progress id="meter" max="100" value="0"></progress></article>
 <article><h2>Статус главы</h2><div id="decision"></div></article>
 <article><h2>Планирование vs исполнение</h2><p class="hint">Ответ HTTP 202 означает только постановку приказа в очередь. Применение подтверждается в /api/strategy; завершение работы — только реальными контрактами, платежами и производством. Приоритеты не перескакивают через уже профинансированные планы и кризисы жизнеобеспечения.</p></article>
</section>
</main>
<script>
"use strict";
const el=id=>document.getElementById(id);
const numbers=["research_priority","economy_priority","shared_ceiling_cr",
"protected_treasury_cr","approved_research_cr","approved_economy_cr"];
let state=null,pending=null,lastFaction=null;
const fmt=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("ru-RU")+" CR":"—";
function row(target,key,value){
 const r=document.createElement("div");r.className="line";
 const a=document.createElement("span"),b=document.createElement("strong");
 a.textContent=key;b.textContent=value==null?"—":String(value);r.append(a,b);target.append(r);
}
function notify(text,isError=false){el("notice").textContent=text;el("notice").classList.toggle("error",isError)}
function current(){return state?.strategy?.faction_charters?.[el("faction").value]}
function loadForm(c){
 if(!c)return;
 for(const key of ["research_authority","economy_authority",...numbers])
   el(key).value=String(c[key]);
}
async function request(url,method,body){
 const opt={cache:"no-store"};if(method){opt.method=method;if(body){
  opt.headers={"Content-Type":"application/json"};opt.body=JSON.stringify(body)}}
 const res=await fetch(url,opt);let value={};try{value=await res.json()}catch{}
 if(!res.ok)throw Error(value.error||"HTTP "+res.status);return {code:res.status,data:value};
}
function render(){
 if(!state)return;
 const names=state.report.factions||[];
 const ids=Object.keys(state.strategy.commanders||{});
 const possible=names.filter(f=>ids.includes(f.id));
 const sel=el("faction"),before=sel.value;
 sel.replaceChildren();
 for(const f of possible){let o=document.createElement("option");o.value=f.id;o.textContent=f.name||f.id;sel.append(o)}
 if(possible.some(f=>f.id===before))sel.value=before;
 const id=sel.value,c=current(),f=names.find(f=>f.id===id);
 if(id!==lastFaction){lastFaction=id;loadForm(c)}
 const st=el("state");st.replaceChildren();
 row(st,"Фракция",f?.name||id);row(st,"Казна",fmt(f?.treasury));
 row(st,"Устав",c?"Применён":"Отсутствует — действуют мандаты 0.6.1");
 if(c){
  row(st,"Наука / экономика",c.research_authority+" / "+c.economy_authority);
  row(st,"Приоритеты",c.research_priority+" / "+c.economy_priority);
  row(st,"Общий лимит",fmt(c.shared_ceiling_cr));
  row(st,"Подтверждено выплачено",fmt(c.spent_cr));
  row(st,"Наука оплачено",fmt(c.spent_research_cr));
  row(st,"Экономика оплачено",fmt(c.spent_economy_cr));
  row(st,"Резерв",fmt(c.protected_treasury_cr));
  row(st,"Допуск науки",fmt(c.approved_research_cr));
  row(st,"Допуск экономики",fmt(c.approved_economy_cr));
  row(st,"Последний статус",c.last_reason);
  el("meter").max=Math.max(c.shared_ceiling_cr,1);
  el("meter").value=Math.min(c.spent_cr,c.shared_ceiling_cr);
 }else{el("meter").value=0;el("meter").max=100}
 const head=state.strategy.factions?.find(x=>x.faction_id===id)?.head;
 const d=el("decision");d.replaceChildren();
 row(d,"Выбор",head?.selected_option);
 row(d,"Причина",head?.reason);
 row(d,"Фактически потрачено",fmt(head?.committed_spend));
 row(d,"Научный мандат",state.strategy.research_mandates?.[id]?.target_technology||"—");
 const econ=state.strategy.economic_mandates?.[id];
 row(d,"Экономический мандат",econ?econ.kind+" · "+econ.commodity+" · "+econ.location:"—");
 if(pending&&c&&pending.faction_id===id&&
     Object.keys(pending).filter(k=>k!=="faction_id").every(k=>c[k]===pending[k])){
     notify("Устав подтверждён нативным игровым движком. Новые решения будут видны по фактическим квитанциям.");
     pending=null;loadForm(c);
 }
}
let polling=false;
async function poll(){
 if(polling)return;polling=true;
 try{
  const [s,r]=await Promise.all([request("/api/strategy"),request("/api/report")]);
  state={strategy:s.data,report:r.data};render();
 }catch(e){notify("Не удалось получить реальные данные: "+e.message,true)}
 finally{polling=false}
}
el("faction").addEventListener("change",()=>{lastFaction=null;render()});
el("form").addEventListener("submit",async event=>{
 event.preventDefault();
 const body={faction_id:el("faction").value,
  research_authority:el("research_authority").value,
  economy_authority:el("economy_authority").value};
 for(const n of numbers)body[n]=Number(el(n).value);
 if(!numbers.every(n=>Number.isSafeInteger(body[n]))){
  notify("Все суммы и приоритеты должны быть целыми числами.",true);return}
 try{
  el("submit").disabled=true;
  const answer=await request("/api/player/faction-charter","POST",body);
  if(answer.code!==202)throw Error("Не получен статус очереди 202");
  pending=body;
  notify("Устав отправлен в очередь. Проверяем, применил ли его игровой движок.");
  await poll();
 }catch(e){notify("Устав отклонён: "+e.message,true)}
 finally{el("submit").disabled=false}
});
poll();setInterval(poll,2500);
</script>
</body>
</html>''',encoding="utf8")
one(server/"http/api.rs",
    """/// Live native-funded economic governance: stock and orders are API facts.""",
    """/// Native faction-wide charter screen: all data read from real strategy.
pub async fn observer_faction_charter_page() -> impl IntoResponse {
    (
        [(axum::http::header::CACHE_CONTROL, "no-store")],
        axum::response::Html(observer_asset(
            "governance-charter.html",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../observer/governance-charter.html")),
        )),
    )
}

/// Live native-funded economic governance: stock and orders are API facts.""")
one(server/"runtime.rs",
    """        .route("/observer/governance-economy.html",
            get(api::observer_economic_governance_page))""",
    """        .route("/observer/governance-economy.html",
            get(api::observer_economic_governance_page))
        .route("/observer/governance-charter.html",
            get(api::observer_faction_charter_page))""")

one(observer/"governance.html",
    """<a href="/observer/governance-economy.html">Экономика</a>""",
    """<a href="/observer/governance-economy.html">Экономика</a>　<a href="/observer/governance-charter.html">Устав</a>""")
one(observer/"governance-economy.html",
    """<a href="/observer/governance.html">Научное управление</a>""",
    """<a href="/observer/governance.html">Научное управление</a>　<a href="/observer/governance-charter.html">Устав фракции</a>""")
print("Galaxy062: engine-queued validated charter route and live in-game charter UI")
