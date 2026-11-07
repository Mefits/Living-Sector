/* Live adapter for the ORIGINAL Observer V5.1 layout.
 * Real values only: GET /api/report, /api/strategy, /api/health, native map's event buffer.
 * No reimplementation of Rust physics, fleet, station-kit, AI, persistence or economy.
 */
(function () {
  "use strict";
  const $ = id => document.getElementById(id);
  const serverMode = /^https?:$/.test(location.protocol);
  const runtime = {context:null,active:serverMode,busy:false,previousTick:null, events:[],health:null,strategic:null,pendingStation:null,lastNativeSelection:""};
  const getNative = () => {
    try { return runtime.context?.nativeFrame?.contentWindow?.__livingSectorNativeBridge || null; }
    catch {return null;}
  };
  const list = x => Array.isArray(x)?x:[];
  const value = x => typeof x==="number"&&Number.isFinite(x)?x:null;
  const count = x => x==null?"—":String(x);
  async function requestJSON(url,opts) {
    const r=await fetch(url,{cache:"no-store",...opts});
    if(!r.ok)throw Error("HTTP "+r.status+" · "+url);
    return r.json();
  }
  function human(s) {return String(s??"").replaceAll("_"," ").replaceAll("-"," ");}
  function prepare(raw,strategy,events) {
    const report = raw?.report??raw?.data??raw;
    if(!Array.isArray(report?.facilities))throw Error("В /api/report нет facilities[]");
    const populations=list(report.populations).map(p=>({...p,count:p.count??p.population_count??null}));
    const ui={...(report.ui||{})};
    const administrative={...(ui.administrators||{})};
    const leaders={...(ui.faction_leaders||{})};
    if(Array.isArray(strategy?.stations)) for(const st of strategy.stations) {
      if(!st.location)continue;
      administrative[st.location]={
        priority:st.head_priority??null,
        strategy:"Назначено "+count(st.assigned_workers)+" из "+count(st.workforce)+" работников",
        reason:st.modules?.map(m=>(m.facility_id||m.facility_type||"")+
          ": "+(m.reason||m.execution_reason||"—")).join("; ")||null,
        modules:st.modules,orders:list(strategy.orders).filter(o=>o.location===st.location)
      };
    }
    if(Array.isArray(strategy?.factions)) for(const fac of strategy.factions){
      if(!fac.faction_id)continue;
      const head=fac.head||{};
      const selected=fac.selected_goal||null;
      leaders[fac.faction_id]={
        status:fac.status??null,
        name:head.name??null,
        goal:selected?.commodity?human(selected.commodity):null,
        priority:head.selected_administrator??fac.administrator??null,
        decision:head.selected_option??null,
        reason:head.reason??fac.reason??null,
        goals:list(fac.goals).map(g=>({title:human(g.commodity||g.goal_id||""),status:g.shortage_ticks>0?
          "Дефицит "+g.shortage_ticks+" тиков":"Наблюдение",reason:null})),
        decisions:head.selected_option?[{tick:head.observed_tick,action:human(head.selected_option),reason:head.reason}]:[],
        risks:list(head.alternatives).filter(a=>a?.blocked_reason).map(a=>a.blocked_reason)
      };
    }
    ui.administrators=administrative;
    ui.faction_leaders=leaders;
    ui.events=events;
    return {...report,populations,markets:list(report.markets),factions:list(report.factions),
      systems:list(report.systems),ships:list(report.ships),construction_sites:list(report.construction_sites),ui};
  }
  function markStatus(msg,live) {
    const el=$("connectionState");if(el)el.textContent=msg;
    const badge=$("sourceBadge");
    if(badge){badge.textContent=live?"● СИМУЛЯЦИЯ LIVE":"НЕТ СОЕДИНЕНИЯ";badge.classList.toggle("live",!!live);}
  }
  function nativeEvents() {
    const bridge=getNative();
    if(!bridge)return runtime.events;
    const arr=list(bridge.getState?.().events);
    if(!arr.length)return runtime.events;
    return arr.slice(-130).map(x=>{
      const e=x?.event??x;
      return { ...e,tick:x.tick??e.tick??null, message:e.message??e.kind??e.type??"",
        kind:e.kind??e.type??"event"};
    });
  }
  function updateRuntimeUI(h,report) {
    const speed=$("v51Speed"),pause=$("v51Pause");
    if(speed&&value(Number(h?.world_speed))!==null){
      speed.disabled=false;speed.value=String(h.world_speed);
    }
    if(pause){pause.disabled=false;pause.textContent=h?.running?"⏸ Пауза":"▶ Продолжить";}
    const tick=$("v51LiveTick");if(tick)tick.textContent=count(report.tick);
  }
  async function refresh(manual=false){
    if(manual)runtime.active=true;
    if(!runtime.active||runtime.busy||!runtime.context)return;
    runtime.busy=true;
    try {
      const api=runtime.context.state.api||"/api/report";
      const [report,strategic,health]=await Promise.all([
        requestJSON(api),requestJSON("/api/strategy").catch(()=>null),requestJSON("/api/health").catch(()=>null)
      ]);
      runtime.strategic=strategic;
      runtime.health=health;
      runtime.events=nativeEvents();
      const normalized=prepare(report,strategic,runtime.events);
      const state=runtime.context.state;
      const previous=state.location;
      const stations=normalized.facilities.filter(x=>x.type==="station"&&x.location);
      state.report=normalized;state.isDemo=false;
      if(!stations.some(x=>x.location===previous))state.location=stations[0]?.location||"";
      const pane=$("detailBody"),top=pane?.scrollTop||0;
      runtime.context.renderAll();
      if(pane)pane.scrollTop=top;
      if(runtime.previousTick!==normalized.tick||manual){
        const active=$("modalBackdrop");
        if(active&&!active.hidden) {
          const modalType=active.getAttribute("data-live-type");
          if(modalType)runtime.context.openModal(modalType);
        }
      }
      runtime.previousTick=normalized.tick;
      updateRuntimeUI(health,normalized);
      markStatus("Связь с Rust · тик "+count(normalized.tick),true);
      if(runtime.pendingStation){getNative()?.selectStation?.(runtime.pendingStation);runtime.pendingStation=null;}
      if(manual)runtime.context.toast("Данные симуляции обновлены");
    } catch(e) {
      markStatus("Сервер недоступен · "+e.message,false);
      if(manual)runtime.context.toast("Не удалось получить данные: "+e.message);
    } finally {runtime.busy=false;}
  }
  function selectedFromNative(item) {
    if(!runtime.active||!runtime.context||!item)return;
    const state=runtime.context.state;
    const fac=list(state.report.facilities).find(f=>f.id===item.id);
    const ship=list(state.report.ships).find(s=>s.id===item.id);
    const loc=fac?.location??ship?.location??null;
    if(loc&&state.location!==loc){state.location=loc;runtime.context.renderAll();}
    if(item.type==="ship"&&ship){
      state.selectedShip=ship.id;
    } else if((item.type==="facility"||item.type==="facility_group")&&fac) {
      state.selectedFacility=fac.id;
    }
  }
  function nativeSync() {
    const bridge=getNative();if(!bridge)return;
    if(runtime.pendingStation){bridge.selectStation?.(runtime.pendingStation);runtime.pendingStation=null;}
    const data=bridge.getState?.();
    if(!data)return;
    runtime.events=nativeEvents();
    if(Number.isFinite(data.zoom)) {const label=$("zoomLabel");if(label)label.textContent=Math.round(data.zoom*100)+"%";}
    const k=JSON.stringify(data.selection||null);
    if(k!==runtime.lastNativeSelection){runtime.lastNativeSelection=k;selectedFromNative(data.selection);}
  }
  function command(action,payload){
    const bridge=getNative();
    if(!bridge)return;
    if(action==="reset")bridge.reset?.();
    if(action==="zoom")bridge.zoom?.(payload);
    if(action==="selectStation")bridge.selectStation?.(payload);
  }
  async function control(path,body) {
    try{
      await requestJSON(path,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
      const h=await requestJSON("/api/health");runtime.health=h;updateRuntimeUI(h,runtime.context.state.report);
    }catch(e){runtime.context.toast("Команда не выполнена: "+e.message);}
  }
  function start(context){
    if(!serverMode||runtime.context)return;
    runtime.context=context;
    document.body.classList.add("v51-live");
    const runtimeControls=$("v51LiveControls");if(runtimeControls)runtimeControls.hidden=false;
    const nativeFrame=context.nativeFrame;
    nativeFrame?.addEventListener("load",nativeSync);
    window.addEventListener("message",e=>{
      if(e.source!==nativeFrame?.contentWindow||e.origin!==location.origin)return;
      const data=e.data;
      if(data?.type!=="living-sector-native-selection")return;
      const key=JSON.stringify(data.selection||null);
      if(key!==runtime.lastNativeSelection){runtime.lastNativeSelection=key;selectedFromNative(data.selection);}
    });
    document.body.addEventListener("click",e=>{
      if(!runtime.active)return;
      const el=e.target.closest("[data-select]");
      if(el?.dataset?.select){runtime.pendingStation=el.dataset.select;command("selectStation",el.dataset.select);}
    },true);
    $("mapResetBtn")?.addEventListener("click",()=>command("reset"),false);
    $("mapZoomIn")?.addEventListener("click",()=>command("zoom",1.18),false);
    $("mapZoomOut")?.addEventListener("click",()=>command("zoom",1/1.18),false);
    $("v51Pause")?.addEventListener("click",()=>control(runtime.health?.running?
      "/api/sim/pause":"/api/sim/resume",{}));
    $("v51Speed")?.addEventListener("change",()=>{const worldSpeed=Number($("v51Speed").value);
      control("/api/sim/speed",{world_speed:worldSpeed,ticks_per_second:worldSpeed>8?16:8});
    });
    refresh();
    window.setInterval(()=>refresh(),2600);
    window.setInterval(nativeSync,600);
  }
  window.LivingSectorV51={
    prepare,
    isLive:()=>serverMode,
    start,refresh,
    pauseLiveForImport:()=>{runtime.active=false;markStatus("Режим файла JSON",false);}
  };
})();