//! Expansion proposals for the faction head. The approved project lives on
//! the native construction site, and its shipments use the contract board.
use std::{collections::BTreeMap, sync::Arc};

use super::*;
use crate::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit, BodyResources},
        construction::{ConstructionSite, CONSTRUCTION_PROGRESS_REQUIRED, LABOR_REQUIRED},
        population::{PopDemographics, PopIdentity, PASSENGER_PAYMENT_PER_HEAD},
        ship::{ShipCargo, ShipEconomy, ShipFuel, ShipIdentity, ShipPosition},
    },
    economy::contracts::ContractType,
    simulation::config::ship_class,
    world::registry::WorldRegistry,
};

pub const DOCK_TYPE: &str = "construction_dock";
pub const LOCATION_TYPE: &str = "colony";
pub const PROJECT_TAG: &str = "strategy.colony.v1";
pub const SETTLERS: u32 = 10;
const MIN_REMAINING_POPULATION: i64 = SETTLERS as i64;

/// The current navigator pursues a moving target. Prefer bodies the assigned
/// hull can catch instead of authorizing an expedition that can orbit forever.
pub(super) fn can_rendezvous(orbit: &BodyOrbit, speed_modifier: f32) -> bool {
    orbit.orbit_period > 0
        && std::f32::consts::TAU * orbit.orbit_radius / (orbit.orbit_period as f32)
            < crate::agents::ship::SHIP_BASE_VELOCITY * speed_modifier
}

#[derive(Resource)]
pub struct Navigation(pub Arc<WorldRegistry>);

#[derive(Clone)]
pub(super) struct Plan {
    pub goal: Goal,
    pub source: String,
    pub body: BodyIdentity,
    pub site_id: Option<String>,
    pub cost: i64,
    pub quantity: u32,
    pub passenger: bool,
    pub reason: &'static str,
}

