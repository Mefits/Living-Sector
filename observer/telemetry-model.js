// Observer V5.1-inspired live telemetry. Read-only: never invent missing data.
export const TELEMETRY_NAMES = Object.freeze({
  food:"Еда",water:"Вода",fuel:"Топливо",ice:"Лёд",ore:"Руда",metals:"Металлы",
  gas:"Газ",polymers:"Полимеры",components:"Компоненты",electronics:"Электроника",
  tools:"Инструменты",medical:"Медикаменты",luxury:"Предметы роскоши"
});
export const telemetryList = v => Array.isArray(v) ? v : [];
export const telemetryNumber = v => typeof v === "number" && Number.isFinite(v) ? v : null;
export function telemetrySnapshot(report, scope="all") {
  const allFacilities=telemetryList(report?.facilities);
  const factions=telemetryList(report?.factions);
  const allMarkets=telemetryList(report?.markets);
  const facilities=allFacilities.filter(f=>scope==="all"||f.faction_id===scope);
  const locations=new Set(facilities.map(f=>f.location??f.facility_location).filter(Boolean));
  const markets=allMarkets.filter(m=>scope==="all"||locations.has(m.facility_location??m.location));
  const ships=telemetryList(report?.ships).filter(s=>scope==="all"||s.faction_id===scope);
  const pops=telemetryList(report?.populations).filter(p=>scope==="all"||p.faction_id===scope);
  const sites=telemetryList(report?.construction_sites).filter(s=>scope==="all"||s.faction_id===scope||locations.has(s.location??s.facility_location));
  const goods=new Map();
  const bump=(id,field,value)=>{const n=telemetryNumber(value);if(n===null)return;const item=goods.get(id)||{id,stock:0,demand:0,shortage_ticks:0,observed_stock:false,observed_demand:false};if(field==="shortage_ticks")item[field]=Math.max(item[field],n);else item[field]+=n;if(field==="stock")item.observed_stock=true;if(field==="demand")item.observed_demand=true;goods.set(id,item);};
  for(const market of markets) {
    for(const [id,n] of Object.entries(market.supply||{}))bump(id,"stock",n);
    for(const [id,n] of Object.entries(market.demand||{}))bump(id,"demand",n);
    for(const [id,n] of Object.entries(market.shortage_ticks||{}))bump(id,"shortage_ticks",n);
  }
  const stock=[...goods.values()].sort((a,b)=>a.id.localeCompare(b.id));
  const population=pops.reduce((sum,p)=>sum+(telemetryNumber(p.population_count)||0),0);
  const factionCash=factions.filter(f=>scope==="all"||f.id===scope).reduce((s,f)=>s+(telemetryNumber(f.treasury)||0),0);
  const cashKnown=factions.some(f=>(scope==="all"||f.id===scope)&&telemetryNumber(f.treasury)!==null);
  const tick=telemetryNumber(report?.tick);
  return {scope,tick,systemCount:telemetryList(report?.systems).length,facilities,markets,ships,pops,sites,stock,population,
    factionCount:scope==="all"?factions.length:factions.filter(f=>f.id===scope).length,
    cash:cashKnown?factionCash:null,shortages:stock.filter(g=>g.shortage_ticks>0),
    factions,
    totals:Object.fromEntries(stock.map(g=>[g.id,g.observed_stock?g.stock:null]))};
}
