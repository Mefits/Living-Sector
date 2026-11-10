"""Galaxy 0.4.1: do not found another colony while established colonies
lack actual essential stocks. A colony project already under construction
continues to receive materials; this blocks NEW speculative founding only.
"""
from pathlib import Path
path=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2/crates/sim_core/src/strategy/coordination.rs"
s=path.read_text(encoding="utf8")
a="""    let colonies = colony::proposals(world, board, relations);
    // Established colonies are not just a founding event."""
b="""    let mut colonies = colony::proposals(world, board, relations);
    // Established colonies are not just a founding event."""
if s.count(a)!=1:raise RuntimeError("Galaxy 0.4.1 colony proposal anchor missing")
s=s.replace(a,b,1)
a="""    let colony_views = colony_development::observe(world, board);
    let migration_plans = colony_development::migration_proposals(world, board, &colony_views);"""
b="""    let colony_views = colony_development::observe(world, board);
    // No third settlement while the faction's second settlement is
    // starving or cannot receive real supplies. This is a gate on new
    // development, not a free food or water grant, and cannot cancel
    // a project for which construction cargo is already paid.
    for view in &colony_views {
        let unsafe_supply=!view.market_unambiguous || view.food
            .zip(view.food_reserve_target)
            .is_none_or(|(stock,target)|stock<target)
            || view.water.zip(view.water_reserve_target)
            .is_none_or(|(stock,target)|stock<target);
        if view.population>0 && unsafe_supply {
            if let Some(plan)=colonies.get_mut(&view.faction_id) {
                if plan.site_id.is_none() {
                    plan.reason="existing_colony_life_support_crisis";
                }
            }
        }
    }
    let migration_plans = colony_development::migration_proposals(world, board, &colony_views);"""
if s.count(a)!=1:raise RuntimeError("Galaxy 0.4.1 colony lifecycle anchor missing")
path.write_text(s.replace(a,b,1),encoding="utf8")
print("Galaxy 0.4.1: founding blocked until pre-existing colonies are supplied")
