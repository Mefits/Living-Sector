import {
  list, number, point, key, buildIndex, factionColor, factionName,
  systemByName, positionOf, sortedCargo,
  panForCursorZoom, clusterMarkers, shipSystem, worldGridStep, mapIconScale,
  groupFacilitiesByLocation, layoutMapLabels, shipMapState, shipsAtHub,
  liveEntityPoint, approachWorldPoint,
  commodityLabel
} from "/observer/model.js";

const byId = id => document.getElementById(id);
const els = Object.fromEntries([
  "connection","connection-text","system-picker","system-search","system-list","faction-legend",
  "map-title","map-summary","pause-btn","speed-select","sector-tab","system-tab","map-layers",
  "ships-toggle","links-toggle","labels-toggle","fit-btn","map","canvas-holder","hover-label",
  "map-error","map-legend","events-toggle","event-count","timeline","event-feed","clear-events",
  "inspector","inspector-body","inspector-back","clear-selection","fleet-strip"
].map(id => [id.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase()), byId(id)]));

const s = {
  report: null, index: null, ships: [], health: null, positions: new Map(),
  ws: null, wsUp: false, live: false, events: [],
  view: "sector", systemName: null, selection: null, selectionHistory: [],
  zoom: 1, pan: {x: 0, y: 0}, dragging: null, hover: null,
  targets: [], visualPositions: new Map(), shipMotion: new Map(),
  mapWorldPositions: new Map(),
  lastReportAt: 0, fetching: false, error: null
};
const fmt = new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 1 });
const q = value => value == null ? "—" : String(value);
const fnum = value => value == null ? "—" : fmt.format(number(value));
const ctx = els.map.getContext("2d");
let pixels = { w: 0, h: 0 };

