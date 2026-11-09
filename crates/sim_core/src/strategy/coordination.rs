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
    pub problem: Option<Goal>,
    pub selected_option: &'static str,
    pub horizon_ticks: u64,
    pub alternatives: Vec<options::Alternative>,
    /// Read-only comparison; no grants, money changes or executor orders.
    pub shadow_portfolio: Option<options::ShadowRecommendation>,
    /// Native recipe-based dependency probe; not a construction or production order.
    pub native_chain_probe: Option<options::NativeChainProbe>,
}
struct Grant {
    administrator: &'static str,
    goal: Goal,
}

#[derive(Resource)]
struct Grants(BTreeMap<String, Grant>);

pub(super) fn authorized(world: &World, faction: &str, administrator: &str, goal: &Goal) -> bool {
    world.get_resource::<Grants>().is_none_or(|grants| {
        grants.0.get(faction).is_some_and(|grant| {
            grant.administrator == administrator && options::same_problem(&grant.goal, goal)
        })
    })
}

fn decision(
    view: &FactionView, sources: &sourcing::Sources<'_>, tick: u64,
    mult: u32, already_commissioned: bool,
) -> HeadDecision {
    let limit = view.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR).max(0);
    let comparison = options::compare(view, sources, mult);
    let shadow_portfolio = options::shadow_portfolio(view, sources, mult);
    let native_chain_probe = options::native_chain_probe(comparison.as_ref().map(|c| &c.goal), sources);
    let selected_option = if already_commissioned { "wait" }
        else { comparison.as_ref().map_or("wait", |c| c.selected) };
    let selected = match selected_option {
        "deliver" => Some("logistics"),
        "build" => Some("construction"),
        _ => None,
    };
    let (problem, alternatives) = comparison.map_or((None, Vec::new()), |c| {
        (Some(c.goal), c.alternatives)
    });
    let planned = alternatives.iter().find(|option| option.action == selected_option)
        .map_or(0, |option| option.first_payment);
    let reason = if already_commissioned { "already_commissioned_this_tick" }
        else if problem.is_none() { "no_current_problem" }
        else if selected_option == "wait" { "wait_no_positive_option" }
        else { "best_projected_relief" };
    // Keep the original two-administrator projection for older readers.
    // The comparison uses net value, and priority is only a legacy hint.
    let proposals = alternatives.iter().filter_map(|option| {
        let administrator = match option.action {
            "deliver" => "logistics",
            "build" => "construction",
            _ => return None,
        };
        let priority = match option.action {
            "deliver" if problem.as_ref().is_some_and(|goal| {
                matches!(goal.commodity, Commodity::Food | Commodity::Water | Commodity::Fuel)
            }) => 3,
            "build" if option.site_id.is_some() => 2,
            "build" => 1,
            _ => 0,
        };
        Some(Proposal {
            administrator,
            goal: problem.clone(),
            status: if option.status == "ready" { "proposed" } else { "blocked" }.into(),
            reason: option.reason.clone(),
            requested_credits: option.first_payment,
            priority,
        })
    }).collect();
    HeadDecision {
        observed_tick: tick, selected_administrator: selected, reason: reason.into(),
        treasury_before: view.treasury, spending_limit: limit, planned_spend: planned,
        committed_spend: 0, proposals, problem, selected_option,
        horizon_ticks: options::horizon_ticks(mult), alternatives, shadow_portfolio, native_chain_probe,
    }
}

