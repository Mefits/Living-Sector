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
    ai::{
        behavior_tree::{Blackboard, BtNode, BtStatus},
        personality::Personality,
    },
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

/// AI: personality + current goal + BT state (parameterized over ShipAction).
#[derive(Debug, Clone)]
pub struct ShipAI {
    pub personality: Personality,
    pub current_goal: String,
    pub current_bt: Option<BtNode<ShipAction>>,
}

/// Ship-specific BT leaf actions. Each variant carries the parameters it
/// needs — the dispatch closure in `ship::decide_and_act` reads them and
/// executes against the ship's components.
#[derive(Debug, Clone)]
pub enum ShipAction {
    /// Begin transit to a named location. Returns Running until arrival.
    Travel { destination: String },
    /// Mark the ship as docked at its current location.
    Dock,
    /// Undock (clear docked_at).
    Undock,
    /// Refill fuel to capacity (MVP: free refill at any location).
    Refuel,
    /// Buy up to `qty` units of `commodity` at the ship's current location.
    /// Returns Failure if no local price or ship can't afford any.
    Buy { commodity: Commodity, qty: u32 },
    /// Sell `qty` of `commodity` at the current location. `qty = 0` means "all".
    Sell { commodity: Commodity, qty: u32 },
    /// Sell every commodity in the hold.
    SellAll,
    /// Accept a delivery contract by id (Phase 8b).
    AcceptContract { contract_id: String },
    /// Pick up the cargo reserved for an accepted contract (Phase 8b).
    PickupCargo { contract_id: String },
    /// Deliver contract cargo and collect payment (Phase 8b).
    DeliverCargo { contract_id: String },
    /// Do nothing — always succeeds.
    Idle,
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
            bt_action: ai.current_bt.as_ref().and_then(|bt| bt.current_action()),
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
    let config = crate::simulation::config::TickConfig {
        ticks_per_second: 8,
        world_speed: if tick_multiplier == 0 { 0.25 } else { 8.0 / tick_multiplier as f32 },
    };

    // Collect entities first so each ship's closure can own a mutable borrow
    // in turn (nested par-style borrows don't work on hecs::World mut queries).
    let entities: Vec<hecs::Entity> = world
        .query::<&ShipIdentity>()
        .iter()
        .map(|(e, _)| e)
        .collect();

    for entity in entities {
        let mut q = match world.query_one::<(
            &mut ShipPosition,
            &mut ShipTransit,
            &mut ShipCargo,
            &mut ShipFuel,
            &mut ShipEconomy,
            &mut ShipAI,
            &mut ShipMemory,
            &mut ShipLifecycle,
        )>(entity) {
            Ok(q) => q,
            Err(_) => continue,
        };
        let (position, transit, cargo, fuel, economy, ai, memory, lifecycle) = match q.get() {
            Some(t) => t,
            None => continue,
        };

        // Ship in transit: no decisions to make, just update status string
        if transit.transit.is_some() {
            ai.current_goal = "in_transit".into();
            continue;
        }

        // --- Planner: build a BT if we don't have one ---
        // The planner is a small decision rule — BT execution is what
        // spreads the plan across ticks (a `travel` step, for example,
        // returns `Running` every tick until arrival).
        let needs_plan = ai.current_bt.is_none();
        if needs_plan {
            let (goal, bt) = plan_goal(position, cargo, fuel, economy, memory);
            ai.current_goal = goal.into();
            ai.current_bt = bt;
        }

        // --- Execute one BT step ---
        if let Some(mut bt) = ai.current_bt.take() {
            let mut bb = Blackboard::new();
            let status = {
                let mut dispatch = |action: &ShipAction, bb: &mut Blackboard| -> BtStatus {
                    execute_ship_action(
                        action,
                        entity,
                        position,
                        transit,
                        cargo,
                        fuel,
                        economy,
                        memory,
                        registry,
                        commands,
                        tick,
                        &config,
                        bb,
                    )
                };
                bt.tick(&mut bb, &mut dispatch)
            };

            match status {
                BtStatus::Running => ai.current_bt = Some(bt),
                BtStatus::Success | BtStatus::Failure => {
                    // Plan done — clear. Next tick replans.
                    ai.current_bt = None;
                }
            }
        }

        lifecycle.dirty = true;
    }
}

