//! WebSocket broadcast publishers + diagnostic loggers.
//!
//! Each publish helper takes the most recent `SnapshotCache` slice for
//! one entity kind and sends a `ServerMsg` variant to every WS client
//! through the broadcast channel. Cadences (every tick / every 8 / 16 /
//! 32) are decided in [`super::run_tick_loop`]; this module is just the
//! per-cadence formatter.
//!
//! Log helpers (`log_*`) emit periodic structured info-level summaries
//! used by `scripts/smoke.sh` and ad-hoc tail-debugging. Cheap aggregate
//! queries — they never touch hot paths since they fire every 80 ticks.
//!
//! Extracted from `engine.rs` in the Phase-21 god-module split.

use crate::snapshot::SnapshotCache;
use crate::ws::protocol::{PositionEntry, ServerMsg};
use bevy_ecs::prelude::World;
use sim_core::agents::market::{MarketIdentity, MarketPricing};
use sim_core::simulation::spawner::AgentStore;
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::info;

pub(super) fn publish_positions(
    tick: u64,
    interval_ms: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let entities: Vec<PositionEntry> = snapshots
        .positions
        .iter()
        .map(|e| {
            let id = e.key().clone();
            let (x, y) = *e.value();
            let kind = if id.starts_with("ship-") {
                "ship"
            } else if id.starts_with("facility-") {
                "facility"
            } else if id.starts_with("site-") {
                // Phase 19c: construction sites are a new rendered
                // kind — Godot draws a scaffold placeholder here.
                "site"
            } else {
                // Body ids in the JSON world data are bare ("earth", "mars",
                // etc.) — default everything non-ship/non-facility to "body".
                "body"
            };
            PositionEntry { id, x, y, kind: kind.to_string() }
        })
        .collect();
    let msg = ServerMsg::Positions { tick, interval_ms, entities };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn publish_ship_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let ships: Vec<serde_json::Value> = snapshots
        .ships
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::ShipStates { tick, ships };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn publish_market_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let markets: Vec<serde_json::Value> = snapshots
        .markets
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::MarketStates { tick, markets };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn publish_facility_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let facilities: Vec<serde_json::Value> = snapshots
        .facilities
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::FacilityStates { tick, facilities };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn publish_population_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let populations: Vec<serde_json::Value> = snapshots
        .populations
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::PopulationStates { tick, populations };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn publish_faction_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let factions: Vec<serde_json::Value> = snapshots
        .factions
        .iter()
        .filter_map(|e| serde_json::to_value(e.value()).ok())
        .collect();
    let msg = ServerMsg::FactionStates { tick, factions };
    let _ = tx.send(Arc::new(msg));
}

/// Publish the full contract board from the snapshot cache (refreshed
/// every tick in `SnapshotCache::update_contracts`).
pub(super) fn publish_contract_states(
    tick: u64,
    snapshots: &SnapshotCache,
    tx: &broadcast::Sender<Arc<ServerMsg>>,
) {
    let contracts: Vec<serde_json::Value> = snapshots
        .contracts
        .iter()
        .map(|e| e.value().clone())
        .collect();
    let msg = ServerMsg::ContractStates { tick, contracts };
    let _ = tx.send(Arc::new(msg));
}

pub(super) fn log_sample_market(world: &mut World, store: &mut AgentStore, label: &str) {
    use sim_core::economy::commodities::Commodity::*;
    let target = store
        .market_at_location
        .get("earth-station")
        .copied()
        .or_else(|| store.market_by_id.values().next().copied());
    if let Some(entity) = target {
        let mut q = world.query::<(&MarketIdentity, &MarketPricing)>();
        if let Ok((id, pricing)) = q.get(&world, entity) {
            let fuel = pricing.prices.get(&Fuel).copied().unwrap_or(0.0);
            let food = pricing.prices.get(&Food).copied().unwrap_or(0.0);
            let ore = pricing.prices.get(&Ore).copied().unwrap_or(0.0);
            let fuel_supply = pricing.supply.get(&Fuel).copied().unwrap_or(0.0);
            info!(
                "market[{}] {}: fuel={:.2} food={:.2} ore={:.2} fuel_supply={:.0}",
                id.id, label, fuel, food, ore, fuel_supply,
            );
        }
    }
}

pub(super) fn log_contract_board(store: &AgentStore, tick: u64) {
    let counts = store.contracts.counts_by_status();
    if !counts.is_empty() {
        info!(tick, "contracts: {:?} total={}", counts, store.contracts.len());
    }
}

pub(super) fn log_factions(world: &mut World, _store: &mut AgentStore, tick: u64) {
    let money = sim_core::economy::money::MoneySnapshot::capture(world, &_store.contracts);
    info!(tick, money = %serde_json::to_string(&money).unwrap(), "money_accounts");
    use sim_core::agents::faction::FactionData;
    let mut q = world.query::<&FactionData>();
    let mut totals: Vec<(String, i64)> = q
        .iter(&world)
        .map(|d| (d.id.clone(), d.treasury))
        .collect();
    totals.sort_by(|a, b| b.1.cmp(&a.1));
    let summary: Vec<String> = totals
        .iter()
        .map(|(id, t)| format!("{id}={t}"))
        .collect();
    info!(tick, "factions: {}", summary.join(", "));
}

pub(super) fn log_sample_ships(world: &mut World, _store: &mut AgentStore, tick: u64) {
    use sim_core::agents::ship::{ShipAI, ShipCargo, ShipCrew, ShipEconomy, ShipMemory};
    let mut by_goal: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
    let mut by_task: std::collections::HashMap<&'static str, u32> = std::collections::HashMap::new();
    let mut total_credits: i64 = 0;
    let mut ships_with_cargo: u32 = 0;
    let mut ship_count: u32 = 0;
    let mut max_credits: i64 = 0;
    let mut min_credits: i64 = i64::MAX;
    let mut total_visited: u32 = 0;
    let mut total_morale: f32 = 0.0;
    let mut min_morale: f32 = 100.0;
    let mut q = world.query::<(&ShipAI, &ShipEconomy, &ShipCargo, &ShipMemory, &ShipCrew)>();
    for (ai, econ, cargo, mem, crew) in q.iter(&world) {
        *by_goal.entry(ai.current_goal.clone()).or_insert(0) += 1;
        *by_task.entry(crew.current_task.as_str()).or_insert(0) += 1;
        total_credits += econ.credits;
        max_credits = max_credits.max(econ.credits);
        min_credits = min_credits.min(econ.credits);
        if cargo.used() > 0 {
            ships_with_cargo += 1;
        }
        total_visited += mem.visited.len() as u32;
        total_morale += crew.morale;
        min_morale = min_morale.min(crew.morale);
        ship_count += 1;
    }
    if ship_count > 0 {
        let avg = total_credits / ship_count as i64;
        let avg_visited = total_visited as f32 / ship_count as f32;
        let avg_morale = total_morale / ship_count as f32;
        info!(
            tick,
            "ships: {:?} | tasks: {:?} | credits avg/min/max={}/{}/{} | with_cargo={} | avg_visited={:.1} | morale avg/min={:.0}/{:.0}",
            by_goal, by_task, avg, min_credits, max_credits, ships_with_cargo, avg_visited, avg_morale, min_morale,
        );
    }
}
