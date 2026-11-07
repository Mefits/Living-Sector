import {
  list, number, point, key, buildIndex, factionColor, factionName,
  systemByName, positionOf, approximateShipsNear, shortageCount, sortedCargo,
  panForCursorZoom, panToFollowWorldPoint, clusterMarkers, shipSystem, worldGridStep, mapIconScale,
  groupFacilitiesByLocation, layoutMapLabels, shipMapState, shipsAtHub,
  liveEntityPoint, approachWorldPoint,
  commodityLabel, contractLabel, contractCargoLabel
} from "/observer/model.js";
import {drawStationComplex,visualStationTier,stationScale,stationReveal} from "/observer/station-kit.js";

const byId = id => document.getElementById(id);
const els = Object.fromEntries([
  "connection","system-count","system-search","system-list","faction-count","faction-legend",
  "world-title","world-subtitle","tick","agent-count","pause-btn","speed-select","sector-tab","system-tab",
  "ships-toggle","links-toggle","labels-toggle","modules-toggle","fit-btn","map","canvas-holder","hover-label",
  "map-error","data-tick","event-feed","clear-events","export-diagnostics","inspector-body","clear-selection",
  "ship-total","facility-total","market-total","first-run-guide","start-system-btn","dismiss-guide-btn",
  "focus-picker","focus-inner-btn","focus-full-btn","focus-caption","follow-btn"
].map(id => [id.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase()), byId(id)]));

const s = {
  report: null, index: null, ships: [], health: null, positions: new Map(),
  ws: null, wsUp: false, live: false, events: [],
  view: "sector", systemName: null, selection: null,
  zoom: 1, pan: {x: 0, y: 0}, cameraFocus: "inner", follow: null, followVisual: null, dragging: null, hover: null,
  targets: [], visualPositions: new Map(), shipMotion: new Map(),
  mapWorldPositions: new Map(), shipCallsigns: new Map(), shipSymbolVariants: new Map(),
  shipHeading: new Map(),
  lastReportAt: 0, fetching: false, error: null, guideDismissed: false
};
const fmt = new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 1 });
const q = value => value == null ? "—" : String(value);
const fnum = value => value == null ? "—" : fmt.format(number(value));
const ctx = els.map.getContext("2d");
// Facility display catalog. It describes real facility types; a catalog entry
// does not imply that this facility can currently be built or operated.
const FACILITY_CATALOG = Object.freeze({
  station:             {label:"Станция",            role:"Центральный узел",       tone:"#7dbec5",order:0},
  shipyard:            {label:"Верфь",              role:"Производство и ремонт кораблей",tone:"#c6b6dd",order:2},
  mining_rig:          {label:"Добывающая платформа",role:"Добыча ресурсов",       tone:"#dbb579",order:3},
  salvage_field:       {label:"Сборщик обломков",   role:"Извлечение ресурсов",    tone:"#c4a77d",order:4},
  gas_harvester:       {label:"Газодобывающая станция",role:"Добыча газа",         tone:"#a7bf9d",order:4},
  refinery:            {label:"Переработчик",      role:"Первичная переработка", tone:"#ce9f8a",order:5},
  smelter:             {label:"Плавильня",         role:"Металлургия",           tone:"#ca9979",order:5},
  factory:             {label:"Фабрика",           role:"Производство компонентов",tone:"#9cbed7",order:6},
  farm:                {label:"Ферма",             role:"Пища и агрокультура",   tone:"#89c5a4",order:7},
  cargo_warehouse:     {label:"Грузовой склад",    role:"Логистическая инфраструктура",tone:"#d3bd8d",order:1},
  warehouse:           {label:"Грузовой склад",    role:"Логистическая инфраструктура",tone:"#d3bd8d",order:1},
  fuel_depot:          {label:"Топливное депо",    role:"Запас топлива",         tone:"#d4b381",order:1},
  repair_dock:         {label:"Ремонтный док",     role:"Ремонт и обслуживание", tone:"#c3bbd8",order:2},
  patrol_base:         {label:"Патрульная база",   role:"Безопасность маршрутов",tone:"#b6bad8",order:8},
  observation_station: {label:"Станция наблюдения",role:"Разведка и мониторинг", tone:"#a3bfcc",order:9},
  solar_power_station: {label:"Солнечная станция",role:"Энергетика",             tone:"#d4c795",order:8},
  gate:                {label:"Врата",             role:"Транспортная инфраструктура",tone:"#a9bdde",order:0},
  jump_gate:           {label:"Врата",             role:"Транспортная инфраструктура",tone:"#a9bdde",order:0}
});
const facilityMeta = type => FACILITY_CATALOG[String(type ?? "")] ??
  {label:String(type || "Неизвестный объект"),role:"Инфраструктура",tone:"#8cb4c1",order:10};
