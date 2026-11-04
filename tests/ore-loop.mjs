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
  const socket = new WebSocket(base.replace("http:", "ws:") + "/ws");
  sockets.push(socket);
  const events = [];
  const done = new Promise((resolve, reject) => {
    timeout.addEventListener("abort", () => reject(timeout.reason), { once: true });
    socket.addEventListener("message", message => {
      const frame = JSON.parse(message.data);
      events.push(...frame.events);
      if (frame.governance.last_decision && !frame.governance.batch_active) resolve(frame.governance);
    });
  });
  done.catch(() => {});
  await once(socket, "open", { signal: timeout });
  await api(base, "/api/sim/speed", { world_speed: 16 });
  await api(base, "/api/sim/resume", {});
  const result = await done;
  assert.ok(events.some(event => event.kind === "ore_requested" && event.actor === "Снабженец"));
  assert.ok(events.some(event => event.kind === "cargo_unloaded" && event.quantity === 50));
  assert.ok(events.some(event => event.kind === "smelt_started" && event.actor === "Промышленник"));
  assert.ok(events.some(event => event.kind === "policy_changed" && event.actor === "Глава фракции"));
  await api(base, "/api/sim/pause", {});
  const paused = await api(base, "/api/report");
  socket.close();
  child.kill();
  await closed;

  const restarted = await api((await start("", save)).base, "/api/report");
  assert.equal(restarted.running, false);
  assert.deepEqual(restarted.governance, paused.governance);
  return result;
}

try {
  const [cautious, industrial] = await Promise.all([observe("cautious"), observe("industrial")]);
  assert.equal(cautious.industry, "Топливо зарезервировано политикой");
  assert.equal(cautious.station_fuel, 194);
  assert.equal(cautious.metal, 48);
  assert.equal(industrial.station_fuel, 190);
  assert.equal(industrial.metal, 80);
  console.log("PASS: same starting stocks, distinct policies, delivery, smelting, and restart.");
} finally {
  for (const socket of sockets) socket.close();
  for (const child of children) child.kill();
  await Promise.all(processClosed);
  await rm(dir, { recursive: true, force: true });
}
