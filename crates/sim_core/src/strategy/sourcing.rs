//! Evaluate what a carrier would pay before the head funds a shipment.
use std::collections::HashMap;

use bevy_ecs::prelude::World;

use crate::agents::faction_relations::{
    FactionRelations, commerce_allowed, market_buy_multiplier, market_controllers,
};
use crate::agents::market::{MarketIdentity, MarketPricing};
use crate::economy::commodities::Commodity;
use crate::economy::contracts::{ContractBoard, ContractStatus};

/// Same market multiplier and integer rounding as a native purchase.
pub(crate) fn purchase_cost(
    price: f32,
    quantity: u32,
    relations: &FactionRelations,
    buyer: &str,
    reputation: u8,
    owner: &str,
) -> Option<i64> {
    let unit_price = price * market_buy_multiplier(relations, buyer, reputation, owner);
    let cost = (f64::from(unit_price) * f64::from(quantity)).ceil();
    (cost.is_finite() && unit_price > 0.0 && cost < i64::MAX as f64).then_some(cost as i64)
}

pub(super) struct Sources<'a> {
    markets: HashMap<&'a str, &'a MarketPricing>,
    owners: HashMap<String, String>,
    relations: &'a FactionRelations,
}

impl<'a> Sources<'a> {
    pub(super) fn new(
        markets: impl IntoIterator<Item = (&'a str, &'a MarketPricing)>,
        owners: HashMap<String, String>,
        relations: &'a FactionRelations,
    ) -> Self {
        Self { markets: markets.into_iter().collect(), owners, relations }
    }

    pub(super) fn market(&self, location: &str) -> Option<&MarketPricing> {
        self.markets.get(location).copied()
    }

    fn owner(&self, location: &str) -> &str {
        self.owners.get(location).map_or("", String::as_str)
    }

    pub(super) fn quote(
        &self, faction: &str, source: &str, commodity: Commodity, quantity: u32,
    ) -> Option<i64> {
        purchase_cost(self.market(source)?.price(commodity), quantity, self.relations,
            faction, 0, self.owner(source))
    }

    pub(super) fn choose(
        &self, faction: &str, destination: &str, commodity: Commodity, quantity: u32,
        reward: i64,
    ) -> Result<String, &'static str> {
        let mut has_stock = false;
        let mut best = None;
        for (&location, market) in &self.markets {
            let owner = self.owner(location);
            if location == destination || !commerce_allowed(self.relations, faction, owner) {
                continue;
            }
            let stock = market.supply.get(&commodity).copied().unwrap_or(0.0);
            if !stock.is_finite() || stock < quantity as f32 {
                continue;
            }
            has_stock = true;
            // Own-faction purchases get their native discount. Quotes from
            // other factions don't depend on a particular captain's reputation.
            let Some(cost) = self.quote(faction, location, commodity, quantity).filter(|&cost| cost < reward) else {
                continue;
            };
            let candidate = (cost, owner != faction, location);
            if best.is_none_or(|current| candidate < current) {
                best = Some(candidate);
            }
        }
        best.map(|(_, _, location)| location.to_owned()).ok_or(if has_stock {
            "unprofitable_source"
        } else {
            "no_accessible_stock"
        })
    }
}

/// Recheck only unclaimed funded offers. Expiry leaves the advance for the
/// native refund pass, which settles it once in the normal economic frame.
pub(super) fn withdraw_unprofitable(
    world: &mut World, board: &mut ContractBoard, relations: &FactionRelations,
    events: &mut Vec<serde_json::Value>, tick: u64,
) {
    let owners = market_controllers(world);
    let mut query = world.query::<(&MarketIdentity, &MarketPricing)>();
    let sources = Sources::new(
        query.iter(world).map(|(id, market)| (id.facility_location.as_str(), market)),
        owners, relations,
    );
    let mut blocked = Vec::new();
    for contract in board.iter() {
        if contract.status != ContractStatus::Posted || contract.contract_type == crate::economy::contracts::ContractType::Passenger {
            continue;
        }
        let Some(reward) = contract.fixed_strategy_reward() else { continue };
        let Some(market) = sources.markets.get(contract.source_location.as_str()) else { continue };
        // Even the best possible purchase discount cannot make this offer
        // profitable. Leave temporary stock shortages to the normal lifecycle.
        let cost = purchase_cost(
            market.price(contract.commodity), contract.quantity, relations, &contract.requestor_id,
            100, sources.owner(&contract.source_location),
        );
        if cost.is_none_or(|cost| cost >= reward) {
            blocked.push((contract.id.clone(), cost, reward));
        }
    }
    blocked.sort_unstable_by(|a, b| a.0.cmp(&b.0));
    for (id, cost, reward) in blocked {
        if board.expire_unclaimed(&id).is_some() {
            events.push(serde_json::json!({
                "kind": "strategy_offer_withdrawn", "contract_id": id, "tick": tick,
                "reason": "unprofitable_source", "minimum_purchase_cost": cost, "reward": reward,
            }));
        }
    }
}
