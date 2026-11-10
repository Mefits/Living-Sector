//! Galaxy 0.4 / Block A: bounded transfers from EXISTING faction treasuries.
//! This system never mints credits, goods, workers, or contracts. Households
//! with zero income get a small temporary safety net, while local market
//! controllers get enough operating cash to pay real worker shifts.
//! Long-term wages, production, contracts and prices remain fully native.

use std::collections::BTreeMap;
use bevy_ecs::prelude::{Entity, World};
use crate::agents::{
    faction::{FactionData, FACTION_WORKING_CAPITAL_FLOOR},
    facility::{FacilityIdentity, FacilityLocation, FacilityOperations},
    market::{MarketIdentity, MarketPricing},
    population::{PopEconomy, PopIdentity, PopSentiment},
};
use crate::economy::commodities::Commodity;

/// Unlike tax accounting (every 200 base ticks), relief must respond within
/// a few production cycles. World-speed multiplier controls both cadences.
pub const RELIEF_INTERVAL_BASE: u64 = 25;
pub const MAX_SPEND_PER_FACTION: i64 = 2_400;
pub const HOUSEHOLD_MINIMUM: i64 = 20;
pub const HOUSEHOLD_TARGET: i64 = 120;
pub const MARKET_MINIMUM: i64 = 200;
pub const MARKET_TARGET: i64 = 700;
pub const PRODUCER_MINIMUM: i64 = 20;
pub const PRODUCER_TARGET: i64 = 160;

#[derive(Copy, Clone)]
enum Recipient { Facility(Entity), Household(Entity) }

struct Request {
    priority: u8,
    faction: String,
    location: String,
    id: String,
    recipient: Recipient,
    needed: i64,
}

fn stock(pricing: &MarketPricing, item: Commodity) -> f32 {
    pricing.supply.get(&item).copied().unwrap_or(0.0).max(0.0)
}

