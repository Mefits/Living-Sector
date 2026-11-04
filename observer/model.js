// Living Sector Observer: pure adapters for the existing headless API.
// Keep this file browser- and Node-compatible. No invented simulation state.

export const list = (value) => Array.isArray(value) ? value : [];
export const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
export const point = (value) =>
  value && Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y))
    ? { x: Number(value.x), y: Number(value.y) } : null;
export const key = (value) => String(value ?? "").trim().toLowerCase();
export const safeHex = (value, fallback = "#8da3b9") =>
  typeof value === "string" && /^#[a-fA-F0-9]{6}$/.test(value) ? value : fallback;

// Display names for existing commodity IDs. These are labels only:
// no new recipes or inventory state are introduced in Observer.
const COMMODITY_NAMES = {
  ore:"Руда", ice:"Лёд", gas:"Газ", metals:"Металлы",
  fuel:"Топливо", polymers:"Полимеры", water:"Вода",
  components:"Компоненты", electronics:"Электроника",
  tools:"Инструменты", food:"Продовольствие",
  medical:"Медикаменты", luxury:"Предметы роскоши"
};
export function commodityLabel(id) {
  return COMMODITY_NAMES[key(id)] ?? String(id ?? "Неизвестный товар");
}
const CONTRACT_NAMES = {
  delivery:"Доставка товаров", subsidy:"Субсидируемая доставка",
  construction:"Снабжение строительства", supply:"Поставка",
  courier:"Курьерская доставка", passenger:"Перевозка пассажиров",
  crew_mission:"Задание экипажа"
};
export function contractLabel(id) {
  return CONTRACT_NAMES[key(id)] ?? (id ? String(id) : "Контракт");
}
// Upstream uses Food as a placeholder for Passenger, and Tools as a
// placeholder for CrewMission. Never present them as physical cargo.
export function contractCargoLabel(commodity,contractType) {
  const kind=key(contractType);
  if(kind==="passenger")return null;
  if(kind==="crew_mission")return null;
  return commodity == null ? null : commodityLabel(commodity);
}

export function ownership(system) {
  const bodies = list(system.bodies);
  const ids = [...new Set(bodies.map(b => b.controlling_faction).filter(Boolean))];
  const contested = bodies.some(b => b.contested === true);
  if (contested || ids.length > 1) return { kind: "mixed", factionId: null, contested };
  if (ids.length === 1) return { kind: "single", factionId: ids[0], contested: false };
  return { kind: "unknown", factionId: null, contested: false };
}

// These are visual groupings inferred from body snapshots, NOT the
// authoritative AgentStore.system_control (which the API doesn't expose).
export function buildIndex(report) {
  const systems = list(report?.systems).map(s => ({
    id: String(s.id ?? s.name),
    name: String(s.name ?? "?"),
    x: number(s.offset_x), y: number(s.offset_y),
    bodies: list(s.bodies),
    ownership: ownership(s)
  })).sort((a, b) => a.name.localeCompare(b.name));
  const bodySystem = new Map();
  const bodyIdCollisions = new Set();
  for (const s of systems) for (const b of s.bodies) {
    const id = key(b.id);
    if (!id) continue;
    if (bodySystem.has(id) && bodySystem.get(id) !== s.name) {
      bodyIdCollisions.add(id);
    } else {
      bodySystem.set(id, s.name);
    }
  }
  for (const id of bodyIdCollisions) bodySystem.delete(id);
  // Resolve ship locations without projecting a ship onto the nearest
  // star. Ambiguous location slugs are deliberately left unresolved.
  const locationSystem = new Map();
  const ambiguousLocations = new Set();
  const registerLocation = (loc, sys) => {
    const id = key(loc);
    if (!id || !sys) return;
    if (locationSystem.has(id) && locationSystem.get(id) !== sys) {
      ambiguousLocations.add(id);
    } else {
      locationSystem.set(id, sys);
    }
  };
  for (const sys of systems) {
    for (const body of sys.bodies) {
      registerLocation(body.id, sys.name);
      registerLocation(body.name, sys.name);
    }
  }
  const facilitySystem = facility => bodySystem.get(key(facility.body_id))
    ?? systems.find(system => system.id === facility.system_id)?.name;
  for (const facility of list(report?.facilities)) {
    registerLocation(facility.location, facilitySystem(facility));
  }
  for (const id of ambiguousLocations) locationSystem.delete(id);


  const factions = list(report?.factions);
  const factionById = new Map(factions.map(f => [f.id, f]));
  const facilities = list(report?.facilities);
  const facilityById = new Map(facilities.map(f => [f.id, f]));
  const facilityByLocation = new Map(facilities.map(f => [key(f.location), f]));
  const systemFacilities = new Map(systems.map(s => [s.name, []]));
  const systemMarkets = new Map(systems.map(s => [s.name, []]));
  const systemPopulations = new Map(systems.map(s => [s.name, []]));
  for (const f of facilities) {
    const sys = facilitySystem(f);
    if (sys) systemFacilities.get(sys)?.push(f);
  }
  for (const m of list(report?.markets)) {
    const f = facilityByLocation.get(key(m.facility_location));
    const sys = f ? bodySystem.get(key(f.body_id)) : null;
    if (sys) systemMarkets.get(sys)?.push(m);
  }
  for (const p of list(report?.populations)) {
    const f = facilityByLocation.get(key(p.facility_location));
    const sys = f ? bodySystem.get(key(f.body_id)) : null;
    if (sys) systemPopulations.get(sys)?.push(p);
  }

  // Only actual gate_link.paired_gate_id relations; no guessed star lanes.
  const gateLinks = [];
  const seen = new Set();
  for (const facility of facilities) {
    if (!facility.gate_link?.paired_gate_id) continue;
    const other = facilityById.get(facility.gate_link.paired_gate_id);
    if (!other) continue;
    const a = bodySystem.get(key(facility.body_id));
    const b = bodySystem.get(key(other.body_id));
    if (!a || !b || a === b) continue;
    const id = [a, b].sort().join("|");
    if (seen.has(id)) continue;
    seen.add(id);
    gateLinks.push({ a, b });
  }

  return {
    systems, factions, factionById, facilities, facilityById,
    bodySystem, locationSystem, facilityByLocation,
    systemFacilities, systemMarkets, systemPopulations, gateLinks
  };
}