// Display-only localization: keep original body ids/names unchanged for API,
// contracts, persistence and user-provided mods.
const BODY_NAMES_RU = Object.freeze({
  "Earth":"Земля", "Luna":"Луна", "Mars":"Марс",
  "Jupiter":"Юпитер", "Callisto":"Каллисто", "Saturn":"Сатурн",
  "Titan":"Титан", "Enceladus":"Энцелад",
  "Asteroid Belt":"Пояс астероидов",
  "Debris Field near Pirate Base":"Поле обломков у пиратской базы"
});
const bodyDisplayName = body => BODY_NAMES_RU[String(body?.name??"")]??String(body?.name??body?.id??"");
const facilityTypeLabel = type => facilityMeta(type).label;
// UI-only classification. A facility's actual faction, recipe and inventory
// come from the API; the catalog never creates or upgrades a building.
const FACILITY_FAMILIES = Object.freeze({
  station: "station", shipyard: "service", repair_dock: "service",
  mining_rig: "extraction", gas_harvester: "extraction", salvage_field: "extraction",
  refinery: "processing", smelter: "processing",
  factory: "production", farm: "production", solar_power_station: "production",
  cargo_warehouse: "logistics", warehouse: "logistics", fuel_depot: "logistics",
  patrol_base: "service", observation_station: "service",
  gate: "service", jump_gate: "service"
});
const FAMILY_NAMES = Object.freeze({
  station: "Станции", logistics: "Логистика", extraction: "Добыча",
  processing: "Переработка", production: "Производство", service: "Сервис", other: "Другие"
});
const FAMILY_ORDER = Object.freeze(["station","logistics","extraction","processing","production","service","other"]);
function facilityFamily(type){
  return FACILITY_FAMILIES[String(type??"")] ?? "other";
}
function hubTier(members){
  const station=list(members).some(f=>f.type==="station");
  // Display hierarchy, not a claim that this is the faction's legal capital.
  return station && members.length>=4 ? "major" : station ? "outpost" : "industrial";
}
function hubTierLabel(members){
  const tier=hubTier(members);
  return tier==="major"?"Крупный фракционный хаб":tier==="outpost"?"Станционный узел":"Промышленная точка";
}
function appendFacilityBreakdown(parent,members){
  const counts=new Map();
  for(const fac of members){
    const family=facilityFamily(fac.type);
    counts.set(family,(counts.get(family)??0)+1);
  }
  const panel=document.createElement("div");panel.className="facility-breakdown";
  for(const family of FAMILY_ORDER){
    const count=counts.get(family)??0;
    if(!count)continue;
    const el=document.createElement("span");el.className="facility-breakdown-item family-"+family;
    el.appendChild(textEl("strong",String(count)));
    el.appendChild(textEl("span",FAMILY_NAMES[family]));
    panel.appendChild(el);
  }
  parent.appendChild(panel);
}
function facilityTypeSummary(fac){
  const meta=facilityMeta(fac.type);
  const role=meta.label;
  const state=facilityStateLabel(fac);
  return role+" · "+state+" · "+Math.round(Math.max(0,number(fac.condition))*100)+"%";
}
// Source: sim_core/src/economy/recipes.rs in S7, not live activity.
const S7_RECIPES_REFERENCE=Object.freeze({
  refinery:[
    ["Металлы",["ore","fuel"],["metals"]],
    ["Лёд",["ice"],["water","fuel"]],
    ["Топливо",["gas"],["fuel"]],
    ["Полимеры",["gas"],["polymers"]]
  ],
  factory:[
    ["Компоненты",["metals","polymers"],["components"]],
    ["Электроника",["components","metals"],["electronics"]],
    ["Инструменты",["metals","polymers"],["tools"]],
    ["Медицина",["water","components"],["medical"]],
    ["Роскошь",["components","polymers"],["luxury"]]
  ],
  farm:[["Продовольствие",["water"],["food"]]]
});
function appendReferenceRecipes(content,fac){
  const recipes=S7_RECIPES_REFERENCE[fac.type];
  if(!recipes)return;
  detailGroup(content,"Возможные рецепты · S7");
  content.appendChild(textEl("p","Справка по типу объекта, не активное производство. Сервер не передаёт текущий рецепт сооружения.","small-note"));
  for(const [title,inputs,outputs] of recipes){
    const block=document.createElement("div");block.className="recipe-line";
    block.appendChild(textEl("strong",title));
    block.appendChild(textEl("span",inputs.map(commodityLabel).join(" + ")+" → "+outputs.map(commodityLabel).join(" + ")));
    content.appendChild(block);
  }
}
function appendOperationalFacts(content,fac){
  const count=Number(fac.crew?.crew_count);
  if(Number.isFinite(count) && count>=0) inspectorRow(content,"Персонал (факт)",fnum(count));
  const dock=Number(fac.docking_capacity);
  if(Number.isFinite(dock)&&dock>=0) inspectorRow(content,"Мест у причала",fnum(dock));
  const mult=Number(fac.fitting?.stats?.recipe_output_mult);
  if(Number.isFinite(mult)&&mult>0) inspectorRow(content,"Множитель выхода",fnum(mult)+"×");
  if(Array.isArray(fac.services)&&fac.services.length){
    detailGroup(content,"Сервисы объекта");
    chips(content,fac.services.map(x=>String(x)),12);
  }
}
function facilityOrder(a,b) {
  return facilityMeta(a.type).order-facilityMeta(b.type).order ||
    String(a.id).localeCompare(String(b.id));
}
function facilityStateLabel(fac) {
  return fac.abandoned ? "Заброшен" : number(fac.condition)<0.35 ? "Изношен" : "Действует";
}
function inspectorMeter(parent,title,value) {
  if(!Number.isFinite(Number(value)))return;
  const progress=Math.max(0,Math.min(1,Number(value)));
  const wrap=document.createElement("div");wrap.className="meter";
  const info=document.createElement("div");info.className="meter-head";
  info.appendChild(textEl("span",title));
  info.appendChild(textEl("strong",Math.round(progress*100)+"%"));
  const rail=document.createElement("div");rail.className="meter-track";
  const fill=document.createElement("div");fill.className="meter-fill";
  if(progress<.35)fill.classList.add("meter-critical");
  else if(progress<.75)fill.classList.add("meter-low");
  fill.style.width=(progress*100)+"%";rail.appendChild(fill);
  wrap.append(info,rail);parent.appendChild(wrap);
}
// The compact planetary images are six-frame sprite sheets from a CC0 pack.
// Loading is optional: a missing texture falls back to a drawn primitive.
// CC0 public-domain assets by Screaming Brain Studios, resized to 32px frames.
// Data-URI embedding is intentional: Genesis Server exposes only 4 Observer
// static assets and does not serve /observer/planets/*.png.
const PLANET_TEXTURE_DATA = {"earth":"data:image/png;base64,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","hot":"data:image/png;base64,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","icy":"data:image/png;base64,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","jupiter":"data:image/png;base64,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","mars":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAAAgCAYAAABEmHeFAAAdJElEQVR42s3ce4xmZ2Hf8e9zO+e8l7nPXrxrGxsDvoSLyJKmIIjtFhLAEFdqFqmKlFRqY1LLRooi0fSPdtmQpAlEShsgDrRECYlQslYaQeoQVSj2FkIxYDu+7K53vfeZ3bm9897P/bn0jxmbddg1juR3kiONNPNK5/3M7zfPubya8zyCa28KcC/9FO35cHzj/Dv33/imd9GcuXPvdfM+DkLGBEJzlrTOStfe9bnV7zw2Onfqhc+ycqqzteOdGo5a/oHbwYNH1MMPf+Ql/5c//T8+vP/1u965uHj9u2jN3zk9bbxNS5l2N+nkjtPLZ8pznexzZx79q9ELx09M1Bft+Tvbbe07l9bkqWef4ex6n43BRlk3Fj63+r3HRueen1z++YX97ypE485O95I/9cwx2V9dpYpajKt0q/8J+f/2P/7XDyez6p29fvWuzdzd2Wgq79NMUpa4xjTjOi1da9fnVr/zf0fnTp2ceP/zM7GPZSQjAbIxTWZHJdOtz6099dzoG88/+dkvfPSjHYBDjz6qD9999zV98UMGv0FGv0ww74l27/7A9T96l2jM7mN2JuGWtywwb3NmhEQB6w7S9hznnjjGc3/xpdU8bnwxVbOPce7vvg5IIGx//QPCHzAPHDr4yy0p3zO997oP3PJj/1KQzBApWLhRUSydJV1dpb/R4cxgzKZpcvJbT/HM//rD1WJCvmzO0m4Ydt2oWT/xLMsnTtBb73CprElbs5ydcH7RnCXRksZCydJTj9O9cIFynLFqPVl7bmJ+srDwgcU3/phIfYT0JTP7oF45j+v1KUYpl8qacWuWs987xrN/8UcT7X+qFXHL9Yo5YGZ7sK5vv/m59Ywn/vwPV5ld+OLlOnnsN3/+X3390CHkJz4RghAivJoDwAA1TL8PWX1cGP9eIx2z8zeQtObt6tqK1NM3y71vvpXZXXuZawlue90sfpSzfP68Xf3ON0S6eU514ym6YcrXZu8nw9Knfg3utj9wVbnKdt99nzdf+MJH63/3n3/7fQtN9fGZhnivqlIarV2Yxow9eeasXCmb0k83cZUj1D1u2p1Q90dcPHvOrn7nGyLbPKc2X2O/2d5N0pqzS6trsmjtl2ZxjvXVdTZXznD9vMYO04nm/76/Kqv2jXLqhuvodwesXDjOYttRdYcT7z9uzdnzy8sya+yTs6+7AaM0+XCVGZ3RubjM6RPP20vffkyknQn2v7Ym3cxNcv/tb2Dvwm7mpjW37W3hi4pLFy/Yle98UxT9ZVXO72Ep075O9n/y8Pn3/xqHhT145Ih6+CMfcdc+AA4cMDzxRE30ug8Ku/GXSShkonwdGaREKoun6xJcJaHRgmSehbbjdYmjUY/JRptI5ykjE0ZW2QxUmeySvr37kfH8ws/x7f/T3Taveia47/PfM1/46Dvq+3/jDz447bt/ucBQimpcay2kd1L1h0P+bqnHU6cusjkYUlSaxajg+qieiL/ISFKNamOUVMIoGwJrNmFtZFnpbHLs+Qv47gV2i3RnfGDdxnQrRZCKlfUxndNPEdbPotJN0uFr3f9Iiiv8OgTWbUK3Eui4iRdNmvUmurvE+pljnDt1gnw8IJMqDGs5mfwuoV8pTLNNlMyxr+W4MXY03Jhs2EU6R2F0GFtlcylUvPuNcixaj1wy5ud+5yPv74YQxJVXAnXF6DesPFEz9foPqjD66nQYigUVXDvCxAKZKkkWT+OFQjRjWjMJxg7I+msUaY+iyhBB0YoFY4/IvFBtHcS8GNW7E3FbYv0v9PWebzFeu8idd2ouXPBXC/8rv/UHH5zXxVfn6ktiuh66VqSNslaupgUn1oecOn2W9V4HIypU0WHcXZ2YP1WPXDs22/kj0ngaj8TrgM37bJw/xurSabLh5g75MwQUcStm10wDVXRZufgCa5fPMRz3wcvXuP+X+1k8A0KRtBN2zzZpkRLKIYqKgAUHmppeVYvUCdVS7rXPL7byL04nxHZINlinyHoUZYYIglYsGXshsiBVS3nRLjfq61r6tsW4+Qtv/Bc/8633veOOi4cefVQf/aM/8lccAAcVfN3ytvvumU7Sry5Uy2KamlaEqh2oxDA/v5deLSizAoqcOhtTVRm+DuQ1jL3ASMeC1uyNImZiSRxr2lIra8tqbyzaTV28cWNz8CUuXHBXXn0OHjmi/vjn32cfOLJyz/Vz9Vfn0zOiaUe04liVZUHuYDxyPP78aU6cOkfR2aAY9anKyfu1q1DJFHPz+9isoTPK6ax1WHrhOGfPv0A2zLb8MHm/Wws6aUk+zgnFkLQYcenSGmdXO3QLixGWBTN5v0gLfD6kqFLGaUEaFKI1zVQimZOSOe9pSIuJNG2plLXVa+gX5Nt+XqYMRyn90lNKQ/QD/Rta0qiqTKsb2nG7LbM3In/2S7/38Q+5EII4fPgwioMHFQfvCKy/5d3N2YWv7ZlO5Jzt0DZWNqUnMoayfR0zjYR9ckxW5GSVRXgP/oo7KRmRSU0aoJAGoyNmtCLRhjhKVFpXdor65vm9+w6sXnfgKwd/4oA7fvw4B48Edcexh8PtD/zFu1+/d/pru+JITpVrtI2UcbBYB+cGgs6lZbh8km53g7QoJ+9Hcjt/k7K9n9lGzH7G5NmY08srPH/8GJsrq+DDDvkJ++WYsszpjHKyNKXKcvqDEYPeiLJ2ZAjGfvL+xjinSMfURUVdOyId02xPQ7NNqQxjJ7DW0QyWWL22frXt5+MxVVFSVx6tInSUUFy1f00UNVQvG9tdibz5DW9WB67/9//lK4Mnv+GOHDmC4kc+Ifm9B7x6+8/8yZ4k3DybX3IGq2YaETOtNnPTi0wZSahHqDrDu5pOceUtnESgCEHiTYNKRfRLSx0qpPfMxIq+laRlLfeJvGq3p25PCPbRv/n63xw4cMDc9+77wgMP3O3v+dhv/Mn+hri50b/kYmHVdGJomARbwvqFs1w8e5y8u4615Q74Ts00DDOtaeZmXp7flhknL61w5swFinEKKARicv5L/Q9RdYZ0Nd2ypq4ctZBYIkajIYP+CC8iyon7Fb3SUlYOKzWmMYOJDAFN3JxGtKYY1oFhPqRMx7Skp1eL18wX235VOaxQ6MYsURThg0CbxivmX7SDav++/bfHw6H9yMF//Tf79u0zAhB88PffMy3yo4vDp92sG6nEdpnXJXHUICk2cYMlumlKXXmWU8sLmQehwCkgICNBCIE4iohMjNaWWSW4oaVZiBVlXZGPM9qGoFotvxJfPzzRfsstg29+uQeIQ4+H9yzEHG2tnXWzdqBiu8l0yMiygqWn/x/Hv/t1Tl28SJ5WLI2rifsvy593cMNlNscZdWk52dnkr546xXefPsHGShd8iTQT9IsObrBMN822+885OXKUwVBYRbezyunnn+X5kyfxVY02Bq0m658aO8oQUYcIJT3NCJwLNOMIKTVZukn3/FnSpTPYQYfheEw+TifjC08rBhegedX+NWVdko8zWiaEeGrGryXXD5+Kbr3lP33orT0JBL159hNRnQUtDbF0NGKB9powWKXqXaTOx0xjaQqLTjR7Fto0puYx7QYmicAkxEmCUoapWHDzVMybZhJuaCkoxqh0wHwsacRGaLzf3RBzt2r1IAePKCC4zvATUemDEoJIOmIDLqtZPfk0Z5/9WzZWlmlUOU0qzIT9H8y/RJ2PmaKgIUpQhplWQrPRJmpHmHhn/GlKmqJEJw2u2z3P/Pwu5meb7JqZpj0zz8zUNEobpqLJ+3t3zTM3t8jcdMJMHKFMg3azgVKGuabmrdctcNcdb+DHb72RKQ1RMWI+mZDfiJCmQeuq/Wsohqi0z3wsacaREKHyN8w359423XzwSAhKs++nfzqqene1y1Fo1JtKlH0MOdV4BVNtUgXPuHK4oBjLBu2pJq6W1K6gVp4gAmiNBKrguKHhua2tqaqCwSDH1BVTRpPEEic1mVA68rDrTdfdf+TzB3/96Bef+Okpl96lBmloVD0lyh6iHrJ+7mmWTvwtS5eXWRnnVFYylgmtqSZ2kn519fw2aIaiQZxooiCRNqchHd4Ewg74W/03aU+1cLWgsiVSeVxTMz89RbPZoD8e7qiv/17/pbfc0HDcOhXTlwnFRoOFdkKYahH81i3LJP0f7D/D1CVTJvp+/iC1z0oW7pi5/wPw65qpxXfGSYvYXnYqvbz1r2U7BlVhozYDErrCoQMgPVI4BtkQ5xxaCLTySD8iSM2CEtwUN8nTMXmWghDEScxUYhBKUXpBpIWoXO0NzH7ht7/4/tv3/+Q7W1OzJNlpp7PL0nhP3d9gvbvM5X7OZT/FmtZoFQiT9vPLMuJa+QO1rykHQ9Z7G1TVCE2NUg6xI/6V/Y/w3mFEYCoKLMQ108YjjOemxOyY/7L+hWZBC25KGhRpii1HLM60KG+6hUh4uv0BaWWJ1IT8H+h/AALipL2dX1J6gVFS1HXhG8bMfgver0G9S4Rc2N55ZZTDt1q40EbbiOBgvQyEJKCEQ9cZztbEJqIKBUJoYuFxQIWi2dBILOPaEicxCIGIDEQJXkq0inDJFJqWt4NhnF3ov9fukz/qioGo++eUlpY6jhh52Bgp+lWLy97ikgZyJ/xr5PdJQAqHTPvkBeACIXiQiggxcf+a/aNpRDGNVhvdbNFuNZAh3zn/av0Hx7i2NBtTKB3jvKCsckZ1wGiHi5to2pPzX+q/CUJeNb8PDW9KF691ea+W8BNto0jipjTaY1rT1L7c/kClWRgXuCKjYz0tL7k+URQ2YlB6GkohoyaFkxR1wdgJcgFJYlARJNbhlYJkFq0NQisqJ6GuoRjgR6VtGPUTDeFJoqbU2hGMZqP2rOaePGoy16hx+c74kbl2/g3rMU6wIAMasFZjBDvm/0D+wpNoiWw2Ea2aYC6Q0iWXnqRhUGbC/jX6LyQ0GhoRwVxVE4IkK6GbgR8OqKowUf/V9C+sxY57WD9vtbdDXy/+iEwaHlF0EbICHJVSZOmIORUYCE+oK/Zqj5IVbaOZbzQJAXIHkfC0IsVcrIlFiZcCrROECghpCcIjlQChEMoQ4gXtRl2YGXysTte9e/0dMm54RLpBnq/T74/YzCo2hyPmpGcgd8IPiGLzGvkdvirZrSyXfUoMzDUSyrLeIf8q+ZtNvA+MbKBlNNe1GpikQRIKnNgB/xX7lxgVoxoxTQnzecnc3CxpUSB8ICTzE/Z/eP68s4K/fuFjWuy5VYY4gUpRjyCKDBCwRZ+mr/FB4aVmr6gxqkYGwWKsaemazIEMgqa2lAFmZUDZGiE8vrLkgFIxIS+Q3hKSaUo1TxAOX46hux5Fu96ATzRUiqLwjMcVvX7KuNulYcutRw/EZH0Xa0QlXyG/YS8DFCW2rJhRgetbMFRih/yX5194Mb+FRSfYOy/I52MaHYkeVRDcRP1X03+oanJAYIijiHaits7Aqklg8v4Py+/yMX5zM9L4rUelfdxGRR2UCGSlp5YJOhFE1rHXBIJsEuoxRihiAm0RCBoUnrYR5A5clVEAhYhoeUuQGmyN8xLra/ABHQXSWhKEwZc1NlQQmriojVaeIs/o9kakXjPVbOyIL2ji4imSV8jvRZNRb7RVOJ5FFZiNw475V+aPCEyJgNcB6aH2huFMTKEqOkAmIlrBEsRk/FfVf7B4qVDeoYxBxDE21Jhqg7wMBAy+tJPzX0X/oaqRIS8pBjXBJFRqmmzUIZEFmoqiqvECtNHI4DHKIKTBh4CKWjSkwYgaF6BlJMrEbISEzVqjTBMhDE4EXPAUVlFXCldk2KLAeUc6qitXefKBJ5iYlAbdtSUo+0ifU1R2y492xq/U1DXzC+/RQuGDxDmL0s0d9a/MH17MLyKMcAipmWslRI0GHZpbvp6c/6r6f9GXAm0MpjGDlm2w5bbvSUfV5PxX7D/HBc94VFWS3mrpy5rx0FI7iUmmkUajXUUoLKEG4UCEgBSgZSAyTYyKEUkLEc8wrmHkBKdci+NFi2mjcd7hUKwxS0e28TLC+ZLSOYL0NsiEtsx/t+hvlKHyjIc1RRmwRNR4VF0QippQC4SdnF/2O2UoPenQUjt1zfwyBIL3eFshZYSSBpE0d8y/Wn7ZaCLiaTIvyUXEWWY4Xu2c/4r9B4dDs84sfTND3JolbihsAGSwQU3Yf8X8wcbNGWZU8buSOHnI1p582LV5yNgsAm44oIHA4XB++8E900arBCUDUlg8ng2r6HuDjmIqJ1DAvPFIFdMPMWUQXMjhYup4ajNnHAIhBNYry1rl6Tqro7j5kNBQDHo2tSmro5Kqt0kcwONw3k7U13HjIWEgH/ZsEfJr5vemjRARwluCrwkisGHNjvlXz6/p+4g4aYCKibRh0bCD/iv3X237ywWcGAdsFCOl3PJLO3H/WvnXypqOgx5ozdq5fmbAu0vIxDGuxyjXZ15aauupWm0uFoqawG7pCV7QEgGLZaOwxBq80gwqy6Cq2NcUyDqlYwWFC4yylKb0LPdLZs0Ul0PFiaGVYqZRtndNf72/ev4dm62YZHgWlXXoDNbp9ruocZeqspgJ+4NtPxudQTY8o+rq+QtvMbVjoxQUtSetLBuZJ9ZiR/yr5V8vamIpaISIrlOklWV/7JHliE49ef+H9V+6wDhLSYLl0qhAlIozQ8t3L6dSTDXK9q7WxP0X8y+9lL/kubGXDdsvpxabX9cMlz9Hf/aBMqoXV7OVIF0lhkXKW2YdgyxwcVQTJYYQYKQksRBEWDpZjrAVRmuyyFM7wbCwZGnJgSlLWTc51a+xdU1fbk0KfaE7JicKQkvp66rfe+K+v75059Lj7anpB3brsLjeWQprvXVxdq3P61SfwdhzcWSJEj1xf48Jiyud5YCvxTBPeevcVv4Lo5o4MVjnycYVlwq4kDnOdFJCVeyY/1J+KYiDZeOK/NrnDKqaUZ6x2tnkrXG2Q36N0Yo88lRXyf98r6auKxABIQNn+znHenWAIF1d9ntP3D9Zv19T1zU9ufXc8AvdMVkwwSSxrPKs/7F73vXXCjYzylYDM3O3kpml6Ks8LbDWMqMDozKll5UM0opxWiBCRVHllHVGqFIGZcbqqGJUVXhX0CktDSUZ145+YQGLEgItQUlHOxbWxA1V6/jT/qe637jwxU+mb/jxDzVmpnbd7Ubrdm3plHrh/EWKccqM9tt+MVH/TT/+ocb0zJ67TT20lH3V284/pwNZldJNSzbHBRudPhurS1y4dJHRuIcvxwyqjNXhDvjb+WWoyKqcqs4I5ZhemXKxl3Gps8GlS+c5u94lEmFn/GpMv0i5PKpJ6wrnCjZKS3M7f+9FH6iLnE5nhWLYsQGhKhXtkF9jhEBJ0NIxFWNn5uZVKvWnd58++Y2tx6GZmUXtPkPsp5GVpBoJYcc0Yg0BsurFySd+a+6H8EgJhIB1AYRCGYVzDikD+1oRRjo2bUAFiLUAIZFChlooPxStYdl44y1c/GYPgrjnPzw0O7/YPiOq3vSJZ78jjz31bVGsXSSJ1c74v/LQ7GI0c2au5adVyGQoh0JVI6YSQ+0Dae2xNtBf7/Dssec4dfo5ysEAgpu4X/lAVnu8F0jrQQqU8WgCyll6mQcCmxuX+db3nmDl8nn26IARO+P3s4CJNK2GoXAOoz03tiKM9Gw6kN5jRGCz2+XZZ4+FZ0+e8pfGYVjEt0zetwEVArGWCCEBGYIxfiCnh5fmbrjloZ/9UE9trQJRpoRBk7p3N9WwwhXa4LG1pbIWQtiazC+2BmEQIFzYmgwFQCC4rT8EEoISRDKgnSMxAiU04LFSVMMyMuU4+TS9Y18DzIH7VuTRz/9q+rrbfqSZjgd3L7/wXDVcPadlnVHvlP/ffzW96fY3N4sivTvduFTFbqRnlMdVFd2xZVSBtYF0mHJ5dY1BZwWX57gd8Htjy7AC58DXHhc8kbREtiSEAMJDVdAbjlnf3GA0GmCd3SHfg/BIV1M5D1oiFQi5nd86Eg14QX/QY2l1tTpzeWxGm/LT9J77GhwwB+57YnL+FfkDniBFVTf2mHMdPv37D/6br9133+eN2p6hryA8DuFtwO1A7UF9f95VePkCEgEC4opXtr4TApQWIAVCSIxRKClxwjH2sh7nMqqy8Ahu85e2Tue4lSee8AcPHlTj1dbj47D6tuGgf3vn4tnaBb+j/umV0eOK/G3eVbf3e726UkYFL3DUBBzD2mMry8baOuurqzhvES/9XpPzLZaAY2QDRuqtf3xZhxWSgMQFT+6gqgs2VlfIx0Osc7AjvsYHTxEkJtIoAomRL+XXWiKFpKhyLqxv1k+/sBJdvtR7ZHe58kspeFiZqG+MQomt/KkTdalno+WN9JFTp4tfOnDrrP/jP/5NJ64YQdsHAl8B7tlaGwjzqtfSEltHXlOATgQJAS/AKk1uQ10UGJx6hFDcu702zJXLYwggHDxyRD3z2S9/ZfnEk/ekGxf/Ufzx//7mV0yo7pEurRuxMXWIaDYMo9xRFimnTp7l3PHncWWXKyYlT9xPy0ASaYxJiKRB4hFaIELAViUbnRVOPPcUnQvnsaEkBoII1BP1JSJ4pAhEkSAxgikhUAkkIeAElEKx1u3V33v6tHn62KlHhsund8bfuvBglSarfe1U2wzL8Mjys9+99+GHH37JVy+bXLu1/SlwALjtil9UXH0ghqu+LK2ndIHMEorCVXUtIrx+hJ/58L0cPx6usbM8/vDDbP6zE3/a3vzSgTob3hZcvXP+oUPy+MYGp1d+60/fqL52YLZpbqMsnK0rUbsgsnHOaFyysbnOYGMJgp28X33fz9OCovS44MjLEcLleFdibYWtMzqdDiuXV0kHfXxlKW0gnbAfXIl1FSHUeOsQUqGkR1hHYWvSKoThKK2WVzajMxdXHrl88ul7Dx0iHD06OV9Lj7CWwlrSKoS8rCsdT0dZFR65cNvN994B4a677hJHjx4Nf29doJfdZ/wZiLeDuG37tXr7ABE/bFk7H8AGAh4nPQoSHULjEfjgvRx/+MXQ/iq7bvnHD1P0bv0zEvF26vI2qHfGP3o0cNddgl13c+qZ5p/tn7nt7T6av62ua6FDUZtYSYIV6aDHoNfB23ryvnm5r1UQWngSI5BS4GuLxFI6x+bmJt2Vy4wGQ0q/M36wFonDASEEErn1kcTaELRzTgqpRj7Rz5ztPPLMN//6XjgUjh49OlEfD84StLNOCaGi2ev1eiofWbrjxnvv+MixwF1w+PBhf5WFsV4ahC9uXwb1JISfgqQNDQEJiKZFNQNSS4K7chenBL4pkEEIEUQkHUnXMf0p+PP74eMvns39K4zf7Te7AHX3y9B6Esqd848eDTwW4Px5Xvhvn/zy7re//0ntxU+puZvajdnrhGrMkoumLS0hH5cSV+6Yn8xeJ3RzHtnaZWfnFoOKp6WXChVABCgHHTforHub59IFdsQPSqGRRNowZYRrGeXbkZFeR6JqLsqVMu6e6PGpv13/zP1cOOzg6I75ZWNRrrtmd7me+tT/fOz++4//9pvdXYfuElcOfn7IGfXFy9Q86AfB/CK099DYL5jeBboBw4uQL4Ottj54BAnBh0BYg+QhWPwsHO++8j3LP23/jn/+k/PTN77jwWbS+sWk2dxTRVPiwsUlzp4+h1s6BukFsDVIJuff9I4Hm6b1i+2pqT2zN75BzM8tYKXEDy7g+xfJBh2eP3WS408dJ9tYDz5Ua9CYqO+kxA0uwnAZEypMEuF8zGiYhdSxVorGQ8/7hc8e/52P/CP4Ya0UzYcu+4XPfvslP4itU8WrWx36akukt4E7ofVuxB6N8g8SXIwvIbgSsfAZQmUh/yYsHIXj4+399PZ7/EPC/5PwDx48qLY/MMGuO9tv/tG33ymS6XcvrV7W/eeffJCsE2OLHfTfcefidde/u7Uwqwf9/MGm8vGoyFldulyudjufyZ9/zlJe3lE/dzW+tOXCdXs/U/vYbl7a+OY5d8fRjYfvHgPceeiQPnr48D+af+jQo/rw4buv6f9/mDHJ0JU0RdAAAAAASUVORK5CYII=","mercury":"data:image/png;base64,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","moon":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAAAgCAYAAABEmHeFAAAbQElEQVR42s2cWYwc1b3/v+dUVVdV790z3ePp8XiwMRaGBCP8kAAJzpUu0Q0Im5fhL0VXUSR0nQTJCMRDpEjReB4i5SkP1ywhUl4uecJKpEAmIAVFIDZZxHJA2AmEGWwPMz1Ld1dX176e/0P6HPV4FrzNJCWNLI/d9env7yy/5fyqCDa/JADJwN8fAXAvIeQ+xtgRACkAOvDvAYDnAFijo6PPNpvNVv/3MoAY13hNTk5Kp0+fFvyf/OQnjyRJcm+73b6v1+sdWV1dTaMooq7rwjAMtNvtoNfrbRv/xIkTjyRJcm+n07nPNM0jKysr6fLyMl1cXESapmv05/P5Z23b3jb9zWbzyJkzZ9JWq7Vj9v/Rj370yNLS0r1nzpy5b2lp6Uj6T9E7Pv6GYdxnmuYRwzBSVVWpqqpQFAWKogTlcvm5JEksVVWf/cUvftECgKmpKXl6enpTPtlq8h8+fFg5e/bsMwC+CeA7W/z/NZeqqksAfh0EwZsA3ugbivV/rlr88ePHFQDPRFH0TVVVvxNFETEMA71eD4ZhYHl5GaZpwvM8xHG8LXzLsp6JouibmqZ9JwgCYpomgiCAYRj4/PPPYVnWus/LsrzEGPt1kiQ3Xb9pmrAsC1988QU+/fRTRFG0I/anlH6n1WqR+fl5tNttGIYBx3GQJMmOjj+3P2MMsixDURRIkgRKKRqNBjRNg67rS3Ec//pPf/rTm++8884bU1NTdHp6ekO+tAFf6a/YB5vN5vMAjgO4rT/54y9ZODEAlslkipqmPeD7/n/3xb/d9xjSlxnh+PHjyksvvRQ//vjjD0qS9HyxWDzOGLut3W4Ty7Jiy7LQbDbJxYsX0Wq1EAQB34FvKn9ycvLBJEmeLxQKx5Mkua3dbhPP8+I0TRFFEel0Omi1WoNswZdluaiq6gNRFN0U/Wma3tbpdIjrunGSJCCEEEopwjCEbdvbbv80TW/rdruEMRbncjkUi0VSKpWQz+cBAL7vgzEGQsi28bn+vr1Jf6GBEAJK/+mIer1eDICVSqVitVp9QJKk/240GvTFF1/clC9tMPkjAA8B+GO1Wr01juOoD6X9n628AAVA0zRlQRDEjDEK4D8AHAbwOgB3q88fP35c+dWvfhU9+eSTD0mS9Me9e/fe2uv1IsuyEMcxNQyDLi8vk2azCdM0t43//e9//yFZlv94yy233Nrr9aL+JKNxHFNZlomiKMILXbEAKADKGGNxHN80/Y7joK+LyrJMstksuOt3XRee522r/Tk/SRKayWRIsVhEuVzGyMgIRkdHkc1mYds2giCghJBt46dpShVFIdlslu/0KBaL0HX9n+IppWmaUkIIM00zDsOQSpL0H7Va7XAYhq/3er11fGmTyf8KABLHcZIkidIXsubSdR2U0g1dIGOMMMakPiwCcDuA/wHwHoDL/bgw3Uj8008//RBj7JUkScjq6mriOI6iKAptt9uYm5vD0tISut0uCoUCCCE3nf/4448/BOCVJEnIyspK4jiOks1maRRFiKIIuVwOSZIgn8+j2+3Cdd1t1e+6rqLrOo2iCHEcI5/PQ5ZlHDhwALquwzAM9DeIHeMrioIDBw6gXC4jk8mgXq+DUgrLsrg32Hb9+/fvRz6fR5qm0HUdcRwjDEMEQQDTNInrupLneQRAVCqVbldV9X8sy3rPdd3LR44ckS9dupQOLgAJQJzNZh+O4/gVvkrSNJUYW++xCCEYGhoCpRS+739ZSCcBCAHk+6HU//WTazIY87300kvxT3/604ejKHrF933ieR48z5MURUGSJJifn8dnn30G13VBCEGlUrnp/GeeeebhMAxf8TxP8FVVFTsMYwz5fB6ZTAa+72N1dRW2bYMQsi36fd9fxy8UChgaGsLw8DCSJMHCwgJarRbCMNxR/tDQEBhjcBwHlFLkcjnEcSy8IiEE/blz0/nVahXDw8M87EEcxyCEwPd9BEEATdNQLpdBKYVpmpKiKOHw8HAewG2XL1/+v0uXLgk+GYiL7ieE/Hlgt6e4gYtSCkmSBpO0uL/yZwD8PwA+gHRycpLecccdLE3T+x3H+XO326WEEPRdKRzHgeM4+Nvf/obZ2dlt45umKfjcnfLFXy6XwRjDwsICisUiXNfF22+/DcMwtl55kjTooa5J/5V8AFhYWEClUkGxWIRpmrBtG59++inOnj27xgPcDPt/GZ9PvDiOEQQBZFnG/Pw8Zmdn4TgO0jSF67oiYd0OfpIkgp/JZNDpdOB5HsbHxzE2NgZJkrC4uIiVlRVUq9XY9335/fffn5mdnRV8qT/RUwC/AbC3vzqlgYwe1WoVjLF1Rr6aK5vNghCCNE1pfyc42DfGnwEod955J3v++efTr3/967+JomhvGIZJJpORwjCE53mQZRm+72N+fn7DisvN4t9zzz2/iaJobxAEiaqqUhiGSNMUo6OjGBsbA6UUnuchCAIsLS3h0qVLV8b/G3rKTCYDSuk16d+ITwiB53lI0xRpmoqxSJIEi4uLm3qA67H/1fK5Ph6eEEIwMjKCTCYD27aRpikURdk2PgDBj6IISZKInT+KIqiqilqthnK5DEmSqGVZoeu6BxljsW3bfz58+LAiAcDw8PADURRNpWma9FfpmkFUFGWNyCt3mgF3d2UsDFmWkcvlUCgU4HkeZYylAO4G8CsAzvnz5zE6OvpAFEVTtm0niqLIfGB930ez2cQXX3yB1dVVhGG4Lfx8Pv9AFEVTlmUlmUxG5ro1TYOqqshkMrAsSyzIlZUVLC4uCvtsdjHGQCmFpmnIZrMIgoBvNpvq34ofBIGY0GEYIpvNisnW6XTW2eB67H+t/Fwuh2w2iziO4fs+arUaxsbG4Hkems0mJEmCruvI5XLwfX9b+LquI01TeJ6HSqWCer2OIAjQ6/WQy+VQKpVQrVbhOA41DCONoujudrv9q2az6VAAbP/+/Sc1TduwPBXHMSzLEjvMlUZO01T8jg92tVpFsVgEpRSMMaiqinw+j3K5TPoToALgBACJEML27NlzMpfLMcYYJEmCoihi1//73/+Oubk5kWxuB39iYuJkNpsV/Ewm88+TnSCA67qi7k0pXTfZBr8PpRSKoqBQKIi4lXvRfD6PQqFAAKSEkC31b8Tvdrsi5/F9H4QQBEEA27ah67ooCd4M+18NHwA8z0On00GSJCgWiyiVShgZGcEtt9yCr33ta7j99ttRLBaRzWZRKBS2lZ/P51EqlVCr1VCtVjE+Pi5soKoqcrkc9u7dS0qlUqrreqVer58AINGjR48eHR4e/laapqz/hTZcBFu5ez4JCCGo1WpiEIaHh6GqqnDVSZKAr3AATwDA2bNnj+7atetblmWxKIokXtnp9Xrghy7cHW4H/8033zw6MjLyrV6vx6IokgZ3de6Fer0eACAMQ8RxvGHlabA4wPmVSgWKooiFGscxFEWR+993Q/1b8aMogiRJkGUZjDER+6qqClVVQSnF8PDwDdn/avl8gvJFJssyCoUCGo0Gcrkc9u3bh3vvvRdjY2PIZDJI03RH+KOjo0L/xMSE0M+jl0ajIVNKIcvyEwBAs9nsvf2Vlmy0w17N1U9akSQJVldXxe95rZYnY/17812gDOC/8vn8vUmSwHGchH9ZXmFptVqI4/hLv9ON8uM4huu6CZ9E/J6yLCOKIliWJSobvV5vsO6+5kqSZI132IifpumW+rfi8zyEbwaEEORyOQwPD4vybKvVuiH7Xy1/UGMulxOx+NLSkth1x8bGsG/fPlQqlcHPbBs/DEM0m00REmcyGaGfJ+x79uwh+/fvTwGUh4eH/0v2PO8+z/OILMsSX2F8MK91EfDPybIsYrBsNgtd11EqlUAI4TFhapqmCuA/Hce5xzRNoiiKFIbhmhLjFeW0beHbtn1Pr9cjiqJIURSJmjIPJ8IwXNNukKbpViVHvstvynddF4yx1HGcdfq/jN/fuZCmKXzfFwkmbwnIZDKI4/i67X89fL6z84TY8zwRwoZhiFqtBtu2hRfYSb5lWWv0c69x6NChdG5uTm02m/9JV1ZWHojjGKOjo7TfxyIMOzix+J+qqgoXtNEE5PVYXr9NkgS2bcN1XSRJIlZ4///GnU7nAdd1MTExQflk57Ht4MTbLr5hGGv4iqKImDqOY+RyOXHqGsexCHGuTIB5Mv5l/MGjewDr9G/E1zQNsiwjSRLs2rULxWJRbAo8+cxms+I7BUFw3fa/Fj6llB88idyNb2CapqFQKIh8iIcqO8m/Uj/3IkEQoFgsghASU0ppWqvVUCqVoOs6oigSA3llfM1X2VYlR34YwuNTWZYhSRI8z0MYhsjlchioND0ZRVFar9dRKpVQqVRg2/aGSfd28rn+arUqdnBFUYTL7fe5iFNIvjCv9EyqqiJNU/R6vS35jLEN9W/G556wWCwil8uJahi/f7/MiFKpJMKw67H/tfJ5IxqP1SuVCqIowsrKCsIwFIugVquJ3brfP7St/OXlZfBoYlA/ryLpui6rqgrXdZ+Ux8fHab1eRxzHWFpawvDwMEzTFLsFj5143GnbNhhj0DQNiqLAsiyxunmyyuMuSZLE5EmSBIqiwHEcqKrKv3hmbGwMIyMjiOMY8/PzqFQq+Pjjj5GmKVRVFYcd28VvNBqCv7S0hFqthl6vJyoHlmWJI37P8zA/P49utys8keM4IkzjcTYfmI34ruuKwU3TdI3+rfhBECAMQ5Hn7Nu3T5RkG40GPv/8c9GUxgee2+Vq7X+tfEVR0Gq1UK1WYVkWTNNEHMcoFovCS+u6jnK5jHw+L9pHdoLPO0QH9fNyKl9sYRhm5Ewmg2KxiLvvvhtBEGBhYQH5fF4MrG3baLfbYpD5DXVdF+Uoni+kaQp+v2w2C1mWhVh+r1arhfHxcRiGgSRJoKoqCoUCvvrVr8I0Tbz77rsolUqo1+uIomhH+BvpL5VKoJTCMAyEYYgwDOH7vmh90DRN8Lkn4JMsn89vyu90OhgbGxMHRZx/1113bcqPokj0ufBSYbVaFaVZzuXnFNybX4v+6+XzkCtNU1iWBVVVMTQ0JDYhvlH0ej0sLS3h8uXLGB0dRbfb3TZ+tVrdVP/q6ipuvfVW9Lt6IdfrdeFGJyYm0O12hdvgtdZcLocgCMTpG0+yBqshfIJqmoZSqQRZlmFZFjKZDJIkEV5FVVUYhsHvFY6OjmY4q9FoiFiOVzW2m99oNDI85xnUTykVdf9qtYqVlRXhBVRVFQOyrpdcUbbkK4qCbre7Rj8/P9iMX6lU1hwE1ut1WJYF13UhyzIymYwot3L9kiRdtf1vlD/oAXft2iUSbs7nYSMfn263y8PIbeGXy2Ux4TfT3+v1IElSSLPZbFAul1EsFqEoCnbv3o16vY49e/aIVex53pqqEK9pNxoNEZPznZln8PxL8SSEHxD1S3K8p+J/ZVkOeOLD69iVSmXH+NlsNiiVSuv0T0xMiGSXhw08xudH7bVabU1CPtiduhm/38e/Tj/fKTfja5qGfD4vNog4jrFv3z7RFTt4JnI99r8RPm+T4bYZ1M9PaPkhWb9cumP8zfT3K2L/K+dyuRc0TXsqjuO4Xq/LSZKAMYazZ8/i448/XhNa8LIUH+TB3hwO5KECd208bBlsWeXhA2NM1nX9BQBPAYiHhoZkngyfO3cOH3300bbzs9nsC5TSpwCs03/u3DmRPBaLRUxMTIhTSd4JeeWBXBRFwjNsxI+iCJqm8R14nX5e476SXy6XUavVEIahmOSWZYn7810/CAL4vi9CwWu1/7XyeW+OpmmIogj9Lk5kMhmUSiURatRqNRQKhTX9QdvN38z+mUyGLySZSpLU5e6GHyXzuIpPPn4KF4ahKE9xt7ZRi4Su69A0DY1GAwCwa9cuZLNZdDod3hdDGWNB/3G5Lv9csVhEtVoV9dqd4BNCuryMWSwW1+gfDC+4F+JlNr4LbdQguBVf13Vks1naf4Z2jf58Po/h4eEt+aqqivyMh2G8UMDtdb32vx6+7/uIogi+74tdeJBPCMHo6ChKpRJs20Y2m91R/pX6+wuTuq4bBEHwBi0UCs95nteilMqe57FCoQBN01CpVMThweADMJqmgVIqqhmD9XdCCPbv349GoyGSmFqtJqo3siyjWCwyx3EoY6zbf0rouTRNWwD+JXxFUZ4D0FIUZUM+j0/5wsxms5AkCb7vizxpkL9v374t+YVCgdm2vUY/gBYAOY5jxp924nzu8oeGhtZ0dxqGIXYynnvouo7bb7/9mu1/I3zelqEoCrLZLA4ePCgmPOcTQuA4DjKZDCqVCnMch/Yn/o7wB/WXy2XW7XZpu93uuq77uvyDH/yg9bOf/exUEATT3W43VlVVGRkZwZ133ilaEfjqLJfLmJubQzabBaUUo6OjoubteR4opThw4AAkSYLruuLkbnV1FY7jIJfLwXXdOAxDBcDz/YnTYoydYoxNt1qtuNvtCv7KysqO8H3fF3xN09bo5yFRLpdDuVzGhx9+iEKhgDAMRTLGG7Qopbjtttu25DuOE0dRtE4/gOlWqxXruq7UajXccccda/iFQgGVSgX/+Mc/RJLdaDTEYVMQBNizZw8OHDiAJEmu2f43wh/Uf/DgQVG/588kmKYp+GEYxlEUKYyxHeEP6s9mswjDMO50Osry8vLz/ECCWJZ1yvf9p1ZWVoqUUlYoFIjruhgaGkIul0O73UapVMKlS5fE6VwQBNB1HYcOHcLly5fR6XRELDY2Noa5uTkEQYAgCETyYZomC8OQhmFoADg18GTQqW63+1Sn0yk2m022tLREHMfZMb7v+6csy3qq0+kU0zRlxWJxHb9QKOCDDz6A53nQNA2O42zI13UdjUZjS36apuv093q9pwzDKLbbbVYoFDbUPzc3B9/3MTIyAs/zoOs67rrrLszOziIIArTbbei6juHh4Wu2//Xyr9b+xWIRQRCwIAj+JXxJktDpdBillF64cMFwHOcUgIQeP35c/vnPf264rntK0zQpSZKw2Wyi1Wqh0+mIujI/1MnlckjTVLS4MsZQq9Wwe/duHDhwYE2Zi8dkYRjCdV2EYRgGQSD1V7wBQPnLX/4iE0IMx3FOjY2NSYqihK1WC4ZhwDCMHeGXy2XDdd1T9XpdStM0bDabaLfb6/RTSkVj12Z8VVW35IdhuKF+27ZP1et1KUmScGlpCYZhrOHzcl+5XEYcx+v4ExMTuOOOO6DrujgQuhb73yh/K/v7vs9foxK6rivFcbyjfP72jEwmE87OzkoffPDBKdM0jcOHDyvS2bNn2eTkpMQYO8MYO0QIOdhqtaJOpyPpug7HcUR/EH8OuF6vY3x8XLga3rtRq9WQJImo1yZJItoSFEWJGGMZ0zRn4jh+ut8RmLz44ovpnXfeKe3du/eMaZqHCCEHP/roo+iLL76Q+MnlTvBLpdKZIAgOZbPZg4uLi5FhGBLf6WVZFg+WtNttSJKEkZER8ZTSZvzBtgxFUaI0TTO2bc+kabqOf8stt5yxbftQLpc7uLCwsCF/I/284sUHu9PpiOrUtei/Xv5W+qMoEg/tW5YVff7555nZ2dmZKIqenpycTC9cuLCtfG7/fm9QBCDz+uuvz3z44YdPT05Opm+88UYiA2CnT59OATiTk5PHoij6vaIoD8dxHCmKovD6bD6fh+d5oveClwbz+Tw0TRMHDzw55N2A/cpJxBhT2u32TBAExwZcH+uXw1JCiPPyyy8f0zTt93v37n34k08+iWRZVngVYKf4jUbj95VK5eF2ux3pui70Z7NZcR7Ay62FQmFLPn9Mrz/5lG63OxNF0Zb8gwcP/r5arT7c6XTW8LfSTykVO3+32xXVkevRfz38rfRHUYQ0TaNer6d8+umnM47jHAOQnD59ekf4XH+xWFRee+21mTfeeGMNn7fmsampKXr69Gn23e9+95iqqjOVSkXp9XpJq9VivEGNN4Txhyt45WOwOcyyLAFutVqs1+sFnucptm3P9Hq9Y1NTU2zgTWG8gsKmpqbo+fPn2SOPPHKsUqnMHDx4ULFtO2m32zvCZ4zR8+fPs/vvv/8YIWRmfHxc6fV6yerqKrNte7CKIA5YeGfn1fL7g78l/ytf+coxADPj4+OKaZqCP6ifP5TD9QdBICabaZo3pP9q+Fdr/9XVVWYYRrC8vKxcvHhx5tKlSzvOtywryGQyysrKysz9999/jDHGpqamBF/0pk5PT6cA8Nhjj7E//OEPj8Zx/Gq1WpVUVSXtdjvq9XqMv3aCn/D1e9vFwxC8DdfzPGYYRizLMimXy+rq6urM7OzssampKTY9PY0r3wkzyCeEsFar9aiiKK/u3r17x/iEkBQATp48yd58881HgyB4dffu3VIulxN8bmgej/IW2834kiSRUqmkdrvdmfn5eT74m/JPnjyJkydPsldfffVR13VfHR8fF3zTNIV+Xu8f5Pu+L0rDvu9fl/6r5W9l/35PPut0OrGqqkTTNPXcuXMzv/3tb3ecr2kaGR0dVT/55JOZ733ve8fOnz/PCCFirm306pO0vzLS99577ygh5Gi9Xu8MDw8rSZIQ27aRJEksy3IiSRJ/0JtPiiSO43hhYQGWZREAcpIknVarNd3pdB4FkGwmfnARMMbY9PR0+stf/vIoY+zo6OhoZ2hoaMf4J0+eZADSRx999Cgh5Oj4+HhnYmJCoZSS/gFYnMvlEt6vtBG/1+uRNE3lOI47nU5n2jCMq+L3JwEDkD744INHCSFHd+/eLfiO4yCO41iSJKHf931+Gpr4vn9D+q+Hz/VLkpTEcRw3m014nkfy+bwMoPPuu+9O/+53v/uX8Akhnffff3/6xz/+8aMDL3pOr+bluPzf2Le//e1qHMcnKKU/ZIyNUEqJbdtQVRWapokeGtd14TgOlpaWmKIoy0mSvPDXv/71WQCdwftdy0Nm/0o+Y4wQQtjrr79ejeP4hCzLPwyCYMQ0TfL222/j0qVLSJJEVIg24l+4cOGm8DVNOyHL8g/TNB3RdZ30ej2x8/Xf9oAPP/wQ77//Pj7++GNGCLmp+rfil0olKIoCxhg8z8PFixeZqqrLjLEXzp49++z09PS/NZ9c7Suqn3jiibxpmkeSJPnG6uqqLEnSCVmW1X5mHnied8o0zdgwjHds237rwoULNgAcOXJEfuutt5JrnPz/FvyXX35ZeuyxxxIAWF5ezi8uLh6xLOsbr732mvzZZ5+dsCxL7XceBp7nnep2u7FhGO8sLi6+tbq6ag+8HvyG+Yyx/Nzc3BFFUb5x8eJFmRByQpIktVQqYXV1NTh37typM2fOxAsLC++02+2brn8z/qD9kySJW63WO4ZhvPXYY4/ZA68n/7fl/38JEtrC+pPM6QAAAABJRU5ErkJggg==","neptune":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAAAgCAYAAABEmHeFAAAZ8klEQVR42s2ca6xlZ3mYn++y1tp7n8vMeGwMMaSiFpKhqhA1qmIXGCM5VQAZS5Gm/dEfVYtiaIqRItq0RKqMG3qR+FNloBZUkVCSP2R+QWuCkIsyCk3jBopt7MF3e67nzJlz2efsy1rf9e2Pbx3PweASJO+dbGnrzDlzznr2+67ve+/fUrzxywDpyPf3QXMXjO4GOQUhg9UQAAG8A74MaQJ8Cdju/84CkV/wdfr0H5uzZ//Ra/xP/M4X7lNq9a5py92SOTWZ7OeDfae3d69xbWuT8asvO5lufBnGC+E/8DtfuC+r1bumM+5G6VP7+7v51Qub+rkn/y95+0XgwIEsTP5D/mQmd89m81NPPvnDfOmpH2u6y4BfuP5//YHP3re11951/qkX797f3jmVZtczndMw75eJX4r805a7EXWqbWc5JqMlBSCRonN1M/pydzCZ+Nnel879j69uA5w69ZA9d+7hN+Srn7P4K7CfRZ38IKr6CDJQSNX/WewXvvQ3wPV/4oD5JqTfB/4UeAzQR375FxG++mf/6t99Vq3e9kGlq4/Amuq6xGQ6ZW9vlyuXr3L1whW6rSsw34E8AyY9Py6Av6q8h857DsZjfvzjZ7n45NNwcAWY9jpZrPzeZyazGVcuX+bpJ56iffklSHtAt1D9h8RH9sdJ7ewcsDMes721xXhjk7i9A24XmFGM4YLkN9VHkDXlveBDQHJGciYGIWdf2GJIwdPNdjZVSr/fzmd/+r1v/pfHeOghzcMP/0z+z9oAVbla86tUa7+NrNxLGvUbuY6opBGly6Vyr/RDxacIXsHclBviMvC7wBf61fF6r/JTrwce+Er11a9+MvzLz/2HX+XYLb+tzPq9k9bgukDONh5MJvr61nV98eJFti9eQXa2wE8plihGCApmbzrfuwg0MeWoY0x6a/MaT/zwKaYvPAtufLgAFyb/IT/mqCWLPtjb5+nzz3L16adgfK1fgAvUv4sgVXTeae+Dnk9mbGxtc/XKJQ4uX4KdqyCzCN2C9Z+0UkqTIaVMloSkhKQO73IMySuVnKmUYn6wlWMIv6vH3//CuXPn4unTp83Zs2fT6y39kdedFWwERrd9FEbfIp+4HdYC1EClUZVGtEIsKNNvH9VvDg2IBq3BCOgIQUP+MHAn8O1+lao3FP4rX6m++vAnw2f+43/7aB6tf6vNx2+fzVQIUeMC+mDa6itXNtSLL7zC+OIV2NuF4PorHvLVm8ufqxCjIUml0ZVWaOWDcH1nl41LF8k7e71dWZD8P4MvWLSxhODZ3tlHDtpDA6vBaNBvOj+L1aIqbUylrBkwHK2wvr7KaLgG1Yh5UMjMacga1Jsvf7/+tNIqi0UZg1KQk0KJJYtBIVqJ1lmQ4GOULFrVow9H1u687eQvf/s73zn7U3zzk4v/B4H65o+Sht+EEwpswjYVrGpsBaYCPQBdg6nBDCDb3mmY/toaEAViQKniTdIdwG8Afw5c7HdM/qmd//Anwyf//Zc+ms3qN2d+RXUuJ2WbKsZGT7uOK1c3eenlS7SbW9A6yAayooRlbz6/dTnZalAJK9pUFdpaUA0+ZLZ29tjeuI7st2XdLYFvbAVmgDENph4gYtgZT3HjOcRDw7Yofo2xFarn23pA06zQNKusrh7HDEfMkxCnAXJQ5ea8iXxbHeHXGFtj7ADJFlSF1gZ1qH8RlURMzijvfVDa3KGq+jfecuvtf75x6emLp06dshcuXMhHN4CBjcjoxMfww28i6wozArtqaFagGkE9gmYFzBCsBdOAroosugax/eXskU2mgGQgeZBV4F3AH/RuUB2N+f7wD/9p/Bdf+OLHsj72zakfqig1Vb1qdDWk7TIb17a5cPEKs2tjcK7wtF0gv6FqVo1tVrDVCFuPqOoRSjd0XceVjW3G166DD6Cq5fCbFbQZYq1F6wbBMp23jA+m0IZ+SVWL51dlISpTUdU1zWiV0coaqhkwjYo48ZAPc8Q3n2+sRZsGpSu0seiqLmtBGYyxKBRagYgi52w6570osyqkd228//Y/uPCtb73GN/1bGNz8AfzgT9AnNc06rBzTVA3YYXlXg/7fFegGqgZUXTy+rYskcpj0c8Qi0ishRuCdvTv8xmEsePqP/9i8h2fk73/0H38gqmN/MgtrOtsRg5Xj2lqLD7C5tccrr1xm99ouOF8Ytl4of7h6XNdVg7FDjB1iqwHaDBCl2T9oubJxjen2GEJaHt8OixfQNcY2oCzzecv2wYQ0nUKUn7RpC+Ir3WCqBq1rUJqqHlBVltFwhG4G7HeRNHFHNkE2EN5Uvq4atKpRSmN6/SsFoiwIKGMQUcUoCCaGeZRs33nTtr9T33TrN2YfujNx/jym95mZPPwjqre8k+ZYolk1xQOslYVuLFR1+WoNaFPCIWv6/1Ng+p+nko3/ZKgllNgweuDdfUL0XaD6O6dPy3/99KfzHf/gH/5RHrz1ncIwDZpVo8yQmBvG431effUCm5vXyG1bLqsWzB+sGWWGGLuGrRqssZiqRhtDJLOzt8eVK5u0kwmILI1vev1rbfqFYHA+sLe/QzubQJbl8U2FtgatbbkV1lA3DY3VUFWM5w6ZzkFCH+28uXx7yDcWUymMMRhtyCmANihRZUMcyp+VTsF5Y6p3Gx/jzv88+90773ygUoDCDj5IvvUcK7cmhscNdgTBQLPeL3YFqiluJocSYmYpRkVy8XA5FqXP5kXOOAHxIPt9iXAKjAVyBg6A24E9QP3zh/7TB2nefi7rY6kaHjNihoRWmM0TL730Ms+9+Dzz3SnEvBS+siNyMFTNOkYblFFk1aDQzGf7PP/8Szz5wyeYXL5SkvAl8XWv/ywKUsY7z8a1TZ744V9y+dkfw3QK09nC+dLrP8VIkkyODsml1D47mLC3s81zzz3JhSeeQq49D+wslC/J93xFN5uTokfChOg93cE+3XxKcFO6g11p22kOs50D2+3d/qMfPbpX6rNp8HlWjgkrq311x8BwtSx8o0GaEmdbDWpYEmBdQ7Pa5wIjMKPignMsuYFq+rh41MelFTBQvTk4ATx4GH5lqT7frKzLYLSCQgOaqCqubW9xYeMq870Oklosf9Tze/ntcLUo3mi8NChVoa3GxYrWJXyg5EXL4usaYzWihmhTo0yDHa4xXFlnZfUkanCs6GgJfGXq8n2zijIN2qyg7QopFr+zduwEt932TtZvewcM3gIMKZXExfCVHqHMiBQFSRGlK7JqyGKxzYiqrqiqCjtYUUbX2VbDE05VD8Jpo4GPYwf3QCO4ZAh9/0v3sb5ZhUENVt3YBGYATdOHcYcxuC5hUjMqLscMiveAXvhDJajDIPk3Af7Jv/63H9fN2j2uEwk+mhQSOSom0xlXN3cY73UoLUVVuoZqQXwnEnwyEhKaCqVLrKnMKsNBjbYKpWqQhA9CVoDEpfGNVShdY61GmwG6rhESta1LFaaui06aUalCLprfNGQSmhKDKzS2bqgHI2xVceLkrdz2jl/G3HQzqLXl8KuaanBDft3Lr6oa7JCqrrDGWKUtKarfhLNYqO5Cj0DViXpFM1gpIUZD2QShjyd1X+u3qsiQYil3J188hvSKThFcH6vnw6TQHHnr4r/hOPBrVbV6Vz04TheqZOsVrasR02nH/v51xgd75Lnry+tV4ZvF8at6RZte/qaXP/bya22IWYhZ45OQky4bUstS+EpbBI2yCqUsKUaszdR1zcrqKvVwndhMwHXL4aeIMULu9Z8FDDU5BpSbMxwOueWWW7j+9ndwfWcT3KTX0+L4ihrd61/rvtSkLUoZlC5v09RK5iqjB8f/9h0f/zWLGtyNrhWqNqgafCzJpXNQaYbHLMpU5CzElIhBSrqtBKrqRndZ1UX51RBWNLg5hApy71Fo+3zb0CugAe41df33QhCldWOgxneOg4N9Ll+6yMHuFqOVXARcBl/VJB/R1hCco640J49ZlLGkDF0XSHGG93OEWCpi0nfYF8q/of/ifRTGCErVVMMhK6sjRmvrzDc3b/D9gvm9/tMR/UfXYeohQ6UJ3Yz1Yyf4pbe/g/HVy4TL149swgXyqyHDFU1wc1JVgSRsqgiqJUvZPAJZG9OENtxrQT5Uwh3RdLt9MqeLlW0avF+DwduQ4TEkqZJ0ZgUqFeVW0k8NpWKpPWCldMF1VcIEMa9rlr32illVH5IkGCM6dTt0symbFy5w9cXzhJ1tsmmgeevi+VZ07naRHAlovLL4piH6NezgbVTNOq0ztC7RdQFJAcSVyyZZKL8avA07PEZKiiwZyQqlEkYiTaNoBhXrK4a9gSV5VTblEvg6J1QlpASDKhFF47wCIwSEZjjk5M23sP7WW9nZPA5xdwn8G/rXpkJMLNbfVijTR19Kg4UkOVpEZ7LRuL1yA7MpiV0CTE2KfWfdd33XVUC3KGokeci+JFuxLQvBO8gOdC6L9EaBvL8B8Wix/DOz1ufBmtXZ7ZFz5mA8Zfv6Lu32AThNqhUMF8+XXv7cyy8JlKnJUWOV4ENH9A7vpuD3UJKWxjdaCL5Devkr3ZKpicmTQgtkQmrJuQXfQuqWxpfsSWLxsUUlIXiHZIfWGWtgMBhw8uRJdlbXYXyYty2er3RGq1RaIyIYBVoZckoobW3ykfls+hkLRlObEruGBIMVGJ5A2wG5qlGVBm0RH4rT8hq8IGoK0ZUdLaGETrkPPDvXu95YSnHYw1r06+eharKirg0pBHwXySkhWWFWVsl17JPvxfFVz88xEkJiOFihGp5A2QG2qqkrjTGWrvNo1RE7x2zukW4CYdZPHSyYry3OB+oGktc4L6CmhOiQmLEqYJRFsga1PH7s9a8kEI/IHzpHygkkYDUcO3ETg/V1urFBYUr4uBR+hORRxiIi5Fy8gTGanCBnqS0kUB4Gq1ANGL79HYxOrBNCZrLbIakptWWryxGASLF4OZaSbupHo5Pva/OuKDp5iKEfkT2cGZfXj4CUG4anHqwQkuL4zeu8ZTZn5mbsbBxAapAF8qXnV4NVTDXgl97+DtZPrONDZme3I6SG2XSGMQrvZ7huj+hnSOhKX2JJ/MpqYsjkCEksKkckZ0LMKBEGlYAK0HuEZfFjUmgiKnlSFlJ0qJ4fXESTaKwwXFul04Ofuv2L5ZdQNfg55FQaYzmRJYFWSM5YVILWw1oF9Yhufwc33SPnBlRfUlKmfPDYN58OpcgdRF0soETwUoaysod0OB/vj8zJt68fyfaVVrVrHcOV42ij2bzyAi++8Bx7G/uQqiXxPaO1iqoesb+/w/50j5gblBqhEBSGnEFCJLiOFLqy+ZbBV4JSha+jIL38AuTUopJGScQaUDkhUZbHzx0qalIvf/JCjqnM56cpSiJCoLGawbABrUsYsyx+jmTxqBSJwZXQkEz2nhwDWmuvUeJKzchBaBEHuWvK+EjO/cJLYHxJ3oVyw3NfnjS9Zcm9dZG2DIjlPmElHDkoEQ/d76EP/D2tkrO2IiVH203YGbdMDhREtUS+JSVHCC1zB10vv+RMlmI1rCoWzXWeHLuizLwEfi+/NR5J5fMoCaTs0GKwJmGMxhqLNaqcSwh+KXwlGmMSCkGOyB99ICaFpEQMAclC0+gyvrJEfk6ZGAI+BHJyxBBRypFziJKFqra/p8n5EYKHGCJaSh5ApL/zfWJMiSvdtMyahADeQ5qXpMunsoFSvyiJRw7LhCNWKLx+BNyKlkeUVqQYIjnSzds+oUy9QIvmq9f4WhcLoonkXn6REi+6ztG1B4TQkl1X+LIcfsrgu5KASwrEEMjOQ54T/JwUBaMzSuW+4pOWw09zvG8JPpGT60ciNErF3nhkVA4oFakaC1XfS1LL4idUCiCeTERyxLuE5ISSAMlZC3lcXKaUd9NbDskg05IftBFUV+Jw31cTYgQTiqUWBUmXxEt8sYJl1b7uRryW/OjeJD1mkfcrCeRkyCljqxKblfi+XR4/W0iCbRTSyy8yJStPaCNaZuQ0wc33SO0E1U4Q3NL40ssfPGQMOUW0DuQAKvlSIs6p90xtya1kCfyoEFHErJFcKmMSWlTOqNSWql0WjFAs9Y3TQ0vg9yFPSogPpOjJ0eHcTKcwdxh5zIL/MtJ+GuluJtdCl1Q59DIvHz5NynCVZJjnGxtFMkgqZwMq25/Jpne76Yi7PbSGh2+kV8AY+PZNJjy+2+5/msbcHGMnvp2q5FsI+/0NXTTfPb7r9j9NXd0c01x0l5ToAVbPCb38KXpCjLQHO4TpNhxcQybjMpi3JH6WTJxnJAk5CSKZlBKDymJzJHfXkbBbjmdKuxx+7vnW4uYOpSDF8rlIkRgSOZViRU4ZkdA3TZbEj4kUI5IyMSZC8MQYJcesc/Tja1f+z7dNKRHUQ6g+jDKRlAwxQjsrnc3kwPWHLYIrm0LUDYXmUKyOuN7izfuvh0nX4c8PrdFrZ0O/CPzZ/z53bvbeD907rAdrH55MZnFzY8Psb2zAeBe6djn8U/cOm8H6h32USEomxUhqZ0TXkZMj+UBMmdn+Pptbm0w2t0tfQuJy+C6QMmTvACnWnozETEie+XTG9vVrbL36KjLb7M8HL4cfc8B1HdE5fNfhuzkxdEhy+NCSQ0foOvbGu+xtvAhxa3l815KD6/+vxbsJrjuIcT430U2/OJ38yp/pUkgfnyFN9vAHGj8V2nG5qSGUAyiS+5hc96fcDg/U5L4Oz5ESW+qVPetHYGf9Ox61PnvAmcMLjUbXz/jZ9T1JrY5hJriD4saXxR/4M35+fY841b6bSGzHxNSRXCD6wpeY0EpjVOlCq9d4C+Y7X252KnxN3wXt5VeiUGi01WileoRbCl/1XXkRQBerrFJCQoebz0huinczOneAb/chuuXy/ZTgZ3h/QAwTog8SXdRuNt5rZ5fPwNmk+y7JHjI5Q5wa4tgjsxJ/a9d3E0PfUOm7jDIHmfQWpj1i9WL//az/2vVfX2u8+H73n+mVUD3wwAP2kc/95z385Mz6sDbkzqNCqacvhf8V+8jnPreX/eTMsNbGdQc+hRkptGjrUJJIMRBjIMYW77oyZ5MnR66/QL4q/BR84YeO4Oe0swkptETXEts5Oke05sjiXzw/xsIP8znRd5AjWbWkNCe6Ft+1dO0Y3+7jZvsQdnq+Wjy/a/FdR9eOCW6CxJbsZz6HuZE0O7O/f3GPO++sTG8VDKTHQd4L5t2vPWRF8pFWurrxq6+dNz1a8Qi9sg+rDv71NefQz8M+CvzWobn8wQ++nzl93vzdtebx6NN7Qzbvvn51I+TZ1JDDkcfJLIj//f+eT58/b8xq/XiKvLduVt+dgguSlSkxJIiU60znc65t7TLful5KjfRnvhfIzz1faUVKAlJq4kqpUiFJgZQiezt7XL/0CtJtgZotnK8P+YcNKR+IXUuMgdB1uHZKdI7QtUz2x1y79FJI3aUaZDl8NyV5R+g6/HxK105D6HzdHVx7VEL3W7PZhzIbj6Wjp6f71TX8BtQfgypAUxWdaWBwY/Ep28/C5yOWr+uVPj+SgMlR5Ve98u8/EsPIUf7p06fNFW75xrMvXPzY7o+eDqRU3XjkynL49m+9/xumWftYO+0CuamwDcZqcq6ZTKc8ff48V55+Fvau95ddDl8YoI2hP8JHyuU0XHIt83bOq6++wrN/8RfI5BlQ01IgWCA/51gSUdcRUySFjuA8wc0RCaVr3s7x8ymbV6+FrZf/siLvPQqn74ezC+Xn7Ilxjpu3xG6O810Inau66eTRX3nvifv7ZwOp/jkyHI0NBdr7YfIodBW0qbRf5UYJTamy+NTRwxZHLbQceWrcawHpUeUfYR09tPqQPnv2rNzG9ftHFY+aY8erUmBfDv+hhx7S73nPeyRe+Df3+8nOo01tK2ybtAqiEZSOVLVhOKihllL9WSJf64gxYIxCmUhty3NxqGp0FlIMSPZ972Tx/MoatAJV15gyqV/6EAq8dyTviH4uB/N9t7f1akXe7/lnF84P0ZOcI4ZWfJy5nFwVuvGjl55/7P6zZ3+Sb153crr3CPJ1CO+DfEc/exzKDGlSNxoq+cicST5iAQN9WzQdeU7IUeXz0wNBAOcEUOfPn+fgXc9/vZ7c/L40m9yB+D7OWCz/3Llzcs8996hbbrmHZx7/7tdXbr31fYrqjphFITkohQ7Rqb3xDjvXrsLB5PAxgAvnS8/PEpXkQM7l0YApelKY44Nna2OD8ZVXIW33MyNL4vsZWYQQulJmDA7XTSW4WWoPDszO5oadX3/5UXBL5M/Ed7PUTg9M8sG62fTRV89/92fy1Rs8L/SwxHIfmK9BfdONwxQmllNFcjigc/hw1NTXeO2Ra+32Cdfho/H0z178b8A3w/tI4WtQLY0vIkp9/vOKhx/Ov/7gw/ehzNfq4eim+TQSY8crF67E5594SqXNC+ZGzJ8BtzB+0/O1BREbFagsYkiCd5GDyYRnnzmfds4/LsjVJfIh+oiPkeh9Cs5JaFvrwgEptMx2x7tXXnrujJu9sny+b+kmk91ub3zm0iv/6w356ucsRAFu6g8wfwrUrX0R/v8rA3ANeKR/SvDu6673V339jeCf/sQnbgrNyQej51Mxcev17V319Pd/iNt4pvcAsnB+ak4+6DyfAnOrMZWKMeO6jpQy0Sd2drZ48fyzhOs/OrT+S+A7UkqkJOTogBrnWoLfFzedXcteHplv+S9dvvydvxY+Xh6Z/hX4P28xHR0eXwVOAR/ordyD/bG2w9rbmX6XfQ841xehDw8/pF9Q+L8R/KMPUz11+vRqZU6cGs+mH3jm8e/bduuFB8vjMpbIr0+cMsZ8oJ0GO59NHwwhNm3bsbW55caXnz1DOIhgvgdpafwQIkpwtrZnclRRS/xe2Nk9d/78uZ5/ysK5vzb+qVOn7Llzb8z/f7Ps4XCRgsBQAAAAAElFTkSuQmCC","saturn":"data:image/png;base64,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","sun":"data:image/png;base64,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","terrestrial":"data:image/png;base64,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","uranus":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAAAgCAYAAABEmHeFAAAYn0lEQVR42s2ca6xc13WYv733OWdm7ov3kpJIUXZTxZGjGG2BQkEBEVKoAApim5X1i3KLAs6PokpgQIEBF86/UmwUND+KIAglC27rwgjaABYBA3LKxigE1Eyd1G0q1XpR0YMUeUnde+feec95n/3oj72HHNO2UgOaiQcYzNxzZ/Y3e++111p7rbWP4Cc+XlDwhLn5p/qdxzA8iJqeIFYnaVUWayWRgbaA1FU4nqOjpxxcehZe7vkvnozgouanfJx+wanzT4ib/KP/JnvMyfaDpuqdkElyUpueTdNUNpMDSIfw9o2K9288B6Mp3dcWylet5GRdH9jRjRuSv/4B7FyD/bTC2IX3XxcHJwqrTxbv/JXltdck/R2QGlK70PFPfmf3sfpg+iBv/cUJJuOTlF1LmkpMAbGDzFbYJc1/KzkpxdhinVSRodNRFCmVQD3Xjsw0P/P6s7vp5zz/jIs4K34iX3y48D8Qs/XPvkw5fZiV5jPoTFBOIS5BzdpUoC1kDtqr4Aqohnuw9XXQ34UXXoIzEs46wP1UnX/SxT//D/hymvJwZ636jMWKyfgAU/Uop3307h7s7MHeAVydQEtBM4ZysBC+wYp82ke6CVk6pHjnHbj0Fuzsw6iG9spC++/5PXQ9YLq3jXv9Dbh6DUYppHahfJUUn5lMeiL74H3I9mDYhe4BjEYwTqFfQacDdtH976OYopTxrQlFYyzFAax87DBiXKEv7+0l0T1fV53iuzvP/+JLnDkjOfu0A+H+5gXwwNdiXv7Nhrv/8Neg9RWMehR3AGoAdqwZppKmkgjtv22Fb0YAzmj/R6ygjZ8V/buQP+O1wGkF582Hdf6Br7n45d8Uzf3Pu1+jzVe05FGdg9ADqmao9651pd3Zllx+H/Z2YDiEqgRrgeaj5yse1RkIPcS6sR7sp7KoplLf2IE3Xof33oMiByxgFsu3Yz04SGVV57Lu9+Hdt+GNSzAcAAacXiB/QGNG+mB3LKtiIhmNYdCHnV24sguTIdhUe4GIFtf/XiqNrqRoNEKCReAKgTDgUqOJECpqq0gcQbl9G33gfvf+C+kzF/lVzWmnOC/MT14AM+G/59nPckj+KQaJSRvMVNKMFJMapinIFEw1E3pAhgaa8F46sNoPREdCeQHMF+C/DQLzx2qCB/6Pi1/+ZdH8vX/vPrt6hD+tNVJnNE1TyrI8UN0P+hRvvwtX3oAr70M+9Rrn5mMxfK0rqfVITSYV00lKXfTRb78Dr7wKu1cD1y2cP51WTMYpwk4pRxPM1evwP16B9AaIEtwi+UM1mdRMxynYCToracoKd60H1/bg/WtQ3wBRgLPOK4P4I+5/zXSSIlyKLSqEBTc2oCUUwLABIcEI52Kr5XqiWnfcLdW13oXWPcMv3Pj6pwfgxLwlkD8i/D/3h5/lqPw26zVs5ZpNG9MSCp34n54IsMqDbq4hG947r4moBegYMul/lTkFrXfh9EP+QyejH7vyf1k0v/of3WeP3sO32y3YaqMPHXJxHFk1GFQU29cRV9+BKzcgHQNVYC6Qv+nidlsqYxLv8CVgCgdpDjoH9BL5grgtsTpCRgkcWYfVQ0A8J1eL4rcQge9MglIRrUMd1KG74BP3ws//IqiPg1vFC5n56PvvIG4JbKPASUhCV7FekmMHkQHRCJGZ2A2nskyvNNVxe6o6fPzdu3//jYdAOE7+95t8ddPn3/0NzT/6g1McbX2bqBYc0dBBUQk/64fwjUdAbPxANzo0YW8TgvmFUSloapBrUN4HD/wx/Fczb31Ov+DUS78h9K//F3dq9WN821rE4UPQ6aDyXJCXDZPxNaqrb0P3A9BjcDXoxfGPHIL2CqqqBEopNjYkSlkiZSmaEbq7DZdv+KbRc9zF8aPIEEcQtzQuNtRZA+Mcej2wMzdsCfy2wUUGkxukTCCR2GMdEDFkDdSzMTFA+ZHyo8AnMug8zL+wsGF9i7HzC0MI0A6yShnKmk5rzWXFff/4y//hjy/923uNX6RnUZx+QXH6Tcfm5x/iztafMagkHQ0dIbHApoRIQibCArB4h8tApcE5kMKvyJtCONNGM8GwCkoN7l6oHoD7XoQrBuC0c+pT53H3ffXphw4d488O9pDtBDodpDbQbmm63T12X72M6G5DlYJtwOmF8lc6SGdhaxNUBFkmUcq7OePxgOb6Fdjd8ZO9JH4UQRRZP+HCUFY1Nk+hHEKaBhdo8XwhDE4a6lrjhCPaVNBKsFsJqBjyBooCyMMicAqKj5YvbvHFIQFSQmu2CIRfCEZD7RA4Zd1Yiya59/rutQd+4Yl/+mJ38xXDpReCC3T2rKXV/B6lixDaciT4N1sCWvgIz0oCtg3TBPoJjBKwwZI44d3Om4t6ponUnCYSERQ12FNQf8WPzAMR5+HsWWGt4/dsTpRY7OEjSCysrzomaZ+rl97Hjft+TzWKFs4/csSPy9YWtFqQZbC6InGuxXAckV/X8G4DU+b4LJxvbYvpNKHfTxjvJNhx20feohXvbosl8XsJ4w8S7DBGWIGrBXFHkty5Cncfh+N/Fzp3AWvByzYL4kd+718JROJgTQSjZyFysKJgRUBhQMmomfZrm66e6r4ZfYXzTxiefDnyIZwvPPswrfgio9SIDZST+E3FeljEBTABtiuYTmEw9W5Ik4MtfV9E0Dhu3ie/aQbDhAjn1Vd7AvIT8L0hzokvvs/D7VUuDnYxa+soISGdgjYpP/jBO7z+g7fhSh+upDCZLJa/gZLSK7CNdchy/34yhmvblt1uj93vvwJ/8efQfR/MdCn86QSubTum05xBf0ozHVH2p1Tb1+HtV+D6O+BGYE1guYXxh/0pTTpGj3JsUeJaBhFZUJrmA03TG8KVy3DjTXA7QXjsYvh5CW2DiB1EGrfroAmWwGlIDZgSDjvIcFIktqXak9W1lU9s/8nDQwk4rH6ajnMccagtiA+D2AyLdwXvUzUOViPv58nYv3bErW20m7kBP04TJrPthvDxSrMF5VNwWiGEo+HpVhu3eRg2D/uV325r9rt79AY3EPnIK48VtXD+1hYcOexNr5CwsgJJAk0DKysSq4Fag7TQcTd3UYvm1w2srgqEiJFRjOwkrNyjEB9vweYKyGRJ/AQRxYh2TPtugbgLREuAkjghiY5K1L2H4Pg90D4WBKiN3zwugH8UaIGTAoeEO4E7hO92bUE5cAkMFRRC2EljrYy36mb6FKdfUJJ/8rXP0UkeweUuWRdqdS0okZnlyoEsRPgyCSbxLqWMIY/BxqFz8yZXhAZuv27wfosG5BcB/sVb7nPJOo+YAndoHbXe8W71dDrm+o0duts93LCG2i2ev4FaXwFjvUtpDOQ55JlfAGkKZSkgrREGyJUPdiyLn4ExEVYrpIooRjHUHZDr4CL/vCn8i+Irz5cxxSjG5THUyhsZFMSSeCNC3LUFx34O4jvCIlgkP4LS+a1GJLzbk0g/Hir0vxRQG5A60oMpjbVfPH36NJKofpBOjIydQXqwFN56+NwOUDi/CBzQikAJKKKgWVJgf27g51MLLoToZiuqCpkzbb2NufbptYQH1zcgjjEiuLFVUbOzc8De3j42zb0ZyxfPn/VdOB/gsjZMQuEnwlr8gKYVDJjjHyyeH8Y/aUtUIyiGEbJsIS4XsD3xatLnAJbDH0WIMoF3Unhz33uBUwETiagF8WYL7jkCKx8PCyCe45uPnm+F35NNhMe0Q0TIxpCE/ucVWCdM3Fg3jTf/8j9959MSzYm4rkRnA7W5Ae0Yjt4J7fXZBn7OGhgHQsHdK7ApQNmgXbbmIg7RXBRCzmkgFf5XEbrWAvdoVHMiThFr66jNVYglrLZTirLLZDCByvhm9BL4K9BWcPcmHFr3n7LWm+JGg9GOujJwXOKOOFAmtLu5OL7zSkkbb5mlg2P3dti8R6LWLbgWHDrmtZ1gTtsvni/XLDQK1rYg9f0XJoJGoKREdg7BoaPQvuv2RfDR86dh/LXngwMjvWXYULCqwESwX+NsYx2ipVv2USl0/CsiqlASuZKE0Gk9FzzIQxRIhfHMgsLNpIcRzzY4wU8q5rTPTHJ38ctzlqghNKy0gF/RFqRCdiQUteGD/RHDwQCdFZCbpfCVQq4o/+k0BJSMgbKAMgOlwDpHParhRgMTB80S+Lnny5B7zDNH7wCykcSkkZ80F0M78fvLJfJ1qrzGrK23ynUDVQHGa+GoHZJ1Vs9ZoZlWXSBfA5UDJX3N2qu7UEx9ZCjTiD7o8YDmQGqJLWwt/OrKGu9haA11GeZTO7g2y6lI78JlMdTt2+LNU2AnaJlZTDzC+wqT4C7YIMF15OOrvd+WBbaSfowyC9bUHPSG9HpTHzpuHFxzC+ebwE+Ctikr73eiYXTNj09RCb8/mgBVsnR+VYORgiyPaGQbKomYuVzTCmw3LMhl8FthPkLVxZUpvLoDqxGikDBxqCRGDkuoExB3hPHKF86nkDC2EEVwfQB7U8gSHx4tM2h0ZFWM3u7+thS5lT7BALrylkJUvoKDImTU7hSwL2FnDNk2JDWInTDhwyAAZejcrB5FhGuHgY+Fa3FwzuqgCXSiUmQ78hq2KsBVKaPuEFsWkNul8SMFuoZVfDlLYkEXoAW074DsANLLQ9xfvwdNAWYnaNbF81t3QN6D4kpBfWWfyFW4y7vwwQ5iNPKoyPl6oGXyb+zAaOj9w6aEXu4rHxLpPZ2iQt5xF2z8ErjDIS8wzzcL5AvIS9g6DB+/x0fIXAytNmQVbqIxlU4ilwmYOjJgfSuYHgnNNCiLOLiPKw5kOyzLei7CYMJ7A9w15w5EoYEoCAahMR2ul94fzL2CyhwkK44yzxnlGcWwQWTOBzYWzBdTf2V9w4tJo0BnEOfe4Ag1c2FbICMfnBZyLkqwBH4HaCU0pkNdGqRUOGMRxvqIWKlAHfcx72XxrfPqWkZQGvg7d8GBhUggOhFumKHuaKE/sN4IiRicDdZysXw6EYwyOBzBIA2VDEkwNRlUJa6piaSOoGr8JjryJd2x8O6QcOD2w/hV+IGuVkLy6Vi4GAdNODOxRRDQeG5DuAmMwv9m5wgGQFUnjsTU4FIYVoZxWmCqkrIMbs8y+JX/2DSGTgyxhZH2WkgEvijBKuXromrAHgs/bPF8l3urLGJFnazSVBXirmNQVL5OYPAORGu+KpIyPJfALytf+rC3C3ESLHbhczarMXQihAO5dTe2uwdWziXplsPHCJ9c6o7C/kR7tyntIcnqiD6VOyJbbs3iYn++wYZSJdeajaHwDTkbhK8Jg9wKAzzL9q0CvXB9ZoaTuU1ZOdNAGuII1v7I9XlKbNEyK9BElt29kiyvERjsMvgDz7erPl8yinwyVwioW16+RAgL60b7FHVTgcuWxpciVJ1biKoabRp/BqLTQrgNZCyxOg9bki63IgYL5rdD/3d2IJ1AZxX6PV+/0Je+Ti1KEI2GqBMqN1kiX0Ac3yoRKUvQFmcmOorXIhXFfyQR6nnyFajQpFB2odoP4+bm9lM3Q9yz0FDKTf+F1RCKZE4DJsFuTUKcvBdeh0GAFdCKpOD5jgNXos1YM71eM93RPr+1DD4837HgKrSbQrkPxQEUiQ8kaBGCKwKssz7SUE6Xxw/9F9z6DS7PfVYuy2EyhbV1aB8NibAy8FvL4Y8nsLoKh7d8k2Xhiz+TBNFZgckE2e+BHQfXp780Pu0OjKdwsA/jLkx7UO6BTYlUhzg6FElzUI0YCTBgs1DoWQaLWc6FtwVzxVaziZ5V/M2n4I8HkxuHBqLQ4Wr+HI6EugL7Ut5nZEeea6YOtMXmDkZhT7cM/jgcqMpAGh8BEyM/DrUG7eZLnV2oOM6XxjfuVoLZ4byKTAvIC0SZI1TkVSVx4G8F7uL5FLkPN5qQ4zp6HDY2vebNC4SKEa72B6hubiiXxC8KPy62hiYLVbQCKSIpXFolSrwkGdjnTLfo2d04sgPnTD9U1aZB2TazuXZgmrlYt7v9A3O1J7PQoAyrPgrayIRUqpOgRzD8zqDPc6Nt29P7RFXfuaYXjhlMl8Ov+zw32qan94nKPq7ph2rrNGh+Hc69lCC0gaoBU8zV2iyY39zi0xhE00BReiGw1gcF8jzErd3c71oif1axZkP/nfOxdKEgHyNEG5KN0EiyZP4URAtaa34zQeSkElKIcnTixBe/I+Ff9jhIz3Etga7Ubi9sPCfBCmRhLGvj/S7q2ybdhGvpLEA+J6Tj8Bpzq5bChV2Y+SrAvzsresW+OSf3odqXetwV3gWb+OLGRfP/4If46PEeZPtQTqAcecWBFogaTBbM6xL5s0NnooI6b3B1Dbrxmq8owqKsweRB2JfLRxtfvJWm3h2pQgA/DyW0TQlR7G9W4JNgS+YXfqNcT7ybATqKVojj8qvnzz8RwgT1m+cY3PclOLLBuHasSoFw3qTUYeyKHOwkTPw4rA4X/jk/8DL4vzONtD5LfwcfQsvgiJ4Lhk/onfG5cb3ypTJpbxQ7ONNVgrEXvOXwOTfWzZeau+KNZmSdWZMiDXtuU3m3Mk0rdDrx2pZxsNFm8fza87O0oUinNHmOGI19tMJZH9KbhkNC5HMZ32XwXeBPfUTGNj45pZKbFsm1N3BFGSIrtYPpUvm0133QwlrAOClzKaUdJknrHJw3Ep6M4E+G6O45ekPFTlpzo4K+g27jb3cxHoHeCxupmYnoh35kc5vSmSYcBAGdhM+lsxR8HZzAc+HL8ZNPvhw9//zmMO0enEsGQpmertm3MBRL5Ith1h2e4wBV7Og6u2HR/RAQ6DtMr8LsddEHPegvl1/2HHqev7sL3X3o92Ew8iWSZTkn8MUS+UPPzwuoMm8dyxSyPpQDXDmGbB9b9UM8eVj7KP9y+FQTyA+gHs6sYd1qGRVF/XPb278/hCfjsLU4LX2KTH4TcccpXKsh6sQY7c/e3pzoQXhm4VmF5yxQP38wW912RpUm2OILwOfDjFlwnD59XrZan2yP6/ib742aU2+98b8bBsOYOgNbzfliC+SPPtlu7j78TXP46Kk8qhu5shJPGk1W15SjIeN0SvedyzSvXgT7VyH0WSyNn2Yp6XBIPhgg0sxrvrICXVFnA3T1PvAq8F74XUviN7V3b2w9V+vjyzGdy8BBVY+x9q0GXo2hWBr/VgKwApc2SasVJ0l14dgx+/nXXqtKOG/FbYdIFTzxIqyfglbjnbci/NZ5zTLTeNN57fJhj/nBf3x2Ru7W7IRbVZx+QX1ye+PF7at7p8rupQbq+FbWcgl8TqtPP/GvX7SrR07lcd24KI4nRU5VVozyjN7l97GX/hLs/wKuB62yeH5ZVqRFwXQ4wIxGiCyEAfMpNGOquo8xV4FX5krD3RL4KTQjPw+imQvXJThXABJjDHW928BbMVy7AHopfC8zs+hc2iRJJ47j+sIjj3zj8fPnb/HlrfjemZCmc4/D/gUYxbBrYDccBpjM7Ujz27TeT3y4uXTtbPDn63Rn68/zz7/pnvnyrz8ubH4B0Ylh38DecvhnnDzDC27d3f941btxoR6beLizY/LdXZdmGdV4jC3KMGT1nPZfPD/LMqrJBJNmPqlU5L5M0lS4m6XOdRij+TtTLJpf+qO+Ipqv8Azrrca51Gk9rqAfQ3cm/Evj+7rSrPLCn1945JHs8fPnz8zJ+o/Onrz1euJbkDwWQmmNL6Y2wg/yeM7nrOYyVT808bMiGW4bfH7cF/zjjISzwEkJv/Qt2H0saPrG1z4vmu8kPA18V37yxL/6VhO1HqtpyCbjpnJNVA5T4bZfBv4cXyJbL49vdSSMFYwnkI99GB2NMxPqOsOYV4ILVC6Vj50GpTScC03XDiLjnIiqqo+1b12Aq4/DGefnd/F855SRMorabYlSxYWTJ+3j589/KvT/rP2we4MKOCP8h+59DNw3IDrsIQ3+5EEu/FIz8wvZzJ0IYa7g5BzwzFxg2n64t+BEyHhZ+IePweQbIJbLP4PgrLDHf+E/P2ac+0ZNcripMorxCDN9Q8P/FHBV3XRjl8EvM1xTYouJRudC4BSixtoRdb2Hta8buLwcfpMLITz/Vry8Ms4ZJ4SOpOwQxwZr9SBNh+eMkeHWiMvjR5FBKTeIova5++/feebixYs6KFj7/3Fz3B/aFxyGzafA/BbUR31s1HGb8N2u/brA88CzYRL4sFvifchC+Fvnf4x/flgf//tPadv8VpVNj2bZQFj7MvB/g7b9kWYXxrdVcdQ6Jay1GDPAuQJjplTVdtD+k6XzIUOIEUpZpAQhjFMq7ko5fT5Jymdv3Pj+zzRf/A336Z2/mekacBJ4KGiZp0LBSdhmcy5ome8BF8PukLla4Z+i8z8r/Fu3iP/UnafX+nLr5GikH6qq70dw6W+FL8T6Q3U9jZrm4Clr81Zdj2iaaxXsLZ1vTN6CFKXKSqn4XLu9opWS3zt0aOfipUuXAv9kBBd/Zvn/Dy73Edl4mFIzAAAAAElFTkSuQmCC","venus":"data:image/png;base64,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"};
const PLANET_TEXTURE_IDS = ["earth","moon","mars","jupiter","saturn","sun",
  "icy","terrestrial","hot","uranus","neptune","venus","mercury"];
const planetTextures = new Map();
for(const id of PLANET_TEXTURE_IDS){
  const image=new Image();image.decoding="async";
  image.src=PLANET_TEXTURE_DATA[id]??"";
  planetTextures.set(id,image);
}
function planetTextureKey(body) {
  const id=String(body.id ?? "").toLowerCase();
  if(id==="luna"||id==="moon"||id==="callisto"||id==="enceladus")return "moon";
  if(id==="titan")return "venus";
  if(planetTextures.has(id))return id;
  if(body.type==="moon")return "moon";
  if(body.biome==="gas_giant")return "jupiter";
  if(body.biome==="terrestrial")return "terrestrial";
  if(body.biome==="desert"||body.biome==="molten")return "hot";
  if(body.biome==="lifeless"||body.biome==="ice")return "icy";
  return null;
}
function drawPlanetSprite(image,x,y,size){
  if(!image || !image.complete || !image.naturalWidth || !image.naturalHeight)return false;
  const cell=image.naturalHeight;
  const count=Math.max(1,Math.floor(image.naturalWidth/cell));
  // The last frame of each six-frame CC0 planetary sheet is fully lit.
  // Hold it permanently: cycling frames caused a visible moving shadow.
  const frame=count-1;
  ctx.drawImage(image,frame*cell,0,cell,cell,x-size/2,y-size/2,size,size);
  return true;
}
// Localized, role-based callsigns. Not IDs: no effect on ECS, contracts or saves.
const SHIP_CLASS_LABELS = Object.freeze({
  courier: "Курьер", freighter: "Грузовик", hauler: "Тяжёлый транспорт",
  tanker: "Танкер", miner: "Шахтёр"
});
const SHIP_FACTION_CODES = Object.freeze({
  "terran-authority": "G", pirates: "P"
});
const SHIP_CANONICAL_NAME = /^(?:Курьер|Грузовик|Тяжёлый транспорт|Танкер|Шахтёр) [A-Z]-\d{2,}$/u;
function shipClassLabel(ship) {
  return SHIP_CLASS_LABELS[String(ship?.class ?? "").toLowerCase()] ??
    String(ship?.class ?? "Корабль");
}
function shipFactionCode(ship) {
  return SHIP_FACTION_CODES[ship?.faction_id] ??
    (String(ship?.faction_id ?? "X").slice(0, 1).toUpperCase() || "X");
}
function refreshShipCallsigns() {
  const groups = new Map();
  for(const ship of s.ships) {
    const group = String(ship.faction_id)+"::"+String(ship.class);
    if(!groups.has(group)) groups.set(group, []);
    groups.get(group).push(ship);
  }
  const names = new Map(), variants = new Map();
  for(const ships of groups.values()) {
    ships.sort((a,b)=>String(a.id).localeCompare(String(b.id)));
    const occupied = new Set();
    // Preserve standardized names already stored in fresh-world seeds.
    for(const ship of ships) {
      if(SHIP_CANONICAL_NAME.test(String(ship.name ?? ""))) {
        const id=Number(String(ship.name).match(/-(\d+)$/)?.[1]);
        if(Number.isSafeInteger(id)&&id>0) occupied.add(id);
      }
    }
    let next = 1;
    for(let i=0;i<ships.length;i++) {
      const ship=ships[i], old=String(ship.name??"");
      if(SHIP_CANONICAL_NAME.test(old)) {
        names.set(ship.id, old);
      } else {
        while(occupied.has(next)) next++;
        names.set(ship.id, shipClassLabel(ship)+" "+shipFactionCode(ship)+"-"+
          String(next).padStart(2,"0"));
        occupied.add(next++);
      }
      const display=names.get(ship.id);
      const ordinal=Number(display.match(/-(\d+)$/)?.[1]) || i+1;
      variants.set(ship.id,ordinal-1);
    }
  }
  s.shipCallsigns = names;
  s.shipSymbolVariants = variants;
}
function shipDisplayName(ship) {
  if(!ship) return "Корабль";
  return s.shipCallsigns.get(ship.id) || ship.name || ship.id || "Корабль";
}

let pixels = { w: 0, h: 0 };

function setOnline(isOnline, statusText) {
  s.live = isOnline;
  els.connection.classList.toggle("online", isOnline);
  els.connection.lastChild.textContent = statusText;
  els.mapError.hidden = isOnline;
  els.pauseBtn.disabled = !isOnline;
  els.speedSelect.disabled = !isOnline;
}

async function getJSON(path) {
  const response = await fetch(path, { cache: "no-store" });
  if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
  return response.json();
}

async function postJSON(path, value) {
  const response = await fetch(path, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(value ?? {})
  });
  if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
  return response.json();
}

