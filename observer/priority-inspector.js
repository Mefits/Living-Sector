// Galaxy 0.4 Observer: decision-first, data-grounded selection cards.
// No simulation logic; do not infer cargo, inventory limits, routes or AI tasks.
import {
  commodityLabel, factionName, sortedCargo, stationEconomy, list, number
} from "./model.js";

const GOALS = Object.freeze({
  trade_run:"Торговый рейс",
  sell_cargo:"Продажа груза",
  mine_asteroid:"Добыча сырья",
  mine:"Добыча сырья",
  contract_delivery:"Доставка по контракту",
  delivery:"Доставка груза",
  supply:"Снабжение",
  refuel:"Заправка",
  repair:"Ремонт",
  retrofit:"Модернизация",
  idle:"Ожидание",
  patrol:"Патрулирование",
  construction:"Строительство",
  colonize:"Колонизация",
  explore:"Исследование",
  salvage:"Сбор обломков"
});
const ROLES = Object.freeze({
  station:"Станционный узел",mining_rig:"Добыча сырья",
  gas_harvester:"Добыча газа",salvage_field:"Сбор обломков",
  refinery:"Переработка",smelter:"Металлургия",factory:"Производство",
  farm:"Производство продовольствия",shipyard:"Кораблестроение",
  warehouse:"Склад",cargo_warehouse:"Склад",fuel_depot:"Склад топлива",
  repair_dock:"Ремонт",gate:"Транспортный узел",jump_gate:"Транспортный узел",
  patrol_base:"Охрана",observation_station:"Наблюдение"
});
const numberFormat=new Intl.NumberFormat("ru-RU",{maximumFractionDigits:1});
const known=(value)=>value!==null&&value!==undefined&&value!=="";
const nfmt=value=>known(value)&&Number.isFinite(Number(value))
  ?numberFormat.format(Number(value)):"—";
const shown=value=>known(value)?String(value):"—";
const nice=key=>GOALS[String(key??"").toLowerCase()]
  ??(known(key)?String(key).replaceAll("_"," "):"Нет активной задачи");
const safePercent=value=>Number.isFinite(Number(value))
  ?Math.max(0,Math.min(100,Number(value)*100)):null;

export function shipPriority(ship,index) {
  const travel=ship?.transit??null;
  const action=String(ship?.current_bt??"");
  const parsed=action.match(/Travel\s*\{\s*destination:\s*"([^"]+)"/);
  const destination=travel?.to??parsed?.[1]??null;
  const origin=travel?.from??ship?.location??null;
  const total=Number(travel?.distance_total);
  const progress=travel&&total>0
    ?safePercent(Number(travel.distance_travelled)/total):null;
  const cargo=sortedCargo(ship?.cargo).map(([id,quantity])=>({
    id, label:commodityLabel(id), quantity:Number(quantity)
  }));
  const faction=factionName(ship?.faction_id,index);
  return {
    faction,
    task:nice(ship?.current_goal),
    rawTask:shown(ship?.current_goal),
    action:shown(ship?.current_bt),
    status:travel?"В полёте":ship?.docked===true?"Пристыкован":
      known(ship?.location)?"На локации":"Местоположение неизвестно",
    origin,destination,progress,cargo,
    cargoUsed:cargo.reduce((sum,item)=>sum+item.quantity,0),
    cargoCapacity:Number.isFinite(Number(ship?.cargo_capacity))?Number(ship.cargo_capacity):null
  };
}

