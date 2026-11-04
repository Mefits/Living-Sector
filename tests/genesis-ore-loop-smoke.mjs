// Run against a fresh Genesis save started at 0.25× to observe the first extraction.
import assert from "node:assert/strict";

const base = process.argv[2] ?? "http://127.0.0.1:18081";
async function api(path, body) {
  const request = body === undefined ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
  const response = await fetch(base + path, { ...request, signal: AbortSignal.timeout(3000) });
  assert.ok(response.ok, path + ": HTTP " + response.status);
  return response.json();
}

const initial = await api("/api/report");
assert.equal(initial.genesis_ore_loop, true);
assert.equal(initial.ships.length, 1);
assert.equal(initial.facilities.length, 2);
assert.ok(initial.markets.every(market => market.supply.ore === 0));
assert.equal(initial.ships[0].cargo.ore ?? 0, 0);

const events = [];
const socket = new WebSocket(base.replace(/^http/, "ws") + "/ws");
try {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(Error("WebSocket did not open")), 5000);
    socket.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
    socket.addEventListener("error", () => { clearTimeout(timeout); reject(Error("WebSocket failed")); }, { once: true });
  });
  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    if (message.type === "events") events.push(...message.events);
  });

  await api("/api/sim/speed", { world_speed: 8 });
  await api("/api/sim/resume", {});
  let transit = false;
  let delivery;
  let received = false;
  for (let attempt = 0; attempt < 120; attempt++) {
    const report = await api("/api/report");
    const [ship] = report.ships;
    transit ||= ship.transit?.from === "belt-outpost" &&
      ship.transit.to === "earth-station" && ship.cargo.ore > 0;
    const station = report.markets.find(market => market.facility_location === "earth-station");
    delivery = events.find(event => event.kind === "cargo_unloaded" && event.location === "earth-station");
    received = Boolean(delivery && station.supply.ore >= delivery.quantity && !ship.cargo.ore);
    if (received) break;
    await new Promise(resolve => setTimeout(resolve, 250));
  }

  const loaded = events.find(event => event.kind === "cargo_loaded");
  assert.ok(loaded && delivery && transit && received, JSON.stringify({ loaded, delivery, transit, received }));
  assert.equal(loaded.location, "belt-outpost");
  assert.equal(loaded.commodity, "ore");
  assert.equal(delivery.commodity, "ore");
  assert.equal(delivery.quantity, loaded.quantity);
  assert.equal(delivery.stock, loaded.quantity);
  const mined = events.slice(0, events.indexOf(loaded)).filter(event => event.kind === "ore_extracted");
  assert.ok(mined.length > 0);
  assert.ok(Math.abs(mined.reduce((sum, event) => sum + event.quantity, 0) - loaded.stock - loaded.quantity) < 0.01);
  console.log("Genesis: ore extracted, loaded, transported and delivered to Earth:", delivery.quantity);
} finally {
  socket.close();
}