function mergeById(previous, incoming, identifier = "id") {
  const map = new Map(list(previous).map(x => [x[identifier], x]));
  for (const entity of list(incoming)) {
    if (entity && entity[identifier] != null) {
      map.set(entity[identifier], { ...map.get(entity[identifier]), ...entity });
    }
  }
  return [...map.values()];
}

function saveReport(report) {
  if (!Array.isArray(report?.systems)) throw new Error("Нет systems[] в /api/report");
  const firstReport = !s.report;
  s.report = report;
  s.ships = list(report.ships);
  refreshShipCallsigns();
  s.index = buildIndex(report);
  s.lastReportAt = Date.now();
  // Genesis has no reason to open on an empty sector map with a guide
  // telling the user to open its one and only system.
  if (firstReport && s.index.systems.length === 1) {
    s.systemName = s.index.systems[0].name;
    s.view = "system";
    s.selection = null;
    s.guideDismissed = true;
    s.cameraFocus = "inner";
    els.shipsToggle.checked = true;
    resetCamera();
  }
  if (s.systemName && !systemByName(s.systemName, s.index)) {
    s.view = "sector"; s.systemName = null; s.selection = null;
  }
  renderSidebar();
  renderInspector();
  refreshToolbar();
  renderStartGuide();
  refreshCameraFocusControls();
}

