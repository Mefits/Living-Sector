"""Galaxy 0.6.1: attach economic priorities to the REAL Genesis coordinators.

The existing logistics administrator still chooses a source and carrier,
and the existing construction administrator still checks recipes, slots,
native site materials and paid construction labor.
This overlay never dispatches a ship directly or fabricates a market.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]/"work/source/Living-Sector-Galaxy-0.2"
core=root/"crates/sim_core/src"
def one(path,old,new):
    s=path.read_text(encoding="utf8")
    n=s.count(old)
    if n!=1:raise RuntimeError(f"Galaxy061 native decision source drift {path}: found {n}: {old[:90]!r}")
    path.write_text(s.replace(old,new,1),encoding="utf8")

# The native logistics proposal now includes a goal selected by a player,
# but ONLY if market stock is genuinely below target, the station is
# owned, the quote is affordable, and no already-funded plan is violated.
p=core/"strategy.rs"
one(p,
    """    for (entity, faction) in factions {
        let members = locations.get(&faction.id).cloned().unwrap_or_default();""",
    """    let player_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    for (entity, faction) in factions {
        let members = locations.get(&faction.id).cloned().unwrap_or_default();""")
one(p,
    """        goals.sort_by(|a,b| b.score.total_cmp(&a.score)""",
    """        if let Some(m)=player_economic_mandates.get(&faction.id) {
            if members.contains(&m.location)
                && economic_mandate::may_commission(
                    m,faction.treasury,faction::SUBSIDY_BASE_PAYMENT*2).is_ok() {
                if let Some((_,_,market))=markets.iter().find(|(loc,_,_)|*loc==m.location){
                    let stock=market.supply.get(&m.commodity).copied().unwrap_or(0.0);
                    if let Some(goal)=m.goal(stock){
                        // The ordinary shortlist retains its own crisis goals.
                        // This is a requested need, not an artificial stock.
                        goals.push(goal);
                    }
                }
            }
        }
        goals.sort_by(|a,b| b.score.total_cmp(&a.score)""")

# The existing construction administrator accepts a player-requested
# industrial production capability. Placement still checks local body,
# tech gates, paid site / materials, existing factory and station slots.
p=core/"strategy/construction.rs"
one(p,
    """        new_goals.sort_by(|a,b| b.score.total_cmp(&a.score)""",
    """        if let Some(m)=world.get_resource::<super::director::Director>()
            .and_then(|d|d.economic_mandates.get(&account.id)).cloned() {
            if m.kind==super::economic_mandate::EconomicKind::Industry &&
                members.contains(&m.location) &&
                super::economic_mandate::may_commission(
                    &m,account.treasury,faction::CONSTRUCTION_BASE_PAYMENT).is_ok() {
                if let Some((_,_,market))=markets.iter().find(|(loc,_,_)|*loc==m.location){
                    let stock=market.supply.get(&m.commodity).copied().unwrap_or(0.0);
                    if let Some(goal)=m.goal(stock) {
                        if !new_goals.iter().any(|g|
                            g.destination==goal.destination && g.commodity==goal.commodity) {
                            new_goals.push(goal);
                        }
                    }
                }
            }
        }
        new_goals.sort_by(|a,b| b.score.total_cmp(&a.score)""")

# A player wanting to develop local production must not be blocked by
# a negative sales-profit projection if a real funded factory site,
# valid materials and workers make the construction action feasible.
p=core/"strategy/director.rs"
one(p,
    """(goal.goal_id=="develop_colony"||(goal.destination.ends_with("-colony")&&a.site_id.is_some()))""",
    """(goal.goal_id=="develop_colony"||goal.goal_id=="player_industry"||
        (goal.destination.ends_with("-colony")&&a.site_id.is_some()))""")

# The existing head still weighs all real alternatives. A delegated
# economic directive injects a preference, but:
#  - survival/crises always outrank it,
#  - an outstanding native paid plan cannot be interrupted,
#  - the mandate MUST afford the candidate before it reaches dispatch,
#  - when infeasible the head keeps the ordinary autonomous fallback.
p=core/"strategy/coordination.rs"
one(p,
    """    for (id,head) in &mut decisions {
        let Some(c)=commanders.get(id) else{continue;};
        // A funded native plan owns its sequence""",
    """    let economic_intents=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    for (id,head) in &mut decisions {
        let Some(c)=commanders.get(id) else{continue;};
        // A funded native plan owns its sequence""")

one(p,
    """        let native_score=head.problem.as_ref().and_then(|g|head.alternatives.iter()""",
    """        if !c.crisis {
            if let Some(m)=economic_intents.get(id).filter(|m|m.active()) {
                if let Some(view)=world.resource::<StrategyState>().factions.get(id) {
                    let target=format!("{}|{}|{}",
                        m.goal_id(),m.location,m.commodity.as_str());
                    if let Some(mut comparison)=options::compare_director_target(
                        view,&sources,mult,c,&target) {
                        if m.kind==super::economic_mandate::EconomicKind::Industry &&
                            comparison.alternatives.iter().any(|a|
                                a.action=="build"&&a.status=="ready") {
                            comparison.selected="build";
                        }
                        let charge=comparison.alternatives.iter()
                            .find(|a|a.action==comparison.selected)
                            .map_or(0,|a|a.first_payment);
                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() {
                            *head=decision(view,&sources,tick,mult,false,Some(c),
                                Some(comparison));
                            head.reason="player_economic_mandate".into();
                        }
                    }
                }
            }
        }
        let native_score=head.problem.as_ref().and_then(|g|head.alternatives.iter()""")

one(p,
    """        let native_target=head.problem.as_ref().map(director::supply_target);""",
    """        let economic_selected=head.problem.as_ref().is_some_and(|g|
            economic_intents.get(id).is_some_and(|m|
                m.active() && g.goal_id==m.goal_id() &&
                g.destination==m.location && g.commodity==m.commodity));
        let native_score=if economic_selected&&!c.crisis {
            native_score.max(160.0)
        }else{native_score};
        let native_target=head.problem.as_ref().map(director::supply_target);""")

# After choosing an alternative and BEFORE the native planner has an
# opportunity to fund it, the same player budget/treasury floor is checked
# against the real next payment quoted by the original comparator.
# This gate catches paths that were auto-chosen without explicit override.
one(p,
    """    // A founded colony takes precedence over speculative new expansion when""",
    """    for (id,head) in &mut decisions {
        if let (Some(g),Some(m))=(head.problem.as_ref(),economic_intents.get(id)) {
            if g.goal_id==m.goal_id() && g.destination==m.location &&
                g.commodity==m.commodity {
                let charge=head.alternatives.iter()
                    .find(|a|a.action==head.selected_option)
                    .map_or(0,|a|a.first_payment);
                let treasury=head.treasury_before;
                if super::economic_mandate::may_commission(m,treasury,charge).is_err() {
                    head.problem=None;
                    head.selected_option="wait";
                    head.selected_administrator=None;
                    head.planned_spend=0;
                    head.reason="player_mandate_budget_or_reserve_blocked".into();
                }
            }
        }
    }
    // A founded colony takes precedence over speculative new expansion when""")

# Count credits ONLY after native administrators/HTN have actually
# posted paid contracts. No prediction can advance this ledger.
one(p,
    """        let mut state = world.resource_mut::<StrategyState>();
        for (id,view) in &mut state.factions {""",
    """        let mut mandate_receipts=Vec::<(String,i64)>::new();
        let mut state = world.resource_mut::<StrategyState>();
        for (id,view) in &mut state.factions {""")
one(p,
    """            if let Some(head) = &mut view.head { head.committed_spend = committed+science_spend.get(id).copied().unwrap_or(0);if head.selected_option=="research"{head.planned_spend=head.committed_spend;} }
        }
    }""",
    """            if let Some(head) = &mut view.head {
                head.committed_spend=committed+science_spend.get(id).copied().unwrap_or(0);
                if head.selected_option=="research"{head.planned_spend=head.committed_spend;}
                if committed>0 && head.problem.as_ref().is_some_and(|goal|
                    economic_intents.get(id).is_some_and(|m|
                        m.active()&&goal.goal_id==m.goal_id() &&
                        goal.destination==m.location&&goal.commodity==m.commodity)) {
                    mandate_receipts.push((id.clone(),committed));
                }
            }
        }
        drop(state);
        for (id,actual_paid) in mandate_receipts {
            super::economic_mandate::actual_commit(world,&id,actual_paid,tick);
        }
    }""")

print("Galaxy 0.6.1: player economic goals prefer native funded logistics/industry, never fake orders, receipts after dispatch")
