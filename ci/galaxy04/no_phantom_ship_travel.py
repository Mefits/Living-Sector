"""Galaxy 0.4 D5: fail a physical ship Travel action if no real direct
edge exists. Prior fallback silently used a fictitious 60-unit route,
allowing ships to cross disconnected systems even after the graph fix.
Native behavior tree pathfinder produces each actual leg separately.
"""
from pathlib import Path
src=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
path=src/"crates/sim_core/src/agents/ship/actions.rs"
s=path.read_text(encoding="utf8")
old='''            let distance = registry
                .travel_distance(&from, destination)
                .or_else(|| registry.travel_distance(destination, &from))
                .unwrap_or(60);'''
new='''            // A planned route must be decomposed into physical legs.
            // A missing direct edge is a navigation error, NOT an
            // implicit 60-unit warp across the sector.
            let Some(distance) = registry
                .travel_distance(&from, destination)
                .or_else(|| registry.travel_distance(destination, &from)) else {
                    return BtStatus::Failure;
                };'''
if s.count(old)!=1:raise RuntimeError("D5 ship transit anchor is different")
path.write_text(s.replace(old,new,1),encoding="utf8")
print("Galaxy D5: physical Travel rejects non-existent direct edges")
