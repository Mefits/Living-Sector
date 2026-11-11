//! Durable station dispatch over native contracts and construction sites.
//! No second ledger, cargo inventory, population or payment path.
use std::collections::{HashMap, HashSet};
use bevy_ecs::prelude::World;
use serde::{Deserialize, Serialize};
use crate::{
    agents::{celestial_body::{BodyIdentity, BodyOrbit}, construction::ConstructionSite, faction_relations::{FactionRelations, commerce_allowed, market_controllers},
        market::{MarketIdentity, MarketPricing}, ship::{ShipIdentity, ShipPosition, ShipTransit, ShipCargo, ShipEconomy, ShipFuel}},
    economy::{commodities::Commodity, contracts::{Contract, ContractBoard, ContractStatus, ContractType}},
    world::registry::WorldRegistry,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Order {
    pub order_id: String,
    pub executor_id: Option<String>,
    pub state: String,
    pub blocked_reason: Option<String>,
    pub attempt: u32,
    pub assigned_tick: u64,
    pub retry_after_tick: u64,
}
impl Order {
    pub fn new(kind: &str, id: &str) -> Self {
        Self { order_id: format!("station:{kind}:{id}"), executor_id: None, state: "waiting".into(),
            blocked_reason: None, attempt: 0, assigned_tick: 0, retry_after_tick: 0 }
    }
    fn assign(&mut self, ship: String, tick: u64) {
        self.executor_id=Some(ship); self.assigned_tick=tick;
        self.attempt=self.attempt.saturating_add(1); self.state="assigned".into(); self.blocked_reason=None;
    }
    fn release(&mut self, reason: &str, tick: u64, cooldown: u64) {
        self.executor_id=None; self.state="blocked".into(); self.blocked_reason=Some(reason.into());
        self.retry_after_tick=tick.saturating_add(cooldown);
    }
}
#[derive(Debug, Clone, Serialize)]
pub struct OrderView {
    #[serde(flatten)] pub order: Order,
    pub faction_id: String,
    pub location: String,
    pub kind: &'static str,
    pub target_id: String,
    pub commodity: Option<Commodity>,
    pub quantity: u32,
    pub completed_quantity: u32,
}

pub fn contract_order(c: &Contract) -> Option<&Order> { c.funding.as_ref()?.station_order.as_ref() }
pub fn may_accept(c: &Contract, ship: &str, faction: &str) -> bool {
    contract_order(c).is_none_or(|o| c.faction_id.as_deref()==Some(faction)
        && o.executor_id.as_deref()==Some(ship))
}
pub fn assigned_contract<'a>(board: &'a ContractBoard, ship: &str) -> Option<&'a Contract> {
    board.iter().filter(|c| matches!(c.status, ContractStatus::Posted|ContractStatus::Accepted|ContractStatus::PickedUp)
        && contract_order(c).is_some_and(|o|o.executor_id.as_deref()==Some(ship)))
        .min_by(|a,b|a.id.cmp(&b.id))
}
pub fn builder_assigned(world:&mut World, ship:&str)->bool {
    world.query::<&ConstructionSite>().iter(world).any(|s|!s.completed && s.labor.completed<s.labor.required
        && s.labor.station_order.as_ref().is_some_and(|o|o.executor_id.as_deref()==Some(ship)))
}

struct Carrier { id:String, faction:String, class:String, location:String, free:u32,
    credits:i64, fuel:f32, speed:f32, busy:bool, reputation:HashMap<String,u8> }
fn distance(registry: &WorldRegistry, from: &str, to: &str) -> Option<u32> {
    if from==to { Some(0) } else { registry.shortest_distance(from,to) }
}

