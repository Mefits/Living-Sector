import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
  parseSnapshot, observedChanges, observationAge, goalKey, human,
  decisionLabels, reasonLabels, projectLabels
} from "./strategy-model.js";

const fixture = JSON.parse(readFileSync(
  new URL("./strategy-api-v1.fixture.json", import.meta.url), "utf8"
));
const snapshot = () => structuredClone(fixture);

test("strategy API v1 fixture is accepted without inventing goals or projects", () => {
  const state = parseSnapshot(snapshot());
  assert.equal(state.schema_version, 1);
  assert.equal(state.factions[0].goals.length, 1);
  assert.equal(state.factions[0].projects.length, 1);
  assert.equal(state.mode, "execute");
  assert.equal(observationAge(state, state.factions[0]), 80);
  assert.equal(state.factions[0].projects[0].reserved_credits, 0);
});
test("unknown or incompatible API version is not shown as live strategic data", () => {
  for (const raw of [
    null, {}, {...fixture, schema_version: 2},
    {...fixture, factions: null}, {...fixture, snapshot_tick: -1},
    {...fixture, mode: "experimental"}
  ]) assert.throws(() => parseSnapshot(raw), /Неподдерживаемый/);
  assert.equal(human("new_status", decisionLabels), "new_status");
  assert.equal(human("new_reason", reasonLabels), "new_reason");
  assert.equal(human("new_project_state", projectLabels), "new_project_state");
});
test("goal identity is scoped by commodity and destination, not category alone", () => {
  assert.notEqual(
    goalKey({goal_id:"supply_industry",commodity:"ore",destination:"earth"}),
    goalKey({goal_id:"supply_industry",commodity:"fuel",destination:"earth"})
  );
  assert.notEqual(
    goalKey({goal_id:"supply_industry",commodity:"ore",destination:"earth"}),
    goalKey({goal_id:"supply_industry",commodity:"ore",destination:"mars"})
  );
});
test("first poll and unchanged tick do not create synthetic history", () => {
  const state = parseSnapshot(snapshot());
  assert.deepEqual(observedChanges(null, state), []);
  assert.deepEqual(observedChanges(state, state), []);
});
test("local history includes only actual differences between two observed states", () => {
  const prev = parseSnapshot(snapshot());
  const nextRaw = snapshot();
  nextRaw.snapshot_tick = 260;
  nextRaw.factions[0].status = "waiting";
  nextRaw.factions[0].reason = "existing_contract";
  nextRaw.factions[0].projects[0].state = "expired";
  nextRaw.factions[0].selected_goal = null;
  const next = parseSnapshot(nextRaw);
  const diff = observedChanges(prev, next);
  assert.equal(diff.length, 3);
  assert.ok(diff.every(x => x.tick === 260 && x.faction_id === "example-faction"));
  assert.ok(diff.some(x => x.message.includes("Выбранный приоритет")));
  assert.ok(diff.some(x => x.message.includes("Ожидание")));
  assert.ok(diff.some(x => x.message.includes("Оплачен → Истёк")));
  assert.deepEqual(observedChanges(next, prev), [], "rollback is not an event");
});
test("a newly observed native contract is not mistaken for a completed project", () => {
  const prevRaw = snapshot();
  prevRaw.factions[0].projects = [];
  const nextRaw = snapshot();
  nextRaw.snapshot_tick += 30;
  nextRaw.factions[0].projects[0].state = "posted";
  const diff = observedChanges(parseSnapshot(prevRaw), parseSnapshot(nextRaw));
  assert.equal(diff.length, 1);
  assert.match(diff[0].message, /Впервые наблюдаем проект/);
  assert.match(diff[0].message, /Опубликован/);
  assert.doesNotMatch(diff[0].message, /Оплачен/);
});
test("strategy interface wires the declared controls without modifying simulation API", () => {
  const html = readFileSync(new URL("./index.html", import.meta.url), "utf8");
  const app = readFileSync(new URL("./app.js", import.meta.url), "utf8");
  const ui = readFileSync(new URL("./strategy-ui.js", import.meta.url), "utf8");
  const ids = [...ui.matchAll(/find\("([a-z-]+)"\)/g)].map(match => match[1]);
  // Every static element used by the standalone module exists in the HTML.
  for (const id of ids) assert.ok(html.includes('id="' + id + '"'), id);
  for (const id of [
    "strategy-toggle", "strategy-drawer", "strategy-backdrop", "strategy-faction",
    "strategy-content", "strategy-summary", "strategy-goals", "strategy-projects",
    "strategy-history", "strategy-close", "strategy-refresh"
  ]) assert.ok(html.includes('id="' + id + '"'), "missing " + id);
  assert.match(app, /initStrategyPanel\(/);
  assert.match(app, /openStrategyForFaction\(/);
  assert.match(ui, /fetch\("\/api\/strategy",\s*\{cache:\s*"no-store"\}\)/);
  assert.doesNotMatch(ui, /method:\s*["']POST|\/api\/sim\/|innerHTML/);
});

test("diagnostic export is a read-only click action with bounded browser history", () => {
  const html = readFileSync(new URL("./index.html", import.meta.url), "utf8");
  const app = readFileSync(new URL("./app.js", import.meta.url), "utf8");
  assert.match(html, /id="export-diagnostics"/);
  assert.match(app, /els\.exportDiagnostics\.addEventListener\("click",exportDiagnostics\)/);
  const start = app.indexOf("async function exportDiagnostics()");
  const end = app.indexOf("function handleEvents(", start);
  assert.ok(start >= 0 && end > start, "export handler should exist");
  const exportCode = app.slice(start, end);
  for (const endpoint of ["/api/health","/api/report","/api/strategy","/api/contracts"]) {
    assert.ok(exportCode.includes(endpoint), "missing diagnostics source: " + endpoint);
  }
  assert.match(exportCode, /browser_events_newest_first:\s*s\.events\.slice\(0,\s*100\)/);
  assert.match(exportCode, /new Blob\(/);
  assert.match(exportCode, /link\.download\s*=/);
  assert.doesNotMatch(exportCode, /postJSON\(|\/api\/sim\/|\/api\/admin\//);
});