pub(super) fn proposals(
    world: &mut World,
    board: &ContractBoard,
    relations: &FactionRelations,
) -> BTreeMap<String, Plan> {
    let settlers=if world.get_resource::<super::director::Director>().is_some(){50}else{SETTLERS};
    let Some(registry) = world.get_resource::<Navigation>().map(|n| n.0.clone()) else {
        return BTreeMap::new();
    };
    let ports: Vec<_> = world
        .query::<(Entity, &FacilityIdentity, &FacilityLocation)>()
        .iter(world)
        .map(|(e, id, l)| (e, id.clone(), l.location_name.clone()))
        .collect();
    let occupied: std::collections::HashSet<_> =
        ports.iter().map(|(_, i, _)| i.body_id.as_str()).collect();
    let sites: Vec<_> = world
        .query::<&ConstructionSite>()
        .iter(world)
        .cloned()
        .collect();
    let bodies: Vec<_> = world
        .query::<(&BodyIdentity, &BodyOrbit, &BodyResources)>()
        .iter(world)
        .map(|(i, orbit, r)| (i.clone(), orbit.clone(), r.resources.clone()))
        .collect();
    let people: Vec<_> = world
        .query::<(&PopIdentity, &PopDemographics)>()
        .iter(world)
        .map(|(i, d)| (i.clone(), d.population_count))
        .collect();
    let ships: Vec<_> = world
        .query::<(
            &ShipIdentity,
            &ShipCargo,
            &ShipEconomy,
            &ShipPosition,
            &ShipFuel,
        )>()
        .iter(world)
        .map(|(id, c, e, p, f)| {
            (
                id.clone(),
                c.capacity,
                e.credits,
                p.location_name.clone(),
                f.fraction(),
                f.speed_modifier,
            )
        })
        .collect();
    let markets: Vec<_> = world
        .query::<(&MarketIdentity, &MarketPricing)>()
        .iter(world)
        .map(|(i, p)| (i.clone(), p.clone()))
        .collect();

    world
        .query::<&FactionData>()
        .iter(world)
        .filter_map(|f| {
            // Keep at most one founding expedition per faction. Existing colonies
            // remain ordinary stations and can in turn sponsor expansion.
            if let Some(site) = sites
                .iter()
                .filter(|s| s.faction_id == f.id && !s.completed && s.labor.colony_source.is_some())
                .min_by_key(|s| &s.id)
            {
                let source = site.labor.colony_source.as_ref().unwrap();
                let (body, _, _) = bodies.iter().find(|(b, _, _)| b.body_id == site.body_id)?;
                let settled = people.iter().any(|(p, n)| {
                    p.facility_location == site.location_name
                        && p.faction_id == f.id
                        && *n >= i64::from(settlers)
                });
                let passenger = !settled;
                let quantity = if passenger {
                    settlers
                } else {
                    site.remaining().min(faction::CONSTRUCTION_QUANTITY)
                };
                let cost = if passenger {
                    i64::from(quantity) * PASSENGER_PAYMENT_PER_HEAD
                } else {
                    faction::CONSTRUCTION_BASE_PAYMENT
                };
                let reason = if board.iter().any(|c| {
                    c.requestor_id == f.id
                        && c.destination_location == site.location_name
                        && outstanding(c)
                }) {
                    "colony_contract_in_progress"
                } else if quantity == 0 {
                    "awaiting_paid_labor"
                } else if f.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR)
                    < cost
                        + construction::STARTUP_CAPITAL
                        + i64::from(site.labor.required.saturating_sub(site.labor.completed))
                            * crate::agents::facility::workforce::WAGE_PER_SHIFT
                {
                    "insufficient_colony_budget"
                } else if passenger
                    && !people.iter().any(|(p, n)| {
                        p.facility_location == *source
                            && p.faction_id == f.id
                            && *n >= i64::from(settlers) + MIN_REMAINING_POPULATION
                    })
                {
                    "insufficient_settlers"
                } else if !passenger
                    && !markets.iter().any(|(i, p)| {
                        i.facility_location == *source
                            && p.supply
                                .get(&Commodity::Metals)
                                .is_some_and(|s| s.is_finite() && *s >= quantity as f32)
                            && sourcing::purchase_cost(
                                p.price(Commodity::Metals),
                                quantity,
                                relations,
                                &f.id,
                                0,
                                &f.id,
                            )
                            .is_some_and(|price| price < cost)
                    })
                {
                    "insufficient_affordable_metals"
                } else {
                    "ready"
                };
                return Some((
                    f.id.clone(),
                    Plan {
                        goal: goal(&site.location_name, 0.0),
                        source: source.clone(),
                        body: body.clone(),
                        site_id: Some(site.id.clone()),
                        quantity,
                        cost,
                        passenger,
                        reason,
                    },
                ));
            }

            let cost =
                i64::from(CONSTRUCTION_PROGRESS_REQUIRED.div_ceil(faction::CONSTRUCTION_QUANTITY))
                    * faction::CONSTRUCTION_BASE_PAYMENT
                    + construction::STARTUP_CAPITAL
                    + i64::from(LABOR_REQUIRED)
                        * crate::agents::facility::workforce::WAGE_PER_SHIFT
                    + i64::from(settlers) * PASSENGER_PAYMENT_PER_HEAD;
            let mut best: Option<Plan> = None;
            for (body, orbit, resources) in &bodies {
                if body.body_type != "planet"
                    || occupied.contains(body.body_id.as_str())
                    || sites
                        .iter()
                        .any(|s| s.body_id == body.body_id && !s.completed)
                {
                    continue;
                }
                let ore = resources.get(&Commodity::Ore).copied().unwrap_or(0.0);
                let ice = resources.get(&Commodity::Ice).copied().unwrap_or(0.0);
                let gas=resources.get(&Commodity::Gas).copied().unwrap_or(0.0);
                // A colony can specialize: e.g. Refuge produces ice and gas
                // while ore arrives from another body in Alpha Centauri.
                // There is no requirement to have ALL raw resources at one
                // landing site. A barren body with no extraction prospect is
                // skipped for now.
                if ore <= 0.0 && ice <= 0.0 && gas <= 0.0 {
                    continue;
                }
                let destination = format!("{}-colony", body.body_id);
                if !registry.locations.get(&destination).is_some_and(|l| {
                    l.loc_type == LOCATION_TYPE && l.celestial_body_id == body.db_id
                }) {
                    continue;
                }
                for (entity, port, source) in &ports {
                    if port.faction_id != f.id || port.facility_type == DOCK_TYPE {
                        continue;
                    }
                    let Some(distance) = registry.shortest_distance(source, &destination) else {
                        continue;
                    };
                    let Some((_, stock)) = markets.iter().find(|(m, _)| m.facility == *entity)
                    else {
                        continue;
                    };
                    let reason = if world.get_resource::<super::director::Director>().is_some() && !super::director::has(world,&f.id,"orbital_habitats") {
                        "requires_orbital_habitats"
                    } else if world.get_resource::<super::director::Director>().is_some() && distance>100 && !super::director::has(world,&f.id,"deep_navigation") {
                        "requires_deep_navigation"
                    } else if f.treasury.saturating_sub(faction::FACTION_SUBSIDY_FLOOR) < cost
                    {
                        "insufficient_colony_budget"
                    } else if !people.iter().any(|(p, n)| {
                        p.facility_location == *source
                            && p.faction_id == f.id
                            && *n >= i64::from(settlers) + MIN_REMAINING_POPULATION
                    }) {
                        "insufficient_settlers"
                    } else if !stock.supply.get(&Commodity::Metals).is_some_and(|n| {
                        n.is_finite() && *n >= CONSTRUCTION_PROGRESS_REQUIRED as f32
                    }) {
                        "insufficient_affordable_metals"
                    } else {
                        let quote = sourcing::purchase_cost(
                            stock.price(Commodity::Metals),
                            faction::CONSTRUCTION_QUANTITY,
                            relations,
                            &f.id,
                            0,
                            &f.id,
                        );
                        let mut passenger = false;
                        let mut carrier = false;
                        let mut engineer = false;
                        for (ship, capacity, credits, location, fuel, speed) in &ships {
                            if ship.faction_id != f.id
                                || *fuel <= 0.0
                                || !can_rendezvous(orbit, *speed)
                                || !location.as_ref().is_some_and(|l| {
                                    l == source || registry.shortest_distance(l, source).is_some()
                                })
                            {
                                continue;
                            }
                            passenger |= ship_class(&ship.class)
                                .is_some_and(|c| c.passenger_capacity >= settlers);
                            carrier |= *capacity >= faction::CONSTRUCTION_QUANTITY
                                && quote.is_some_and(|q| {
                                    q < faction::CONSTRUCTION_BASE_PAYMENT && *credits >= q
                                });
                            engineer |= crate::agents::construction::executor::capable(&ship.class);
                        }
                        if !passenger {
                            "no_passenger_transport"
                        } else if !carrier {
                            "no_viable_local_carrier"
                        } else if !engineer {
                            "no_viable_local_builder"
                        } else {
                            "ready"
                        }
                    };
                    let gas_need=stock.supply.get(&Commodity::Gas).copied().unwrap_or(0.0)<50.0;
                    // Prefer growing around an existing owned STATION
                    // in the same star system. No hard-coded star/system ID:
                    // works for each faction and later player colonies.
                    // A faraway expedition remains possible when its real
                    // value + logistics justify it.
                    let same_local_system = ports.iter().any(|(_, own, _)| {
                        own.faction_id == f.id
                            && own.facility_type == "station"
                            && bodies.iter().any(|(home,_,_)| {
                                home.body_id == own.body_id
                                    && home.star_system_id == body.star_system_id
                            })
                    });
                    let specialty = ore.max(ice).max(gas);
                    let gas_value = if gas_need {gas * 0.55} else {gas * 0.10};
                    let local_factor = if same_local_system { 4.0 } else { 1.0 };
                    let score = (0.1 + specialty + gas_value) * local_factor
                        / (1.0 + distance as f32);
                    let plan = Plan {
                        goal: goal(&destination, score),
                        source: source.clone(),
                        body: body.clone(),
                        site_id: None,
                        cost,
                        quantity: settlers,
                        passenger: true,
                        reason,
                    };
                    if best.as_ref().is_none_or(|old| {
                        (plan.reason == "ready")
                            .cmp(&(old.reason == "ready"))
                            .then_with(|| plan.goal.score.total_cmp(&old.goal.score))
                            .then_with(|| old.goal.destination.cmp(&plan.goal.destination))
                            .then_with(|| old.source.cmp(&plan.source))
                            .is_gt()
                    }) {
                        best = Some(plan);
                    }
                }
            }
            best.map(|plan| (f.id.clone(), plan))
        })
        .collect()
}

