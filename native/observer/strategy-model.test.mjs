import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
  parseSnapshot, observedChanges, observationAge, goalKey, human,
  decisionLabels, reasonLabels, projectLabels,
  administratorLabels, headReasonLabels, assessmentForGoal, projectGroups, progressFraction,
  nativeExecutionForFaction, nativeOutcomeVerified, nativeGoalText
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
  const html = readFileSync(new URL("./native.html", import.meta.url), "utf8");
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
  const html = readFileSync(new URL("./native.html", import.meta.url), "utf8");
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
  assert.match(exportCode, /browser_events_newest_first:\s*s\.events\.slice\(0,\s*1000\)/);
  assert.match(app, /s\.events\.length\s*=\s*Math\.min\(s\.events\.length,1000\)/);
  assert.match(exportCode, /browser_event_capacity:\s*1000/);
  assert.match(exportCode, /new Blob\(/);
  assert.match(exportCode, /link\.download\s*=/);
  assert.doesNotMatch(exportCode, /postJSON\(|\/api\/sim\/|\/api\/admin\//);
});


test("S2–S4 additive API fields parse while S1 remains supported", () => {
  const s1 = parseSnapshot(snapshot());
  assert.equal(s1.factions[0].head, null);
  assert.equal(s1.factions[0].construction, null);
  assert.deepEqual(s1.factions[0].assessments, []);
  const raw = snapshot();
  const f = raw.factions[0];
  f.assessments = [{
    goal: f.goals[0], reason: "no_accessible_stock", source: null
  }];
  f.head = {
    observed_tick: 220, selected_administrator: "construction",
    reason: "finish_existing_construction", treasury_before: 80000,
    spending_limit: 75000, planned_spend: 10000, committed_spend: 10000,
    proposals: [
      {administrator:"logistics",goal:f.goals[0], status:"blocked",
       reason:"no_accessible_stock",requested_credits:1600, priority:3},
      {administrator:"construction",goal:{goal_id:"expand_production",
       commodity:"food",destination:"port",shortage_ticks:0,score:0},
       status:"proposed",reason:"shadow_no_mutation",requested_credits:10000,priority:2}
    ]
  };
  f.construction = {
    observed_tick: 220, status: "commissioned", reason:"funded_native_contract",
    selected_goal: {goal_id:"expand_production",commodity:"food",destination:"port",
      shortage_ticks:0,score:0},
    site_id:"site-3", facility_type:"farm", progress_delivered:400,
    progress_required:600, contract_id:"contract-4"
  };
  f.projects.push({project_id:"contract-4",contract_id:"contract-4",
    administrator:"construction",state:"posted",executor_id:null,
    reserved_credits:10000,source:"mine",destination:"port",
    commodity:"food",quantity:200});
  const parsed = parseSnapshot(raw);
  const view = parsed.factions[0];
  assert.equal(view.head.selected_administrator, "construction");
  assert.equal(view.head.committed_spend, 10000);
  assert.equal(view.construction.progress_required, 600);
  assert.equal(progressFraction(view.construction), 2/3);
  assert.equal(assessmentForGoal(view, view.goals[0]).reason, "no_accessible_stock");
  assert.equal(projectGroups(view).construction.length, 1);
  assert.equal(projectGroups(view).logistics.length, 1);
  assert.equal(human("construction", administratorLabels), "Строительство");
  assert.match(human("finish_existing_construction",headReasonLabels), /стройки/);
  assert.equal(progressFraction({progress_delivered:5,progress_required:0}), null);
  assert.equal(progressFraction({progress_delivered:999,progress_required:600}), 1);
});
test("S4 proposals alone are not reported as completed strategic contracts", () => {
  const raw = snapshot();
  raw.factions[0].projects = [];
  raw.factions[0].head = {
    observed_tick: raw.snapshot_tick, selected_administrator: null,
    reason:"no_feasible_proposal", treasury_before:30000,spending_limit:25000,
    planned_spend:0,committed_spend:0,
    proposals:[{administrator:"logistics",status:"proposed",reason:"ready",
      goal:raw.factions[0].goals[0],requested_credits:1600,priority:3}]
  };
  const previous = parseSnapshot(raw);
  const nextRaw = structuredClone(raw);
  nextRaw.snapshot_tick += 60;
  nextRaw.factions[0].head.observed_tick += 60;
  nextRaw.factions[0].head.selected_administrator = "logistics";
  nextRaw.factions[0].head.reason = "urgent_supply";
  const changes = observedChanges(previous, parseSnapshot(nextRaw));
  assert.equal(changes.length, 1);
  assert.match(changes[0].message, /Глава: Логистика/);
  assert.doesNotMatch(changes[0].message, /Оплачен|Доставлен/);
});
test("construction progress is observed from site state only, never inferred from paid contracts", () => {
  const raw = snapshot();
  raw.factions[0].construction = {
    observed_tick:200,status:"waiting",reason:"existing_contract",
    selected_goal:raw.factions[0].goals[0],
    site_id:"site-1",facility_type:"farm",progress_delivered:100,
    progress_required:600,contract_id:"contract-1"
  };
  const before = parseSnapshot(raw);
  const nextRaw = structuredClone(raw);
  nextRaw.snapshot_tick += 100;
  nextRaw.factions[0].construction.progress_delivered = 270;
  const changes = observedChanges(before,parseSnapshot(nextRaw));
  assert.equal(changes.length,1);
  assert.match(changes[0].message, /270 \/ 600/);
});
test("UI has dedicated head and construction sections and renders additive fields", () => {
  const html = readFileSync(new URL("./native.html", import.meta.url), "utf8");
  const ui = readFileSync(new URL("./strategy-ui.js", import.meta.url), "utf8");
  for (const id of ["strategy-head","strategy-construction","strategy-projects"]) {
    assert.ok(html.includes('id="' + id + '"'));
  }
  for (const field of ["planned_spend","committed_spend","spending_limit","assessments",
                       "progress_delivered","selected_administrator"]) {
    if (field==="assessments") {
      assert.match(ui, /assessmentForGoal/);
    } else assert.ok(ui.includes(field), field);
  }
  assert.match(ui, /Предложения показаны ДО исполнения/);
  assert.match(ui, /Контракты строительства — это доставки грузов/);
});

test("S7 choices remain forecast alternatives rather than executed contracts", () => {
  const raw = snapshot();
  raw.factions[0].head = {
    observed_tick: raw.snapshot_tick, selected_option:"deliver",
    problem:{goal_id:"supply_industry",commodity:"ice",destination:"earth-station",
      shortage_ticks:51,score:51},
    horizon_ticks:1200,
    alternatives:[
      {action:"deliver",status:"ready",reason:"positive_projected_relief",
        source:"belt-outpost",material:"ice",first_payment:1600,
        total_commitment:1600,treasury_after:8400,estimated_delay_ticks:120,
        shipment_count:1,covered_units:60,first_purchase_cost:150,estimated_net_value:25400},
      {action:"build",status:"blocked",reason:"no_construction_proposal",
        first_payment:0,total_commitment:0,covered_units:0},
      {action:"wait",status:"ready",reason:"reconsider_next_cycle",
        first_payment:0,total_commitment:0,covered_units:0}
    ]
  };
  const v = parseSnapshot(raw);
  assert.equal(v.factions[0].head.selected_option,"deliver");
  assert.equal(v.factions[0].head.alternatives[0].covered_units,60);
  assert.equal(v.factions[0].projects.length,raw.factions[0].projects.length);
  const ui = readFileSync(new URL("./strategy-ui.js",import.meta.url),"utf8");
  for(const key of ["head.alternatives","head.selected_option","head.horizon_ticks",
    "option.total_commitment","option.covered_units","option.estimated_net_value"]) {
    assert.ok(ui.includes(key),"missing S7 field "+key);
  }
  assert.match(ui,/НЕ фактический размер партии/);
  assert.match(ui,/Выбранный вариант не равен завершённому контракту/);
});

test("native HTN state parses with no fabricated receipts and survives legacy v1", () => {
  const legacy = parseSnapshot(snapshot());
  assert.equal(nativeExecutionForFaction(legacy, "example-faction"), null);
  const payload = snapshot();
  payload.ai_execution = {
    active: {"example-faction": { goal: {commodity:"water",destination_id:"earth",target_units:20},
      ledger: {planner_id:"hybrid",plan_id:"p1",steps:[
        {phase:"succeeded",step:{step_id:"s1",action_id:"supply_ice"},native_order_id:"contract-42"},
        {phase:"running",step:{step_id:"s2",action_id:"produce_water"},native_order_id:"facility:water"}
      ]} }},
    history: [{faction_id:"else",final_status:"completed"}],
    deferred_goals: {"example-faction": {goal:{commodity:"water",destination_id:"earth",target_units:20},failed_attempts:1}}
  };
  const result = nativeExecutionForFaction(parseSnapshot(payload), "example-faction");
  assert.equal(result.completed, 1);
  assert.equal(result.steps.length, 2);
  assert.equal(result.history.length, 0);
  assert.equal(result.deferred.failed_attempts, 1);
  assert.match(nativeGoalText(result.active.goal), /Вода/);
});

test("a claimed completion without genuine step receipts or final stock is not verified", () => {
  const goal = {target_units:20};
  const base = {final_status:"completed",reason:"native_receipts_and_goal_stock_confirmed",
    goal,observed_goal_stock:25,steps:[{phase:"succeeded",native_order_id:"paid-42"}]};
  assert.equal(nativeOutcomeVerified(base),true);
  assert.equal(nativeOutcomeVerified({...base,observed_goal_stock:19}),false);
  assert.equal(nativeOutcomeVerified({...base,steps:[{phase:"submitted",native_order_id:"paid-42"}]}),false);
  assert.equal(nativeOutcomeVerified({...base,steps:[{phase:"succeeded",native_order_id:null}]}),false);
  assert.equal(nativeOutcomeVerified({...base,reason:"forecast_only"}),false);
  assert.equal(nativeOutcomeVerified({...base,goal:null}),false);
  const produced={...base,reason:"native_recipe_receipts_and_goal_production_confirmed",
    observed_goal_stock:0,produced_goal_units:20,required_goal_production_units:20,
    steps:[{phase:"succeeded",native_order_id:"contract-8",reason_code:"native_contract_paid"},
      {phase:"succeeded",native_order_id:"facility:refinery",
       reason_code:"native_recipe_paid_and_output_counter_confirmed"}]};
  assert.equal(nativeOutcomeVerified(produced),true);
  assert.equal(nativeOutcomeVerified({...produced,produced_goal_units:0}),false);
  assert.equal(nativeOutcomeVerified({...produced,steps:base.steps}),false);
});

test("native planner panel has its own real source and uses safe DOM-only rendering", () => {
  const html = readFileSync(new URL("./native.html", import.meta.url),"utf8");
  const ui = readFileSync(new URL("./strategy-ui.js", import.meta.url),"utf8");
  assert.match(html, /id="strategy-ai-native"/);
  assert.match(ui, /renderNativeExecution\(active\)/);
  assert.doesNotMatch(ui, /innerHTML/);
  const galaxy = readFileSync(new URL("./galaxy.html", import.meta.url),"utf8");
  assert.match(galaxy, /ai_execution/);
  assert.match(galaxy, /Подтверждён запас и квитанции/);
});
