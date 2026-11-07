import test from "node:test";
import assert from "node:assert/strict";
import {parseSnapshot} from "./strategy-model.js";
const base = {schema_version:1,snapshot_tick:50,mode:"execute",factions:[{faction_id:"terran-authority"}]};
test("A1/A2 collections survive parsing",()=>{
  const s=parseSnapshot({...base,stations:[{faction_id:"terran-authority",location:"earth-station",assigned_workers:12}],
    orders:[{faction_id:"terran-authority",order_id:"station:contract:1",state:"assigned"}]});
  assert.equal(s.stations[0].assigned_workers,12);
  assert.equal(s.orders[0].state,"assigned");
});
test("pre-A1 API remains compatible",()=>{
  const s=parseSnapshot(base);
  assert.deepEqual(s.stations,[]);
  assert.deepEqual(s.orders,[]);
});
