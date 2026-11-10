"""D6: make station dispatcher tests use a valid *registered* world graph.

The graph-search change D4 is intentionally strict: missing graph vertices
are NOT silently assumed to exist. The original test fixture constructed
only edges, not the world locations those edges connect. That was accepted
by one-hop travel_distance but invalid for multi-hop shortest_distance.

Correct the TEST WORLD, not the production graph algorithm. Retain all
pre-existing assertions, including real purchase price, no minted credits,
one-to-one carrier assignment and source fallback.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
p=root/"crates/sim_core/src/strategy/orders/tests.rs"
s=p.read_text(encoding="utf-8")
before='''    let mut registry=WorldRegistry::default();registry.routes.insert("source".into(),vec![crate::world::registry::Route {to:"port".into(),distance:1}]);
    (w,ContractBoard::new(),registry,a,b)'''
after='''    let mut registry=WorldRegistry::default();
    // WorldRegistry::shortest_distance must see actual vertex registration;
    // a route to a non-existent location is invalid even if an edge says so.
    for name in ["source","port","backup"] {
        registry.locations.insert(name.into(),crate::world::registry::LocationInfo {
            db_id:0,name:name.into(),loc_type:"station".into(),celestial_body_id:0
        });
    }
    registry.routes.insert("source".into(),vec![
        crate::world::registry::Route {to:"port".into(),distance:1}
    ]);
    (w,ContractBoard::new(),registry,a,b)'''
if s.count(before)!=1:
    raise RuntimeError(f"D6 test fixture anchor expected once, found {s.count(before)}")
p.write_text(s.replace(before,after,1),encoding="utf-8")
print("D6: registered test locations for native station dispatch fixture")