export function factionColor(factionId, index) {
  return safeHex(index.factionById.get(factionId)?.colors?.primary);
}

export function factionName(factionId, index) {
  return index.factionById.get(factionId)?.name ?? factionId ?? "Неизвестно";
}

export function systemByName(name, index) {
  return index.systems.find(s => s.name === name) ?? null;
}

export function positionOf(ship, positions) {
  return point(positions.get(ship.id)) ?? point(ship.position);
}

// Body/facility snapshots contain slower-changing metadata, while the WS
// positions stream carries fresh coordinates each tick. Use one source for
// visible positions across all entity kinds; fall back for offline viewing.
export function liveEntityPoint(entity, livePositions) {
  const id=entity?.id ?? entity?.body_id;
  return (id != null ? point(livePositions?.get(String(id))) : null) ??
    point(entity) ?? point(entity?.universe_position) ?? point(entity?.position);
}

// Cosmetic interpolation only. Never change ECS state or move a map marker
// to another entity's coordinate. Snap on large discontinuities/teleports.
export function approachWorldPoint(current,target,rate=0.18,snapDistance=12) {
  const wanted=point(target);
  if(!wanted)return null;
  const old=point(current);
  if(!old)return wanted;
  const d=Math.hypot(wanted.x-old.x,wanted.y-old.y);
  if(d>snapDistance)return wanted;
  return {x:old.x+(wanted.x-old.x)*rate,y:old.y+(wanted.y-old.y)*rate};
}

export function systemAtPosition(pos, systems) {
  if (!pos || !systems?.length) return null;
  let found = null, best = Infinity;
  for (const s of systems) {
    const dx = pos.x - s.x, dy = pos.y - s.y;
    const distance = dx * dx + dy * dy;
    if (distance < best) { best = distance; found = s; }
  }
  return found;
}

// A preliminary proximity grouping for statistics, never used as proof
// of a ship's system membership or ownership.
export function approximateShipsNear(system, ships, positions, radius) {
  const r2 = radius * radius;
  return list(ships).filter(ship => {
    const p = positionOf(ship, positions);
    return p && (p.x - system.x) ** 2 + (p.y - system.y) ** 2 <= r2;
  });
}

// Preserve the world point below the cursor while the camera zoom changes.
// Screen transform is: viewport centre + worldDelta * scale + pan.
export function panForCursorZoom(pan, cursor, viewport, oldZoom, newZoom) {
  if (!(oldZoom > 0) || !(newZoom > 0)) return {...pan};
  const ratio = newZoom / oldZoom;
  const dx = cursor.x - viewport.w / 2;
  const dy = cursor.y - viewport.h / 2;
  return {
    x: dx - (dx - pan.x) * ratio,
    y: dy - (dy - pan.y) * ratio
  };
}

// Group real map markers occupying the same screen region. This does
// not create or delete simulation agents; the group retains every member.
export function clusterMarkers(markers, cellSize = 34) {
  const buckets = new Map();
  for (const marker of list(markers)) {
    if (!Number.isFinite(marker.x) || !Number.isFinite(marker.y)) continue;
    const cell = Math.floor(marker.x / cellSize) + ":" + Math.floor(marker.y / cellSize);
    if (!buckets.has(cell)) buckets.set(cell, []);
    buckets.get(cell).push(marker);
  }
  return [...buckets].map(([id, members]) => ({
    id,
    x: members.reduce((n, m) => n + m.x, 0) / members.length,
    y: members.reduce((n, m) => n + m.y, 0) / members.length,
    members
  }));
}

