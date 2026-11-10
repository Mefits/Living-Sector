"""Galaxy B5: show ONLY genuinely navigable cross-system travel_routes in
/api/report and Observer; keep jump-gate links distinct. The map no
longer invents connections just from stellar proximity.
Requires resource_grade_snapshot.py and galaxy_lanes.py first.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
def patch(path,pairs):
    s=path.read_text(encoding="utf8")
    for old,new in pairs:
        if s.count(old)!=1:
            raise RuntimeError(f"Expected unique B5 anchor in {path.name}, got {s.count(old)}: {old[:65]!r}")
        s=s.replace(old,new,1)
    path.write_text(s,encoding="utf8")
patch(root/"crates/sim_core/src/agents/celestial_body.rs",[
("""pub struct BodySnapshot {
    pub body_id: String,""",
"""pub struct BodySnapshot {
    /// Native body DB id for server-side route-to-system resolution.
    /// This is not a new identity exposed to the player.
    #[serde(skip)]
    pub db_id: i64,
    pub body_id: String,"""),
("""        Self {
            body_id: identity.body_id.clone(),
            system_name:""",
"""        Self {
            db_id: identity.db_id,
            body_id: identity.body_id.clone(),
            system_name:""")
])
patch(root/"crates/sim_server/src/http/api.rs",[
("""    let systems = build_systems_with_bodies(&state);

    let tps =""",
"""    let systems = build_systems_with_bodies(&state);
    let system_links = actual_system_corridors(&state);

    let tps ="""),
("""        "systems": systems,
        "ships": ships,""",
"""        "systems": systems,
        // Native travel_routes graph; not a visual proximity guess.
        "system_links": system_links,
        "ships": ships,"""),
("""fn build_systems_with_bodies(state: &AppState) -> Vec<serde_json::Value> {""",
"""fn actual_system_corridors(state: &AppState) -> Vec<serde_json::Value> {
    use std::collections::{BTreeMap,HashMap};
    // Body identities carry the true system in their cached snapshot.
    // Registry locations carry a native celestial_body_id (DB integer).
    let body_system: HashMap<i64,String> = state.snapshots.bodies.iter()
        .map(|entry| (entry.value().db_id, entry.value().system_name.clone()))
        .collect();
    let location_system: HashMap<String,String> = state.registry.locations.iter()
        .filter_map(|(name, loc)| body_system.get(&loc.celestial_body_id)
            .map(|sys|(name.clone(),sys.clone()))).collect();
    let mut corridors:BTreeMap<(String,String),u32>=BTreeMap::new();
    for (origin, outgoing) in &state.registry.routes {
        let Some(a)=location_system.get(origin) else {continue};
        for leg in outgoing {
            let Some(b)=location_system.get(&leg.to) else {continue};
            if a==b {continue;}
            let pair=if a<b {(a.clone(),b.clone())} else {(b.clone(),a.clone())};
            let minimum=corridors.entry(pair).or_insert(leg.distance);
            *minimum=(*minimum).min(leg.distance);
        }
    }
    corridors.into_iter().map(|((a,b),distance)|
        json!({"a":a,"b":b,"distance":distance,"kind":"travel"})).collect()
}

fn build_systems_with_bodies(state: &AppState) -> Vec<serde_json::Value> {"""),
("""                    "biome": snap.biome,
                    // Bundle D: territorial control""",
"""                    "biome": snap.biome,
                    "resource_grades": snap.resource_grades,
                    // Bundle D: territorial control""")
])
patch(root/"observer/model.js",[
("""  // Only actual gate_link.paired_gate_id relations; no guessed star lanes.
  const gateLinks = [];""",
"""  // Star corridors are sent by the server from native WorldRegistry
  // travel_routes. Never synthesize lines merely from star positions.
  const knownSystems = new Set(systems.map(s=>s.name));
  const routeLinks = [];
  const routesSeen = new Set();
  for (const route of list(report?.system_links)) {
    const a = String(route?.a ?? ""), b = String(route?.b ?? "");
    if (!knownSystems.has(a) || !knownSystems.has(b) || a===b) continue;
    const id = [a,b].sort().join("|");
    if (routesSeen.has(id)) continue;
    routesSeen.add(id);
    routeLinks.push({a,b,distance:number(route?.distance,0)});
  }
  // Only actual gate_link.paired_gate_id relations; no guessed gate links.
  const gateLinks = [];"""),
("""    systemFacilities, systemMarkets, systemPopulations, gateLinks
  };""",
"""    systemFacilities, systemMarkets, systemPopulations, routeLinks, gateLinks
  };""")
])
patch(root/"observer/app.js",[
("""    if(els.linksToggle.checked){
      for(const link of s.index.gateLinks){""",
"""    if(els.linksToggle.checked){
      for(const link of s.index.routeLinks ?? []){
        const a=sysMap.get(link.a),b=sysMap.get(link.b);
        if(!a||!b)continue;
        const p=toScreen(a),q=toScreen(b);
        ctx.setLineDash([]);ctx.lineWidth=1.3;ctx.strokeStyle="rgba(121,166,177,.36)";
        ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.stroke();
      }
      // Gate edges are physically different links; retain dashed styling.
      for(const link of s.index.gateLinks){""")
])
print("Galaxy B5: live system corridors and descriptive raw grades exposed to Observer")
