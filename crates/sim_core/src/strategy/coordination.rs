//! A single head decision over both administrators' non-mutating proposals.
use super::*;

#[derive(Clone, Debug, Serialize)]
pub struct Proposal {
    pub administrator: &'static str,
    pub goal: Option<Goal>,
    pub status: String,
    pub reason: String,
    pub requested_credits: i64,
    pub priority: u8,
}
#[derive(Clone, Debug, Serialize)]
pub struct HeadDecision {
    pub observed_tick: u64,
    pub selected_administrator: Option<&'static str>,
    pub reason: String,
    pub treasury_before: i64,
    /// Spendable current balance, not a second account or durable reservation.
    pub spending_limit: i64,
    pub planned_spend: i64,
    pub committed_spend: i64,
    pub proposals: Vec<Proposal>,
}
#[derive(Resource)]
struct Grants(BTreeMap<String, &'static str>);

pub(super) fn authorized(world: &World, faction: &str, administrator: &str) -> bool {
    world.get_resource::<Grants>().is_none_or(|g| g.0.get(faction).is_some_and(|a| *a == administrator))
}
fn choose(proposals: &[Proposal], limit: i64) -> Option<&Proposal> {
    proposals.iter().filter(|p| p.status == "proposed" && p.requested_credits <= limit)
        .max_by(|a,b| a.priority.cmp(&b.priority)
            .then_with(|| a.goal.as_ref().map_or(0.0,|g| g.score).total_cmp(&b.goal.as_ref().map_or(0.0,|g| g.score)))
            // Stable tie-break independent of the order administrators were evaluated.
            .then_with(|| b.administrator.cmp(a.administrator)))
}
fn decision(view: &FactionView, tick: u64, already_commissioned: bool) -> HeadDecision {
    let urgent = view.selected_goal.as_ref().is_some_and(|g|
        matches!(g.commodity, Commodity::Food | Commodity::Water | Commodity::Fuel));
    let mut proposals = vec![Proposal { administrator: "logistics", goal: view.selected_goal.clone(),
        status: view.status.clone(), reason: view.reason.clone(),
        requested_credits: faction::SUBSIDY_BASE_PAYMENT * 2, priority: if urgent { 3 } else { 0 } }];
    if let Some(c) = &view.construction {
        proposals.push(Proposal { administrator: "construction", goal: c.selected_goal.clone(),
            status: c.status.clone(), reason: c.reason.clone(), requested_credits: faction::CONSTRUCTION_BASE_PAYMENT,
            priority: if c.site_id.is_some() { 2 } else { 1 } });
    }
    let limit = view.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR).max(0);
    let chosen = if already_commissioned { None } else { choose(&proposals,limit) };
    let selected = chosen.map(|p| p.administrator);
    let planned = chosen.map_or(0,|p| p.requested_credits);
    let reason = if already_commissioned { "already_commissioned_this_tick" }
        else { match chosen.map(|p| p.priority) {
            Some(3) => "urgent_supply", Some(2) => "finish_existing_construction",
            Some(1) => "expand_production", Some(_) => "supply_industry", None => "no_feasible_proposal",
        }};
    HeadDecision { observed_tick: tick, selected_administrator: selected, reason: reason.into(),
        treasury_before: view.treasury, spending_limit: limit, planned_spend: planned,
        committed_spend: 0, proposals }
}

