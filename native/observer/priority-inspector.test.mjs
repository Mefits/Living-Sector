import test from "node:test";
import assert from "node:assert/strict";
import {shipPriority, resourceGradeEntries, stationVisualOccupancy} from "./priority-inspector.js";

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


test("Galaxy 0.4.1 visually distinguishes 3 buildings plus paid fourth project",()=>{
  const station={location:"venus-colony",body_id:"venus",faction_id:"terran-authority"};
  const report={
    facilities:[
      {type:"station",...station},
      ...["mining_rig","refinery","farm"].map(type=>({type,...station})),
      {type:"factory",location:"earth-station",faction_id:"terran-authority",body_id:"earth"}
    ],
    construction_sites:[{...station,facility_type:"factory",
      progress_delivered:400,progress_required:600,labor:{blocked_reason:"awaiting_materials"}}]
  };
  const result=stationVisualOccupancy(report,station);
  assert.equal(result.visualTier,"T1");
  assert.equal(result.capacity,4);
  assert.equal(result.built.length,3);
  assert.equal(result.projects.length,1);
  assert.equal(result.empty,0);
});
test("Galaxy 0.4.1 three built and no project really leave one visual socket",()=>{
  const station={location:"nadir-ashfall-colony",body_id:"nadir-ashfall",faction_id:"pirates"};
  const report={facilities:[{...station,type:"station"},
    ...["farm","refinery","mining_rig"].map(type=>({...station,type}))],
    construction_sites:[]};
  const result=stationVisualOccupancy(report,station);
  assert.equal(result.capacity,4);
  assert.equal(result.empty,1);
  assert.equal(result.projects.length,0);
});