function setOnline(isOnline, statusText) {
  s.live = isOnline;
  els.connection.classList.toggle("online", isOnline);
  if (!isOnline || !s.health) els.connectionText.textContent = statusText;
  els.connection.classList.toggle("paused", isOnline && s.health?.running === false);
  els.mapError.hidden = isOnline || !s.report;
  refreshToolbar();
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

function saveReport(report) {
  if (!Array.isArray(report?.systems)) throw new Error("Нет systems[] в /api/report");
  if (s.report && report.tick < s.report.tick) return;
  const firstReport = !s.report;
  s.report = report;
  s.ships = list(report.ships);
  s.index = buildIndex(report);
  s.lastReportAt = Date.now();
  // In a one-system world, open the system directly.
  if (firstReport && s.index.systems.length === 1) {
    s.systemName = s.index.systems[0].name;
    s.view = "system";
    s.selection = null;
    els.shipsToggle.checked = true;
    resetCamera();
  }
  if (s.systemName && !systemByName(s.systemName, s.index)) {
    s.view = "sector"; s.systemName = null; s.selection = null; s.selectionHistory = [];
  }
  renderSidebar();
  renderInspector();
  refreshToolbar();
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
  const h = s.health ?? s.report;
  if (!h) return;
  const running = h.running === true;
  if (s.live && typeof h.running === "boolean") {
    const status = h.save_error ? "Ошибка сохранения" : running ? "Симуляция идёт" : "На паузе";
    if (h.save_error) els.connection.title = h.save_error;
    if (els.connectionText.textContent !== status) els.connectionText.textContent = status;
    els.connection.classList.toggle("paused", !running);
  }
  els.pauseBtn.textContent = running ? "Ⅱ Пауза" : "▶ Продолжить";
  if (s.index) {
    const inSystem = s.view === "system";
    const system = inSystem ? systemByName(s.systemName, s.index) : null;
    const systemCount = s.index.systems.length;
    els.mapTitle.textContent = system?.name ?? "Сектор";
    els.mapSummary.textContent = system
      ? "Тела " + list(system.bodies).length + " · Объекты " + (s.index.systemFacilities.get(system.name)?.length ?? 0)
      : "Системы " + systemCount;
    els.systemTab.disabled = !s.systemName;
    els.sectorTab.classList.toggle("active", !inSystem);
    els.systemTab.classList.toggle("active", inSystem);
    els.sectorTab.setAttribute("aria-pressed", String(!inSystem));
    els.systemTab.setAttribute("aria-pressed", String(inSystem));
    els.mapLegend.hidden = !inSystem;
    els.linksToggle.closest("label").hidden = inSystem;
    els.systemPicker.hidden = inSystem && systemCount === 1;
    if (els.systemPicker.hidden) els.systemPicker.open = false;
  }
  renderOreFlow();
  renderGovernance();
  const speed = h.world_speed ?? h.config?.world_speed;
  if (speed != null && !els.speedSelect.matches(":focus")) {
    const closest = [...els.speedSelect.options].reduce((best, opt) =>
      Math.abs(Number(opt.value) - speed) < Math.abs(Number(best.value) - speed) ? opt : best,
      els.speedSelect.options[0]);
    els.speedSelect.value = closest.value;
  }
  renderFleet();
}

function renderGovernance() {
  const gov = s.report?.governance;
  if (!gov) return;
  const panel = document.getElementById("faction-policy");
  panel.replaceChildren();
  inspectorRow(panel, "Глава", gov.leader);
  inspectorRow(panel, "Курс", gov.policy);
  inspectorRow(panel, "Резерв топлива", fnum(gov.fuel_floor) + " из " + fnum(gov.station_fuel));
  inspectorRow(panel, "Руда на станции", fnum(gov.station_ore) + " · цель " + fnum(gov.ore_target));
  inspectorRow(panel, "Груз в трюме", fnum(gov.cargo));
  inspectorRow(panel, "Металл", fnum(gov.metal));
  inspectorRow(panel, "Снабженец", gov.logistics);
  inspectorRow(panel, "Промышленник", gov.industry);
  inspectorRow(panel, "Грузовик", gov.ship);
  if (gov.last_decision) inspectorRow(panel, "Решение главы", gov.last_decision);
}

function renderOreFlow() {
  if (!s.report?.genesis_ore_loop || s.view !== "system") return;
  const markets = list(s.report.markets);
  const stockAt = location => markets.find(m => m.facility_location === location)?.supply;
  const cargo = s.ships.reduce((sum, ship) => sum + (ship.cargo?.ore ?? 0), 0);
  els.mapSummary.textContent = "Руда · Пояс " + fnum(stockAt("belt-outpost")?.ore) +
    " → Трюм " + fnum(cargo) + " → Станция " + fnum(stockAt("earth-station")?.ore) +
    " · Металл " + fnum(stockAt("earth-station")?.metals);
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
    item.addEventListener("click", () => chooseSystem(system.name));
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

function setSelection(selection, drillDown = false) {
  if (drillDown) s.selectionHistory.push(s.selection);
  else s.selectionHistory = [];
  s.selection = selection;
  renderInspector();
  renderFleet();
}

function chooseSystem(name) {
  if (!s.index || !systemByName(name, s.index)) return;
  const changed = s.systemName !== name || s.view !== "system";
  s.systemName = name;
  if (s.view !== "system") {
    s.view = "system";
    els.shipsToggle.checked = true;
  }
  if (changed) resetCamera();
  els.systemPicker.open = false;
  setSelection(null);
  renderSidebar();
  refreshToolbar();
}

function sectorMode() {
  if (s.view === "sector") return;
  s.view = "sector";
  els.shipsToggle.checked = false;
  setSelection(null);
  resetCamera();
  renderSidebar();
  refreshToolbar();
}

function shipStatus(ship) {
  if (ship.status_label) return ship.status_label;
  const state = shipMapState(ship);
  if (state === "in_transit") return "В пути";
  if (state === "docked") return "У причала";
  return state === "at_location" ? "На месте" : "Положение не указано";
}

function renderFleet() {
  // Keep this a quick selector for Genesis-sized rosters. Larger worlds
  // can still use the ship layer and the location's existing ship list.
  const ships = s.view === "system" && s.ships.length <= 8 ? s.ships.filter(ship =>
    s.index.systems.length === 1 || shipSystem(ship, s.index) === s.systemName) : [];
  els.fleetStrip.hidden = ships.length === 0;
  const ids = ships.map(ship => String(ship.id));
  const buttons = [...els.fleetStrip.children];
  if (buttons.length !== ids.length || buttons.some((button, i) => button.dataset.shipId !== ids[i])) {
    els.fleetStrip.replaceChildren(...ships.map(ship => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "fleet-ship";
      button.dataset.shipId = String(ship.id);
      button.append(textEl("span", ship.name ?? ship.id), textEl("span", "", "fleet-status"));
      button.addEventListener("click", () => setSelection({type:"ship", id:ship.id}));
      return button;
    }));
  }
  ships.forEach((ship, i) => {
    const button = els.fleetStrip.children[i];
    const status = shipStatus(ship);
    if (button.lastChild.textContent !== status) button.lastChild.textContent = status;
    button.lastChild.dataset.transit = String(shipMapState(ship) === "in_transit");
    button.setAttribute("aria-pressed", String(s.selection?.type === "ship" && s.selection.id === ship.id));
  });
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
function chips(parent, entries, max = 8, emptyLabel = "Нет данных") {
  const items = list(entries).slice(0, max);
  if (!items.length) return parent.appendChild(textEl("p", emptyLabel, "small-note"));
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
      shipStatus(ship),
      "group-member-note"));
    button.addEventListener("click",()=>{
      setSelection({type:"ship",id:ship.id}, true);
    });
    content.appendChild(button);
  }
}