async function fetchReport() {
  if (s.fetching) return;
  s.fetching = true;
  try {
    const report = await getJSON("/api/report");
    saveReport(report);
    s.error = null;
  } catch (error) {
    s.error = error.message;
  } finally {
    s.fetching = false;
  }
}

function refreshToolbar() {
  if (!s.report) return;
  const h = s.health ?? s.report;
  const running = Boolean(h.running);
  els.tick.textContent = fnum(h.tick);
  els.dataTick.textContent = fnum(s.report.tick);
  els.agentCount.textContent = h.agent_count != null ? fnum(h.agent_count) : "—";
  els.pauseBtn.textContent = running ? "⏸ Пауза" : "▶ Продолжить";
  els.shipTotal.textContent = fnum(s.ships.length);
  els.facilityTotal.textContent = fnum(list(s.report.facilities).length);
  els.marketTotal.textContent = fnum(list(s.report.markets).length);
  els.systemCount.textContent = fnum(s.index?.systems.length);
  els.factionCount.textContent = fnum(list(s.report.factions).length);
  els.worldTitle.textContent = s.view === "system"
    ? "Система · " + s.systemName : "Обзор сектора";
  const largeWorld = s.ships.length > 20 ? " · большой исходный мир" : "";
  const smallStart = s.index?.systems.length === 1 && s.ships.length <= 8;
  els.worldSubtitle.textContent = smallStart
    ? (s.view === "system" ? "Живая карта · объекты и маршруты" : "Малый старт · сектор")
    : (s.view === "system" ? "Система · живые данные" : "Сектор · живые данные") + largeWorld;
  els.sectorTab.classList.toggle("active", s.view === "sector");
  els.systemTab.classList.toggle("active", s.view === "system");
  els.systemTab.disabled = !s.systemName;
  refreshCameraFocusControls();
  const speed = h.world_speed ?? h.config?.world_speed;
  if (speed != null && !els.speedSelect.matches(":focus")) {
    const closest = [...els.speedSelect.options].reduce((best, opt) =>
      Math.abs(Number(opt.value) - speed) < Math.abs(Number(best.value) - speed) ? opt : best,
      els.speedSelect.options[0]);
    els.speedSelect.value = closest.value;
    els.speedSelect.title = "Текущий world_speed: " + speed;
  }
}

function marker(parent, className, color) {
  const dot = document.createElement("span");
  dot.className = className;
  dot.style.backgroundColor = color;
  parent.appendChild(dot);
  return dot;
}
function textEl(tag, content, cssClass) {
  const el = document.createElement(tag);
  el.textContent = q(content);
  if (cssClass) el.className = cssClass;
  return el;
}

function renderSidebar() {
  if (!s.index) return;
  els.systemList.replaceChildren();
  const search = els.systemSearch.value.trim().toLocaleLowerCase("ru");
  for (const system of s.index.systems) {
    if (search && !system.name.toLocaleLowerCase("ru").includes(search)) continue;
    const item = document.createElement("button");
    item.className = "system-item" + (s.systemName === system.name && s.view === "system" ? " active" : "");
    const color = system.ownership.kind === "single"
      ? factionColor(system.ownership.factionId, s.index) : "#788d9e";
    marker(item, "dot", color);
    item.appendChild(textEl("span", system.name, "sys-name"));
    item.appendChild(textEl("span", list(system.bodies).length, "sys-count"));
    item.addEventListener("click", () => chooseSystem(system.name, true));
    els.systemList.appendChild(item);
  }
  if (!els.systemList.childNodes.length) {
    els.systemList.appendChild(textEl("div", "Ничего не найдено", "empty"));
  }
  els.factionLegend.replaceChildren();
  const factions = [...list(s.report.factions)].sort((a,b) => a.name.localeCompare(b.name));
  for (const faction of factions) {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "faction-item strategy-faction-link";
    row.title = "Показать стратегию фракции";
    marker(row, "dot", factionColor(faction.id, s.index));
    row.appendChild(textEl("span", faction.name));
    row.addEventListener("click", () => openStrategyForFaction(faction.id));
    els.factionLegend.appendChild(row);
  }
}

function renderStartGuide() {
  const system = s.index?.systems.find(x => x.name === "Sol") ?? s.index?.systems[0];
  const visible = Boolean(system && !s.guideDismissed && !s.selection && s.view === "sector");
  els.firstRunGuide.hidden = !visible;
  els.startSystemBtn.disabled = !system;
  els.startSystemBtn.textContent = system ? "Открыть " + system.name : "Нет доступных систем";
}

function chooseSystem(name, enter) {
  if (!s.index || !systemByName(name, s.index)) return;
  const changed = s.systemName !== name || (enter && s.view !== "system");
  s.systemName = name;
  s.selection = { type: "system", id: name };
  s.guideDismissed = true;
  if (enter) {
    s.view = "system";
    els.shipsToggle.checked = true;
    if(changed)s.cameraFocus="inner";
  }
  if (changed) resetCamera();
  renderSidebar(); renderInspector(); refreshToolbar(); renderStartGuide();
}

