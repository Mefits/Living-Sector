//! Persistence emit pass + per-component JSON serialisers.
//!
//! Each tick reserves one channel slot before collecting dirty state. All
//! economic entities, the contract board and tick enter one indivisible frame.
//! Backpressure leaves dirty flags untouched; the next admitted frame catches up.
//! The worker merges complete frames without awaiting, then commits in SQLite.
//!
//! ## JSON serialisers
//!
//! Three helpers ([`ship_fitting_to_json`], [`ship_progression_to_json`],
//! [`facility_fitting_to_json`]) emit the column-shaped JSON the SQLite
//! schema expects. They're `pub(crate)` so admin paths in `engine.rs`
//! and `http/admin.rs` can hand them to direct INSERTs without
//! routing through the persistence worker.
//!
//! Extracted from `engine.rs` in the Phase-21 god-module split.

use bevy_ecs::prelude::{Entity, World};
use sim_db::persistence::DbWrite;
use sim_core::simulation::spawner::AgentStore;
use tokio::sync::mpsc;

/// Lifecycle effects must travel with the contract/balance state they changed.
/// Retained in the World until an economic frame has a reserved channel slot.
#[derive(Default, bevy_ecs::prelude::Resource)]
pub(super) struct PendingLifecycleWrites(pub Vec<DbWrite>);

pub(super) fn queue_lifecycle_write(world: &mut World, write: DbWrite) {
    world.init_resource::<PendingLifecycleWrites>();
    world.resource_mut::<PendingLifecycleWrites>().0.push(write);
}

pub(super) fn has_lifecycle_writes(world: &World) -> bool {
    world.get_resource::<PendingLifecycleWrites>()
        .is_some_and(|pending| !pending.0.is_empty())
}

/// Serialise a `ShipFitting` to the slot-name → slug-or-null JSON shape
/// stored in the `ships.fitting` column. Parser: [`ship_fitting_from_json`].
pub(crate) fn ship_fitting_to_json(fitting: &sim_core::agents::ship::ShipFitting) -> String {
    let mut obj = serde_json::Map::new();
    for slot in sim_core::modules::SLOTS.iter().copied() {
        let v = match fitting.slot_slug(slot) {
            Some(s) => serde_json::Value::String(s.to_string()),
            None => serde_json::Value::Null,
        };
        obj.insert(slot.as_str().to_string(), v);
    }
    serde_json::Value::Object(obj).to_string()
}

/// Serialise a `ShipProgression` to the `{level, xp, retrofit_points}`
/// JSON shape stored in the `ships.progression` column.
pub(crate) fn ship_progression_to_json(p: &sim_core::agents::ship::ShipProgression) -> String {
    serde_json::json!({
        "level": p.level,
        "xp": p.xp,
        "retrofit_points": p.retrofit_points,
    })
    .to_string()
}

/// Serialise a `FacilityFitting` to the slot-name → slug-or-null JSON
/// shape stored in the `facilities.fitting` column.
pub(crate) fn facility_fitting_to_json(
    fitting: &sim_core::agents::facility::FacilityFitting,
) -> String {
    let mut obj = serde_json::Map::new();
    for slot in sim_core::facility_modules::FACILITY_SLOTS.iter().copied() {
        let v = match fitting.slots[slot.index()] {
            Some(s) => serde_json::Value::String(s.to_string()),
            None => serde_json::Value::Null,
        };
        obj.insert(slot.as_str().to_string(), v);
    }
    serde_json::Value::Object(obj).to_string()
}