let lastInspectorSelection = "";
function renderInspector() {
  const selectionKey = s.selection ? s.selection.type + ":" + s.selection.id : "";
  const sameSelection = selectionKey === lastInspectorSelection;
  const previousScroll = sameSelection ? els.inspectorBody.scrollTop : 0;
  lastInspectorSelection = selectionKey;
  els.inspectorBody.replaceChildren();
  const entity = selectionEntity();
  els.inspector.hidden = !entity;
  els.inspectorBack.hidden = s.selectionHistory.length === 0;
  if (!entity) return;
  const type = s.selection.type;
  const typeNames = {
    system:"ЗВЁЗДНАЯ СИСТЕМА",ship:"КОРАБЛЬ",facility:"ОБЪЕКТ",body:"НЕБЕСНОЕ ТЕЛО",
    ship_group:"ГРУППА КОРАБЛЕЙ", facility_group:"ЛОГИСТИЧЕСКИЙ ХАБ"
  };
  els.inspectorBody.appendChild(textEl("div", typeNames[type], "kind"));
  els.inspectorBody.appendChild(textEl("h2", entity.name ?? entity.id));
  const content = els.inspectorBody;
  if (type === "ship_group" || type === "facility_group") {
    const isShip = type === "ship_group";
    const members = entity.members;
    if (!isShip && members.length) showHubShips(content, members[0].location);
    detailGroup(content, (isShip ? "Корабли" : "Инфраструктура") + " · " + members.length);
    for (const member of members.slice(0, 140)) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "group-member";
      button.appendChild(textEl("span", member.name ?? member.id));
      button.appendChild(textEl("span", isShip ? shipStatus(member) : (facilityNames[member.type] ?? member.type ?? ""), "group-member-note"));
      button.addEventListener("click", () => {
        setSelection({type: isShip ? "ship" : "facility", id: member.id}, true);
      });
      content.appendChild(button);
    }
    if (members.length > 140) {
      content.appendChild(textEl("p",
        "Показаны первые 140 объектов; для остальных приблизьте карту или откройте их через другой район.",
        "small-note"));
    }
    if (!isShip && members.length) showMarket(content, members[0].location);
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
    inspectorRow(content, "Инфраструктура", facilities.length);
    inspectorRow(content, "Склады", markets.length);
    if (s.view === "sector") {
      const openSystem = textEl("button", "Открыть систему", "small-button");
      openSystem.addEventListener("click", () => chooseSystem(entity.name));
      content.appendChild(openSystem);
    }
    detailGroup(content, "Объекты системы");
    chips(content, facilities.map(f => f.name), 16);
    detailGroup(content, "Склады");
    chips(content, markets.map(m => m.facility_location), 16);
  } else if (type === "ship") {
    const status = document.createElement("div");
    status.className = "ship-status";
    status.appendChild(textEl("strong", shipStatus(entity)));
    if (entity.transit) {
      const {from, to, distance_travelled, distance_total} = entity.transit;
      status.appendChild(textEl("span", locationLabel(from) + " → " + locationLabel(to)));
      if (distance_total > 0 && Number.isFinite(distance_travelled)) {
        const progress = document.createElement("progress");
        progress.max = distance_total;
        progress.value = distance_travelled;
        progress.setAttribute("aria-label", "Прогресс перелёта");
        status.appendChild(progress);
      }
    } else if (entity.location) {
      status.appendChild(textEl("span", locationLabel(entity.location)));
    }
    content.appendChild(status);
    detailGroup(content, "Груз");
    chips(content, sortedCargo(entity.cargo).map(([name, amount]) =>
      commodityLabel(name) + " · " + fnum(amount)), 8, "Трюм пуст");
    inspectorRow(content, "Топливо", fnum(entity.fuel) + " / " + fnum(entity.fuel_capacity));
  } else if (type === "facility") {
    inspectorRow(content, "Тип", facilityNames[entity.type] ?? entity.type);
    inspectorRow(content, "Фракция", factionName(entity.faction_id, s.index));
    inspectorRow(content, "Расположение", locationLabel(entity.location, entity.id));
    if (entity.project) inspectorRow(content, "Проект", entity.project);
    if (entity.progress != null) inspectorRow(content, "Готовность", Math.floor(entity.progress * 100) + "%");
    if (entity.deposit != null) inspectorRow(content, "Руда в залежи", fnum(entity.deposit));
    showHubShips(content, entity.location);
    inspectorRow(content, "Резерв топлива", fnum(entity.reserves.fuel));
    showMarket(content, entity.location);
  } else if (type === "body") {
    inspectorRow(content, "Тип", entity.type);
    inspectorRow(content, "Фракция", factionName(entity.controlling_faction, s.index));
    inspectorRow(content, "Радиус орбиты", entity.orbit_radius);
  }
  els.inspectorBody.scrollTop = previousScroll;
}

