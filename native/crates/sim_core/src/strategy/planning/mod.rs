//! Pure, faction-scoped planning contract for Galaxy.
//!
//! The native ECS/market/contract board are the only source of truth. A planner
//! receives an OWNED, read-only projection; neither this module nor a search
//! adapter may create cargo, commit money or mutate a ship. Only an explicitly opt-in,
//! revalidated native dispatch may submit work; baseline remains default.

use bevy_ecs::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

use crate::agents::{
    facility::{FacilityIdentity, FacilityLocation},
    faction::FactionData,
    market::{MarketIdentity, MarketPricing},
    ship::{ShipCargo, ShipFuel, ShipIdentity, ShipPosition, ShipTransit},
};
use crate::economy::{
    commodities::Commodity,
    contracts::{ContractBoard, ContractStatus},
    recipes,
};
use super::director;

mod baseline;
mod htn_adapter;
mod forward_search;
mod telic_goap;
mod control_beam;
mod comparison;
mod hybrid;
pub use hybrid::{HybridPlanner, HybridPreferences, HybridDecision, HybridRoleTrace};
pub use telic_goap::TelicGoapAdapter;
pub use control_beam::ControlBeamAdapter;
pub use comparison::{compare_planners, PlannerComparison, ComparedPlanner};
mod native_catalogue;
pub use native_catalogue::{htn_native_shadow, HtnNativeShadow};
pub use htn_adapter::HtnAdapter;
pub use baseline::{native_decision_shadow, shadow_enabled, ShadowTrace};
mod native_execution;
pub use native_execution::{NativeExecution, NativeDriveReport, drive_native_htn, execution_enabled};
mod ledger;
pub use ledger::{LedgerError, PlanGate, PlanLedger, StepPhase, StepRecord};

pub const SCHEMA_VERSION: u32 = 1;