pub(super) fn emit_persist_writes(
    world: &mut World,
    store: &mut AgentStore,
    tick: u64,
    tx: &mpsc::Sender<DbWrite>,
) {
    use sim_core::agents::{
        faction::FactionData,
        market::{MarketHistory, MarketIdentity, MarketPricing},
        ship::{
            ShipCargo, ShipEconomy, ShipFitting, ShipFuel, ShipIdentity, ShipLifecycle,
            ShipPosition, ShipProgression,
        },
    };

    // No dirty flag is cleared unless the entire frame can enter the queue.
    let Ok(permit) = tx.try_reserve() else { return; };
    let mut writes = Vec::new();

    // Ships
    //
    // ShipFitting arrived in Phase 18a; persistence of it in 18b. We read
    // it separately via get() because it's optional on legacy saves and
    // hecs requires any `&` column in the main query to be present on
    // every archetype. Fall back to the tier-1 default when absent so we
    // always emit a well-formed `fitting_json`.
    let mut ship_writes: Vec<DbWrite> = Vec::new();
    let mut dirty_ships: Vec<Entity> = Vec::new();
    {
        let mut q = world.query::<(
            Entity,
            &ShipIdentity,
            &ShipPosition,
            &ShipCargo,
            &ShipFuel,
            &ShipEconomy,
            &ShipLifecycle,
        )>();
        // Snapshot the per-ship data we need so we can do nested
        // optional-component reads (ShipProgression, ShipFitting) on
        // `&world` without holding the QueryState's borrow.
        let rows: Vec<(Entity, DbWrite, bool)> = q
            .iter(&world)
            .map(|(e, identity, pos, cargo, fuel, econ, life)| {
                let cargo_json: serde_json::Map<String, serde_json::Value> = cargo
                    .cargo
                    .iter()
                    .map(|(c, &q)| (c.as_str().to_string(), serde_json::Value::from(q)))
                    .collect();
                (
                    e,
                    DbWrite::Ship {
                        db_id: identity.db_id,
                        credits: econ.credits,
                        fuel: fuel.fuel,
                        position_x: pos.position.0,
                        position_y: pos.position.1,
                        cargo_json: serde_json::Value::Object(cargo_json).to_string(),
                        resume_json: serde_json::to_string(&sim_db::persistence::ShipResumeState {
                            crew_savings: world.get::<sim_core::agents::ship::ShipCrew>(e).map(|c| c.wages_credits).unwrap_or(0),
                            location_name: pos.location_name.clone(),
                            docked_db_id: pos.docked_at.and_then(|e| world.get::<sim_core::agents::facility::FacilityIdentity>(e).map(|id| id.db_id)),
                            system_id: pos.system_id.clone(),
                            universe_offset: pos.universe_offset,
                            transit: world.get::<sim_core::agents::ship::ShipTransit>(e).and_then(|t| t.transit.clone()),
                            cargo_age: cargo.cargo_age.clone(),
                            cargo_origin: cargo.cargo_origin.clone(),
                        }).expect("serializable ship resume state"),
                        current_goal: world.get::<sim_core::agents::ship::ShipAI>(e).map(|ai| ai.current_goal.clone()).unwrap_or_default(),
                        active_contract_id: econ.active_contract_id.clone(),
                        broke_strikes: life.broke_strikes,
                        hoard_strikes: life.hoard_strikes,
                        idle_ticks: life.idle_ticks,
                        // placeholders, filled below
                        fitting_json: String::new(),
                        progression_json: String::new(),
                    },
                    life.dirty,
                )
            })
            .collect();
        for (e, mut write, life_dirty) in rows {
            // A ship flushes when lifecycle OR progression (Phase 18d)
            // dirties. Fitting is mutated through the refit apply, which
            // also marks lifecycle dirty, so we don't track it separately
            // here.
            let prog_dirty = world
                .get::<ShipProgression>(e)
                .map(|p| p.dirty)
                .unwrap_or(false);
            if !life_dirty && !prog_dirty && !world.get::<sim_core::agents::ship::ShipCrew>(e).is_some_and(|c| c.dirty) {
                continue;
            }
            let fitting_json = world
                .get::<ShipFitting>(e)
                .map(|f| ship_fitting_to_json(f))
                .unwrap_or_else(|| ship_fitting_to_json(&ShipFitting::new_default()));
            let progression_json = world
                .get::<ShipProgression>(e)
                .map(|p| ship_progression_to_json(p))
                .unwrap_or_else(|| ship_progression_to_json(&ShipProgression::new()));
            if let DbWrite::Ship {
                fitting_json: ref mut fj,
                progression_json: ref mut pj,
                ..
            } = write
            {
                *fj = fitting_json;
                *pj = progression_json;
            }
            ship_writes.push(write);
            dirty_ships.push(e);
        }
    }
    for write in ship_writes {
        writes.push(write);
    }
    for e in dirty_ships {
        if let Some(mut crew) = world.get_mut::<sim_core::agents::ship::ShipCrew>(e) { crew.dirty = false; }
        if let Some(mut life) = world.get_mut::<ShipLifecycle>(e) {
            life.dirty = false;
        }
        if let Some(mut prog) = world.get_mut::<ShipProgression>(e) {
            prog.dirty = false;
        }
    }

    // Markets
    let mut market_q = world.query::<(&MarketIdentity, &MarketPricing, &mut MarketHistory)>();
    for (identity, pricing, mut hist) in market_q.iter_mut(world) {
        if !hist.dirty {
            continue;
        }
        let to_json = |m: &std::collections::HashMap<sim_core::economy::commodities::Commodity, f32>| {
            let map: serde_json::Map<String, serde_json::Value> = m
                .iter()
                .map(|(c, v)| (c.as_str().to_string(), serde_json::Value::from(*v)))
                .collect();
            serde_json::Value::Object(map).to_string()
        };
        let shortage_json = {
            let map: serde_json::Map<String, serde_json::Value> = hist
                .shortage_ticks
                .iter()
                .map(|(c, v)| (c.as_str().to_string(), serde_json::Value::from(*v)))
                .collect();
            serde_json::Value::Object(map).to_string()
        };
        writes.push(DbWrite::Market {
            db_id: identity.db_id,
            prices_json: to_json(&pricing.prices),
            supply_json: to_json(&pricing.supply),
            demand_json: to_json(&pricing.demand),
            shortage_ticks_json: shortage_json,
        });

        // Phase 20d (persistent trends): emit the freshest trend
        // sample, if one was added this tick. The in-memory ring's
        // sampling cadence (every `MARKET_TREND_SAMPLE_INTERVAL_BASE`
        // base ticks) means most market flushes have nothing new at
        // the back; we cheap-check that the latest sample's tick
        // matches the current tick before emitting. Same dedup-key
        // (market, tick) so two flushes in one tick collapse to a
        // single batch INSERT.
        if let Some(latest) = hist.trend_samples.back() {
            if latest.tick == tick {
                let entries: Vec<(String, f32, f32)> = latest
                    .prices
                    .iter()
                    .map(|(commodity, &price)| {
                        let supply =
                            latest.supply.get(commodity).copied().unwrap_or(0.0);
                        (commodity.as_str().to_string(), price, supply)
                    })
                    .collect();
                if !entries.is_empty() {
                    writes.push(DbWrite::MarketTrendBatch {
                        market_db_id: identity.db_id,
                        tick: tick as i64,
                        entries,
                    });
                }
            }
        }

        hist.dirty = false;
    }

    // Factions
    let mut faction_q = world.query::<&mut FactionData>();
    for mut data in faction_q.iter_mut(world) {
        if !data.dirty {
            continue;
        }
        writes.push(DbWrite::Faction {
            id: data.id.clone(),
            treasury: data.treasury,
        });
        data.dirty = false;
    }

    // All economic state shares the contract/tick cadence. A partial cadence
    // could persist the carrier payout without the payer debit or escrow.
    {
        use sim_core::agents::facility::{
            FacilityFitting, FacilityIdentity, FacilityOperations, FacilityStorage, ModuleStock,
        };
        // Collect which facilities to flush up front so we can read
        // optional components afterwards without juggling borrows.
        // A facility is dirty when FacilityOperations, ModuleStock,
        // FacilityFitting, or FacilityCrew has changed since the
        // last flush.
        use sim_core::agents::facility::FacilityCrew;
        let mut dirty: Vec<Entity> = Vec::new();
        {
            let mut q = world.query::<(Entity, &FacilityOperations)>();
            let entities: Vec<(Entity, bool)> =
                q.iter(&world).map(|(e, ops)| (e, ops.dirty)).collect();
            for (e, ops_dirty) in entities {
                if ops_dirty {
                    dirty.push(e);
                    continue;
                }
                let stock_dirty = world
                    .get::<ModuleStock>(e)
                    .map(|s| s.dirty)
                    .unwrap_or(false);
                if stock_dirty {
                    dirty.push(e);
                    continue;
                }
                let fit_dirty = world
                    .get::<FacilityFitting>(e)
                    .map(|f| f.dirty)
                    .unwrap_or(false);
                if fit_dirty {
                    dirty.push(e);
                    continue;
                }
                let crew_dirty = world
                    .get::<FacilityCrew>(e)
                    .map(|c| c.dirty)
                    .unwrap_or(false);
                if crew_dirty {
                    dirty.push(e);
                }
            }
        }

        for entity in dirty {
            let (db_id, credits, condition, reserves_json) = {
                let Some(fid) = world.get::<FacilityIdentity>(entity) else {
                    continue;
                };
                let Some(ops) = world.get::<FacilityOperations>(entity) else {
                    continue;
                };
                let Some(storage) = world.get::<FacilityStorage>(entity) else {
                    continue;
                };
                let reserves_json: serde_json::Map<String, serde_json::Value> = storage
                    .reserves
                    .iter()
                    .map(|(c, &v)| (c.as_str().to_string(), serde_json::Value::from(v)))
                    .collect();
                (
                    fid.db_id,
                    ops.credits,
                    ops.condition,
                    serde_json::Value::Object(reserves_json).to_string(),
                )
            };
            let module_stock_json = match world.get::<ModuleStock>(entity) {
                Some(stock) => {
                    let obj: serde_json::Map<String, serde_json::Value> = stock
                        .stock
                        .iter()
                        .map(|(k, &v)| (k.clone(), serde_json::Value::from(v)))
                        .collect();
                    serde_json::Value::Object(obj).to_string()
                }
                None => "{}".to_string(),
            };
            let fitting_json = match world.get::<FacilityFitting>(entity) {
                Some(f) => facility_fitting_to_json(f),
                None => "{}".to_string(),
            };
            let crew_state_json = match world.get::<FacilityCrew>(entity) {
                Some(c) => {
                    let snap = sim_core::agents::facility::FacilityCrewSnapshot::from(&*c);
                    serde_json::to_string(&snap).unwrap_or_else(|_| "{}".to_string())
                }
                None => "{}".to_string(),
            };
            writes.push(DbWrite::Facility {
                db_id,
                credits,
                condition,
                reserves_json,
                module_stock_json,
                fitting_json,
                crew_state_json,
            });
            if let Some(mut ops) = world.get_mut::<FacilityOperations>(entity) {
                ops.dirty = false;
            }
            if let Some(mut stock) = world.get_mut::<ModuleStock>(entity) {
                stock.dirty = false;
            }
            if let Some(mut fit) = world.get_mut::<FacilityFitting>(entity) {
                fit.dirty = false;
            }
            if let Some(mut crew) = world.get_mut::<FacilityCrew>(entity) {
                crew.dirty = false;
            }
        }
    }

    // Phase 19c-d: flush dirty construction sites on the same cadence
    // as facilities. Volume is low (one site per commodity-location)
    // so we push every dirty row directly — no further dedup needed.
    {
        use sim_core::agents::construction::ConstructionSite;
        let dirty: Vec<Entity> = {
            let mut q = world.query::<(Entity, &ConstructionSite)>();
            q.iter(&world)
                .filter(|(_, s)| s.dirty)
                .map(|(e, _)| e)
                .collect()
        };
        for entity in dirty {
            let row_opt = {
                let Some(site) = world.get::<ConstructionSite>(entity) else {
                    continue;
                };
                Some(sim_db::persistence::ConstructionSiteRow {
                    agent_id: site.id.clone(),
                    name: site.name.clone(),
                    facility_type: site.facility_type.clone(),
                    faction_id: site.faction_id.clone(),
                    body_id: site.body_id.clone(),
                    location_name: site.location_name.clone(),
                    commodity: site.commodity.as_str().to_string(),
                    progress_delivered: site.progress_delivered as i64,
                    progress_required: site.progress_required as i64,
                    position_x: site.position.0,
                    position_y: site.position.1,
                    spawned_at_tick: site.spawned_at_tick as i64,
                    completed: site.completed,
                })
            };
            if let Some(row) = row_opt {
                writes.push(DbWrite::ConstructionSiteUpsert { row });
            }
            if let Some(mut site) = world.get_mut::<ConstructionSite>(entity) {
                site.dirty = false;
            }
        }
    }

    {
        use sim_core::agents::population::{
            PopDemographics, PopEconomy, PopIdentity, PopSentiment,
        };
        let mut q =
            world.query::<(&PopIdentity, &PopDemographics, &PopEconomy, &mut PopSentiment)>();
        for (pid, demo, econ, mut sent) in q.iter_mut(world) {
            if !sent.dirty {
                continue;
            }
            writes.push(DbWrite::Population {
                employed_fraction: demo.employed_fraction,
                db_id: pid.db_id,
                population_count: demo.population_count,
                overall_sentiment: sent.overall_sentiment,
                food_satisfaction: sent.food_satisfaction,
                total_wealth: econ.total_wealth,
            });
            sent.dirty = false;
        }
    }

    {
        use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit, BodyResources};
        let mut q = world.query::<(&BodyIdentity, &mut BodyOrbit, &BodyResources)>();
        for (bid, mut orbit, resources) in q.iter_mut(world) {
            if !orbit.dirty {
                continue;
            }
            let resources_json: serde_json::Map<String, serde_json::Value> = resources
                .resources
                .iter()
                .map(|(c, &v)| (c.as_str().to_string(), serde_json::Value::from(v)))
                .collect();
            writes.push(DbWrite::Body {
                db_id: bid.db_id,
                current_angle: orbit.current_angle,
                resources_json: serde_json::Value::Object(resources_json).to_string(),
            });
            orbit.dirty = false;
        }
    }

    writes.push(DbWrite::Tick { tick });
    let rows = store.contracts.iter()
        .map(sim_db::persistence::ContractRow::from).collect();
    writes.push(DbWrite::ContractBoardSnapshot { rows });
    if let Some(mut pending) = world.get_resource_mut::<PendingLifecycleWrites>() {
        writes.append(&mut pending.0);
    }
    permit.send(DbWrite::EconomicFrame { writes });
}

