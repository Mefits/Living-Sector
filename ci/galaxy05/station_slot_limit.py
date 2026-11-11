"""Galaxy 0.5 E5: native construction administrator enforces actual core slots.

The station tier lives in persisted Director.station_progress, NOT in
FacilityLifecycle.level (recipe XP). Pending construction sites already
occupy a position. Unfinished sites may receive cargo/labor as before;
new facilities cannot be launched over the physical cap.
"""
from pathlib import Path

p=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy/construction.rs"
s=p.read_text(encoding="utf8")
a="""                let already_built = existing.is_none() && facilities.iter().any(|(i,l)|
                    i.faction_id == account.id && l.location_name == goal.destination && Some(i.facility_type.as_str()) == kind);
                let reason = if conflict { "site_owned_by_other_faction" }"""
b="""                let already_built = existing.is_none() && facilities.iter().any(|(i,l)|
                    i.faction_id == account.id && l.location_name == goal.destination && Some(i.facility_type.as_str()) == kind);
                // True T1=4, T2=5, T3=6 station core cap. This is
                // independent of dock capacity and factory XP level.
                let full_station_core=existing.is_none() && facilities.iter()
                    .find(|(i,l)|i.facility_type=="station"
                        && i.faction_id==account.id
                        && l.location_name==goal.destination)
                    .is_some_and(|(station,_)|{
                        let tier=world.get_resource::<super::director::Director>()
                            .and_then(|d|d.station_progress.get(&station.id))
                            .map_or(super::progression::StationTier::T1,|d|d.tier);
                        let built=facilities.iter().filter(|(i,l)|
                            i.faction_id==account.id &&
                            l.location_name==goal.destination &&
                            i.facility_type!="station" && i.facility_type!="gate")
                            .count();
                        let in_progress=world.query::<&ConstructionSite>().iter(world)
                            .filter(|site|site.faction_id==account.id &&
                                site.location_name==goal.destination && !site.completed
                                && site.facility_type!="station").count();
                        matches!(super::progression::available_slot(tier,built,in_progress),
                            super::progression::SlotAvailability::Full{..})
                    });
                let reason = if conflict { "site_owned_by_other_faction" }"""
if s.count(a)!=1:raise RuntimeError("Galaxy05 E5 station core cap insertion drift")
s=s.replace(a,b,1)
a="""                    else if already_built { "producer_already_present" }"""
b="""                    else if already_built { "producer_already_present" }
                    else if full_station_core { "no_free_station_slot" }"""
if s.count(a)!=1:raise RuntimeError("Galaxy05 E5 slot full blocker placement drift")
p.write_text(s.replace(a,b,1),encoding="utf8")
print("Galaxy05 E5: native construction refuses new facility at 4/5/6 slots")