/// Market quantities are kept as floating-point values because native Genesis
/// prices and stocks are f32; integer rounding would silently invent stock.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MarketEntry {
    /// Stable native market identity; a location can contain several separate markets.
    #[serde(default)]
    pub market_id: String,
    /// Facility owning this stock; never silently sum co-located facilities.
    #[serde(default)]
    pub facility_id: String,
    pub location_id: String,
    pub stock: BTreeMap<String, f64>,
    pub demand: BTreeMap<String, f64>,
    pub prices: BTreeMap<String, f64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FacilityEntry {
    pub facility_id: String,
    pub location_id: String,
    pub facility_type: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ShipEntry {
    pub ship_id: String,
    pub class: String,
    pub location_id: Option<String>,
    pub in_transit: bool,
    pub free_cargo: u32,
    pub fuel: f64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommitmentEntry {
    pub contract_id: String,
    pub status: String,
    pub source: String,
    pub destination: String,
    pub commodity: Commodity,
    pub quantity: u32,
    pub assigned_ship_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeEntry {
    pub recipe_id: String,
    pub facility_type: String,
    pub inputs: Vec<(Commodity, u32)>,
    pub outputs: Vec<(Commodity, u32)>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PlanningSnapshot {
    pub schema_version: u32,
    pub tick: u64,
    pub faction_id: String,
    pub treasury_credits: i64,
    /// Financial floor is NOT a reservation or additional account.
    pub treasury_floor_credits: i64,
    /// Only the faction's own markets are included in this initial capture.
    /// External offers require a separately authorised visibility projection.
    pub owned_markets: Vec<MarketEntry>,
    pub facilities: Vec<FacilityEntry>,
    pub ships: Vec<ShipEntry>,
    pub active_commitments: Vec<CommitmentEntry>,
    pub technologies: Vec<String>,
    pub recipes: Vec<RecipeEntry>,
}

fn sorted_finite(map: &std::collections::HashMap<Commodity, f32>) -> BTreeMap<String, f64> {
    map.iter().filter_map(|(commodity, quantity)| {
        quantity.is_finite().then(|| (commodity.as_str().to_string(), f64::from(*quantity)))
    }).collect()
}

impl PlanningSnapshot {
    /// Capture owned data from native components, with stable IDs and ordering.
    /// No ECS Entity is kept past this call and no World data is mutated.
    pub fn capture(world: &mut World, board: &ContractBoard, tick: u64, faction_id: &str) -> Result<Self, &'static str> {
        let treasury = world.query::<&FactionData>().iter(world)
            .find(|faction| faction.id == faction_id)
            .map(|faction| faction.treasury).ok_or("unknown_faction")?;
        let mut facilities: Vec<_> = world.query::<(&FacilityIdentity, &FacilityLocation)>().iter(world)
            .filter(|(identity, _)| identity.faction_id == faction_id)
            .map(|(identity, location)| FacilityEntry {
                facility_id: identity.id.clone(), location_id: location.location_name.clone(),
                facility_type: identity.facility_type.clone(),
            }).collect();
        facilities.sort_by(|a,b| a.facility_id.cmp(&b.facility_id));
        let owned_ids: BTreeSet<_> = facilities.iter().map(|f| f.facility_id.as_str()).collect();
        let all_markets: Vec<_> = world.query::<(&MarketIdentity, &MarketPricing)>().iter(world)
            .map(|(identity, pricing)| (identity.id.clone(), identity.facility, identity.facility_location.clone(), pricing.clone()))
            .collect();
        let mut owned_markets: Vec<_> = all_markets.into_iter().filter_map(|(market_id, owner, location, pricing)| {
            let identity = world.get::<FacilityIdentity>(owner)?;
            if !owned_ids.contains(identity.id.as_str()) { return None; }
            Some(MarketEntry {
                market_id, facility_id: identity.id.clone(),
                location_id: location, stock: sorted_finite(&pricing.supply),
                demand: sorted_finite(&pricing.demand), prices: sorted_finite(&pricing.prices),
            })
        }).collect();
        owned_markets.sort_by(|a,b|a.location_id.cmp(&b.location_id).then_with(||a.market_id.cmp(&b.market_id)));
        let mut ships: Vec<_> = world.query::<(&ShipIdentity, &ShipPosition, &ShipTransit, &ShipCargo, &ShipFuel)>().iter(world)
            .filter(|(ship,_,_,_,_)|ship.faction_id == faction_id)
            .map(|(ship, position, transit, cargo, fuel)| ShipEntry {
                ship_id: ship.id.clone(), class: ship.class.clone(),
                location_id: position.location_name.clone(), in_transit: transit.transit.is_some(),
                free_cargo: cargo.free(), fuel: f64::from(fuel.fuel),
            }).collect();
        ships.sort_by(|a,b|a.ship_id.cmp(&b.ship_id));
        let mut active_commitments: Vec<_> = board.iter().filter(|contract| {
            (contract.requestor_id == faction_id || contract.faction_id.as_deref() == Some(faction_id))
                && !matches!(contract.status, ContractStatus::Paid | ContractStatus::Expired)
        }).map(|contract| CommitmentEntry {
            contract_id: contract.id.clone(), status: format!("{:?}", contract.status).to_lowercase(),
            source: contract.source_location.clone(), destination: contract.destination_location.clone(),
            commodity: contract.commodity, quantity: contract.quantity,
            assigned_ship_id: contract.fulfiller_id.clone(),
        }).collect();
        active_commitments.sort_by(|a,b|a.contract_id.cmp(&b.contract_id));
        let technologies = world.get_resource::<director::Director>()
            .and_then(|director|director.commanders.get(faction_id))
            .map_or_else(Vec::new, |commander|commander.technologies.clone());
        let recipes = recipes::RECIPES.iter().map(|r|RecipeEntry {
            recipe_id: r.id.into(), facility_type: r.facility_type.into(),
            inputs: r.inputs.to_vec(), outputs: r.outputs.to_vec(),
        }).collect();
        Ok(Self {
            schema_version: SCHEMA_VERSION, tick, faction_id: faction_id.into(),
            treasury_credits: treasury,
            treasury_floor_credits: crate::agents::faction::FACTION_SUBSIDY_FLOOR,
            owned_markets, facilities, ships, active_commitments, technologies, recipes,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GoalSpec {
    pub goal_id: String,
    pub destination_id: String,
    pub commodity: Commodity,
    pub target_units: u32,
    pub priority: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum ActionKind { Deliver, Produce, Construct, Research, FoundColony }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionSpec {
    pub action_id: String,
    pub kind: ActionKind,
    /// Deliver: source location; Produce: stable ID of the native producer.
    pub source_id: Option<String>,
    pub destination_id: String,
    pub commodity: Option<Commodity>,
    pub units: u32,
    pub cost_credits: i64,
    pub expected_ticks: u64,
    pub inputs: Vec<(Commodity, u32)>,
    pub outputs: Vec<(Commodity, u32)>,
    pub required_facility_type: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PlanStatus { Ready, NoPlan, BudgetExhausted, InvalidSnapshot }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanStep {
    pub step_id: String,
    pub action_id: String,
    pub depends_on: Vec<String>,
    /// Predicted completion is NOT proof of a native completion receipt.
    pub expected_condition: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanResult {
    pub status: PlanStatus,
    pub goal_id: String,
    pub planner_id: String,
    pub steps: Vec<PlanStep>,
    pub forecast_credits: i64,
    pub forecast_ticks: u64,
    pub nodes_expanded: u32,
    pub explanation: String,
}

#[derive(Clone, Copy, Debug)]
pub struct SearchBudget { pub max_nodes: u32, pub max_depth: usize }
impl Default for SearchBudget { fn default() -> Self { Self { max_nodes: 2_000, max_depth: 12 } } }

/// Every adapter uses the same immutable data and action catalogue.
/// No World/SQLite/HTTP or native contract issuer is available here.
pub trait Planner {
    fn id(&self) -> &'static str;
    fn plan(&self, snapshot: &PlanningSnapshot, goal: &GoalSpec,
            actions: &[ActionSpec], budget: SearchBudget) -> PlanResult;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValidationError {
    WrongSchema, MismatchedGoal, InvalidPlanStatus, DepthExceeded, NodesExceeded,
    DuplicateAction, DuplicateStep, UnknownAction, InvalidDependency,
    InvalidCost, SpendExceedsTreasury, InvalidForecast,
}

/// Check that a proposed plan is internally coherent and affordable in the
/// current *snapshot*. Dispatch must separately recheck the live ECS and board.
pub fn validate_plan(snapshot: &PlanningSnapshot, goal: &GoalSpec, actions: &[ActionSpec],
                     plan: &PlanResult, budget: SearchBudget) -> Result<(), ValidationError> {
    if snapshot.schema_version != SCHEMA_VERSION || snapshot.faction_id.is_empty() {
        return Err(ValidationError::WrongSchema);
    }
    if plan.goal_id != goal.goal_id {return Err(ValidationError::MismatchedGoal);}
    if budget.max_nodes == 0 || plan.nodes_expanded > budget.max_nodes {return Err(ValidationError::NodesExceeded);}
    if plan.steps.len() > budget.max_depth {return Err(ValidationError::DepthExceeded);}
    if plan.forecast_credits < 0 {return Err(ValidationError::InvalidCost);}
    if plan.status != PlanStatus::Ready {
        return if plan.steps.is_empty() {Ok(())} else {Err(ValidationError::InvalidPlanStatus)};
    }
    if plan.steps.is_empty() {return Err(ValidationError::InvalidPlanStatus);}
    let mut catalogue = BTreeMap::new();
    for action in actions {
        if action.action_id.is_empty() || action.cost_credits < 0 ||
            catalogue.insert(action.action_id.as_str(), action).is_some() {
            return Err(ValidationError::DuplicateAction);
        }
    }
    let mut seen = BTreeSet::new();
    let mut spent = 0_i64;
    let mut duration = 0_u64;
    for step in &plan.steps {
        if step.step_id.is_empty() || !seen.insert(step.step_id.as_str()) {
            return Err(ValidationError::DuplicateStep);
        }
        if step.depends_on.iter().any(|dep|!seen.contains(dep.as_str()) || dep == &step.step_id) {
            return Err(ValidationError::InvalidDependency);
        }
        let action = catalogue.get(step.action_id.as_str()).ok_or(ValidationError::UnknownAction)?;
        spent = spent.checked_add(action.cost_credits).ok_or(ValidationError::InvalidCost)?;
        duration = duration.checked_add(action.expected_ticks).ok_or(ValidationError::InvalidForecast)?;
    }
    if spent != plan.forecast_credits || duration != plan.forecast_ticks {
        return Err(ValidationError::InvalidForecast);
    }
    if spent > snapshot.treasury_credits.saturating_sub(snapshot.treasury_floor_credits).max(0) {
        return Err(ValidationError::SpendExceedsTreasury);
    }
    Ok(())
}

/// Native-order observation; `submitted` and `running` never imply success.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum ReceiptStatus { Submitted, Running, Succeeded, Failed, Cancelled }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExecutionReceipt {
    pub plan_id: String,
    pub step_id: String,
    pub native_order_id: Option<String>,
    pub status: ReceiptStatus,
    pub reason_code: String,
    pub tick: u64,
}

/// Stable idempotency identity across save/restore. Never use transient ECS Entity IDs.
pub fn dispatch_key(faction_id: &str, plan_id: &str, step_id: &str) -> String {
    // Length prefixes avoid collisions even if IDs contain separators.
    format!("{}:{}:{}:{}:{}:{}", faction_id.len(), faction_id,
        plan_id.len(), plan_id, step_id.len(), step_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> PlanningSnapshot {
        PlanningSnapshot {
            schema_version: SCHEMA_VERSION, tick: 500, faction_id: "genesis".into(),
            treasury_credits: 25_000, treasury_floor_credits: 10_000,
            owned_markets: vec![], facilities: vec![], ships: vec![],
            active_commitments: vec![], technologies: vec![], recipes: vec![],
        }
    }
    fn goal() -> GoalSpec { GoalSpec {goal_id:"water@colony".into(),destination_id:"colony".into(),commodity:Commodity::Water,target_units:10,priority:100} }
    fn action(id:&str, cost:i64) -> ActionSpec { ActionSpec {
        action_id:id.into(),kind:ActionKind::Deliver,source_id:Some("mine".into()),
        destination_id:"colony".into(),commodity:Some(Commodity::Ice),units:8,
        cost_credits:cost,expected_ticks:100,inputs:vec![],outputs:vec![],required_facility_type:None,
    } }
    fn plan() -> PlanResult {PlanResult {status:PlanStatus::Ready,goal_id:goal().goal_id,planner_id:"htn".into(),
        steps:vec![PlanStep{step_id:"s1".into(),action_id:"deliver_ice".into(),depends_on:vec![],expected_condition:"delivered".into()}],
        forecast_credits:1_000,forecast_ticks:100,nodes_expanded:17,explanation:"test".into()}}

    #[test]
    fn contracts_are_serializable_and_do_not_require_world() {
        let json=serde_json::to_string(&snapshot()).unwrap();
        assert_eq!(serde_json::from_str::<PlanningSnapshot>(&json).unwrap(),snapshot());
        assert_eq!(validate_plan(&snapshot(),&goal(),&[action("deliver_ice",1_000)],&plan(),SearchBudget::default()),Ok(()));
    }
    #[test]
    fn reject_impossible_spending_without_mutation() {
        let original=snapshot(); let mut expensive=plan();expensive.forecast_credits=20_000;
        assert_eq!(validate_plan(&original,&goal(),&[action("deliver_ice",20_000)],&expensive,SearchBudget::default()),Err(ValidationError::SpendExceedsTreasury));
        assert_eq!(original.treasury_credits,25_000);
    }
    #[test]
    fn reject_invalid_steps_or_forged_forecasts() {
        let allowed=[action("deliver_ice",1_000)];
        let mut unknown=plan();unknown.steps[0].action_id="not_native".into();
        assert_eq!(validate_plan(&snapshot(),&goal(),&allowed,&unknown,SearchBudget::default()),Err(ValidationError::UnknownAction));
        let mut repeat=plan();repeat.steps.push(repeat.steps[0].clone());repeat.forecast_credits=2_000;repeat.forecast_ticks=200;
        assert_eq!(validate_plan(&snapshot(),&goal(),&allowed,&repeat,SearchBudget::default()),Err(ValidationError::DuplicateStep));
        let mut fraud=plan();fraud.forecast_credits=0;
        assert_eq!(validate_plan(&snapshot(),&goal(),&allowed,&fraud,SearchBudget::default()),Err(ValidationError::InvalidForecast));
        let mut cycle=plan();cycle.steps[0].depends_on=vec!["s1".into()];
        assert_eq!(validate_plan(&snapshot(),&goal(),&allowed,&cycle,SearchBudget::default()),Err(ValidationError::InvalidDependency));
    }
    #[test]
    fn block_depth_and_node_budgets() {
        assert_eq!(validate_plan(&snapshot(),&goal(),&[action("deliver_ice",1_000)],&plan(),SearchBudget{max_nodes:10,max_depth:12}),Err(ValidationError::NodesExceeded));
        assert_eq!(validate_plan(&snapshot(),&goal(),&[action("deliver_ice",1_000)],&plan(),SearchBudget{max_nodes:20,max_depth:0}),Err(ValidationError::DepthExceeded));
    }
    #[test]
    fn idempotency_keys_cannot_collide_on_separators() {
        assert_ne!(dispatch_key("f:a","b","c"),dispatch_key("f","a:b","c"));
    }
}