/// One funded strategic contract per faction per decision cycle. Both proposals
/// observe the same treasury and board before either administrator may mutate them.
pub fn run_cycle(world: &mut World, board: &mut ContractBoard, relations: &FactionRelations,
    events: &mut Vec<serde_json::Value>, tick: u64, mult: u32) {
    world.init_resource::<StrategyState>();
    if world.resource::<StrategyState>().last_coordinated_tick == Some(tick) { return; }
    let mode = world.resource::<StrategyState>().mode;
    world.resource_mut::<StrategyState>().mode = Mode::Shadow;
    super::run_cycle(world,board,relations,tick,mult);
    let mut preview_events = Vec::new();
    construction::run_cycle(world,board,relations,&mut preview_events,tick,mult);
    debug_assert!(preview_events.is_empty());
    world.resource_mut::<StrategyState>().mode = mode;
    let decisions: Vec<_> = world.resource::<StrategyState>().factions.iter().map(|(id,view)| {
        let already = board.iter().any(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
            matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG)));
        (id.clone(),decision(view,tick,already))
    }).collect();
    let grants = decisions.iter().filter_map(|(id,d)| d.selected_administrator.map(|a| (id.clone(),a))).collect();
    for (id,d) in decisions { world.resource_mut::<StrategyState>().factions.get_mut(&id).unwrap().head = Some(d); }
    if mode == Mode::Execute {
        world.insert_resource(Grants(grants));
        // Gate checks, not call order, decide which administrator can fund work.
        super::run_cycle(world,board,relations,tick,mult);
        construction::run_cycle(world,board,relations,events,tick,mult);
        world.remove_resource::<Grants>();
        let mut state = world.resource_mut::<StrategyState>();
        for (id,view) in &mut state.factions {
            let committed: i64 = board.iter().filter(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
                matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG)))
                .filter_map(|c| c.funding.as_ref()).map(|f| f.reserved).sum();
            if let Some(head) = &mut view.head { head.committed_spend = committed; }
        }
    }
    world.resource_mut::<StrategyState>().last_coordinated_tick = Some(tick);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agents::{celestial_body::{BodyIdentity,BodyOrbit,BodyResources},construction::ConstructionSite};
    fn fixture() -> (World, ContractBoard, Entity, Entity, Entity) {
        let (mut w,b,owner,port,source) = super::super::tests::fixture(Mode::Execute);
        w.get_mut::<FactionData>(owner).unwrap().treasury = 80_000;
        w.get_mut::<MarketPricing>(source).unwrap().supply = [(Commodity::Food,600.0),(Commodity::Ore,600.0)].into();
        w.spawn((BodyIdentity { db_id: 1, body_id: "earth".into(), name: "Earth".into(),
            body_type: "planet".into(), star_system_id: 1, system_name: "sol".into() },
            BodyOrbit { orbit_radius: 1.0, orbit_period: 100, current_angle: 0.0, universe_offset: (0.0,0.0), dirty: false },
            BodyResources { resources: [(Commodity::Ore,1.0)].into(), max_resources: [(Commodity::Ore,1.0)].into() }));
        (w,b,owner,port,source)
    }
    #[test]
    fn strategy_block_head_urgent_supply_wins_and_tick_cannot_fund_twice() {
        let (mut w,mut b,owner,_,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        // Exercise actual faction pipeline at a tick where both legacy intervals coincide.
        faction::tick_factions(&mut w,&mut b,&mut events,&mut HashMap::new(),&relations,600,1);
        assert_eq!(b.iter().count(),1);
        assert_eq!(b.iter().next().unwrap().mission_category.as_deref(),Some(super::super::PROJECT_TAG));
        let view = &w.resource::<StrategyState>().factions["own"];
        let head = view.head.as_ref().unwrap();
        assert_eq!(head.selected_administrator,Some("logistics"));
        assert_eq!(head.reason,"urgent_supply"); assert_eq!(head.planned_spend,1600); assert_eq!(head.committed_spend,1600);
        assert_eq!(view.construction.as_ref().unwrap().reason,"head_priority");
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),0);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,78_400);
        run_cycle(&mut w,&mut b,&relations,&mut events,600,1);
        assert_eq!(b.iter().count(),1);
        // Persisted board guards replay even when transient head state is lost.
        w.insert_resource(StrategyState { mode: Mode::Execute, ..Default::default() });
        run_cycle(&mut w,&mut b,&relations,&mut events,600,1);
        assert_eq!(b.iter().count(),1); assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,78_400);
        assert_eq!(w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().reason,"already_commissioned_this_tick");
    }
    #[test]
    fn strategy_block_head_continues_site_before_industrial_delivery() {
        let (mut w,mut b,owner,port,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        faction::ensure_site_spawned(&mut w,&mut events,"own",Commodity::Food,"port",1);
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks = [(Commodity::Ore,50)].into();
        run_cycle(&mut w,&mut b,&relations,&mut events,60,1);
        let head = w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.reason,"finish_existing_construction");
        assert_eq!(head.selected_administrator,Some("construction"));
        assert_eq!(head.committed_spend,10_000); assert_eq!(b.iter().count(),1);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,70_000);
        // An in-flight construction shipment does not prevent useful logistics next cycle.
        run_cycle(&mut w,&mut b,&relations,&mut events,120,1);
        assert_eq!(b.iter().count(),2);
        assert_eq!(w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().selected_administrator,Some("logistics"));
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,68_400);
    }
    #[test]
    fn strategy_block_head_shadow_matches_execution_and_respects_budget_floor() {
        let (mut w,mut b,owner,port,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks = [(Commodity::Ore,1000)].into();
        w.resource_mut::<StrategyState>().mode = Mode::Shadow;
        run_cycle(&mut w,&mut b,&relations,&mut events,60,1);
        let head = w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.selected_administrator,Some("construction")); assert_eq!(head.committed_spend,0);
        assert_eq!(head.planned_spend,10_000); assert!(events.is_empty()); assert_eq!(b.iter().count(),0);
        assert_eq!(w.query::<&ConstructionSite>().iter(&w).count(),0);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,80_000);
        w.resource_mut::<StrategyState>().mode = Mode::Execute;
        run_cycle(&mut w,&mut b,&relations,&mut events,120,1);
        assert_eq!(w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().selected_administrator,Some("construction"));
        assert_eq!(b.iter().count(),1);
        // Fresh world: only logistics fits; spending limit preserves the native floor.
        let (mut w,mut b,owner,_,_) = fixture();
        w.get_mut::<FactionData>(owner).unwrap().treasury = 6_600;
        run_cycle(&mut w,&mut b,&relations,&mut events,60,1);
        let head = w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.spending_limit,1600); assert_eq!(head.committed_spend,1600);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,5_000);
        assert_eq!(b.iter().count(),1);
    }
    #[test]
    fn strategy_block_head_selection_is_independent_of_proposal_order() {
        let (mut w,mut b,_,_,_) = fixture();
        w.resource_mut::<StrategyState>().mode = Mode::Shadow;
        run_cycle(&mut w,&mut b,&FactionRelations::new(),&mut Vec::new(),60,1);
        let head = w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        let mut proposals = head.proposals.clone();
        let expected = choose(&proposals,head.spending_limit).unwrap().administrator;
        proposals.reverse();
        assert_eq!(choose(&proposals,head.spending_limit).unwrap().administrator,expected);
        assert!(choose(&proposals,1599).is_none());
    }
}
