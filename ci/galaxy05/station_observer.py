"""Galaxy05 E7: report authoritative station tiers to Observer.

No facility-XP-level abuse: station_core is a separate read-only field.
Counts actual native facilities and unfinished sites. The native engine
alone owns tiers, receipts, resources and wallets; the browser never
determines upgrade success.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
server=root/"crates/sim_server/src"
observer=root/"observer"
def one(path,a,b):
    s=path.read_text(encoding="utf8")
    if s.count(a)!=1: raise RuntimeError(f"Galaxy05 Observer tier drift: {path} {a[:80]!r}")
    path.write_text(s.replace(a,b,1),encoding="utf8")

p=core/"agents/facility/components.rs"
one(p,
    """    pub level: u8,
    pub xp: u32,
    /// True when the facility has been broke""",
    """    pub level: u8,
    pub xp: u32,
    /// True core tier and physical module slots (station only).
    /// The unrelated facility XP level above stays unchanged.
    #[serde(skip_serializing_if="Option::is_none")]
    pub station_core: Option<serde_json::Value>,
    /// True when the facility has been broke""")
one(p,
    """            position,
            level,
            xp,
            abandoned,""",
    """            position,
            level,
            xp,
            station_core:None,
            abandoned,""")

p=server/"snapshot.rs"
one(p,
    """        let mut live: std::collections::HashSet<String> = Default::default();
        for e in entities {""",
    """        // Physical slot counts, not estimated from glyphs.
        let mut modules_by_location=std::collections::HashMap::<(String,String),usize>::new();
        for e in &entities {
            let Some(id)=world.get::<FacilityIdentity>(*e) else {continue;};
            let Some(loc)=world.get::<FacilityLocation>(*e) else {continue;};
            if id.facility_type=="station" || id.facility_type=="gate" {continue;}
            *modules_by_location.entry((id.faction_id.clone(),loc.location_name.clone()))
                .or_default()+=1;
        }
        let mut building_by_location=std::collections::HashMap::<(String,String),usize>::new();
        for site in world.query::<&ConstructionSite>().iter(world) {
            if !site.completed && site.facility_type!="station" {
                *building_by_location.entry((site.faction_id.clone(),site.location_name.clone()))
                    .or_default()+=1;
            }
        }
        let mut live: std::collections::HashSet<String> = Default::default();
        for e in entities {""")
one(p,
    """            let snap = FacilitySnapshot::build(
                &identity,""",
    """            let mut snap = FacilitySnapshot::build(
                &identity,""")
one(p,
    """            // Also publish the facility's position in the flat cache so""",
    """            if identity.facility_type=="station" {
                let state=world.get_resource::<sim_core::strategy::director::Director>()
                    .and_then(|d|d.station_progress.get(&identity.id))
                    .cloned().unwrap_or_default();
                let built=modules_by_location.get(&(
                    identity.faction_id.clone(),location.location_name.clone()))
                    .copied().unwrap_or(0);
                let pending=building_by_location.get(&(
                    identity.faction_id.clone(),location.location_name.clone()))
                    .copied().unwrap_or(0);
                let cap=state.tier.max_modules();
                snap.station_core=Some(serde_json::json!({
                    "tier":format!("{:?}",state.tier).to_lowercase(),
                    "slot_capacity":cap,
                    "built":built,"in_progress":pending,
                    "used":built+pending,
                    "free":cap.saturating_sub(built+pending),
                    "upgrade_target":state.target
                        .map(|t|format!("{t:?}").to_lowercase()),
                    "upgrade_materials_installed":state.materials_installed,
                    "upgrade_labor_completed":state.labor_completed,
                    "upgrade_labor_required":state.target
                        .map(sim_core::strategy::progression::upgrade_work),
                    "upgrade_last_receipt_tick":state.last_receipt_tick,
                    "upgrade_blocked_reason":state.blocked_reason,
                }));
            }
            // Also publish the facility's position in the flat cache so""")

p=observer/"priority-inspector.js"
one(p,
    """  const visualTier=occupied>5?"T3":occupied>4?"T2":"T1";
  const capacity=visualTier==="T3"?6:visualTier==="T2"?5:4;""",
    """  const core=station?.station_core;
  const visualTier=core?.tier?.toUpperCase()??(occupied>5?"T3":occupied>4?"T2":"T1");
  const capacity=core?.slot_capacity??(visualTier==="T3"?6:visualTier==="T2"?5:4);""")
one(p,
    """    block(factories,"Визуальных позиций",visual.visualTier+" · "+visual.capacity);
    block(factories,"Свободно на схеме",nfmt(visual.empty));
    factories.append(node(doc,"p","priority-muted",
      "Слоты пока только отображаются; игровой предел строительства отдельно не реализован."));""",
    """    block(factories,"Ядро станции",entity?.station_core?.tier?.toUpperCase()??visual.visualTier);
    block(factories,"Производственные места",nfmt(visual.capacity));
    block(factories,"Свободные места",nfmt(visual.empty));
    if(entity?.station_core?.upgrade_target){
      block(factories,"Повышение до",shown(entity.station_core.upgrade_target).toUpperCase());
      block(factories,"Материалы оплачены",entity.station_core.upgrade_materials_installed?"Да":"Нет");
      block(factories,"Работы",nfmt(entity.station_core.upgrade_labor_completed)
          +" / "+nfmt(entity.station_core.upgrade_labor_required));
    }
    if(entity?.station_core?.upgrade_blocked_reason)
      block(factories,"Ожидание улучшения",shown(entity.station_core.upgrade_blocked_reason));""")
print("Galaxy05 E7: real station core, upgrade receipts and 4/5/6 slot usage visible in Observer")
