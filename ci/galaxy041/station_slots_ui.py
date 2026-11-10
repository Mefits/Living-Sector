"""Galaxy 0.4.1 station visibility: correct T1 4-socket visual threshold,
and show real built/in-progress/empty sockets without pretending the
drawing is a simulated station upgrade or an enforced hard building cap.

No economy, AI, material, or worker mutation. Short Node regressions only.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/observer"
def one(path,old,new):
    src=path.read_text(encoding="utf8")
    count=src.count(old)
    if count!=1:
        raise RuntimeError(f"Galaxy 0.4.1 station UI anchor count={count}: {path} {old[:65]!r}")
    path.write_text(src.replace(old,new,1),encoding="utf8")

one(root/"station-kit.js",
    'return count>5?"t3":count>3?"t2":"t1";',
    'return count>5?"t3":count>4?"t2":"t1";')
one(root/"station-kit.test.mjs",
    '  assert.equal(visualStationTier([core,mod,mod,mod,mod]),"t2");',
    '''  assert.equal(visualStationTier([core,mod,mod,mod]),"t1");
  assert.equal(visualStationTier([core,mod,mod,mod,mod]),"t1");
  assert.equal(visualStationTier([core,mod,mod,mod,mod,mod]),"t2");''')

path=root/"priority-inspector.js"
source=path.read_text(encoding="utf8")
marker='function stationCard(parent,entity,report,index) {'
if source.count(marker)!=1:raise RuntimeError("Station inspector function not uniquely found")
addon=r'''/** Actual facilities and construction sites. These are VISUAL sockets
 * in Galaxy 0.4.1, not a native construction slot cap or auto-upgrade. */
export function stationVisualOccupancy(report,station) {
  const same=(e)=>e?.location===station?.location &&
      e?.faction_id===station?.faction_id &&
      e?.body_id===station?.body_id;
  const built=list(report?.facilities).filter(e=>same(e)&&e?.type!=="station");
  const projects=list(report?.construction_sites).filter(s=>same(s));
  const occupied=built.length+projects.length;
  const visualTier=occupied>5?"T3":occupied>4?"T2":"T1";
  const capacity=visualTier==="T3"?6:visualTier==="T2"?5:4;
  return {built,projects,visualTier,capacity,
    empty:Math.max(0,capacity-occupied),overflow:Math.max(0,occupied-capacity)};
}
'''
source=source.replace(marker,addon+marker,1)
old='''    const children=list(econ?.members).filter(f=>f?.id!==at?.id);
    if(!children.length)factories.append(node(doc,"p","priority-muted","Предприятий нет"));'''
new='''    const children=list(econ?.members).filter(f=>f?.id!==at?.id);
    const visual=stationVisualOccupancy(report,entity);
    block(factories,"Построено",nfmt(visual.built.length));
    block(factories,"Строится",nfmt(visual.projects.length));
    block(factories,"Визуальных позиций",visual.visualTier+" · "+visual.capacity);
    block(factories,"Свободно на схеме",nfmt(visual.empty));
    factories.append(node(doc,"p","priority-muted",
      "Слоты пока только отображаются; игровой предел строительства отдельно не реализован."));
    for(const site of visual.projects) {
      const progress=known(site.progress_delivered)&&known(site.progress_required)
        ?nfmt(site.progress_delivered)+" / "+nfmt(site.progress_required):"—";
      block(factories,"Строится: "+(ROLES[site.facility_type]??shown(site.facility_type)),progress);
      if(site.labor?.blocked_reason)block(factories,
        "Причина ожидания",shown(site.labor.blocked_reason));
    }
    if(!children.length)factories.append(node(doc,"p","priority-muted","Предприятий нет"));'''
if source.count(old)!=1:raise RuntimeError("Station enterprise card anchor missing")
path.write_text(source.replace(old,new,1),encoding="utf8")
test=root/"priority-inspector.test.mjs"
s=test.read_text(encoding="utf8")
old='import {shipPriority, resourceGradeEntries} from "./priority-inspector.js";'
new='import {shipPriority, resourceGradeEntries, stationVisualOccupancy} from "./priority-inspector.js";'
if s.count(old)!=1:raise RuntimeError("Inspector test import anchor missing")
s=s.replace(old,new,1)+r"""

test("Galaxy 0.4.1 visually distinguishes 3 buildings plus paid fourth project",()=>{
  const station={location:"venus-colony",body_id:"venus",faction_id:"terran-authority"};
  const report={
    facilities:[
      {type:"station",...station},
      ...["mining_rig","refinery","farm"].map(type=>({type,...station})),
      {type:"factory",location:"earth-station",faction_id:"terran-authority",body_id:"earth"}
    ],
    construction_sites:[{...station,facility_type:"factory",
      progress_delivered:400,progress_required:600,labor:{blocked_reason:"awaiting_materials"}}]
  };
  const result=stationVisualOccupancy(report,station);
  assert.equal(result.visualTier,"T1");
  assert.equal(result.capacity,4);
  assert.equal(result.built.length,3);
  assert.equal(result.projects.length,1);
  assert.equal(result.empty,0);
});
test("Galaxy 0.4.1 three built and no project really leave one visual socket",()=>{
  const station={location:"nadir-ashfall-colony",body_id:"nadir-ashfall",faction_id:"pirates"};
  const report={facilities:[{...station,type:"station"},
    ...["farm","refinery","mining_rig"].map(type=>({...station,type}))],
    construction_sites:[]};
  const result=stationVisualOccupancy(report,station);
  assert.equal(result.capacity,4);
  assert.equal(result.empty,1);
  assert.equal(result.projects.length,0);
});
"""
test.write_text(s,encoding="utf8")
print("Galaxy 0.4.1 station UI: 4 real T1 visual positions, construction progress and blockers")
