// Node >=22.13. Run from the repository root against a compiled genesis_server.
// Uses the stock Genesis seed and a fresh temporary save. Only clock controls
// and read endpoints are used. --observe collects a baseline without assertions
// about the scenario outcome or a restart.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { closeSync, mkdtempSync, openSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const binary = resolve(process.argv[2] ?? 'target/debug/genesis_server');
const observe = process.argv.includes('--observe');
const dir = mkdtempSync(join(tmpdir(), 'genesis-autonomous-'));
const listener = createServer();
listener.listen(0, '127.0.0.1');
await once(listener, 'listening');
const port = listener.address().port;
await new Promise((done) => listener.close(done));
const origin = `http://127.0.0.1:${port}`;
const strategyTags = new Set(['strategy.logistics.v1', 'strategy.construction.v1']);
const contracts = new Map();
const flights = new Map();
const events = [];
let socket, server, report, strategy, checkpoint, restored, passed;
let phase = 0;

async function request(path, body, status = 200) {
  const options = { signal: AbortSignal.timeout(2000) };
  if (body !== undefined) {
    Object.assign(options, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body) });
  }
  const response = await fetch(origin + path, options);
  assert.equal(response.status, status, path);
  return response.json();
}

async function start() {
  const log = openSync(join(dir, 'server.log'), 'a');
  server = spawn(binary, [], {
    env: { ...process.env, DATABASE_PATH: join(dir, phase ? 'in-flight.db' : 'world.db'), DATA_DIR: resolve('priv/genesis/data'),
      LIVING_SECTOR_STRATEGY_MODE: 'execute', WORLD_SPEED: phase ? '0.25' : '16.0', BIND_ADDR: `127.0.0.1:${port}` },
    stdio: ['ignore', log, log],
  });
  const current = server;
  const exited = once(current, 'exit');
  closeSync(log);
  const deadline = Date.now() + 20_000;
  while (true) {
    assert.equal(current.exitCode, null, 'server exited during startup');
    try { report = await request('/api/report'); break; }
    catch (error) { if (Date.now() >= deadline) throw error; await delay(50); }
  }
  socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(data);
    for (const event of message.events ?? []) {
      if (event.kind.startsWith('construction_') || event.kind.startsWith('ship_transaction_')) {
        events.push({ ...event, tick: event.tick ?? message.tick, phase });
      }
    }
  });
  await Promise.race([
    new Promise((done, reject) => {
      socket.addEventListener('open', done, { once: true });
      socket.addEventListener('error', () => reject(new Error('WebSocket connection failed')), { once: true });
    }),
    delay(3000, undefined, { ref: false }).then(() => { throw new Error('WebSocket connection timed out'); }),
  ]);
  return { exited };
}

async function sample() {
  [report, strategy] = await Promise.all([request('/api/report'), request('/api/strategy')]);
  for (const c of (await request('/api/contracts')).data) {
    if (strategyTags.has(c.mission_category)) contracts.set(c.id, c);
  }
  for (const ship of report.ships) {
    const c = contracts.get(ship.active_contract_id);
    if (c && ship.transit?.distance_travelled > 0 && ship.cargo[c.commodity] >= c.quantity) {
      flights.set(c.id, { ship: ship.id, ...ship.transit });
    }
  }
}

async function pause() {
  await request('/api/sim/pause', {});
  const deadline = Date.now() + 2000;
  do {
    await sample();
    if (!report.running) return;
    await delay(25);
  } while (Date.now() < deadline);
  throw new Error('clock did not pause');
}

async function stop(exited) {
  socket?.close();
  server.kill('SIGTERM');
  const result = await Promise.race([exited, delay(3500, null, { ref: false })]);
  if (!result) { server.kill('SIGKILL'); await exited; }
  assert.deepEqual(result, [0, null], 'server failed graceful shutdown');
}

function deliveries() {
  return [...contracts.values()].filter(c => c.status === 'paid').map(c => {
    const applied = events.filter(e => e.kind === 'ship_transaction_applied' && e.ship_id === c.fulfiller_id);
    const accept = applied.find(e => e.operation === 'accept' && e.contract_id === c.id);
    const deliver = applied.find(e => e.operation === 'deliver' && e.contract_id === c.id);
    const buy = applied.find(e => e.operation === 'buy' && e.tick >= accept?.tick &&
      e.tick <= deliver?.tick && e.location === c.source_location && e.commodity === c.commodity);
    return { id: c.id, faction: c.requestor_id, type: c.contract_type, ship: c.fulfiller_id,
      quantity: c.quantity, paid: deliver?.payment, accept: accept?.tick, buy: buy?.tick,
      deliver: deliver?.tick, flight: flights.get(c.id) };
  });
}