/// One funded strategic contract per faction per decision cycle. Both proposals
/// observe the same treasury and board before either administrator may mutate them.
pub fn run_cycle(world: &mut World, board: &mut ContractBoard, relations: &FactionRelations,
    events: &mut Vec<serde_json::Value>, tick: u64, mult: u32) {
    world.init_resource::<StrategyState>();
    if world.resource::<StrategyState>().last_coordinated_tick == Some(tick) { return; }
    let mode = world.resource::<StrategyState>().mode;
    if mode == Mode::Execute {
        sourcing::withdraw_unprofitable(world, board, relations, events, tick);
    }
    world.resource_mut::<StrategyState>().mode = Mode::Shadow;
    super::run_cycle(world,board,relations,tick,mult);
    let mut preview_events = Vec::new();
    construction::run_cycle(world,board,relations,&mut preview_events,tick,mult);
    debug_assert!(preview_events.is_empty());
    world.resource_mut::<StrategyState>().mode = mode;
    let colonies = colony::proposals(world, board, relations);
    let owners = crate::agents::faction_relations::market_controllers(world);
    let mut query = world.query::<(&MarketIdentity, &MarketPricing)>();
    let sources = sourcing::Sources::new(
        query.iter(world).map(|(id, market)| (id.facility_location.as_str(), market)),
        owners, relations,
    );
    let mut decisions: Vec<_> = world.resource::<StrategyState>().factions.iter().map(|(id,view)| {
        let already = board.iter().any(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
            matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG) | Some(colony::PROJECT_TAG)));
        (id.clone(), decision(view, &sources, tick, mult, already))
    }).collect();
    for (id, head) in &mut decisions {
        let Some(plan) = colonies.get(id) else { continue; };
        let ready = plan.reason == "ready";
        head.proposals.push(Proposal {
            administrator: "construction", goal: Some(plan.goal.clone()),
            status: if ready { "proposed" } else { "blocked" }.into(),
            reason: plan.reason.into(), requested_credits: plan.cost, priority: 1,
        });
        // Finish a viable expedition ahead of other projects. A new one can
        // begin when current operational needs have no funded alternative.
        if ready && head.reason != "already_commissioned_this_tick"
            && (plan.site_id.is_some() || head.selected_option == "wait")
        {
            head.selected_administrator = Some("construction");
            head.selected_option = if plan.site_id.is_none() { "found_colony" } else { "supply_colony" };
            head.problem = Some(plan.goal.clone());
            head.reason = "viable_expansion".into();
            head.planned_spend = plan.cost;
            head.alternatives.clear();
        }
    }
    let grants = decisions.iter().filter_map(|(id, decision)| Some((id.clone(), Grant {
        administrator: decision.selected_administrator?,
        goal: decision.problem.clone()?,
    }))).collect();
    for (id,d) in decisions { world.resource_mut::<StrategyState>().factions.get_mut(&id).unwrap().head = Some(d); }
    if mode == Mode::Execute {
        world.insert_resource(Grants(grants));
        // Gate checks, not call order, decide which administrator can fund work.
        super::run_cycle(world,board,relations,tick,mult);
        construction::run_cycle(world,board,relations,events,tick,mult);
        world.remove_resource::<Grants>();
        let approved: Vec<_> = world.resource::<StrategyState>().factions.iter().filter_map(|(id, view)| {
            matches!(view.head.as_ref()?.selected_option, "found_colony" | "supply_colony").then(|| id.clone())
        }).collect();
        for id in approved {
            colony::commission(world, board, events, &id, &colonies[&id], tick, mult);
        }
        let mut state = world.resource_mut::<StrategyState>();
        for (id,view) in &mut state.factions {
            let committed: i64 = board.iter().filter(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
                matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG) | Some(colony::PROJECT_TAG)))
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
        {
            let mut market = w.get_mut::<MarketPricing>(port).unwrap();
            market.demand = [(Commodity::Food, 50.0), (Commodity::Ore, 200.0)].into();
            market.prices = [(Commodity::Food, 18.0), (Commodity::Ore, 15.0)].into();
        }
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
        assert_eq!(head.reason,"best_projected_relief"); assert_eq!(head.planned_spend,1600); assert_eq!(head.committed_spend,1600);
        // Shadow advisor is an observation only: it must not replace the native grant.
        let shadow = head.shadow_portfolio.as_ref().expect("positive portfolio option");
        assert_eq!(shadow.mode, "shadow_only");
        assert!(shadow.compared_valid_options > 0);
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
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks = HashMap::new();
        {
            let mut market = w.get_mut::<MarketPricing>(port).unwrap();
            market.supply.insert(Commodity::Water, 600.0);
            market.prices.insert(Commodity::Food, 500.0);
        }
        run_cycle(&mut w,&mut b,&relations,&mut events,60,1);
        let head = w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.reason,"best_projected_relief");
        assert_eq!(head.selected_administrator,Some("construction"));
        assert_eq!(head.committed_spend,10_000); assert_eq!(b.iter().count(),1);
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,70_000);
        // An in-flight construction shipment does not prevent useful logistics next cycle.
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks.insert(Commodity::Ore, 50);
        run_cycle(&mut w,&mut b,&relations,&mut events,120,1);
        assert_eq!(b.iter().count(),2);
        assert_eq!(w.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().selected_administrator,Some("logistics"));
        assert_eq!(w.get::<FactionData>(owner).unwrap().treasury,68_400);
    }
    #[test]
    fn strategy_block_head_shadow_matches_execution_and_respects_budget_floor() {
        let (mut w,mut b,owner,port,_) = fixture(); let mut events = Vec::new(); let relations = FactionRelations::new();
        w.get_mut::<MarketHistory>(port).unwrap().shortage_ticks = [(Commodity::Ore,1000)].into();
        w.get_mut::<MarketPricing>(port).unwrap().prices.insert(Commodity::Ore, 500.0);
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
    fn strategy_block_head_grant_executes_the_specific_problem() {
        let (mut world, mut board, _, port, _) = fixture();
        // Food has the oldest recorded shortage and an affordable source.
        // At decision time the local stock already covers the horizon.
        world.get_mut::<MarketPricing>(port).unwrap().supply.insert(Commodity::Food, 1000.0);
        run_cycle(&mut world, &mut board, &FactionRelations::new(), &mut Vec::new(), 60, 1);
        let view = &world.resource::<StrategyState>().factions["own"];
        let head = view.head.as_ref().unwrap();
        assert_eq!(head.selected_option, "deliver");
        assert_eq!(head.problem.as_ref().unwrap().commodity, Commodity::Ore);
        assert_eq!(head.committed_spend, 1600);
        let contracts: Vec<_> = board.iter().collect();
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].commodity, Commodity::Ore);
        assert_eq!(contracts[0].destination_location, head.problem.as_ref().unwrap().destination);
    }

    #[test]
    fn strategy_block_head_compares_build_deliver_and_wait_for_same_problem() {
        let (mut world, mut board, owner, port, source) = fixture();
        world.resource_mut::<StrategyState>().mode = Mode::Shadow;
        world.get_mut::<MarketHistory>(port).unwrap().shortage_ticks =
            [(Commodity::Ore, 1000)].into();
        world.get_mut::<MarketPricing>(port).unwrap().prices.insert(Commodity::Ore, 500.0);
        let relations = FactionRelations::new();
        let mut events = Vec::new();

        run_cycle(&mut world, &mut board, &relations, &mut events, 60, 1);
        let head = world.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.selected_option, "build");
        assert_eq!(head.problem.as_ref().unwrap().commodity, Commodity::Ore);
        assert_eq!(head.alternatives.len(), 3);
        let build = head.alternatives.iter().find(|a| a.action == "build").unwrap();
        assert_eq!(build.total_commitment, 50_150);
        assert_eq!(build.treasury_after, 29_850);

        // Same problem and supplies. This treasury can pay a shipment or
        // the first building lot but cannot finish and commission the site.
        world.get_mut::<FactionData>(owner).unwrap().treasury = 40_000;
        run_cycle(&mut world, &mut board, &relations, &mut events, 120, 1);
        let head = world.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.selected_option, "deliver");
        assert_eq!(head.alternatives.iter().find(|a| a.action == "build").unwrap().reason,
            "insufficient_project_budget");

        world.get_mut::<MarketPricing>(source).unwrap().prices.insert(Commodity::Ore, 500.0);
        run_cycle(&mut world, &mut board, &relations, &mut events, 180, 1);
        let head = world.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.selected_option, "wait");
        assert_eq!(head.committed_spend, 0);
        assert!(board.iter().next().is_none());

        // A viable source alone does not justify spending if the local
        // stock covers the forecast demand, even with stale shortage age.
        world.get_mut::<MarketPricing>(source).unwrap().prices.insert(Commodity::Ore, 1.0);
        world.get_mut::<MarketPricing>(port).unwrap().supply.insert(Commodity::Ore, 3000.0);
        run_cycle(&mut world, &mut board, &relations, &mut events, 240, 1);
        let head = world.resource::<StrategyState>().factions["own"].head.as_ref().unwrap();
        assert_eq!(head.selected_option, "wait");
        assert!(head.alternatives.iter().any(|a| a.reason == "no_projected_shortage_relief"));
    }
}