const facilityNames = {
  "pirate-station":"Пиратская база",
  construction_site:"Строительная площадка",
  station:"Станция", mining_rig:"Добыча", farm:"Ферма",
  refinery:"Переработка", factory:"Завод", shipyard:"Верфь", gate:"Врата"
};

function locationLabel(location, exceptId) {
  if (location == null) return "—";
  const facilities = list(s.report?.facilities).filter(f => key(f.location) === key(location));
  const hub = facilities.find(f => f.type === "station" || f.type === "mining_rig") ?? facilities[0];
  return hub?.id === exceptId ? location : (hub?.name ?? location);
}

function showMarket(content, location) {
  const market = list(s.report.markets).find(m => key(m.facility_location) === key(location));
  if (!market) return;
  detailGroup(content, "Склад");
  inspectorRow(content, "Руда", fnum(market.supply.ore));
  if (market.metal_capacity != null) {
    inspectorRow(content, "Металл", fnum(market.supply.metals) + " / " + fnum(market.metal_capacity));
    inspectorRow(content, "Доставка", market.delivery_status);
    inspectorRow(content, "Плавка", market.smelting_status);
  }
}

const eventNames = {
  ore_extracted: "Руда добыта", cargo_loaded: "Руда погружена", cargo_unloaded: "Руда доставлена",
  pirate_base_built: "Пиратская база собрана",
  raider_built: "Рейдер собран",
  raid_delivered: "Трофеи доставлены пиратам",
  raid_deflected: "Перехват сорван",
  raid_stolen: "Пираты захватили руду",
  patrol_order: "Заказан патрульный корабль",
  patrol_inputs: "Материалы доставлены на верфь",
  patrol_ready: "Патрульный корабль готов",
  yard_dispatched: "Материалы в пути",
  yard_assembly: "Начат монтаж верфи",
  yard_completed: "Верфь готова",
  ship_order: "Заказан грузовик",
  ship_completed: "Грузовик собран",
  ship_commissioned: "Грузовик принят во флот",
  policy_changed: "Смена курса",
  smelt_started: "Запущена плавка",
  ore_cancelled: "Заявка закрыта",
  ore_requested: "Станция запросила руду",
  metal_smelted: "Металл выплавлен",
};
function eventLabel(event) {
  if (event.reason) return {kind: eventNames[event.kind], detail: event.actor + " · " + event.reason};
  const parts = [
    locationLabel(event.location),
    commodityLabel(event.commodity) + " · " + fnum(event.quantity),
    "На складе " + fnum(event.stock),
  ];
  if (event.ship_name || event.actor) parts.unshift(event.ship_name || event.actor);
  return {kind: eventNames[event.kind], detail: parts.join(" · ")};
}
const eventRows = new WeakMap();
function renderEvents() {
  els.eventCount.textContent = fnum(s.events.length);
  if (els.timeline.hidden) return;
  if (!s.events.length) {
    els.eventFeed.replaceChildren(textEl("div", "События появятся по мере работы симуляции", "empty"));
    return;
  }
  els.eventFeed.querySelector(".empty")?.remove();
  const visible = s.events.slice(0, 70);
  for (const entry of visible.slice().reverse()) {
    if (eventRows.get(entry)?.isConnected) continue;
    const {tick, event} = entry;
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
    eventRows.set(entry, row);
    els.eventFeed.prepend(row);
  }
  while (els.eventFeed.childElementCount > visible.length) els.eventFeed.lastElementChild.remove();
}
function handleEvents(tick, events) {
  for (const event of list(events)) s.events.unshift({tick,event});
  s.events.length = Math.min(s.events.length,100);
  renderEvents();
}

