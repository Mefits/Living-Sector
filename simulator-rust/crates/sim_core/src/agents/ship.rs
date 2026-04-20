//! Ship components for hecs storage.
//!
//! A ship entity is spawned with the full bundle of components below. Fields
//! are grouped by access pattern so that tick phases load only the data they
//! need — position updates don't pull cargo or AI into cache.
//!
//! Spawn a ship with:
//! ```ignore
//! world.spawn((
//!     ShipIdentity { ... },
//!     ShipPosition { ... },
//!     ShipTransit { transit: None },
//!     ShipCargo { ... },
//!     ShipFuel { ... },
//!     ShipEconomy { ... },
//!     ShipAI { ... },
//!     ShipMemory { ... },
//!     ShipLifecycle { ... },
//! ));
//! ```

use crate::{
    ai::{behavior_tree::BtNode, personality::Personality},
    economy::commodities::{Cargo, Commodity, PriceKnowledge},
};
use hecs::Entity;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// In-transit data for a ship traveling between locations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transit {
    pub from: String,
    pub to: String,
    pub departure_tick: u64,
    pub arrival_tick: u64,
}

/// Stable identity — set at spawn, rarely mutated.
#[derive(Debug, Clone)]
pub struct ShipIdentity {
    pub db_id: i64,
    /// Human-readable agent id, e.g. "ship-artemis-7".
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
}

/// Spatial state — changes every tick while in transit.
#[derive(Debug, Clone)]
pub struct ShipPosition {
    pub location_name: Option<String>, // None while in transit
    pub docked_at: Option<Entity>,      // facility entity if docked
    pub system_id: String,
    pub universe_offset: (f32, f32),
    pub position: (f32, f32),
}

/// Transit state. `None` when the ship is stationary (docked or idle at a location).
#[derive(Debug, Clone)]
pub struct ShipTransit {
    pub transit: Option<Transit>,
}

/// Cargo hold.
#[derive(Debug, Clone)]
pub struct ShipCargo {
    pub cargo: Cargo,
    pub capacity: u32,
    /// tick each commodity was first acquired (for hoard detection)
    pub cargo_age: HashMap<Commodity, u64>,
}

impl ShipCargo {
    pub fn used(&self) -> u32 {
        self.cargo.values().sum()
    }
    pub fn free(&self) -> u32 {
        self.capacity.saturating_sub(self.used())
    }
}

/// Fuel and propulsion.
#[derive(Debug, Clone)]
pub struct ShipFuel {
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub fuel_consumption_rate: f32,
    pub speed_modifier: f32,
}

impl ShipFuel {
    pub fn fraction(&self) -> f32 {
        if self.fuel_capacity > 0.0 { self.fuel / self.fuel_capacity } else { 0.0 }
    }
}

/// Economic state.
#[derive(Debug, Clone)]
pub struct ShipEconomy {
    pub credits: i64,
    pub efficiency: f32,
    pub active_contract_id: Option<String>,
    pub faction_reputation: HashMap<String, u8>,
}

/// AI: personality + current goal + BT state.
#[derive(Debug, Clone)]
pub struct ShipAI {
    pub personality: Personality,
    pub current_goal: String,
    pub current_bt: Option<BtNode>,
}

/// Learned memory — price knowledge, visited locations.
/// Rarely loaded except during trade decisions.
#[derive(Debug, Clone)]
pub struct ShipMemory {
    pub price_knowledge: PriceKnowledge,
    pub visited: Vec<String>,
}

/// Lifecycle counters and dirty flag for persistence.
#[derive(Debug, Clone)]
pub struct ShipLifecycle {
    pub broke_strikes: u8,
    pub hoard_strikes: u8,
    pub idle_ticks: u32,
    pub dirty: bool,
}

/// Serializable snapshot for HTTP/WS clients — built by querying components.
#[derive(Debug, Clone, Serialize)]
pub struct ShipSnapshot {
    pub id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    pub location_name: Option<String>,
    pub docked: bool,
    pub transit: Option<Transit>,
    pub cargo: HashMap<String, u32>,
    pub cargo_capacity: u32,
    pub fuel: f32,
    pub fuel_capacity: f32,
    pub credits: i64,
    pub current_goal: String,
    pub bt_action: Option<String>,
    pub position: (f32, f32),
}

