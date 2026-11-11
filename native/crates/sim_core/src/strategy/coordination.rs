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
/// Observable relationship between a player policy and what the native head
/// actually selected. No second decision maker and no inferred completion.
#[derive(Clone, Debug, Serialize)]
pub struct PolicyImpact {
    pub department: &'static str,
    pub mode: governance::MandateMode,
    pub target: String,
    pub priority: Option<u8>,
    pub selected: bool,
    pub status: &'static str,
    pub reason: String,
    pub funded_contract_id: Option<String>,
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
    /// What player directives did to this head decision (or why not).
    /// A policy in advise/hold mode is visible but cannot issue paid orders.
    pub policy_impacts: Vec<PolicyImpact>,
    /// Legacy decision expressed in the shared planner contract; diagnostic only.
    pub planning_shadow: Option<planning::ShadowTrace>,
    /// Real native planning dispatch (legacy key retained for Observer compatibility):
    /// planner_id/mode distinguish HTN and hybrid. Forecasts are not receipts.
    #[serde(skip_serializing_if="Option::is_none")]
    pub htn_execution: Option<planning::NativeDriveReport>,
}
struct Grant {
    administrator: &'static str,
    goal: Goal,
}

#[derive(Resource)]
struct Grants(BTreeMap<String, Grant>);

/// A player's grant is not interchangeable with an autonomous shortage of
/// the same commodity at the same station. Construction is the one allowed
/// alias: an existing site's "expand_production" goal continues the very
/// same player industry target. All other player-policy identity is exact.
fn granted_goal_matches(grant: &Goal, goal: &Goal, administrator: &str) -> bool {
    if !options::same_problem(grant, goal) {return false;}
    match grant.goal_id.as_str() {
        "player_supply" => goal.goal_id=="player_supply",
        "player_industry" => administrator=="construction" &&
            matches!(goal.goal_id.as_str(), "player_industry"|"expand_production"),
        _ => !goal.goal_id.starts_with("player_"),
    }
}
pub(super) fn authorized(world: &World, faction: &str, administrator: &str, goal: &Goal) -> bool {
    world.get_resource::<Grants>().is_none_or(|grants| {
        grants.0.get(faction).is_some_and(|grant| {
            grant.administrator == administrator &&
                granted_goal_matches(&grant.goal, goal, administrator)
        })
    })
}

