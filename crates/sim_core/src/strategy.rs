//! First head -> logistics administrator -> native contract execution slice.
//! Read-only projections are rebuilt from ECS/board; money lives in native accounts.
use bevy_ecs::prelude::*;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use crate::agents::{faction::{self, FactionData}, facility::{FacilityIdentity, FacilityLocation},
    market::{MarketIdentity, MarketHistory, MarketPricing}, faction_relations::FactionRelations};
use crate::economy::{commodities::Commodity, contracts::{ContractBoard, ContractStatus, FundingSource}};

pub mod construction;
pub mod station;
pub mod orders;
pub mod coordination;
mod options;
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
#[derive(Clone, Debug, Serialize)]
pub struct GoalAssessment {
    pub goal: Goal,
    pub reason: String,
    pub source: Option<String>,
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
    pub orders: Vec<orders::OrderView>,
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
            factions: self.factions.values().cloned().collect(), stations: Vec::new(), orders: Vec::new() }
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
            let duplicate = contracts.iter().any(|c| (c.requestor_id == faction.id || c.faction_id.as_deref()==Some(faction.id.as_str())) && outstanding(c) &&
                c.commodity == goal.commodity && c.destination_location == goal.destination);
            let source = sources.choose(&faction.id, &goal.destination, goal.commodity,
                faction::SUBSIDY_QUANTITY, payment);
            let reason = if duplicate { "existing_contract" }
                else if let Err(reason) = source { reason }
                else if !affordable { "insufficient_budget" } else { "ready" };
            GoalAssessment { goal: goal.clone(), reason: reason.into(), source: source.ok() }
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
                let mut account = world.get_mut::<FactionData>(entity).unwrap();
                account.treasury -= payment; account.dirty = true;
                view.treasury = account.treasury;
                let id = contracts.post_subsidy(faction.id.clone(), candidate.goal.commodity, faction::SUBSIDY_QUANTITY,
                    candidate.source.unwrap(), candidate.goal.destination, payment, tick,
                    faction::SUBSIDY_LIFESPAN_BASE * tick_multiplier as u64);
                contracts.register_prepaid(&id, FundingSource::Faction);
                contracts.get_mut(&id).unwrap().mission_category = Some(PROJECT_TAG.into());
                view.status = "commissioned".into(); view.reason = "funded_native_contract".into();
            }
        } else if let Some(first) = view.assessments.first() {
            view.status = if first.reason == "existing_contract" { "waiting" } else { "blocked" }.into();
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
            matches!(c.mission_category.as_deref(), Some(PROJECT_TAG) | Some(construction::PROJECT_TAG))).collect();
        records.sort_by(|a,b| outstanding(b).cmp(&outstanding(a))
            .then_with(|| b.posted_at_tick.cmp(&a.posted_at_tick)).then_with(|| a.id.cmp(&b.id)));
        view.projects = records.into_iter().take(32).map(|c| Project {
            project_id: c.id.clone(), contract_id: c.id.clone(), administrator:
                if c.mission_category.as_deref() == Some(construction::PROJECT_TAG) { "construction" } else { "logistics" },
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
        assert_eq!(view.assessments[0].reason, "existing_contract");
        assert_eq!(view.selected_goal.as_ref().unwrap().commodity, Commodity::Ore);
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
