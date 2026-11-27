"""Galaxy 0.4 D3: replace legacy automatic COMPLETE interstellar route
mesh with exactly the eight explicitly seeded, reachable corridors.

Before this fix spawner::chart_colony_routes added an all-pairs edge for
EVERY pair of locations across different star systems. It bypassed the new
galactic corridor graph and would have drawn a 28-edge complete network
across eight systems, contradicting both ship routes and the UI design.

Keep the existing same-system colony route generation fully intact.
"""
from pathlib import Path
src=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
path=src/"crates/sim_db/src/spawner.rs"
s=path.read_text(encoding="utf8")
old='''    if std::env::var("LIVING_SECTOR_GALAXY").as_deref()==Ok("1") {
        // Surveyed interstellar cruise corridors; ordinary movement and fuel apply.
        sqlx::query("INSERT OR IGNORE INTO travel_routes (from_location,to_location,distance)
            SELECT a.name,b.name,100+CAST(ABS(sa.universe_offset_x-sb.universe_offset_x)+ABS(sa.universe_offset_y-sb.universe_offset_y) AS INTEGER)
            FROM locations a JOIN celestial_bodies ba ON ba.id=a.celestial_body_id JOIN star_systems sa ON sa.id=ba.star_system_id
            JOIN locations b JOIN celestial_bodies bb ON bb.id=b.celestial_body_id JOIN star_systems sb ON sb.id=bb.star_system_id
            WHERE sa.id<>sb.id").execute(&mut *tx).await?;
    }
'''
new='''    // Galaxy 0.4 D3: do NOT synthesize an all-to-all interstellar mesh.
    // Eight deliberate cross-system transport lanes are already inserted by
    // seeder::seed_world from world JSON travel_routes. Those lanes are
    // the *same* native graph used by pathfinding, trade, and the Observer.
    // Above SQL still adds ordinary intra-system colony access only.
'''
if s.count(old)!=1:raise RuntimeError("Old all-pairs route generator not found exactly once")
path.write_text(s.replace(old,new,1),encoding="utf8")
print("Galaxy 0.4 D3: removed automatic complete interstellar route graph")
