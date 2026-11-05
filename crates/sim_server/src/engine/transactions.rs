//! Exclusive economic commits. A failed validation changes no economic state.
//! Receipts live with the current BT, not in a durable transaction journal.

use bevy_ecs::prelude::{Entity, World};
use sim_core::agents::{
    facility::{
        FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations, FacilityStorage,
        REFUEL_PRICE_PER_UNIT, REFUEL_UNITS_PER_TICK,
    },
    faction_relations::{commerce_allowed, market_buy_multiplier, market_controllers},
    market::{MarketHistory, MarketIdentity, MarketPricing},
    ship::{
        CrewTask, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFuel, ShipIdentity,
        ShipLifecycle, ShipPosition, ShipTransaction, ShipTransit,
    },
};
use sim_core::economy::{
    commodities::Commodity,
    contracts::{ContractStatus, ContractType},
};
use sim_core::simulation::spawner::AgentStore;

type Rejection = &'static str;

pub(super) fn apply_transaction(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    request_id: u64,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) {
    let Some(request) = world
        .get::<ShipEconomy>(ship)
        .and_then(|e| e.transaction.pending.as_ref())
        .filter(|p| p.id == request_id && p.result.is_none())
        .map(|p| p.request.clone())
    else {
        return;
    };
    let outcome = match &request {
        ShipTransaction::Buy {
            location,
            commodity,
            quantity,
            max_unit_price,
        } => buy(
            world,
            store,
            ship,
            location,
            *commodity,
            *quantity,
            *max_unit_price,
            tick,
        ),
        ShipTransaction::Refuel { location } => refuel(world, store, ship, location),
        ShipTransaction::Deliver { contract_id } => {
            deliver(world, store, ship, contract_id, events, tick)
        }
    };
    if let Some(mut economy) = world.get_mut::<ShipEconomy>(ship) {
        if let Some(pending) = economy.transaction.pending.as_mut() {
            pending.result = Some(outcome.as_ref().map(|_| ()).map_err(|e| *e));
        }
    }
    if outcome.is_ok() {
        if let Some(mut lifecycle) = world.get_mut::<ShipLifecycle>(ship) {
            lifecycle.dirty = true;
        }
    }
    let (location, commodity, contract_id, requested_quantity) = match &request {
        ShipTransaction::Buy {
            location,
            commodity,
            quantity,
            ..
        } => (
            Some(location.as_str()),
            Some(commodity.as_str()),
            None,
            Some(*quantity),
        ),
        ShipTransaction::Refuel { location } => (Some(location.as_str()), Some("fuel"), None, None),
        ShipTransaction::Deliver { contract_id } => (None, None, Some(contract_id.as_str()), None),
    };
    events.push(serde_json::json!({
        "kind": if outcome.is_ok() { "ship_transaction_applied" } else { "ship_transaction_rejected" },
        "ship_id": world.get::<ShipIdentity>(ship).map(|id| id.id.as_str()),
        "request_id": request_id, "operation": request.kind(), "tick": tick,
        "location": location, "commodity": commodity, "contract_id": contract_id, "requested_quantity": requested_quantity,
        "reason": outcome.as_ref().err(),
        "quantity": outcome.as_ref().ok().map(|v| v.0),
        "payment": outcome.as_ref().ok().map(|v| v.1),
    }));
}

fn dock(
    world: &World,
    store: &AgentStore,
    ship: Entity,
    location: &str,
) -> Result<Entity, Rejection> {
    let position = world.get::<ShipPosition>(ship).ok_or("missing_position")?;
    if position.location_name.as_deref() != Some(location)
        || world
            .get::<ShipTransit>(ship)
            .ok_or("missing_transit")?
            .transit
            .is_some()
    {
        return Err("wrong_location");
    }
    let facility = position.docked_at.ok_or("not_docked")?;
    if world
        .get::<FacilityLocation>(facility)
        .ok_or("missing_dock")?
        .location_name
        != location
        || !world
            .get::<FacilityStorage>(facility)
            .ok_or("missing_dock_storage")?
            .docked_ships
            .contains(&ship)
        || world
            .get::<FacilityLifecycle>(facility)
            .is_some_and(|l| l.abandoned)
    {
        return Err("invalid_dock");
    }
    let faction = &world
        .get::<ShipIdentity>(ship)
        .ok_or("missing_ship")?
        .faction_id;
    let owner = &world
        .get::<FacilityIdentity>(facility)
        .ok_or("missing_dock_owner")?
        .faction_id;
    if !commerce_allowed(&store.relations, faction, owner) {
        return Err("embargo");
    }
    Ok(facility)
}