#[cfg(test)]
mod checkpoint_tests {
    use super::*;
    use sim_core::agents::faction::{FactionColors, FactionData};
    use sim_core::ai::personality::Personality;

    #[test]
    fn checkpoint_backpressure_keeps_dirty_state_until_whole_frame_is_admitted() {
        let mut world = World::new();
        let entity = world.spawn(FactionData {
            id: "issuer".into(), name: "Issuer".into(), faction_type: "normal".into(),
            home_system: String::new(), treasury: 850,
            personality: Personality::balanced_trader(),
            colors: FactionColors { primary: String::new(), secondary: String::new() },
            active_subsidies: 0, dirty: true,
        }).id();
        let mut store = AgentStore::new();
        let (tx, mut rx) = mpsc::channel(1);
        tx.try_send(DbWrite::Tick { tick: 1 }).unwrap();
        emit_persist_writes(&mut world, &mut store, 2, &tx);
        assert!(world.get::<FactionData>(entity).unwrap().dirty);
        assert_eq!(rx.len(), 1);
        rx.try_recv().unwrap();
        // Deliberately not a multiple of 16: no old contract cadence remains.
        emit_persist_writes(&mut world, &mut store, 3, &tx);
        assert!(!world.get::<FactionData>(entity).unwrap().dirty);
        let DbWrite::EconomicFrame { writes } = rx.try_recv().unwrap() else { panic!("expected complete frame"); };
        assert!(writes.iter().any(|w| matches!(w, DbWrite::Faction { treasury: 850, .. })));
        assert!(writes.iter().any(|w| matches!(w, DbWrite::ContractBoardSnapshot { .. })));
        assert!(writes.iter().any(|w| matches!(w, DbWrite::Tick { tick: 3 })));
        assert!(rx.try_recv().is_err());
    }
}