function handleWs(message) {
  if (message.type !== "genesis_update" || !s.report) return;
  if (list(message.events).length) handleEvents(message.tick, message.events);
  if (message.tick < s.report.tick) return;
  s.report.tick = message.tick;
  for (const entity of list(message.entities)) {
    s.positions.set(entity.id, {x: entity.x, y: entity.y});
  }
  s.ships = list(message.ships);
  s.report.ships = s.ships;
  s.report.markets = list(message.markets);
  s.report.governance = message.governance;
  s.report.facilities = message.facilities;
  s.index = buildIndex(s.report);
  if (s.health) s.health.tick = message.tick;
  renderOreFlow();
  renderGovernance();
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
    const orbit = Math.max(1, ...sys.bodies.map(body => {
      const pos = point(body);
      return pos ? Math.hypot(pos.x - sys.x, pos.y - sys.y) : 0;
    }));
    const span = (orbit + 0.45) * 2;
    return {cx:sys.x,cy:sys.y,sx:span,sy:span};
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
function bodyBiome(body) {
  const biome = key(body.biome);
  // Older snapshots can omit the biome. Keep the two known Sol planets
  // recognizable without altering their simulated properties.
  return biome || ({earth:"terrestrial", mars:"desert"}[key(body.id)] ?? "");
}
function bodyColor(body){
  const biome=bodyBiome(body);
  if(body.type==="moon" || biome==="lifeless")return "#a8b5c9";
  if(body.type==="belt" || body.type==="asteroid" || biome==="asteroid")return "#cba16c";
  if(biome==="terrestrial")return "#4b9cc4";
  if(biome==="desert" || biome==="molten")return "#bd8066";
  if(biome==="gas_giant")return "#c4ae85";
  return "#8eb0c7";
}
function bodyRadius(body) {
  if (bodyBiome(body) === "gas_giant") return 16;
  if (body.id === "mars") return 7;
  return body.type === "moon" ? 5 : body.type === "belt" || body.type === "asteroid" ? 8 : 10;
}

function drawMapSprite(name, x, y, size) {
  const sprite = byId("map-sprite-" + name);
  if (!sprite?.complete || !sprite.naturalWidth) return false;
  const scale = size / Math.max(sprite.naturalWidth, sprite.naturalHeight);
  const width = sprite.naturalWidth * scale;
  const height = sprite.naturalHeight * scale;
  ctx.drawImage(sprite, x - width / 2, y - height / 2, width, height);
  return true;
}

function drawBody(body, p, selected = false) {
  const tint = bodyColor(body);
  const belt = body.type === "belt" || body.type === "asteroid";
  const r = bodyRadius(body);
  ctx.save();
  if (belt) {
    ctx.strokeStyle = "rgba(210,174,113,.40)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.ellipse(p.x, p.y, 13, 7, -.4, 0, Math.PI * 2);
    ctx.stroke();
    const rocks = [[-6,1,3.2],[2,-3,4],[6,3,2.3],[-2,4,1.3]];
    for (const [index, [x, y, radius]] of rocks.entries()) {
      if (drawMapSprite("rock-" + (index % 3 + 1), p.x+x, p.y+y, radius*2)) continue;
      ctx.fillStyle = tint;
      ctx.beginPath();
      ctx.moveTo(p.x+x-radius, p.y+y-radius*.3);
      ctx.lineTo(p.x+x-radius*.3, p.y+y-radius);
      ctx.lineTo(p.x+x+radius, p.y+y-radius*.4);
      ctx.lineTo(p.x+x+radius*.65, p.y+y+radius);
      ctx.lineTo(p.x+x-radius*.65, p.y+y+radius*.55);
      ctx.fill();
    }
  } else if (!drawMapSprite("body-" + key(body.id), p.x, p.y, r * 2)) {
    ctx.translate(p.x, p.y);
    ctx.scale(r, r);
    ctx.beginPath();
    ctx.arc(0, 0, 1, 0, Math.PI * 2);
    ctx.clip();
    ctx.fillStyle = tint;
    ctx.fillRect(-1, -1, 2, 2);
    if (bodyBiome(body) === "terrestrial") {
      ctx.fillStyle = "#739b7c";
      ctx.beginPath();
      ctx.moveTo(-.78,-.45); ctx.lineTo(-.45,-.69); ctx.lineTo(.02,-.53);
      ctx.lineTo(-.12,-.27); ctx.lineTo(-.32,-.19); ctx.lineTo(-.25,.03);
      ctx.lineTo(-.53,.36); ctx.lineTo(-.63,.09); ctx.lineTo(-.53,-.18);
      ctx.moveTo(.16,-.17); ctx.lineTo(.54,-.43); ctx.lineTo(.88,-.21);
      ctx.lineTo(.69,.08); ctx.lineTo(.41,.13); ctx.lineTo(.37,.43); ctx.lineTo(.18,.24);
      ctx.fill();
      ctx.strokeStyle = "#d0e4e5a0";
      ctx.lineWidth = .09;
      ctx.beginPath();
      ctx.ellipse(-.15, -.52, .74, .13, -.21, Math.PI, Math.PI * 1.88);
      ctx.stroke();
      ctx.beginPath();
      ctx.ellipse(.25, .39, .74, .13, -.2, .15, Math.PI);
      ctx.stroke();
    } else {
      for (const [x,y,radius] of [[-.32,-.35,.24],[.33,-.19,.19],[-.18,.44,.30],[.58,.35,.12]]) {
        circle(x,y,radius,"rgba(37,30,39,.19)");
        circle(x-.025,y-.035,radius*.57,"rgba(221,198,187,.13)");
      }
    }
    const shade = ctx.createLinearGradient(-.9,-.9,.85,.85);
    shade.addColorStop(0,"rgba(225,244,255,.36)");
    shade.addColorStop(.46,"rgba(10,22,34,0)");
    shade.addColorStop(1,"rgba(5,12,22,.82)");
    ctx.fillStyle = shade;
    ctx.fillRect(-1,-1,2,2);
    ctx.restore();
    ctx.save();
    ctx.lineWidth = .55;
    circle(p.x,p.y,r,"rgba(191,219,232,.42)",false);
  }
  if (selected || body.contested) {
    ctx.lineWidth = 1.2;
    circle(p.x,p.y,r+5,selected?"#bce8df":"#dfb472",false);
  }
  ctx.restore();
}

function drawFacilityHub(at, kind, selected) {
  const mine = kind === "mining_rig";
  const accent = mine ? "#dab27a" : "#8dd0d0";
  ctx.save();
  ctx.translate(at.x, at.y);
  const hasSprite = (mine || kind === "station" || kind === "shipyard" || kind === "pirate-station") &&
    drawMapSprite(mine ? "mining-rig" : kind, 0, 0, kind === "shipyard" ? 21 : 14);
  ctx.lineWidth = .85;
  ctx.lineJoin = "round";
  ctx.strokeStyle = "#b0c6ce";
  if (!hasSprite && mine) {
    ctx.fillStyle = "#554735";
    ctx.beginPath();
    ctx.moveTo(-5, 2); ctx.lineTo(-2, -4); ctx.lineTo(3, -4);
    ctx.lineTo(5, 1); ctx.lineTo(2, 4); ctx.lineTo(-4, 4);
    ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.fillStyle = accent;
    ctx.fillRect(-.8,-5.5,1.7,6);
    ctx.fillRect(-6,1,2.6,1.6);
  } else if (!hasSprite) {
    ctx.fillStyle = "#2f5269";
    ctx.fillRect(-6,-3,3,6);
    ctx.fillRect(3,-3,3,6);
    ctx.strokeRect(-6,-3,3,6);
    ctx.strokeRect(3,-3,3,6);
    ctx.fillStyle = "#405565";
    ctx.fillRect(-3,-1,6,2);
    ctx.fillStyle = "#879ca6";
    ctx.fillRect(-2.1,-4.5,4.2,9);
    ctx.fillStyle = "#d7e6e8";
    ctx.fillRect(-1.7,-4,1,7);
    ctx.fillStyle = accent;
    ctx.fillRect(.25,-2,1,3);
  }
  if (selected) {
    ctx.lineWidth = 1;
    circle(0,0,8,"#b0eddd",false);
  }
  ctx.restore();
}

function drawFacilityOrbit(center, station, bodySize) {
  const radius = Math.hypot(station.x - center.x, station.y - center.y);
  if (radius < bodySize + 4) return;
  ctx.save();
  ctx.lineWidth = 1;
  ctx.setLineDash([2, 4]);
  circle(center.x, center.y, radius, "rgba(131,185,196,.29)", false);
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
  const dx = old.x - oldX;
  const dy = old.y - oldY;
  const heading = Math.hypot(dx, dy) > 0.0001
    ? Math.atan2(-dy, dx) + Math.PI / 2
    : s.shipMotion.get(ship.id)?.heading ?? 0;
  s.shipMotion.set(ship.id,{dx,dy,heading});
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
    ctx.strokeStyle=trail;ctx.lineWidth=1.35;ctx.beginPath();
    ctx.moveTo(-unitX*4,-unitY*4);ctx.lineTo(-unitX*16,-unitY*16);ctx.stroke();
  }
  ctx.rotate(move?.heading ?? 0);
  const hull = key(ship.class);
  if (drawMapSprite(hull, 0, 0, hull === "courier" ? 10 : 12)) {
    circle(0, 5.5, 1, color);
  } else {
    ctx.beginPath();
    if (hull === "courier") {
      ctx.moveTo(0,-5); ctx.lineTo(3.1,3.6);
      ctx.lineTo(0,2.1); ctx.lineTo(-3.1,3.6);
    } else {
      ctx.moveTo(0,-4.5); ctx.lineTo(2.2,-3);
      ctx.lineTo(3.4,-1); ctx.lineTo(3.4,3.7);
      ctx.lineTo(-3.4,3.7); ctx.lineTo(-3.4,-1); ctx.lineTo(-2.2,-3);
    }
    ctx.closePath();
    ctx.fillStyle = "#70828f";
    ctx.fill();
    ctx.lineWidth = .7;
    ctx.strokeStyle = "#c5d7e3";
    ctx.stroke();
    ctx.fillStyle = color;
    ctx.fillRect(-.9,-2.5,1.8,3.5);
    ctx.fillStyle = "#b0d2da";
    ctx.fillRect(-2,2.8,1.1,1.1);
    ctx.fillRect(.9,2.8,1.1,1.1);
  }
  if (selected) { ctx.lineWidth = 1; circle(0,0,7,"#b0eddd",false); }
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
      const bodyScreens = new Map();
      for(const body of sys.bodies){
        const p=liveWorldPoint(body);if(!p)continue;const screen=toScreen(p);
        bodyScreens.set(key(body.id), {screen, radius:bodyRadius(body)*iconScale});
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
        const anchor = bodyScreens.get(key(prefer.body_id));
        if (anchor) drawFacilityOrbit(anchor.screen, at, anchor.radius);
        withMapScale(at,iconScale,()=>drawFacilityHub(at,prefer.type,selected));
        markGlyph(at,8*iconScale);
        askLabel("hub-"+hub.id,at,prefer.name,
          prefer.type==="mining_rig"?"#d5b275":"#84c4c7",
          selected?1:15,9,205);
        const targetType=members.length>1?"facility_group":"facility";
        addTarget(targetType,members.length>1?hub.id:members[0].id,
          at.x,at.y,Math.max(10,8*iconScale),prefer.name,
          members.length>1?ids:null);
      }
    }
  }
  if(showShips){
    const shipMarkers=[];
    const visibleShips=s.ships.filter(ship=>
      s.view!=="system" || s.index.systems.length===1 ||
      shipSystem(ship,s.index)===s.systemName);
    // Parked ships are available in the hub and fleet strip; only actual
    // transit gets an independent hull on the map.
    for (const ship of visibleShips) {
      if (shipMapState(ship) !== "in_transit") {
        s.visualPositions.delete(ship.id);
        s.shipMotion.delete(ship.id);
        continue;
      }
      const p = smoothPosition(ship, positionOf(ship, s.positions));
      if(!p)continue;
      const sc=toScreen(p);
      if(!visible(sc,20))continue;
      shipMarkers.push({...sc,ship});
    }
    for(const group of clusterMarkers(shipMarkers,34)){
      if(group.members.length>1){
        const ids=group.members.map(m=>m.ship.id);
        const selected=ids.includes(s.selection?.id);
        withMapScale(group,Math.min(iconScale,1.8),()=>
          drawShip(group.members[0].ship,group,"#84b9c5",
            selected,scale));
        markGlyph(group,8*iconScale);
        askLabel("ships-"+group.id,group,ids.length+" корабля",
          "#c2dce4",selected?0:5,9,118);
        addTarget("ship_group",group.id,group.x,group.y,
          Math.max(17,16*iconScale),ids.length+" кораблей",ids);
      }else{
        const {ship,x,y}=group.members[0];
        const at={x,y},selected=isSelected("ship",ship.id);
        withMapScale(at,iconScale,()=>drawShip(ship,at,
          factionColor(ship.faction_id,s.index),selected,scale));
        markGlyph(at,7*iconScale);
        askLabel("ship-"+ship.id,at,ship.name??ship.class,
          "#c2dce4",selected?0:3,8,145);
        addTarget("ship",ship.id,at.x,at.y,
          Math.max(9,7*iconScale),ship.name);
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
  let lastPick = null;
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
      const p = toLocal(e);
      const sameSpot = lastPick && e.timeStamp - lastPick.time < 500 &&
        Math.hypot(p.x - lastPick.x, p.y - lastPick.y) < 5;
      // Opening the dock can move the map before the second click.
      if (sameSpot) return;
      const target = nearestTarget(p.x, p.y);
      lastPick = target ? {...p, time:e.timeStamp, target} : null;
      if(target){
        if (target.type === "system") s.systemName = target.id;
        setSelection({type:target.type,id:target.id,ids:target.ids,name:target.name});
        refreshToolbar();
        renderSidebar();
      }
    }
  });
  els.map.addEventListener("pointercancel",()=>{s.dragging=null;els.map.classList.remove("grabbing");});
  els.map.addEventListener("pointerleave",()=>{els.hoverLabel.hidden=true;});
  els.map.addEventListener("dblclick",e=>{
    const p = toLocal(e);
    const target = lastPick?.target ?? nearestTarget(p.x, p.y);
    lastPick = null;
    if(target?.type==="system")chooseSystem(target.id);
    else if(target?.type==="ship_group" || target?.type==="facility_group") changeZoomAt(p,2);
  });
  els.map.addEventListener("wheel",e=>{
    e.preventDefault();
    const pointer=toLocal(e);
    changeZoomAt(pointer,e.deltaY<0?1.18:1/1.18);
  },{passive:false});
}