fn decision(
    view: &FactionView, sources: &sourcing::Sources<'_>, tick: u64,
    mult: u32, already_commissioned: bool, commander:Option<&director::Commander>,
    retained:Option<options::Comparison>,
) -> HeadDecision {
    let limit = view.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR).max(0);
    let comparison = retained.or_else(||commander.map_or_else(||options::compare(view,sources,mult),
        |c|options::compare_director(view,sources,mult,c)));
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
        policy_impacts:Vec::new(),planning_shadow: None, htn_execution: None,
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
    director::observe(world,board,tick,mult);
    if mode==Mode::Execute {director::environmental_events(world,tick,mult);}
    let commanders=world.get_resource::<director::Director>().map(|d|d.commanders.clone()).unwrap_or_default();
    let research_ready:std::collections::HashSet<String>=commanders.keys().filter(|id|director::research_ready(world,id,tick)).cloned().collect();
    let mut colonies = colony::proposals(world, board, relations);
    // Established colonies are not just a founding event. Observe their
    // actual households, local resources and staffed native modules.
    let colony_views = colony_development::observe(world, board);
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
    let migration_plans = colony_development::migration_proposals(world, board, &colony_views);
    let colony_stock_goals:BTreeMap<String,Goal> = world.query::<&FactionData>().iter(world)
        .filter_map(|f| colony_development::next_supply_goal(&colony_views,board,&f.id)
            .map(|g|(f.id.clone(),g))).collect();
    let owners = crate::agents::faction_relations::market_controllers(world);
    // Own a stable snapshot rather than borrowing ECS World throughout
    // the director's evaluation. Native orders still revalidate live prices.
    let market_snapshot: Vec<(String, MarketPricing)> = {
        let mut query = world.query::<(&MarketIdentity, &MarketPricing)>();
        query.iter(world).map(|(id, market)|
            (id.facility_location.clone(), market.clone())).collect()
    };
    let sources = sourcing::Sources::new(
        market_snapshot.iter().map(|(location, market)| (location.as_str(), market)),
        owners, relations,
    );
    let mut decisions: Vec<_> = world.resource::<StrategyState>().factions.iter().map(|(id,view)| {
        let already = board.iter().any(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
            matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG) |
                Some(colony::PROJECT_TAG) | Some(colony_development::MIGRATION_TAG)));
        // Ordinary autonomy must not accidentally choose an unapproved
        // player proposal merely because it is in the preview goal list.
        // The mandate is evaluated separately below with its exact quote,
        // permissions, and budget. Keep unrelated native alternatives.
        let mut baseline=view.clone();
        baseline.goals.retain(|g|!g.goal_id.starts_with("player_"));
        if let Some(construction)=baseline.construction.as_mut(){
            construction.offers.retain(|o|!o.goal.goal_id.starts_with("player_"));
        }
        (id.clone(),decision(&baseline,&sources,tick,mult,already,commanders.get(id),None))
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
        if !commanders.contains_key(id) && ready && head.reason != "already_commissioned_this_tick"
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
    // The leader decides a durable *goal* here. Planner mode (HTN/GOAP/Beam)
    // affects only how that goal is satisfied and must not rewrite this vote.
    let native_active:std::collections::HashSet<String>=world.get_resource::<director::Director>()
        .map(|d|d.ai_execution.active.keys().cloned().collect()).unwrap_or_default();
    let switch_policy=director::strategy_switch_policy();
    let economic_intents=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    // Captured only from genuine READY native alternatives, before native
    // administrators charge money. Never auto-approve a proposal.
    let mut specific_offers=Vec::<(
        String,super::economic_mandate::EconomicMandate,String,i64,i64
    )>::new();
    // Only a fully authorized quote may influence the head's scoring.
    let mut authorized_mandates=std::collections::HashSet::<String>::new();
    for (id,head) in &mut decisions {
        let Some(c)=commanders.get(id) else{continue;};
        // A funded native plan owns its sequence until receipts finish. Even a
        // newly urgent intent must not silently cancel escrow, cargo or work.
        // This explicitly blocks a *second* head grant for the same cycle;
        // the native driver below still advances the outstanding plan.
        if mode==Mode::Execute && planning::execution_enabled() && native_active.contains(id) {
            head.selected_option="wait";
            head.selected_administrator=None;
            head.problem=None;
            head.planned_spend=0;
            head.reason="outstanding_native_plan_retained".into();
            if let Some(memory)=world.resource_mut::<director::Director>().commanders.get_mut(id) {
                memory.strategic.pending=None;
                memory.strategic.reason="outstanding_native_plan_retained".into();
            }
            continue;
        }
        if head.reason=="already_commissioned_this_tick"{continue;}
        if !c.crisis {
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
                            .map_or(0,|a|a.total_commitment.max(a.first_payment));
                        let ready=comparison.alternatives.iter().any(|a|
                            a.action==comparison.selected && a.status=="ready");
                        let quoted_action=comparison.selected.to_string();
                        if ready && super::economic_proposal::can_offer(
                            world,id,m,charge,view.treasury) {
                            specific_offers.push((id.clone(),m.clone(),
                                quoted_action.clone(),charge,view.treasury));
                        }
                        if super::economic_mandate::may_commission(
                            m,view.treasury,charge).is_ok() &&
                            super::economic_proposal::authorize_action(
                                world,id,m,&quoted_action,charge,view.treasury,tick).is_ok() {
                            *head=decision(view,&sources,tick,mult,false,Some(c),
                                Some(comparison));
                            head.reason="player_economic_mandate".into();
                            authorized_mandates.insert(id.clone());
                        }
                    }
                }
            }
        }
        let native_score=head.problem.as_ref().and_then(|g|head.alternatives.iter()
            .find(|a|a.action==head.selected_option)
            .map(|a|director::option_score(c,g,a))).unwrap_or(0.0).max(0.0);
        let economic_selected=authorized_mandates.contains(id) &&
            head.problem.as_ref().is_some_and(|g|
                economic_intents.get(id).is_some_and(|m|
                    m.active() && g.goal_id==m.goal_id() &&
                    g.destination==m.location && g.commodity==m.commodity));
        let native_score=if economic_selected&&!c.crisis {
            native_score.max(super::charter::priority_score(
                world,id,super::charter::Department::Economy,160.0))
        }else{native_score};
        let native_target=head.problem.as_ref().map(director::supply_target);
        // Player directives choose a strategic PRIORITY, not native
        // actions. Life support and outstanding prepaid plans still win.
        let delegated_science=super::governance::active(world,id).is_some_and(|m|
            m.mode==super::governance::MandateMode::Delegated) &&
            super::charter::may_direct(world,id,super::charter::Department::Research);
        let research=if research_ready.contains(id)&&!c.crisis {
            18.0*c.profile.science+if c.strategic.kind=="research"{2.0}else{0.0}
                +if delegated_science{super::charter::priority_score(
                    world,id,super::charter::Department::Research,160.0)}else{0.0}
        }else{-1.0};
        let expansion=colonies.get(id).filter(|p|p.reason=="ready"&&(!c.crisis||p.site_id.is_some()))
            .map(|p|if p.site_id.is_some(){80.0}else{25.0*c.profile.expansion}).unwrap_or(-1.0);
        let expansion_target=colonies.get(id).map(|p|director::supply_target(&p.goal));
        let migration=migration_plans.get(id).filter(|_|!c.crisis);
        let migration_score=if migration.is_some(){60.0}else{-1.0};
        let mut candidates=vec![director::Candidate{
            action:"supply".into(),target:native_target.clone(),score:native_score,
            available:head.selected_option!="wait"&&native_score>0.0,reason:head.reason.clone()},
            director::Candidate{action:"research".into(),target:c.research.clone(),score:research,
                available:research>0.0,reason:if c.crisis{"survival_first"}else if research<=0.0{
                    "research_resources_unavailable"}else{"paid_science_available"}.into()},
            director::Candidate{action:"expand".into(),target:expansion_target.clone(),score:expansion,
                available:expansion>0.0,reason:colonies.get(id).map_or("no_colony_target",|p|p.reason).into()},
            director::Candidate{action:"migrate".into(),target:migration.map(|p|p.destination.clone()),
                score:migration_score,available:migration.is_some(),
                reason:if c.crisis{"survival_first"}else if migration.is_some(){"colony_needs_workers"}
                    else{"no_funded_passenger_route"}.into()}];
        // A previously committed supply target may still be fully feasible
        // even if it was not today's highest-scoring shortage. Re-evaluate it
        // using the current market and grants rather than stale stored data.
        let previous_supply=c.strategic.target.as_deref().filter(|_|c.strategic.kind=="supply")
            .filter(|target|Some(*target)!=native_target.as_deref())
            .and_then(|target|world.resource::<StrategyState>().factions.get(id)
                .and_then(|view|options::compare_director_target(view,&sources,mult,c,target)));
        if let Some(old)=&previous_supply {
            let score=old.alternatives.iter().find(|a|a.action==old.selected)
                .map(|a|director::option_score(c,&old.goal,a)).unwrap_or(0.0).max(0.0);
            candidates.push(director::Candidate{action:"supply".into(),
                target:Some(director::supply_target(&old.goal)),score,available:score>0.0,
                reason:"previous_supply_still_feasible".into()});
        }
        candidates.sort_by(|a,b|b.score.total_cmp(&a.score)
            .then_with(||a.action.cmp(&b.action)).then_with(||a.target.cmp(&b.target)));
        // No mutation until all alternatives have been evaluated. The same
        // planning cycle cannot count as two hysteresis confirmations.
        let mut strategic=c.strategic.clone();
        let previous_target=previous_supply.as_ref().map(|old|director::supply_target(&old.goal));
        let current_essential=head.problem.as_ref().is_some_and(|g|
            matches!(g.commodity,Commodity::Food|Commodity::Water));
        let old_essential=previous_supply.as_ref().is_some_and(|old|
            matches!(old.goal.commodity,Commodity::Food|Commodity::Water));
        let survival=c.crisis && candidates.iter().any(|a|a.action=="supply"&&a.available &&
            ((current_essential && a.target==native_target) ||
             (old_essential && a.target.as_deref()==previous_target.as_deref())));
        // Priority of a *survival* supply alternative must outrank benign
        // strategy choices, but it still needs a valid native option.
        let funded_native_order=board.iter().any(|contract|
            contract.requestor_id==*id &&
            contract.funding.as_ref().is_some_and(|f|f.reserved>0) &&
            !matches!(contract.status,ContractStatus::Paid|ContractStatus::Expired) &&
            matches!(contract.mission_category.as_deref(),
                Some(PROJECT_TAG)|Some(construction::PROJECT_TAG)|
                Some(colony::PROJECT_TAG)|Some(colony_development::MIGRATION_TAG)));
        // A NEW, legally approved player priority should be acted on at the
        // next cycle if it is the highest-ranked choice. Autonomous inertia
        // (two-cycle hysteresis) still governs all other strategy changes.
        // Never displace an existing funded physical commitment or crisis.
        let player_top=economic_selected && !c.crisis &&
            !native_active.contains(id) && !funded_native_order &&
            candidates.first().is_some_and(|choice|
                choice.available && choice.action=="supply" &&
                choice.target==native_target);
        let needs_switch=player_top &&
            (strategic.kind!="supply" || strategic.target!=native_target);
        let chosen=if needs_switch {
            Some(director::accept_authorized_player_priority(
                &mut strategic,&candidates[0],tick))
        }else{
            director::retain_or_switch(&mut strategic,&candidates,tick,survival,
                native_active.contains(id)||funded_native_order,switch_policy)
        };
        if let Some((choice,decision_reason))=chosen {
            match choice.action.as_str() {
                "research" => {
                    head.selected_option="research";head.selected_administrator=None;
                    head.problem=None;head.planned_spend=0;
                    head.reason=decision_reason.into();
                },
                "migrate" => {
                    if let Some(plan)=migration_plans.get(id) {
                        head.selected_option="migrate_colony";head.selected_administrator=None;
                        head.problem=None;head.planned_spend=plan.payment;
                        head.reason="colony_workforce_needed".into();
                    }
                },
                "expand" => {
                    if let Some(p)=colonies.get(id) {
                        head.selected_option=if p.site_id.is_some(){"supply_colony"}else{"found_colony"};
                        head.selected_administrator=Some("construction");
                        head.problem=Some(p.goal.clone());head.planned_spend=p.cost;
                        head.reason=decision_reason.into();
                    }
                },
                "supply" => {
                    if choice.target!=native_target {
                        if let Some(old)=previous_supply {
                            if let Some(view)=world.resource::<StrategyState>().factions.get(id) {
                                let mut restored=decision(view,&sources,tick,mult,false,Some(c),Some(old));
                                if let Some(p)=colonies.get(id) {
                                    restored.proposals.push(Proposal{
                                        administrator:"construction",goal:Some(p.goal.clone()),
                                        status:if p.reason=="ready"{"proposed"}else{"blocked"}.into(),
                                        reason:p.reason.into(),requested_credits:p.cost,priority:1,
                                    });
                                }
                                *head=restored;
                            }
                        }
                    }
                    head.reason=if c.crisis && head.problem.as_ref().is_some_and(|g|
                        matches!(g.commodity,Commodity::Food|Commodity::Water)) {
                        "urgent_life_support".into()
                    }else if c.strategic.kind.is_empty() && decision_reason=="previous_goal_unavailable" {
                        head.reason.clone()
                    }else{decision_reason.into()};
                },
                _ => {},
            }
        } else {
            strategic.pending=None;
            strategic.score=0.0;
            strategic.reason="no_feasible_strategic_choice".into();
            if c.crisis {head.reason="survival_no_feasible_proposal".into();}
        }
        let mut d=world.resource_mut::<director::Director>();
        let memory=d.commanders.get_mut(id).unwrap();
        // Shadow only projects a decision: it must not advance the two-cycle
        // confirmation counter or overwrite an actual strategic commitment.
        if mode==Mode::Execute { memory.strategic=strategic; }
        if memory.intent!=head.selected_option {memory.since=tick;memory.intent=head.selected_option.into();}
        memory.reason=head.reason.clone();memory.candidates=candidates;
        director::record(memory,tick,head.selected_option,&head.reason,"selected");
    }
    for (id,head) in &mut decisions {
        if let (Some(g),Some(m))=(head.problem.as_ref(),economic_intents.get(id)) {
            if g.goal_id==m.goal_id() && g.destination==m.location &&
                g.commodity==m.commodity {
                if m.kind==super::economic_mandate::EconomicKind::Industry &&
                    head.selected_option!="build" {
                    // Industrial mandate must not silently degrade into
                    // a one-off imported delivery. Native construction
                    // administrator must physically build a producer.
                    head.problem=None;
                    head.selected_option="wait";
                    head.selected_administrator=None;
                    head.planned_spend=0;
                    head.reason="industry_requires_native_build".into();
                    continue;
                }
                let charge=head.alternatives.iter()
                    .find(|a|a.action==head.selected_option)
                    .map_or(0,|a|a.total_commitment.max(a.first_payment));
                let treasury=head.treasury_before;
                if super::economic_mandate::may_commission(m,treasury,charge).is_err() ||
                    super::economic_proposal::authorize_action(
                        world,id,m,&head.selected_option,charge,treasury,tick).is_err() {
                    head.problem=None;
                    head.selected_option="wait";
                    head.selected_administrator=None;
                    head.planned_spend=0;
                    head.reason=super::economic_proposal::authorize_action(
                        world,id,m,&head.selected_option,charge,treasury,tick)
                        .err().unwrap_or("player_mandate_budget_or_reserve_blocked").into();
                }
            }
        }
    }
    // A founded colony takes precedence over speculative new expansion when
    // actual essential stock is low. Give HTN/hybrid a REAL market stock goal;
    // the old head is retained as a fallback if no physical plan exists.
    // A native prepaid plan is NEVER replaced mid-flight.
    let mut colony_fallbacks=BTreeMap::<String,HeadDecision>::new();
    if mode==Mode::Execute && planning::execution_enabled() {
        for (id,head) in &mut decisions {
            if native_active.contains(id) || head.reason=="already_commissioned_this_tick" {continue;}
            let Some(goal)=colony_stock_goals.get(id) else{continue;};
            let essential=goal.goal_id=="colony_life_support";
            if !essential && !matches!(head.selected_option,"wait" | "migrate_colony") {continue;}
            colony_fallbacks.insert(id.clone(),head.clone());
            head.problem=Some(goal.clone());
            head.selected_option="wait";
            head.selected_administrator=None;
            head.planned_spend=0;
            head.reason=if essential {"colony_life_support_native_goal"}
                else {"colony_industrial_chain_native_goal"}.into();
        }
    }
    // HTN and hybrid are explicitly opt-in. All money, orders, ships and materials still
    // belong to Genesis. Active plans suppress a competing legacy head grant;
    // unsupported snapshots fall back to the old director without mutation.
    if mode == Mode::Execute && planning::execution_enabled() {
        for (id, head) in &mut decisions {
            let colony_priority=head.reason=="colony_life_support_native_goal" ||
                head.reason=="colony_industrial_chain_native_goal";
            if let Some(report) = planning::drive_native_htn(world, board, relations, tick, mult, id, head) {
                let dispatch_kind = if report.mode == "native_hybrid_opt_in" {"hybrid_native"} else {"htn_native"};
                head.selected_option = dispatch_kind;
                head.selected_administrator = None;
                head.planned_spend = report.committed_credits;
                head.reason = report.reason.clone();
                if let Some(c) = world.resource_mut::<director::Director>().commanders.get_mut(id) {
                    c.intent = dispatch_kind.into();
                    c.reason = report.reason.clone();
                    if colony_priority {
                        if let Some(goal)=head.problem.as_ref() {
                            c.strategic.kind="supply".into();
                            c.strategic.target=Some(director::supply_target(goal));
                            c.strategic.since=tick;
                            c.strategic.reason="colony_life_support_native_goal".into();
                            c.strategic.pending=None;
                        }
                    }
                    director::record(c, tick, dispatch_kind, &report.reason, &report.status);
                }
                head.htn_execution = Some(report);
            } else if let Some(previous)=colony_fallbacks.remove(id) {
                // No dispatched native plan. Do not suppress the previously
                // available funded Genesis option or claim colony success.
                *head=previous;
            }
        }
    }
    // A read-only baseline projection after the director finalises its choice.
    // The native grant/dispatch below remains the only source of actual orders.
    if planning::shadow_enabled() {
        for (id, head) in &mut decisions {
            head.planning_shadow = Some(planning::native_decision_shadow(world, board, tick, id, head));
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
        let migrants:Vec<_>=world.resource::<StrategyState>().factions.iter()
            .filter(|(_,v)|v.head.as_ref().is_some_and(|h|h.selected_option=="migrate_colony"))
            .map(|(id,_)|id.clone()).collect();
        for id in migrants {
            if let Some(plan)=migration_plans.get(&id) {
                let payment=colony_development::commission(world,board,events,&id,plan,tick,mult);
                if payment>0 {
                    if let Some(head)=world.resource_mut::<StrategyState>().factions
                        .get_mut(&id).and_then(|v|v.head.as_mut()) {
                        head.reason="colony_migration_approved".into();
                    }
                }
            }
        }
        let science:Vec<_>=world.resource::<StrategyState>().factions.iter().filter(|(_,v)|v.head.as_ref().is_some_and(|h|h.selected_option=="research")).map(|(id,_)|id.clone()).collect();
        let mut science_spend=BTreeMap::new();
        for id in science {let result=director::research(world,&id,tick);science_spend.insert(id.clone(),result.as_ref().copied().unwrap_or(0));let reason=result.as_ref().err().copied().unwrap_or("paid_research_shift");
            if let Some(c)=world.resource_mut::<director::Director>().commanders.get_mut(&id){director::record(c,tick,"research",reason,if result.is_ok(){"executed"}else{"blocked"});}
        }
        // One receipt per actual sanctioned order; faction-wide tick totals
        // remain useful for display, but are NOT evidence of mandated spend.
        let mut mandate_receipts=Vec::<(String,i64,String,String)>::new();
        let mut state = world.resource_mut::<StrategyState>();
        for (id,view) in &mut state.factions {
            let committed: i64 = board.iter().filter(|c| c.requestor_id == *id && c.posted_at_tick == tick &&
                matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG) |
                    Some(colony::PROJECT_TAG) | Some(colony_development::MIGRATION_TAG)))
                .filter_map(|c| c.funding.as_ref()).map(|f| f.reserved).sum();
            if let Some(head) = &mut view.head {
                head.committed_spend=committed+science_spend.get(id).copied().unwrap_or(0);
                if head.selected_option=="research"{head.planned_spend=head.committed_spend;}
                if let (Some(goal),Some(m))=(head.problem.as_ref(),economic_intents.get(id)) {
                    if m.active() && goal.goal_id==m.goal_id() &&
                        goal.destination==m.location && goal.commodity==m.commodity {
                        // The chosen goal and action must agree with the
                        // administrator's *new* paid native contract. In
                        // particular, another faction project in this tick
                        // cannot consume a player's approval token.
                        let contract=match (m.kind,head.selected_option) {
                            (super::economic_mandate::EconomicKind::Supply,"deliver")=>
                                board.iter().find(|c| c.requestor_id==*id &&
                                    c.posted_at_tick==tick &&
                                    c.contract_type==crate::economy::contracts::ContractType::Subsidy &&
                                    c.mission_category.as_deref()==Some(PROJECT_TAG) &&
                                    c.destination_location==m.location &&
                                    c.commodity==m.commodity),
                            (super::economic_mandate::EconomicKind::Industry,"build")=>
                                view.construction.as_ref()
                                    .filter(|cv|cv.status=="commissioned" &&
                                        cv.selected_goal.as_ref().is_some_and(|g|
                                            g.destination==m.location &&
                                            g.commodity==m.commodity))
                                    .and_then(|cv|cv.contract_id.as_ref())
                                    .and_then(|contract_id|board.get(contract_id))
                                    .filter(|c| c.requestor_id==*id &&
                                        c.posted_at_tick==tick &&
                                        c.contract_type==crate::economy::contracts::ContractType::Construction &&
                                        c.mission_category.as_deref()==Some(construction::PROJECT_TAG) &&
                                        c.destination_location==m.location),
                            _=>None,
                        };
                        if let Some(c)=contract {
                            if let Some(funding)=c.funding.as_ref().filter(|f|
                                f.source==FundingSource::Faction && f.reserved>0) {
                                mandate_receipts.push((id.clone(),funding.reserved,
                                    c.id.clone(),head.selected_option.into()));
                            }
                        }
                    }
                }
            }
        }
        drop(state);
        for (id,actual_paid,contract_id,action) in mandate_receipts {
            super::economic_mandate::actual_commit(
                world,&id,actual_paid,&contract_id,&action,tick);
        }
    }
    // Expose physical blockers or verified local stock, not a simulated
    // success event. This runs AFTER the native administrator/driver cycle.
    super::economic_proposal::expire(world,tick);
    for (id,mandate,action,quote,treasury) in specific_offers {
        // Keep the receipt of an already funded delivery visible while the
        // native carrier is still working. Replacing it with a new offer
        // would destroy the player's only durable proposal->contract link.
        let outstanding=world.get_resource::<director::Director>()
            .and_then(|d|d.economic_proposals.get(&id))
            .filter(|p|p.status==super::economic_proposal::ProposalStatus::Consumed)
            .and_then(|p|p.funded_contract_id.as_deref())
            .and_then(|contract_id|board.get(contract_id))
            .is_some_and(|c|!matches!(c.status,ContractStatus::Paid|ContractStatus::Expired));
        if !outstanding {
            super::economic_proposal::publish(
                world,&id,&mandate,&action,quote,treasury,tick);
        }
    }
    let actual_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    let actual_economic_stocks:std::collections::HashMap<String,MarketPricing>=
        world.query::<(&MarketIdentity,&MarketPricing)>().iter(world)
            .map(|(id,market)|(id.facility_location.clone(),market.clone())).collect();
    let head_reasons:std::collections::HashMap<String,(String,String)>=
        world.resource::<StrategyState>().factions.iter().filter_map(|(id,view)|
            view.head.as_ref().map(|head|(id.clone(),(
                head.selected_option.to_string(),head.reason.clone())))).collect();
    let life_support_blockers:std::collections::HashSet<String>=
        world.get_resource::<director::Director>()
            .map(|d|d.commanders.iter().filter(|(_,c)|c.crisis)
                .map(|(id,_)|id.clone()).collect()).unwrap_or_default();
    for (id,m) in actual_economic_mandates {
        if m.last_commitment_tick==Some(tick) {continue;}
        let market=actual_economic_stocks.get(&m.location);
        let supply=market.map(|p|p.supply.get(&m.commodity).copied().unwrap_or(0.0));
        let active=board.iter().any(|contract|
            contract.requestor_id==id && contract.destination_location==m.location &&
            contract.commodity==m.commodity &&
            !matches!(contract.status,ContractStatus::Paid|ContractStatus::Expired));
        let reason=if m.mode==super::governance::MandateMode::Hold {
            "mandate_on_hold".to_owned()
        }else if m.mode==super::governance::MandateMode::Advise {
            "advisory_only".to_owned()
        }else if market.is_none(){
            "market_unavailable".to_owned()
        }else if m.kind==super::economic_mandate::EconomicKind::Industry &&
            super::economic_mandate::native_producer_exists(
                world,&id,&m.location,m.commodity) {
            // Built capacity is an ECS fact; actual production shifts and
            // their input/wage payment are independent receipts.
            "native_producer_present_actual_output_unverified".to_owned()
        }else if m.kind==super::economic_mandate::EconomicKind::Supply &&
            supply.is_some_and(|n|n.is_finite()&&n>=m.min_stock as f32) {
            "observed_stock_target_reached".to_owned()
        }else if life_support_blockers.contains(&id){
            "life_support_overrides_player_policy".to_owned()
        }else if active {
            "native_delivery_in_progress_not_completed".to_owned()
        }else {
            let payment=if m.kind==super::economic_mandate::EconomicKind::Supply{
                faction::SUBSIDY_BASE_PAYMENT*2
            }else{faction::CONSTRUCTION_BASE_PAYMENT};
            let treasury=world.query::<&FactionData>().iter(world)
                .find(|f|f.id==id).map_or(0,|f|f.treasury);
            match super::economic_mandate::may_commission(&m,treasury,payment)
                .and_then(|_|super::charter::authorize(world,&id,
                    super::charter::Department::Economy,payment,treasury)) {
                Err(r)=>r.to_owned(),
                Ok(())=>{
                    let (choice,why)=head_reasons.get(&id).cloned().unwrap_or_default();
                    if choice=="wait"||choice.is_empty() {
                        format!("waiting_native_administrator:{why}")
                    }else{
                        format!("native_administrator_chose:{choice}")
                    }
                }
            }
        };
        super::economic_mandate::status(world,&id,&reason);
    }
    // Read-only policy audit after all native grants and paid receipts.
    // Delegated, advisory, and hold modes are distinct even when the AI
    // independently chooses a similar supply or research objective.
    let impacts:Vec<_>=world.get_resource::<director::Director>().map(|d|
        d.commanders.keys().map(|id|{
            let head=world.resource::<StrategyState>().factions.get(id)
                .and_then(|v|v.head.as_ref());
            let charter=d.faction_charters.get(id);
            let mut items=Vec::new();
            if let Some(m)=d.economic_mandates.get(id) {
                let selected=head.is_some_and(|h|h.problem.as_ref().is_some_and(|g|
                    g.goal_id==m.goal_id() && g.destination==m.location &&
                    g.commodity==m.commodity) &&
                    matches!((m.kind,h.selected_option),
                        (super::economic_mandate::EconomicKind::Supply,"deliver")|
                        (super::economic_mandate::EconomicKind::Industry,"build")));
                let proposal=d.economic_proposals.get(id);
                let funded=proposal.and_then(|p|p.funded_contract_id.clone());
                let status=if m.mode==governance::MandateMode::Hold {"hold"}
                    else if m.mode==governance::MandateMode::Advise {"advisory"}
                    else if charter.is_some_and(|c|c.economy_authority==charter::Authority::Autonomous)
                        {"charter_autonomous"}
                    else if d.commanders.get(id).is_some_and(|c|c.crisis) {"survival_override"}
                    else if funded.is_some() {"native_contract_linked"}
                    else if selected {"selected_by_head"}
                    else if proposal.is_some_and(|p|p.status==super::economic_proposal::ProposalStatus::Pending)
                        {"awaiting_specific_approval"}
                    else {"not_selected"};
                items.push(PolicyImpact{
                    department:"economy",mode:m.mode,
                    target:format!("{} · {} · {}",m.goal_id(),m.location,m.commodity.as_str()),
                    priority:charter.map(|c|c.economy_priority),
                    selected: selected && m.mode==governance::MandateMode::Delegated,
                    status,reason:m.last_reason.clone(),funded_contract_id:funded,
                });
            }
            if let Some(m)=d.research_mandates.get(id) {
                let selected=head.is_some_and(|h|h.selected_option=="research") &&
                    m.mode==governance::MandateMode::Delegated &&
                    charter.is_none_or(|c|c.research_authority!=charter::Authority::Autonomous);
                let status=if m.mode==governance::MandateMode::Hold {"hold"}
                    else if m.mode==governance::MandateMode::Advise {"advisory"}
                    else if charter.is_some_and(|c|c.research_authority==charter::Authority::Autonomous)
                        {"charter_autonomous"}
                    else if d.commanders.get(id).is_some_and(|c|c.crisis) {"survival_override"}
                    else if selected {"selected_by_head"}
                    else {"not_selected"};
                items.push(PolicyImpact{department:"research",mode:m.mode,
                    target:m.target_technology.clone(),
                    priority:charter.map(|c|c.research_priority),
                    selected,status,reason:m.last_reason.clone(),funded_contract_id:None});
            }
            (id.clone(),items)
        }).collect()
    ).unwrap_or_default();
    for (id,items) in impacts {
        if let Some(head)=world.resource_mut::<StrategyState>().factions.get_mut(&id)
            .and_then(|v|v.head.as_mut()) {
            head.policy_impacts=items;
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
    fn planner_shadow_is_read_only_and_projects_a_real_native_step() {
        let (mut world, mut board, owner, _, _) = fixture();
        let mut events = Vec::new();
        let relations = FactionRelations::new();
        run_cycle(&mut world, &mut board, &relations, &mut events, 600, 1);
        let head = world.resource::<StrategyState>().factions["own"].head.as_ref().unwrap().clone();
        let treasury_before = world.get::<FactionData>(owner).unwrap().treasury;
        let contracts_before = board.iter().count();
        let trace = planning::native_decision_shadow(&mut world, &board, 600, "own", &head);
        assert_eq!(trace.mode, "diagnostic_only");
        assert_eq!(trace.faction_id, "own");
        assert_eq!(trace.selected_native_action, "deliver");
        assert_eq!(trace.status, "projected_first_step");
        assert_eq!(trace.validation, "valid");
        assert!(trace.proposal.as_ref().is_some_and(|p| p.planner_id == "genesis_baseline"));
        assert_eq!(trace.htn.as_ref().map(|h|h.mode), Some("read_only_real_genesis_snapshot"));
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury, treasury_before);
        assert_eq!(board.iter().count(), contracts_before);
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