function sectorMode() {
  s.view = "sector";
  els.shipsToggle.checked = false;
  resetCamera(); renderSidebar(); refreshToolbar(); renderStartGuide();
  refreshCameraFocusControls();
}
// Observer-only follow state; this NEVER modifies the simulation's coordinates.
/// Double-click or press "Следить" after selecting a physical object.
function trackedEntity() {
  if(!s.follow || !s.index)return null;
  const {type,id,ids}=s.follow;
  if(type==="ship")return s.ships.find(x=>x.id===id)??null;
  if(type==="body")return s.index.systems.flatMap(sys=>sys.bodies).find(x=>x.id===id)??null;
  if(type==="facility")return list(s.report?.facilities).find(x=>x.id===id)??null;
  if(type==="facility_group") {
    const members=list(s.report?.facilities).filter(x=>ids?.includes(x.id));
    return members.find(x=>x.type==="station") ?? members[0] ?? null;
  }
  if(type==="construction_site")return list(s.report?.construction_sites).find(x=>x.id===id)??null;
  return null;
}
function updateFollowButton(){
  if(!els.followBtn)return;
  const selectable=["ship","body","facility","facility_group","construction_site"].includes(s.selection?.type);
  els.followBtn.disabled=!selectable && !s.follow;
  const following=Boolean(s.follow);
  els.followBtn.classList.toggle("following",following);
  els.followBtn.setAttribute("aria-pressed",String(following));
  els.followBtn.textContent=following?"Снять слежение":"Следить за объектом";
}
function stopFollowing(){
  s.follow=null;s.followVisual=null;
  updateFollowButton();
}
function followSelectedObject(){
  const item=s.selection;
  if(!item||!["ship","body","facility","facility_group","construction_site"].includes(item.type)){
    stopFollowing();return;
  }
  if(s.follow?.type===item.type && s.follow?.id===item.id) {
    stopFollowing();return;
  }
  s.follow={type:item.type,id:item.id,ids:item.ids??null};
  s.followVisual=null;
  updateFollowButton();
}
function followedWorldPosition(){
  const entity=trackedEntity();
  if(!entity) {
    if(s.follow)stopFollowing();
    return null;
  }
  const target=s.follow.type==="ship"?
    positionOf(entity,s.positions):liveEntityPoint(entity,s.positions);
  if(!target)return null;
  // Smooth only camera coordinates, not world/agent state.
  s.followVisual=approachWorldPoint(s.followVisual,target,0.18,12);
  return s.followVisual;
}

function resetCamera() {
  stopFollowing();
  const current=systemByName(s.systemName,s.index);
  // Small comfortable overscan of the populated core, even when a remote
  // Saturn system would otherwise consume most of the available pixels.
  s.zoom = s.view==="system" && s.cameraFocus==="inner" && canFocusInner(current) ? 1.28 : 1;
  s.pan = {x: 0, y: 0};
}

// View presets affect the Observer camera only; never a simulated position.
// A useful starting frame should show the populated inner system without
// shrinking Earth/Mars/Jupiter to dots because Saturn is far away.
function canFocusInner(sys) {
  if(!sys || !Array.isArray(sys.bodies))return false;
  const radii=sys.bodies.map(body=>number(body.orbit_radius))
    .filter(radius=>Number.isFinite(radius)&&radius>0);
  return radii.length >= 3 && Math.max(...radii)>7;
}
function innerFocusRadius(sys) {
  const radii=sys.bodies.map(b=>number(b.orbit_radius))
    .filter(r=>Number.isFinite(r)&&r>0);
  const outer=Math.max(0,...radii);
  // Keep inner-view world scale comparable to the original system, so
  // doubled physical distances actually LOOK doubled on screen instead
  // of silently zooming out to the same crowded fit.
  // Farther planets remain reachable through "Вся система"/pan/zoom.
  return Math.max(4,Math.min(7,outer*.31));
}
function refreshCameraFocusControls() {
  const system = s.view === "system" && systemByName(s.systemName,s.index);
  const supported=Boolean(system && canFocusInner(system));
  if(els.focusPicker)els.focusPicker.hidden=!supported;
  if(!supported)return;
  const inner=s.cameraFocus === "inner";
  els.focusInnerBtn.classList.toggle("active",inner);
  els.focusFullBtn.classList.toggle("active",!inner);
  els.focusInnerBtn.setAttribute("aria-pressed",String(inner));
  els.focusFullBtn.setAttribute("aria-pressed",String(!inner));
  els.focusCaption.textContent=inner
    ? "Ближние планеты · пояс. Юпитер и дальние орбиты — во всей системе"
    : "Все планеты и дальние узлы системы";
}
function setCameraFocus(mode) {
  if(s.view!=="system" || (mode!=="inner"&&mode!=="full"))return;
  s.cameraFocus=mode;
  resetCamera();
  refreshCameraFocusControls();
}


function selectionEntity() {
  if (!s.selection || !s.report) return null;
  const {type, id} = s.selection;
  if (type === "ship_group") return {
    name: "Корабли в одной области",
    members: (s.selection.ids ?? []).map(shipId => s.ships.find(x => x.id === shipId)).filter(Boolean)
  };
  if (type === "facility_group") return {
    name: s.selection.name ?? "Объекты в одном хабе",
    members: (s.selection.ids ?? []).map(facId =>
      list(s.report.facilities).find(x => x.id === facId)).filter(Boolean)
  };
  if (type === "system") return systemByName(id, s.index);
  if (type === "ship") return s.ships.find(x => x.id === id) ?? null;
  if (type === "facility") return list(s.report.facilities).find(x => x.id === id) ?? null;
  if (type === "construction_site") return list(s.report.construction_sites).find(x => x.id === id) ?? null;
  if (type === "body") {
    for (const system of s.index.systems) {
      const body = system.bodies.find(x => x.id === id);
      if (body) return body;
    }
  }
  return null;
}

function inspectorRow(parent, label, value) {
  const row = document.createElement("div");
  row.className = "field";
  row.appendChild(textEl("span", label, "label"));
  row.appendChild(textEl("span", value, "value"));
  parent.appendChild(row);
}
function detailGroup(parent, title) { parent.appendChild(textEl("div", title, "group-title")); }
function chips(parent, entries, max = 8) {
  const items = list(entries).slice(0, max);
  if (!items.length) return parent.appendChild(textEl("p", "Нет данных"));
  for (const item of items) parent.appendChild(textEl("span", item, "chip"));
}
function showHubShips(content, location) {
  const members=shipsAtHub(s.ships,location);
  if(!members.length)return;
  detailGroup(content,"Корабли у станции");
  for(const ship of members.slice(0,100)){
    const button=document.createElement("button");
    button.type="button";button.className="group-member";
    button.appendChild(textEl("span",shipDisplayName(ship)));
    button.appendChild(textEl("span",
      shipMapState(ship)==="docked"?"Пристыкован": "На месте / без перелёта",
      "group-member-note"));
    button.addEventListener("click",()=>{
      s.selection={type:"ship",id:ship.id};renderInspector();
    });
    content.appendChild(button);
  }
}


let lastInspectorSelection = "";
function renderInspector() {
  const selectionKey = s.selection ? s.selection.type + ":" + s.selection.id : "";
  const previousScroll = selectionKey && selectionKey === lastInspectorSelection
    ? els.inspectorBody.scrollTop : 0;
  lastInspectorSelection = selectionKey;
  els.inspectorBody.replaceChildren();
  const entity = selectionEntity();
  document.body.classList.toggle("has-selection", Boolean(entity));
  renderStartGuide();
  if (!entity) {
    els.inspectorBody.appendChild(textEl("div", "◎", "placeholder-icon"));
    els.inspectorBody.appendChild(textEl("h2", "Выберите объект"));
    els.inspectorBody.appendChild(textEl("p", "Нажмите на систему, планету, станцию или корабль. Здесь появится его настоящее состояние."));
    return;
  }
  const type = s.selection.type;
  const typeNames = {
    system:"ЗВЁЗДНАЯ СИСТЕМА",ship:"КОРАБЛЬ",facility:"ОБЪЕКТ",body:"НЕБЕСНОЕ ТЕЛО",
    ship_group:"ГРУППА КОРАБЛЕЙ", facility_group:"ГРУППА ОБЪЕКТОВ",
    construction_site:"СТРОИТЕЛЬНАЯ ПЛОЩАДКА"
  };
  els.inspectorBody.appendChild(textEl("div", typeNames[type], "kind"));
  els.inspectorBody.appendChild(textEl("h2", type === "ship" ? shipDisplayName(entity) : type === "body" ? bodyDisplayName(entity) : (entity.name ?? entity.id)));
  const content = els.inspectorBody;
  if (type === "ship_group" || type === "facility_group") {
    const isShip = type === "ship_group";
    const members = entity.members;
    inspectorRow(content, "Всего", members.length);
    if(!isShip){
      inspectorRow(content, "Роль узла", hubTierLabel(members));
      inspectorRow(content, "Узел", members[0]?.location ?? "—");
      inspectorRow(content, "Фракция", factionName(members[0]?.faction_id, s.index));
      inspectorRow(content, "Не заброшены", members.filter(m=>!m.abandoned).length+" / "+members.length);
      detailGroup(content,"Состав узла");
      appendFacilityBreakdown(content,members);
      detailGroup(content,"Выбор сооружения");
      const ongoing=list(s.report?.construction_sites).filter(site=>
        site.location===members[0]?.location);
      if(ongoing.length){
        detailGroup(content,"Строительство на узле");
        for(const site of ongoing){
          const button=document.createElement("button");button.type="button";
          button.className="group-member";
          button.appendChild(textEl("span",site.name??"Строительная площадка"));
          button.appendChild(textEl("span",Math.round(number(site.progress)*100)+"%", "group-member-note"));
          button.addEventListener("click",()=>{
            s.selection={type:"construction_site",id:site.id};renderInspector();
          });
          content.appendChild(button);
        }
      }
    }
    content.appendChild(textEl("p",isShip ?
      "Корабли сгруппированы из-за масштаба карты. Выберите нужный корабль." :
      "Одна локация — один станционный комплекс. Внешние узлы показывают реальные предприятия; форма T1–T3 пока только визуальная компоновка, не механика улучшения станции.",
      "small-note"));
    for (const member of (isShip?members:[...members].sort(facilityOrder)).slice(0, 140)) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "group-member";
      button.appendChild(textEl("span", isShip ? shipDisplayName(member) : (member.name ?? member.id)));
      button.appendChild(textEl("span", isShip ? (member.current_goal ?? member.class ?? "") :
        facilityTypeSummary(member), "group-member-note"));
      if(!isShip)button.classList.add("family-"+facilityFamily(member.type));
      button.addEventListener("click", () => {
        s.selection = {type: isShip ? "ship" : "facility", id: member.id};
        renderInspector();
      });
      content.appendChild(button);
    }
    if (members.length > 140) {
      content.appendChild(textEl("p",
        "Показаны первые 140 объектов; для остальных приблизьте карту или откройте их через другой район.",
        "small-note"));
    }
    if(type==="facility_group" && members.length)
      showHubShips(content,members[0].location);
    els.inspectorBody.scrollTop = previousScroll;
    return;
  }
  if (type === "system") {
    const own = entity.ownership;
    const ownLabel = own.kind === "single"
      ? factionName(own.factionId, s.index) + " (по телам)"
      : own.kind === "mixed" ? "Несколько / спорная" : "Не определён";
    inspectorRow(content, "Территория", ownLabel);
    inspectorRow(content, "Координаты", fnum(entity.x) + " / " + fnum(entity.y));
    inspectorRow(content, "Тел", list(entity.bodies).length);
    const facilities = s.index.systemFacilities.get(entity.name) ?? [];
    const markets = s.index.systemMarkets.get(entity.name) ?? [];
    const pops = s.index.systemPopulations.get(entity.name) ?? [];
    inspectorRow(content, "Инфраструктура", facilities.length);
    inspectorRow(content, "Рынки", markets.length);
    inspectorRow(content, "Популяции", pops.length);
    inspectorRow(content, "Нехватки", shortageCount(markets) + " позиций");
    content.appendChild(textEl("p", "Принадлежность рассчитана по владельцам небесных тел. Это не официальный system_control.", "small-note"));
    detailGroup(content, "Объекты системы");
    chips(content, facilities.map(f => f.name), 16);
    detailGroup(content, "Доступные рынки");
    chips(content, markets.map(m => m.facility_location), 16);
  } else if (type === "ship") {
    inspectorRow(content, "Класс", shipClassLabel(entity));
    inspectorRow(content, "Позывной", shipDisplayName(entity));
    inspectorRow(content, "Внутренний ID", entity.id);
    inspectorRow(content, "Размер", entity.size ?? "—");
    inspectorRow(content, "Связь с фракцией", factionName(entity.faction_id, s.index));
    content.appendChild(textEl("p", "Фракционная принадлежность пока не определяет владельца или режим приказов. Корабль самостоятельно выбирает контракты.", "small-note"));
    inspectorRow(content, "Цель ИИ", entity.current_goal);
    inspectorRow(content, "Действие", entity.current_bt ?? "—");
    inspectorRow(content, "Положение", entity.location ?? (entity.transit ? "В пути" : "Неизвестно"));
    if (entity.transit) {
      inspectorRow(content, "Из", entity.transit.from);
      inspectorRow(content, "В", entity.transit.to);
      inspectorRow(content, "Пройдено", fnum(entity.transit.distance_travelled) + " / " + fnum(entity.transit.distance_total));
    }
    inspectorRow(content, "Топливо", fnum(entity.fuel) + " / " + fnum(entity.fuel_capacity));
    if(number(entity.fuel_capacity)>0)inspectorMeter(content,"Топливо",number(entity.fuel)/number(entity.fuel_capacity));
    inspectorRow(content, "Кредиты", fnum(entity.credits));
    inspectorRow(content, "Экипаж", entity.crew?.size ?? "—");
    detailGroup(content, "Груз");
    chips(content, sortedCargo(entity.cargo).map(([name,amount]) => commodityLabel(name) + ": " + amount));
    if (entity.progression) {
      detailGroup(content, "Развитие");
      inspectorRow(content, "Уровень", entity.progression.level ?? "—");
      inspectorRow(content, "Очки модернизации", entity.progression.retrofit_points ?? "—");
    }
    if (entity.fitting?.modules) {
      detailGroup(content, "Установленные модули");
      const slotNames = {engine:"Двигатель",cargo_bay:"Трюм",sensors:"Сенсоры",reactor:"Реактор",comms:"Связь"};
      for (const slot of ["engine","cargo_bay","sensors","reactor","comms"]) {
        const slug = entity.fitting.modules[slot];
        inspectorRow(content, slotNames[slot], slug ? String(slug).replace(/.*_t([123])$/, "T$1") : "Нет данных");
      }
    }
  } else if (type === "facility") {
    inspectorRow(content, "Тип", facilityTypeLabel(entity.type));
    inspectorRow(content, "Назначение", facilityMeta(entity.type).role);
    if(["mining_rig","salvage_field","gas_harvester","refinery","smelter"].includes(entity.type)){
      const raw=naturalResourcesAt(entity);
      if(raw.length)inspectorRow(content,"Сырьё небесного тела",
        raw.map(([name,value])=>commodityLabel(name)+" · "+fnum(value)).join(" / "));
    }
    inspectorRow(content, "Фракция", factionName(entity.faction_id, s.index));
    inspectorRow(content, "Расположение", entity.location);
    inspectorRow(content, "Статус", facilityStateLabel(entity));
    inspectorRow(content, "Категория", FAMILY_NAMES[facilityFamily(entity.type)]);
    inspectorMeter(content,"Состояние сооружения",number(entity.condition));
    inspectorRow(content, "Уровень", entity.level);
    inspectorRow(content, "Кредиты", fnum(entity.credits));
    inspectorRow(content, "Корабли у причала", list(entity.docked_ships).length);
    inspectorRow(content, "Заброшен", entity.abandoned ? "Да" : "Нет");
    appendOperationalFacts(content,entity);
    if (entity.gate_link) inspectorRow(content, "Связанные врата", entity.gate_link.paired_gate_id);
    detailGroup(content, "Резервы предприятия");
    chips(content, Object.entries(entity.reserves ?? {}).filter(([,v])=>number(v)>0).map(([k,v])=>commodityLabel(k) + ": " + fnum(v)));
    content.appendChild(textEl("p","Резервы объекта и общий запас рынка — разные данные; здесь не показаны выдуманные производственные рецепты.","small-note"));
    // Show the actual commodity market attached to this facility location.
    const market = list(s.report.markets).find(m => key(m.facility_location) === key(entity.location));
    if (market) {
      detailGroup(content, "Рынок — товары");
      const commodities = [...new Set([
        ...Object.keys(market.prices ?? {}), ...Object.keys(market.supply ?? {})
      ])].sort((a,b) => number(market.shortage_ticks?.[b]) - number(market.shortage_ticks?.[a]));
      for (const commodity of commodities.slice(0, 16)) {
        inspectorRow(content, commodityLabel(commodity),
          "Цена " + fnum(market.prices?.[commodity]) +
          " · запас " + fnum(market.supply?.[commodity]) +
          " · спрос " + fnum(market.demand?.[commodity]));
      }
    }
    appendReferenceRecipes(content,entity);
    showHubShips(content,entity.location);
  } else if (type === "construction_site") {
    inspectorRow(content, "Тип будущего объекта", facilityTypeLabel(entity.facility_type));
    inspectorRow(content, "Фракция", factionName(entity.faction_id, s.index));
    inspectorRow(content, "Узел", entity.location);
    inspectorRow(content, "Материал", commodityLabel(entity.commodity));
    inspectorRow(content, "Доставлено", fnum(entity.progress_delivered) + " / " + fnum(entity.progress_required));
    inspectorMeter(content,"Готовность строительства",number(entity.progress));
    content.appendChild(textEl("p", "Прогресс относится к реальной площадке. Завершённый контракт — ещё не готовая постройка.", "small-note"));
  } else if (type === "body") {
    inspectorRow(content, "Тип", entity.type);
    inspectorRow(content, "Биом", entity.biome ?? "—");
    inspectorRow(content, "Фракция", factionName(entity.controlling_faction, s.index));
    inspectorRow(content, "Спорная", entity.contested ? "Да" : "Нет");
    inspectorRow(content, "Радиус орбиты", entity.orbit_radius);
    const constructed=list(s.report?.facilities).filter(f=>f.body_id===entity.id);
    if(constructed.length){
      detailGroup(content,"Размещённая инфраструктура · "+constructed.length);
      chips(content,constructed.map(f=>facilityTypeLabel(f.type)),12);
    }
    if(entity.resources && Object.values(entity.resources).some(value=>number(value)>0)){
      detailGroup(content,"Ресурсы тела по данным сервера");
      chips(content,Object.entries(entity.resources).filter(([,amount])=>number(amount)>0)
        .map(([name,amount])=>commodityLabel(name)+" · "+fnum(amount)),12);
    }
  }
  els.inspectorBody.scrollTop = previousScroll;
}

const eventNames = {
  ship_docked: "Корабль пристыковался", ship_undocked: "Корабль отстыковался",
  ship_refitted: "Модернизация корабля", ship_decommissioned: "Корабль списан",
  construction_completed: "Строительство завершено", construction_started: "Строительство началось",
  contract_posted: "Опубликован контракт", contract_renewed: "Контракт продлён",
  contract_expired: "Срок контракта истёк", contract_completed: "Контракт выполнен",
  ship_spawned: "Создан корабль", faction_control_changed: "Изменение территории"
};
function eventLabel(event) {
  if (typeof event === "string") return {kind:"Событие",detail:event};
  const raw = String(event?.event_type ?? event?.kind ?? event?.type ?? "event");
  const kind = eventNames[raw] ?? raw.replaceAll("_", " ");
  const detail = event?.message ?? event?.description ?? event?.detail ?? event?.text;
  if (typeof detail === "string") return {kind,detail};
  const contractType = event?.contract_type;
  const cargo = contractCargoLabel(event?.commodity, contractType);
  const parts = [];
  if (contractType) parts.push("Тип: " + contractLabel(contractType));
  for(const [field,label] of [
    ["ship_name","Корабль"],["ship_id","Корабль"],
    ["facility_name","Объект"],["facility_id","Объект"],
    ["location","Место"],["source_location","Откуда"],
    ["destination","Куда"],["quantity","Количество"]
  ]){
    if(event?.[field] != null) parts.push(label + ": " + event[field]);
  }
  if(cargo)parts.push("Груз: "+cargo);
  if(event?.kind==="contract_expired")parts.push("Исполнитель не принял заявку");
  return {kind,detail:parts.slice(0,5).join(" · ") || "Изменение в симуляции"};
}
function renderEvents() {
  els.eventFeed.replaceChildren();
  if (!s.events.length) {
    els.eventFeed.appendChild(textEl("div","События появятся по мере работы симуляции","empty"));
    return;
  }
  for (const {tick,event} of s.events.slice(0,70)) {
    const row = document.createElement("div");
    row.className = "event-row";
    row.appendChild(textEl("time","t " + fnum(tick)));
    const body = document.createElement("div");
    const parsed = eventLabel(event);
    body.appendChild(textEl("span", parsed.kind, "event-kind"));
    body.appendChild(textEl("span", parsed.detail));
    if (event && typeof event === "object") {
      const details = document.createElement("details"); details.className = "event-raw";
      details.appendChild(textEl("summary", "Технические данные"));
      const raw = textEl("pre", JSON.stringify(event, null, 2));
      details.appendChild(raw); body.appendChild(details);
    }
    row.appendChild(body);
    els.eventFeed.appendChild(row);
  }
}
// User-facing export: current real server snapshots plus only the events received
// by this particular browser tab (Observer retains at most the newest 1000).
// This is NOT a full server log or a complete replay of earlier ticks.
async function exportDiagnostics() {
  const button = els.exportDiagnostics;
  if (button.disabled) return;
  const oldText = button.textContent;
  button.disabled = true;
  button.textContent = "Сбор…";
  try {
    const routes = {
      health: "/api/health",
      report: "/api/report",
      strategy: "/api/strategy",
      contracts: "/api/contracts",
      facilities: "/api/facilities",
      ships: "/api/ships",
      markets: "/api/markets",
      construction_sites: "/api/construction_sites",
      retirements: "/api/retirements",
      faction_relations: "/api/factions/relations",
      populations: "/api/populations"
    };
    const results = await Promise.all(Object.entries(routes).map(async ([name, path]) => {
      try { return [name, {ok: true, value: await getJSON(path)}]; }
      catch (error) { return [name, {ok: false, error: String(error?.message ?? error)}]; }
    }));
    const endpoints = Object.fromEntries(results);
    if (!endpoints.health.ok && !endpoints.report.ok && !endpoints.strategy.ok) {
      throw new Error("Не удалось получить данные с сервера. Проверьте подключение.");
    }
    const currentTick = endpoints.health.value?.tick ??
      endpoints.report.value?.tick ?? s.health?.tick ?? "unknown";
    const payload = {
      format: "living-sector-observer-diagnostics-v1",
      captured_at: new Date().toISOString(),
      note: "Текущие снимки API и до 1000 последних событий этой вкладки. НЕ полный серверный журнал тиков.",
      source: "Observer UI-1 / GET endpoints / local WebSocket event buffer",
      snapshot_tick_at_export: currentTick,
      browser_events_newest_first: s.events.slice(0, 1000),
      browser_event_count: s.events.length,
      browser_event_capacity: 1000,
      endpoints
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], {type: "application/json;charset=utf-8"});
    const uri = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = uri;
    link.download = "LivingSector-Diagnostics-t" + currentTick + "-" +
      new Date().toISOString().replaceAll(":", "-") + ".json";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(uri), 1000);
  } catch (error) {
    window.alert("Экспорт диагностики: " + String(error?.message ?? error));
  } finally {
    button.textContent = oldText;
    button.disabled = false;
  }
}

function handleEvents(tick, events) {
  for (const event of list(events)) s.events.unshift({tick,event});
  s.events.length = Math.min(s.events.length,1000);
  renderEvents();
}

function handleWs(message) {
  const m = message;
  if (m.tick != null && s.health) s.health.tick = m.tick;
  switch (m.type) {
    case "positions":
      for (const e of list(m.entities)) {
        if (e?.id && Number.isFinite(e.x) && Number.isFinite(e.y))
          s.positions.set(e.id, {x: e.x, y: e.y});
      }
      break;
    case "ship_states":
      s.ships = mergeById(s.ships, m.ships);
      refreshShipCallsigns();
      if (s.report) s.report.ships = s.ships;
      break;
    case "market_states":
      if (s.report) { s.report.markets = mergeById(s.report.markets, m.markets); s.index = buildIndex(s.report); }
      break;
    case "facility_states":
      if (s.report) { s.report.facilities = mergeById(s.report.facilities, m.facilities); s.index = buildIndex(s.report); }
      break;
    case "faction_states":
      if (s.report) { s.report.factions = mergeById(s.report.factions, m.factions); s.index = buildIndex(s.report); }
      break;
    case "population_states":
      if (s.report) { s.report.populations = mergeById(s.report.populations, m.populations); s.index = buildIndex(s.report); }
      break;
    case "events": handleEvents(m.tick, m.events); break;
    case "server_hello":
    case "sim_control_ack":
      if (s.health) {
        s.health.running = m.running;
        s.health.world_speed = m.world_speed;
      }
      break;
    default: break;
  }
}

function connectWs() {
  if (s.ws && (s.ws.readyState === WebSocket.CONNECTING || s.ws.readyState === WebSocket.OPEN)) return;
  const protocol = location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(protocol + "//" + location.host + "/ws");
  s.ws = socket;
  socket.addEventListener("open", () => {
    s.wsUp = true;
    setOnline(true, "Симуляция подключена");
  });
  socket.addEventListener("message", event => {
    try { handleWs(JSON.parse(event.data)); }
    catch (error) { console.warn("Observer: invalid server message", error); }
  });
  socket.addEventListener("close", () => {
    if (s.ws !== socket) return;
    s.wsUp = false;
    setOnline(false, "Связь с симулятором потеряна");
    window.setTimeout(connectWs, 2500);
  });
  socket.addEventListener("error", () => socket.close());
}

async function fetchHealth() {
  try {
    s.health = await getJSON("/api/health");
    setOnline(s.wsUp, s.wsUp ? "Симуляция подключена" : "Ожидание потока…");
    refreshToolbar();
  } catch (error) {
    setOnline(false, "Нет связи с сервером");
    s.error = error.message;
  }
}

async function control(path, value) {
  els.pauseBtn.disabled = true; els.speedSelect.disabled = true;
  try {
    await postJSON(path, value);
    await fetchHealth();
  } catch (error) {
    window.alert("Команда не выполнена: " + error.message);
  } finally {
    els.pauseBtn.disabled = !s.wsUp;
    els.speedSelect.disabled = !s.wsUp;
  }
}