/// Sequential arbitration before the parallel ship pass. Accepted contracts own
/// their carriers until native release/settlement. Orders do not reserve stock.
pub fn dispatch(world: &mut World, board: &mut ContractBoard, relations: &FactionRelations,
    registry: &WorldRegistry, tick: u64, multiplier: u32) {
    if !super::executing(world) { return; }
    let cooldown=30*u64::from(multiplier.max(1));
    let lease=300*u64::from(multiplier.max(1));
    let owners=market_controllers(world);
    let markets:HashMap<_,_>=world.query::<(&MarketIdentity,&MarketPricing)>().iter(world)
        .map(|(id,p)|(id.facility_location.clone(),p.clone())).collect();
    let orbits: HashMap<_, _> = world.query::<(&BodyIdentity, &BodyOrbit)>().iter(world)
        .map(|(id, orbit)| (id.db_id, orbit.clone())).collect();
    let reachable = |location: &str, speed| registry.locations.get(location)
        .and_then(|location| orbits.get(&location.celestial_body_id))
        .is_some_and(|orbit| super::colony::can_rendezvous(orbit, speed));
    let galaxy = world.get_resource::<super::director::Director>().is_some();
    let mut ships:Vec<_>=world.query::<(&ShipIdentity,&ShipPosition,&ShipTransit,&ShipCargo,&ShipEconomy,&ShipFuel)>().iter(world)
        .map(|(id,p,t,c,e,f)|Carrier {id:id.id.clone(),faction:id.faction_id.clone(),class:id.class.clone(),
            location:p.location_name.clone().unwrap_or_default(),free:c.free(),credits:e.credits,fuel:f.fraction(),speed:f.speed_modifier,
            busy:t.transit.is_some() || e.active_contract_id.is_some() || e.transaction.pending.is_some() || (!galaxy && c.used()>0),
            reputation:e.faction_reputation.clone()}).collect();
    ships.sort_by(|a,b|a.id.cmp(&b.id));
    let alive:HashSet<_>=ships.iter().map(|s|s.id.as_str()).collect();
    let mut used:HashSet<String>=board.iter().filter(|c|matches!(c.status,ContractStatus::Accepted|ContractStatus::PickedUp|ContractStatus::Delivered))
        .filter_map(|c|c.fulfiller_id.clone()).collect();
    let mut ids:Vec<_>=board.iter().filter(|c| c.fixed_strategy_reward().is_some()
        && (contract_order(c).is_some() || c.fulfiller_id.as_ref().is_none_or(|id|ships.iter().any(|s|s.id==*id && c.faction_id.as_deref()==Some(s.faction.as_str()))))).map(|c|c.id.clone()).collect();
    ids.sort_by(|a,b| {
        let priority=|id:&String|{
            let c=board.get(id).unwrap();
            if matches!(c.commodity,Commodity::Food|Commodity::Water)
                && c.contract_type!=ContractType::Passenger {0u8}
                else if c.contract_type==ContractType::Passenger {1} else {2}
        };
        priority(a).cmp(&priority(b)).then_with(||a.cmp(b))
    });
    let mut sites:Vec<_>=world.query::<(bevy_ecs::prelude::Entity,&ConstructionSite)>().iter(world)
        .map(|(e,s)|(s.id.clone(),e)).collect(); sites.sort_by(|a,b|a.0.cmp(&b.0));
    for (_,e) in &sites {
        let mut site=world.get_mut::<ConstructionSite>(*e).unwrap();
        let done=site.completed || site.labor.completed>=site.labor.required;
        let last_work=site.labor.last_shift.as_ref().map_or(0,|s|s.tick);
        if let Some(o)=site.labor.station_order.as_mut() {
            let before=o.clone();
            if done {o.state="completed".into();o.blocked_reason=None;}
            else if let Some(ship)=o.executor_id.clone() {
                if !alive.contains(ship.as_str()) {o.release("executor_missing",tick,cooldown);}
                else if used.contains(&ship) {o.release("executor_has_other_order",tick,cooldown);}
                else if tick.saturating_sub(last_work.max(o.assigned_tick))>=lease {o.release("construction_progress_timeout",tick,cooldown);}
                else {used.insert(ship);}
            }
            if *o!=before {site.dirty=true;}
        }
    }
    for id in &ids {
        let c=board.get_mut(id).unwrap();
        // A fixed strategy reward is authorized only when fully escrowed.
        // Prevent the station dispatcher from tying a carrier to an order
        // that the exclusive acceptance phase must reject.
        let funded = c.fixed_strategy_reward().is_some_and(|reward|
            c.funding_top_up(reward) == Ok(0));
        let o=c.funding.as_mut().unwrap().station_order.get_or_insert_with(||Order::new("delivery",id));
        match c.status {
            ContractStatus::Paid => {o.state="completed".into();o.blocked_reason=None;},
            ContractStatus::Expired => {o.state="cancelled".into();o.blocked_reason=Some("contract_expired".into());},
            ContractStatus::Accepted|ContractStatus::PickedUp|ContractStatus::Delivered => {
                o.executor_id=c.fulfiller_id.clone();o.state="executing".into();o.blocked_reason=None;
            },
            ContractStatus::Posted => {
                if !funded {
                    if o.executor_id.is_some() || tick >= o.retry_after_tick {
                        o.release("invalid_order_escrow",tick,cooldown);
                    }
                    continue;
                }
                if o.blocked_reason.as_deref()==Some("invalid_order_escrow") {
                    // Funds have changed: reconsider immediately, not after
                    // the old retry timer. This does not move any credits.
                    o.retry_after_tick=tick;
                    o.blocked_reason=None;
                }
                if let Some(ship)=o.executor_id.clone() {
                    if !alive.contains(ship.as_str()) {o.release("executor_missing",tick,cooldown);}
                    else if used.contains(&ship) {o.release("executor_busy",tick,cooldown);}
                    else if o.state=="executing" || tick.saturating_sub(o.assigned_tick)>=lease {
                        o.release("execution_released_or_accept_timeout",tick,cooldown);
                    } else {used.insert(ship);}
                }
            }
        }
    }
    for id in ids {
        let c=board.get(&id).unwrap();
        let o=contract_order(c).unwrap();
        if c.status!=ContractStatus::Posted || o.executor_id.is_some() || tick<o.retry_after_tick
            || !c.fixed_strategy_reward().is_some_and(|reward|c.funding_top_up(reward)==Ok(0)) {continue;}
        let faction=c.faction_id.as_deref().unwrap_or("");
        let source_owner=owners.get(&c.source_location).map_or("",String::as_str);
        let destination_owner=owners.get(&c.destination_location).map_or("",String::as_str);
        let selected=ships.iter().filter(|s|!faction.is_empty() && s.faction==faction && !s.busy && !used.contains(&s.id))
            .filter_map(|s| {
                if !commerce_allowed(relations,&s.faction,source_owner) || !commerce_allowed(relations,&s.faction,destination_owner) {return None;}
                let route=distance(registry,&s.location,&c.source_location)?.saturating_add(distance(registry,&c.source_location,&c.destination_location)?);
                if c.mission_category.as_deref() == Some(super::colony::PROJECT_TAG)
                    && !reachable(&c.destination_location, s.speed) { return None; }
                if c.contract_type == ContractType::Passenger {
                    let seats = crate::simulation::config::ship_class(&s.class)?.passenger_capacity;
                    return (seats >= c.quantity).then_some((s.fuel < 0.25, route, s.id.as_str()));
                }
                if s.free < c.quantity { return None; }
                let market=markets.get(&c.source_location)?;
                let stock=market.supply.get(&c.commodity).copied().unwrap_or(0.0);
                if !stock.is_finite() || stock<c.quantity as f32 {return None;}
                let cost=super::sourcing::purchase_cost(market.price(c.commodity),c.quantity,relations,&s.faction,
                    s.reputation.get(source_owner).copied().unwrap_or(0),source_owner)?;
                if cost>=c.initial_payment || cost>s.credits {return None;}
                Some((s.fuel<0.25,route,s.id.as_str()))
            }).min().map(|(_,_,id)|id.to_string());
        // Galaxy 0.4 A4: a prepaid station contract is a commitment to
        // deliver the commodity, not a commitment to buy it from one mine.
        // Re-source only an unaccepted, fully funded offer, and only when an
        // alternative market and a specific idle carrier can execute it.
        // Do NOT move money, create goods or change an accepted contract.
        let mut assignment = selected.map(|ship| (c.source_location.clone(), ship));
        if assignment.is_none() && c.contract_type != ContractType::Passenger {
            let mut viable: Vec<(bool, u32, i64, String, String)> = Vec::new();
            for (other_source, market) in &markets {
                if other_source == &c.source_location || other_source == &c.destination_location {
                    continue;
                }
                let owner = owners.get(other_source).map_or("", String::as_str);
                let stock = market.supply.get(&c.commodity).copied().unwrap_or(0.0);
                if !stock.is_finite() || stock < c.quantity as f32 ||
                    !commerce_allowed(relations, faction, owner) { continue; }
                for ship in ships.iter().filter(|s|
                    s.faction == faction && !s.busy && !used.contains(&s.id) &&
                    s.free >= c.quantity &&
                    commerce_allowed(relations, &s.faction, destination_owner)) {
                    let Some(route) = distance(registry, &ship.location, other_source)
                        .and_then(|a| distance(registry, other_source, &c.destination_location)
                            .map(|b| a.saturating_add(b))) else { continue; };
                    if c.mission_category.as_deref() == Some(super::colony::PROJECT_TAG)
                        && !reachable(&c.destination_location, ship.speed) { continue; }
                    let Some(cost) = super::sourcing::purchase_cost(
                        market.price(c.commodity), c.quantity, relations, &ship.faction,
                        ship.reputation.get(owner).copied().unwrap_or(0), owner,
                    ) else { continue; };
                    if cost >= c.initial_payment || cost > ship.credits { continue; }
                    viable.push((owner != faction, route, cost, other_source.clone(), ship.id.clone()));
                }
            }
            // Own-faction supply wins; then shortest viable route, then
            // the actual purchase quote, with stable tie-breaking.
            viable.sort();
            if let Some((_, _, _, alternative, ship)) = viable.into_iter().next() {
                assignment = Some((alternative, ship));
            }
        }
        let contract = board.get_mut(&id).unwrap();
        if let Some((source, ship)) = assignment {
            if contract.source_location != source { contract.source_location = source; }
            used.insert(ship.clone());
            contract.funding.as_mut().unwrap().station_order.as_mut().unwrap().assign(ship,tick);
        } else {
            let reason = match markets.get(&contract.source_location) {
                None => "source_market_missing",
                Some(m) if m.supply.get(&contract.commodity).copied().unwrap_or(0.0)
                    < contract.quantity as f32 => "source_stock_short",
                _ => "no_viable_local_carrier",
            };
            contract.funding.as_mut().unwrap().station_order.as_mut().unwrap()
                .release(reason,tick,cooldown);
        }
    }
    // The dispatcher has just validated the real source quote. Supply that
    // quote to the appointed pilot so stale personal memory cannot deadlock
    // a legal funded order. No inventory/cash is changed or reserved here.
    let quotes:Vec<_>=board.iter().filter(|c|matches!(c.status,ContractStatus::Posted|ContractStatus::Accepted))
        .filter_map(|c|Some((contract_order(c)?.executor_id.clone()?,c.source_location.clone(),c.commodity,markets.get(&c.source_location)?.price(c.commodity)))).collect();
    for (ship,source,commodity,price) in quotes {
        if !price.is_finite()||price<=0.0 {continue;}
        for (identity,mut memory) in world.query::<(&ShipIdentity,&mut crate::agents::ship::ShipMemory)>().iter_mut(world) {
            if identity.id==ship {memory.price_knowledge.entry(source.clone()).or_default().insert(commodity,crate::economy::commodities::PriceMemory{price,tick});break;}
        }
    }
    for (_,e) in sites {
        let site=world.get::<ConstructionSite>(e).unwrap();
        if site.completed || site.remaining()>0 || site.labor.completed>=site.labor.required {continue;}
        let mut order=site.labor.station_order.clone().unwrap_or_else(||Order::new("construction",&site.id));
        if order.executor_id.is_none() && tick>=order.retry_after_tick {
            let selected=ships.iter().filter(|s|!site.faction_id.is_empty() && s.faction==site.faction_id && !s.busy && !used.contains(&s.id)
                && crate::agents::construction::executor::capable(&s.class)
                && (site.labor.colony_source.is_none() || reachable(&site.location_name, s.speed)))
                .filter_map(|s|distance(registry,&s.location,&site.location_name).map(|d|(d,s.id.as_str())))
                .min().map(|(_,id)|id.to_string());
            if let Some(ship)=selected {used.insert(ship.clone());order.assign(ship,tick);}
            else {order.release("no_viable_local_builder",tick,cooldown);}
        }
        if let Some(ship)=order.executor_id.as_deref() {
            if site.labor.last_executor.as_deref()==Some(ship) && site.labor.last_shift.as_ref().is_some_and(|s|s.tick>=order.assigned_tick) {
                order.state="executing".into();
            }
            order.blocked_reason=site.labor.blocked_reason.clone();
        }
        let mut site=world.get_mut::<ConstructionSite>(e).unwrap();
        if site.labor.station_order.as_ref()!=Some(&order) {site.labor.station_order=Some(order);site.dirty=true;}
    }
}

