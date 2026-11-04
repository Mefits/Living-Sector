import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = await mkdtemp(join(tmpdir(), "genesis-fleet-"));
const timeout = AbortSignal.timeout(45000);
const children = new Set();

async function start(save) {
  const child = spawn(process.argv[2], [], {
    env: { ...process.env, GENESIS_PORT: "0", GENESIS_SAVE_PATH: save, GENESIS_NO_BROWSER: "1" },
    stdio: ["ignore", "pipe", "inherit"],
  });
  children.add(child);
  const closed = new Promise(resolve => child.once("close", resolve));
  child.once("close", () => children.delete(child));
  const lines = createInterface({ input: child.stdout });
  try {
    const [line] = await Promise.race([
      once(lines, "line", { signal: timeout }),
      closed.then(code => { throw new Error("Genesis exited during startup: " + code); }),
    ]);
    return { child, closed, base: new URL(line.split(" ").at(-1)).origin };
  } finally {
    lines.close();
  }
}

async function stop(server) {
  server.child.kill();
  await server.closed;
}

async function api(server, path, body) {
  const response = await fetch(server.base + path, {
    signal: timeout,
    ...(body && { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }),
  });
  assert.ok(response.ok, path + " returned " + response.status);
  return response.json();
}

const diag = server => api(server, "/api/diagnostics");
const pause = server => api(server, "/api/sim/pause", {});
async function resume(server) {
  await api(server, "/api/sim/speed", { world_speed: 16 });
  await api(server, "/api/sim/resume", {});
}
async function until(server, predicate) {
  while (!timeout.aborted) {
    const data = await diag(server);
    if (predicate(data)) return data;
    await new Promise(resolve => setTimeout(resolve, 80));
  }
  throw timeout.reason;
}

function warehouse(name, x, water) {
  return { name, x, y: 0, capacity: 200, stock: {water} };
}

async function fleetCase(initial, count) {
  const state = structuredClone(initial);
  Object.assign(state, {
    station_ore: 100, belt_ore: 0, deposit: 0, metal: 80, station_fuel: 200,
    industry: undefined,
    warehouses: {north: warehouse("Север", 2, 45), south: warehouse("Юг", 3, 45), client: warehouse("Получатель", 5, 0)},
  });
  state.construction.phase = "complete";
  Object.assign(state.conflict, { base_ready: true, base_progress: 40, pirate_fuel_stock: 0 });
  state.fleet = { initialized: true, next_order: 2,
    orders: {1: {destination: "client", resource: "water", remaining: 110, priority: 100}},
    ships: Object.fromEntries(Array.from({length: count}, (_, i) => [
      "test-" + i, {name: "Грузовик " + i, location: i % 2 ? "south" : "north", fuel: 100,
        tank: 100, capacity: 20, status: "Готов", task: null, leg: null},
    ])),
  };
  const save = join(dir, "fleet-" + count + ".json");
  await writeFile(save, JSON.stringify(state));
  let server = await start(save);
  await resume(server);
  const moving = await until(server, d => Object.values(d.state.fleet.ships).some(s => s.leg && s.task?.loaded));
  if (count === 5) {
    assert.ok(Object.values(moving.state.fleet.ships).filter(s => s.task).length > 1);
    await pause(server);
    const saved = await diag(server);
    await stop(server);
    server = await start(save);
    assert.deepEqual((await diag(server)).state.fleet, saved.state.fleet);
    await resume(server);
  }
  const delivered = await until(server, d => d.state.warehouses.client.stock.water === 90);
  assert.equal(delivered.state.fleet.orders[1].remaining, 20);
  assert.equal(delivered.state.warehouses.north.stock.water, 0);
  assert.equal(delivered.state.warehouses.south.stock.water, 0);
  assert.equal(Object.keys(delivered.state.fleet.ships).length, count);
  await stop(server);
}

async function legacyCase(initial, independent = false) {
  const state = structuredClone(initial);
  delete state.fleet;
  delete state.industry;
  Object.assign(state, {station_ore: 18, station_fuel: 100, metal: 8, smelting_elapsed: 2, phase: "outbound", elapsed: 7.5, route_duration: 16, fuel: 23, cargo: 40});
  Object.assign(state.construction, {phase: "complete", active_second: true, parked_fuel: 55});
  if (independent) {
    state.construction.active_second = false;
    state.second_freighter = {
      phase: "outbound", elapsed: 4, outbound_duration: 18, fuel: 19, cargo: 20,
    };
  }
  const save = join(dir, independent ? "pr-6.json" : "old.json");
  await writeFile(save, JSON.stringify(state));
  const server = await start(save);
  const imported = await diag(server);
  const ships = imported.state.fleet.ships;
  assert.deepEqual(imported.state.warehouses["earth-station"].stock, {ore: 8, fuel: 99, metals: 8});
  assert.equal(imported.state.industry.plants["earth-station"].batch.remaining, 12);
  const active = ships[independent ? "freighter-1" : "freighter-2"];
  assert.equal(active.fuel, 23);
  assert.equal(active.leg.elapsed, 30);
  assert.equal(active.task.quantity, 40);
  if (independent) {
    const second = ships["freighter-2"];
    assert.equal(second.fuel, 19);
    assert.equal(second.leg.elapsed, 16);
    assert.equal(second.task.quantity, 20);
    assert.equal(active.task.order, second.task.order);
  } else {
    assert.equal(ships["freighter-1"].fuel, 55);
  }
  await stop(server);
}

