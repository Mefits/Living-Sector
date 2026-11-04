import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const world = JSON.parse(readFileSync(new URL("../priv/genesis/data/worlds/sol.json",import.meta.url),"utf8"));
const factions = JSON.parse(readFileSync(new URL("../priv/genesis/data/factions.json",import.meta.url),"utf8"));

test("Genesis starts with one system, one faction and exactly three persistent starting ships",()=>{
  assert.equal(world.system.name,"Sol");
  assert.equal(factions.length,1);
  assert.equal(world.ships.length,3);
  const shipNames=world.ships.map(s=>s.name);
  assert.equal(new Set(shipNames).size,shipNames.length);
  for (const ship of world.ships) assert.equal(ship.faction_id,factions[0].id);
});

test("Genesis has only local infrastructure, routes and markets with resolved endpoints",()=>{
  const bodyIds=new Set(world.bodies.map(b=>b.id));
  const locations=new Set(world.facilities.map(f=>f.location));
  assert.equal(world.facilities.length,6);
  assert.equal(world.markets.length,2);
  assert.equal(world.travel_routes.length,1);
  assert.ok(world.facilities.some(f=>f.type==="mining_rig"));
  assert.ok(world.facilities.some(f=>f.type==="refinery"));
  assert.ok(world.facilities.some(f=>f.type==="factory"));
  assert.ok(world.facilities.some(f=>f.type==="shipyard"));
  assert.ok(world.facilities.some(f=>f.type==="station"));
  for(const fac of world.facilities){
    assert.ok(bodyIds.has(fac.body),fac.name+" body unknown");
    assert.equal(fac.faction_id,factions[0].id);
  }
  for(const m of world.markets)assert.ok(locations.has(m.facility_id));
  for(const ship of world.ships)assert.ok(locations.has(ship.location));
  for(const route of world.travel_routes){
    assert.ok(locations.has(route.from));
    assert.ok(locations.has(route.to));
  }
});
test("ore is produced by a real extraction rig, not by seeded market fiat",()=>{
  const belt=world.bodies.find(b=>b.id==="belt");
  const mine=world.facilities.find(f=>f.type==="mining_rig");
  assert.equal(mine.body,"belt");
  assert.ok(belt.resources.ore>0);
  assert.equal(world.markets.find(m=>m.facility_id==="earth-station").production.ore,undefined);
  assert.equal(world.markets.find(m=>m.facility_id==="belt-outpost").production.ore,undefined);
});
test("resource and commodity locations are genuinely separated",()=>{
  const earth=world.markets.find(m=>m.facility_id==="earth-station");
  const belt=world.markets.find(m=>m.facility_id==="belt-outpost");
  assert.ok(belt.supply.ore>earth.supply.ore);
  assert.ok(earth.prices.ore>belt.prices.ore);
  assert.ok(earth.demand.ore>0);
});
