import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = await mkdtemp(join(tmpdir(), "genesis-ore-loop-"));
const timeout = AbortSignal.timeout(25000);
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

async function observe(leader) {
  const save = join(dir, leader + ".json");
  const { base, child, closed } = await start(leader, save);
  const initial = await api(base, "/api/report");
  assert.equal(initial.governance.station_fuel, 200);
  assert.equal(initial.governance.metal, 0);
  assert.ok(["venus", "mars", "jupiter"].every(id => initial.systems[0].bodies.some(body => body.id === id)));
  const baseSite = initial.facilities.find(f => f.id === "pirate-outpost");
  const rig = initial.facilities.find(f => f.id === "belt-outpost");
  assert.equal(baseSite.body_id, "jupiter");
  assert.ok(Math.hypot(baseSite.x - rig.x, baseSite.y - rig.y) > 2);
  const socket = new WebSocket(base.replace("http:", "ws:") + "/ws");
  sockets.push(socket);
  const events = [];
  const done = new Promise((resolve, reject) => {
    timeout.addEventListener("abort", () => reject(timeout.reason), { once: true });
    socket.addEventListener("message", message => {
      const frame = JSON.parse(message.data);
      events.push(...frame.events);
      if (events.some(event => event.kind === "raid_deflected")
          && events.some(event => event.kind === "cargo_unloaded" && event.ship_name === "Грузовой-002")) resolve(frame);
    });
  });
  done.catch(() => {});
  await once(socket, "open", { signal: timeout });
  await api(base, "/api/sim/speed", { world_speed: 16 });
  await api(base, "/api/sim/resume", {});
  const result = await done;
  const ordered = ["yard_dispatched", "yard_assembly", "yard_completed", "ship_completed",
    "ship_commissioned", "patrol_ready", "raid_deflected"];
  let previous = -1;
  for (const kind of ordered) {
    const index = events.findIndex(event => event.kind === kind);
    assert.ok(index > previous, kind);
    previous = index;
  }
  assert.ok(events.some(event => event.kind === "raid_stolen" && event.quantity === 10));
  assert.ok(events.some(event => event.kind === "raid_delivered" && event.quantity === 10));
  assert.equal(result.ships.find(ship => ship.id === "freighter-2").name, "Грузовой-002");
  assert.ok(result.facilities.some(facility => facility.type === "shipyard"));
  await api(base, "/api/sim/pause", {});
  const paused = await api(base, "/api/report");
  socket.close();
  child.kill();
  await closed;

  const restartedBase = (await start("", save)).base;
  const restarted = await api(restartedBase, "/api/report");
  const diagnosticResponse = await fetch(restartedBase + "/api/diagnostics", {signal: timeout});
  assert.match(diagnosticResponse.headers.get("content-disposition"), /Living-Sector-diagnostics.json/);
  const diagnostics = await diagnosticResponse.json();
  assert.equal(diagnostics.version, "0.5.1");
  assert.equal(diagnostics.state.tick, restarted.tick);
  assert.ok(diagnostics.events.some(event => event.details.kind === "raid_deflected"));
  assert.ok(diagnostics.events.some(event => event.kind === "operations"));
  assert.equal(restarted.running, false);
  assert.deepEqual(restarted.governance, paused.governance);
  assert.deepEqual(restarted.ships.map(ship => ship.id), paused.ships.map(ship => ship.id));
  assert.deepEqual(restarted.facilities, paused.facilities);
  return result;
}

try {
  await observe("industrial");
  console.log("PASS: physical construction, commissioned freighter, raid, escort and restart.");
} finally {
  for (const socket of sockets) socket.close();
  for (const child of children) child.kill();
  await Promise.all(processClosed);
  await rm(dir, { recursive: true, force: true });
}