fn goal(destination: &str, score: f32) -> Goal {
    Goal {
        goal_id: "found_colony".into(),
        commodity: Commodity::Metals,
        destination: destination.into(),
        shortage_ticks: 0,
        score,
    }
}

pub(super) fn commission(
    world: &mut World,
    board: &mut ContractBoard,
    events: &mut Vec<serde_json::Value>,
    faction_id: &str,
    plan: &Plan,
    tick: u64,
    mult: u32,
) -> i64 {
    let destination = &plan.goal.destination;
    if plan.site_id.is_none() {
        if world
            .query::<&ConstructionSite>()
            .iter(world)
            .any(|s| s.body_id == plan.body.body_id && !s.completed)
        {
            return 0;
        }
        let Some(center) = world
            .query::<(&BodyIdentity, &BodyOrbit)>()
            .iter(world)
            .find(|(id, _)| id.db_id == plan.body.db_id)
            .map(|(_, o)| o.universe_position())
        else {
            return 0;
        };
        let id = format!("site-station-{destination}-{tick}");
        let position = crate::agents::facility::facility_offset_position(center, &id);
        let mut site = ConstructionSite {
            id: id.clone(),
            name: format!("{} Colony", plan.body.name),
            facility_type: "station".into(),
            faction_id: faction_id.into(),
            body_id: plan.body.body_id.clone(),
            location_name: destination.clone(),
            commodity: Commodity::Metals,
            progress_delivered: 0,
            progress_required: CONSTRUCTION_PROGRESS_REQUIRED,
            position,
            spawned_at_tick: tick,
            completed: false,
            dirty: true,
            labor: Default::default(),
        };
        site.labor.colony_source = Some(plan.source.clone());
        world.spawn(site);
        events.push(serde_json::json!({
            "kind":"colony_approved", "faction_id":faction_id, "site_id":id, "tick":tick,
            "source":plan.source, "destination":destination, "body_id":plan.body.body_id, "estimated_cost":plan.cost,
        }));
        return 0;
    }
    let distance=world.get_resource::<Navigation>().and_then(|n|n.0.shortest_distance(&plan.source,destination)).unwrap_or(0);
    let base_lifespan=if world.get_resource::<super::director::Director>().is_some(){faction::CONSTRUCTION_LIFESPAN_BASE.max(u64::from(distance)*100+1200)}else{faction::CONSTRUCTION_LIFESPAN_BASE};
    let mut payer = world
        .query::<&mut FactionData>()
        .iter_mut(world)
        .find(|f| f.id == faction_id)
        .expect("head has a treasury");
    if payer
        .treasury
        .saturating_sub(faction::FACTION_SUBSIDY_FLOOR)
        < plan.cost
    {
        return 0;
    }
    let lifespan = base_lifespan * u64::from(mult);
    let id = if plan.passenger {
        board.post_passenger_for(
            faction_id.into(),
            Some(faction_id.into()),
            plan.quantity,
            plan.source.clone(),
            destination.clone(),
            plan.cost,
            tick,
            lifespan,
        )
    } else {
        board.post_construction(
            faction_id.into(),
            Some(faction_id.into()),
            Commodity::Metals,
            plan.quantity,
            plan.source.clone(),
            destination.clone(),
            plan.cost,
            tick,
            lifespan,
        )
    };
    payer.treasury -= plan.cost;
    payer.dirty = true;
    board.register_prepaid(&id, FundingSource::Faction);
    let contract = board.get_mut(&id).unwrap();
    debug_assert!(matches!(
        contract.contract_type,
        ContractType::Construction | ContractType::Passenger
    ));
    contract.mission_category = Some(PROJECT_TAG.into());
    plan.cost
}
