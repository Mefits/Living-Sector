import test from "node:test";
import assert from "node:assert/strict";
import {shipPriority, resourceGradeEntries} from "./priority-inspector.js";

const index={factionById:new Map([
  ["ceti-freeholds",{name:"Ceti Freeholds"}],
  ["pirates",{name:"Pirates"}]
])};

test("ship card prioritizes faction, native task, route and REAL cargo",()=>{
  const data=shipPriority({
    faction_id:"ceti-freeholds",class:"freighter",current_goal:"trade_run",
    current_bt:'Travel { destination: "mars-colony" }',
    transit:{from:"alpha-station",to:"mars-colony",distance_total:20,distance_travelled:8},
    cargo:{food:100,water:25,gas:0},cargo_capacity:300,credits:500
  },index);
  assert.equal(data.faction,"Ceti Freeholds");
  assert.equal(data.task,"Торговый рейс");
  assert.equal(data.origin,"alpha-station");
  assert.equal(data.destination,"mars-colony");
  assert.equal(data.progress,40);
  assert.deepEqual(data.cargo.map(c=>c.id),["food","water"]);
  assert.equal(data.cargoUsed,125);
  assert.equal(data.cargoCapacity,300);
});

test("no fabricated destination or trip progress when server has no route",()=>{
  const data=shipPriority({
    faction_id:"pirates",current_goal:"sell_cargo",
    current_bt:"DockDwell { seconds: 2 }",location:"pirate-outpost",
    transit:null,docked:true,cargo:{},fuel:10
  },index);
  assert.equal(data.faction,"Pirates");
  assert.equal(data.task,"Продажа груза");
  assert.equal(data.status,"Пристыкован");
  assert.equal(data.destination,null);
  assert.equal(data.progress,null);
  assert.deepEqual(data.cargo,[]);
});

test("extract destination from authoritative Travel action when transit is not yet set",()=>{
  const data=shipPriority({
    faction_id:"pirates",current_goal:"patrol",
    current_bt:'Travel { destination: "nadir-outpost" }',
    location:"pirate-outpost",transit:null,cargo:{}
  },index);
  assert.equal(data.destination,"nadir-outpost");
  assert.equal(data.progress,null);
  assert.equal(data.origin,"pirate-outpost");
});

test("planet grade UI reports only server-supplied I-V levels",()=>{
  assert.deepEqual(resourceGradeEntries({
    resource_grades:{ore:4,ice:2,gas:0}
  }).map(x=>[x.id,x.grade]),[["ore",4],["ice",2]]);
  assert.deepEqual(resourceGradeEntries({resources:{ore:1.0}}),[]);
  assert.deepEqual(resourceGradeEntries({resource_grades:{"ore":6,"ice":"4"}}),[]);
  assert.deepEqual(resourceGradeEntries({resource_grades:null}),[]);
});
