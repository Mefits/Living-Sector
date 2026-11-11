//! Block IV: colony aftercare on the *real* Galaxy economy.
//!
//! Nothing in this module produces stock, population or construction progress.
//! It reads native markets, households, facilities, ships and commitments. The
//! sole writer is a prepaid Passenger contract, processed by the existing
//! embark/deliver pipeline. Supply goals are executed by native HTN/hybrid.
use super::*;
use crate::agents::{
    facility::{FacilityCrew, FacilityIdentity, FacilityLocation},
    population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment,
        CONSUMPTION_INTERVAL_BASE, EMERGENCY_WATER_RATE,
        EMERGENCY_WATER_THRESHOLD, PASSENGER_PAYMENT_PER_HEAD},
    ship::{ShipCargo, ShipEconomy, ShipFuel, ShipIdentity, ShipPosition, ShipTransit},
};
use crate::economy::contracts::ContractType;
use crate::simulation::config::ship_class;

pub const MIGRATION_TAG: &str = "strategy.colony.workforce.v1";
const MIN_LIFE_SUPPORT_STOCK: f32 = 20.0;
/// Forecast is deliberately conservative but bounded: 80 native purchase
/// cycles = 400 base ticks, multiplied by world speed just like purchases.
/// Route ETA is not accurately known until a carrier is dispatched, so
/// use a stable buffer now; never pretend a receipt equals future stock.
const LIFE_SUPPORT_BUFFER_CYCLES: f32 = 80.0;
// Native consumption is paid every CONSUMPTION_INTERVAL_BASE × tick_multiplier.
const _: u64 = CONSUMPTION_INTERVAL_BASE;
const MAX_FORECAST_RESERVE: f32 = 180.0;
const INDUSTRY_ELECTRONICS_TARGET: f32 = 10.0;
const MAX_MIGRATION_PARTY: u32 = 20;
const MIN_SOURCE_RESERVE: i64 = colony::SETTLERS as i64;

#[derive(Clone, Debug, Serialize)]
pub struct ColonyView {
    pub faction_id: String,
    pub location: String,
    pub population: i64,
    pub available_workers: i64,
    pub required_workers: i64,
    pub missing_workers: i64,
    pub water: Option<f32>,
    pub food: Option<f32>,
    pub electronics: Option<f32>,
    /// Actual market fuel; not a station's invisible free fuel reserve.
    pub fuel: Option<f32>,
    pub water_reserve_target: Option<f32>,
    pub food_reserve_target: Option<f32>,
    pub facilities: Vec<String>,
    pub phase: String,
    pub reason: String,
    pub next_commodity: Option<Commodity>,
    pub pending_passenger_contract: Option<String>,
    pub market_unambiguous: bool,
}

fn stock(market: &MarketPricing, commodity: Commodity) -> Option<f32> {
    let quantity = market.supply.get(&commodity).copied().unwrap_or(0.0);
    (quantity.is_finite() && quantity >= 0.0).then_some(quantity)
}
fn reserve(market: &MarketPricing, commodity: Commodity, per_purchase: f32) -> Option<f32> {
    let demand = market.demand.get(&commodity).copied().unwrap_or(0.0);
    if !demand.is_finite() || demand < 0.0 || !per_purchase.is_finite() || per_purchase < 0.0 {
        return None;
    }
    // Demand history alone misses starving households that cannot afford a
    // purchase. Derive an additional floor from the ACTUAL consumption
    // coefficients of all local households, including emergency water.
    let history_floor = (demand * 2.0).max(MIN_LIFE_SUPPORT_STOCK);
    let forecast_floor = (per_purchase * LIFE_SUPPORT_BUFFER_CYCLES)
        .min(MAX_FORECAST_RESERVE);
    let target = history_floor.max(forecast_floor);
    target.is_finite().then_some(target)
}