impl ShipSnapshot {
    pub fn build(
        identity: &ShipIdentity,
        position: &ShipPosition,
        transit: &ShipTransit,
        cargo: &ShipCargo,
        fuel: &ShipFuel,
        economy: &ShipEconomy,
        ai: &ShipAI,
    ) -> Self {
        let cargo_map: HashMap<String, u32> = cargo
            .cargo
            .iter()
            .map(|(c, &qty)| (c.as_str().to_string(), qty))
            .collect();
        Self {
            id: identity.id.clone(),
            name: identity.name.clone(),
            class: identity.class.clone(),
            faction_id: identity.faction_id.clone(),
            location_name: position.location_name.clone(),
            docked: position.docked_at.is_some(),
            transit: transit.transit.clone(),
            cargo: cargo_map,
            cargo_capacity: cargo.capacity,
            fuel: fuel.fuel,
            fuel_capacity: fuel.fuel_capacity,
            credits: economy.credits,
            current_goal: ai.current_goal.clone(),
            bt_action: ai.current_bt.as_ref().and_then(|bt| bt.current_action()).map(String::from),
            position: position.position,
        }
    }
}

// ============================================================================
// Tick logic — Phase 4 MVP
// ============================================================================
//
// Direct state-machine approach rather than full BT execution. The BT engine
// from Phase 1 is still available for Phase 4.5 when we want more elaborate
// goal chains, but for the MVP we use a simple decision tree each tick:
//
//   1. Advance transit (if in transit). Arrive → set location, clear transit.
//   2. Observe local market prices (if at a location, not in transit).
//   3. Decide:
//      - in transit? consume fuel, position interpolation
//      - fuel below 25%? instant refill (facility-based later)
//      - at location with cargo? sell locally at known price
//      - at location with empty cargo + known margin? buy locally → travel to sell
//      - at location without profitable route? idle (or explore later)
//
// Market supply changes emit SimCommand::AddSupply / RemoveSupply to the
// buffer. Credits move in-place (within the ship) because self-transfers
// don't need cross-agent coordination.

use crate::economy::commodities::PriceMemory;
use crate::simulation::commands::{CommandBuffer, SimCommand};
use crate::world::{registry::WorldRegistry, travel};

const FUEL_CRITICAL_FRACTION: f32 = 0.25;
const MIN_TRADE_MARGIN: f32 = 0.10; // 10% minimum margin
const TRADE_QTY_DEFAULT: u32 = 50;

/// Tick all ships in 3 passes to keep hecs borrows clean.
pub fn tick_ships(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_scale: f32,
    tick_multiplier: u32,
) {
    advance_transits(world, registry, tick, tick_scale);
    observe_prices(world, tick);
    decide_and_act(world, registry, commands, tick, tick_multiplier);
}

/// Pass 1: advance transit clocks, interpolate position, consume fuel.
fn advance_transits(world: &mut hecs::World, registry: &WorldRegistry, tick: u64, tick_scale: f32) {
    // Snapshot body positions for location→position lookups.
    let body_positions: std::collections::HashMap<i64, (f32, f32)> = world
        .query::<(
            &crate::agents::celestial_body::BodyIdentity,
            &crate::agents::celestial_body::BodyOrbit,
        )>()
        .iter()
        .map(|(_e, (id, orbit))| (id.db_id, orbit.universe_position()))
        .collect();

    let location_to_pos = |loc: &str| -> Option<(f32, f32)> {
        let info = registry.locations.get(loc)?;
        body_positions.get(&info.celestial_body_id).copied()
    };

    for (_e, (position, transit, fuel, memory, lifecycle)) in world
        .query_mut::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipFuel,
            &mut ShipMemory,
            &mut ShipLifecycle,
        )>()
    {
        if let Some(t) = transit.transit.clone() {
            if tick >= t.arrival_tick {
                position.location_name = Some(t.to.clone());
                position.docked_at = None;
                transit.transit = None;
                if !memory.visited.contains(&t.to) {
                    memory.visited.push(t.to.clone());
                }
                if let Some(pos) = location_to_pos(&t.to) {
                    position.position = pos;
                }
                lifecycle.dirty = true;
            } else {
                let progress = travel::transit_progress(tick, t.departure_tick, t.arrival_tick);
                if let (Some(from), Some(to)) =
                    (location_to_pos(&t.from), location_to_pos(&t.to))
                {
                    position.position = (
                        from.0 + (to.0 - from.0) * progress,
                        from.1 + (to.1 - from.1) * progress,
                    );
                }
                let consumption = fuel.fuel_consumption_rate * tick_scale;
                fuel.fuel = (fuel.fuel - consumption).max(0.0);
            }
        }
    }
}

