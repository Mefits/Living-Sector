import test from "node:test";
import assert from "node:assert/strict";
import {
  buildIndex, ownership, factionColor, positionOf, shortageCount,
  systemAtPosition, approximateShipsNear
} from "./model.js";

const report = {
  systems: [
    {name:"Sol",id:"system-sol",offset_x:0,offset_y:0,bodies:[
      {id:"earth",name:"Earth",controlling_faction:"f1",contested:false,x:0,y:2}
    ]},
    {name:"Tau Ceti",id:"system-tau",offset_x:40,offset_y:10,bodies:[
      {id:"tau-1",name:"Tau I",controlling_faction:"f2",contested:false,x:41,y:10}
    ]}
  ],
  factions:[
    {id:"f1",name:"Terrans",colors:{primary:"#3b82f6"}},
    {id:"f2",name:"Mining",colors:{primary:"#e1a243"}}
  ],
  facilities:[
    {id:"g1",name:"Sol Gate",body_id:"earth",location:"earth-gate",gate_link:{paired_gate_id:"g2"}},
    {id:"g2",name:"Tau Gate",body_id:"tau-1",location:"tau-gate",gate_link:{paired_gate_id:"g1"}},
    {id:"f3",name:"Sol Foundry",body_id:"earth",location:"earth-station"}
  ],
  markets:[
    {id:"market-earth",facility_location:"earth-station",shortage_ticks:{fuel:3,ore:0}},
    {id:"unknown-market",facility_location:"nonexistent",shortage_ticks:{ore:900}}
  ],
  populations:[{id:"p1",facility_location:"earth-station"}]
};
test("real gate pairs create one non-fictitious inter-system link",()=>{
  const i=buildIndex(report);
  assert.deepEqual(i.gateLinks,[{a:"Sol",b:"Tau Ceti"}]);
  assert.equal(i.systemFacilities.get("Sol").length,2);
  assert.equal(i.systemMarkets.get("Sol").length,1);
  assert.equal(i.systemPopulations.get("Sol").length,1);
  assert.equal(shortageCount(i.systemMarkets.get("Sol")),1);
});
test("missing gate endpoint never fabricates route",()=>{
  const i=buildIndex({...report,facilities:report.facilities.filter(x=>x.id!=="g2")});
  assert.deepEqual(i.gateLinks,[]);
});
test("ownership is derived from body snapshots, not declared as actual system_control",()=>{
  assert.deepEqual(ownership(report.systems[0]),{kind:"single",factionId:"f1",contested:false});
  assert.equal(ownership({bodies:[{controlling_faction:"f1"},{controlling_faction:"f2"}]}).kind,"mixed");
  assert.equal(ownership({bodies:[{controlling_faction:"f1",contested:true}]}).kind,"mixed");
  assert.equal(ownership({bodies:[]}).kind,"unknown");
});
test("ship positions come from live WebSocket updates when present",()=>{
  const ship={id:"s1",position:{x:1,y:1}};
  assert.deepEqual(positionOf(ship,new Map([["s1",{x:5,y:6}]])),{x:5,y:6});
  assert.deepEqual(positionOf(ship,new Map()),{x:1,y:1});
});
test("faction color is the existing project's palette",()=>{
  const i=buildIndex(report);
  assert.equal(factionColor("f1",i),"#3b82f6");
  assert.equal(factionColor("missing",i),"#8da3b9");
});
test("nearest system and proximity figures are only best-effort grouping",()=>{
  const i=buildIndex(report);
  assert.equal(systemAtPosition({x:41,y:10},i.systems).name,"Tau Ceti");
  const ships=[{id:"s1",position:{x:1,y:2}},{id:"s2",position:{x:39,y:10}}];
  assert.equal(approximateShipsNear(i.systems[0],ships,new Map(),5).length,1);
});
test("body ids ambiguous between two systems cannot establish a gate",()=>{
  const clone=structuredClone(report);
  clone.systems[1].bodies[0].id="earth";
  const i=buildIndex(clone);
  assert.deepEqual(i.gateLinks,[]);
});

test("UI ids referenced by the code exist in the actual HTML", async () => {
  const { readFileSync } = await import("node:fs");
  const app = readFileSync(new URL("./app.js", import.meta.url), "utf8");
  const html = readFileSync(new URL("./index.html", import.meta.url), "utf8");
  const match = app.match(/const els = Object\.fromEntries\(\[([\s\S]*?)\]\.map/);
  assert.ok(match, "UI id binding block should be present");
  const ids = [...match[1].matchAll(/"([a-z][a-z0-9-]+)"/g)].map(m => m[1]);
  assert.ok(ids.length > 25, "expected all mapped UI controls");
  for (const id of ids) assert.ok(html.includes('id="' + id + '"'), "missing HTML id: " + id);
});
