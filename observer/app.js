import {
  list, number, point, key, buildIndex, factionColor, factionName,
  systemByName, positionOf, approximateShipsNear, shortageCount, sortedCargo,
  panForCursorZoom, clusterMarkers, shipSystem, worldGridStep, mapIconScale,
  groupFacilitiesByLocation, layoutMapLabels, shipMapState, shipsAtHub,
  liveEntityPoint, approachWorldPoint
} from "/observer/model.js";

const byId = id => document.getElementById(id);
const els = Object.fromEntries([
  "connection","system-count","system-search","system-list","faction-count","faction-legend",
  "world-subtitle","tick","agent-count","pause-btn","speed-select","sector-tab","system-tab",
  "ships-toggle","links-toggle","labels-toggle","fit-btn","map","canvas-holder","hover-label",
  "map-error","data-tick","event-feed","clear-events","inspector-body","clear-selection",
  "ship-total","facility-total","market-total","first-run-guide","start-system-btn","dismiss-guide-btn"
].map(id => [id.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase()), byId(id)]));

const s = {
  report: null, index: null, ships: [], health: null, positions: new Map(),
  ws: null, wsUp: false, live: false, events: [],
  view: "sector", systemName: null, selection: null,
  zoom: 1, pan: {x: 0, y: 0}, dragging: null, hover: null,
  targets: [], visualPositions: new Map(), shipMotion: new Map(),
  mapWorldPositions: new Map(),
  lastReportAt: 0, fetching: false, error: null, guideDismissed: false
};
const fmt = new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 1 });
const q = value => value == null ? "—" : String(value);
const fnum = value => value == null ? "—" : fmt.format(number(value));
const ctx = els.map.getContext("2d");
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
  s.index = buildIndex(report);
  s.lastReportAt = Date.now();
  // Genesis has no reason to open on an empty sector map with a guide
  // telling the user to open its one and only system.
  if (firstReport && s.index.systems.length === 1 && s.ships.length <= 8) {
    s.systemName = s.index.systems[0].name;
    s.view = "system";
    s.selection = null;
    s.guideDismissed = true;
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
  const largeWorld = s.ships.length > 20 ? " · большой исходный мир" : "";
  const smallStart = s.index?.systems.length === 1 && s.ships.length <= 8;
  els.worldSubtitle.textContent = smallStart
    ? "Малый старт · " + (s.view === "system" ? s.systemName : "сектор")
    : (s.view === "system" ? s.systemName : "Сектор · живые данные") + largeWorld;
  els.sectorTab.classList.toggle("active", s.view === "sector");
  els.systemTab.classList.toggle("active", s.view === "system");
  els.systemTab.disabled = !s.systemName;
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
    const row = document.createElement("div");
    row.className = "faction-item";
    marker(row, "dot", factionColor(faction.id, s.index));
    row.appendChild(textEl("span", faction.name));
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
  if (enter) { s.view = "system"; els.shipsToggle.checked = true; }
  if (changed) resetCamera();
  renderSidebar(); renderInspector(); refreshToolbar(); renderStartGuide();
}

