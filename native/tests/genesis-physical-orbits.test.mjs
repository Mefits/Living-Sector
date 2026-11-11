import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const worldNames=["sol","alpha_centauri","tau_ceti","vega","barnard","lalande"];
const worlds=worldNames.map(name=>JSON.parse(readFileSync(
  new URL("../priv/genesis/data/worlds/"+name+".json",import.meta.url),"utf8")));

test("all 6 systems preserve bodies with at least 2x physical orbital radii",()=>{
  const knownMinimums={
    sol:{mercury:0.8,venus:1.4,earth:2,mars:3.04,jupiter:10.4,saturn:19,kuiper:24},
    alpha_centauri:{proxima:1.6,haven:3.6,refuge:5},
    tau_ceti:{forge:1.2,anvil:2.4,frostheim:7},
    vega:{veritas:1.6,orison:3},
    barnard:{yeoman:1.4,"outpost-gamma":5.2},
    lalande:{kinship:1.8,"lalande-outer":6}
  };
  for(let i=0;i<worlds.length;i++){
    const world=worlds[i],expected=knownMinimums[worldNames[i]];
    for(const [bodyId,minimum] of Object.entries(expected)){
      const body=world.bodies.find(b=>b.id===bodyId);
      assert.ok(body,"missing body "+bodyId);
      assert.ok(body.orbit_radius>=minimum-1e-7,bodyId+" should use doubled physical radius");
    }
  }
});

test("interstellar offsets scale with planetary world size",()=>{
  const expected=[[0,0],[40,10],[80,-20],[120,-60],[110,-110],[160,-90]];
  assert.deepEqual(worlds.map(w=>w.system.universe_offset),expected);
});

test("orbit is persistent shared physical state and ships chase live station locations",()=>{
  const core=readFileSync(new URL("../crates/sim_core/src/agents/facility/components.rs",import.meta.url),"utf8");
  const engine=readFileSync(new URL("../crates/sim_server/src/engine.rs",import.meta.url),"utf8");
  const snapshot=readFileSync(new URL("../crates/sim_server/src/snapshot.rs",import.meta.url),"utf8");
  const ships=readFileSync(new URL("../crates/sim_core/src/agents/ship/mod.rs",import.meta.url),"utf8");
  const persistence=readFileSync(new URL("../crates/sim_db/src/persistence.rs",import.meta.url),"utf8");
  const migration=readFileSync(new URL("../crates/sim_db/migrations/018_facility_orbits.sql",import.meta.url),"utf8");
  assert.match(core,/pub const FACILITY_ORBIT_PERIOD: f32 = 8_000\.0/);
  assert.match(core,/pub struct FacilityOrbit/);
  assert.match(engine,/tick_facility_orbits\(&mut world, tick_scale\)/);
  assert.match(snapshot,/facility_orbit_position\(center, angle\)/);
  assert.match(ships,/facility_orbit_position\(center,\*angle\)/);
  assert.match(persistence,/DbWrite::FacilityOrbit/);
  assert.match(migration,/ALTER TABLE facilities ADD COLUMN orbit_angle/);
});