/// Pass 2: observe local market prices into ship memory.
fn observe_prices(world: &mut hecs::World, tick: u64) {
    let market_prices: std::collections::HashMap<
        String,
        std::collections::HashMap<Commodity, f32>,
    > = world
        .query::<(
            &crate::agents::market::MarketIdentity,
            &crate::agents::market::MarketPricing,
        )>()
        .iter()
        .map(|(_e, (id, pricing))| (id.facility_location.clone(), pricing.prices.clone()))
        .collect();

    for (_e, (position, memory)) in world.query_mut::<(&ShipPosition, &mut ShipMemory)>() {
        if let Some(loc) = &position.location_name {
            if let Some(prices) = market_prices.get(loc) {
                let entry = memory.price_knowledge.entry(loc.clone()).or_default();
                for (&commodity, &price) in prices {
                    entry.insert(commodity, PriceMemory { price, tick });
                }
            }
        }
    }
}

/// Find the best profitable trade route from memory.
pub fn best_trade_route(memory: &ShipMemory) -> Option<(Commodity, String, String, f32)> {
    let mut best: Option<(Commodity, String, String, f32)> = None;
    let locs: Vec<_> = memory.price_knowledge.iter().collect();
    for (i, (loc_a, prices_a)) in locs.iter().enumerate() {
        for (loc_b, prices_b) in locs.iter().skip(i + 1) {
            for (commodity, pa) in prices_a.iter() {
                if let Some(pb) = prices_b.get(commodity) {
                    let (buy, sell, lo, hi) = if pa.price < pb.price {
                        ((*loc_a).clone(), (*loc_b).clone(), pa.price, pb.price)
                    } else {
                        ((*loc_b).clone(), (*loc_a).clone(), pb.price, pa.price)
                    };
                    let margin = (hi - lo) / lo.max(1.0);
                    if margin > MIN_TRADE_MARGIN && best.as_ref().is_none_or(|b| margin > b.3) {
                        best = Some((*commodity, buy, sell, margin));
                    }
                }
            }
        }
    }
    best
}

/// Pass 3: decide + act on each ship.
fn decide_and_act(
    world: &mut hecs::World,
    registry: &WorldRegistry,
    commands: &mut CommandBuffer,
    tick: u64,
    tick_multiplier: u32,
) {
    // Reconstruct config from tick_multiplier so runtime WORLD_SPEED override
    // affects travel-time calculations consistently.
    let config = crate::simulation::config::TickConfig {
        ticks_per_second: 8,
        world_speed: if tick_multiplier == 0 { 0.25 } else { 8.0 / tick_multiplier as f32 },
    };

    for (entity, (position, transit, cargo, fuel, economy, ai, memory, lifecycle)) in world
        .query_mut::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipCargo,
            &mut ShipFuel,
            &mut ShipEconomy,
            &mut ShipAI,
            &mut ShipMemory,
            &mut ShipLifecycle,
        )>()
    {
        // Skip ships in transit
        if transit.transit.is_some() {
            ai.current_goal = "in_transit".into();
            continue;
        }

        let at_location = match position.location_name.clone() {
            Some(l) => l,
            None => {
                ai.current_goal = "idle".into();
                continue;
            }
        };

        // Rule 1: low fuel → refuel (MVP: free refill)
        if fuel.fraction() < FUEL_CRITICAL_FRACTION {
            fuel.fuel = fuel.fuel_capacity;
            ai.current_goal = "refuel".into();
            lifecycle.dirty = true;
            continue;
        }

        // Rule 2: have cargo to sell at current location
        if cargo.used() > 0 {
            sell_cargo_locally(entity, &at_location, cargo, economy, memory, commands);
            ai.current_goal = "sell_cargo".into();
            lifecycle.dirty = true;
            // Fall through to potentially start a new trade run
        }

        // Rule 3: empty cargo + profitable route
        if cargo.used() == 0 {
            if let Some((commodity, buy_loc, sell_loc, _margin)) = best_trade_route(memory) {
                if buy_loc == at_location {
                    buy_cargo_locally(
                        entity,
                        &at_location,
                        commodity,
                        cargo,
                        economy,
                        memory,
                        tick,
                        commands,
                    );
                    begin_travel(&at_location, &sell_loc, registry, position, transit, fuel, tick, &config);
                    ai.current_goal = "trade_run".into();
                    lifecycle.dirty = true;
                    continue;
                } else {
                    begin_travel(&at_location, &buy_loc, registry, position, transit, fuel, tick, &config);
                    ai.current_goal = "trade_run_travel".into();
                    lifecycle.dirty = true;
                    continue;
                }
            }
        }

        ai.current_goal = "idle".into();
    }
}