export function resourceGradeEntries(body) {
  const grades=body?.resource_grades;
  if(!grades || typeof grades!=="object" || Array.isArray(grades))return [];
  return Object.entries(grades)
    .filter(([,g])=>Number.isInteger(g)&&g>=1&&g<=5)
    .map(([id,grade])=>({id,label:commodityLabel(id),grade}))
    .sort((a,b)=>b.grade-a.grade||a.id.localeCompare(b.id));
}
const has=(obj,key)=>Object.prototype.hasOwnProperty.call(obj??{},key);
function node(doc,tag,className,text) {
  const el=doc.createElement(tag);
  if(className)el.className=className;
  if(text!==undefined)el.textContent=String(text);
  return el;
}
function block(parent,label,value) {
  const wrap=node(parent.ownerDocument,"div","priority-line");
  wrap.append(node(parent.ownerDocument,"span","priority-label",label),
    node(parent.ownerDocument,"strong","priority-value",shown(value)));
  parent.append(wrap);
  return wrap;
}
function heading(parent,kind,faction,status) {
  const doc=parent.ownerDocument;
  const header=node(doc,"div","priority-header");
  const top=node(doc,"div","priority-kicker",kind);
  header.append(top);
  const title=node(doc,"div","priority-faction",shown(faction));
  header.append(title);
  if(status)header.append(node(doc,"span","priority-status",status));
  parent.append(header);
}
function section(parent,label) {
  const doc=parent.ownerDocument,card=node(doc,"section","priority-section");
  card.append(node(doc,"div","priority-section-title",label));
  parent.append(card);
  return card;
}
function technical(parent) {
  const doc=parent.ownerDocument;
  const details=node(doc,"details","priority-technical");
  details.append(node(doc,"summary",null,"Дополнительные сведения"));
  parent.append(details);
  return details;
}
function stockRows(parent, market, {limit=8}={}) {
  const doc=parent.ownerDocument;
  if(!market || !market.supply || typeof market.supply!=="object") {
    parent.append(node(doc,"p","priority-muted","Данных о запасах нет"));
    return;
  }
  const goods=["food","water","fuel",...Object.keys(market.supply)]
    .filter((id,i,arr)=>arr.indexOf(id)===i)
    .filter(id=>has(market.supply,id)||["food","water","fuel"].includes(id))
    .slice(0,limit);
  for(const id of goods) {
    const value=has(market.supply,id)?market.supply[id]:0;
    const row=block(parent,commodityLabel(id),nfmt(value));
    if(Number(market.shortage_ticks?.[id])>0)row.classList.add("priority-shortage");
  }
}
function shipCard(parent,ship,index) {
  const doc=parent.ownerDocument;
  const summary=shipPriority(ship,index);
  heading(parent,"КОРАБЛЬ · "+shown(ship?.class),summary.faction,summary.status);
  const task=section(parent,"ТЕКУЩАЯ ЗАДАЧА");
  task.append(node(doc,"div","priority-task",summary.task));
  const route=section(parent,"МАРШРУТ / МЕСТОНАХОЖДЕНИЕ");
  if(summary.destination) {
    block(route,"Откуда",shown(summary.origin));
    block(route,"Куда",summary.destination);
  } else {
    block(route,"Сейчас",shown(ship?.location??ship?.transit?.from));
    route.append(node(doc,"p","priority-muted","Пункт назначения не предоставлен сервером"));
  }
  if(summary.progress!==null) {
    const progress=node(doc,"div","priority-progress");
    progress.append(node(doc,"span",null,"Пройдено "+nfmt(summary.progress)+"%"));
    const track=node(doc,"div","priority-progress-track");
    const fill=node(doc,"div","priority-progress-fill");
    fill.style.width=summary.progress+"%";
    track.append(fill);progress.append(track);route.append(progress);
  }
  const cargo=section(parent,"ГРУЗ В ТРЮМЕ");
  if(summary.cargo.length) {
    for(const item of summary.cargo)block(cargo,item.label,nfmt(item.quantity));
  } else cargo.append(node(doc,"p","priority-muted","Трюм пуст"));
  if(summary.cargoCapacity!==null)
    block(cargo,"Загрузка",nfmt(summary.cargoUsed)+" / "+nfmt(summary.cargoCapacity));
  const details=technical(parent);
  block(details,"Название",ship?.name??ship?.id);
  block(details,"Внутренний ID",ship?.id);
  block(details,"Цель ИИ (код)",summary.rawTask);
  block(details,"Действие ИИ",summary.action);
  block(details,"Топливо",nfmt(ship?.fuel)+" / "+nfmt(ship?.fuel_capacity));
  block(details,"Кредиты",nfmt(ship?.credits)+" CR");
  block(details,"Экипаж",ship?.crew?.size);
  block(details,"Размер",ship?.size);
}
function stationCard(parent,entity,report,index) {
  const doc=parent.ownerDocument;
  const isStation=entity?.type==="station";
  const econ=stationEconomy(report,entity?.location);
  const at=econ?.station??entity;
  heading(parent,isStation?"СТАНЦИЯ":"ПРЕДПРИЯТИЕ",factionName(entity?.faction_id,index),
    entity?.abandoned?"Заброшен":"");
  const main=section(parent,"ДЕЯТЕЛЬНОСТЬ");
  block(main,"Назначение",ROLES[entity?.type]??shown(entity?.type));
  block(main,"Расположение",entity?.location);
  const blocker=entity?.crew?.work_blocked_reason;
  if(blocker)block(main,"Последняя причина простоя",blocker);
  const shift=entity?.crew?.work_shift;
  if(shift?.tick!=null)block(main,"Последняя смена","Тик "+nfmt(shift.tick));
  if(shift?.workers)block(main,"Работники прошлой смены",
    nfmt(list(shift.workers).reduce((v,w)=>v+number(w?.[1]),0)));
  if(isStation || econ?.market) {
    const inventory=section(parent,"ЗАПАСЫ РЫНКА");
    stockRows(inventory,econ?.market);
    if(econ?.shortages?.length)inventory.append(node(doc,"p","priority-warning",
      "Отмечен дефицит: "+econ.shortages.map(g=>commodityLabel(g.id)).join(", ")));
  }
  if(isStation) {
    const factories=section(parent,"ПРЕДПРИЯТИЯ");
    const children=list(econ?.members).filter(f=>f?.id!==at?.id);
    if(!children.length)factories.append(node(doc,"p","priority-muted","Предприятий нет"));
    for(const fac of children.slice(0,14))block(factories,
      ROLES[fac.type]??shown(fac.type),fac.crew?.work_blocked_reason?"Простой: "+fac.crew.work_blocked_reason:"—");
  }
  if(!isStation) {
    const reserve=section(parent,"РЕЗЕРВЫ ПРЕДПРИЯТИЯ");
    const goods=Object.entries(entity?.reserves??{}).filter(([,v])=>Number(v)>0);
    if(!goods.length)reserve.append(node(doc,"p","priority-muted","Резервы отсутствуют"));
    else for(const [commodity,amount] of goods.slice(0,12))
      block(reserve,commodityLabel(commodity),nfmt(amount));
  }
  const details=technical(parent);
  block(details,"Название",entity?.name??entity?.id);
  block(details,"Внутренний ID",entity?.id);
  block(details,"Тип (код)",entity?.type);
  block(details,"Кредиты объекта",nfmt(entity?.credits)+" CR");
  block(details,"Состояние",known(entity?.condition)?nfmt(number(entity.condition)*100)+"%":"—");
  block(details,"Уровень",entity?.level);
  block(details,"Док",list(entity?.docked_ships).length);
  if(econ?.market)block(details,"Источник складских данных","Рынок: "+shown(econ.market.facility_location));
}
function bodyCard(parent,body,index,report) {
  const doc=parent.ownerDocument;
  heading(parent,"НЕБЕСНОЕ ТЕЛО",body?.controlling_faction
    ?factionName(body.controlling_faction,index):"Контроль не установлен",
    body?.contested?"Спорная территория":null);
  const main=section(parent,"РЕСУРСЫ ПЛАНЕТЫ");
  const grades=resourceGradeEntries(body);
  if(grades.length) {
    for(const item of grades) {
      const line=node(doc,"div","priority-grade-line");
      line.append(node(doc,"span",null,item.label));
      const segments=node(doc,"span","priority-grade-segments");
      for(let i=0;i<5;i++){
        const segment=node(doc,"i",i<item.grade?"active":"");
        segments.append(segment);
      }
      line.append(segments,node(doc,"strong",null,"Ур. "+item.grade));
      main.append(line);
    }
    main.append(node(doc,"p","priority-muted",
      "Качество месторождений пока не влияет на добычу. Запасы неисчерпаемы."));
  } else main.append(node(doc,"p","priority-muted",
    "Сервер не предоставил уровни месторождений. Отсутствие сведений не означает отсутствие ресурсов."));
  const location=section(parent,"ОБЪЕКТ И ТЕРРИТОРИЯ");
  block(location,"Тип",shown(body?.type));
  block(location,"Биом",shown(body?.biome));
  const factories=list(report?.facilities).filter(f=>f.body_id===body?.id);
  block(location,"Сооружения",nfmt(factories.length));
  const detail=technical(parent);
  block(detail,"Название",body?.name??body?.id);
  block(detail,"Внутренний ID",body?.id);
  block(detail,"Радиус орбиты",nfmt(body?.orbit_radius));
}
function constructionCard(parent,site,index) {
  const doc=parent.ownerDocument;
  heading(parent,"СТРОИТЕЛЬСТВО",factionName(site?.faction_id,index),null);
  const main=section(parent,"ТЕКУЩАЯ ЗАДАЧА");
  block(main,"Строим",ROLES[site?.facility_type]??shown(site?.facility_type));
  block(main,"Где",site?.location);
  if(site?.labor?.blocked_reason)
    block(main,"Причина ожидания",site.labor.blocked_reason);
  const materials=section(parent,"МАТЕРИАЛЫ И ПРОГРЕСС");
  block(materials,"Материал",commodityLabel(site?.commodity));
  block(materials,"Доставлено",nfmt(site?.progress_delivered)+" / "+nfmt(site?.progress_required));
  const progress=safePercent(site?.progress);
  if(progress!==null)block(materials,"Готовность",nfmt(progress)+"%");
  block(materials,"Труд",nfmt(site?.labor?.completed)+" / "+nfmt(site?.labor?.required));
  const details=technical(parent);
  block(details,"Название",site?.name??site?.id);
  block(details,"Внутренний ID",site?.id);
  block(details,"Источник колонизации",site?.labor?.colony_source);
}
function hubCard(parent,hub,index,report,select) {
  const doc=parent.ownerDocument,members=list(hub?.members);
  const station=members.find(f=>f?.type==="station")??members[0];
  if(!station)return false;
  stationCard(parent,station,report,index);
  const sectionEl=section(parent,"ОБЪЕКТЫ УЗЛА");
  for(const fac of members.slice(0,30)) {
    const button=node(doc,"button","priority-member");
    button.type="button";
    button.append(node(doc,"span",null,ROLES[fac.type]??shown(fac.type)),
      node(doc,"small",null,shown(fac.name??fac.id)));
    button.addEventListener("click",()=>select?.("facility",fac.id));
    sectionEl.append(button);
  }
  return true;
}

/** Renders a complete priority-first card for one known selection kind.
    Other kinds (star systems and ship clusters) use the legacy inspector.
    Returns true only when content was rendered. */
export function renderPriorityInspector(parent,type,entity,{index,report,select}={}) {
  if(!parent||!entity||!index)return false;
  switch(type){
    case "ship":shipCard(parent,entity,index);return true;
    case "facility":stationCard(parent,entity,report,index);return true;
    case "body":bodyCard(parent,entity,index,report);return true;
    case "construction_site":constructionCard(parent,entity,index);return true;
    case "facility_group":return hubCard(parent,entity,index,report,select);
    default:return false;
  }
}