function boundsOf(view) {
  const sys = systemByName(s.systemName, s.index);
  if (view === "system" && sys) {
    const inner= s.cameraFocus==="inner" && canFocusInner(sys);
    const bodies = sys.bodies
      .filter(b => !inner || number(b.orbit_radius) <= innerFocusRadius(sys))
      .map(b => point(b)).filter(Boolean);
    const coords = [{x:sys.x,y:sys.y},...bodies];
    const minX = Math.min(...coords.map(p => p.x)), maxX = Math.max(...coords.map(p=>p.x));
    const minY = Math.min(...coords.map(p => p.y)), maxY = Math.max(...coords.map(p=>p.y));
    const radius = Math.max(1, maxX-minX, maxY-minY);
    return { cx:(minX+maxX)/2, cy:(minY+maxY)/2, sx: Math.max(radius*1.4,3), sy:Math.max(radius*1.4,3) };
  }
  const systems = s.index?.systems ?? [];
  if (!systems.length) return {cx:0,cy:0,sx:60,sy:60};
  const minX = Math.min(...systems.map(p=>p.x)), maxX=Math.max(...systems.map(p=>p.x));
  const minY = Math.min(...systems.map(p=>p.y)), maxY=Math.max(...systems.map(p=>p.y));
  return {
    cx:(minX+maxX)/2,cy:(minY+maxY)/2,
    sx:Math.max((maxX-minX)*1.35,10),
    sy:Math.max((maxY-minY)*1.35,10)
  };
}

function resizeCanvas() {
  const rect = els.map.getBoundingClientRect();
  const w = Math.max(1, rect.width), h = Math.max(1, rect.height);
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  if (pixels.w !== w || pixels.h !== h || els.map.width !== Math.round(w*dpr)) {
    pixels = {w,h};
    els.map.width = Math.round(w*dpr);
    els.map.height = Math.round(h*dpr);
  }
  ctx.setTransform(dpr,0,0,dpr,0,0);
  return {w,h};
}

function camera(w,h) {
  const b = boundsOf(s.view);
  const scale = Math.min(w / b.sx, h / b.sy) * s.zoom * 0.84;
  if(s.follow && s.view==="system"){
    const target=followedWorldPosition();
    if(target) {
      s.pan=panToFollowWorldPoint(target,b,scale);
    }
  }
  return {
    scale,
    toScreen: p => ({
      x: w/2 + (p.x - b.cx) * scale + s.pan.x,
      y: h/2 - (p.y - b.cy) * scale + s.pan.y
    })
  };
}
function inCanvas(p,w,h,pad=15) {
  return p.x >= -pad && p.y >= -pad && p.x <= w+pad && p.y <= h+pad;
}
function drawGrid(w,h,cam) {
  // World-anchored grid. It moves with the map, rather than staying
  // fixed to the viewer's screen while planets slide over it.
  if (!cam || !(cam.scale>0)) return;
  const step=worldGridStep(cam.scale,92);
  const pitch=step*cam.scale;
  if (!(pitch>=20) || !Number.isFinite(pitch)) return;
  const zero=cam.toScreen({x:0,y:0});
  const offset=(value)=>((value%pitch)+pitch)%pitch;
  ctx.save();
  ctx.strokeStyle=s.view==="sector"?"rgba(85,120,149,.10)":"rgba(85,120,149,.065)";
  ctx.lineWidth=1;
  for(let x=offset(zero.x);x<w;x+=pitch){
    ctx.beginPath();ctx.moveTo(Math.round(x)+.5,0);ctx.lineTo(Math.round(x)+.5,h);ctx.stroke();
  }
  for(let y=offset(zero.y);y<h;y+=pitch){
    ctx.beginPath();ctx.moveTo(0,Math.round(y)+.5);ctx.lineTo(w,Math.round(y)+.5);ctx.stroke();
  }
  ctx.restore();
}
function withMapScale(at,scale,draw) {
  if (scale===1) {draw();return;}
  ctx.save();ctx.translate(at.x,at.y);ctx.scale(scale,scale);
  ctx.translate(-at.x,-at.y);draw();ctx.restore();
}
function drawBackdrop(w,h) {
  const bg=ctx.createRadialGradient(w*.5,h*.4,10,w*.5,h*.4,Math.max(w,h)*.9);
  bg.addColorStop(0,"#102336");
  bg.addColorStop(.55,"#0a1725");
  bg.addColorStop(1,"#06101b");
  ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);
  // Purely decorative distant specks; never interactable or simulated stars.
  // Deterministic per screen size so the stars don't flicker across frames.
  for(let i=1;i<=88;i++){
    const sx=((Math.sin(i*127.1)*43758.5453)%1+1)%1*w;
    const sy=((Math.sin(i*311.7)*23421.123)%1+1)%1*h;
    const a=.06+.13*((Math.sin(i*72.8)*2654)%1+1)%1;
    ctx.fillStyle="rgba(177,204,223,"+a+")";
    ctx.fillRect(sx,sy,i%13===0?1.8:1,i%13===0?1.8:1);
  }
}
function circle(x,y,r,color,fill=true) {
  ctx.beginPath();ctx.arc(x,y,r,0,2*Math.PI);
  if(fill){ctx.fillStyle=color;ctx.fill();}else{ctx.strokeStyle=color;ctx.stroke();}
}
function label(pos,text,color="#bdceda",font=11) {
  ctx.fillStyle=color;ctx.font=font+"px Segoe UI, sans-serif";
  ctx.textAlign="center";ctx.fillText(String(text),pos.x,pos.y);
}
function textChip(x,y,text,accent="#a5c0d0",max=170) {
  ctx.save();
  ctx.font="11px Segoe UI, sans-serif";
  const labelText=String(text ?? "").slice(0,42);
  const ww=Math.min(max,ctx.measureText(labelText).width+16);
  ctx.fillStyle="rgba(6,17,28,.88)";
  ctx.strokeStyle="rgba(74,106,123,.28)";
  ctx.lineWidth=1;
  ctx.beginPath();ctx.roundRect(x,y-10,ww,20,4);ctx.fill();ctx.stroke();
  ctx.fillStyle=accent;ctx.textAlign="left";ctx.textBaseline="middle";
  ctx.fillText(labelText,x+8,y,ww-14);
  ctx.restore();
}
function drawOrbits(sys,toScreen,scale,w,h) {
  const center=toScreen(sys);
  const radii=[...new Set(sys.bodies.map(body=>{
    const p=point(body);
    return p ? Math.round(Math.hypot(p.x-sys.x,p.y-sys.y)*scale) : 0;
  }).filter(r=>r>12&&r<Math.max(w,h)*2))].sort((a,b)=>a-b);
  ctx.save();ctx.lineWidth=1;
  for(const radius of radii.slice(0,12)){
    ctx.beginPath();ctx.setLineDash([2,8]);
    ctx.strokeStyle="rgba(108,145,164,.13)";
    ctx.arc(center.x,center.y,radius,0,Math.PI*2);ctx.stroke();
  }
  ctx.restore();
}
function drawSun(at) {
  ctx.save();
  const glow=ctx.createRadialGradient(at.x,at.y,1,at.x,at.y,35);
  glow.addColorStop(0,"rgba(236,191,112,.35)");
  glow.addColorStop(1,"rgba(236,191,112,0)");
  ctx.fillStyle=glow;ctx.beginPath();ctx.arc(at.x,at.y,35,0,Math.PI*2);ctx.fill();
  if(!drawPlanetSprite(planetTextures.get("sun"),at.x,at.y,30)){
    circle(at.x,at.y,12,"#e7bf78");
    circle(at.x,at.y,13,"rgba(255,222,165,.55)",false);
  }
  ctx.restore();
}
function bodyColor(body){
  const biome=String(body.biome??"").toLowerCase();
  if(body.type==="moon" || biome==="lifeless")return "#a8b5c9";
  if(body.type==="belt" || body.type==="asteroid" || biome==="asteroid")return "#cba16c";
  if(biome==="terrestrial")return "#4b9cc4";
  if(biome==="desert" || biome==="molten")return "#bd8066";
  if(biome==="gas_giant")return "#c4ae85";
  return "#8eb0c7";
}
function drawBody(body,p,selected=false){
  const tint=bodyColor(body);
  const belt=body.type==="belt"||body.type==="asteroid";
  const giant=body.biome==="gas_giant";
  const saturn=body.id==="saturn";
  const r=belt?8:giant?12:body.type==="moon"?6:9;
  ctx.save();
  if(belt){
    ctx.strokeStyle="rgba(210,174,113,.58)";ctx.lineWidth=1;
    ctx.beginPath();ctx.ellipse(p.x,p.y,13,7,-.4,0,Math.PI*2);ctx.stroke();
    circle(p.x-5,p.y+1,3.3,tint);circle(p.x+3,p.y-3,4,tint);circle(p.x+6,p.y+3,2.4,tint);
  }else if(drawPlanetSprite(planetTextures.get(planetTextureKey(body)),p.x,p.y,r*2.6)){
    // The texture includes the natural outline; do not double-shade it.
  }else{
    if(saturn){
      ctx.lineWidth=4;ctx.strokeStyle="rgba(198,170,125,.42)";
      ctx.beginPath();ctx.ellipse(p.x,p.y,21,8,-0.35,Math.PI,2*Math.PI);ctx.stroke();
    }
    const shading=ctx.createLinearGradient(p.x-r,p.y-r,p.x+r,p.y+r);
    shading.addColorStop(0,"#e5e0ce");shading.addColorStop(0.27,tint);
    shading.addColorStop(1,"#172534");
    circle(p.x,p.y,r,shading);
    ctx.save();ctx.beginPath();ctx.arc(p.x,p.y,r-0.35,0,2*Math.PI);ctx.clip();
    if(giant){
      ctx.strokeStyle="rgba(101,66,41,.42)";ctx.lineWidth=2.1;
      for(let band=-2;band<=2;band++){
        const y=p.y+band*3.3;
        ctx.beginPath();ctx.moveTo(p.x-r-2,y);ctx.lineTo(p.x+r+2,y+1.0);ctx.stroke();
      }
    }else if(body.type==="moon"){
      for(const [dx,dy,rr] of [[-1.6,-1,1.5],[2.5,1.5,1.1],[-2,2.3,0.8]]){
        ctx.strokeStyle="rgba(24,48,64,.31)";ctx.lineWidth=.85;
        ctx.beginPath();ctx.arc(p.x+dx,p.y+dy,rr,0,2*Math.PI);ctx.stroke();
      }
    }else if(body.id==="earth"){
      ctx.strokeStyle="rgba(93,174,130,.8)";ctx.lineWidth=2.8;
      ctx.beginPath();ctx.moveTo(p.x-5,p.y-2);ctx.lineTo(p.x-1,p.y-3);
      ctx.lineTo(p.x+1,p.y+0);ctx.moveTo(p.x+3,p.y+2);ctx.lineTo(p.x+6,p.y+4);ctx.stroke();
    }
    ctx.restore();
    if(saturn){
      ctx.lineWidth=3.2;ctx.strokeStyle="rgba(230,206,158,.72)";
      ctx.beginPath();ctx.ellipse(p.x,p.y,21,8,-0.35,0,Math.PI);ctx.stroke();
    }
  }
  if(selected||body.contested){
    ctx.lineWidth=1.4;circle(p.x,p.y,r+7,selected?"#bce8df":"#dfb472",false);
  }
  ctx.restore();
}
// Resource signature comes from the actual celestial body's richness map.
// It is NOT a claim about a specific recipe currently running at the plant.
function naturalResourcesAt(fac){
  if(!fac?.body_id||!s.index)return [];
  for(const sys of s.index.systems){
    const body=sys.bodies.find(b=>b.id===fac.body_id);
    if(body)return Object.entries(body.resources??{}).filter(([,q])=>Number(q)>0)
      .sort((a,b)=>Number(b[1])-Number(a[1]));
  }
  return [];
}
function primaryNaturalResource(fac){
  if(fac?.type==="salvage_field")return "salvage";
  if(fac?.type==="gas_harvester")return "gas";
  const measured=naturalResourcesAt(fac)[0]?.[0];
  if(measured)return measured;
  // The S7 Observer snapshot does not include planetary resource richness.
  // Names can influence pictograms, but NEVER claim a measured yield.
  const label=String(fac?.name??"").toLowerCase();
  if(/gas|газ|атмосфер/.test(label))return "gas";
  if(/ice|cryo|л[её]д|крио/.test(label))return "ice";
  if(/ore|руд|шахт|belt|астероид/.test(label))return "ore";
  return null;
}
function drawFacilityHub(at,kind,selected,fac=null,visual={}){
  const info=facilityMeta(kind), tint=selected?"#eafdf4":info.tone;
  const source=primaryNaturalResource(fac);
  ctx.save();ctx.translate(at.x,at.y);
  ctx.lineWidth=selected?2:1.5;ctx.lineCap="round";ctx.lineJoin="round";
  ctx.strokeStyle=tint;ctx.fillStyle="#0b202d";
  if(fac?.abandoned)ctx.globalAlpha=.52;
  const outline=(points)=>{
    ctx.beginPath();ctx.moveTo(points[0][0],points[0][1]);
    for(const [x,y] of points.slice(1))ctx.lineTo(x,y);
    ctx.closePath();ctx.fill();ctx.stroke();
  };
  const lines=(segments)=>{ctx.beginPath();for(const [a,b,c,d] of segments){
    ctx.moveTo(a,b);ctx.lineTo(c,d);
  }ctx.stroke();};
  switch(kind){
    case "station":
      outline([[-11,-7],[-5,-10],[5,-10],[11,-7],[11,7],[5,10],[-5,10],[-11,7]]);
      lines([[-6,0,6,0],[-2,-10,-2,-14],[2,-10,2,-14]]);break;
    case "shipyard": case "repair_dock":
      outline([[-12,-10],[-6,-10],[-6,5],[6,5],[6,-10],[12,-10],[12,11],[-12,11]]);
      lines([[-3,-3,0,-7],[0,-7,3,-3],[0,-7,0,4]]);break;
    case "mining_rig": case "salvage_field":
      if(source==="gas"){
        // Gas gathering: compression manifold and paired pressure tanks.
        outline([[0,-12],[10,-6],[10,7],[0,12],[-10,7],[-10,-6]]);
        ctx.beginPath();ctx.ellipse(-4,1,3,7,0,0,Math.PI*2);ctx.stroke();
        ctx.beginPath();ctx.ellipse(4,1,3,7,0,0,Math.PI*2);ctx.stroke();
      }else if(source==="ice"){
        // Ice drilling: a crystalline core and a downward bore.
        outline([[0,-12],[11,0],[0,12],[-11,0]]);
        lines([[0,-7,6,0],[6,0,0,7],[0,7,-6,0],[-6,0,0,-7],[0,7,0,12]]);
      }else if(source==="salvage"){
        // Salvage: two open mechanical jaws, not a generic miner.
        outline([[-12,-10],[-5,-10],[-5,-3],[5,-3],[5,-10],[12,-10],[9,8],[-9,8]]);
        lines([[-7,-7,-3,1],[7,-7,3,1],[-4,4,4,4]]);
      }else if(source==="ore"){
        // Ore: excavating picks angled toward the central drilling mast.
        outline([[0,-12],[12,0],[0,12],[-12,0]]);
        lines([[-8,0,-2,-6],[-2,-6,0,5],[8,0,2,-6],[2,-6,0,5]]);
      }else{
        // Neutral extraction silhouette when the API provides no ore/ice/gas.
        outline([[-11,-9],[-5,-9],[-5,2],[5,2],[5,-9],[11,-9],[11,9],[-11,9]]);
        lines([[-6,5,6,5],[0,-6,0,5]]);
      }
      break;
    case "gas_harvester":
      outline([[0,-11],[9,-5],[9,5],[0,11],[-9,5],[-9,-5]]);
      lines([[-10,0,10,0],[-3,-6,3,-6],[-3,6,3,6]]);break;
    case "refinery": case "smelter":
      // Processing != extraction. Two reaction vessels are distinct from
      // drills/jaws above; local resource has a subtle vessel variant.
      ctx.beginPath();ctx.roundRect(-12,-10,24,20,3);ctx.fill();ctx.stroke();
      if(source==="gas"){
        for(const x of [-5,5]){
          ctx.beginPath();ctx.ellipse(x,0,3.5,7,0,0,Math.PI*2);ctx.stroke();
        }
        lines([[-8,7,8,7],[-8,-7,8,-7]]);
      }else if(source==="ice"){
        ctx.beginPath();ctx.moveTo(0,-7);ctx.lineTo(7,0);ctx.lineTo(0,7);ctx.lineTo(-7,0);ctx.closePath();ctx.stroke();
        lines([[-9,0,9,0],[0,-9,0,9]]);
      }else if(kind==="smelter"){
        // Smelter is a specifically metallurgical silhouette.
        ctx.beginPath();ctx.roundRect(-7,0,14,7,1);ctx.stroke();
        lines([[-7,0,-7,-5],[0,0,0,-8],[7,0,7,-4],[-4,4,4,4]]);
      }else{
        // Generic refinery handles several recipes, not necessarily ore.
        lines([[-6,-5,-6,7],[0,-7,0,7],[6,-5,6,7],[-9,4,9,4]]);
      }
      break;
    case "factory":
      outline([[-12,-4],[-5,-10],[1,-4],[7,-10],[12,-4],[12,10],[-12,10]]);
      lines([[-7,3,7,3],[-7,7,7,7]]);break;
    case "farm":
      ctx.beginPath();ctx.roundRect(-11,-11,22,22,8);ctx.fill();ctx.stroke();
      ctx.beginPath();ctx.ellipse(1,-1,4,8,-.6,0,2*Math.PI);ctx.stroke();
      lines([[-5,7,6,-7]]);break;
    case "cargo_warehouse": case "warehouse":
      outline([[-12,-10],[12,-10],[12,10],[-12,10]]);
      lines([[-7,-5,7,-5],[-7,0,7,0],[-7,5,7,5],[0,-9,0,9]]);break;
    case "fuel_depot":
      outline([[-12,-9],[12,-9],[12,9],[-12,9]]);
      for(const x of [-5,5]){ctx.beginPath();ctx.ellipse(x,0,3.5,7,0,0,Math.PI*2);ctx.stroke();}break;
    case "patrol_base":
      outline([[0,-12],[11,-8],[9,5],[0,12],[-9,5],[-11,-8]]);
      lines([[-6,0,6,0],[0,-6,0,6]]);break;
    case "observation_station":
      outline([[-12,-6],[0,-10],[12,-6],[12,6],[0,10],[-12,6]]);
      ctx.beginPath();ctx.arc(0,0,4,0,Math.PI*2);ctx.stroke();break;
    case "solar_power_station":
      outline([[-12,-10],[12,-10],[12,10],[-12,10]]);
      lines([[-4,-10,-4,10],[4,-10,4,10],[-12,0,12,0]]);break;
    case "gate": case "jump_gate":
      ctx.beginPath();ctx.arc(0,0,11,.4,Math.PI*1.85);ctx.stroke();
      ctx.beginPath();ctx.arc(0,0,6,0,Math.PI*2);ctx.stroke();break;
    default:
      ctx.beginPath();ctx.roundRect(-10,-9,20,18,3);ctx.fill();ctx.stroke();
      lines([[-5,0,5,0]]);
  }
  // A small colored anchor identifies the faction. Main silhouette color
  // identifies the role; neither is inferred from a facility's display name.
  if(fac?.faction_id && s.index){
    const ownerColor=factionColor(fac.faction_id,s.index);
    ctx.fillStyle=ownerColor;ctx.strokeStyle="#0b202d";ctx.lineWidth=.8;
    ctx.beginPath();ctx.arc(-10,10,3.1,0,2*Math.PI);ctx.fill();ctx.stroke();
  }
  if(fac && !fac.abandoned && Number.isFinite(Number(fac.condition)) && number(fac.condition)<.35){
    ctx.fillStyle="#de795d";ctx.beginPath();ctx.arc(11,10,3.2,0,Math.PI*2);ctx.fill();
  }
  if(visual.major && kind==="station"){
    // Four corners + faction ring identify a major hub. The interior
    // remains the same station glyph as every other station.
    const ownerTint=factionColor(fac?.faction_id,s.index);
    ctx.strokeStyle=ownerTint;ctx.lineWidth=2.2;
    for(const [a,b] of [[-.22,.22],[1.35,1.79],[2.95,3.38],[4.55,5.0]]){
      ctx.beginPath();ctx.arc(0,0,17,a,b);ctx.stroke();
    }
    ctx.fillStyle=ownerTint;
    for(const x of [-12,12])ctx.fillRect(x-2,13,4,3);
  }
  if(selected){ctx.strokeStyle="rgba(177,238,221,.52)";ctx.lineWidth=1;
    ctx.beginPath();ctx.arc(0,0,20,0,2*Math.PI);ctx.stroke();}
  ctx.restore();
}
// World-state scaffold: does not spawn, progress, or move any simulation entity.
function drawSite(site,at,selected){
  const ratio=Math.max(0,Math.min(1,number(site.progress)));
  ctx.save();ctx.translate(at.x,at.y);
  ctx.fillStyle="rgba(16,32,39,.96)";ctx.strokeStyle=selected?"#eaffdc":"#dcaf70";
  ctx.lineWidth=1.3;ctx.setLineDash([3,3]);ctx.strokeRect(-10,-10,20,20);
  ctx.setLineDash([]);
  ctx.beginPath();ctx.moveTo(-7,7);ctx.lineTo(-7,-3);ctx.lineTo(0,-7);
  ctx.lineTo(7,-3);ctx.lineTo(7,7);ctx.stroke();
  ctx.fillStyle="#0b202c";ctx.fillRect(-11,13,22,5);
  ctx.fillStyle="#d7ad6c";ctx.fillRect(-10,14,20*ratio,3);
  ctx.restore();
}

function liveWorldPoint(entity) {
  const target=liveEntityPoint(entity,s.positions);
  if(!target)return null;
  const id=String(entity.id??entity.body_id??"unknown");
  const old=s.mapWorldPositions.get(id);
  const next=approachWorldPoint(old,target);
  s.mapWorldPositions.set(id,next);
  return next;
}
function isSelected(type,id) {
  return s.selection?.type===type && s.selection.id===id;
}
function addTarget(type,id,x,y,r,name,ids=null) {
  s.targets.push({type,id,x,y,r,name,ids});
}
function changeZoomAt(cursor, factor) {
  const oldZoom = s.zoom;
  const newZoom = Math.max(0.35, Math.min(30, oldZoom * factor));
  if (newZoom === oldZoom) return;
  const r = els.map.getBoundingClientRect();
  s.pan = panForCursorZoom(s.pan,cursor,{w:r.width,h:r.height},oldZoom,newZoom);
  s.zoom = newZoom;
}
function smoothPosition(ship, target) {
  if(!target)return null;
  const old=s.visualPositions.get(ship.id);
  if(!old) {
    s.visualPositions.set(ship.id,{...target});
    s.shipMotion.set(ship.id,{dx:0,dy:0});
    return target;
  }
  const dist=Math.hypot(target.x-old.x,target.y-old.y);
  // No artificial flight trails across gates / large simulation teleports.
  if(dist>5){
    s.visualPositions.set(ship.id,{...target});
    s.shipMotion.set(ship.id,{dx:0,dy:0});
    return target;
  }
  const oldX=old.x,oldY=old.y;
  old.x+=(target.x-old.x)*0.17;
  old.y+=(target.y-old.y)*0.17;
  s.shipMotion.set(ship.id,{dx:old.x-oldX,dy:old.y-oldY});
  return old;
}
// Tactical map glyphs: family-by-role, individual geometry variants per stable callsign.
// Inspired by the readable visual grammar of X4's holomap; not copied assets.
function shipGlyphVariant(ship) {
  const value = s.shipSymbolVariants.get(ship?.id);
  return Number.isFinite(value) ? Math.max(0,value) : 0;
}
// Heading is based on the persistent journey vector (departure → current
// simulated world coordinate), not a tiny screen-space interpolation delta.
// Keep the previous angle when the server reports unchanged coordinates.
function shipHeadingAngle(ship, inFlight) {
  const last=s.shipHeading.get(ship.id);
  if(!inFlight)return last?.angle ?? 0;
  const origin=ship.transit?.departure_position;
  const current=positionOf(ship,s.positions);
  let angle=null;
  if(Array.isArray(origin)&&origin.length>=2&&current){
    const dx=current.x-number(origin[0]),dy=-(current.y-number(origin[1]));
    if(Math.hypot(dx,dy)>.07)angle=Math.atan2(dy,dx)+Math.PI/2;
  }
  // Fallback: a stable reported screen direction, never a one-frame zero.
  if(angle===null){
    const motion=s.shipMotion.get(ship.id);
    if(motion&&Math.hypot(motion.dx,motion.dy)>.006)
      angle=Math.atan2(-motion.dy,motion.dx)+Math.PI/2;
  }
  if(angle===null)return last?.angle ?? 0;
  if(!last){s.shipHeading.set(ship.id,{angle});return angle;}
  const delta=Math.atan2(Math.sin(angle-last.angle),Math.cos(angle-last.angle));
  const smoothed=last.angle+delta*.19;
  last.angle=smoothed;
  return smoothed;
}
function drawShip(ship,at,color,selected,scale=1) {
  ctx.save();ctx.translate(at.x,at.y);
  const inFlight=scale>0&&Boolean(ship.transit);
  const rotation=shipHeadingAngle(ship,inFlight);
  const move=s.shipMotion.get(ship.id);
  const mx=(move?.dx??0)*scale,my=-(move?.dy??0)*scale;
  const speed=Math.hypot(mx,my);
  if(inFlight && speed>.08){
    const unitX=mx/speed,unitY=my/speed;
    const trail=ctx.createLinearGradient(0,0,-unitX*19,-unitY*19);
    trail.addColorStop(0,"rgba(112,210,221,.55)");
    trail.addColorStop(1,"rgba(112,210,221,0)");
    ctx.strokeStyle=trail;ctx.lineWidth=2.1;ctx.beginPath();
    ctx.moveTo(-unitX*5,-unitY*5);ctx.lineTo(-unitX*19,-unitY*19);ctx.stroke();
  }
  // Even when motion is momentarily zero the nose stays on its route.
  ctx.rotate(rotation);
  // Same 24x24 icon grid for every role. Scale and selection affect readability,
  // never the simulated position, facing, speed or cargo capacity.
  ctx.scale(selected?1.12:1,selected?1.12:1);
  const role=String(ship.class??"").toLowerCase();
  const variant=shipGlyphVariant(ship);
  const feature=variant%4;
  ctx.lineJoin="round";ctx.lineCap="round";
  const outline=()=>{ctx.fillStyle=color;ctx.fill();ctx.lineWidth=1.35;
    ctx.strokeStyle="#d8edf2";ctx.stroke();};
  const body=(pts)=>{
    ctx.beginPath();ctx.moveTo(pts[0][0],pts[0][1]);
    for(const p of pts.slice(1))ctx.lineTo(p[0],p[1]);
    ctx.closePath();outline();
  };
  const detail=(stroke="#142638",lineWidth=1.3)=>{ctx.strokeStyle=stroke;
    ctx.lineWidth=lineWidth;ctx.beginPath();};
  if(role==="courier"){
    // Small pointed messenger: high nose, tucked aft wings.
    body([[0,-10], [5,-3], [7,7], [1,4], [0,8], [-1,4], [-7,7],[-5,-3]]);
    detail();ctx.moveTo(0,-6);ctx.lineTo(0,2);ctx.moveTo(-3,3);ctx.lineTo(3,3);ctx.stroke();
  }else if(role==="freighter"){
    // Medium transport: armored cargo rectangle and broad shoulders.
    body([[0,-10],[7,-6],[9,2],[8,9],[-8,9],[-9,2],[-7,-6]]);
    detail();ctx.moveTo(-5,-2);ctx.lineTo(5,-2);
    ctx.moveTo(-5,4);ctx.lineTo(5,4);ctx.stroke();
  }else if(role==="hauler"){
    // Huge heavy transporter: two external cargo banks.
    body([[0,-10],[4,-7],[4,8],[1,10],[-1,10],[-4,8],[-4,-7]]);
    ctx.fillStyle=color;ctx.strokeStyle="#d8edf2";ctx.lineWidth=1.2;
    ctx.fillRect(-12,-4,6,13);ctx.strokeRect(-12,-4,6,13);
    ctx.fillRect(6,-4,6,13);ctx.strokeRect(6,-4,6,13);
    detail();ctx.moveTo(0,-6);ctx.lineTo(0,7);ctx.stroke();
  }else if(role==="tanker"){
    // Tanker: narrow central frame, clearly rounded pressurized tanks.
    body([[0,-10],[4,-6],[4,8],[0,11],[-4,8],[-4,-6]]);
    ctx.fillStyle=color;ctx.strokeStyle="#d8edf2";ctx.lineWidth=1.25;
    for(const x of [-9,9]){ctx.beginPath();ctx.ellipse(x,3,3.1,7,0,0,Math.PI*2);
      ctx.fill();ctx.stroke();}
    detail();ctx.moveTo(-3,0);ctx.lineTo(3,0);ctx.stroke();
  }else if(role==="miner"){
    // Mining ship: fork/jaws at nose; short, industrial workboat.
    body([[-9,-10],[-3,-10],[-2,-4],[2,-4],[3,-10],[9,-10],[7,4],
      [4,9],[-4,9],[-7,4]]);
    detail();ctx.moveTo(-4,1);ctx.lineTo(4,1);ctx.moveTo(0,1);ctx.lineTo(0,7);ctx.stroke();
  }else{
    // Unknown class: distinct neutral scout marker, no class inference.
    body([[0,-11],[7,7],[0,3],[-7,7]]);
  }
  // Individuality layer: class silhouette remains the primary identifier.
  // Variants distinguish ships of the same class without fake role changes.
  ctx.strokeStyle="#edfaff";ctx.lineWidth=1.25;ctx.beginPath();
  if(feature===0){
    ctx.moveTo(-3,6);ctx.lineTo(-3,8);
    ctx.moveTo(3,6);ctx.lineTo(3,8);
  }else if(feature===1){
    ctx.moveTo(-2,-5);ctx.lineTo(2,-5);
    ctx.moveTo(-2,-3);ctx.lineTo(2,-3);
  }else if(feature===2){
    ctx.moveTo(-8,2);ctx.lineTo(-11,4);
    ctx.moveTo(8,2);ctx.lineTo(11,4);
  }else{
    ctx.moveTo(-3,5);ctx.lineTo(3,5);
    ctx.moveTo(0,3);ctx.lineTo(0,8);
  }
  ctx.stroke();
  // Secondary bank of variants for >4 ships of a role; avoids repetitive glyphs.
  if(variant>=4){
    const stripe=variant%3;
    ctx.fillStyle="#eef5e5";
    ctx.fillRect(-3+(stripe*2),-1,1.65,2.35);
  }
  if(selected){ctx.lineWidth=1.1;ctx.strokeStyle="#b0eddd";
    ctx.beginPath();ctx.arc(0,0,15.5,0,2*Math.PI);ctx.stroke();}
  ctx.restore();
}

