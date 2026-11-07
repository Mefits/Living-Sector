import test from "node:test";
import assert from "node:assert/strict";
import {telemetrySnapshot} from "./telemetry-model.js";
const sample={tick:10,systems:[{name:"Sol"}],factions:[{id:"a",treasury:140},{id:"b",treasury:60}],
  facilities:[{id:"fa",location:"earth",faction_id:"a"},{id:"fb",location:"pirate",faction_id:"b"}],
  markets:[{facility_location:"earth",supply:{food:80,water:0},demand:{food:10},shortage_ticks:{water:4}},
    {facility_location:"pirate",supply:{food:15},demand:{food:3}}],
  populations:[{faction_id:"a",population_count:50},{faction_id:"b",population_count:24}],
  ships:[{faction_id:"a"},{faction_id:"b"}]};
test("read-only global aggregate keeps zeros and real shortages",()=>{
 const x=telemetrySnapshot(sample);
 assert.equal(x.population,74);assert.equal(x.totals.food,95);assert.equal(x.totals.water,0);
 assert.equal(x.shortages.length,1);assert.equal(x.cash,200);assert.equal(x.ships.length,2);
});
test("faction scope isolates stations and market stocks",()=>{
 const x=telemetrySnapshot(sample,"a");
 assert.equal(x.population,50);assert.equal(x.totals.food,80);assert.equal(x.markets.length,1);
 assert.equal(x.ships.length,1);assert.equal(x.cash,140);
});
test("missing metrics stay unknown instead of fabricated",()=>{
 const x=telemetrySnapshot({facilities:[{faction_id:"a",location:"port"}],markets:[{facility_location:"port",demand:{food:5}}]},"a");
 assert.equal(x.totals.food,null);assert.equal(x.cash,null);assert.equal(x.population,0);
});
