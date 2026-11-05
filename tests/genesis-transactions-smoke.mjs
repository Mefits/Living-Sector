// Node >=22; run from the repository root with a compiled genesis_server path.
// Uses a fresh temporary SQLite DB and the real Genesis seed, without stock injections.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, openSync, closeSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const binary = resolve(process.argv[2] ?? 'target/debug/genesis_server');
const dir = mkdtempSync(join(tmpdir(), 'genesis-transactions-'));
const port = Number(process.env.GENESIS_TEST_PORT ?? 18087);
const base = `http://127.0.0.1:${port}`;
const log = openSync(join(dir, 'server.log'), 'w');
const server = spawn(binary, [], {
  env: { ...process.env, DATABASE_PATH: join(dir, 'world.db'), DATA_DIR: resolve('priv/genesis/data'),
    LIVING_SECTOR_UI_DIR: resolve('observer'), BIND_ADDR: `127.0.0.1:${port}`, WORLD_SPEED: '16.0' },
  stdio: ['ignore', log, log],
});
closeSync(log);
let socket;
let passed = false;
let eventError;
const events = [];
const receipts = new Set();
const get = async (path) => {
  const response = await fetch(base + path, { signal: AbortSignal.timeout(2000) });
  assert.equal(response.status, 200, path);
  return response.json();
};
const post = async (path, body = {}) => {
  const response = await fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(2000) });
  assert.equal(response.status, 200, path);
};
function physicalBounds(report) {
  for (const ship of report.ships) {
    assert.ok(Number.isFinite(ship.fuel) && ship.fuel >= 0 && ship.fuel <= ship.fuel_capacity + 0.001, `fuel ${ship.id}`);
    assert.ok(Object.values(ship.cargo).reduce((a, b) => a + b, 0) <= ship.cargo_capacity, `cargo ${ship.id}`);
  }
  for (const market of report.markets) {
    for (const n of Object.values(market.supply)) assert.ok(Number.isFinite(n) && n >= 0, 'market stock');
  }
  for (const facility of report.facilities) {
    for (const n of Object.values(facility.reserves)) assert.ok(Number.isFinite(n) && n >= 0, 'facility reserves');
  }
}
try {
  let initial;
  for (let attempt = 0; attempt < 80; attempt++) {
    assert.equal(server.exitCode, null, `server exited; see ${dir}`);
    try { initial = await get('/api/report'); break; } catch { await delay(250); }
  }
  assert.ok(initial, `server startup timed out; see ${dir}`);
  assert.equal(initial.systems.length, 1);
  assert.equal(initial.factions.length, 2);
  assert.equal(initial.ships.length, 8);
  assert.equal(initial.facilities.length, 14);
  assert.equal(initial.markets.length, 6);
  assert.equal((await fetch(base + '/observer')).status, 200);
  socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  await new Promise((done, reject) => {
    const timeout = setTimeout(() => reject(new Error('WebSocket timed out')), 3000);
    socket.addEventListener('open', () => { clearTimeout(timeout); done(); }, { once: true });
    socket.addEventListener('error', (error) => { clearTimeout(timeout); reject(error); }, { once: true });
  });
  socket.addEventListener('message', ({ data }) => {
    try {
      const msg = JSON.parse(data);
      for (const event of msg.events ?? []) {
        if (!event.kind.startsWith('ship_transaction_')) continue;
        const key = `${event.ship_id}:${event.request_id}`;
        assert.ok(!receipts.has(key), `duplicate receipt ${key}`);
        receipts.add(key);
        events.push(event);
      }
    } catch (error) { eventError = error; }
  });
  await post('/api/sim/speed', { ticks_per_second: 60, world_speed: 16 });
  const target = initial.tick + 3600;
  const deadline = Date.now() + 80_000;
  let report = initial;
  let lastProgress = initial.tick;
  while (report.tick < target) {
    assert.ok(Date.now() < deadline, 'tick advance timed out');
    assert.equal(server.exitCode, null, `server crashed; see ${dir}`);
    if (eventError) throw eventError;
    await delay(250);
    report = await get('/api/report');
    physicalBounds(report);
    if (report.tick - lastProgress >= 1000) {
      console.log(`tick ${report.tick}; transaction receipts ${events.length}`);
      lastProgress = report.tick;
    }
  }
  await post('/api/sim/pause');
  if (eventError) throw eventError;
  const applied = events.filter(e => e.kind === 'ship_transaction_applied');
  assert.ok(applied.length > 0, 'no real transactions observed');
  const countBy = (rows, key) => rows.reduce((out, row) => {
    const value = row[key]; out[value] = (out[value] ?? 0) + 1; return out;
  }, {});
  const contracts = await get('/api/contracts');
  const result = { ticks: report.tick - initial.tick, ships: report.ships.length,
    applied: countBy(applied, 'operation'), rejected: countBy(events.filter(e => e.kind === 'ship_transaction_rejected'), 'reason'),
    paidContracts: contracts.data.filter(c => c.status === 'paid').length };
  writeFileSync(join(dir, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  passed = true;
} finally {
  socket?.close();
  server.kill('SIGTERM');
  for (let i = 0; i < 20 && server.exitCode === null; i++) await delay(100);
  if (server.exitCode === null) server.kill('SIGKILL');
  if (passed) rmSync(dir, { recursive: true, force: true });
  else console.error(`Smoke diagnostics: ${dir}`);
}
