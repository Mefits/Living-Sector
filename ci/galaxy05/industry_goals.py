"""Galaxy05 E7: progression investment joins native construction choices.

After the paid core upgrade has created an additional slot, station
administrators may propose REAL alloyplant2/qfab3 facilities. These
projects reuse the current site, materials, real delivery contracts,
worker labor, escrow and eventual materialization. No fantasy spawn.
"""
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy/construction.rs"
s=p.read_text(encoding="utf8")
a="""        new_goals.sort_by(|a,b| b.score.total_cmp(&a.score).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));"""
b="""        // T2/T3 production investments. All prerequisites must be
        // researched and a truly paid upgrade must be completed first.
        // These goals enter the same native administrator portfolio as
        // all ordinary shortages; they do NOT create free buildings.
        for (station,loc) in facilities.iter().filter(|(id,_)|
            id.faction_id==account.id && id.facility_type=="station") {
            let tier=world.get_resource::<super::director::Director>()
                .and_then(|d|d.station_progress.get(&station.id))
                .map_or(super::progression::StationTier::T1,|s|s.tier);
            let candidate=if tier>=super::progression::StationTier::T3 &&
                super::director::has(world,&account.id,"quantumtech3") {
                Some((Commodity::QuantumCores,"qfab3",75.0))
            } else if tier>=super::progression::StationTier::T2 &&
                super::director::has(world,&account.id,"alloytech2") {
                Some((Commodity::Alloys,"alloyplant2",60.0))
            } else {None};
            let Some((commodity,kind,score))=candidate else {continue;};
            if facilities.iter().any(|(i,l)|i.faction_id==account.id &&
                l.location_name==loc.location_name && i.facility_type==kind) ||
               sites.iter().any(|site|site.location_name==loc.location_name &&
                site.facility_type==kind) {
                continue;
            }
            new_goals.push(Goal{
                goal_id:"progression_industry".into(),commodity,
                destination:loc.location_name.clone(),shortage_ticks:0,score,
            });
        }
        new_goals.sort_by(|a,b| b.score.total_cmp(&a.score).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));"""
if s.count(a)!=1:raise RuntimeError("Galaxy05 E7 progression construction anchor drift")
p.write_text(s.replace(a,b,1),encoding="utf8")
print("Galaxy05 E7: AI administrators can fund real Tier2 alloy plants and Tier3 quantum fabs")
