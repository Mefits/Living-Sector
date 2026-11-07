import test from "node:test";
import assert from "node:assert/strict";
import {
  buildIndex, ownership, factionColor, positionOf, shortageCount,
  systemAtPosition, approximateShipsNear,
  panForCursorZoom, panToFollowWorldPoint, clusterMarkers, shipSystem,
  groupFacilitiesByLocation, layoutMapLabels, shipMapState, shipsAtHub,
  liveEntityPoint, approachWorldPoint
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

test("zooming around cursor does not move the selected world point on screen",()=>{
  const viewport={w:1000,h:700}, cursor={x:750,y:170};
  const pan={x:115,y:-38};
  const before={x:cursor.x-viewport.w/2-pan.x,y:cursor.y-viewport.h/2-pan.y};
  const result=panForCursorZoom(pan,cursor,viewport,1,1.4);
  const after={x:cursor.x-viewport.w/2-result.x,y:cursor.y-viewport.h/2-result.y};
  assert.ok(Math.abs(before.x*1.4-after.x)<1e-9);
  assert.ok(Math.abs(before.y*1.4-after.y)<1e-9);
  assert.deepEqual(panForCursorZoom(pan,cursor,viewport,1,1),pan);
  const restored=panForCursorZoom(result,cursor,viewport,1.4,1);
  assert.ok(Math.abs(restored.x-pan.x)<1e-9);
  assert.ok(Math.abs(restored.y-pan.y)<1e-9);
});
test("marker clustering preserves all real entities without multiplication",()=>{
  const markers=[
    {id:"a",x:10,y:10},{id:"b",x:11,y:11},{id:"c",x:88,y:10}
  ];
  const groups=clusterMarkers(markers,34);
  assert.equal(groups.length,2);
  assert.equal(groups[0].members.length,2);
  assert.equal(groups[1].members.length,1);
  assert.deepEqual(groups.flatMap(g=>g.members.map(m=>m.id)).sort(),["a","b","c"]);
});
test("ship system membership is based on exact location, not map proximity",()=>{
  const i=buildIndex(report);
  assert.equal(shipSystem({location:"earth-station"},i),"Sol");
  assert.equal(shipSystem({location:"earth"},i),"Sol");
  assert.equal(shipSystem({location:"tau-gate"},i),"Tau Ceti");
  assert.equal(shipSystem({location:"unknown",position:{x:0,y:0}},i),null);
  assert.equal(shipSystem({transit:{from:"earth-gate",to:"tau-gate"}},i),null);
  assert.equal(shipSystem({transit:{from:"earth-station",to:"earth-gate"}},i),"Sol");
});


test("facility icons represent actual physical locations, not every building",()=>{
  const facilities=[
    {id:"a",location:"earth-station",name:"Genesis Station"},
    {id:"b",location:"earth-station",name:"Genesis Shipyard"},
    {id:"c",location:"belt-outpost",name:"Belt Extraction"}
  ];
  const groups=groupFacilitiesByLocation(facilities);
  assert.equal(groups.length,2);
  assert.equal(groups[0].members.length,2);
  assert.equal(groups[1].members.length,1);
  assert.deepEqual(groups.flatMap(g=>g.members.map(x=>x.id)).sort(),["a","b","c"]);
});
test("labels avoid overlapping other labels and real map glyphs",()=>{
  const labels=[
    {id:"ship1",x:150,y:150,text:"Cargo 1",w:100,h:20,radius:16,priority:0},
    {id:"ship2",x:150,y:150,text:"Cargo 2",w:100,h:20,radius:16,priority:1},
    {id:"hub",x:150,y:150,text:"Station",w:90,h:20,radius:16,priority:2}
  ];
  const obstacle={x:140,y:140,w:20,h:20};
  const placed=layoutMapLabels(labels,{w:450,h:300},[obstacle]);
  assert.equal(placed.length,3);
  const intersects=(a,b)=>a.x < b.x+b.w && a.x+a.w > b.x &&
    a.y < b.y+b.h && a.y+a.h > b.y;
  for(const p of placed)assert.equal(intersects(p,obstacle),false);
  for(let i=0;i<placed.length;i++){
    for(let j=i+1;j<placed.length;j++)assert.equal(intersects(placed[i],placed[j]),false);
  }
  assert.ok(placed.every(p=>p.x>=8&&p.y>=8));
});
test("too many labels never overlap or move actual map markers",()=>{
  const glyph={x:25,y:25,w:20,h:20};
  const labels=Array.from({length:25},(_,i)=>({
    id:"object"+i,x:35,y:35,w:110,h:20,radius:16,priority:i
  }));
  const before=structuredClone(labels);
  const placed=layoutMapLabels(labels,{w:190,h:120},[glyph]);
  assert.ok(placed.length<labels.length);
  assert.deepEqual(labels,before);
});

test("only explicit transit draws a moving ship, never a docked/parked one",()=>{
  const inTransit={id:"f",location:null,transit:{from:"earth-station",to:"belt-outpost"},docked:false};
  const docked={id:"d",location:"earth-station",transit:null,docked:true};
  const parked={id:"p",location:"earth-station",transit:null,docked:false};
  const lost={id:"x",location:null,transit:null,docked:false};
  assert.equal(shipMapState(inTransit),"in_transit");
  assert.equal(shipMapState(docked),"docked");
  assert.equal(shipMapState(parked),"at_location");
  assert.equal(shipMapState(lost),"unknown");
  assert.equal(shipMapState({docked:true,location:"earth-station",
    transit:{from:"earth-station",to:"belt-outpost"}}),"in_transit");
});
test("station ship list contains real docked/parked ships by exact location only",()=>{
  const ships=[
    {id:"d",location:"earth-station",docked:true,transit:null},
    {id:"p",location:"EARTH-STATION",docked:false,transit:null},
    {id:"f",location:"earth-station",docked:false,
      transit:{from:"earth-station",to:"belt-outpost"}},
    {id:"o",location:"belt-outpost",docked:true,transit:null}
  ];
  assert.deepEqual(shipsAtHub(ships,"earth-station").map(s=>s.id),["d","p"]);
  assert.deepEqual(shipsAtHub(ships,"belt-outpost").map(s=>s.id),["o"]);
  assert.equal(shipsAtHub(ships,"unknown").length,0);
  assert.equal(shipsAtHub(ships,"").length,0);
});

test("map bodies and stations prioritize live server WS positions over older snapshots",()=>{
  const body={id:"earth",x:10,y:0,position:{x:10,y:0}};
  const facility={id:"facility-genesis",position:{x:10.1,y:0.2}};
  const positions=new Map([
    ["earth",{x:3,y:8}],
    ["facility-genesis",{x:3.1,y:8.2}]
  ]);
  assert.deepEqual(liveEntityPoint(body,positions),{x:3,y:8});
  assert.deepEqual(liveEntityPoint(facility,positions),{x:3.1,y:8.2});
  assert.deepEqual(liveEntityPoint(facility,new Map()),{x:10.1,y:0.2});
  assert.deepEqual(liveEntityPoint(body,new Map()),{x:10,y:0});
});
test("visual orbital interpolation follows live coordinates without altering source or overshooting",()=>{
  const original={x:0,y:0},newPos={x:4,y:0};
  const result=approachWorldPoint(original,newPos,0.25,12);
  assert.deepEqual(result,{x:1,y:0});
  assert.deepEqual(original,{x:0,y:0});
  assert.deepEqual(newPos,{x:4,y:0});
  assert.deepEqual(approachWorldPoint(null,newPos),newPos);
  assert.deepEqual(approachWorldPoint(original,{x:200,y:0}),{x:200,y:0});
  assert.equal(approachWorldPoint(original,null),null);
});
test("regression: no hidden parked ships or fake circular vessel placement in map renderer",async()=>{
  const {readFileSync}=await import("node:fs");
  const app=readFileSync(new URL("./app.js",import.meta.url),"utf8");
  assert.ok(app.includes("hubAnchors.set(key(hub.location)"));
  assert.ok(app.includes("anchoredShips.add(ship.id)"));
  assert.ok(app.includes("drawShip(ship,at"));
  assert.ok(app.includes("liveWorldPoint(prefer)"));
  assert.ok(app.includes("liveWorldPoint(body)"));
  assert.ok(!app.includes("const angle=-Math.PI/2+(2*Math.PI*i/group.members.length)"));
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

test("follow-camera recentering tracks any moving world object without screen drift",()=>{
  const bounds={cx:2,cy:-4};
  const scale=24,w=960,h=600;
  for(const target of [{x:2,y:-4},{x:18,y:7},{x:-3,y:11}]){
    const pan=panToFollowWorldPoint(target,bounds,scale);
    const screen={x:w/2+(target.x-bounds.cx)*scale+pan.x,
      y:h/2-(target.y-bounds.cy)*scale+pan.y};
    assert.ok(Math.abs(screen.x-w/2)<1e-9);
    assert.ok(Math.abs(screen.y-h/2)<1e-9);
  }
});

test("physical station marker stays at server location, never reflows around planets",async()=>{
  const {readFileSync}=await import("node:fs");
  const app=readFileSync(new URL("./app.js",import.meta.url),"utf8");
  const html=readFileSync(new URL("./index.html",import.meta.url),"utf8");
  assert.ok(app.includes("const at=actual;"),"complex must stay on physical position");
  assert.ok(app.includes("followSelectedObject()"));
  assert.ok(app.includes("if(s.follow)stopFollowing()"));
  assert.ok(html.includes('id="follow-btn"'));
  assert.ok(!app.includes("const at=layoutMarker(actual,footprint,0)"));
});
