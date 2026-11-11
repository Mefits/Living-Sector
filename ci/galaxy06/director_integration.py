"""Galaxy 0.6: connect one player science mandate to the real Director.

- Automatic factions remain identical when no mandate exists.
- A delegated long-range research target selects actual prerequisites.
- Paid-progress-in-flight is never deleted when the player changes focus.
- Crisis/survival and active prepaid native plan take precedence.
- ONLY native paid research may debit CR and count spent budget.
- Mode advise changes no economic decisions; hold pauses science only.
- Existing save files default to no research mandates.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
CORE=ROOT/"crates/sim_core/src"
SERVER=ROOT/"crates/sim_server/src"

def one(path,a,b):
    s=path.read_text(encoding="utf8")
    n=s.count(a)
    if n!=1:raise RuntimeError(f"Galaxy06 director source drift in {path.name}: {n}, {a[:75]!r}")
    path.write_text(s.replace(a,b,1),encoding="utf8")

p=CORE/"strategy/director.rs"
one(p,
  """    pub station_progress: BTreeMap<String,super::progression::StationDevelopment>,
}""",
  """    pub station_progress: BTreeMap<String,super::progression::StationDevelopment>,
    /// No directive in old checkpoints means normal independent faction AI.
    #[serde(default)]
    pub research_mandates:BTreeMap<String,super::governance::ResearchMandate>,
}""")

one(p,
  """        let c=d.commanders.entry(f.id.clone()).or_insert_with(||Commander{""",
  """        // Take a snapshot of the voluntary player rule before taking the
        // mutable commander slot from the same native Director resource.
        let mandate=d.research_mandates.get(&f.id).cloned();
        let c=d.commanders.entry(f.id.clone()).or_insert_with(||Commander{""")

one(p,
  """        c.stations=station_count;c.colonies=colonies;c.completed_contracts=paid;
        if c.research.is_none(){""",
  """        c.stations=station_count;c.colonies=colonies;c.completed_contracts=paid;
        if let Some(ref m)=mandate {
            // A science mandate only selects a target when not replacing a
            // shift already paid for. The engine never rolls research back.
            if m.mode==super::governance::MandateMode::Delegated &&
                !m.completed(&c.technologies) && c.progress==0 {
                if let Ok(Some(next))=super::governance::next_technology(
                    &m.target_technology,&c.technologies) {
                    if c.research.as_deref()!=Some(next.id) {
                        c.research=Some(next.id.to_string());
                        c.research_required=next.work;
                        c.progress=0;
                    }
                }
            }
        }
        if c.research.is_none(){""")

one(p,
  """        let cost=price.ceil() as i64+10;
        if treasury<cost+10_000 {return Err("research_reserve");}""",
  """        let cost=price.ceil() as i64+10;
        if treasury<cost+10_000 {return Err("research_reserve");}
        // Revalidate the ENTIRE directive budget against today's actual
        // quote, before moving a single electron or real credit.
        super::governance::authorize_research(world,faction_id,cost,treasury)?;""")

one(p,
  """        if c.progress>=c.research_required {let tech=c.research.take().unwrap();c.technologies.push(tech.clone());record(c,tick,"technology_completed",&tech,"completed");}
        return Ok(cost);""",
  """        if c.progress>=c.research_required {let tech=c.research.take().unwrap();c.technologies.push(tech.clone());record(c,tick,"technology_completed",&tech,"completed");}
        drop(d);
        super::governance::paid_research(world,faction_id,cost);
        return Ok(cost);""")

one(p,
  """    if c.research.is_none()||c.crisis{return false;}
    let occupied=workforce::occupied_workers(world,tick);""",
  """    if c.research.is_none()||c.crisis{return false;}
    if super::governance::active(world,id)
        .is_some_and(|m|m.mode==super::governance::MandateMode::Hold) {
        return false;
    }
    let occupied=workforce::occupied_workers(world,tick);""")

p=CORE/"strategy/coordination.rs"
one(p,
  """        let research=if research_ready.contains(id)&&!c.crisis {
            18.0*c.profile.science+if c.strategic.kind=="research"{2.0}else{0.0}
        }else{-1.0};""",
  """        // Player directives choose a strategic PRIORITY, not native
        // actions. Life support and outstanding prepaid plans still win.
        let delegated_science=super::governance::active(world,id).is_some_and(|m|
            m.mode==super::governance::MandateMode::Delegated);
        let research=if research_ready.contains(id)&&!c.crisis {
            18.0*c.profile.science+if c.strategic.kind=="research"{2.0}else{0.0}
                +if delegated_science{160.0}else{0.0}
        }else{-1.0};""")

p=CORE/"strategy.rs"
one(p,
  """    pub station_progress: BTreeMap<String,progression::StationDevelopment>,
    /// Read-only persisted plan ledger""",
  """    pub station_progress: BTreeMap<String,progression::StationDevelopment>,
    /// Read-only player science policy and actual paid CR ledger.
    #[serde(default)]
    pub research_mandates: BTreeMap<String,governance::ResearchMandate>,
    /// Read-only persisted plan ledger""")
one(p,
  """            station_progress:BTreeMap::new(), ai_execution:None }""",
  """            station_progress:BTreeMap::new(),
            research_mandates:BTreeMap::new(), ai_execution:None }""")

p=SERVER/"snapshot.rs"
one(p,
  """                snapshot.station_progress = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.station_progress.clone()).unwrap_or_default();""",
  """                snapshot.station_progress = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.station_progress.clone()).unwrap_or_default();
                snapshot.research_mandates = world.get_resource::<sim_core::strategy::director::Director>()
                    .map(|d|d.research_mandates.clone()).unwrap_or_default();""")

print("Galaxy06: researched prerequisite + real mandate budget + strategy priority + saved API state")
