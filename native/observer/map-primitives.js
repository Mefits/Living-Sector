/**
 * Pure presentation primitives for the Observer map.
 *
 * No DOM, Canvas, server state, camera mutation, networking or assets.
 * Keep the existing formulas to preserve the established visual output.
 * Rendering and animation remain in app.js.
 */
import {point} from "./model.js";

export function inCanvas(p,w,h,pad=15) {
  return p.x >= -pad && p.y >= -pad && p.x <= w+pad && p.y <= h+pad;
}

export function bodyColor(body) {
  const biome=String(body.biome??"").toLowerCase();
  if(body.type==="moon" || biome==="lifeless")return "#a8b5c9";
  if(body.type==="belt" || body.type==="asteroid" || biome==="asteroid")return "#cba16c";
  if(biome==="terrestrial")return "#4b9cc4";
  if(biome==="desert" || biome==="molten")return "#bd8066";
  if(biome==="gas_giant")return "#c4ae85";
  return "#8eb0c7";
}

export function orbitScreenRadii(sys,scale,w,h) {
  return [...new Set(sys.bodies.map(body=>{
    const p=point(body);
    return p ? Math.round(Math.hypot(p.x-sys.x,p.y-sys.y)*scale) : 0;
  }).filter(r=>r>12&&r<Math.max(w,h)*2))].sort((a,b)=>a-b);
}

export function backdropSpeck(i,w,h) {
  const x=((Math.sin(i*127.1)*43758.5453)%1+1)%1*w;
  const y=((Math.sin(i*311.7)*23421.123)%1+1)%1*h;
  const alpha=.06+.13*((Math.sin(i*72.8)*2654)%1+1)%1;
  const size=i%13===0?1.8:1;
  return {x,y,alpha,size};
}