fn controller(
    world: &mut World,
    store: &AgentStore,
    ship: Entity,
    location: &str,
) -> Result<String, Rejection> {
    let owner = market_controllers(world)
        .remove(location)
        .unwrap_or_default();
    let faction = &world
        .get::<ShipIdentity>(ship)
        .ok_or("missing_ship")?
        .faction_id;
    if !commerce_allowed(&store.relations, faction, &owner) {
        return Err("embargo");
    }
    Ok(owner)
}

fn dirty_market(world: &mut World, market: Entity) {
    if let Some(mut history) = world.get_mut::<MarketHistory>(market) {
        history.dirty = true;
    }
}

fn crew_success(world: &mut World, ship: Entity, task: CrewTask, navigation: bool) {
    if let Some(mut crew) = world.get_mut::<ShipCrew>(ship) {
        crew.current_task = task;
        crew.dirty = true;
    }
    if let Some(mut skills) = world.get_mut::<ShipCrewSkills>(ship) {
        skills.grant("trading", 1);
        if navigation {
            skills.grant("navigation", 1);
        }
    }
}

fn market_at(
    world: &World,
    store: &AgentStore,
    ship: Entity,
    location: &str,
) -> Result<(Entity, Entity), Rejection> {
    let market = *store
        .market_at_location
        .get(location)
        .ok_or("missing_market")?;
    let seller = world
        .get::<MarketIdentity>(market)
        .ok_or("missing_market_owner")?
        .facility;
    let seller_faction = &world
        .get::<FacilityIdentity>(seller)
        .ok_or("missing_seller")?
        .faction_id;
    let faction = &world
        .get::<ShipIdentity>(ship)
        .ok_or("missing_ship")?
        .faction_id;
    if !commerce_allowed(&store.relations, faction, seller_faction) {
        return Err("embargo");
    }
    if world
        .get::<FacilityLifecycle>(seller)
        .is_some_and(|l| l.abandoned)
    {
        return Err("seller_abandoned");
    }
    if world
        .get::<MarketIdentity>(market)
        .unwrap()
        .facility_location
        != location
        || world
            .get::<FacilityLocation>(seller)
            .ok_or("missing_market_location")?
            .location_name
            != location
    {
        return Err("wrong_market_location");
    }
    Ok((market, seller))
}

