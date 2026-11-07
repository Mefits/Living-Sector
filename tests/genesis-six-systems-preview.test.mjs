import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const names = ["sol", "alpha_centauri", "tau_ceti", "vega", "barnard", "lalande"];
const worlds = names.map(name => JSON.parse(readFileSync(
  new URL(`../priv/genesis/data/worlds/${name}.json`, import.meta.url), "utf8")));
const factions = JSON.parse(readFileSync(new URL(
  "../priv/genesis/data/factions.json", import.meta.url), "utf8"));
const allFacilities = worlds.flatMap(w => w.facilities);
const allMarkets = worlds.flatMap(w => w.markets);
const allShips = worlds.flatMap(w => w.ships);
const allPopulations = worlds.flatMap(w => w.populations);

test("six original star systems are visible with original bodies, but not legacy fleet/economy", () => {
  assert.equal(worlds.length, 6);
  assert.equal(new Set(worlds.map(w => w.system.name)).size, 6);
  assert.equal(worlds.reduce((sum,w) => sum + w.bodies.length, 0), 36);
  assert.equal(new Set(worlds.flatMap(w => w.bodies.map(b => b.id))).size, 36);
  assert.ok(worlds.every(w => w.system.universe_offset.length === 2));
  for(const w of worlds.slice(2)) {
    assert.equal(w.facilities.length, 0);
    assert.equal(w.ships.length, 0);
    assert.equal(w.markets.length, 0);
  }
});

test("three independent starter economies, one station, three provisional modules (including native farm) and one placeholder ship each", () => {
  assert.equal(factions.length, 3);
  assert.equal(factions.filter(f => f.type === "outlaw").length, 1);
  assert.equal(allFacilities.length, 12);
  assert.equal(allMarkets.length, 3);
  assert.equal(allShips.length, 3);
  assert.equal(allPopulations.length, 3);
  const bodyIds = new Set(worlds.flatMap(w => w.bodies.map(b => b.id)));
  for(const faction of factions) {
    const fs = allFacilities.filter(f => f.faction_id === faction.id);
    assert.equal(fs.length, 4, faction.id);
    assert.deepEqual(fs.map(f => f.type), ["station","mining_rig","refinery","farm"]);
    assert.ok(fs.every(f => f.location === fs[0].location), faction.id);
    assert.ok(fs.every(f => bodyIds.has(f.body)));
    const market = allMarkets.find(m => m.facility_id === fs[0].location);
    assert.ok(market, faction.id);
    assert.equal(market.supply.food, 1000);
    assert.equal(market.supply.water, 1000);
    assert.ok(Object.keys(market.supply).every(x => x === "food" || x === "water"));
    const ship = allShips.filter(s => s.faction_id === faction.id);
    assert.equal(ship.length, 1);
    assert.equal(ship[0].class, "freighter");
    assert.equal(ship[0].location, fs[0].location);
    const pop = allPopulations.filter(p => p.faction_id === faction.id);
    assert.equal(pop.length, 1);
    assert.equal(pop[0].population_count, 50);
    assert.equal(pop[0].facility_id, fs[0].location);
    assert.equal(market.production.food, undefined, 'food must be grown by a paid native farm, not by legacy market flow');
    assert.equal(market.consumption.food, undefined, 'only paid household purchases may consume food');
  }
});

test("body-specific extraction gives Earth ore but no gas; Jupiter gas but no ore", () => {
  const sol = worlds[0];
  const earth = sol.bodies.find(b => b.id === "earth");
  const jupiter = sol.bodies.find(b => b.id === "jupiter");
  assert.ok(earth.resources.ore > 0);
  assert.equal(earth.resources.gas, undefined);
  assert.ok(jupiter.resources.gas > 0);
  assert.equal(jupiter.resources.ore, undefined);
  assert.ok(sol.bodies.some(b => b.type === "belt" || b.type === "asteroid"));
});

test("no cross-system trade infrastructure or preseeded external business", () => {
  assert.ok(worlds.every(w => w.travel_routes.length === 0));
  assert.ok(allFacilities.every(f => f.type !== "shipyard" && f.type !== "gate"));
  assert.ok(worlds.slice(1).every(w => w.system.name !== "Sol"));
});


test("survival farms use the native water-to-food recipe and occupy the third preview module socket", () => {
  const recipeSource = readFileSync(new URL("../crates/sim_core/src/economy/recipes.rs",import.meta.url),"utf8");
  assert.match(recipeSource, /id: "grow_food",[\s\S]*?facility_type: "farm",[\s\S]*?inputs: &\[\(Commodity::Water, 3\)\],[\s\S]*?outputs: &\[\(Commodity::Food, 10\)\]/);
  const restockSource = readFileSync(new URL("../crates/sim_core/src/agents/facility/mod.rs",import.meta.url),"utf8");
  const list = restockSource.match(/pub const RESTOCK_COMMODITIES: &\[Commodity\] = &\[([\s\S]*?)\];/);
  assert.ok(list);
  assert.doesNotMatch(list[1], /Commodity::(?:Food|Water)/, "household necessities must remain for market buyers");
  assert.match(list[1], /Commodity::Fuel/);
  assert.match(list[1], /Commodity::Tools/);
});