/// The returned data is descriptive, not a forecast of completed deliveries.
/// Multiple markets at a location are deliberately NOT combined.
pub fn observe(world: &mut World, board: &ContractBoard) -> Vec<ColonyView> {
    let mut facilities: Vec<_> = world.query::<(&FacilityIdentity, &FacilityLocation, &FacilityCrew)>()
        .iter(world).map(|(identity, location, crew)|
            (identity.clone(), location.location_name.clone(), crew.crew_count)).collect();
    facilities.sort_by(|a, b| a.0.id.cmp(&b.0.id));
    let markets: Vec<_> = world.query::<(&MarketIdentity, &MarketPricing)>()
        .iter(world).map(|(identity, pricing)|
            (identity.facility_location.clone(), identity.facility, pricing.clone())).collect();
    let people: Vec<_> = world.query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
        .iter(world).map(|(identity, demo, economy, sentiment)| {
            let count = demo.population_count.max(0);
            let share = count as f32 / 1000.0;
            let food = economy.consumption.get(&Commodity::Food).copied().unwrap_or(0.0)
                .max(0.0) * share;
            let emergency_water = if sentiment.food_satisfaction < EMERGENCY_WATER_THRESHOLD {
                EMERGENCY_WATER_RATE * share
            } else { 0.0 };
            let water = economy.consumption.get(&Commodity::Water).copied().unwrap_or(0.0)
                .max(0.0) * share + emergency_water;
            (identity.faction_id.clone(), identity.facility_location.clone(), count, food, water)
        }).collect();
    let mut result = Vec::new();
    for (station, location, _) in facilities.iter().filter(|(identity, location, _)|
        identity.facility_type == "station" && location.ends_with("-colony")) {
        let local: Vec<_> = facilities.iter().filter(|(f, loc, _)|
            f.faction_id == station.faction_id && loc == location).collect();
        let local_people: Vec<_> = people.iter().filter(|(f, loc, _, _, _)|
            f == &station.faction_id && loc == location).collect();
        let population: i64 = local_people.iter().map(|(_, _, count, _, _)| *count).sum();
        let food_per_purchase: f32 = local_people.iter().map(|(_, _, _, food, _)| *food).sum();
        let water_per_purchase: f32 = local_people.iter().map(|(_, _, _, _, water)| *water).sum();
        let required_workers: i64 = local.iter().filter(|(f, _, _)|
            matches!(f.facility_type.as_str(), "mining_rig" | "refinery" | "farm" | "factory"))
            .map(|(_, _, crew)| i64::from(*crew)).sum();
        let available_workers = population.saturating_mul(3) / 5;
        let missing_workers = (required_workers - available_workers).max(0);
        let mut local_markets = markets.iter().filter(|(loc, _, _)| loc == location);
        let first = local_markets.next();
        let unique = first.is_some() && local_markets.next().is_none();
        let market = first.filter(|(_, entity, _)|
            unique && facilities.iter().any(|(f, loc, _)|
                loc == location && f.id == station.id &&
                world.get::<FacilityIdentity>(*entity).is_some_and(|owner|owner.id == station.id)));
        let pricing = market.map(|(_, _, p)| p);
        let fuel=pricing.and_then(|p|stock(p,Commodity::Fuel));
        let (water, food, electronics, water_target, food_target) = if let Some(pricing) = pricing {
            (stock(pricing, Commodity::Water), stock(pricing, Commodity::Food),
             stock(pricing, Commodity::Electronics),
             reserve(pricing, Commodity::Water, water_per_purchase),
             reserve(pricing, Commodity::Food, food_per_purchase))
        } else {(None, None, None, None, None)};
        let has = |kind: &str| local.iter().any(|(f, _, _)| f.facility_type == kind);
        let pending_passenger_contract = board.iter().filter(|c|
            c.contract_type == ContractType::Passenger && c.requestor_id == station.faction_id &&
            c.destination_location == *location && super::outstanding(c))
            .map(|c| c.id.clone()).min();
        let (phase, reason, next_commodity) = if !unique || pricing.is_none() {
            ("blocked", "ambiguous_or_missing_colony_market", None)
        } else if water.is_none() || food.is_none() || water_target.is_none() || food_target.is_none() {
            ("blocked", "invalid_colony_life_support_stock", None)
        } else if population == 0 {
            ("awaiting_population", "no_resident_household", None)
        } else if water.zip(water_target).is_some_and(|(s, t)| s < t) ||
                  food.zip(food_target).is_some_and(|(s, t)| s < t) {
            let water_ratio = water.zip(water_target).map_or(f32::INFINITY, |(s,t)|s/t);
            let food_ratio = food.zip(food_target).map_or(f32::INFINITY, |(s,t)|s/t);
            let kind = if water_ratio <= food_ratio {Commodity::Water} else {Commodity::Food};
            ("life_support", "colony_essential_reserve_below_target", Some(kind))
        } else if !has("mining_rig") {
            ("building", "colony_needs_mining_rig", None)
        } else if !has("refinery") {
            ("building", "colony_needs_refinery", None)
        } else if !has("farm") {
            ("building", "colony_needs_farm", None)
        } else if missing_workers > 0 {
            if pending_passenger_contract.is_some() {
                ("migration", "passenger_contract_in_progress", None)
            } else { ("migration", "colony_needs_workers", None) }
        } else if !has("factory") {
            ("building", "colony_needs_factory", None)
        } else if electronics.is_some_and(|s|s < INDUSTRY_ELECTRONICS_TARGET) {
            ("industrial_chain", "colony_needs_electronics", Some(Commodity::Electronics))
        } else {
            ("operational", "colony_life_support_and_industry_present", None)
        };
        result.push(ColonyView {
            faction_id: station.faction_id.clone(), location: location.clone(),
            population, available_workers, required_workers, missing_workers,
            water, food, electronics, fuel, water_reserve_target:water_target,
            food_reserve_target:food_target,
            facilities:local.iter().map(|(f, _, _)|f.facility_type.clone()).collect(),
            phase:phase.into(), reason:reason.into(), next_commodity,
            pending_passenger_contract, market_unambiguous:unique && pricing.is_some(),
        });
    }
    result.sort_by(|a,b|a.faction_id.cmp(&b.faction_id).then_with(||a.location.cmp(&b.location)));
    result
}

