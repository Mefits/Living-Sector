"""Galaxy 0.4 D4: strategies use *multi-leg planning distance*, while
ship physical transit keeps its direct-leg travel_distance.

Under the old complete interstellar mesh every destination was a direct
edge. After D3 the galaxy has 8 corridors; strategic option evaluation,
station dispatch, colony viability and financial quotations must plan
through multiple real edges. But giving ShipAction::Travel a synthetic
long-distance edge would allow ships to teleport past intermediate
systems. This patch keeps those semantics separate.
"""
from pathlib import Path
src=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src"
registry=src/"world/registry.rs"
s=registry.read_text(encoding="utf-8")
old='''    pub fn reachable_from(&self, location: &str) -> &[Route] {'''
new=r'''    /// Shortest physical cost across native travel corridors, ignoring
    /// jump-gate teleportation (conservative for strategic budget checks).
    /// Does not create a direct edge: the ship's leg-by-leg BT still uses
    /// pathfinder::PathfinderCtx and the direct-only travel_distance().
    pub fn shortest_distance(&self, from: &str, to: &str) -> Option<u32> {
        use std::cmp::Reverse;
        use std::collections::BinaryHeap;
        if from == to { return Some(0); }
        if !self.locations.contains_key(from) || !self.locations.contains_key(to) {
            return None;
        }
        let mut frontier: BinaryHeap<Reverse<(u32, String)>> = BinaryHeap::new();
        let mut costs: HashMap<String,u32> = HashMap::new();
        frontier.push(Reverse((0,from.to_owned())));
        costs.insert(from.to_owned(),0);
        while let Some(Reverse((cost,from))) = frontier.pop() {
            if from==to { return Some(cost); }
            if cost > costs.get(&from).copied().unwrap_or(u32::MAX) { continue; }
            for leg in self.reachable_from(&from) {
                if !self.locations.contains_key(&leg.to) { continue; }
                let sum = cost.saturating_add(leg.distance);
                if sum < costs.get(&leg.to).copied().unwrap_or(u32::MAX) {
                    costs.insert(leg.to.clone(),sum);
                    frontier.push(Reverse((sum,leg.to.clone())));
                }
            }
        }
        None
    }

    pub fn reachable_from(&self, location: &str) -> &[Route] {'''
if s.count(old)!=1:raise RuntimeError("D4 missing WorldRegistry helper anchor")
s=s.replace(old,new,1)
if "fn galaxy04_multihop_strategy_distance" in s:raise RuntimeError("Test already present")
s+=r'''

#[cfg(test)]
mod galaxy04_multihop_strategy_distance_tests {
    use super::*;

    #[test]
    fn galaxy04_multihop_strategy_distance_preserves_real_ship_legs() {
        let mut g=WorldRegistry::default();
        for name in ["station-alpha","station-sol","mars-colony","isolated"] {
            g.locations.insert(name.into(),LocationInfo {
                db_id:0,name:name.into(),loc_type:"station".into(),
                celestial_body_id:0,
            });
        }
        g.routes.insert("station-alpha".into(),vec![
            Route{to:"station-sol".into(),distance:125}
        ]);
        g.routes.insert("station-sol".into(),vec![
            Route{to:"station-alpha".into(),distance:125},
            Route{to:"mars-colony".into(),distance:22}
        ]);
        g.routes.insert("mars-colony".into(),vec![
            Route{to:"station-sol".into(),distance:22}
        ]);
        assert_eq!(g.travel_distance("station-alpha","mars-colony"),None,
            "Ships must never transit across non-existing direct edge");
        assert_eq!(g.shortest_distance("station-alpha","mars-colony"),Some(147));
        assert_eq!(g.shortest_distance("mars-colony","station-alpha"),Some(147));
        assert_eq!(g.shortest_distance("mars-colony","mars-colony"),Some(0));
        assert_eq!(g.shortest_distance("isolated","mars-colony"),None);
        assert_eq!(g.shortest_distance("missing","mars-colony"),None);
    }
}
'''
registry.write_text(s,encoding="utf-8")

# Only strategic feasibility and budget estimators use graph shortest paths.
# Do NOT touch ship/actions.rs (physical transit of one current leg).
strategy=src/"strategy"
changed={}
files=[src/"strategy.rs",*strategy.rglob("*.rs")]
for file in files:
    data=file.read_text(encoding="utf-8")
    count=data.count(".travel_distance(")
    if not count:continue
    file.write_text(data.replace(".travel_distance(",".shortest_distance("),
                    encoding="utf-8")
    changed[str(file.relative_to(src))]=count
if sum(changed.values())<9:raise RuntimeError(f"D4 found unusually few strategic route sites: {changed}")
# The free-cargo liquidation module from A3 uses actual BT multi-hop
# route_actions; its buyer selection may now use the same shortest cost.
ship=src/"agents/ship/behavior.rs"
source=ship.read_text(encoding="utf-8")
before="let Some(d) = registry.travel_distance(at, location) else { continue; };"
if source.count(before)!=1:
    raise RuntimeError("D4 expected A3 liquidity planner source")
source=source.replace(before,
    "let Some(d) = registry.shortest_distance(at, location) else { continue; };")
ship.write_text(source,encoding="utf-8")
print("Galaxy D4: shortest physical planning routes in",changed,
      "without changing direct ship Transit leg semantics")
