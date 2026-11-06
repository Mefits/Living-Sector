//! First head -> logistics administrator -> native contract execution slice.
//! Read-only projections are rebuilt from ECS/board; money lives in native accounts.
use bevy_ecs::prelude::*;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use crate::agents::{faction::{self, FactionData}, facility::{FacilityIdentity, FacilityLocation},
    market::{MarketIdentity, MarketHistory, MarketPricing}, faction_relations::FactionRelations};
use crate::economy::{commodities::Commodity, contracts::{ContractBoard, ContractStatus, FundingSource}};

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
pub struct FactionView {
    pub faction_id: String,
    pub observed_tick: u64,
    pub treasury: i64,
    pub goals: Vec<Goal>,
    pub selected_goal: Option<Goal>,
    pub administrator: &'static str,
    pub status: String,
    pub reason: String,
    pub projects: Vec<Project>,
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct Snapshot {
    pub schema_version: u32,
    pub snapshot_tick: u64,
    pub mode: Mode,
    pub factions: Vec<FactionView>,
}
#[derive(Resource, Default)]
pub struct StrategyState {
    pub mode: Mode,
    pub factions: BTreeMap<String, FactionView>,
}
impl StrategyState {
    pub fn snapshot(&self, tick: u64) -> Snapshot {
        Snapshot { schema_version: 1, snapshot_tick: tick, mode: self.mode,
            factions: self.factions.values().cloned().collect() }
    }
}
pub fn executing(world: &World) -> bool {
    world.get_resource::<StrategyState>().is_some_and(|s| s.mode == Mode::Execute)
}
fn goal_id(c: Commodity) -> &'static str {
    match c { Commodity::Food | Commodity::Water => "sustain_population",
        Commodity::Fuel => "secure_fuel", _ => "supply_industry" }
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
        .map(|(i,h,p)| (i.facility_location.clone(), h.shortage_ticks.clone(), p.supply.clone())).collect();
    let supply: HashMap<_,_> = markets.iter().map(|(l,_,s)| (l.clone(),s.clone())).collect();
    let owners = crate::agents::faction_relations::market_controllers(world);
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
        goals.sort_by(|a,b| b.score.total_cmp(&a.score)
            .then_with(|| a.goal_id.cmp(&b.goal_id)).then_with(|| a.commodity.as_str().cmp(b.commodity.as_str()))
            .then_with(|| a.destination.cmp(&b.destination)));
        let selected = goals.first().cloned();
        let mut view = FactionView { faction_id: faction.id.clone(), observed_tick: tick,
            treasury: faction.treasury, goals, selected_goal: selected.clone(), administrator: "logistics",
            status: "idle".into(), reason: "no_chronic_shortage".into(), projects: Vec::new() };
        if let Some(goal) = selected {
            let active = |c: &crate::economy::contracts::Contract| matches!(c.status,
                ContractStatus::Posted | ContractStatus::Accepted | ContractStatus::PickedUp);
            let existing = contracts.iter().any(|c| c.requestor_id == faction.id && active(c) &&
                (c.mission_category.as_deref() == Some(PROJECT_TAG) ||
                (c.commodity == goal.commodity && c.destination_location == goal.destination)));
            let source = faction::choose_logistics_source(&supply, &members, &owners, relations,
                &faction.id, &goal.destination, goal.commodity, faction::SUBSIDY_QUANTITY as f32);
            let payment = faction::SUBSIDY_BASE_PAYMENT * 2;
            let affordable = faction.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR) >= payment;
            if existing {
                view.status = "waiting".into(); view.reason = "existing_contract".into();
            } else if source.is_none() {
                view.status = "blocked".into(); view.reason = "no_accessible_stock".into();
            } else if !affordable {
                view.status = "blocked".into(); view.reason = "insufficient_budget".into();
            } else if !execute {
                view.status = "proposed".into(); view.reason = "shadow_no_mutation".into();
            } else {
                let mut account = world.get_mut::<FactionData>(entity).unwrap();
                account.treasury -= payment; account.dirty = true;
                view.treasury = account.treasury;
                let id = contracts.post_subsidy(faction.id.clone(), goal.commodity, faction::SUBSIDY_QUANTITY,
                    source.unwrap(), goal.destination, payment, tick,
                    faction::SUBSIDY_LIFESPAN_BASE * tick_multiplier as u64);
                contracts.register_prepaid(&id, FundingSource::Faction);
                contracts.get_mut(&id).unwrap().mission_category = Some(PROJECT_TAG.into());
                view.status = "commissioned".into(); view.reason = "funded_native_contract".into();
            }
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
            faction_id: id.clone(), observed_tick: tick, treasury, goals: Vec::new(), selected_goal: None,
            administrator: "logistics", status: "observing".into(), reason: "awaiting_cycle".into(), projects: Vec::new() });
        view.treasury = treasury;
        let mut records: Vec<_> = contracts.iter().filter(|c| c.requestor_id == id &&
            c.mission_category.as_deref() == Some(PROJECT_TAG)).collect();
        records.sort_by(|a,b| b.posted_at_tick.cmp(&a.posted_at_tick).then_with(|| a.id.cmp(&b.id)));
        view.projects = records.into_iter().take(32).map(|c| Project {
            project_id: c.id.clone(), contract_id: c.id.clone(), administrator: "logistics",
            state: match c.status { ContractStatus::Posted => "posted", ContractStatus::Accepted => "accepted",
                ContractStatus::PickedUp => "picked_up", ContractStatus::Delivered => "delivered",
                ContractStatus::Paid => "paid", ContractStatus::Expired => "expired" }.into(), executor_id: c.fulfiller_id.clone(),
            reserved_credits: c.funding.as_ref().map_or(0,|f| f.reserved),
            source: c.source_location.clone(), destination: c.destination_location.clone(),
            commodity: c.commodity, quantity: c.quantity,
        }).collect();
    }
}