/// Return only a need with a unique live market, resident population and no
/// outstanding shipment for the SAME commodity. The planner still must find
/// an actual funded route, recipe and production receipt.
pub(super) fn next_supply_goal(views:&[ColonyView], board:&ContractBoard, faction:&str)
    -> Option<Goal> {
    let mut options=Vec::new();
    for c in views.iter().filter(|c|c.faction_id==faction && c.market_unambiguous && c.population>0) {
        // A shipment of water in flight does NOT prohibit an independent food
        // plan. Inspect both actual reserve shortages, not a single label.
        for (commodity,current,target) in [
            (Commodity::Water,c.water,c.water_reserve_target),
            (Commodity::Food,c.food,c.food_reserve_target),
        ] {
            if !current.zip(target).is_some_and(|(s,t)|t>0.0 && s<t) {continue;}
            if board.iter().any(|contract| contract.destination_location==c.location &&
                contract.commodity==commodity && super::outstanding(contract) &&
                contract.contract_type!=ContractType::Passenger) {continue;}
            let ratio=current.unwrap_or(0.0)/target.unwrap_or(1.0);
            options.push(Goal {goal_id:"colony_life_support".into(),commodity,
                destination:c.location.clone(),shortage_ticks:0,
                score:1500.0+(1.0-ratio)*100.0});
        }
        // Ships refuel from the real dock reserve, with additional fuel now
        // transferable from the dock's OWN market stock (0.4.1). Until a
        // carrier physically delivers it, an empty colony still has none.
        // Lower priority than food and water so rescue ships are not used
        // for fuel while residents are starving.
        if c.fuel.is_some_and(|f|f<20.0)
            && !board.iter().any(|contract|contract.destination_location==c.location
                && contract.commodity==Commodity::Fuel
                && super::outstanding(contract)
                && contract.contract_type!=ContractType::Passenger) {
            options.push(Goal{goal_id:"colony_service_fuel".into(),
                commodity:Commodity::Fuel,destination:c.location.clone(),
                shortage_ticks:0,score:600.0});
        }
        // The electronics objective is real only if a factory has materialised,
        // staff is available, and essential supplies are already secure.
        if c.phase=="industrial_chain" && c.next_commodity==Some(Commodity::Electronics) &&
            c.missing_workers==0 && !board.iter().any(|contract|
                contract.destination_location==c.location &&
                contract.commodity==Commodity::Electronics && super::outstanding(contract) &&
                contract.contract_type!=ContractType::Passenger) {
            options.push(Goal{goal_id:"colony_electronics_chain".into(),
                commodity:Commodity::Electronics,destination:c.location.clone(),
                shortage_ticks:0,score:55.0});
        }
    }
    options.into_iter().max_by(|a,b|a.score.total_cmp(&b.score)
        .then_with(||b.destination.cmp(&a.destination))
        .then_with(||b.commodity.as_str().cmp(a.commodity.as_str())))
}