// Buildings sharing a real location represent one map hub. Group by
// location ID, not proximity: zoom must never split a station into five
// overlaid symbols or accidentally combine two distinct stations.
export function groupFacilitiesByLocation(facilities) {
  const groups = new Map();
  for (const fac of list(facilities)) {
    const id = key(fac.location) || key(fac.id);
    if (!id) continue;
    if (!groups.has(id)) groups.set(id, {id, location: fac.location, members: []});
    groups.get(id).members.push(fac);
  }
  return [...groups.values()];
}

// Place compact labels around real map markers without covering each
// other. Keep stable priority ordering; lower-priority labels disappear
// at cramped zoom levels, but hover and clicks remain available.
export function layoutMapLabels(items, viewport, obstacles = []) {
  const intersects = (a,b) => a.x < b.x+b.w && a.x+a.w > b.x &&
    a.y < b.y+b.h && a.y+a.h > b.y;
  const placed=[], used=[...obstacles];
  const ordered=[...list(items)].sort((a,b)=>
    a.priority-b.priority || String(a.id).localeCompare(String(b.id)));
  for (const item of ordered) {
    const w=item.w, h=item.h??20;
    if (!(w>0) || !(h>0) || !Number.isFinite(item.x) || !Number.isFinite(item.y)) continue;
    const offset=Math.max(16,item.radius??17)+5;
    const choices=[
      {x:item.x+offset,y:item.y-h-6},
      {x:item.x+offset,y:item.y+5},
      {x:item.x-offset-w,y:item.y-h-6},
      {x:item.x-offset-w,y:item.y+5},
      {x:item.x-w/2,y:item.y-offset-h},
      {x:item.x-w/2,y:item.y+offset}
    ];
    for(const p of choices) {
      const rect={x:p.x,y:p.y,w,h};
      if(rect.x<8 || rect.y<8 ||
         rect.x+w>viewport.w-8 || rect.y+h>viewport.h-8)continue;
      if(used.some(box=>intersects(rect,box)))continue;
      used.push(rect);
      placed.push({...item,x:p.x,y:p.y});
      break;
    }
  }
  return placed;
}

// A ship parked at a named location is not a free-floating map marker.
// In-transit ships are the only ones rendered as moving ship silhouettes.
// Classification uses authoritative server fields; no speed/nearby guesses.
export function shipMapState(ship) {
  if (ship?.transit != null) return "in_transit";
  if (typeof ship?.location === "string" && ship.location.trim()) {
    return ship.docked === true ? "docked" : "at_location";
  }
  return "unknown";
}

export function shipsAtHub(ships, location) {
  const loc=key(location);
  if(!loc)return [];
  return list(ships).filter(ship=>
    shipMapState(ship)!=="in_transit" && key(ship.location)===loc);
}

// Exact location matching only; never infer system membership from a
// ship's nearest star or coincidental 2D position.
export function shipSystem(ship, index) {
  // The server now exposes the actual ShipPosition.system_id.
  // This is needed while ships travel (ship.location becomes null).
  const actual = index?.systems?.find(
    sys => sys.id === ship?.system_id || sys.name === ship?.system_id
  );
  if (actual) return actual.name;
  // Compatibility with older Windows servers that don't expose it yet.
  const resolve = loc => index?.locationSystem?.get(key(loc)) ?? null;
  if (ship?.transit) {
    const from = resolve(ship.transit.from);
    const to = resolve(ship.transit.to);
    return from && from === to ? from : null;
  }
  return resolve(ship?.location);
}

// Convert a fixed world grid interval into a screen-space pitch.
// Candidate world steps follow a 1/2/5/10 progression; the chosen
// interval is stable for any given zoom and does not depend on panning.
export function worldGridStep(scale, targetPixels = 90) {
  if (!(scale > 0) || !Number.isFinite(scale)) return 1;
  const wanted = targetPixels / scale;
  const power = 10 ** Math.floor(Math.log10(wanted));
  const multiples = [1, 2, 5, 10];
  const multiple = multiples.find(m => m * power >= wanted) ?? 10;
  return power * multiple;
}

export function mapIconScale(zoom) {
  return Math.min(2.7, Math.max(0.62, Math.sqrt(Math.max(0.1, zoom))));
}

export function shortageCount(markets) {
  return list(markets).reduce((total, market) =>
    total + Object.values(market.shortage_ticks || {}).filter(v => Number(v) > 0).length, 0);
}

export function sortedCargo(cargo) {
  return Object.entries(cargo || {}).filter(([, qty]) => Number(qty) > 0)
    .sort((a, b) => Number(b[1]) - Number(a[1]));
}
