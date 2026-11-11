import test from "node:test";
import assert from "node:assert/strict";
import {visualStationTier,stationSockets,stationReveal,stationScale,drawStationComplex} from "./station-kit.js";
test("four / five / six distinct sockets",()=>{
  for(const [tier,expected] of [["t1",4],["t2",5],["t3",6]]){
    const slots=stationSockets(tier,1);
    assert.equal(slots.length,expected);
    assert.equal(new Set(slots.map(s=>s.x.toFixed(3)+":"+s.y.toFixed(3))).size,expected);
  }
});
test("station tier is a visual choice from existing facilities, not an ECS upgrade",()=>{
  const core={type:"station"},mod={type:"factory"};
  assert.equal(visualStationTier([core,mod]),"t1");
  assert.equal(visualStationTier([core,mod,mod,mod]),"t1");
  assert.equal(visualStationTier([core,mod,mod,mod,mod]),"t1");
  assert.equal(visualStationTier([core,mod,mod,mod,mod,mod]),"t2");
  assert.equal(visualStationTier([core,mod,mod,mod,mod,mod,mod]),"t3");
});
test("smooth detail reveal; zoom does not shrink hit targets",()=>{
  assert.equal(stationReveal(.5),0);assert.equal(stationReveal(7),1);
  assert(stationReveal(2.5)>0&&stationReveal(2.5)<1);
  for(let z=.7;z<12;z+=.35)assert(stationScale(z+.1)>=stationScale(z));
});
test("click targets correspond only to visible populated sockets",()=>{
  const nil=()=>{};
  const ctx={save:nil,restore:nil,translate:nil,scale:nil,beginPath:nil,moveTo:nil,lineTo:nil,
    closePath:nil,fill:nil,stroke:nil,arc:nil,setLineDash:nil,strokeRect:nil,fillText:nil,roundRect:nil};
  const modules=[{id:"f1",type:"factory"},{id:"f2",type:"cargo_warehouse"}];
  const far=drawStationComplex(ctx,{x:100,y:100,tier:"t1",zoom:1,modules,showModules:true});
  assert.equal(far.moduleTargets.length,0);
  const near=drawStationComplex(ctx,{x:100,y:100,tier:"t1",zoom:7,modules,showModules:true});
  assert.deepEqual(near.moduleTargets.map(x=>x.entity.id),["f1","f2"]);
  assert(near.moduleTargets.every(x=>x.r>=13));
});
