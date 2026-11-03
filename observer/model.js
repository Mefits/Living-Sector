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

  const factions = list(report?.factions);
  const factionById = new Map(factions.map(f => [f.id, f]));
  const facilities = list(report?.facilities);
  const facilityById = new Map(facilities.map(f => [f.id, f]));
  const facilityByLocation = new Map(facilities.map(f => [key(f.location), f]));
  const systemFacilities = new Map(systems.map(s => [s.name, []]));
  const systemMarkets = new Map(systems.map(s => [s.name, []]));
  const systemPopulations = new Map(systems.map(s => [s.name, []]));
  for (const f of facilities) {
    const sys = bodySystem.get(key(f.body_id));
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
    bodySystem, facilityByLocation,
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

export function shortageCount(markets) {
  return list(markets).reduce((total, market) =>
    total + Object.values(market.shortage_ticks || {}).filter(v => Number(v) > 0).length, 0);
}

export function sortedCargo(cargo) {
  return Object.entries(cargo || {}).filter(([, qty]) => Number(qty) > 0)
    .sort((a, b) => Number(b[1]) - Number(a[1]));
}