/// Sell all cargo at the ship's current location using known local prices.
fn sell_cargo_locally(
    entity: hecs::Entity,
    at_location: &str,
    cargo: &mut ShipCargo,
    economy: &mut ShipEconomy,
    memory: &ShipMemory,
    commands: &mut CommandBuffer,
) {
    let prices = match memory.price_knowledge.get(at_location) {
        Some(p) => p,
        None => return,
    };
    let to_sell: Vec<_> = cargo
        .cargo
        .iter()
        .filter(|(_, &qty)| qty > 0)
        .map(|(&c, &qty)| (c, qty))
        .collect();
    for (commodity, qty) in to_sell {
        if let Some(pm) = prices.get(&commodity) {
            let total = (pm.price * qty as f32) as i64;
            economy.credits += total;
            cargo.cargo.remove(&commodity);
            cargo.cargo_age.remove(&commodity);
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity,
                quantity: qty as f32,
            });
        }
    }
}

/// Buy as much as ship can afford/carry at current local price.
#[allow(clippy::too_many_arguments)]
fn buy_cargo_locally(
    entity: hecs::Entity,
    at_location: &str,
    commodity: Commodity,
    cargo: &mut ShipCargo,
    economy: &mut ShipEconomy,
    memory: &ShipMemory,
    tick: u64,
    commands: &mut CommandBuffer,
) {
    let price = match memory
        .price_knowledge
        .get(at_location)
        .and_then(|m| m.get(&commodity))
    {
        Some(pm) => pm.price,
        None => return,
    };
    let qty = affordable_quantity(economy.credits, price, cargo.free()).min(TRADE_QTY_DEFAULT);
    if qty == 0 {
        return;
    }
    let cost = (price * qty as f32) as i64;
    economy.credits -= cost;
    *cargo.cargo.entry(commodity).or_insert(0) += qty;
    cargo.cargo_age.insert(commodity, tick);
    commands.push(SimCommand::RemoveSupplyAtShipLocation {
        ship: entity,
        commodity,
        quantity: qty as f32,
    });
}

fn affordable_quantity(credits: i64, price: f32, capacity: u32) -> u32 {
    if price <= 0.0 || credits <= 0 {
        return 0;
    }
    let by_credits = (credits as f32 / price) as u32;
    by_credits.min(capacity)
}

#[allow(clippy::too_many_arguments)]
fn begin_travel(
    from: &str,
    dest: &str,
    registry: &WorldRegistry,
    position: &mut ShipPosition,
    transit: &mut ShipTransit,
    fuel: &ShipFuel,
    tick: u64,
    config: &crate::simulation::config::TickConfig,
) {
    if from == dest {
        return;
    }
    let distance = registry
        .travel_distance(from, dest)
        .or_else(|| registry.travel_distance(dest, from))
        .unwrap_or(60);
    let arrival = travel::arrival_tick(tick, distance, fuel.speed_modifier, config);
    transit.transit = Some(Transit {
        from: from.to_string(),
        to: dest.to_string(),
        departure_tick: tick,
        arrival_tick: arrival,
    });
    position.location_name = None;
    position.docked_at = None;
}

#[cfg(test)]
mod tick_tests {
    use super::*;

    #[test]
    fn affordable_quantity_respects_credits_and_capacity() {
        assert_eq!(affordable_quantity(100, 10.0, 1000), 10);
        assert_eq!(affordable_quantity(0, 10.0, 1000), 0);
        assert_eq!(affordable_quantity(1000, 10.0, 50), 50);
        assert_eq!(affordable_quantity(50, 10.0, 100), 5);
    }

    #[test]
    fn best_trade_route_finds_best_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 10.0, tick: 1 });
        memory.price_knowledge.insert("belt".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 50.0, tick: 1 });
        memory.price_knowledge.insert("earth".into(), b);
        let route = best_trade_route(&memory).unwrap();
        assert_eq!(route.0, Commodity::Ore);
        assert_eq!(route.1, "belt");
        assert_eq!(route.2, "earth");
    }

    #[test]
    fn best_trade_route_none_for_thin_margin() {
        let mut memory = ShipMemory {
            price_knowledge: Default::default(),
            visited: vec![],
        };
        let mut a = std::collections::HashMap::new();
        a.insert(Commodity::Ore, PriceMemory { price: 100.0, tick: 1 });
        memory.price_knowledge.insert("a".into(), a);
        let mut b = std::collections::HashMap::new();
        b.insert(Commodity::Ore, PriceMemory { price: 105.0, tick: 1 });
        memory.price_knowledge.insert("b".into(), b);
        assert!(best_trade_route(&memory).is_none());
    }
}
