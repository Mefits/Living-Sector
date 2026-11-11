import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const world = JSON.parse(readFileSync(new URL("../priv/genesis/data/worlds/sol.json",import.meta.url),"utf8"));
const factions = JSON.parse(readFileSync(new URL("../priv/genesis/data/factions.json",import.meta.url),"utf8"));

test("Genesis starts one Sol system with two independent, persistent factions",()=>{
  assert.equal(world.system.name,"Sol");
  assert.equal(factions.length,2);
  assert.equal(world.ships.length,8);
  const factionIds=new Set(factions.map(f=>f.id));
  assert.equal(factionIds.size,2);
  assert.equal(factions.find(f=>f.id==="pirates")?.type,"outlaw");
  assert.ok(world.ships.some(s=>s.faction_id==="pirates"));
  assert.ok(world.ships.some(s=>s.faction_id==="terran-authority"));
  const shipNames=world.ships.map(s=>s.name);
  assert.equal(new Set(shipNames).size,shipNames.length);
  for (const ship of world.ships) assert.ok(factionIds.has(ship.faction_id));
});

test("Genesis has only local infrastructure, routes and markets with resolved endpoints",()=>{
  const bodyIds=new Set(world.bodies.map(b=>b.id));
  const locations=new Set(world.facilities.map(f=>f.location));
  assert.equal(world.facilities.length,14);
  assert.equal(world.markets.length,6);
  assert.equal(world.travel_routes.length,7);
  assert.ok(world.facilities.some(f=>f.type==="mining_rig"));
  assert.ok(world.facilities.some(f=>f.type==="refinery"));
  assert.ok(world.facilities.some(f=>f.type==="factory"));
  assert.ok(world.facilities.some(f=>f.type==="shipyard"));
  assert.ok(world.facilities.some(f=>f.type==="station"));
  for(const fac of world.facilities){
    assert.ok(bodyIds.has(fac.body),fac.name+" body unknown");
    assert.ok(factions.some(f=>f.id===fac.faction_id));
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

test("Genesis freighters have system-range communications and a profitable real trade lane",()=>{
  const freighters=world.ships.filter(s=>s.class==="freighter");
  assert.ok(freighters.length>=2);
  for(const ship of freighters){
    assert.equal(ship.fitting.comms,"comms_t2",
      ship.name+" needs both local market prices to form an autonomous trade route");
    assert.ok(ship.credits>=10000);
  }
  const courier=world.ships.find(s=>s.class==="courier");
  assert.ok(courier);
  assert.equal(courier.fitting?.comms??"comms_t1","comms_t1",
    "Genesis keeps a meaningful progression path for the courier");
  const earth=world.markets.find(m=>m.facility_id==="earth-station");
  const belt=world.markets.find(m=>m.facility_id==="belt-outpost");
  assert.ok(earth&&belt);
  assert.ok(earth.prices.food<belt.prices.food,
    "Earth can supply actual provisions to the belt");
  assert.ok(belt.prices.ore<earth.prices.ore,
    "Belt has an attractive ore delivery to Earth");
  assert.ok(earth.supply.food>=50);
  assert.ok(belt.supply.ore>=50);
  assert.ok(world.travel_routes.some(r=>
    (r.from==="earth-station"&&r.to==="belt-outpost") ||
    (r.from==="belt-outpost"&&r.to==="earth-station")));
});

test("Genesis runs the original shared simulation core with finite ships",()=>{
  const tuning=JSON.parse(readFileSync(new URL("../priv/genesis/data/tuning.json",import.meta.url),"utf8"));
  assert.equal(tuning.auto_replace_retired_ships,false,
    "ship losses must not be silently replaced in the finite economy");
  assert.equal(tuning.regenerate_body_resources,false,
    "depleted mineral bodies must not refill from hidden timed regeneration");
  const nativeEntry=readFileSync(new URL("../crates/sim_server/src/bin/genesis_server.rs",import.meta.url),"utf8");
  assert.match(nativeEntry,/sim_server::runtime::run\(\)/,
    "Genesis must reuse the original server/AI/economy, not its own simulation");
});

test("outlaw economy is self-contained and shares the original market types",()=>{
  const facs=world.facilities.filter(f=>f.faction_id==="pirates");
  assert.ok(facs.some(f=>f.location==="pirate-outpost"&&f.type==="station"));
  assert.ok(facs.some(f=>f.type==="mining_rig"&&f.body==="callisto"));
  assert.ok(facs.some(f=>f.type==="refinery"));
  assert.ok(facs.some(f=>f.type==="farm"));
  assert.ok(facs.some(f=>f.type==="factory"));
  assert.ok(facs.some(f=>f.type==="shipyard"));
  for(const loc of ["pirate-outpost","jupiter-gas-field","callisto-mine","pirate-wreckage"])
    assert.ok(world.markets.some(m=>m.facility_id===loc),`missing independent market ${loc}`);
});

test("finite wreckage near Jupiter has a slow salvage facility and no fiat outputs",()=>{
  const body=world.bodies.find(b=>b.id==="jupiter-wreckage");
  const jupiter=world.bodies.find(b=>b.id==="jupiter");
  assert.ok(body&&jupiter);
  assert.ok(Math.abs(body.orbit_radius-jupiter.orbit_radius)<0.15);
  assert.ok(Math.abs(body.current_angle-jupiter.current_angle)<5);
  for(const c of ["ore","ice","gas","metals"])assert.ok(body.resources[c]>0);
  const salvage=world.facilities.find(f=>f.type==="salvage_field");
  assert.ok(salvage);
  assert.equal(salvage.body,body.id);
  assert.equal(salvage.faction_id,"pirates");
  const market=world.markets.find(m=>m.facility_id===salvage.location);
  assert.ok(market);
  assert.equal(market.supply.ore,0);
  assert.equal(market.production?.ore,undefined);
  assert.equal(market.production?.metals,undefined);
  assert.ok(world.travel_routes.some(r=>r.from==="pirate-outpost"&&r.to===salvage.location));
});
