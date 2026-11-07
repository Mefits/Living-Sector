// The source for Observer's optional live statistics drawer. Bundled into app.js.
import {telemetrySnapshot, TELEMETRY_NAMES, telemetryList, telemetryNumber} from "/observer/telemetry-model.js";
const telemetryFormat=new Intl.NumberFormat("ru-RU",{maximumFractionDigits:1});
const telemetryText=value=>value===null||value===undefined?"—":String(value);
const telemetryFmt=value=>value===null||value===undefined?"—":telemetryFormat.format(value);
const telemetryDom=(tag,cls,value)=>{
  const e=document.createElement(tag);if(cls)e.className=cls;
  if(value!==undefined)e.textContent=telemetryText(value);
  return e;
};
const telemetryState={tab:"overview",scope:"all",history:[],getReport:()=>null,getEvents:()=>[],onSelect:null};
let telemetryEls=null;
function telemetryStat(label,value,note="") {
  const e=telemetryDom("div","telemetry-kpi");
  e.append(telemetryDom("small","",label),telemetryDom("strong","",telemetryFmt(value)));
  if(note)e.append(telemetryDom("span","",note));
  return e;
}
function telemetrySection(title,note=""){
  const box=telemetryDom("section","telemetry-block");
  const h=telemetryDom("header","telemetry-section-head");
  h.append(telemetryDom("b","",title));if(note)h.append(telemetryDom("small","",note));
  box.append(h);return box;
}
function telemetryLine(box,title,value,note=""){
  const row=telemetryDom("div","telemetry-line");
  const a=telemetryDom("span","",title);
  const right=telemetryDom("strong","",telemetryFmt(value));
  if(note)right.title=note;
  row.append(a,right);box.append(row);return row;
}
function telemetryBar(box,title,quantity,maximum,note="",tone="teal"){
  const wrap=telemetryDom("div","telemetry-stock");
  const row=telemetryDom("div","telemetry-stock-head");
  row.append(telemetryDom("span","",title),telemetryDom("strong","",telemetryFmt(quantity)));
  wrap.append(row);
  const track=telemetryDom("div","telemetry-track");
  const fill=telemetryDom("div","telemetry-fill telemetry-"+tone);
  fill.style.width=quantity===null||!Number.isFinite(maximum)||maximum<=0?"0%":
    Math.max(0,Math.min(100,quantity/maximum*100)).toFixed(2)+"%";
  track.append(fill);wrap.append(track);
  if(note)wrap.append(telemetryDom("small","",note));
  box.append(wrap);
}
function telemetryGroups(parent,items,onChoose) {
  for(const item of items) {
    const row=telemetryDom("button","telemetry-object");
    row.type="button";
    const left=telemetryDom("span","");
    left.append(telemetryDom("strong","",item.name||item.id||item.type||"Объект"));
    left.append(telemetryDom("small","",item.type||item.class||item.location||""));
    row.append(left,telemetryDom("span","telemetry-chevron","↗"));
    row.addEventListener("click",()=>onChoose(item));
    parent.append(row);
  }
}
function telemetryScopeOptions(data) {
  const select=telemetryEls.scope;
  const keys=["all",...data.factions.map(f=>f.id).filter(Boolean)];
  const existing=[...select.options].map(x=>x.value);
  if(existing.join("|")===keys.join("|"))return;
  select.replaceChildren();
  select.add(new Option("Весь сектор","all"));
  for(const fac of data.factions) if(fac.id)select.add(new Option(fac.name||fac.id,fac.id));
  if(!keys.includes(telemetryState.scope))telemetryState.scope="all";
  select.value=telemetryState.scope;
}
function telemetryCapture(raw) {
  const snapshot=telemetrySnapshot(raw,"all");
  if(snapshot.tick===null||telemetryState.history.at(-1)?.tick===snapshot.tick)return;
  telemetryState.history.push({tick:snapshot.tick,food:snapshot.totals.food,water:snapshot.totals.water,
    fuel:snapshot.totals.fuel,population:snapshot.population,ships:snapshot.ships.length});
  if(telemetryState.history.length>90)telemetryState.history.shift();
}
function telemetryChart(box) {
  const history=telemetryState.history;
  if(history.length<2){
    box.append(telemetryDom("p","telemetry-note","График появится после нескольких новых снимков. Данные накапливаются только в этой вкладке браузера."));
    return;
  }
  const width=500,height=190,pad=18;
  const valid=history.flatMap(h=>[h.food,h.water,h.fuel]).filter(x=>Number.isFinite(x));
  const maximum=Math.max(1,...valid);
  const x=i=>pad+(width-pad*2)*(i/(history.length-1));
  const y=v=>height-pad-(height-pad*2)*(v/maximum);
  const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");
  svg.setAttribute("viewBox","0 0 500 190");svg.classList.add("telemetry-chart");
  for(let n=0;n<=4;n++){
    const line=document.createElementNS(svg.namespaceURI,"line");
    const yy=pad+n*(height-pad*2)/4;
    line.setAttribute("x1",pad);line.setAttribute("x2",width-pad);
    line.setAttribute("y1",yy);line.setAttribute("y2",yy);
    line.setAttribute("stroke","#24404d");line.setAttribute("stroke-width","1");svg.append(line);
  }
  for(const [key,color] of [["food","#5ecfba"],["water","#7ec8d8"],["fuel","#dda86c"]]){
    let segment=[];
    const flush=()=>{
      if(segment.length<2){segment=[];return;}
      const line=document.createElementNS(svg.namespaceURI,"polyline");
      line.setAttribute("points",segment.join(" "));line.setAttribute("fill","none");
      line.setAttribute("stroke",color);line.setAttribute("stroke-width","2.5");
      line.setAttribute("stroke-linejoin","round");line.setAttribute("stroke-linecap","round");
      svg.append(line);segment=[];
    };
    history.forEach((point,i)=>{
      if(!Number.isFinite(point[key])){flush();return;}
      segment.push(x(i).toFixed(1)+","+y(point[key]).toFixed(1));
    });flush();
  }
  box.append(svg);
  const caption=telemetryDom("div","telemetry-legend");
  for(const [k,color] of [["food","#5ecfba"],["water","#7ec8d8"],["fuel","#dda86c"]]){
    const row=telemetryDom("span","",TELEMETRY_NAMES[k]);
    row.style.color=color;caption.append(row);
  }
  box.append(caption,telemetryDom("p","telemetry-note","Запасы по рынкам сектора · последнее значение тика "+telemetryFmt(history.at(-1).tick)+". Это наблюдаемая история, не серверная статистика всех тиков."));
}
function telemetryView(data,report) {
  const root=telemetryEls.content;root.replaceChildren();
  const tab=telemetryState.tab;
  if(tab==="overview"){
    const grid=telemetryDom("div","telemetry-kpi-grid");
    grid.append(telemetryStat("СИСТЕМЫ",data.systemCount),telemetryStat("НАСЕЛЕНИЕ",data.population),
      telemetryStat("СООРУЖЕНИЯ",data.facilities.length),telemetryStat("КОРАБЛИ",data.ships.length));
    root.append(grid);
    const stock=telemetrySection("Основные резервы","Реальные остатки рынков");
    const max=Math.max(1,...data.stock.map(x=>x.observed_stock?x.stock:0));
    for(const id of ["food","water","fuel","ice","ore"]){
      const good=data.stock.find(x=>x.id===id);
      telemetryBar(stock,TELEMETRY_NAMES[id],good?.observed_stock?good.stock:null,max,
        good?.shortage_ticks>0?"Дефицит "+good.shortage_ticks+" тиков":"",
        good?.shortage_ticks>0?"alert":"teal");
    }
    stock.append(telemetryDom("p","telemetry-note","Длины полос относительные; пределы вместимости складов не выдумываются."));
    root.append(stock);
    const alerts=telemetrySection("Требуют внимания");
    if(data.shortages.length===0)alerts.append(telemetryDom("p","telemetry-note","В текущем снимке нет опубликованных рыночных дефицитов."));
    for(const g of data.shortages)telemetryLine(alerts,TELEMETRY_NAMES[g.id]||g.id,g.shortage_ticks,"Тиков дефицита");
    root.append(alerts);
    const projects=telemetrySection("Строительные площадки");
    telemetryLine(projects,"Количество",data.sites.length);
    for(const site of data.sites.slice(0,8))telemetryLine(projects,site.name||site.id,Number.isFinite(site.progress)?Math.round(site.progress*100)+"%":"—");
    root.append(projects);
  }else if(tab==="resources"||tab==="market"){
    const block=telemetrySection(tab==="resources"?"Запасы ресурсов":"Рынки и спрос",
      data.markets.length+" рынк.");
    const max=Math.max(1,...data.stock.map(x=>x.observed_stock?x.stock:0));
    if(!data.stock.length)block.append(telemetryDom("p","telemetry-note","Нет опубликованных запасов."));
    for(const good of data.stock){
      telemetryBar(block,TELEMETRY_NAMES[good.id]||good.id,
        good.observed_stock?good.stock:null,max,
        good.observed_demand?"Спрос: "+telemetryFmt(good.demand)+(good.shortage_ticks>0?" · Дефицит "+good.shortage_ticks+" тиков":""):"",
        good.shortage_ticks>0?"alert":"teal");
    }
    block.append(telemetryDom("p","telemetry-note","Шкала сравнивает фактические запасы между ресурсами; это не индикатор заполнения склада."));
    root.append(block);
    if(tab==="market")for(const market of data.markets){
      const prices=market.prices||{};
      const card=telemetrySection(market.facility_location||market.id||"Рынок","Текущие цены");
      for(const [id,price] of Object.entries(prices).slice(0,15))
        telemetryLine(card,TELEMETRY_NAMES[id]||id,telemetryNumber(price));
      root.append(card);
    }
  }else if(tab==="industry"){
    const card=telemetrySection("Предприятия","Состояние и персонал");
    if(!data.facilities.length)card.append(telemetryDom("p","telemetry-note","Нет предприятий в выбранной области."));
    for(const fac of data.facilities){
      const panel=telemetryDom("div","telemetry-workplace");
      const title=telemetryDom("div","telemetry-stock-head");
      title.append(telemetryDom("span","",fac.name||fac.type||fac.id),
        telemetryDom("strong","",fac.abandoned?"Заброшено":fac.type||"Объект"));panel.append(title);
      if(telemetryNumber(fac.condition)!==null)
        telemetryBar(panel,"Состояние",Math.max(0,Math.min(1,fac.condition))*100,100,"","teal");
      const crew=fac.crew||{};
      if(crew.work_shift?.workers!==undefined)telemetryLine(panel,"Последняя смена",crew.work_shift.workers);
      if(crew.work_blocked_reason)panel.append(telemetryDom("small","telemetry-danger",crew.work_blocked_reason));
      if(telemetryNumber(fac.credits)!==null)telemetryLine(panel,"Касса, CR",fac.credits);
      panel.addEventListener("click",()=>{telemetryState.onSelect?.("facility",fac.id);telemetryOpen(false);});
      panel.tabIndex=0;panel.setAttribute("role","button");
      panel.addEventListener("keydown",ev=>{if(ev.key==="Enter"){panel.click();}});
      card.append(panel);
    }
    root.append(card);
  }else if(tab==="population"){
    const grid=telemetryDom("div","telemetry-kpi-grid");
    grid.append(telemetryStat("ЖИТЕЛИ",data.population),telemetryStat("ГРУППЫ",data.pops.length),
      telemetryStat("КАЗНА ФРАКЦИЙ, CR",data.cash));
    root.append(grid);
    for(const pop of data.pops){
      const block=telemetrySection(pop.label||pop.id||"Население",pop.facility_location||pop.location||"");
      telemetryLine(block,"Численность",telemetryNumber(pop.population_count));
      telemetryLine(block,"Средства, CR",telemetryNumber(pop.total_wealth));
      const satisfaction=telemetryNumber(pop.food_satisfaction);
      if(satisfaction!==null)telemetryBar(block,"Удовлетворённость едой",satisfaction,100,"","teal");
      if(telemetryNumber(pop.overall_sentiment)!==null)
        telemetryBar(block,"Настроение",pop.overall_sentiment,100,"","teal");
      root.append(block);
    }
  }else if(tab==="fleet"){
    const grid=telemetryDom("div","telemetry-kpi-grid");
    grid.append(telemetryStat("КОРАБЛИ",data.ships.length),
      telemetryStat("С ГРУЗОМ",data.ships.filter(x=>Object.values(x.cargo||{}).some(v=>Number(v)>0)).length));
    root.append(grid);
    const block=telemetrySection("Флот","Клик — открыть в игровом инспекторе");
    telemetryGroups(block,data.ships,ship=>{telemetryState.onSelect?.("ship",ship.id);telemetryOpen(false);});
    for(const ship of data.ships){
      const fuel=telemetryNumber(ship.fuel);
      const cap=telemetryNumber(ship.fuel_capacity);
      if(fuel!==null&&cap>0)telemetryBar(block,(ship.name||ship.id)+" · топливо",fuel,cap,"","teal");
    }
    root.append(block);
  }else if(tab==="analytics"){
    const block=telemetrySection("История запасов","Food / Water / Fuel");telemetryChart(block);root.append(block);
  }else if(tab==="signals"){
    const block=telemetrySection("События мира","Из живого WebSocket");
    const events=telemetryList(telemetryState.getEvents()).slice(0,60);
    if(!events.length)block.append(telemetryDom("p","telemetry-note","Событий пока нет."));
    for(const row of events) {
      const e=row.event||row;const line=telemetryDom("div","telemetry-event");
      line.append(telemetryDom("small","", "ТИК "+telemetryFmt(row.tick)),
        telemetryDom("span","",e.message||e.kind||e.type||"Событие"));
      block.append(line);
    }
    root.append(block);
  }
}
function telemetryOpen(open) {
  if(!telemetryEls)return;
  if(open) {
    const strategy=document.getElementById("strategy-drawer");
    if(strategy&&!strategy.hidden)document.getElementById("strategy-close")?.click();
  }
  telemetryEls.drawer.hidden=!open;telemetryEls.backdrop.hidden=!open;
  telemetryEls.button.setAttribute("aria-expanded",String(open));
  document.body.classList.toggle("telemetry-open",open);
  if(open){telemetryUpdate();telemetryEls.close.focus();}
  else telemetryEls.button.focus();
}
function telemetryUpdate() {
  if(!telemetryEls||telemetryEls.drawer.hidden)return;
  const report=telemetryState.getReport();
  if(!report){telemetryEls.content.replaceChildren(telemetryDom("p","telemetry-note","Ожидание реального снимка /api/report…"));return;}
  const all=telemetrySnapshot(report,"all");
  telemetryCapture(report);
  telemetryScopeOptions(all);
  const data=telemetrySnapshot(report,telemetryState.scope);
  telemetryEls.tick.textContent="ТИК "+telemetryFmt(data.tick);
  telemetryView(data,report);
}
export function initTelemetryPanel({getReport,getEvents,onSelect}={}){
  if(telemetryEls)return;
  telemetryState.getReport=typeof getReport==="function"?getReport:()=>null;
  telemetryState.getEvents=typeof getEvents==="function"?getEvents:()=>[];
  telemetryState.onSelect=typeof onSelect==="function"?onSelect:null;
  const find=id=>document.getElementById(id);
  telemetryEls={button:find("telemetry-toggle"),drawer:find("telemetry-drawer"),
    backdrop:find("telemetry-backdrop"),close:find("telemetry-close"),tick:find("telemetry-tick"),
    scope:find("telemetry-scope"),content:find("telemetry-content"),tabs:find("telemetry-tabs")};
  if(Object.values(telemetryEls).some(e=>!e))throw Error("Не найдена панель телеметрии");
  telemetryEls.button.addEventListener("click",()=>telemetryOpen(telemetryEls.drawer.hidden));
  telemetryEls.close.addEventListener("click",()=>telemetryOpen(false));
  telemetryEls.backdrop.addEventListener("click",()=>telemetryOpen(false));
  telemetryEls.scope.addEventListener("change",()=>{telemetryState.scope=telemetryEls.scope.value;telemetryUpdate();});
  telemetryEls.tabs.querySelectorAll("button[data-tab]").forEach(button=>button.addEventListener("click",()=>{
    telemetryState.tab=button.dataset.tab;
    telemetryEls.tabs.querySelectorAll("button").forEach(b=>b.classList.toggle("active",b===button));
    telemetryUpdate();
  }));
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!telemetryEls.drawer.hidden)telemetryOpen(false);});
  window.setInterval(telemetryUpdate,4500);
}