async function industryCase(initial) {
  const state = structuredClone(initial);
  const {warehouses, industry} = state;
  warehouses["earth-station"].stock.metals = 80;
  industry.deposits["belt-outpost"].remaining = 0;
  state.construction.phase = "complete";
  Object.assign(state.conflict, {base_ready: true, base_progress: 40, pirate_fuel_stock: 0, raider_destroyed: true});
  const site = (name, x, capacity, stock) => ({name, x, y: 0, capacity, stock});
  warehouses.north = site("Северная плавильня", 2, 11, {ore: 10, fuel: 1});
  warehouses.south = site("Южная плавильня", 3, 40, {fuel: 2});
  const smelter = (location, period) => ({location, period, operation: {kind: "process", recipe: "smelt_metals"}});
  industry.plants.north = smelter("north", 40);
  industry.plants.south = smelter("south", 8);
  for (const [id, x] of [["mine-a", 4], ["mine-b", 5]]) {
    warehouses[id] = site(id, x, 10, {});
    industry.deposits[id] = {resource: "ore", initial: 10, remaining: 10};
    industry.plants[id] = {location: id, period: 8, operation: {kind: "extract", deposit: id, amount: 10}};
  }
  state.fleet.ships["freighter-1"].location = "mine-a";
  state.fleet.ships["freighter-2"] = {...state.fleet.ships["freighter-1"], location: "mine-b", name: "Грузовой-002"};
  const save = join(dir, "industry.json");
  await writeFile(save, JSON.stringify(state));
  let server = await start(save);
  await resume(server);
  await until(server, d => d.state.industry.plants.north.batch);
  await pause(server);
  const paused = (await diag(server)).state;
  assert.equal(paused.warehouses.north.stock.ore, 0);
  assert.equal(paused.warehouses.north.stock.fuel, 0);
  await stop(server);
  server = await start(save);
  const restored = (await diag(server)).state;
  assert.deepEqual(restored.industry, paused.industry);
  assert.deepEqual(restored.warehouses, paused.warehouses);
  await resume(server);
  const result = (await until(server, d => d.state.warehouses.south.stock.metals === 16)).state;
  assert.equal(result.warehouses.north.stock.metals, 8);
  for (const id of ["mine-a", "mine-b"]) {
    assert.equal(result.industry.deposits[id].remaining, 0);
    assert.equal(result.warehouses[id].stock.ore, 0);
  }
  await stop(server);
}

async function verifyImportedLog(logPath) {
  const log = JSON.parse(await readFile(logPath, "utf8"));
  const save = join(dir, "imported-log.json");
  await writeFile(save, JSON.stringify(log.state));
  const server = await start(save);
  const state = (await diag(server)).state;
  assert.deepEqual(state.fleet, log.state.fleet);
  assert.equal(state.warehouses["earth-station"].stock.metals, log.state.metal);
  assert.equal(state.warehouses["earth-station"].stock.fuel, log.state.station_fuel);
  assert.equal(state.warehouses["mars-outpost"].stock.ore, log.state.construction.mars_ore);
  assert.equal(state.industry.deposits["belt-outpost"].remaining, log.state.deposit);
  await stop(server);
}

try {
  const origin = await start(join(dir, "new.json"));
  const initial = await diag(origin);
  assert.equal(initial.version, "0.11.0");
  await resume(origin);
  await Promise.all([
    legacyCase(initial.state), legacyCase(initial.state, true), industryCase(initial.state),
    ...(process.argv[3] ? [verifyImportedLog(process.argv[3])] : []),
    ...[1, 2, 5].map(count => fleetCase(initial.state, count)),
    until(origin, d => d.state.warehouses["earth-station"].stock.metals > 0),
  ]);
  await stop(origin);
  console.log("PASS: independent fleet, two mines and two smelters, local stocks, in-flight and in-process reload, legacy migration.");
} finally {
  await Promise.all([...children].map(async child => {
    const closed = once(child, "close");
    child.kill();
    await closed;
  }));
  await rm(dir, {recursive: true, force: true});
}