/// Planner: pick a goal + build its BT. Small decision rule.
///
/// Rule order:
/// 1. Fuel critical → refuel BT (dock → refuel → undock)
/// 2. Cargo onboard → sell_cargo BT (dock → sell_all → undock)
/// 3. Empty cargo + known profitable route → trade_run BT (travel → dock →
///    refuel → buy → undock → travel → dock → sell → undock)
/// 4. No cargo, no route → idle
fn plan_goal(
    position: &ShipPosition,
    cargo: &ShipCargo,
    fuel: &ShipFuel,
    _economy: &ShipEconomy,
    memory: &ShipMemory,
) -> (&'static str, Option<BtNode<ShipAction>>) {
    let at_loc = match &position.location_name {
        Some(l) => l.clone(),
        None => return ("idle", Some(BtNode::action(ShipAction::Idle))),
    };

    // 1. Fuel critical
    if fuel.fraction() < FUEL_CRITICAL_FRACTION {
        return ("refuel", Some(build_refuel_bt()));
    }

    // 2. Cargo onboard — sell it
    if cargo.used() > 0 {
        return ("sell_cargo", Some(build_sell_cargo_bt()));
    }

    // 3. Profitable trade route
    if let Some((commodity, buy_loc, sell_loc, _margin)) = best_trade_route(memory) {
        let bt = build_trade_run_bt(&at_loc, &buy_loc, &sell_loc, commodity);
        return ("trade_run", Some(bt));
    }

    ("idle", Some(BtNode::action(ShipAction::Idle)))
}

// --- BT builders ---

fn build_refuel_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::Refuel),
        BtNode::action(ShipAction::Undock),
    ])
}

fn build_sell_cargo_bt() -> BtNode<ShipAction> {
    BtNode::sequence(vec![
        BtNode::action(ShipAction::Dock),
        BtNode::action(ShipAction::SellAll),
        BtNode::action(ShipAction::Undock),
    ])
}

/// Build a trade_run BT. Start at `current`, visit `buy_loc`, buy `commodity`,
/// travel to `sell_loc`, sell, end at sell_loc.
///
/// If `current == buy_loc`, skip the initial travel leg.
fn build_trade_run_bt(
    current: &str,
    buy_loc: &str,
    sell_loc: &str,
    commodity: Commodity,
) -> BtNode<ShipAction> {
    let mut steps = Vec::with_capacity(10);
    if current != buy_loc {
        // Leg 1: travel to buy location
        steps.push(BtNode::action(ShipAction::Travel { destination: buy_loc.to_string() }));
    }
    // Buy
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::Refuel));
    steps.push(BtNode::action(ShipAction::Buy { commodity, qty: TRADE_QTY_DEFAULT }));
    steps.push(BtNode::action(ShipAction::Undock));
    // Leg 2: travel to sell location
    steps.push(BtNode::action(ShipAction::Travel { destination: sell_loc.to_string() }));
    // Sell
    steps.push(BtNode::action(ShipAction::Dock));
    steps.push(BtNode::action(ShipAction::SellAll));
    steps.push(BtNode::action(ShipAction::Undock));
    BtNode::sequence(steps)
}

// --- Action executor (the dispatch closure's body) ---

