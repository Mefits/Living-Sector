// Flat, dynamic station composition for the Living Sector Observer.
// Pure read-only view: T1/T2/T3 are inferred display layouts, not ECS upgrades.
export const STATION_TIERS=Object.freeze({
 t1:{label:"Аванпост",sides:4,slots:4,rotation:-Math.PI/4},
 t2:{label:"Станция",sides:5,slots:5,rotation:-Math.PI/2},
 t3:{label:"Орбитальный комплекс",sides:6,slots:6,rotation:-Math.PI/6}
});
const catalog={
 station:["Управление","#967da9","command"],shipyard:["Верфь","#a99ab6","shipyard"],
 repair_dock:["Ремонт","#a99ab6","repair"],mining_rig:["Добыча","#bd9669","mine"],
 gas_harvester:["Газ","#86aaa5","gas"],salvage_field:["Обломки","#bd9669","mine"],
 refinery:["Переработка","#8ca1b3","factory"],smelter:["Плавильня","#b6967d","factory"],
 factory:["Производство","#8ca1b3","factory"],farm:["Ферма","#83ac91","farm"],
 cargo_warehouse:["Склад","#bca483","storage"],warehouse:["Склад","#bca483","storage"],
 fuel_depot:["Топливо","#bea36e","fuel"],solar_power_station:["Энергия","#acb67b","power"],
 observation_station:["Связь","#a48dbb","signal"],patrol_base:["Оборона","#b19ba9","shield"],
 gate:["Врата","#8caac6","signal"],jump_gate:["Врата","#8caac6","signal"]
};
export const STATION_MODULES=Object.freeze(Object.fromEntries(Object.entries(catalog).map(
 ([k,[label,color,icon]])=>[k,Object.freeze({label,color,icon})])));