#[derive(Clone, Debug)]
pub(super) struct MigrationPlan {
    pub destination:String,
    pub source:String,
    pub quantity:u32,
    pub payment:i64,
    pub reason:&'static str,
}

/// One physical household-to-household trip, only after essential reserves are
/// present. The recipient MUST exist: native delivery cannot spawn households.
pub(super) fn migration_proposals(world:&mut World,board:&ContractBoard,views:&[ColonyView])
    -> BTreeMap<String,MigrationPlan> {
    let mut result=BTreeMap::new();
    let nav=world.get_resource::<colony::Navigation>().map(|n|n.0.clone());
    let owners:Vec<_>=world.query::<&FactionData>().iter(world)
        .map(|f|(f.id.clone(),f.treasury)).collect();
    let settlements:Vec<_>=world.query::<(&PopIdentity,&PopDemographics)>().iter(world)
        .map(|(p,d)|(p.faction_id.clone(),p.facility_location.clone(),d.population_count.max(0))).collect();
    let stations:Vec<_>=world.query::<(&FacilityIdentity,&FacilityLocation)>().iter(world)
        .filter(|(i,_)|i.facility_type=="station")
        .map(|(i,l)|(i.faction_id.clone(),l.location_name.clone())).collect();
    let assigned:std::collections::BTreeSet<&str>=board.iter().filter(|c|super::outstanding(c))
        .filter_map(|c|c.fulfiller_id.as_deref()).collect();
    let ships:Vec<_>=world.query::<(&ShipIdentity,&ShipCargo,&ShipEconomy,&ShipFuel,&ShipPosition,&ShipTransit)>()
        .iter(world).filter(|(i,_,e,f,_,t)|e.active_contract_id.is_none() &&
            !assigned.contains(i.id.as_str()) && t.transit.is_none() && f.fuel>0.0)
        .map(|(i,_,_,_,p,_)|(i.faction_id.clone(),i.class.clone(),p.location_name.clone())).collect();
    for c in views.iter().filter(|c|c.phase=="migration" && c.missing_workers>0 &&
        c.pending_passenger_contract.is_none() && c.market_unambiguous &&
        c.water.zip(c.water_reserve_target).is_some_and(|(s,t)|s>=t) &&
        c.food.zip(c.food_reserve_target).is_some_and(|(s,t)|s>=t)) {
        let quantity=((c.missing_workers*5+2)/3).clamp(1,i64::from(MAX_MIGRATION_PARTY)) as u32;
        let payment=i64::from(quantity).saturating_mul(PASSENGER_PAYMENT_PER_HEAD);
        if owners.iter().find(|(id,_)|id==&c.faction_id)
            .is_none_or(|(_,cash)|cash.saturating_sub(faction::FACTION_SUBSIDY_FLOOR)<payment) {continue;}
        if nav.is_none() {continue;}
        let registry=nav.as_ref().unwrap();
        let mut sources:Vec<_>=stations.iter().filter(|(id,loc)|id==&c.faction_id && loc!=&c.location)
            .filter(|(_,loc)|registry.shortest_distance(loc,&c.location).is_some())
            .filter(|(_,loc)|settlements.iter().any(|(id,pop_loc,n)|id==&c.faction_id &&
                pop_loc==loc && *n >= i64::from(quantity)+MIN_SOURCE_RESERVE))
            .map(|(_,loc)|loc.clone()).collect();
        sources.sort();sources.dedup();
        let source=sources.into_iter().find(|source|ships.iter().any(|(id,class,position)|
            id==&c.faction_id && ship_class(class).is_some_and(|info|info.passenger_capacity>=quantity) &&
            position.as_ref().is_some_and(|p|p==source || registry.shortest_distance(p,source).is_some())));
        if let Some(source)=source {
            result.entry(c.faction_id.clone()).or_insert(MigrationPlan {
                destination:c.location.clone(),source,quantity,payment,reason:"ready",
            });
        }
    }
    result
}

