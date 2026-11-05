//! Move local market stock into service reserves, paying the actual owner.
//! A facility moving its own stock makes no payment to itself.

use super::*;
use crate::agents::{
    faction_relations::{commerce_allowed, FactionRelations},
    market::MarketHistory,
};

pub(super) fn tick_restock(world: &mut World, relations: &FactionRelations) {
    let facilities: Vec<(Entity, String, String)> = {
        let mut q = world.query::<(
            Entity,
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityLifecycle,
        )>();
        q.iter(world)
            .filter(|(_, _, _, life)| !life.abandoned)
            .map(|(e, id, loc, _)| (e, id.faction_id.clone(), loc.location_name.clone()))
            .collect()
    };
    let markets: std::collections::HashMap<String, (Entity, Entity)> = {
        let mut q = world.query::<(Entity, &MarketIdentity)>();
        q.iter(world)
            .map(|(e, id)| (id.facility_location.clone(), (e, id.facility)))
            .collect()
    };
    for (buyer, faction, location) in facilities {
        let Some(&(market, seller)) = markets.get(&location) else {
            continue;
        };
        let Some(seller_id) = world.get::<FacilityIdentity>(seller) else {
            continue;
        };
        if !commerce_allowed(relations, &faction, &seller_id.faction_id)
            || world
                .get::<FacilityLifecycle>(seller)
                .is_some_and(|l| l.abandoned)
            || world
                .get::<FacilityLocation>(seller)
                .is_none_or(|l| l.location_name != location)
        {
            continue;
        }
        let Some(seller_ops) = world.get::<FacilityOperations>(seller) else {
            continue;
        };
        let seller_balance = seller_ops.credits;
        let internal = buyer == seller;
        let Some(ops) = world.get::<FacilityOperations>(buyer) else {
            continue;
        };
        let buyer_balance = ops.credits;
        let mut remaining = buyer_balance;
        let Some(storage) = world.get::<FacilityStorage>(buyer) else {
            continue;
        };
        let Some(pricing) = world.get::<MarketPricing>(market) else {
            continue;
        };
        let mut purchases = Vec::new();
        // Stable priority, including when the budget cannot cover every service commodity.
        for &commodity in RESTOCK_COMMODITIES {
            let current = storage.reserves.get(&commodity).copied().unwrap_or(0.0);
            let supply = pricing.supply.get(&commodity).copied().unwrap_or(0.0);
            if !current.is_finite()
                || current < 0.0
                || current >= RESERVE_RESTOCK_THRESHOLD
                || !supply.is_finite()
                || supply < 1.0
            {
                continue;
            }
            let mut qty = (RESERVE_RESTOCK_TARGET - current).min(supply).floor();
            let cost = if internal {
                0
            } else {
                let price = pricing.prices.get(&commodity).copied().unwrap_or(0.0);
                if !price.is_finite() || price <= 0.0 || remaining <= 0 {
                    continue;
                }
                qty = qty.min(((remaining as f64 / price as f64).floor()) as f32);
                let cost = (qty as f64 * price as f64).ceil();
                if !cost.is_finite() || cost >= i64::MAX as f64 {
                    continue;
                }
                let cost = cost as i64;
                if cost <= 0 || cost > remaining {
                    continue;
                }
                cost
            };
            if qty < 1.0 {
                continue;
            }
            remaining -= cost;
            purchases.push((commodity, qty, cost));
        }
        if purchases.is_empty() {
            continue;
        }
        // All validation precedes writes. The loop holds exclusive World access.
        let total = buyer_balance - remaining;
        let Some(seller_after) = seller_balance.checked_add(total) else {
            continue;
        };
        if !internal {
            let mut ops = world.get_mut::<FacilityOperations>(buyer).unwrap();
            ops.credits = remaining;
            ops.dirty = true;
            let mut ops = world.get_mut::<FacilityOperations>(seller).unwrap();
            ops.credits = seller_after;
            ops.dirty = true;
        } else {
            // Reserve persistence follows the facility's operations dirty flag.
            world.get_mut::<FacilityOperations>(buyer).unwrap().dirty = true;
        }
        for (commodity, qty, _) in purchases {
            *world
                .get_mut::<FacilityStorage>(buyer)
                .unwrap()
                .reserves
                .entry(commodity)
                .or_insert(0.0) += qty;
            *world
                .get_mut::<MarketPricing>(market)
                .unwrap()
                .supply
                .get_mut(&commodity)
                .unwrap() -= qty;
        }
        if let Some(mut history) = world.get_mut::<MarketHistory>(market) {
            history.dirty = true;
        }
    }
}

#[cfg(test)]
mod supply_flow_tests;