function renderMap() {
  const {w,h}=resizeCanvas();
  ctx.clearRect(0,0,w,h);drawBackdrop(w,h);
  s.targets=[];
  if(!s.index){window.requestAnimationFrame(renderMap);return;}
  const cam=camera(w,h);
  drawGrid(w,h,cam);
  const {toScreen,scale} = cam;
  // Buildings are UI markers, not kilometer-scale geometry. Avoid icon
  // explosion when zooming while retaining readable planetary texture sizes.
  const iconScale=Math.min(1.2,mapIconScale(s.zoom));
  const planetScale=Math.min(2.3,mapIconScale(s.zoom)*1.15);
  const visible = (p,pad=12) => inCanvas(p,w,h,pad);
  const sysMap=new Map(s.index.systems.map(system => [system.name,system]));
  const showLabels=els.labelsToggle.checked;
  const showShips=els.shipsToggle.checked;
  const hubAnchors=new Map();
  const labelRequests=[];
  const markerObstacles=[];
  const markGlyph=(p,r)=>markerObstacles.push({
    x:p.x-r,y:p.y-r,w:r*2,h:r*2
  });
  const askLabel=(id,p,name,color,priority,radius=15,max=165,plain=false)=>{
    if(!showLabels)return;
    const text=String(name??"").slice(0,42);
    ctx.save();ctx.font="11px Segoe UI, sans-serif";
    const width=Math.min(max,ctx.measureText(text).width+(plain?8:16));
    ctx.restore();
    labelRequests.push({id,x:p.x,y:p.y,w:width,h:plain?16:20,
      text,color,priority,radius:radius*iconScale,plain,max});
  };

  if(s.view==="sector"){
    if(els.linksToggle.checked){
      for(const link of s.index.gateLinks){
        const a=sysMap.get(link.a),b=sysMap.get(link.b);
        if(!a||!b)continue;
        const p=toScreen(a),q=toScreen(b);
        ctx.setLineDash([5,7]);ctx.lineWidth=1.1;ctx.strokeStyle="rgba(121,166,177,.38)";
        ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.stroke();ctx.setLineDash([]);
      }
    }
    for(const system of s.index.systems){
      const p=toScreen(system);if(!visible(p,40))continue;
      const own=system.ownership;
      const tint=own.kind==="single"?factionColor(own.factionId,s.index):"#8195a6";
      circle(p.x,p.y,17,tint+"28");
      ctx.lineWidth=own.kind==="mixed"?2.1:1.3;
      circle(p.x,p.y,11,own.kind==="mixed"?"#dbad70":tint,false);
      circle(p.x,p.y,4.5,tint);
      if(isSelected("system",system.name)){ctx.lineWidth=1.7;circle(p.x,p.y,23,"#bbefe5",false);}
      if(showLabels)label({x:p.x,y:p.y+29},system.name);
      addTarget("system",system.name,p.x,p.y,15,system.name);
    }
  }else{
    const sys=systemByName(s.systemName,s.index);
    if(sys){
      const center=toScreen({x:sys.x,y:sys.y});
      drawOrbits(sys,toScreen,scale,w,h);
      withMapScale(center,planetScale,()=>drawSun(center));
      markGlyph(center,19*planetScale);
      askLabel("sun-"+sys.name,center,sys.name+" · звезда","#eed09a",50,17,140);
      // The occupied discs keep station/module glyphs off planet artwork.
      // Body labels are laid out later against all markers.
      const celestialObstacles=[{x:center.x,y:center.y,r:20*planetScale}];
      for(const body of sys.bodies){
        const p=liveWorldPoint(body);if(!p)continue;const screen=toScreen(p);
        if(!visible(screen,70))continue;
        withMapScale(screen,planetScale,()=>drawBody(body,screen,isSelected("body",body.id)));
        const rr=(body.type==="belt"||body.type==="asteroid"?15:
          body.biome==="gas_giant"?17:body.type==="moon"?9:13)*planetScale;
        celestialObstacles.push({x:screen.x,y:screen.y,r:rr});
        markGlyph(screen,rr);
        askLabel("body-"+body.id,screen,bodyDisplayName(body),"#bdcfdc",40,rr/Math.max(.1,iconScale),135,true);
        addTarget("body",body.id,screen.x,screen.y,Math.max(13,rr),bodyDisplayName(body));
      }
      const occupiedMarkers=[];
      const attachedConstructionSites=new Set();
      const renderedStationOrbits=new Set();
      // Find a nearby screen-only marker position without overlapping planets.
      // The real ECS location stays untouched; a short connector indicates
      // the actual anchoring when the icon must be displaced.
      const layoutMarker=(origin,r,priority=0)=>{
        const blocked=[...celestialObstacles,...occupiedMarkers];
        const accepts=pt=>pt.x>r+5&&pt.y>r+5&&pt.x<w-r-5&&pt.y<h-r-5&&
          blocked.every(ob=>Math.hypot(pt.x-ob.x,pt.y-ob.y)>=ob.r+r+5);
        if(accepts(origin))return origin;
        const rings=priority===0?[30,48,68,91,114,140,167]:[23,38,53,72,96,121,148,174];
        let best=null,score=Infinity;
        for(const dist of rings){
          for(let j=0;j<24;j++){
            const a=2*Math.PI*j/24;
            const pt={x:origin.x+Math.cos(a)*dist,y:origin.y+Math.sin(a)*dist};
            if(!accepts(pt))continue;
            // Prefer compact, horizontal placements without covering the planet.
            const cost=dist+Math.abs(Math.sin(a))*6;
            if(cost<score){best=pt;score=cost;}
          }
          if(best)break;
        }
        return best;
      };
      const leader=(origin,pt)=>{
        if(Math.hypot(origin.x-pt.x,origin.y-pt.y)<3)return;
        ctx.save();ctx.strokeStyle="rgba(117,166,184,.42)";
        ctx.lineWidth=1;ctx.setLineDash([3,4]);
        ctx.beginPath();ctx.moveTo(origin.x,origin.y);ctx.lineTo(pt.x,pt.y);
        ctx.stroke();ctx.restore();
      };
      // A location remains one physical site. Satellite symbols are
      // selectable UI offsets, not invented facility positions.
      for(const hub of groupFacilitiesByLocation(
        s.index.systemFacilities.get(sys.name)??[])){
        const members=[...hub.members].sort(facilityOrder);
        const prefer=members[0];
        const p=liveWorldPoint(prefer);
        if(!p)continue;
        const actual=toScreen(p);
        if(!visible(actual,75))continue;
        // Show the real local orbit around the parent body, rather
        // than a connector line to a displaced screen-space menu.
        if(!renderedStationOrbits.has(prefer.body_id)){
          const parent=sys.bodies.find(body=>body.id===prefer.body_id);
          const parentPos=parent?liveWorldPoint(parent):null;
          if(parentPos){
            const parentScreen=toScreen(parentPos);
            const r=Math.hypot(p.x-parentPos.x,p.y-parentPos.y)*scale;
            if(r>4 && r<Math.max(w,h)){
              ctx.save();
              ctx.setLineDash([3,6]);ctx.lineWidth=1;
              ctx.strokeStyle="rgba(119,183,197,.24)";
              ctx.beginPath();ctx.arc(parentScreen.x,parentScreen.y,r,0,Math.PI*2);
              ctx.stroke();ctx.restore();
              renderedStationOrbits.add(prefer.body_id);
            }
          }
        }
        // One actual location is one station complex. Screen-space sockets
        // are visual annotations, never simulated additional facilities.
        const stationCore=members.some(m=>m.type==="station");
        const building=stationCore ? list(s.report?.construction_sites).filter(site=>
          site.location===hub.location && site.body_id===prefer.body_id) : [];
        for(const site of building)attachedConstructionSites.add(site.id);
        const tier=visualStationTier(members,building);
        const visualModules=members.filter(m=>m.id!==prefer.id)
          .map(m=>({...m,__selected:isSelected("facility",m.id)}))
          .concat(building.map(site=>({...site,__site:true,
            __selected:isSelected("construction_site",site.id)})));
        const composeScale=stationScale(s.zoom);
        const reveal=els.modulesToggle.checked ?
          Math.max(stationCore && members.some(m=>isSelected("facility",m.id)) ? .55 : 0,
            stationReveal(s.zoom)) : 0;
        const footprint=stationCore?
          Math.max(18*composeScale,reveal>.08?56*composeScale:0):16*iconScale;
        // This is the physical station's actual server/world position.
        // Never push the entire complex into a free screen slot when
        // planets move; only its text label may move or disappear.
        const at=actual;
        occupiedMarkers.push({x:at.x,y:at.y,r:footprint});
        const ids=members.map(x=>x.id);
        const selected=ids.includes(s.selection?.id) ||
          (s.selection?.type==="facility_group" &&
          s.selection.ids?.some(id=>ids.includes(id)));
        const primary=hubTier(members)==="major";
        let moduleTargets=[];
        if(stationCore){
          const drawn=drawStationComplex(ctx,{x:at.x,y:at.y,tier,zoom:s.zoom,
            tint:factionColor(prefer.faction_id,s.index),selected,
            modules:visualModules,showModules:els.modulesToggle.checked});
          moduleTargets=drawn.moduleTargets;
          markGlyph(at,Math.max(17*composeScale,footprint*.72));
        }else{
          // Industrial/extraction location without a station is NOT a new station.
          withMapScale(at,iconScale,()=>drawFacilityHub(at,prefer.type,selected,prefer));
          markGlyph(at,14*iconScale);
        }
        const coreTargetType=members.length>1?"facility_group":"facility";
        addTarget(coreTargetType,members.length>1?hub.id:members[0].id,
          at.x,at.y,Math.max(19,19*composeScale),prefer.name,
          members.length>1?ids:null);
        // Each occupied socket is clickable only once it is actually visible.
        for(const item of moduleTargets){
          const entry=item.entity;
          addTarget(entry.__site?"construction_site":"facility",entry.id,
            item.x,item.y,Math.max(15,item.r),entry.name??"Модуль");
        }
        const parked=showShips?shipsAtHub(s.ships,hub.location):[];
        // The label stays short: each parked vessel gets its own
        // anchored, selectable icon drawn below in the ships layer.
        askLabel("hub-"+hub.id,at,
          prefer.name+(members.length>1?" · "+members.length+" объекта":""),
          primary?factionColor(prefer.faction_id,s.index):facilityMeta(prefer.type).tone,
          selected?0:primary?3:15,primary?21:17,205);
        hubAnchors.set(key(hub.location),{at,parked});
      }
      // Show real construction sites on the orbital map. An offset leader
      // is used only when a hub glyph would visually cover the scaffold.
      const bodyIds=new Set(sys.bodies.map(body=>body.id));
      for(const site of list(s.report?.construction_sites)){
        if(attachedConstructionSites.has(site.id))continue;
        if(!bodyIds.has(site.body_id))continue;
        const actual=liveWorldPoint(site);if(!actual)continue;
        const anchor=toScreen(actual);if(!visible(anchor,35))continue;
        const at=layoutMarker(anchor,15*iconScale,1);
        if(!at)continue;
        leader(anchor,at);
        occupiedMarkers.push({x:at.x,y:at.y,r:15*iconScale});
        const selected=isSelected("construction_site",site.id);
        withMapScale(at,iconScale,()=>drawSite(site,at,selected));
        markGlyph(at,12*iconScale);
        askLabel("site-"+site.id,at,facilityTypeLabel(site.facility_type)+" · "+Math.round(number(site.progress)*100)+"%",
          "#e0b47a",selected?0:8,18,150);
        addTarget("construction_site",site.id,at.x,at.y,Math.max(13,14*iconScale),site.name);
      }
    }
  }
  if(showShips){
    const shipMarkers=[];
    const visibleShips=s.ships.filter(ship=>
      s.view!=="system" || s.index.systems.length===1 ||
      shipSystem(ship,s.index)===s.systemName);
    const anchoredShips=new Set();
    if(s.view==="system"){
      // Parked vessels are visible as individual SMALL dock icons at the
      // station. The offsets are static screen-layout slots tied to the
      // hub's real coordinate; they do not orbit, interpolate or wander.
      for(const [loc,hub] of hubAnchors){
        const parked=[...hub.parked].sort((a,b)=>
          String(a.id).localeCompare(String(b.id)));
        for(let i=0;i<parked.length;i++){
          const ship=parked[i];
          anchoredShips.add(ship.id);
          s.visualPositions.delete(ship.id);
          s.shipMotion.delete(ship.id);
          const col=i%3,row=Math.floor(i/3);
          const at={
            x:hub.at.x+(31+col*20)*iconScale,
            y:hub.at.y+(10+row*21)*iconScale
          };
          if(!visible(at,20))continue;
          const selected=isSelected("ship",ship.id);
          withMapScale(at,Math.min(iconScale,1.8),()=>drawShip(ship,at,
            factionColor(ship.faction_id,s.index),selected,0));
          markGlyph(at,10*iconScale);
          askLabel("parked-"+ship.id,at,shipDisplayName(ship),
            "#c2dce4",selected?0:5,13,140);
          addTarget("ship",ship.id,at.x,at.y,Math.max(12,12*iconScale),
            shipDisplayName(ship)+" · у станции");
        }
      }
    }
    // In-flight ships always use their own real coordinates, never
    // the location of a nearby facility. Unknown/idle ships without
    // a known hub remain visible at their own reported coordinates.
    for(const ship of visibleShips){
      if(anchoredShips.has(ship.id))continue;
      const state=shipMapState(ship);
      if(state!=="in_transit"){
        s.visualPositions.delete(ship.id);
        s.shipMotion.delete(ship.id);
      }
      const target=positionOf(ship,s.positions);
      const p=state==="in_transit" ? smoothPosition(ship,target) : target;
      if(!p)continue;
      const sc=toScreen(p);
      if(!visible(sc,20))continue;
      shipMarkers.push({...sc,ship,state});
    }
    for(const group of clusterMarkers(shipMarkers,34)){
      if(group.members.length>1){
        const ids=group.members.map(m=>m.ship.id);
        const selected=ids.includes(s.selection?.id);
        withMapScale(group,Math.min(iconScale,1.8),()=>
          drawShip(group.members[0].ship,group,"#84b9c5",
            selected,group.members[0].state==="in_transit"?scale:0));
        markGlyph(group,12*iconScale);
        askLabel("ships-"+group.id,group,ids.length+" корабля",
          "#c2dce4",selected?0:5,16,118);
        addTarget("ship_group",group.id,group.x,group.y,
          Math.max(17,16*iconScale),ids.length+" кораблей",ids);
      }else{
        const {ship,x,y,state}=group.members[0];
        const at={x,y},selected=isSelected("ship",ship.id);
        withMapScale(at,iconScale,()=>drawShip(ship,at,
          factionColor(ship.faction_id,s.index),selected,
          state==="in_transit"?scale:0));
        markGlyph(at,11*iconScale);
        askLabel("ship-"+ship.id,at,shipDisplayName(ship),
          "#c2dce4",selected?0:3,16,145);
        addTarget("ship",ship.id,at.x,at.y,
          Math.max(selected?15:12,12*iconScale),shipDisplayName(ship));
      }
    }
  }
  // Labels are a UI overlay, not physical objects. Move or drop only
  // labels when space is tight; never move the actual simulated positions.
  for(const item of layoutMapLabels(labelRequests,{w,h},markerObstacles)){
    if(item.plain){
      ctx.save();ctx.fillStyle=item.color;
      ctx.textAlign="left";ctx.font="11px Segoe UI, sans-serif";
      ctx.fillText(item.text,item.x+4,item.y+12,item.w-8);ctx.restore();
    }else{
      textChip(item.x,item.y+10,item.text,item.color,item.max);
    }
  }
  window.requestAnimationFrame(renderMap);
}

function nearestTarget(x,y) {
  const hits=s.targets.filter(p=>(p.x-x)**2+(p.y-y)**2<=p.r*p.r)
    .sort((a,b)=>{
      const priority={ship:0,ship_group:0,construction_site:0,facility:1,facility_group:1,body:2,system:3};
      return priority[a.type]-priority[b.type] ||
        ((a.x-x)**2+(a.y-y)**2)-((b.x-x)**2+(b.y-y)**2);
    });
  return hits[0]??null;
}

function installCanvasHandlers(){
  const toLocal=e=>{const r=els.map.getBoundingClientRect();return{x:e.clientX-r.left,y:e.clientY-r.top}};
  els.map.addEventListener("pointerdown",e=>{
    if(e.button!==0)return;
    const p=toLocal(e);
    s.dragging={start:p,previous:p,moved:false};
    els.map.setPointerCapture(e.pointerId);els.map.classList.add("grabbing");
  });
  els.map.addEventListener("pointermove",e=>{
    const p=toLocal(e);
    if(s.dragging){
      if(Math.hypot(p.x-s.dragging.start.x,p.y-s.dragging.start.y)>4)s.dragging.moved=true;
      if(s.dragging.moved){
        if(s.follow)stopFollowing(); // direct user pan releases tracking
        s.pan.x+=p.x-s.dragging.previous.x;
        s.pan.y+=p.y-s.dragging.previous.y;
      }
      s.dragging.previous=p;
      els.hoverLabel.hidden=true;
      return;
    }
    const target=nearestTarget(p.x,p.y);
    if(!target){els.hoverLabel.hidden=true;return;}
    els.hoverLabel.textContent=target.name;
    els.hoverLabel.style.left=Math.min(p.x+15,pixels.w-150)+"px";
    els.hoverLabel.style.top=Math.min(p.y+15,pixels.h-34)+"px";
    els.hoverLabel.hidden=false;
  });
  els.map.addEventListener("pointerup",e=>{
    if(!s.dragging)return;
    const moved=s.dragging.moved;
    s.dragging=null;els.map.classList.remove("grabbing");
    if(!moved){
      const p=toLocal(e),target=nearestTarget(p.x,p.y);
      if(target){
        s.selection={type:target.type,id:target.id,ids:target.ids,name:target.name};
        if(target.type==="system")s.systemName=target.id;
        s.guideDismissed = true;
        renderInspector();refreshToolbar();renderSidebar();updateFollowButton();
      }
    }
  });
  els.map.addEventListener("pointercancel",()=>{s.dragging=null;els.map.classList.remove("grabbing");});
  els.map.addEventListener("pointerleave",()=>{els.hoverLabel.hidden=true;});
  els.map.addEventListener("dblclick",e=>{
    const p=toLocal(e),target=nearestTarget(p.x,p.y);
    if(target?.type==="system")chooseSystem(target.id,true);
    else if(target?.type==="ship_group") changeZoomAt(p,2);
    else if(target && ["ship","body","facility","facility_group","construction_site"].includes(target.type)) {
      s.selection={type:target.type,id:target.id,ids:target.ids,name:target.name};
      s.guideDismissed=true;
      followSelectedObject();
      renderInspector();updateFollowButton();
    }
  });
  els.map.addEventListener("wheel",e=>{
    e.preventDefault();
    const pointer=toLocal(e);
    changeZoomAt(pointer,e.deltaY<0?1.18:1/1.18);
  },{passive:false});
  els.map.addEventListener("keydown",e=>{
    if(e.key==="Escape"){sectorMode();els.map.blur();}
    if(e.key==="1"){setCameraFocus("inner");e.preventDefault();}
    if(e.key==="2"){setCameraFocus("full");e.preventDefault();}
    if(e.key.toLowerCase()==="f"){if(s.follow)stopFollowing();else followSelectedObject();e.preventDefault();}
  });
}

function wireControls() {
  els.pauseBtn.addEventListener("click",()=>control(
    s.health?.running?"/api/sim/pause":"/api/sim/resume",{}
  ));
  els.speedSelect.addEventListener("change",()=>control("/api/sim/speed",{
    world_speed:Number(els.speedSelect.value)
  }));
  els.sectorTab.addEventListener("click",sectorMode);
  els.systemTab.addEventListener("click",()=>{if(s.systemName)chooseSystem(s.systemName,true);});
  els.fitBtn.addEventListener("click",resetCamera);
  els.followBtn.addEventListener("click",()=>{if(s.follow)stopFollowing();else followSelectedObject();});
  els.focusInnerBtn.addEventListener("click",()=>setCameraFocus("inner"));
  els.focusFullBtn.addEventListener("click",()=>setCameraFocus("full"));
  els.systemSearch.addEventListener("input",renderSidebar);
  els.exportDiagnostics.addEventListener("click",exportDiagnostics);
  els.clearEvents.addEventListener("click",()=>{s.events=[];renderEvents();});
  els.clearSelection.addEventListener("click",()=>{s.selection=null;stopFollowing();renderInspector();});
  els.startSystemBtn.addEventListener("click",()=>{
    const chosen = s.index?.systems.find(x => x.name === "Sol") ?? s.index?.systems[0];
    if (chosen) chooseSystem(chosen.name, true);
  });
  els.dismissGuideBtn.addEventListener("click",()=>{s.guideDismissed=true;renderStartGuide();});
  installCanvasHandlers();
}

/* BEGIN GENERATED STRATEGY BUNDLE */