const DEFAULT_MODULE={label:"Модуль",color:"#99a8b4",icon:"storage"};
export function moduleVisual(type){return STATION_MODULES[type]||DEFAULT_MODULE;}
export function visualStationTier(members,sites=[]){
 const count=(members||[]).filter(x=>x.type!=="station").length+(sites||[]).length;
 return count>5?"t3":count>3?"t2":"t1";
}
const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
export function stationReveal(zoom){
 const t=clamp((zoom-1.55)/2.15,0,1);return t*t*(3-2*t);
}
export function stationScale(zoom){return clamp(.89+Math.log2(1+Math.max(0,zoom))*.31,.94,2.25);}
export function stationSockets(tier,scale=1){
 const t=STATION_TIERS[tier]||STATION_TIERS.t1,orbit=43*scale;
 return Array.from({length:t.slots},(_,i)=>{
  const a=-Math.PI/2+2*Math.PI*i/t.slots;
  return{x:Math.cos(a)*orbit,y:Math.sin(a)*orbit,angle:a,index:i};
 });
}
function polygon(ctx,n,r,rot){
 ctx.beginPath();for(let i=0;i<n;i++){
  const a=rot+i*2*Math.PI/n,x=Math.cos(a)*r,y=Math.sin(a)*r;
  if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);
 }ctx.closePath();
}
function drawSymbol(ctx,type){
 ctx.strokeStyle="#e0eaf0";ctx.fillStyle="#e0eaf0";ctx.lineWidth=1.75;
 ctx.lineCap="round";ctx.lineJoin="round";
 const line=(...a)=>{ctx.beginPath();ctx.moveTo(a[0],a[1]);
  for(let i=2;i<a.length;i+=2)ctx.lineTo(a[i],a[i+1]);ctx.stroke();};
 const rect=(x,y,w,h)=>ctx.strokeRect(x,y,w,h);
 const circle=(x,y,r)=>{ctx.beginPath();ctx.arc(x,y,r,0,2*Math.PI);ctx.stroke();};
 switch(type){
 case"factory":line(-7,6,-7,0,-2,3,-2,0,3,3,3,-6,7,-6,7,6,-7,6);break;
 case"storage":rect(-6,-5,12,10);line(-6,-1,0,3,6,-1);break;
 case"shipyard":line(-7,5,-7,-5,7,-5,7,5);line(-5,5,0,1,5,5);break;
 case"repair":line(-7,6,0,-1);line(1,-4,5,-8,7,-6,4,-2);break;
 case"mine":line(-6,6,1,-5,4,-3,-3,8);line(-2,-3,2,-7,7,-5);break;
 case"farm":line(0,6,0,-6);line(0,-2,-5,-6);line(0,3,5,-2);break;
 case"gas":circle(-4,0,3);circle(4,0,3);line(-4,-6,-4,-3,4,-3,4,-6);break;
 case"signal":line(0,6,0,-5);circle(0,-5,2);break;
 case"power":line(2,-8,-4,1,1,1,-2,8,6,-2,1,-2,2,-8);break;
 case"fuel":ctx.beginPath();ctx.moveTo(0,-7);ctx.bezierCurveTo(-2,-3,-6,1,-4,5);
  ctx.bezierCurveTo(-2,9,3,9,5,5);ctx.bezierCurveTo(7,1,2,-4,0,-7);ctx.stroke();break;
 case"shield":line(0,-8,7,-5,6,4,0,8,-6,4,-7,-5,0,-8);break;
 case"command":circle(0,0,3);line(0,-8,0,-5);line(0,5,0,8);line(-8,0,-5,0);line(5,0,8,0);break;
 default:rect(-5,-5,10,10);
 }
}
export function drawStationComplex(ctx,p){
 const tier=STATION_TIERS[p.tier]||STATION_TIERS.t1,sc=stationScale(p.zoom);
 const reveal=p.showModules?(p.selected?Math.max(.55,stationReveal(p.zoom)):stationReveal(p.zoom)):0;
 const centerR=16*sc,modules=p.modules||[],sockets=stationSockets(p.tier,sc);
 ctx.save();ctx.translate(p.x,p.y);ctx.lineJoin="round";ctx.lineCap="round";
 if(reveal>.005){
  ctx.globalAlpha=reveal;ctx.lineWidth=2.8*sc;ctx.strokeStyle="#637e90";
  for(const s of sockets){
   const from=centerR+2*sc;ctx.beginPath();
   ctx.moveTo(Math.cos(s.angle)*from,Math.sin(s.angle)*from);
   ctx.lineTo(s.x-Math.cos(s.angle)*11*sc,s.y-Math.sin(s.angle)*11*sc);ctx.stroke();
  }
 }
 ctx.globalAlpha=1;ctx.fillStyle="#142b3b";
 ctx.strokeStyle=p.selected?"#c5e7e4":(p.tint||"#80b8d8");
 ctx.lineWidth=(p.selected?2.9:2.25)*sc;
 polygon(ctx,tier.sides,centerR,tier.rotation);ctx.fill();ctx.stroke();
 ctx.strokeStyle="#7591a4";ctx.lineWidth=.95*sc;
 polygon(ctx,tier.sides,centerR*.72,tier.rotation);ctx.stroke();
 ctx.fillStyle=p.tint||"#80b8d8";
 ctx.beginPath();ctx.arc(0,0,2.7*sc,0,Math.PI*2);ctx.fill();
 const targets=[];
 if(reveal>.005){
  for(let i=0;i<sockets.length;i++){
   const slot=sockets[i],entry=modules[i],r=12.5*sc;
   ctx.save();ctx.globalAlpha=reveal;ctx.translate(slot.x,slot.y);
   if(entry){
    const meta=moduleVisual(entry.type||entry.facility_type),site=entry.__site===true;
    ctx.fillStyle=site?"#202630":"#1d303a";
    ctx.strokeStyle=entry.__selected?"#e9faf4":site?"#d0a76a":meta.color;
    ctx.lineWidth=(entry.__selected?3:2.15)*sc;
    if(site)ctx.setLineDash([3*sc,2*sc]);
    if(["factory","command","signal","shield"].includes(meta.icon)){
     polygon(ctx,6,r,-Math.PI/6);
    }else if(["storage","repair","shipyard","fuel"].includes(meta.icon)){
     ctx.beginPath();ctx.roundRect(-r,-r,2*r,2*r,3.1*sc);
    }else{
     ctx.beginPath();ctx.arc(0,0,r,0,Math.PI*2);
    }
    ctx.fill();ctx.stroke();ctx.setLineDash([]);
    ctx.save();ctx.scale(sc*.91,sc*.91);
    drawSymbol(ctx,site?"repair":meta.icon);
    ctx.restore();
    if(site){const progress=clamp(Number(entry.progress)||0,0,1);
     ctx.strokeStyle="#dbb57e";ctx.lineWidth=2.6*sc;
     ctx.beginPath();ctx.arc(0,0,r+3*sc,-Math.PI/2,-Math.PI/2+progress*Math.PI*2);ctx.stroke();
    }
    if(entry.__selected){ctx.strokeStyle="#d6f6ef";ctx.lineWidth=1;
     ctx.beginPath();ctx.arc(0,0,r+4*sc,0,Math.PI*2);ctx.stroke();}
    if(reveal>.17)targets.push({x:p.x+slot.x,y:p.y+slot.y,r:Math.max(13,r+3),entity:entry});
   }else{
    ctx.strokeStyle="#627381";ctx.lineWidth=sc;
    ctx.setLineDash([2.5*sc,3*sc]);ctx.beginPath();
    ctx.arc(0,0,r*.72,0,Math.PI*2);ctx.stroke();ctx.setLineDash([]);
   }
   ctx.restore();
  }
 }
 if(modules.length>sockets.length){
  ctx.save();ctx.fillStyle="#d6d9ce";ctx.textAlign="center";
  ctx.font=(10*sc)+"px Segoe UI";
  ctx.fillText("+"+(modules.length-sockets.length),0,centerR+13*sc);
  ctx.restore();
 }
 ctx.restore();
 return{radius:Math.max(centerR,reveal>.005?56*sc:0),
  moduleTargets:targets,reveal,scale:sc};
}