pub fn snapshot(world:&mut World, board:&ContractBoard)->Vec<OrderView> {
    let mut out:Vec<_>=board.iter().filter_map(|c|contract_order(c).map(|o| {
        let mut order=o.clone();
        match c.status {
            ContractStatus::Paid=>{order.state="completed".into();order.blocked_reason=None;},
            ContractStatus::Expired=>{order.state="cancelled".into();order.blocked_reason=Some("contract_expired".into());},
            ContractStatus::Accepted|ContractStatus::PickedUp|ContractStatus::Delivered=>{order.state="executing".into();},
            _=>{},
        }
        OrderView {order,faction_id:c.faction_id.clone().unwrap_or_default(),location:c.destination_location.clone(),
            kind:if c.contract_type == ContractType::Passenger { "passenger" } else { "delivery" },target_id:c.id.clone(),commodity:(c.contract_type != ContractType::Passenger).then_some(c.commodity),quantity:c.quantity,
            completed_quantity:if c.status==ContractStatus::Paid {c.quantity} else {0}}
    })).collect();
    for site in world.query::<&ConstructionSite>().iter(world) {
        if let Some(order)=&site.labor.station_order {
            out.push(OrderView {order:order.clone(),faction_id:site.faction_id.clone(),location:site.location_name.clone(),
                kind:"construction",target_id:site.id.clone(),commodity:None,quantity:site.labor.required,completed_quantity:site.labor.completed});
        }
    }
    out.sort_by(|a,b|a.order.order_id.cmp(&b.order.order_id));out
}

#[cfg(test)]
mod tests;
