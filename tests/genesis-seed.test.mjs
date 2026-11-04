import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const readSeed = name => JSON.parse(readFileSync(new URL("../priv/genesis/data/" + name, import.meta.url), "utf8"));
const world = readSeed("worlds/sol.json");
const factions = readSeed("factions.json");

test("Genesis starts with one faction, one freighter and two working facilities", () => {
  assert.equal(world.system.name, "Sol");
  assert.deepEqual(world.bodies.map(body => body.id), ["earth", "belt"]);
  assert.equal(readSeed("tuning.json").genesis_ore_loop, true);
  assert.equal(factions.length, 1);
  assert.equal(world.ships.length, 1);
  const [ship] = world.ships;
  assert.equal(ship.faction_id, factions[0].id);
  assert.equal(ship.class, "freighter");
  assert.equal(ship.location, "belt-outpost");
  assert.deepEqual(Object.values(ship.fitting).filter(Boolean), ["comms_t2"]);
  assert.deepEqual(world.facilities.map(f => f.type).sort(), ["mining_rig", "station"]);
  for (const facility of world.facilities) {
    assert.equal(facility.faction_id, factions[0].id);
    assert.ok(world.bodies.some(body => body.id === facility.body));
    assert.deepEqual(facility.services, ["market", "refuel"]);
    assert.deepEqual(Object.keys(facility.reserves), ["fuel"]);
  }
  assert.equal(world.travel_routes.length, 1);
  assert.equal(world.travel_routes[0].from, "earth-station");
  assert.equal(world.travel_routes[0].to, "belt-outpost");
  assert.deepEqual(world.populations, []);
});

test("ore starts at zero and can come only from the belt's mining rig", () => {
  assert.deepEqual(world.bodies.flatMap(body => Object.keys(body.resources)), ["ore"]);
  const rig = world.facilities.find(f => f.type === "mining_rig");
  assert.ok(world.bodies.find(body => body.id === rig.body).resources.ore > 0);
  assert.equal(world.markets.length, 2);
  for (const market of world.markets) {
    assert.deepEqual(market.supply, { ore: 0 });
    assert.deepEqual(Object.keys(market.prices), ["ore"]);
    assert.deepEqual(market.production, {});
    assert.deepEqual(market.consumption, {});
    assert.ok(world.facilities.some(f => f.location === market.facility_id));
  }
  const earth = world.markets.find(m => m.facility_id === "earth-station");
  const belt = world.markets.find(m => m.facility_id === rig.location);
  assert.ok(earth.prices.ore > belt.prices.ore);
  assert.ok(earth.demand.ore > 0);
});