pub(super) fn tick_relief(
    world: &mut World,
    events: &mut Vec<serde_json::Value>,
    tick: u64,
    tick_multiplier: u32,
) {
    let cadence = RELIEF_INTERVAL_BASE.saturating_mul(u64::from(tick_multiplier));
    if cadence == 0 || tick == 0 || tick % cadence != 0 { return; }

    let accounts: BTreeMap<String, (Entity, i64)> = world
        .query::<(Entity, &FactionData)>()
        .iter(world)
        .map(|(entity, f)| (f.id.clone(), (entity, f.treasury)))
        .collect();
    let mut requests: Vec<Request> = Vec::new();

    // Direct household relief is only triggered for nearly empty wallets;
    // this avoids continuous universal income and preserves earned wages.
    for (entity, id, wallet) in world
        .query::<(Entity, &PopIdentity, &PopEconomy)>()
        .iter(world)
    {
        if wallet.total_wealth < 0 || wallet.total_wealth >= HOUSEHOLD_MINIMUM { continue; }
        if !accounts.contains_key(&id.faction_id) { continue; }
        let starving = world.get::<PopSentiment>(entity)
            .is_some_and(|s| s.food_satisfaction < 40);
        requests.push(Request {
            priority: if starving { 0 } else { 1 },
            faction: id.faction_id.clone(),
            location: id.facility_location.clone(),
            id: id.id.clone(),
            recipient: Recipient::Household(entity),
            needed: HOUSEHOLD_TARGET - wallet.total_wealth,
        });
    }

    // Production's stock owner usually pays the wages, not the refinery or
    // farm. Funding a producer while its market controller has zero CR would
    // leave station allocations at 0, the failure seen in the 10,919-tick
    // diagnostic. Target the real native payer.
    let markets: BTreeMap<String, (String, f32, f32)> = world
        .query::<(&MarketIdentity, &MarketPricing)>()
        .iter(world)
        .filter_map(|(m, pricing)| {
            let owner = world.get::<FacilityIdentity>(m.facility)?;
            let ops = world.get::<FacilityOperations>(m.facility)?;
            if owner.faction_id.is_empty() || ops.credits < 0 { return None; }
            if ops.credits < MARKET_MINIMUM && accounts.contains_key(&owner.faction_id) {
                requests.push(Request {
                    priority: if stock(pricing, Commodity::Food) < 20.0
                        || stock(pricing, Commodity::Water) < 20.0 { 2 } else { 3 },
                    faction: owner.faction_id.clone(),
                    location: m.facility_location.clone(),
                    id: owner.id.clone(),
                    recipient: Recipient::Facility(m.facility),
                    needed: MARKET_TARGET - ops.credits,
                });
            }
            Some((m.facility_location.clone(), (
                owner.faction_id.clone(),
                stock(pricing, Commodity::Food),
                stock(pricing, Commodity::Water),
            )))
        }).collect();

    // A producer can require its own wallet for tools/repair and shifts when
    // it is also the stock owner. Only relieve ESSENTIAL producers in locations
    // actually short of their output, not every idle factory in the universe.
    for (entity, id, location, ops) in world
        .query::<(Entity, &FacilityIdentity, &FacilityLocation, &FacilityOperations)>()
        .iter(world)
    {
        if !accounts.contains_key(&id.faction_id)
            || ops.credits < 0 || ops.credits >= PRODUCER_MINIMUM { continue; }
        let Some((owner, food, water)) = markets.get(&location.location_name) else { continue; };
        if owner != &id.faction_id { continue; }
        let emergency = (id.facility_type == "farm" && *food < 20.0)
            || (id.facility_type == "refinery" && *water < 20.0);
        if !emergency { continue; }
        requests.push(Request {
            priority: 4,
            faction: id.faction_id.clone(),
            location: location.location_name.clone(),
            id: id.id.clone(),
            recipient: Recipient::Facility(entity),
            needed: PRODUCER_TARGET - ops.credits,
        });
    }

    requests.sort_by(|a,b| a.priority.cmp(&b.priority)
        .then_with(|| a.faction.cmp(&b.faction))
        .then_with(|| a.location.cmp(&b.location))
        .then_with(|| a.id.cmp(&b.id)));
    let mut spent: BTreeMap<String, i64> = BTreeMap::new();
    for request in requests {
        let Some(&(owner, _)) = accounts.get(&request.faction) else { continue; };
        let available = world.get::<FactionData>(owner)
            .map(|f| f.treasury.saturating_sub(FACTION_WORKING_CAPITAL_FLOOR).max(0))
            .unwrap_or(0);
        let within_cap = MAX_SPEND_PER_FACTION
            .saturating_sub(*spent.get(&request.faction).unwrap_or(&0));
        let amount = request.needed.min(available).min(within_cap);
        if amount <= 0 { continue; }

        // Check recipient arithmetic before debiting the treasury; never
        // allow a partial transfer, even with a malformed old save.
        let can_receive = match request.recipient {
            Recipient::Facility(entity) => world.get::<FacilityOperations>(entity)
                .and_then(|ops| ops.credits.checked_add(amount)).is_some(),
            Recipient::Household(entity) => world.get::<PopEconomy>(entity)
                .and_then(|pop| pop.total_wealth.checked_add(amount)).is_some(),
        };
        if !can_receive { continue; }
        {
            let mut faction = world.get_mut::<FactionData>(owner).unwrap();
            faction.treasury -= amount;
            faction.dirty = true;
        }
        match request.recipient {
            Recipient::Facility(entity) => {
                let mut ops = world.get_mut::<FacilityOperations>(entity).unwrap();
                ops.credits += amount;
                ops.dirty = true;
            }
            Recipient::Household(entity) => {
                world.get_mut::<PopEconomy>(entity).unwrap().total_wealth += amount;
                if let Some(mut sentiment) = world.get_mut::<PopSentiment>(entity) {
                    sentiment.dirty = true;
                }
            }
        }
        *spent.entry(request.faction.clone()).or_default() += amount;
        events.push(serde_json::json!({
            "kind": "faction_relief_transfer",
            "tick": tick,
            "faction_id": request.faction,
            "recipient_id": request.id,
            "location": request.location,
            "recipient_kind": match request.recipient {
                Recipient::Facility(_) => "facility",
                Recipient::Household(_) => "household",
            },
            "amount": amount,
        }));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::personality::Personality;
    use crate::agents::faction::FactionColors;
    use std::collections::HashMap;

    fn scenario(treasury: i64) -> (World, Entity, Entity, Entity, Entity) {
        let mut world = World::new();
        let faction = world.spawn(FactionData {
            id: "civ".into(), name: "Civ".into(), faction_type: "normal".into(),
            home_system: "sol".into(), treasury,
            personality: Personality::balanced_trader(),
            colors: FactionColors {primary: String::new(),secondary:String::new()},
            active_subsidies: 0, dirty: false,
        }).id();
        let station = world.spawn((
            FacilityIdentity {db_id:1,id:"station".into(),name:"Station".into(),
                facility_type:"station".into(),faction_id:"civ".into(),body_id:"mars".into()},
            FacilityLocation {location_id:1,location_name:"mars-colony".into()},
            FacilityOperations {docking_capacity:5,services:vec![],
                condition:1.0,reputation:50,credits:0,dirty:false,starving_notified:false},
        )).id();
        let market = world.spawn((
            MarketIdentity {db_id:1,id:"market".into(),facility:station,
                facility_location:"mars-colony".into()},
            MarketPricing {price_elasticity:0.02,spread:0.1,
                prices:HashMap::new(),supply:[
                    (Commodity::Food,7.0),(Commodity::Water,13.0)
                ].into(),demand:HashMap::new()},
        )).id();
        let people = world.spawn((
            PopIdentity {db_id:1,id:"people".into(),label:"People".into(),
                demographic:"workers".into(),facility:station,facility_location:"mars-colony".into(),
                faction_id:"civ".into()},
            PopEconomy {total_wealth:0,spending_rate:0.0,
                consumption:HashMap::new(),production_commodity:None,production_amount:0.0},
            PopSentiment {overall_sentiment:20,unrest:70,food_satisfaction:0,
                safety_satisfaction:50,entertainment_satisfaction:50,dirty:false},
        )).id();
        (world,faction,station,people,market)
    }

    #[test]
    fn rescue_preserves_credits_and_market_stock() {
        let (mut w,faction,station,people,market) = scenario(30_000);
        let before = w.get::<FactionData>(faction).unwrap().treasury
            + w.get::<FacilityOperations>(station).unwrap().credits
            + w.get::<PopEconomy>(people).unwrap().total_wealth;
        let original_stock = w.get::<MarketPricing>(market).unwrap().supply.clone();
        let mut events = vec![];
        tick_relief(&mut w,&mut events,25,1);
        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,120);
        assert_eq!(w.get::<FacilityOperations>(station).unwrap().credits,700);
        assert_eq!(events.len(),2);
        assert_eq!(w.get::<MarketPricing>(market).unwrap().supply,original_stock);
        let after = w.get::<FactionData>(faction).unwrap().treasury
            + w.get::<FacilityOperations>(station).unwrap().credits
            + w.get::<PopEconomy>(people).unwrap().total_wealth;
        assert_eq!(after,before);
        tick_relief(&mut w,&mut events,25,1);
        assert_eq!(events.len(),2,"a completed top-up is not repeated on the same tick");
    }

    #[test]
    fn preserve_treasury_floor_and_working_cadence() {
        let (mut w,faction,station,people,_) = scenario(FACTION_WORKING_CAPITAL_FLOOR + 50);
        let mut events = vec![];
        tick_relief(&mut w,&mut events,1,1);
        assert!(events.is_empty());
        tick_relief(&mut w,&mut events,25,1);
        assert_eq!(w.get::<FactionData>(faction).unwrap().treasury,FACTION_WORKING_CAPITAL_FLOOR);
        assert_eq!(w.get::<PopEconomy>(people).unwrap().total_wealth,50);
        assert_eq!(w.get::<FacilityOperations>(station).unwrap().credits,0);
        assert_eq!(events.len(),1);
    }
}
