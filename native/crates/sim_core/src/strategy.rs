//! First head -> logistics administrator -> native contract execution slice.
//! Read-only projections are rebuilt from ECS/board; money lives in native accounts.
use bevy_ecs::prelude::*;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use crate::agents::{faction::{self, FactionData}, facility::{FacilityIdentity, FacilityLocation},
    market::{MarketIdentity, MarketHistory, MarketPricing}, faction_relations::FactionRelations};
use crate::economy::{commodities::Commodity, contracts::{ContractBoard, ContractStatus, FundingSource}};

pub mod director;
pub mod progression;
pub mod governance;
pub mod economic_mandate;
pub mod charter;
pub mod planning;
pub mod construction;
pub mod colony;
pub mod colony_development;
pub mod station;
pub mod orders;
pub mod coordination;
mod options;
mod portfolio_policy;
pub mod production_dependencies;
pub(crate) mod sourcing;

pub const PROJECT_TAG: &str = "strategy.logistics.v1";
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode { #[default] Shadow, Execute }
#[derive(Clone, Debug, Serialize)]
pub struct Goal {
    pub goal_id: String,
    pub commodity: Commodity,
    pub destination: String,
    pub shortage_ticks: u32,
    pub score: f32,
}
#[derive(Clone, Debug, Serialize)]
pub struct Project {
    pub project_id: String,
    pub contract_id: String,
    pub administrator: &'static str,
    pub state: String,
    pub executor_id: Option<String>,
    pub reserved_credits: i64,
    pub source: String,
    pub destination: String,
    pub commodity: Commodity,
    pub quantity: u32,
}
/// Exact native contract state associated with a shortage goal.
#[derive(Clone, Debug, Serialize)]
pub struct PendingDelivery {
    pub contract_id: String,
    pub status: &'static str,
    pub source: String,
    pub quantity: u32,
    pub posted_at_tick: u64,
    pub age_ticks: u64,
    pub fulfiller_id: Option<String>,
    pub station_order_executor_id: Option<String>,
    pub station_order_blocked_reason: Option<String>,
    pub reserved_credits: i64,
}
impl PendingDelivery {
    fn from_native(c: &crate::economy::contracts::Contract, tick: u64) -> Self {
        let order = c.funding.as_ref().and_then(|f| f.station_order.as_ref());
        Self {
            contract_id: c.id.clone(),
            status: match c.status {
                ContractStatus::Posted => "posted",
                ContractStatus::Accepted => "accepted",
                ContractStatus::PickedUp => "picked_up",
                ContractStatus::Delivered => "delivered",
                ContractStatus::Paid => "paid",
                ContractStatus::Expired => "expired",
            },
            source: c.source_location.clone(),
            quantity: c.quantity,
            posted_at_tick: c.posted_at_tick,
            age_ticks: tick.saturating_sub(c.posted_at_tick),
            fulfiller_id: c.fulfiller_id.clone(),
            station_order_executor_id: order.and_then(|o| o.executor_id.clone()),
            station_order_blocked_reason: order.and_then(|o| o.blocked_reason.clone()),
            reserved_credits: c.funding.as_ref().map_or(0, |f| f.reserved),
        }
    }
}

/// An existing order prevents duplicates, but does NOT imply a carrier
/// accepted it or any physical goods reached the target station.
#[derive(Clone, Debug, Serialize)]
pub struct GoalAssessment {
    pub goal: Goal,
    pub reason: String,
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_delivery: Option<PendingDelivery>,
}
#[derive(Clone, Debug, Serialize)]
pub struct FactionView {
    pub faction_id: String,
    pub observed_tick: u64,
    pub treasury: i64,
    pub goals: Vec<Goal>,
    pub assessments: Vec<GoalAssessment>,
    pub selected_goal: Option<Goal>,
    pub administrator: &'static str,
    pub status: String,
    pub reason: String,
    pub projects: Vec<Project>,
    pub construction: Option<construction::ConstructionView>,
    pub head: Option<coordination::HeadDecision>,
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct Snapshot {
    pub schema_version: u32,
    pub snapshot_tick: u64,
    pub mode: Mode,
    pub factions: Vec<FactionView>,
    pub stations: Vec<station::StationView>,
    /// Current physically observed colonies; empty on older API servers.
    pub colonies: Vec<colony_development::ColonyView>,
    pub orders: Vec<orders::OrderView>,
    pub commanders: BTreeMap<String,director::Commander>,
    pub technologies: Vec<director::Technology>,
    #[serde(default)]
    pub station_progress: BTreeMap<String,progression::StationDevelopment>,
    /// Read-only player science policy and actual paid CR ledger.
    #[serde(default)]
    pub research_mandates: BTreeMap<String,governance::ResearchMandate>,
    #[serde(default)]
    pub economic_mandates: BTreeMap<String,economic_mandate::EconomicMandate>,
    #[serde(default)]
    pub faction_charters: BTreeMap<String,charter::FactionCharter>,
    /// Read-only persisted plan ledger for runtime diagnostics. Never a forecast of success.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ai_execution: Option<planning::NativeExecution>,
}
#[derive(Resource, Default)]
pub struct StrategyState {
    pub mode: Mode,
    pub last_coordinated_tick: Option<u64>,
    pub factions: BTreeMap<String, FactionView>,
}
impl StrategyState {
    pub fn snapshot(&self, tick: u64) -> Snapshot {
        Snapshot { schema_version: 1, snapshot_tick: tick, mode: self.mode,
            factions: self.factions.values().cloned().collect(), stations: Vec::new(),
            colonies: Vec::new(), orders: Vec::new(), commanders:BTreeMap::new(),
            technologies:director::TECHNOLOGIES.to_vec(),
            station_progress:BTreeMap::new(),
            research_mandates:BTreeMap::new(),
            economic_mandates:BTreeMap::new(),
            faction_charters:BTreeMap::new(), ai_execution:None }
    }
}
pub fn executing(world: &World) -> bool {
    world.get_resource::<StrategyState>().is_some_and(|s| s.mode == Mode::Execute)
}
fn goal_id(c: Commodity) -> &'static str {
    match c { Commodity::Food | Commodity::Water => "sustain_population",
        Commodity::Fuel => "secure_fuel", _ => "supply_industry" }
}
fn outstanding(c: &crate::economy::contracts::Contract) -> bool {
    !matches!(c.status, ContractStatus::Paid | ContractStatus::Expired)
        || c.funding.as_ref().is_some_and(|f| f.reserved > 0)
}

/// "Posted" is not "being delivered". Distinguish genuinely held,
/// in-flight and unassigned commitments WITHOUT issuing another order.
/// 180 native ticks is a reporting threshold, not a retry or timeout.
const UNASSIGNED_DIAGNOSTIC_AGE_TICKS: u64 = 180;
fn existing_delivery_reason(pending: &PendingDelivery) -> &'static str {
    match pending.status {
        "posted" if pending.fulfiller_id.is_none()
            && pending.station_order_executor_id.is_none()
            && pending.age_ticks >= UNASSIGNED_DIAGNOSTIC_AGE_TICKS =>
            "existing_contract_unassigned_stale",
        "posted" if pending.fulfiller_id.is_none()
            && pending.station_order_executor_id.is_none() =>
            "existing_contract_unassigned",
        "expired" => "existing_contract_refund_pending",
        _ => "existing_contract",
    }
}
/// Called at the existing faction subsidy cadence. In execute mode it replaces
/// only subsidy selection; taxes, construction and independent ships remain native.
pub fn run_cycle(world: &mut World, contracts: &mut ContractBoard,
    relations: &FactionRelations, tick: u64, tick_multiplier: u32) {
    world.init_resource::<StrategyState>();
    let execute = executing(world);
    let mut factions: Vec<_> = world.query::<(Entity, &FactionData)>().iter(world)
        .map(|(e, f)| (e, f.clone())).collect();
    factions.sort_by(|a,b| a.1.id.cmp(&b.1.id));
    let mut locations: HashMap<String, Vec<String>> = HashMap::new();
    for (id, loc) in world.query::<(&FacilityIdentity, &FacilityLocation)>().iter(world) {
        locations.entry(id.faction_id.clone()).or_default().push(loc.location_name.clone());
    }
    for locs in locations.values_mut() { locs.sort(); locs.dedup(); }
    let markets: Vec<_> = world.query::<(&MarketIdentity, &MarketHistory, &MarketPricing)>().iter(world)
        .map(|(i,h,p)| (i.facility_location.clone(), h.shortage_ticks.clone(), p.clone())).collect();
    let sources = sourcing::Sources::new(
        markets.iter().map(|(location, _, pricing)| (location.as_str(), pricing)),
        crate::agents::faction_relations::market_controllers(world), relations,
    );
    let player_economic_mandates=world.get_resource::<director::Director>()
        .map(|d|d.economic_mandates.clone()).unwrap_or_default();
    let crisis_factions:std::collections::HashSet<String>=
        world.get_resource::<director::Director>()
        .map(|d|d.commanders.iter().filter(|(_,c)|c.crisis)
            .map(|(id,_)|id.clone()).collect()).unwrap_or_default();
    for (entity, faction) in factions {
        let members = locations.get(&faction.id).cloned().unwrap_or_default();
        let mut goals = Vec::new();
        for (loc, shortages, _) in &markets {
            if !members.contains(loc) { continue; }
            for (&commodity, &age) in shortages {
                if age < faction::SUBSIDY_TRIGGER_TICKS { continue; }
                goals.push(Goal { goal_id: goal_id(commodity).into(), commodity,
                    destination: loc.clone(), shortage_ticks: age,
                    score: faction::shortage_priority(commodity, age, Some(&faction.personality)) });
            }
        }
        // Production input requests join the same head portfolio and funded
        // contracts. A local administrator never posts a competing reward.
        if let Some(stations)=world.get_resource::<station::StationAdministration>() {
            for station in stations.stations.iter().filter(|s|s.faction_id==faction.id && members.contains(&s.location)) {
                for need in &station.needs {
                    if goals.iter().any(|g|g.commodity==need.commodity && g.destination==station.location) {continue;}
                    goals.push(Goal {goal_id:goal_id(need.commodity).into(),commodity:need.commodity,
                        destination:station.location.clone(),shortage_ticks:0,
                        score:faction::shortage_priority(need.commodity,faction::SUBSIDY_TRIGGER_TICKS,Some(&faction.personality))});
                }
            }
        }
        if let Some(m)=player_economic_mandates.get(&faction.id) {
            if members.contains(&m.location) && !crisis_factions.contains(&faction.id)
                && charter::may_direct(world,&faction.id,charter::Department::Economy)
                && economic_mandate::may_commission(
                    m,faction.treasury,faction::SUBSIDY_BASE_PAYMENT*2).is_ok() {
                if let Some((_,_,market))=markets.iter().find(|(loc,_,_)|*loc==m.location){
                    let stock=market.supply.get(&m.commodity).copied().unwrap_or(0.0);
                    if let Some(goal)=m.goal(stock){
                        // A request for new industry is satisfied only by
                        // checking real installed producers, not by temporary
                        // inventory from traders.
                        if m.kind!=economic_mandate::EconomicKind::Industry ||
                            !economic_mandate::native_producer_exists(
                                world,&faction.id,&m.location,m.commodity) {
                            goals.push(goal);
                        }
                    }
                }
            }
        }
        goals.sort_by(|a,b| b.score.total_cmp(&a.score)
            .then_with(|| a.goal_id.cmp(&b.goal_id)).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));
        // Keep an outstanding project stable even when its shortage disappears.
        // Delivered awaits settlement; terminal contracts with held escrow await refund.
        let held = contracts.iter().filter(|c| c.requestor_id == faction.id &&
            c.mission_category.as_deref() == Some(PROJECT_TAG) && outstanding(c))
            .min_by(|a,b| a.posted_at_tick.cmp(&b.posted_at_tick).then_with(|| a.id.cmp(&b.id)));
        let payment = faction::SUBSIDY_BASE_PAYMENT * 2;
        let affordable = faction.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR) >= payment;
        let assessments: Vec<_> = goals.iter().map(|goal| {
            // Same native board as the ship and economy: no parallel project
            // lifecycle or inferred stock/credit changes. Stable ID selection
            // makes the diagnosis repeatable over multiple save loads.
            let duplicate = contracts.iter().filter(|c|
                (c.requestor_id == faction.id ||
                    c.faction_id.as_deref() == Some(faction.id.as_str())) &&
                outstanding(c) && c.commodity == goal.commodity &&
                c.destination_location == goal.destination)
                .min_by(|a,b|a.posted_at_tick.cmp(&b.posted_at_tick)
                    .then_with(||a.id.cmp(&b.id)));
            let pending_delivery = duplicate.map(|c| PendingDelivery::from_native(c,tick));
            let source = sources.choose(&faction.id, &goal.destination, goal.commodity,
                faction::SUBSIDY_QUANTITY, payment);
            let reason = if let Some(pending) = &pending_delivery {
                existing_delivery_reason(pending)
            } else if let Err(reason) = source { reason }
                else if !affordable { "insufficient_budget" } else { "ready" };
            GoalAssessment { goal: goal.clone(), reason: reason.into(),
                source: source.ok(), pending_delivery }
        }).collect();
        let candidate = assessments.iter()
            .find(|a| a.reason == "ready" && coordination::authorized(world, &faction.id, "logistics", &a.goal))
            .or_else(|| assessments.iter().find(|a| a.reason == "ready")).cloned();
        let selected = held.map(|c| goals.iter().find(|g| g.commodity == c.commodity &&
            g.destination == c.destination_location).cloned().unwrap_or_else(|| Goal {
                goal_id: goal_id(c.commodity).into(), commodity: c.commodity,
                destination: c.destination_location.clone(), shortage_ticks: 0, score: 0.0,
            })).or_else(|| candidate.as_ref().map(|a| a.goal.clone()))
            .or_else(|| goals.first().cloned());
        let head = world.resource::<StrategyState>().factions.get(&faction.id).and_then(|v| v.head.clone());
        let construction = world.resource::<StrategyState>().factions.get(&faction.id)
            .and_then(|v| v.construction.clone());
        let mut view = FactionView { faction_id: faction.id.clone(), observed_tick: tick,
            treasury: faction.treasury, goals, assessments, selected_goal: selected, administrator: "logistics",
            status: "idle".into(), reason: "no_chronic_shortage".into(), projects: Vec::new(), construction, head };
        if held.is_some() {
            view.status = "waiting".into(); view.reason = "existing_contract".into();
        } else if let Some(candidate) = candidate {
            if !execute {
                view.status = "proposed".into(); view.reason = "shadow_no_mutation".into();
            } else if !coordination::authorized(world, &faction.id, "logistics", &candidate.goal) {
                view.status = "waiting".into(); view.reason = "head_priority".into();
            } else {
                let distance=world.get_resource::<colony::Navigation>().and_then(|n|candidate.source.as_ref().and_then(|source|n.0.shortest_distance(source,&candidate.goal.destination))).unwrap_or(0);
                let lifespan=if world.get_resource::<director::Director>().is_some(){faction::SUBSIDY_LIFESPAN_BASE.max(u64::from(distance)*100+1200)}else{faction::SUBSIDY_LIFESPAN_BASE};
                let mut account = world.get_mut::<FactionData>(entity).unwrap();
                account.treasury -= payment; account.dirty = true;
                view.treasury = account.treasury;
                let id = contracts.post_subsidy(faction.id.clone(), candidate.goal.commodity, faction::SUBSIDY_QUANTITY,
                    candidate.source.unwrap(), candidate.goal.destination, payment, tick,
                    lifespan * tick_multiplier as u64);
                contracts.register_prepaid(&id, FundingSource::Faction);
                contracts.get_mut(&id).unwrap().mission_category = Some(PROJECT_TAG.into());
                view.status = "commissioned".into(); view.reason = "funded_native_contract".into();
            }
        } else if let Some(first) = view.assessments.first() {
            // An unassigned old order is not in execution: make the
            // observable state blocked without reposting or spending money.
            view.status = if first.reason.starts_with("existing_contract")
                && first.reason != "existing_contract_unassigned_stale" {
                "waiting"
            } else { "blocked" }.into();
            view.reason = first.reason.clone();
        }
        world.resource_mut::<StrategyState>().factions.insert(faction.id, view);
    }
    refresh(world, contracts, tick);
}
/// Reconstruct project identity/status from persisted contracts, including after
/// restart. No extra wallet or project ID allocator is introduced by the prototype.
pub fn refresh(world: &mut World, contracts: &ContractBoard, tick: u64) {
    world.init_resource::<StrategyState>();
    let accounts: Vec<_> = world.query::<&FactionData>().iter(world).map(|f| (f.id.clone(),f.treasury)).collect();
    let mut state = world.resource_mut::<StrategyState>();
    state.factions.retain(|id,_| accounts.iter().any(|(f,_)| f==id));
    for (id, treasury) in accounts {
        let view = state.factions.entry(id.clone()).or_insert_with(|| FactionView {
            faction_id: id.clone(), observed_tick: tick, treasury, goals: Vec::new(), assessments: Vec::new(), selected_goal: None,
            administrator: "logistics", status: "observing".into(), reason: "awaiting_cycle".into(), projects: Vec::new(), construction: None, head: None });
        view.treasury = treasury;
        let mut records: Vec<_> = contracts.iter().filter(|c| c.requestor_id == id &&
            matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG) | Some(colony::PROJECT_TAG) |
                    Some(colony_development::MIGRATION_TAG))).collect();
        records.sort_by(|a,b| outstanding(b).cmp(&outstanding(a))
            .then_with(|| b.posted_at_tick.cmp(&a.posted_at_tick)).then_with(|| a.id.cmp(&b.id)));
        view.projects = records.into_iter().take(32).map(|c| Project {
            project_id: c.id.clone(), contract_id: c.id.clone(), administrator:
                if matches!(c.mission_category.as_deref(), Some(construction::PROJECT_TAG) | Some(colony::PROJECT_TAG)) { "construction" }
                else if c.mission_category.as_deref()==Some(colony_development::MIGRATION_TAG) {"migration"}
                else { "logistics" },
            state: match c.status { ContractStatus::Posted => "posted", ContractStatus::Accepted => "accepted",
                ContractStatus::PickedUp => "picked_up", ContractStatus::Delivered => "delivered",
                ContractStatus::Paid => "paid", ContractStatus::Expired => "expired" }.into(), executor_id: c.fulfiller_id.clone(),
            reserved_credits: c.funding.as_ref().map_or(0,|f| f.reserved),
            source: c.source_location.clone(), destination: c.destination_location.clone(),
            commodity: c.commodity, quantity: c.quantity,
        }).collect();
    }
    drop(state);
    construction::refresh(world);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agents::faction::FactionColors;

    pub(super) fn fixture(mode: Mode) -> (World, ContractBoard, Entity, Entity, Entity) {
        let mut world = World::new();
        world.insert_resource(StrategyState { mode, ..Default::default() });
        let owner = world.spawn(FactionData {
            id: "own".into(), name: "Own".into(), faction_type: "normal".into(), home_system: "sol".into(),
            treasury: 20_000, personality: crate::ai::personality::Personality::balanced_trader(),
            colors: FactionColors { primary: String::new(), secondary: String::new() }, active_subsidies: 0, dirty: false,
        }).id();
        let mut markets = Vec::new();
        for (n, name) in ["port", "mine"].iter().enumerate() {
            let facility = world.spawn((FacilityIdentity { db_id: n as i64 + 1, id: name.to_string(),
                name: name.to_string(), facility_type: "station".into(), faction_id: "own".into(), body_id: "earth".into() },
                FacilityLocation { location_id: n as i64 + 1, location_name: name.to_string() })).id();
            markets.push(world.spawn((MarketIdentity { db_id: n as i64 + 1, id: format!("market-{name}"),
                facility, facility_location: name.to_string() }, MarketHistory::default(),
                MarketPricing { price_elasticity: 1.0, spread: 0.0, prices: [(Commodity::Ore, 1.0), (Commodity::Food, 6.0)].into(),
                    supply: HashMap::new(), demand: HashMap::new() })).id());
        }
        world.get_mut::<MarketHistory>(markets[0]).unwrap().shortage_ticks =
            [(Commodity::Food, 1000), (Commodity::Ore, 50)].into();
        world.get_mut::<MarketPricing>(markets[1]).unwrap().supply.insert(Commodity::Ore, 200.0);
        (world, ContractBoard::new(), owner, markets[0], markets[1])
    }

    #[test]
    fn galaxy061_player_supply_mandate_only_funds_a_real_native_contract(){
        let (mut world,mut board,owner,port,source)=fixture(Mode::Shadow);
        let relations=FactionRelations::new();
        // Water is an ACTUAL existing source product, not a shadow yield.
        world.get_mut::<MarketPricing>(source).unwrap().supply
            .insert(Commodity::Water,500.0);
        world.get_mut::<MarketPricing>(source).unwrap().prices
            .insert(Commodity::Water,1.0);
        world.get_mut::<MarketPricing>(port).unwrap().demand
            .insert(Commodity::Water,80.0);
        world.insert_resource(director::Director::default());
        director::observe(&mut world,&board,0,1);
        world.resource_mut::<director::Director>().economic_mandates.insert(
            "own".into(),economic_mandate::EconomicMandate{
                kind:economic_mandate::EconomicKind::Supply,
                location:"port".into(),
                commodity:Commodity::Water,
                min_stock:200,
                mode:governance::MandateMode::Delegated,
                budget_ceiling_cr:4000,treasury_floor_cr:10000,
                spent_cr:0,created_tick:0,last_commitment_tick:None,
                last_reason:String::new(),
            }
        );
        // An ordinary observer view never produces a real contract.
        run_cycle(&mut world,&mut board,&relations,60,1);
        assert!(world.resource::<StrategyState>().factions["own"]
            .goals.iter().any(|g|g.goal_id=="player_supply" &&
                g.commodity==Commodity::Water));
        assert_eq!(board.iter().count(),0);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,20_000);

        world.resource_mut::<StrategyState>().mode=Mode::Execute;
        let mut events=Vec::new();
        coordination::run_cycle(&mut world,&mut board,&relations,&mut events,120,1);
        let funded:Vec<_>=board.iter().filter(|contract|
            contract.requestor_id=="own" &&
            contract.destination_location=="port" &&
            contract.commodity==Commodity::Water &&
            contract.funding.as_ref().is_some_and(|x|x.reserved>0)).collect();
        assert_eq!(funded.len(),1,"Mandate must issue ONE actual funded water contract");
        let actual=funded[0].funding.as_ref().unwrap().reserved;
        assert!(actual>0);
        assert_eq!(world.resource::<director::Director>()
            .economic_mandates["own"].spent_cr,actual);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury,
            20_000-actual);
        // An acceptance/posted offer is not yet a delivered water unit.
        assert_eq!(world.get::<MarketPricing>(port).unwrap()
            .supply.get(&Commodity::Water).copied().unwrap_or(0.0),0.0);
    }

    #[test]
    fn galaxy061_player_supply_budget_refuses_new_native_contract(){
        let (mut world,mut board,owner,port,source)=fixture(Mode::Execute);
        world.get_mut::<MarketPricing>(source).unwrap().supply
            .insert(Commodity::Water,500.0);
        world.get_mut::<MarketPricing>(source).unwrap().prices
            .insert(Commodity::Water,1.0);
        world.get_mut::<MarketPricing>(port).unwrap().demand
            .insert(Commodity::Water,80.0);
        world.insert_resource(director::Director::default());
        director::observe(&mut world,&board,0,1);
        world.resource_mut::<director::Director>().economic_mandates.insert(
            "own".into(),economic_mandate::EconomicMandate {
                kind:economic_mandate::EconomicKind::Supply,
                location:"port".into(),commodity:Commodity::Water,
                min_stock:200,mode:governance::MandateMode::Delegated,
                budget_ceiling_cr:1000,treasury_floor_cr:10000,
                spent_cr:0,created_tick:0,last_commitment_tick:None,
                last_reason:String::new(),
            }
        );
        let mut events=Vec::new();
        coordination::run_cycle(&mut world,&mut board,&FactionRelations::new(),
            &mut events,120,1);
        assert!(!board.iter().any(|c|c.requestor_id=="own"&&
            c.commodity==Commodity::Water));
        assert_eq!(world.resource::<director::Director>()
            .economic_mandates["own"].spent_cr,0);
        // Any autonomous unrelated income and purchases remain owned by
        // the baseline Director; the mandate never prints new money.
        assert!(world.get::<FactionData>(owner).unwrap().treasury<=20_000);
    }

    #[test]
    fn strategy_block_portfolio_skips_unavailable_goal_and_shadow_matches_execute() {
        let (mut world, mut board, owner, _, _) = fixture(Mode::Shadow);
        let relations = FactionRelations::new();
        run_cycle(&mut world, &mut board, &relations, 60, 1);
        let view = &world.resource::<StrategyState>().factions["own"];
        assert_eq!(view.goals[0].commodity, Commodity::Food);
        assert_eq!(view.assessments[0].reason, "no_accessible_stock");
        assert_eq!(view.selected_goal.as_ref().unwrap().commodity, Commodity::Ore);
        assert_eq!(view.status, "proposed");
        assert_eq!(board.iter().count(), 0);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury, 20_000);
        world.resource_mut::<StrategyState>().mode = Mode::Execute;
        run_cycle(&mut world, &mut board, &relations, 120, 1);
        assert_eq!(board.iter().next().unwrap().commodity, Commodity::Ore);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury, 18_400);
    }

    #[test]
    fn strategy_block_existing_non_strategy_goal_does_not_block_other_needs() {
        let (mut world, mut board, _, _, source) = fixture(Mode::Execute);
        world.get_mut::<MarketPricing>(source).unwrap().supply.insert(Commodity::Food, 200.0);
        board.post_subsidy("own".into(), Commodity::Food, 200, "mine".into(), "port".into(), 1600, 0, 1000);
        run_cycle(&mut world, &mut board, &FactionRelations::new(), 60, 1);
        assert_eq!(board.iter().count(), 2);
        let view = &world.resource::<StrategyState>().factions["own"];
        assert_eq!(view.assessments[0].reason, "existing_contract_unassigned");
        assert_eq!(view.assessments[0].pending_delivery.as_ref().unwrap().status, "posted");
        assert!(view.assessments[0].pending_delivery.as_ref().unwrap().fulfiller_id.is_none());
        assert_eq!(view.selected_goal.as_ref().unwrap().commodity, Commodity::Ore);
    }

    #[test]
    fn strategy_native_unassigned_delivery_becomes_visible_stalled_without_duplicate() {
        let (mut world, mut board, _, _, source) = fixture(Mode::Execute);
        let relations = FactionRelations::new();
        world.get_mut::<MarketPricing>(source).unwrap().supply
            .insert(Commodity::Food, 500.0);
        let id = board.post_subsidy("own".into(), Commodity::Food, 200,
            "mine".into(), "port".into(), 1600, 0, 1000);
        run_cycle(&mut world, &mut board, &relations, 60, 1);
        let view = &world.resource::<StrategyState>().factions["own"];
        let food = view.assessments.iter().find(|a|a.goal.commodity==Commodity::Food).unwrap();
        assert_eq!(food.reason, "existing_contract_unassigned");
        let before=food.pending_delivery.as_ref().unwrap();
        assert_eq!(before.contract_id, id);
        assert_eq!(before.status, "posted");
        assert_eq!(before.age_ticks, 60);
        assert!(before.fulfiller_id.is_none());

        // Existing posted request must not be considered delivered or
        // trigger a second spend solely because no ship accepted it.
        run_cycle(&mut world, &mut board, &relations, 360, 1);
        let view = &world.resource::<StrategyState>().factions["own"];
        let food = view.assessments.iter().find(|a|a.goal.commodity==Commodity::Food).unwrap();
        assert_eq!(food.reason, "existing_contract_unassigned_stale");
        assert_eq!(food.pending_delivery.as_ref().unwrap().age_ticks, 360);
        assert_eq!(board.iter().filter(|c|c.commodity==Commodity::Food
            && c.destination_location=="port").count(), 1);

        // The exact SAME contract transitions to accepted; the head can
        // distinguish real execution from a stalled posted request.
        assert!(board.accept(&id, "ship-test".into(), 370));
        run_cycle(&mut world, &mut board, &relations, 420, 1);
        let view = &world.resource::<StrategyState>().factions["own"];
        let food = view.assessments.iter().find(|a|a.goal.commodity==Commodity::Food).unwrap();
        assert_eq!(food.reason, "existing_contract");
        let after=food.pending_delivery.as_ref().unwrap();
        assert_eq!(after.status, "accepted");
        assert_eq!(after.fulfiller_id.as_deref(), Some("ship-test"));
        assert_eq!(after.contract_id, id);
    }

    #[test]
    fn strategy_block_hold_through_settlement_and_replan_after_release() {
        let (mut world, mut board, owner, port, source) = fixture(Mode::Execute);
        let relations = FactionRelations::new();
        run_cycle(&mut world, &mut board, &relations, 60, 1);
        let id = board.iter().next().unwrap().id.clone();
        // Need vanishes while cargo is in flight: retain the actual project's goal.
        world.get_mut::<MarketHistory>(port).unwrap().shortage_ticks.clear();
        for status in [ContractStatus::Posted, ContractStatus::Accepted, ContractStatus::PickedUp,
            ContractStatus::Delivered, ContractStatus::Expired] {
            board.get_mut(&id).unwrap().status = status;
            world.insert_resource(StrategyState { mode: Mode::Execute, ..Default::default() });
            run_cycle(&mut world, &mut board, &relations, 120, 1);
            let view = &world.resource::<StrategyState>().factions["own"];
            assert_eq!(view.status, "waiting");
            assert_eq!(view.selected_goal.as_ref().unwrap().commodity, Commodity::Ore);
            assert_eq!(board.iter().count(), 1);
            assert_eq!(world.get::<FactionData>(owner).unwrap().treasury, 18_400);
        }
        // Native settlement/refund owns money; strategy only observes its completion.
        board.get_mut(&id).unwrap().funding.as_mut().unwrap().reserved = 0;
        world.get_mut::<MarketHistory>(port).unwrap().shortage_ticks.insert(Commodity::Food, 50);
        world.get_mut::<MarketPricing>(source).unwrap().supply.insert(Commodity::Food, 200.0);
        run_cycle(&mut world, &mut board, &relations, 180, 1);
        assert_eq!(board.iter().count(), 2);
        assert_eq!(world.resource::<StrategyState>().factions["own"].selected_goal.as_ref().unwrap().commodity, Commodity::Food);
        assert_eq!(world.get::<FactionData>(owner).unwrap().treasury, 16_800);
    }
}