#[allow(clippy::too_many_arguments)]
fn buy(
    world: &mut World,
    store: &AgentStore,
    ship: Entity,
    location: &str,
    commodity: Commodity,
    quantity: u32,
    max_unit_price: f32,
    tick: u64,
) -> Result<(f32, i64), Rejection> {
    dock(world, store, ship, location)?;
    let owner = controller(world, store, ship, location)?;
    let (market, seller) = market_at(world, store, ship, location)?;
    let faction = &world
        .get::<ShipIdentity>(ship)
        .ok_or("missing_ship")?
        .faction_id;
    let pricing = world
        .get::<MarketPricing>(market)
        .ok_or("missing_pricing")?;
    let economy = world.get::<ShipEconomy>(ship).ok_or("missing_economy")?;
    let price = pricing.price(commodity)
        * market_buy_multiplier(
            &store.relations,
            faction,
            economy.faction_reputation.get(&owner).copied().unwrap_or(0),
            &owner,
        );
    if !price.is_finite() || price <= 0.0 || !max_unit_price.is_finite() || price > max_unit_price {
        return Err("invalid_or_changed_price");
    }
    let supply = pricing.supply.get(&commodity).copied().unwrap_or(0.0);
    if quantity == 0 || quantity > (1 << 24) || !supply.is_finite() || supply < quantity as f32 {
        return Err("insufficient_stock");
    }
    let cargo = world.get::<ShipCargo>(ship).ok_or("missing_cargo")?;
    if cargo.free() < quantity {
        return Err("insufficient_capacity");
    }
    let cost = (price as f64 * quantity as f64).ceil();
    if cost >= i64::MAX as f64 || cost > economy.credits as f64 {
        return Err("insufficient_credits");
    }
    let cost = cost as i64;
    // Recheck as integers; f64 cannot represent every large credit balance.
    if economy.credits < cost {
        return Err("insufficient_credits");
    }
    let seller_credits = world
        .get::<FacilityOperations>(seller)
        .ok_or("missing_seller_economy")?
        .credits
        .checked_add(cost)
        .ok_or("credit_overflow")?;

    // All fallible checks precede all writes; exclusive World access prevents interleaving.
    world
        .get_mut::<MarketPricing>(market)
        .unwrap()
        .supply
        .insert(commodity, supply - quantity as f32);
    world.get_mut::<ShipEconomy>(ship).unwrap().credits -= cost;
    let mut ops = world.get_mut::<FacilityOperations>(seller).unwrap();
    ops.credits = seller_credits;
    ops.dirty = true;
    let mut cargo = world.get_mut::<ShipCargo>(ship).unwrap();
    *cargo.cargo.entry(commodity).or_insert(0) += quantity;
    cargo.cargo_age.insert(commodity, tick);
    cargo
        .cargo_origin
        .insert(commodity, (location.into(), cost as f32 / quantity as f32));
    dirty_market(world, market);
    crew_success(world, ship, CrewTask::Loading, false);
    Ok((quantity as f32, cost))
}

fn refuel(
    world: &mut World,
    store: &AgentStore,
    ship: Entity,
    location: &str,
) -> Result<(f32, i64), Rejection> {
    let facility = dock(world, store, ship, location)?;
    controller(world, store, ship, location)?;
    let fuel = world.get::<ShipFuel>(ship).ok_or("missing_fuel")?;
    let reserve = world
        .get::<FacilityStorage>(facility)
        .unwrap()
        .reserves
        .get(&Commodity::Fuel)
        .copied()
        .unwrap_or(0.0);
    if !fuel.fuel.is_finite()
        || !fuel.fuel_capacity.is_finite()
        || fuel.fuel < 0.0
        || fuel.fuel_capacity <= 0.0
        || fuel.fuel > fuel.fuel_capacity
        || !reserve.is_finite()
        || reserve < 0.0
    {
        return Err("invalid_fuel_state");
    }
    let amount = REFUEL_UNITS_PER_TICK
        .min(fuel.fuel_capacity - fuel.fuel)
        .min(reserve);
    if amount <= 0.0 {
        return Err("no_fuel_transfer");
    }
    let payment = (amount.ceil() as i64)
        .checked_mul(REFUEL_PRICE_PER_UNIT)
        .ok_or("credit_overflow")?;
    if world
        .get::<ShipEconomy>(ship)
        .ok_or("missing_economy")?
        .credits
        < payment
    {
        return Err("insufficient_credits");
    }
    let facility_credits = world
        .get::<FacilityOperations>(facility)
        .ok_or("missing_dock_economy")?
        .credits
        .checked_add(payment)
        .ok_or("credit_overflow")?;
    world.get_mut::<ShipFuel>(ship).unwrap().fuel += amount;
    world.get_mut::<ShipEconomy>(ship).unwrap().credits -= payment;
    world
        .get_mut::<FacilityStorage>(facility)
        .unwrap()
        .reserves
        .insert(Commodity::Fuel, reserve - amount);
    let mut ops = world.get_mut::<FacilityOperations>(facility).unwrap();
    ops.credits = facility_credits;
    ops.dirty = true;
    Ok((amount, payment))
}

