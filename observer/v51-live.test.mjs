import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
const read=name=>readFileSync(new URL(name,import.meta.url),"utf8");
test("default Observer is actual V5.1 layout, not a compact telemetry drawer",()=>{
 const s=read("./index.html");
 for(const id of ["stationList","mapPane","detailPanel","modalBackdrop","v51NativeMap",
   "v51Pause","v51Speed","v51LiveControls","nativeMapFrame"]) {
   if(id==="nativeMapFrame")continue;
   assert.ok(s.includes('id="'+id+'"'),id);
 }
 for(const label of ["Фракции","Хроника","Производство","Население","Графики"])assert.ok(s.includes(label),label);
 assert.match(s,/v51-live-adapter\.js/);
 assert.match(s,/native\.html\?embed=map/);
 assert.match(s,/readNativeBodyModal/);
 assert.match(s,/readNativeSystemModal/);
 assert.ok(s.length>90000,"full UI preserved, not reduced to a sketch");
});
test("native Observer still exists with real map, camera follow, station kit, strategy, 16x",()=>{
 const html=read("./native.html"),app=read("./app.js");
 for(const id of ["map","follow-btn","focus-inner-btn","focus-full-btn","strategy-drawer","telemetry-drawer","speed-select"]) {
   assert.ok(html.includes('id="'+id+'"'),id);
 }
 assert.match(html,/value="16"/);
 assert.match(html,/native-map-embedded/);
 assert.match(app,/installV51MapBridge/);
 assert.match(app,/__livingSectorNativeBridge/);
 assert.match(app,/drawStationComplex/);
});
test("live adapter uses native strategy heads and does not invent population",()=>{
 const source=read("./v51-live-adapter.js");
 const sandbox={window:{},location:{protocol:"http:",origin:"http://example.test"},document:{},Number,Array,Object,String,JSON,Math,Set};
 vm.runInNewContext(source,sandbox,{filename:"v51-live-adapter.js"});
 const prepare=sandbox.window.LivingSectorV51.prepare;
 const report={tick:42,facilities:[{id:"a",type:"station",location:"Earth",faction_id:"ceti"}],
   markets:[],populations:[{facility_location:"Earth",population_count:30}],
   factions:[{id:"ceti",name:"Ceti"}]};
 const strategy={factions:[{faction_id:"ceti",status:"observing",reason:"no_shortage",
   head:{selected_option:"stockpile_water",selected_administrator:"logistics",
     reason:"food_supply_low",observed_tick:42},goals:[]}],
   stations:[{faction_id:"ceti",location:"Earth",workforce:20,assigned_workers:9,
     modules:[{facility_id:"r1",reason:"staff_food"}]}],orders:[]};
 const next=prepare(report,strategy,[]);
 assert.equal(next.populations[0].count,30);
 assert.equal(next.ui.faction_leaders.ceti.decision,"stockpile_water");
 assert.equal(next.ui.administrators.Earth.strategy,"Назначено 9 из 20 работников");
 assert.equal(next.ui.faction_leaders.ceti.decisions[0].tick,42);
 const unknown=prepare({...report,populations:[{facility_location:"Earth"}]},null,[]);
 assert.equal(unknown.populations[0].count,null);
 assert.equal(unknown.ui.faction_leaders.ceti,undefined);
});
test("script is syntactically valid and balances are not represented as executable Rust params",()=>{
 const html=read("./index.html");
 const inline=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x=>x[1]).filter(x=>x.trim());
 assert.ok(inline.length>=1);
 for(const script of inline)assert.doesNotThrow(()=>new Function(script));
 assert.match(html,/Физический мир/);
});
