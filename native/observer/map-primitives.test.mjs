import assert from "node:assert/strict";
import test from "node:test";
import {inCanvas,bodyColor,orbitScreenRadii,backdropSpeck} from "./map-primitives.js";

test("viewport selection boundary and padding are unchanged",()=>{
  assert.equal(inCanvas({x:-15,y:10},100,80),true);
  assert.equal(inCanvas({x:-15.01,y:10},100,80),false);
  assert.equal(inCanvas({x:115,y:95},100,80),true);
  assert.equal(inCanvas({x:116,y:20},100,80),false);
  assert.equal(inCanvas({x:0,y:0},100,80,0),true);
});

test("planet color catalog gives original visible tints",()=>{
  assert.equal(bodyColor({type:"moon",biome:"terrestrial"}),"#a8b5c9");
  assert.equal(bodyColor({type:"belt",biome:"desert"}),"#cba16c");
  assert.equal(bodyColor({type:"planet",biome:"terrestrial"}),"#4b9cc4");
  assert.equal(bodyColor({type:"planet",biome:"molten"}),"#bd8066");
  assert.equal(bodyColor({type:"planet",biome:"gas_giant"}),"#c4ae85");
  assert.equal(bodyColor({type:"planet"}),"#8eb0c7");
});

test("orbit pixel rings stay deduplicated, sorted, and clipped",()=>{
  const sys={x:0,y:0,bodies:[
    {x:14,y:0},{x:14,y:0},{x:45,y:0},{x:105,y:0},
    {x:12,y:0},{id:"unknown"}
  ]};
  assert.deepEqual(orbitScreenRadii(sys,1,50,50),[14,45]);
  assert.deepEqual(orbitScreenRadii({x:100,y:100,bodies:[{x:110,y:100}]},2,150,150),[20]);
  assert.deepEqual(orbitScreenRadii({x:0,y:0,bodies:[]},1,100,100),[]);
});

test("distant decorative specks exactly preserve prior deterministic formula",()=>{
  for(const i of [1,13,41,88]){
    const w=1024,h=720;
    const oldX=((Math.sin(i*127.1)*43758.5453)%1+1)%1*w;
    const oldY=((Math.sin(i*311.7)*23421.123)%1+1)%1*h;
    const oldAlpha=.06+.13*((Math.sin(i*72.8)*2654)%1+1)%1;
    const oldSize=i%13===0?1.8:1;
    assert.deepEqual(backdropSpeck(i,w,h),{
      x:oldX,y:oldY,alpha:oldAlpha,size:oldSize
    });
  }
});