// Pure, read-only adapter for GET /api/strategy v1.
// Never infer execution or progress from scores, proposed goals or HTTP freshness.
const goalLabels = Object.freeze({
  sustain_population: "Снабжение населения",
  secure_fuel: "Обеспечение топливом",
  supply_industry: "Снабжение промышленности",
  expand_production: "Расширение производства"
});
const decisionLabels = Object.freeze({
  observing: "Наблюдение", idle: "Нет предложений",
  proposed: "Предложение", blocked: "Заблокировано",
  waiting: "Ожидание", commissioned: "Контракт создан"
});
const reasonLabels = Object.freeze({
  awaiting_cycle: "Ожидание следующего анализа",
  no_chronic_shortage: "Не выявлено длительного дефицита",
  shadow_no_mutation: "Диагностический режим: деньги и контракты не меняются",
  no_accessible_stock: "Нет доступного запаса в подходящем источнике",
  insufficient_budget: "Недостаточно свободного бюджета",
  existing_contract: "Для потребности уже существует контракт",
  funded_native_contract: "Создан обеспеченный штатный контракт",
  head_priority: "Ожидает решения главы: выбран другой администратор",
  ready: "Доступно для выбора",
  site_owned_by_other_faction: "Площадка принадлежит другой фракции",
  no_producer: "Не найден тип производителя для ресурса",
  producer_already_present: "Такой производитель здесь уже существует",
  invalid_site_location: "Невозможно разместить объект в этой точке",
  no_local_resource: "На планете отсутствует необходимый добываемый ресурс",
  awaiting_materialization: "Ожидается завершение строительства",
  positive_projected_relief: "Ожидается полезный эффект",
  unprofitable_source: "Поставка экономически невыгодна",
  no_construction_proposal: "Нет подходящего строительного проекта",
  reconsider_next_cycle: "Повторная оценка в следующем цикле"
});
const administratorLabels = Object.freeze({
  logistics: "Логистика", construction: "Строительство"
});
const headReasonLabels = Object.freeze({
  urgent_supply: "Срочное снабжение продовольствием, водой или топливом",
  finish_existing_construction: "Продолжение существующей стройки",
  expand_production: "Расширение производства",
  supply_industry: "Снабжение промышленности",
  no_feasible_proposal: "Нет выполнимых предложений",
  already_commissioned_this_tick: "Новый контракт уже создан в этом тике",
  best_projected_relief: "Выбран вариант с наибольшим прогнозируемым эффектом"
});
const optionLabels = Object.freeze({
  deliver: "Доставить", build: "Построить", wait: "Подождать"
});
const optionStatusLabels = Object.freeze({
  ready: "Возможен", blocked: "Недоступен", waiting: "Ожидание"
});
const optionReasonLabels = Object.freeze({
  positive_projected_relief: "Положительный прогноз",
  unprofitable_source: "Поставка экономически невыгодна",
  no_accessible_stock: "Нет доступного запаса",
  insufficient_budget: "Не хватает бюджета",
  producer_already_present: "Производитель уже существует",
  no_construction_proposal: "Стройка не предложена",
  reconsider_next_cycle: "Вернуться к выбору в следующем цикле"
});
const projectLabels = Object.freeze({
  posted: "Опубликован", accepted: "Принят",
  picked_up: "Груз забран", delivered: "Доставлен",
  paid: "Оплачен", expired: "Истёк"
});
const commodityLabels = Object.freeze({
  ore:"Руда", ice:"Лёд", gas:"Газ", metals:"Металлы",
  fuel:"Топливо", polymers:"Полимеры", water:"Вода",
  components:"Компоненты", electronics:"Электроника",
  tools:"Инструменты", food:"Продовольствие",
  medical:"Медикаменты", luxury:"Предметы роскоши"
});
function human(value, dictionary) {
  const code = String(value ?? "");
  return dictionary[code] || code || "—";
}
function goalKey(goal) {
  if (!goal) return null;
  // A goal_id is a category, not a unique instance.
  return JSON.stringify([goal.goal_id, goal.commodity, goal.destination]);
}
function parseSnapshot(input) {
  if (!input || input.schema_version !== 1 || !Array.isArray(input.factions) ||
      !Number.isSafeInteger(input.snapshot_tick) || input.snapshot_tick < 0 ||
      !["shadow","execute"].includes(input.mode)) {
    throw new Error("Неподдерживаемый формат /api/strategy (ожидается v1)");
  }
  const factions = input.factions.map(f => ({
    faction_id: String(f.faction_id ?? ""),
    observed_tick: Number.isSafeInteger(f.observed_tick) ? f.observed_tick : null,
    treasury: Number.isFinite(f.treasury) ? f.treasury : null,
    goals: Array.isArray(f.goals) ? f.goals : [],
    selected_goal: f.selected_goal ?? null,
    administrator: String(f.administrator ?? "—"),
    status: String(f.status ?? "—"),
    reason: String(f.reason ?? "—"),
    projects: Array.isArray(f.projects) ? f.projects : [],
    assessments: Array.isArray(f.assessments) ? f.assessments : [],
    construction: f.construction && typeof f.construction === "object" ? f.construction : null,
    head: f.head && typeof f.head === "object" ? f.head : null
  })).filter(f=>f.faction_id);
  return {
    schema_version: 1,
    snapshot_tick: input.snapshot_tick,
    mode: input.mode,
    factions
  };
}

function assessmentForGoal(faction, goal) {
  const wanted = goalKey(goal);
  return (faction?.assessments ?? []).find(a => goalKey(a?.goal) === wanted) ?? null;
}
function projectGroups(faction) {
  const projects = faction?.projects ?? [];
  return {
    logistics: projects.filter(project => project.administrator !== "construction"),
    construction: projects.filter(project => project.administrator === "construction")
  };
}
function progressFraction(construction) {
  const required = construction?.progress_required;
  const delivered = construction?.progress_delivered;
  if (!Number.isFinite(required) || required <= 0 || !Number.isFinite(delivered)) return null;
  return Math.max(0, Math.min(1, delivered / required));
}

function observedChanges(before, after) {
  // This is a local diff of observed snapshots, NOT an authoritative event log.
  if (!before || !after || after.snapshot_tick <= before.snapshot_tick) return [];
  const results = [];
  const previous = new Map(before.factions.map(f => [f.faction_id, f]));
  for (const now of after.factions) {
    const old = previous.get(now.faction_id);
    if (!old) continue;
    const add = message => results.push({
      faction_id: now.faction_id, tick: after.snapshot_tick, message
    });
    if (goalKey(old.selected_goal) !== goalKey(now.selected_goal)) {
      const target = now.selected_goal;
      add(target
        ? "Выбран приоритет: " + human(target.goal_id, goalLabels) +
          " · " + human(target.commodity, commodityLabels) +
          " → " + String(target.destination ?? "—")
        : "Выбранный приоритет больше не указан");
    }
    if (old.status !== now.status || old.reason !== now.reason) {
      add("Решение: " + human(now.status, decisionLabels) +
        " · " + human(now.reason, reasonLabels));
    }
    const wasHead = old.head;
    const isHead = now.head;
    if (isHead && (!wasHead || (Number.isSafeInteger(isHead.observed_tick) &&
      isHead.observed_tick > (wasHead.observed_tick ?? -1)))) {
      const changed = !wasHead || wasHead.selected_administrator !== isHead.selected_administrator ||
        wasHead.reason !== isHead.reason;
      if (changed) {
        add("Глава: " + (isHead.selected_administrator
          ? human(isHead.selected_administrator, administratorLabels)
          : "Никто не выбран") + " · " + human(isHead.reason, headReasonLabels));
      }
    }
    const fromConstruction = old.construction;
    const toConstruction = now.construction;
    if (toConstruction) {
      if (fromConstruction && (fromConstruction.status !== toConstruction.status ||
          fromConstruction.reason !== toConstruction.reason)) {
        add("Строительство: " + human(toConstruction.status, decisionLabels) +
          " · " + human(toConstruction.reason, reasonLabels));
      }
      if (toConstruction.site_id && fromConstruction?.site_id === toConstruction.site_id &&
          Number.isFinite(toConstruction.progress_delivered) &&
          toConstruction.progress_delivered !== fromConstruction.progress_delivered) {
        add("Стройплощадка " + toConstruction.site_id + ": " +
          toConstruction.progress_delivered + " / " + toConstruction.progress_required);
      }
    }
    const oldProjects = new Map(old.projects.map(p => [p.contract_id, p]));
    for (const project of now.projects) {
      if (!project.contract_id) continue;
      const previousProject = oldProjects.get(project.contract_id);
      if (!previousProject) {
        add("Впервые наблюдаем проект " + project.contract_id +
          " · " + human(project.state, projectLabels));
      } else if (previousProject.state !== project.state) {
        add("Проект " + project.contract_id + ": " +
          human(previousProject.state, projectLabels) + " → " +
          human(project.state, projectLabels));
      }
    }
  }
  return results;
}
function observationAge(snapshot, faction) {
  if (!snapshot || !faction || !Number.isSafeInteger(faction.observed_tick)) return null;
  return Math.max(0, snapshot.snapshot_tick - faction.observed_tick);
}

// Independent, read-only strategy drawer. No writes to the simulation API.
const format = new Intl.NumberFormat("ru-RU", {maximumFractionDigits: 1});
const text = value => value === null || value === undefined ? "—" : String(value);
const formatNumber = value => Number.isFinite(value) ? format.format(value) : "—";
const node = (tag, content, className) => {
  const element = document.createElement(tag);
  if (content !== undefined) element.textContent = text(content);
  if (className) element.className = className;
  return element;
};
const find = id => document.getElementById(id);

let elements;
let getFactions = () => [];
let snapshot = null;
let selectedFaction = null;
let changes = [];
let pending = false;
let requestError = null;

function strategyFactionName(id) {
  return getFactions().find(f => f.id === id)?.name || id;
}
function addField(parent, label, value) {
  const row = node("div", undefined, "strategy-field");
  row.append(node("span", label, "strategy-field-label"), node("span", value, "strategy-field-value"));
  parent.appendChild(row);
}
function addNote(parent, message) {
  parent.append(node("p", message, "strategy-note"));
}
function showEmpty(container, message) {
  container.replaceChildren(node("p", message, "strategy-empty"));
}
function setOpen(open) {
  if (!elements) return;
  elements.drawer.hidden = !open;
  elements.backdrop.hidden = !open;
  elements.toggle.setAttribute("aria-expanded", String(open));
  document.body.classList.toggle("strategy-open", open);
  if (open) {
    elements.close.focus();
    poll();
  } else {
    elements.toggle.focus();
  }
}
function openStrategyForFaction(id = null) {
  if (!elements) return;
  if (id) selectedFaction = String(id);
  setOpen(true);
  render();
}

function fillFactionSelect() {
  const select = elements.faction;
  const current = selectedFaction;
  select.replaceChildren();
  if (!snapshot?.factions.length) {
    select.appendChild(new Option("Нет сведений о фракциях", ""));
    select.disabled = true;
    return null;
  }
  select.disabled = false;
  const sorted = [...snapshot.factions].sort((a, b) =>
    strategyFactionName(a.faction_id).localeCompare(strategyFactionName(b.faction_id), "ru"));
  for (const faction of sorted) {
    select.appendChild(new Option(strategyFactionName(faction.faction_id), faction.faction_id));
  }
  const present = sorted.some(f => f.faction_id === current);
  selectedFaction = present ? current : sorted[0].faction_id;
  select.value = selectedFaction;
  return snapshot.factions.find(f => f.faction_id === selectedFaction);
}
function strategyRenderHead(faction) {
  const target = elements.head;
  target.replaceChildren();
  const head = faction.head;
  if (!head) return showEmpty(target,
    "Этот сервер ещё не передаёт решения главы (поле head доступно с S4). " +
    "Показанные ниже логистические решения не являются общим выбором главы.");
  const card = node("article", undefined, "strategy-summary-card strategy-head-card");
  const chosen = head.selected_administrator
    ? human(head.selected_administrator, administratorLabels) : "Нет выбранного администратора";
  card.append(node("div", "РЕШЕНИЕ ГЛАВЫ · ТИК " + formatNumber(head.observed_tick),
    "strategy-eyebrow"));
  card.append(node("h3", chosen, "strategy-faction-name"));
  card.append(node("p", human(head.reason, headReasonLabels), "strategy-decision-reason"));
  addField(card, "Казна при выборе", formatNumber(head.treasury_before) + " CR");
  addField(card, "Доступно для выбора", formatNumber(head.spending_limit) + " CR");
  addField(card, "План платежа", formatNumber(head.planned_spend) + " CR");
  addField(card, "Фактически зарезервировано", formatNumber(head.committed_spend) + " CR");
  const age = observationAge(snapshot, head);
  if (age !== null && age > 0) addNote(card,
    "Данные относятся к последнему решению главы, а не к текущему балансу.");
  target.append(card);
  // S7 options use forecast data; never equate covered_units with the native contract quantity.
  const options = Array.isArray(head.alternatives) ? head.alternatives : null;
  if (options) {
    if (head.problem) {
      const problem = head.problem;
      const caption = node("div", "ПРОБЛЕМА · " +
        human(problem.commodity, commodityLabels) + " → " + text(problem.destination),
        "strategy-problem-title");
      target.append(caption);
      addNote(target, "Дефицит: " + formatNumber(problem.shortage_ticks) +
        " тик. · Горизонт прогноза: " + formatNumber(head.horizon_ticks) + " тик.");
    }
    target.append(node("h4", "ВАРИАНТЫ ГЛАВЫ · S7", "strategy-subheading"));
    for (const option of options) {
      const selected = option.action === head.selected_option;
      const item = node("article", undefined, "strategy-option-card");
      if (selected) item.classList.add("strategy-proposal-chosen");
      const header = node("div", undefined, "strategy-goal-heading");
      header.append(node("strong", human(option.action, optionLabels)));
      header.append(node("span", selected ? "Выбран" :
        human(option.status, optionStatusLabels),
        selected ? "strategy-selection-tag" : "strategy-project-state"));
      item.append(header);
      item.append(node("p", human(option.reason, optionReasonLabels), "strategy-option-reason"));
      if (option.source) addField(item, "Источник", option.source);
      if (option.material) addField(item, "Товар / сырьё", human(option.material, commodityLabels));
      if (option.site_id) addField(item, "Стройплощадка", option.site_id);
      addField(item, "Первая оплата", formatNumber(option.first_payment) + " CR");
      addField(item, "Полный бюджет (оценка)", formatNumber(option.total_commitment) + " CR");
      addField(item, "Казна после (прогноз)", formatNumber(option.treasury_after) + " CR");
      if (option.action !== "wait") {
        addField(item, "Оценка задержки", formatNumber(option.estimated_delay_ticks) + " тик.");
        addField(item, "План поставок", formatNumber(option.shipment_count));
        addField(item, "Покрытие потребности", formatNumber(option.covered_units) + " ед.");
        if (Number.isFinite(option.first_purchase_cost))
          addField(item, "Закупка 1-й партии", formatNumber(option.first_purchase_cost) + " CR");
        if (Number.isFinite(option.estimated_net_value))
          addField(item, "Расчётная оценка", formatNumber(option.estimated_net_value));
      }
      target.append(item);
    }
    addNote(target, "Покрытие потребности — прогнозируемый эффект, НЕ фактический размер партии. " +
      "Полный бюджет не означает, что все будущие платежи уже зарезервированы. " +
      "Выбранный вариант не равен завершённому контракту.");
  }
  const proposals = Array.isArray(head.proposals) ? head.proposals : [];
  const label = node("h4", "ПРЕДЛОЖЕНИЯ АДМИНИСТРАТОРОВ", "strategy-subheading");
  target.append(label);
  if (!proposals.length) return addNote(target, "Предложения в последнем цикле не переданы.");
  for (const proposal of proposals) {
    const selected = proposal.administrator === head.selected_administrator;
    const item = node("article", undefined, "strategy-proposal-card");
    if (selected) item.classList.add("strategy-proposal-chosen");
    const row = node("div", undefined, "strategy-goal-heading");
    row.append(node("strong", human(proposal.administrator, administratorLabels)));
    row.append(node("span", selected ? "Выбран" :
      human(proposal.status, decisionLabels), selected ? "strategy-selection-tag" : "strategy-project-state"));
    item.append(row);
    if (proposal.goal) item.append(node("div",
      human(proposal.goal.commodity, commodityLabels) + " → " + text(proposal.goal.destination),
      "strategy-route"));
    addField(item, "Состояние до выбора",
      human(proposal.status, decisionLabels));
    addField(item, "Основание", human(proposal.reason, reasonLabels));
    addField(item, "Запрошено", formatNumber(proposal.requested_credits) + " CR");
    addField(item, "Уровень приоритета", formatNumber(proposal.priority));
    target.append(item);
  }
  addNote(target, "Предложения показаны ДО исполнения. Реальное выполнение смотри в " +
    "состоянии администратора и статусах контрактов ниже.");
}
function strategyRenderConstruction(faction) {
  const target = elements.construction;
  target.replaceChildren();
  const c = faction.construction;
  if (!c) return showEmpty(target,
    "Сервер ещё не передаёт строительного администратора (S1/S2) " +
    "или первый строительный цикл пока не выполнялся.");
  const card = node("article", undefined, "strategy-construction-card");
  const row = node("div", undefined, "strategy-section-header");
  row.append(node("span", "Последнее решение · тик " + formatNumber(c.observed_tick),
    "strategy-eyebrow"),
    node("span", human(c.status, decisionLabels), "strategy-state"));
  card.append(row);
  card.append(node("p", human(c.reason, reasonLabels), "strategy-decision-reason"));
  if (c.selected_goal) {
    addField(card, "Цель", human(c.selected_goal.goal_id, goalLabels));
    addField(card, "Ресурс", human(c.selected_goal.commodity, commodityLabels));
    addField(card, "Узел", c.selected_goal.destination);
  } else addNote(card, "Активной строительной цели на последнем анализе нет.");
  addField(card, "Тип сооружения", c.facility_type || "—");
  addField(card, "Площадка", c.site_id || "Не создана");
  addField(card, "Контракт на поставку", c.contract_id || "Нет");
  const ratio = progressFraction(c);
  if (ratio !== null && c.site_id) {
    const progress = node("div", undefined, "strategy-site-progress");
    const header = node("div", undefined, "strategy-goal-heading");
    header.append(node("span", "Доставленные материалы"),
      node("strong", formatNumber(c.progress_delivered) + " / " +
        formatNumber(c.progress_required)));
    progress.append(header);
    const bar = document.createElement("progress");
    bar.value = ratio;
    bar.max = 1;
    bar.setAttribute("aria-label", "Прогресс доставки строительных материалов");
    progress.append(bar);
    card.append(progress);
  } else addNote(card, "Прогресс площадки пока недоступен; не следует считать её завершённой.");
  const age = observationAge(snapshot, c);
  if (age !== null && age > 0) addNote(card,
    "Решение принято " + age + " тик. назад; прогресс площадки может быть обновлён отдельно.");
  target.append(card);
}
function renderSummary(faction) {
  const target = elements.summary;
  target.replaceChildren();
  const card = node("section", undefined, "strategy-summary-card");
  const header = node("div", undefined, "strategy-section-header");
  header.append(node("span", "Логистический администратор", "strategy-eyebrow"),
    node("span", human(faction.status, decisionLabels), "strategy-state"));
  card.append(header);
  const name = node("h3", strategyFactionName(faction.faction_id), "strategy-faction-name");
  card.append(name);
  card.append(node("p", human(faction.reason, reasonLabels), "strategy-decision-reason"));
  const metrics = node("div", undefined, "strategy-metrics");
  for (const [label, value] of [
    ["Казна", formatNumber(faction.treasury) + " CR"],
    ["Кандидаты", faction.goals.length],
    ["Проекты в ответе", faction.projects.length]
  ]) {
    const item = node("div", undefined, "strategy-metric");
    item.append(node("span", label), node("strong", value));
    metrics.append(item);
  }
  card.append(metrics);
  addField(card, "Администратор", faction.administrator);
  addField(card, "Тик наблюдения", formatNumber(faction.observed_tick));
  const age = observationAge(snapshot, faction);
  addField(card, "Возраст отчёта", age === null ? "не указан" : age + " тик.");
  if (age !== null && age > 0) {
    addNote(card, "Решение принято на предыдущем цикле анализа. Текущий тик мира может быть новее.");
  }
  target.append(card);
}
function renderGoals(faction) {
  const target = elements.goals;
  target.replaceChildren();
  if (!faction.goals.length) return showEmpty(target, "На последнем анализе кандидаты не сформированы.");
  const selectedKey = goalKey(faction.selected_goal);
  faction.goals.forEach((goal, index) => {
    const card = node("article", undefined, "strategy-goal-card");
    if (goalKey(goal) === selectedKey) card.classList.add("strategy-goal-selected");
    const heading = node("div", undefined, "strategy-goal-heading");
    heading.append(node("span", (index + 1) + ". " + human(goal.goal_id, goalLabels)));
    if (goalKey(goal) === selectedKey) heading.append(node("span", "Выбран", "strategy-selection-tag"));
    card.append(heading);
    const details = node("div", undefined, "strategy-goal-details");
    details.append(
      node("span", human(goal.commodity, commodityLabels) + " → " + text(goal.destination)),
      node("span", "Дефицит: " + formatNumber(goal.shortage_ticks) + " тик.")
    );
    card.append(details);
    const assessment = assessmentForGoal(faction, goal);
    if (assessment) {
      const ready = assessment.reason === "ready";
      card.append(node("div", "Выполнимость: " + human(assessment.reason, reasonLabels),
        ready ? "strategy-assessment ready" : "strategy-assessment blocked"));
      if (assessment.source) card.append(node("div", "Доступный источник: " + assessment.source,
        "strategy-goal-details"));
    } else if (!faction.assessments.length) {
      card.append(node("div", "Оценка выполнимости недоступна (S1).",
        "strategy-goal-details"));
    }
    card.append(node("div", "Оценка приоритета: " + formatNumber(goal.score), "strategy-score"));
    target.append(card);
  });
}
function renderProjects(faction) {
  const target = elements.projects;
  target.replaceChildren();
  if (!faction.projects.length) {
    return showEmpty(target, "Стратегические контракты ещё не наблюдаются. Это не означает, " +
      "что в мире нет обычных контрактов.");
  }
  const groups = projectGroups(faction);
  for (const admin of ["logistics", "construction"]) {
    if (!groups[admin].length) continue;
    target.append(node("h4", human(admin, administratorLabels) +
      " · " + groups[admin].length + " контракт(ов)", "strategy-subheading"));
    for (const project of groups[admin]) {
      const card = node("article", undefined, "strategy-project-card");
      const top = node("div", undefined, "strategy-project-top");
      top.append(node("strong", human(project.commodity, commodityLabels)),
        node("span", human(project.state, projectLabels), "strategy-project-state"));
      card.append(top);
      card.append(node("div", text(project.source) + " → " + text(project.destination),
        "strategy-route"));
      addField(card, "Количество", formatNumber(project.quantity));
      addField(card, "Исполнитель", project.executor_id || "Не назначен");
      addField(card, "Резерв оплаты", formatNumber(project.reserved_credits) + " CR");
      addField(card, "Контракт", project.contract_id);
      target.append(card);
    }
  }
  addNote(target, "Контракты строительства — это доставки грузов. " +
    "Сама стройплощадка и её прогресс показаны отдельно.");
}
function renderHistory() {
  const target = elements.history;
  target.replaceChildren();
  const entries = changes.filter(item => item.faction_id === selectedFaction).slice(0, 50);
  if (!entries.length) {
    return showEmpty(target, "Изменения появятся после следующих опросов. Ранее произошедшие события недоступны.");
  }
  for (const item of entries) {
    const row = node("div", undefined, "strategy-history-row");
    row.append(node("time", "Тик " + formatNumber(item.tick)), node("div", item.message));
    target.append(row);
  }
}
function render() {
  if (!elements) return;
  const scroll = elements.content.scrollTop;
  const active = fillFactionSelect();
  elements.mode.textContent = snapshot?.mode === "execute" ? "EXECUTE · выполнение" :
    snapshot?.mode === "shadow" ? "SHADOW · наблюдение" : "Нет данных";
  elements.mode.dataset.mode = snapshot?.mode || "unknown";
  elements.update.textContent = requestError
    ? "Ошибка получения данных · " + requestError
    : snapshot ? "API v1 · тик " + formatNumber(snapshot.snapshot_tick) : "Ожидание ответа API";
  elements.update.classList.toggle("strategy-error", Boolean(requestError));
  if (active) {
    strategyRenderHead(active);
    renderSummary(active);
    renderGoals(active);
    strategyRenderConstruction(active);
    renderProjects(active);
  } else {
    showEmpty(elements.head, requestError || "Нет сведений о стратегическом управлении.");
    showEmpty(elements.summary, requestError || "Нет сведений о стратегическом управлении.");
    elements.goals.replaceChildren();
    elements.construction.replaceChildren();
    elements.projects.replaceChildren();
  }
  renderHistory();
  elements.content.scrollTop = scroll;
}
async function poll() {
  if (!elements || elements.drawer.hidden || pending || document.hidden) return;
  pending = true;
  try {
    const response = await fetch("/api/strategy", {cache: "no-store"});
    if (!response.ok) throw new Error("HTTP " + response.status);
    const next = parseSnapshot(await response.json());
    if (snapshot && next.snapshot_tick < snapshot.snapshot_tick) {
      // New world or rollback: comparison against previous timeline would be misleading.
      changes = [];
      snapshot = null;
    }
    const additions = observedChanges(snapshot, next);
    if (additions.length) changes = [...additions.reverse(), ...changes].slice(0, 100);
    snapshot = next;
    requestError = null;
  } catch (error) {
    requestError = error instanceof Error ? error.message : String(error);
    // Keep the previous snapshot visible, clearly marked as last known data.
  } finally {
    pending = false;
    render();
  }
}
function initStrategyPanel(options = {}) {
  if (elements) return;
  getFactions = typeof options.getFactions === "function" ? options.getFactions : getFactions;
  elements = {
    toggle:find("strategy-toggle"), drawer:find("strategy-drawer"),
    backdrop:find("strategy-backdrop"), close:find("strategy-close"),
    mode:find("strategy-mode"), update:find("strategy-update"),
    faction:find("strategy-faction"), content:find("strategy-content"),
    head:find("strategy-head"), summary:find("strategy-summary"),
    goals:find("strategy-goals"), construction:find("strategy-construction"),
    projects:find("strategy-projects"), history:find("strategy-history"),
    clear:find("strategy-clear-history"), refresh:find("strategy-refresh")
  };
  if (Object.values(elements).some(element => !element)) {
    throw new Error("Отсутствует элемент интерфейса стратегии");
  }
  elements.toggle.addEventListener("click", () => setOpen(elements.drawer.hidden));
  elements.close.addEventListener("click", () => setOpen(false));
  elements.backdrop.addEventListener("click", () => setOpen(false));
  elements.faction.addEventListener("change", () => {
    selectedFaction = elements.faction.value;
    render();
  });
  elements.clear.addEventListener("click", () => {changes = [];renderHistory();});
  elements.refresh.addEventListener("click", poll);
  document.addEventListener("keydown", event => {
    if (elements.drawer.hidden) return;
    if (event.key === "Escape") {
      event.preventDefault();
      setOpen(false);
    } else if (event.key === "Tab") {
      // Keep keyboard focus inside the modal; return it to the toggle on close.
      const focusable = [...elements.drawer.querySelectorAll("button:not([disabled]),select:not([disabled])")];
      if (!focusable.length) return;
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first.focus();
      }
    }
  });
  window.setInterval(poll, 6000);
  render();
}

/* END GENERATED STRATEGY BUNDLE */
wireControls();
initStrategyPanel({getFactions: () => list(s.report?.factions)});
renderMap();
fetchReport().then(()=>{connectWs();fetchHealth();});
window.setInterval(fetchReport,18000);
window.setInterval(fetchHealth,2500);
window.setInterval(()=>{refreshToolbar();renderInspector();},2200);
window.addEventListener("beforeunload",()=>s.ws?.close());