function sectorMode() {
  s.view = "sector";
  els.shipsToggle.checked = false;
  resetCamera(); renderSidebar(); refreshToolbar(); renderStartGuide();
}
function resetCamera() {
  s.zoom = 1;
  s.pan = {x: 0, y: 0};
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
    button.appendChild(textEl("span",ship.name??ship.id));
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
    ship_group:"ГРУППА КОРАБЛЕЙ", facility_group:"ГРУППА ОБЪЕКТОВ"
  };
  els.inspectorBody.appendChild(textEl("div", typeNames[type], "kind"));
  els.inspectorBody.appendChild(textEl("h2", entity.name ?? entity.id));
  const content = els.inspectorBody;
  if (type === "ship_group" || type === "facility_group") {
    const isShip = type === "ship_group";
    const members = entity.members;
    inspectorRow(content, "Всего", members.length);
    content.appendChild(textEl("p",
      "Несколько реальных объектов отображаются одним значком, чтобы карта не превращалась в стену символов. Выберите нужный объект из списка.",
      "small-note"));
    for (const member of members.slice(0, 140)) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "group-member";
      button.appendChild(textEl("span", member.name ?? member.id));
      button.appendChild(textEl("span", isShip ? (member.current_goal ?? member.class ?? "") :
        (member.type ?? ""), "group-member-note"));
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
    inspectorRow(content, "Класс", entity.class);
    inspectorRow(content, "Размер", entity.size ?? "—");
    inspectorRow(content, "Фракция", factionName(entity.faction_id, s.index));
    inspectorRow(content, "Цель ИИ", entity.current_goal);
    inspectorRow(content, "Действие", entity.current_bt ?? "—");
    inspectorRow(content, "Положение", entity.location ?? (entity.transit ? "В пути" : "Неизвестно"));
    if (entity.transit) {
      inspectorRow(content, "Из", entity.transit.from);
      inspectorRow(content, "В", entity.transit.to);
      inspectorRow(content, "Пройдено", fnum(entity.transit.distance_travelled) + " / " + fnum(entity.transit.distance_total));
    }
    inspectorRow(content, "Топливо", fnum(entity.fuel) + " / " + fnum(entity.fuel_capacity));
    inspectorRow(content, "Кредиты", fnum(entity.credits));
    inspectorRow(content, "Экипаж", entity.crew?.size ?? "—");
    detailGroup(content, "Груз");
    chips(content, sortedCargo(entity.cargo).map(([name,amount]) => name + ": " + amount));
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
    inspectorRow(content, "Тип", entity.type);
    inspectorRow(content, "Фракция", factionName(entity.faction_id, s.index));
    inspectorRow(content, "Расположение", entity.location);
    inspectorRow(content, "Состояние", Math.round(number(entity.condition) * 100) + "%");
    inspectorRow(content, "Уровень", entity.level);
    inspectorRow(content, "Кредиты", fnum(entity.credits));
    inspectorRow(content, "Корабли у причала", list(entity.docked_ships).length);
    inspectorRow(content, "Заброшен", entity.abandoned ? "Да" : "Нет");
    if (entity.gate_link) inspectorRow(content, "Связанные врата", entity.gate_link.paired_gate_id);
    detailGroup(content, "Запасы");
    chips(content, Object.entries(entity.reserves ?? {}).filter(([,v])=>number(v)>0).map(([k,v])=>k + ": " + fnum(v)));
    // Show the actual commodity market attached to this facility location.
    const market = list(s.report.markets).find(m => key(m.facility_location) === key(entity.location));
    if (market) {
      detailGroup(content, "Рынок — товары");
      const commodities = [...new Set([
        ...Object.keys(market.prices ?? {}), ...Object.keys(market.supply ?? {})
      ])].sort((a,b) => number(market.shortage_ticks?.[b]) - number(market.shortage_ticks?.[a]));
      for (const commodity of commodities.slice(0, 16)) {
        inspectorRow(content, commodity,
          "Цена " + fnum(market.prices?.[commodity]) +
          " · запас " + fnum(market.supply?.[commodity]) +
          " · спрос " + fnum(market.demand?.[commodity]));
      }
    }
    showHubShips(content,entity.location);
  } else if (type === "body") {
    inspectorRow(content, "Тип", entity.type);
    inspectorRow(content, "Биом", entity.biome ?? "—");
    inspectorRow(content, "Фракция", factionName(entity.controlling_faction, s.index));
    inspectorRow(content, "Спорная", entity.contested ? "Да" : "Нет");
    inspectorRow(content, "Радиус орбиты", entity.orbit_radius);
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
  const names = [
    ["ship_name","Корабль"],["ship_id","Корабль"],["facility_name","Объект"],
    ["facility_id","Объект"],["location","Место"],["destination","Куда"],
    ["commodity","Товар"],["quantity","Количество"],["faction_id","Фракция"]
  ];
  const summary = names.filter(([field]) => event?.[field] != null)
    .slice(0,3).map(([field,label]) => label + ": " + event[field]).join(" · ");
  return {kind,detail:summary || "Изменение в симуляции"};
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
function handleEvents(tick, events) {
  for (const event of list(events)) s.events.unshift({tick,event});
  s.events.length = Math.min(s.events.length,100);
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
    const bodies = sys.bodies.map(b => point(b)).filter(Boolean);
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
  circle(at.x,at.y,12,"#e7bf78");
  circle(at.x,at.y,13,"rgba(255,222,165,.55)",false);
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
  const r=belt?8:body.type==="moon"?5:9;
  ctx.save();
  if(belt){
    ctx.strokeStyle="rgba(210,174,113,.58)";ctx.lineWidth=1;
    ctx.beginPath();ctx.ellipse(p.x,p.y,13,7,-.4,0,Math.PI*2);ctx.stroke();
    circle(p.x-5,p.y+1,3.3,tint);circle(p.x+3,p.y-3,4,tint);circle(p.x+6,p.y+3,2.4,tint);
  }else{
    circle(p.x,p.y,r,tint);
    ctx.fillStyle="rgba(255,255,255,.24)";
    ctx.beginPath();ctx.arc(p.x-r*.28,p.y-r*.3,Math.max(1.4,r*.35),0,Math.PI*2);ctx.fill();
  }
  if(selected||body.contested){
    ctx.lineWidth=1.4;circle(p.x,p.y,r+7,selected?"#bce8df":"#dfb472",false);
  }
  ctx.restore();
}
function drawFacilityHub(at,kind,selected) {
  // Purposeful silhouettes instead of a hexagon with multiple tiny
  // squares that became an unintelligible 'skull' when scaled.
  const mine=kind==="mining_rig";
  const line=selected?"#e9fff7":mine?"#d5b275":"#84c4c7";
  ctx.save();
  ctx.translate(at.x,at.y);
  ctx.lineWidth=selected?2:1.6;
  ctx.lineJoin="round";
  ctx.fillStyle="rgba(10,30,43,.94)";
  ctx.strokeStyle=line;
  ctx.beginPath();
  if(mine) {
    ctx.moveTo(0,-11);ctx.lineTo(12,0);
    ctx.lineTo(0,11);ctx.lineTo(-12,0);ctx.closePath();
  } else {
    ctx.roundRect(-12,-9,24,18,4);
  }
  ctx.fill();ctx.stroke();
  // A single legible feature at normal zoom: docking bar or ore seam.
  ctx.beginPath();
  if(mine) {
    ctx.moveTo(-5,4);ctx.lineTo(0,-4);ctx.lineTo(5,4);
  } else {
    ctx.moveTo(-6,0);ctx.lineTo(6,0);
  }
  ctx.stroke();
  if(selected) {
    ctx.strokeStyle="rgba(177,238,221,.45)";
    ctx.beginPath();ctx.arc(0,0,16,0,2*Math.PI);ctx.stroke();
  }
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
function drawShip(ship,at,color,selected,scale=1) {
  ctx.save();ctx.translate(at.x,at.y);
  const move=s.shipMotion.get(ship.id);
  const mx=(move?.dx??0)*scale,my=-(move?.dy??0)*scale;
  const speed=Math.hypot(mx,my);
  if(speed>.08){
    // Only visible when the real current position changes.
    const unitX=mx/speed,unitY=my/speed;
    const trail=ctx.createLinearGradient(0,0,-unitX*20,-unitY*20);
    trail.addColorStop(0,"rgba(112,210,221,.6)");
    trail.addColorStop(1,"rgba(112,210,221,0)");
    ctx.strokeStyle=trail;ctx.lineWidth=2.1;ctx.beginPath();
    ctx.moveTo(-unitX*5,-unitY*5);ctx.lineTo(-unitX*20,-unitY*20);ctx.stroke();
    ctx.rotate(Math.atan2(my,mx)+Math.PI/2);
  }
  const r=selected?8.5:7;
  const hull=String(ship.class??"").toLowerCase();
  if(hull==="courier"){
    ctx.beginPath();ctx.moveTo(0,-r*1.3);ctx.lineTo(r*.7,r*.88);
    ctx.lineTo(0,r*.25);ctx.lineTo(-r*.7,r*.88);ctx.closePath();
  }else if(hull==="freighter"||hull==="hauler"||hull==="tanker"){
    ctx.beginPath();ctx.moveTo(0,-r*1.15);ctx.lineTo(r*.92,-r*.12);
    ctx.lineTo(r*.8,r*.95);ctx.lineTo(-r*.8,r*.95);
    ctx.lineTo(-r*.92,-r*.12);ctx.closePath();
  }else{
    ctx.beginPath();ctx.moveTo(0,-r*1.2);ctx.lineTo(r,r);
    ctx.lineTo(0,r*.35);ctx.lineTo(-r,r);ctx.closePath();
  }
  ctx.fillStyle=color;ctx.fill();ctx.lineWidth=1.3;ctx.strokeStyle="#dbeef1";ctx.stroke();
  if(selected){ctx.lineWidth=1.2;circle(0,0,r+8,"#b0eddd",false);}
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
  const iconScale=mapIconScale(s.zoom);
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
      withMapScale(center,iconScale,()=>drawSun(center));
      markGlyph(center,15*iconScale);
      askLabel("sun-"+sys.name,center,sys.name+" · звезда","#eed09a",50,17,140);
      for(const body of sys.bodies){
        const p=liveWorldPoint(body);if(!p)continue;const screen=toScreen(p);
        if(!visible(screen,26))continue;
        withMapScale(screen,iconScale,()=>drawBody(body,screen,isSelected("body",body.id)));
        markGlyph(screen,14*iconScale);
        askLabel("body-"+body.id,screen,body.name,"#bdcfdc",40,14,135,true);
        addTarget("body",body.id,screen.x,screen.y,Math.max(13,13*iconScale),body.name);
      }
      // A spaceport is one place, regardless of how many factories,
      // stations and shipyards share its location. Their full list is
      // available in the inspector after clicking the hub.
      for(const hub of groupFacilitiesByLocation(
        s.index.systemFacilities.get(sys.name)??[])){
        const members=hub.members;
        const prefer=members.find(x=>x.type==="station") ??
          members.find(x=>x.type==="mining_rig") ??
          members.find(x=>x.type==="shipyard") ?? members[0];
        const p=liveWorldPoint(prefer);
        if(!p)continue;
        const at=toScreen(p);
        if(!visible(at,30))continue;
        const ids=members.map(x=>x.id);
        const selected=ids.includes(s.selection?.id) ||
          (s.selection?.type==="facility_group" &&
          s.selection.ids?.some(id=>ids.includes(id)));
        withMapScale(at,iconScale,()=>drawFacilityHub(at,prefer.type,selected));
        markGlyph(at,14*iconScale);
        const parked=showShips?shipsAtHub(s.ships,hub.location):[];
        // The label stays short: each parked vessel gets its own
        // anchored, selectable icon drawn below in the ships layer.
        askLabel("hub-"+hub.id,at,prefer.name,
          prefer.type==="mining_rig"?"#d5b275":"#84c4c7",
          selected?1:15,17,205);
        hubAnchors.set(key(hub.location),{at,parked});
        const targetType=members.length>1?"facility_group":"facility";
        addTarget(targetType,members.length>1?hub.id:members[0].id,
          at.x,at.y,Math.max(15,15*iconScale),prefer.name,
          members.length>1?ids:null);
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
          askLabel("parked-"+ship.id,at,ship.name??ship.class,
            "#c2dce4",selected?0:5,13,140);
          addTarget("ship",ship.id,at.x,at.y,Math.max(12,12*iconScale),
            (ship.name??ship.id)+" · у станции");
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
        askLabel("ship-"+ship.id,at,ship.name??ship.class,
          "#c2dce4",selected?0:3,16,145);
        addTarget("ship",ship.id,at.x,at.y,
          Math.max(selected?15:12,12*iconScale),ship.name);
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
      const priority={ship:0,ship_group:0,facility:1,facility_group:1,body:2,system:3};
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
        renderInspector();refreshToolbar();renderSidebar();
      }
    }
  });
  els.map.addEventListener("pointercancel",()=>{s.dragging=null;els.map.classList.remove("grabbing");});
  els.map.addEventListener("pointerleave",()=>{els.hoverLabel.hidden=true;});
  els.map.addEventListener("dblclick",e=>{
    const p=toLocal(e),target=nearestTarget(p.x,p.y);
    if(target?.type==="system")chooseSystem(target.id,true);
    else if(target?.type==="ship_group" || target?.type==="facility_group") changeZoomAt(p,2);
  });
  els.map.addEventListener("wheel",e=>{
    e.preventDefault();
    const pointer=toLocal(e);
    changeZoomAt(pointer,e.deltaY<0?1.18:1/1.18);
  },{passive:false});
  els.map.addEventListener("keydown",e=>{
    if(e.key==="Escape"){sectorMode();els.map.blur();}
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
  els.systemSearch.addEventListener("input",renderSidebar);
  els.clearEvents.addEventListener("click",()=>{s.events=[];renderEvents();});
  els.clearSelection.addEventListener("click",()=>{s.selection=null;renderInspector();});
  els.startSystemBtn.addEventListener("click",()=>{
    const chosen = s.index?.systems.find(x => x.name === "Sol") ?? s.index?.systems[0];
    if (chosen) chooseSystem(chosen.name, true);
  });
  els.dismissGuideBtn.addEventListener("click",()=>{s.guideDismissed=true;renderStartGuide();});
  installCanvasHandlers();
}

wireControls();
renderMap();
fetchReport().then(()=>{connectWs();fetchHealth();});
window.setInterval(fetchReport,18000);
window.setInterval(fetchHealth,2500);
window.setInterval(()=>{refreshToolbar();renderInspector();},2200);
window.addEventListener("beforeunload",()=>s.ws?.close());