fn deliver(
    world: &mut World,
    store: &mut AgentStore,
    ship: Entity,
    contract_id: &str,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
) -> Result<(f32, i64), Rejection> {
    let c = store
        .contracts
        .get(contract_id)
        .ok_or("missing_contract")?
        .clone();
    let identity = world.get::<ShipIdentity>(ship).ok_or("missing_ship")?;
    let economy = world.get::<ShipEconomy>(ship).ok_or("missing_economy")?;
    if c.fulfiller_id.as_deref() != Some(identity.id.as_str())
        || economy.active_contract_id.as_deref() != Some(contract_id)
    {
        return Err("wrong_fulfiller");
    }
    if !matches!(
        c.status,
        ContractStatus::Accepted | ContractStatus::PickedUp
    ) {
        return Err("inactive_contract");
    }
    if c.faction_id
        .as_deref()
        .is_some_and(|owner| !commerce_allowed(&store.relations, &identity.faction_id, owner))
    {
        return Err("embargo");
    }
    let bonus = world
        .get::<sim_core::agents::ship::ShipFitting>(ship)
        .map(|f| f.derived.comms_bonus)
        .unwrap_or(0.0);
    let treaty = c
        .faction_id
        .as_deref()
        .map(|f| {
            sim_core::agents::faction_relations::trade_pact_payment_multiplier(
                &store.relations,
                &identity.faction_id,
                f,
            )
        })
        .unwrap_or(1.0);
    // Preserve existing reward policy; funding/escrow of bonuses is a separate migration.
    let payment = ((c.payment as f64) * (1.0 + bonus as f64) * treaty as f64).round();
    if !payment.is_finite() || payment < 0.0 || payment >= i64::MAX as f64 {
        return Err("invalid_payment");
    }
    let payment = payment as i64;
    economy
        .credits
        .checked_add(payment)
        .ok_or("credit_overflow")?;
    dock(world, store, ship, &c.destination_location)?;
    controller(world, store, ship, &c.destination_location)?;
    let physical = !matches!(
        c.contract_type,
        ContractType::Passenger | ContractType::CrewMission
    );
    let mut destination_market = None;
    if physical {
        let cargo = world.get::<ShipCargo>(ship).ok_or("missing_cargo")?;
        if c.quantity == 0 || cargo.cargo.get(&c.commodity).copied().unwrap_or(0) < c.quantity {
            return Err("insufficient_cargo");
        }
        if c.contract_type == ContractType::Construction {
            use sim_core::agents::construction::{find_site, ConstructionSite};
            let site = find_site(world, &c.destination_location, c.commodity)
                .ok_or("missing_construction_site")?;
            let site = world.get::<ConstructionSite>(site).unwrap();
            if site.remaining() < c.quantity {
                return Err("construction_overdelivery");
            }
            let faction = &world.get::<ShipIdentity>(ship).unwrap().faction_id;
            if !commerce_allowed(&store.relations, faction, &site.faction_id) {
                return Err("embargo");
            }
            // Old helper finds by location/commodity; reject a different owner's site.
            if c.faction_id
                .as_deref()
                .is_some_and(|f| f != site.faction_id)
            {
                return Err("wrong_construction_owner");
            }
        } else {
            let (market, _) = market_at(world, store, ship, &c.destination_location)?;
            let pricing = world
                .get::<MarketPricing>(market)
                .ok_or("missing_destination_pricing")?;
            let supply = pricing.supply.get(&c.commodity).copied().unwrap_or(0.0);
            if !supply.is_finite() || supply < 0.0 || !(supply + c.quantity as f32).is_finite() {
                return Err("invalid_destination_stock");
            }
            destination_market = Some(market);
        }
    }
    // Status changes only after recipient, ownership, cargo and payment pass.
    let c = store
        .contracts
        .mark_delivered(contract_id)
        .ok_or("inactive_contract")?;
    let quantity = c.quantity;
    super::apply::commit_contract_delivery(world, store, ship, c, payment, events, tick);
    if let Some(market) = destination_market {
        dirty_market(world, market);
    }
    crew_success(world, ship, CrewTask::Unloading, true);
    Ok((quantity as f32, payment))
}

#[cfg(test)]
mod tests;