let exited;
try {
  ({ exited } = await start());
  await request('/api/sim/speed', { ticks_per_second: 60, world_speed: 16 });
  const deadline = Date.now() + 135_000;
  const maxTick = 5500;
  while (true) {
    await delay(100);
    await sample();
    assert.ok(Date.now() < deadline, 'scenario timed out');
    if (!observe && !checkpoint) {
      const ship = report.ships.find(s => {
        const c = contracts.get(s.active_contract_id);
        return c?.contract_type === 'construction' && s.transit?.distance_travelled > 0 &&
          s.cargo[c.commodity] >= c.quantity;
      });
      if (ship) {
        await pause();
        const held = report.ships.find(s => s.id === ship.id);
        if (held?.transit && held.active_contract_id === ship.active_contract_id) {
          checkpoint = { tick: report.tick, ship: held, contract: contracts.get(held.active_contract_id),
            sites: report.construction_sites.map(s => s.id).sort() };
          const saved = await request('/api/admin/save-as', { name: 'in-flight' }, 201);
          assert.equal(saved.tick, checkpoint.tick);
          const db = new DatabaseSync(join(dir, 'in-flight.db'), { readOnly: true });
          try {
            const row = db.prepare('SELECT resume_json, cargo, fuel FROM ships WHERE active_contract_id = ?')
              .get(held.active_contract_id);
            assert.ok(row, 'saved ship lost active contract');
            const resume = JSON.parse(row.resume_json);
            const comparableTransit = transit => ({
              ...transit,
              distance_total: Math.fround(transit.distance_total),
              distance_travelled: Math.fround(transit.distance_travelled),
              departure_position: transit.departure_position?.map(Math.fround),
            });
            assert.deepEqual(comparableTransit(resume.transit), comparableTransit(held.transit),
              'SQLite did not checkpoint the active leg');
            assert.deepEqual(JSON.parse(row.cargo), held.cargo);
            assert.equal(row.fuel, held.fuel);
          } finally {
            db.close();
          }
          await stop(exited);
          phase++;
          ({ exited } = await start());
          const resumed = report.ships.find(s => s.id === held.id);
          assert.equal(resumed?.active_contract_id, held.active_contract_id, 'held contract lost on restart');
          assert.deepEqual(resumed.cargo, held.cargo, 'cargo changed on restart');
          if (resumed.transit) {
            assert.equal(resumed.transit.departure_tick, held.transit.departure_tick, 'flight restarted');
          } else {
            assert.equal(resumed.location, held.transit.to, 'ship lost its flight destination');
          }
          assert.deepEqual(report.construction_sites.map(s => s.id).sort(), checkpoint.sites, 'site changed on restart');
          restored = { savedTick: saved.tick, tick: report.tick, distance: held.transit.distance_travelled,
            contract: checkpoint.contract.id };
          console.log('Restored loaded flight', restored);
          await request('/api/sim/speed', { ticks_per_second: 60, world_speed: 16 });
        } else {
          await request('/api/sim/resume', {});
        }
      }
    }
    const delivered = deliveries();
    if (report.tick >= maxTick || (!observe && restored &&
      delivered.some(d => d.id === checkpoint.contract.id) &&
      ['pirates', 'terran-authority'].every(f => delivered.some(d => d.faction === f && d.buy && d.flight)) &&
      events.some(e => e.kind === 'construction_completed'))) break;
  }
  await pause();
  const delivered = deliveries();
  const completed = events.filter(e => e.kind === 'construction_completed');
  const rejected = events.filter(e => e.kind === 'ship_transaction_rejected' &&
    e.reason === 'insufficient_contract_funding' && contracts.has(e.contract_id));
  console.log(JSON.stringify({ tick: report.tick, delivered, completed, restored,
    strategicFundingRejections: rejected.length }, null, 2));
  if (!observe) {
    assert.ok(restored, 'no loaded construction flight available for restart');
    assert.ok(delivered.some(d => d.id === checkpoint.contract.id && d.deliver), 'resumed delivery never paid');
    const repeated = events.filter(e => e.phase === 1 && e.kind === 'ship_transaction_applied' &&
      e.ship_id === checkpoint.ship.id && e.tick <= delivered.find(d => d.id === checkpoint.contract.id).deliver &&
      (e.operation === 'accept' || (e.operation === 'buy' && e.commodity === checkpoint.contract.commodity)));
    assert.deepEqual(repeated, [], 'resumed flight repeated acceptance or cargo purchase');
    assert.equal(rejected.length, 0, 'strategic offers exceeded their funding');
    for (const faction of ['pirates', 'terran-authority']) {
      assert.ok(delivered.some(d => d.faction === faction && d.accept && d.buy && d.deliver && d.flight?.ship === d.ship),
        `no autonomous strategic delivery with witnessed flight for ${faction}`);
    }
    assert.ok(completed.some(e => {
      const progress = events.filter(p => p.kind === 'construction_progress' && p.site_id === e.site_id);
      return events.some(p => p.kind === 'construction_site_started' && p.site_id === e.site_id) &&
        progress.length >= 3 && progress.at(-1).progress === 1 &&
        report.facilities.some(f => f.id === e.facility_id) &&
        report.construction_sites.every(s => s.id !== e.site_id);
    }), 'no completed facility witnessed from site creation through three deliveries');
  }
  passed = true;
} finally {
  writeFileSync(join(dir, 'diagnostics.json'), JSON.stringify({ report, strategy,
    contracts: [...contracts.values()], events, checkpoint, restored }, null, 2));
  if (server?.exitCode === null && exited) await stop(exited);
  if (passed && !observe) rmSync(dir, { recursive: true, force: true });
  else console.error(`Diagnostics: ${dir}`);
}
