import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = await mkdtemp(join(tmpdir(), "genesis-ore-loop-"));
const save = join(dir, "save.json");
const timeout = AbortSignal.timeout(25000);
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
  let waitedForOre = false;
  let minedInFlight = false;
  let delivered = 0;
  let nextRequest = false;
  let firstSmelt;
  const cycle = new Promise((resolve, reject) => {
    timeout.addEventListener("abort", () => reject(timeout.reason), { once: true });
    socket.addEventListener("message", message => {
      const frame = JSON.parse(message.data);
      const ship = frame.ships[0];
      const station = frame.markets[1];
      waitedForOre ||= ship.docked && ship.status_label.startsWith("Ждёт руду");
      minedInFlight ||= ship.transit !== null && frame.events.some(event => event.kind === "ore_extracted");
      delivered += frame.events.filter(event => event.kind === "cargo_unloaded").reduce((sum, event) => sum + event.quantity, 0);
      if (!firstSmelt && frame.events.some(event => event.kind === "metal_smelted")) firstSmelt = frame;
      nextRequest ||= delivered === 50 && frame.events.some(event => event.kind === "ore_requested");
      if (station.supply.metals === station.metal_capacity && ship.status_label === "Нет заявки") resolve(frame);
    });
  });
  cycle.catch(() => {});
  await once(socket, "open", { signal: timeout });
  await api(base, "/api/sim/speed", { world_speed: 16 });
  await api(base, "/api/sim/resume", {});
  const full = await cycle;
  assert.ok(waitedForOre && minedInFlight && nextRequest);
  assert.ok(delivered >= 100);
  assert.equal(firstSmelt.markets[1].supply.ore, 40);
  assert.equal(firstSmelt.markets[1].supply.metals, 8);
  assert.equal(firstSmelt.reserves["earth-station"], 199);
  assert.equal(full.markets[1].smelting_status, "Склад металла заполнен");

  await api(base, "/api/sim/pause", {});
  assert.equal(JSON.parse(await readFile(save, "utf8")).metal, 80);
  socket.close();
  children[0].kill();
  await processClosed[0];

  const restarted = await api(await start(), "/api/report");
  assert.equal(restarted.running, false);
  assert.equal(restarted.markets[1].supply.metals, 80);
  console.log("PASS: demand, independent mining, delivery, smelting, full storage, and restart.");
} finally {
  socket?.close();
  for (const child of children) child.kill();
  await Promise.all(processClosed);
  await rm(dir, { recursive: true, force: true });
}
