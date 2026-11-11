import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {stationEconomy} from "./model.js";

// The three actual initial station hubs in Genesis seed data.
// Seeds use facility_id; /api/report renames it to facility_location.
function seed(name) {
  const world=JSON.parse(readFileSync(new URL("../priv/genesis/data/worlds/"+name+".json",import.meta.url),"utf8"));
  return {facilities:world.facilities,markets:world.markets.map(m=>({...m,facility_location:m.facility_id}))};
}
for(const [world,location,stationId,expectedCount] of [
  ["sol","earth-station","facility-earth-station",4],
  ["sol","pirate-outpost","facility-pirate-station",4],
  ["alpha_centauri","alpha-station","facility-alpha-station",4]
]) {
  test("seed station: "+location,()=>{
    const economy=stationEconomy(seed(world),location);
    assert.ok(economy,"real station must be found");
    assert.equal(economy.station.id,stationId);
    assert.equal(economy.members.length,expectedCount);
    assert.ok(economy.members.every(f=>f.location===location),"never mix locations");
    assert.equal(economy.market.facility_location,location);
    assert.ok(economy.goods.some(g=>g.id==="food"));
    assert.ok(economy.goods.some(g=>g.id==="water"));
    assert.ok(economy.goods.some(g=>g.id==="fuel"));
  });
}
test("shortages are only the explicit server shortage_ticks, not low inferred stock",()=>{
  const report={facilities:[{id:"station",type:"station",location:"hub",credits:0}],
    markets:[{facility_location:"hub",supply:{food:0},demand:{food:10,fuel:4},
      shortage_ticks:{fuel:9,food:0},prices:{food:17}}]};
  const economy=stationEconomy(report,"hub");
  assert.equal(economy.station.credits,0);
  assert.deepEqual(economy.shortages.map(g=>g.id),["fuel"]);
  assert.equal(economy.goods.find(g=>g.id==="food").stock,0);
  assert.equal(economy.goods.find(g=>g.id==="fuel").stock,0);
  assert.equal(economy.goods.find(g=>g.id==="fuel").demand,4);
});
test("missing station, market or inventory is not turned into invented data",()=>{
  assert.equal(stationEconomy({}, "hub"),null);
  assert.equal(stationEconomy({facilities:[{type:"farm",location:"hub"}]},"hub"),null);
  const economy=stationEconomy({facilities:[{type:"station",location:"hub"}],
    markets:[{facility_location:"hub",demand:{food:10}}]},"hub");
  assert.equal(economy.goods.find(g=>g.id==="food").stock,null);
  assert.deepEqual(economy.shortages,[]);
  assert.equal(economy.station.credits,undefined);
});
