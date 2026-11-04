import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = await mkdtemp(join(tmpdir(), "genesis-ore-loop-"));
const timeout = AbortSignal.timeout(65000);
const processClosed = [];
const children = [];
const sockets = [];

async function start(leader, save) {
  const child = spawn(process.argv[2], [], {
    env: { ...process.env, GENESIS_PORT: "0", GENESIS_SAVE_PATH: save, GENESIS_NO_BROWSER: "1", GENESIS_LEADER: leader },
    stdio: ["ignore", "pipe", "inherit"],
  });
  children.push(child);
  const closed = new Promise(resolve => child.once("close", resolve));
  processClosed.push(closed);
  const lines = createInterface({ input: child.stdout });
  try {
    const [line] = await once(lines, "line", { signal: timeout });
    assert.match(line, /^Genesis Clean: http:\/\/127\.0\.0\.1:\d+\/observer$/);
    return { base: new URL(line.split(" ").at(-1)).origin, child, closed };
  } finally {
    lines.close();
  }
}

async function api(base, path, data) {
  const response = await fetch(base + path, {
    signal: timeout,
    ...(data && {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(data),
    }),
  });
  assert.ok(response.ok, path + " returned " + response.status);
  return response.json();
}

async function runSeed(name, state, stop) {
  const save = join(dir, name + ".json");
  await writeFile(save, JSON.stringify(state));
  const server = await start("industrial", save);
  const socket = new WebSocket(server.base.replace("http:", "ws:") + "/ws");
  sockets.push(socket);
  const events = [];
  const done = new Promise((resolve, reject) => {
    timeout.addEventListener("abort", () => reject(timeout.reason), { once: true });
    socket.addEventListener("message", message => {
      const frame = JSON.parse(message.data);
      events.push(...frame.events);
      if (stop(frame, events)) resolve(frame);
    });
  });
  done.catch(() => {});
  await once(socket, "open", { signal: timeout });
  await api(server.base, "/api/sim/speed", { world_speed: 16 });
  await api(server.base, "/api/sim/resume", {});
  const frame = await done;
  await api(server.base, "/api/sim/pause", {});
  socket.close();
  server.child.kill();
  await server.closed;
  return { events, frame, save };
}

try {
  const origin = await start("industrial", join(dir, "original.json"));
  const initial = await api(origin.base, "/api/diagnostics");
  assert.equal(initial.version, "0.8.0");
  const fresh = await runSeed("fresh", initial.state, (_, events) => events.some(event => event.kind === "ship_commissioned"));
  assert.ok(fresh.events.some(event => event.kind === "building_approved" && event.actor === "Genesis" && event.reason.includes("Орбитальная верфь")));
  const state = initial.state;
  Object.assign(state, { metal: 60, station_ore: 20, deposit: 500 });
  state.construction.phase = "complete";
  Object.assign(state.conflict, { base_ready: true, base_progress: 40, pirate_fuel_stock: 0 });
  const calm = await runSeed("calm", state, frame => frame.tick >= 36);
  assert.ok(!calm.events.some(event => event.kind === "building_approved" && event.reason.includes("Рудный аванпост")));

  Object.assign(state, { deposit: 80 });
  Object.assign(state.conflict, { raider_destroyed: true, pirate_metal: 44, pirate_fuel_stock: 30 });
  const risk = await runSeed("risk", state, (_, events) =>
    events.filter(event => event.kind === "building_completed").length >= 2
      && events.some(event => event.kind === "cargo_loaded" && event.location === "mars-outpost"));
  assert.ok(risk.events.some(event => event.kind === "building_approved" && event.actor === "Genesis" && event.reason.includes("Рудный аванпост")));
  assert.ok(risk.events.some(event => event.kind === "building_approved" && event.actor === "Пираты" && event.reason.includes("Орбитальная верфь")));
  assert.equal(risk.frame.governance.catalog.length, 11);
  const restored = await start("", risk.save);
  const report = await api(restored.base, "/api/report");
  assert.ok(report.facilities.some(facility => facility.id === "pirate-shipyard"));
  assert.ok(report.facilities.some(facility => facility.id === "mars-outpost" && facility.type === "mining_rig"));
  console.log("PASS: calm economy, site choice, both construction fleets, first outpost shipment, reload.");
} finally {
  for (const socket of sockets) socket.close();
  for (const child of children) child.kill();
  await Promise.all(processClosed);
  await rm(dir, { recursive: true, force: true });
}