/// This is the ONLY mutating operation in colony aftercare. Passengers and
/// escrow are not simulated here: actual boarding, transport, payout and
/// household transfer remain native Genesis operations.
pub(super) fn commission(world:&mut World,board:&mut ContractBoard,events:&mut Vec<serde_json::Value>,
    faction_id:&str,plan:&MigrationPlan,tick:u64,mult:u32)->i64 {
    if plan.reason!="ready" || plan.quantity==0 || plan.source==plan.destination ||
        board.iter().any(|c|c.contract_type==ContractType::Passenger &&
            c.requestor_id==faction_id && c.destination_location==plan.destination && super::outstanding(c)) {
        return 0;
    }
    let valid_people={
        let mut query=world.query::<(&PopIdentity,&PopDemographics)>();
        let mut origin=false;let mut recipient=false;
        for (id,d) in query.iter(world).filter(|(id,_)|id.faction_id==faction_id) {
            if id.facility_location==plan.source &&
                d.population_count>=i64::from(plan.quantity)+MIN_SOURCE_RESERVE {origin=true;}
            if id.facility_location==plan.destination {recipient=true;}
        }
        origin && recipient
    };
    if !valid_people {return 0;}
    let navigable=world.get_resource::<colony::Navigation>().is_some_and(|nav|
        nav.0.shortest_distance(&plan.source,&plan.destination).is_some());
    let idle_carrier=world.query::<(&ShipIdentity,&ShipEconomy,&ShipFuel,&ShipPosition,&ShipTransit)>()
        .iter(world).any(|(id,e,f,p,t)|id.faction_id==faction_id &&
            ship_class(&id.class).is_some_and(|spec|spec.passenger_capacity>=plan.quantity) &&
            e.active_contract_id.is_none() && t.transit.is_none() && f.fuel>0.0 &&
            p.location_name.as_ref().is_some_and(|loc|loc==&plan.source ||
                world.get_resource::<colony::Navigation>().is_some_and(|nav|
                    nav.0.shortest_distance(loc,&plan.source).is_some())));
    if !navigable || !idle_carrier {return 0;}
    let Some((payer,_))=world.query::<(Entity,&FactionData)>().iter(world)
        .find(|(_,f)|f.id==faction_id &&
            f.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR)>=plan.payment) else{return 0;};
    let base=faction::CONSTRUCTION_LIFESPAN_BASE;
    let lifespan=base.saturating_mul(u64::from(mult.max(1)));
    let contract=board.post_passenger_for(faction_id.into(),Some(faction_id.into()),
        plan.quantity,plan.source.clone(),plan.destination.clone(),plan.payment,tick,lifespan);
    board.register_prepaid(&contract,FundingSource::Faction);
    if let Some(c)=board.get_mut(&contract){c.mission_category=Some(MIGRATION_TAG.into());}
    if let Some(mut account)=world.get_mut::<FactionData>(payer){account.treasury-=plan.payment;account.dirty=true;}
    events.push(serde_json::json!({"kind":"colony_workforce_contract_posted","faction_id":faction_id,
        "contract_id":contract,"destination":plan.destination,"source":plan.source,
        "passengers":plan.quantity,"tick":tick}));
    plan.payment
}


#[cfg(test)]
mod galaxy04_life_support_reserve_tests {
    use super::*;
    use std::collections::HashMap;

    fn market(demand: f32) -> MarketPricing {
        MarketPricing {
            price_elasticity: 0.02,
            spread: 0.1,
            prices: HashMap::new(),
            supply: HashMap::new(),
            demand: [(Commodity::Food, demand)].into(),
        }
    }

    #[test]
    fn unpurchased_hunger_still_requires_physical_stock() {
        let m = market(0.0);
        assert_eq!(reserve(&m, Commodity::Food, 0.75), Some(60.0));
        assert_eq!(reserve(&m, Commodity::Food, 0.0), Some(20.0));
    }

    #[test]
    fn market_demand_is_not_reduced_by_forecast_ceiling() {
        let m = market(150.0);
        assert_eq!(reserve(&m, Commodity::Food, 10.0), Some(300.0));
        assert_eq!(reserve(&m, Commodity::Food, f32::INFINITY), None);
    }
}