#[allow(clippy::too_many_arguments)]
fn execute_ship_action(
    action: &ShipAction,
    entity: hecs::Entity,
    position: &mut ShipPosition,
    transit: &mut ShipTransit,
    cargo: &mut ShipCargo,
    fuel: &mut ShipFuel,
    economy: &mut ShipEconomy,
    memory: &ShipMemory,
    registry: &WorldRegistry,
    commands: &mut CommandBuffer,
    tick: u64,
    config: &crate::simulation::config::TickConfig,
    _bb: &mut Blackboard,
) -> BtStatus {
    match action {
        ShipAction::Idle => BtStatus::Success,

        ShipAction::Dock => {
            if position.location_name.is_some() {
                // Docked_at facility resolution deferred — we mark "at-location"
                // by virtue of not being in transit. Real facility docking comes
                // with capacity checks in Phase 8b+.
                BtStatus::Success
            } else {
                BtStatus::Failure
            }
        }

        ShipAction::Undock => {
            position.docked_at = None;
            BtStatus::Success
        }

        ShipAction::Refuel => {
            fuel.fuel = fuel.fuel_capacity;
            BtStatus::Success
        }

        ShipAction::Travel { destination } => {
            // If we're already at the destination, step succeeds immediately
            if position.location_name.as_deref() == Some(destination.as_str()) {
                return BtStatus::Success;
            }
            // If already in transit, return Running until arrival
            if let Some(t) = &transit.transit {
                if tick >= t.arrival_tick {
                    // Arrival handled by advance_transits; this is the step completion
                    return BtStatus::Success;
                }
                return BtStatus::Running;
            }
            // Start the transit
            let from = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let distance = registry
                .travel_distance(&from, destination)
                .or_else(|| registry.travel_distance(destination, &from))
                .unwrap_or(60);
            let arrival = travel::arrival_tick(tick, distance, fuel.speed_modifier, config);
            transit.transit = Some(Transit {
                from,
                to: destination.clone(),
                departure_tick: tick,
                arrival_tick: arrival,
            });
            position.location_name = None;
            position.docked_at = None;
            BtStatus::Running
        }

        ShipAction::Buy { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let want = affordable_quantity(economy.credits, price, cargo.free()).min(*qty);
            if want == 0 {
                return BtStatus::Failure;
            }
            let cost = (price * want as f32) as i64;
            economy.credits -= cost;
            *cargo.cargo.entry(*commodity).or_insert(0) += want;
            cargo.cargo_age.insert(*commodity, tick);
            commands.push(SimCommand::RemoveSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: want as f32,
            });
            BtStatus::Success
        }

        ShipAction::Sell { commodity, qty } => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let price = match memory.price_knowledge.get(&at).and_then(|m| m.get(commodity)) {
                Some(pm) => pm.price,
                None => return BtStatus::Failure,
            };
            let have = cargo.cargo.get(commodity).copied().unwrap_or(0);
            let amount = if *qty == 0 { have } else { (*qty).min(have) };
            if amount == 0 {
                return BtStatus::Failure;
            }
            let revenue = (price * amount as f32) as i64;
            economy.credits += revenue;
            let new_remaining = have - amount;
            if new_remaining == 0 {
                cargo.cargo.remove(commodity);
                cargo.cargo_age.remove(commodity);
            } else {
                cargo.cargo.insert(*commodity, new_remaining);
            }
            commands.push(SimCommand::AddSupplyAtShipLocation {
                ship: entity,
                commodity: *commodity,
                quantity: amount as f32,
            });
            BtStatus::Success
        }

        ShipAction::SellAll => {
            let at = match &position.location_name {
                Some(l) => l.clone(),
                None => return BtStatus::Failure,
            };
            let prices = match memory.price_knowledge.get(&at) {
                Some(p) => p.clone(),
                None => return BtStatus::Failure,
            };
            let to_sell: Vec<_> = cargo
                .cargo
                .iter()
                .filter(|(_, &q)| q > 0)
                .map(|(&c, &q)| (c, q))
                .collect();
            if to_sell.is_empty() {
                return BtStatus::Success;
            }
            for (commodity, qty) in to_sell {
                if let Some(pm) = prices.get(&commodity) {
                    let revenue = (pm.price * qty as f32) as i64;
                    economy.credits += revenue;
                    cargo.cargo.remove(&commodity);
                    cargo.cargo_age.remove(&commodity);
                    commands.push(SimCommand::AddSupplyAtShipLocation {
                        ship: entity,
                        commodity,
                        quantity: qty as f32,
                    });
                }
            }
            BtStatus::Success
        }

        // Phase 8b: contract actions — stubbed out for now
        ShipAction::AcceptContract { .. }
        | ShipAction::PickupCargo { .. }
        | ShipAction::DeliverCargo { .. } => BtStatus::Success,
    }
}

fn affordable_quantity(credits: i64, price: f32, capacity: u32) -> u32 {
    if price <= 0.0 || credits <= 0 {
        return 0;
    }
    let by_credits = (credits as f32 / price) as u32;
    by_credits.min(capacity)
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
