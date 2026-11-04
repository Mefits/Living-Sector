import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = await mkdtemp(join(tmpdir(), "genesis-ore-loop-"));
const save = join(dir, "save.json");
const timeout = AbortSignal.timeout(15000);
const processClosed = [];
const children = [];
let socket;

async function start() {
  const child = spawn(process.argv[2], [], {
    env: { ...process.env, GENESIS_PORT: "0", GENESIS_SAVE_PATH: save, GENESIS_NO_BROWSER: "1" },
    stdio: ["ignore", "pipe", "inherit"],
  });
  children.push(child);
  processClosed.push(new Promise(resolve => child.once("close", resolve)));
  const lines = createInterface({ input: child.stdout });
  try {
    const [line] = await once(lines, "line", { signal: timeout });
    assert.match(line, /^Genesis Clean: http:\/\/127\.0\.0\.1:\d+\/observer$/);
    return new URL(line.split(" ").at(-1)).origin;
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

try {
  const base = await start();
  const initial = await api(base, "/api/report");
  assert.equal(initial.running, false);
  assert.deepEqual(initial.markets.map(market => market.supply.ore), [0, 0]);

  socket = new WebSocket(base.replace("http:", "ws:") + "/ws");
  const received = [];
  let inFlight = false;
  let frame;
  const delivery = new Promise((resolve, reject) => {
    timeout.addEventListener("abort", () => reject(timeout.reason), { once: true });
    socket.addEventListener("message", message => {
      frame = JSON.parse(message.data);
      inFlight ||= frame.ships[0].transit !== null && frame.ships[0].cargo.ore === 50;
      received.push(...frame.events);
      if (frame.events.some(event => event.kind === "cargo_unloaded")) resolve(frame);
    });
  });
  await once(socket, "open", { signal: timeout });
  await api(base, "/api/sim/speed", { world_speed: 8 });
  await api(base, "/api/sim/resume", {});
  const arrival = await delivery;
  assert.deepEqual(received.map(event => [event.kind, event.quantity]), [
    ["ore_extracted", 50], ["cargo_loaded", 50], ["cargo_unloaded", 50],
  ]);
  assert.ok(inFlight);
  assert.deepEqual(arrival.markets.map(market => market.supply.ore), [0, 50]);
  assert.equal(arrival.ships[0].cargo.ore, 0);
  assert.ok(arrival.ships[0].fuel < initial.ships[0].fuel);

  await api(base, "/api/sim/pause", {});
  assert.equal(JSON.parse(await readFile(save, "utf8")).station_ore, 50);
  socket.close();
  children[0].kill();
  await processClosed[0];

  const restarted = await api(await start(), "/api/report");
  assert.equal(restarted.running, false);
  assert.equal(restarted.markets[1].supply.ore, 50);
  console.log("PASS: 50 ore mined, loaded, flown, unloaded, and restored on restart.");
} finally {
  socket?.close();
  for (const child of children) child.kill();
  await Promise.all(processClosed);
  await rm(dir, { recursive: true, force: true });
}