function wireControls() {
  els.pauseBtn.addEventListener("click",()=>control(
    s.health?.running?"/api/sim/pause":"/api/sim/resume",{}
  ));
  els.speedSelect.addEventListener("change",()=>control("/api/sim/speed",{
    world_speed:Number(els.speedSelect.value)
  }));
  els.sectorTab.addEventListener("click",sectorMode);
  els.systemTab.addEventListener("click",()=>{if(s.systemName)chooseSystem(s.systemName);});
  els.fitBtn.addEventListener("click",resetCamera);
  els.systemSearch.addEventListener("input",renderSidebar);
  els.eventsToggle.addEventListener("click", () => {
    els.timeline.hidden = !els.timeline.hidden;
    els.eventsToggle.setAttribute("aria-expanded", String(!els.timeline.hidden));
    renderEvents();
  });
  els.clearEvents.addEventListener("click", () => { s.events = []; renderEvents(); });
  els.clearSelection.addEventListener("click", () => {
    setSelection(null);
    els.map.focus({preventScroll:true});
  });
  els.inspectorBack.addEventListener("click", () => {
    s.selection = s.selectionHistory.pop() ?? null;
    renderInspector();
    renderFleet();
  });
  const popovers = [els.systemPicker, els.mapLayers, document.getElementById("faction-menu")];
  document.addEventListener("click", event => {
    for (const popover of popovers) {
      if (!popover.contains(event.target)) popover.open = false;
    }
  });
  document.addEventListener("keydown", event => {
    if (event.key !== "Escape" || event.target.matches("input, select")) return;
    const opened = popovers.find(popover => popover.open);
    if (opened) opened.open = false;
    else if (s.selection) setSelection(null);
    else if (!els.timeline.hidden) els.eventsToggle.click();
    else sectorMode();
  });
  installCanvasHandlers();
}

wireControls();
renderMap();
fetchReport().then(()=>{connectWs();fetchHealth();});
window.setInterval(fetchReport,18000);
window.setInterval(fetchHealth,2500);
window.setInterval(() => {
  refreshToolbar();
  // Keep a focused inspector control attached while the user navigates it.
  if (!els.inspectorBody.contains(document.activeElement) || document.activeElement.matches("summary")) renderInspector();
}, 2200);
window.addEventListener("beforeunload",()=>s.ws?.close());
