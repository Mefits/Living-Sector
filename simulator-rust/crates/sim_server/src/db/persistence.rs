//! Persistence worker — batches dirty-agent flushes to SQLite.
//!
//! ## Pattern
//!
//! 1. At the end of each tick the engine collects dirty entities into
//!    `Vec<DbWrite>` and sends them over an mpsc channel to this worker.
//! 2. The worker dedups by (agent_kind, db_id) — a ship marked dirty 40
//!    times in 5 seconds still writes once.
//! 3. Every `PERSIST_SWEEP_SECS` seconds the worker opens a single
//!    transaction and applies the deduped batch. Tick counter goes in too.
//!
//! This mirrors the Elixir `PersistenceManager` (ETS dirty-set + sweep).
//! SQLite is WAL-mode with a single writer connection, so there's no
//! contention with tick-loop reads elsewhere.

use anyhow::Result;
use serde_json::json;
use sqlx::SqlitePool;
use std::collections::HashMap;
use tokio::sync::mpsc;
use tracing::{debug, info, warn};

/// A single persist request. The engine emits these per-tick; the worker
/// batches + dedups before touching SQLite.
#[derive(Debug, Clone)]
pub enum DbWrite {
    Ship {
        db_id: i64,
        credits: i64,
        fuel: f32,
        position_x: f32,
        position_y: f32,
        cargo_json: String,
        current_goal: String,
        active_contract_id: Option<String>,
        broke_strikes: u8,
        hoard_strikes: u8,
        idle_ticks: u32,
        /// JSON object mapping slot name → module slug (or null). Always
        /// emitted so the stored row stays in sync after any refit,
        /// without requiring a separate DbWrite variant.
        fitting_json: String,
    },
    Market {
        db_id: i64,
        prices_json: String,
        supply_json: String,
        demand_json: String,
        shortage_ticks_json: String,
    },
    Faction {
        id: String,
        treasury: i64,
    },
    /// Facility runtime state. Condition + reserves drift every tick;
    /// credits move on docking fees + restock + spread revenue + tax.
    /// `module_stock_json` is only meaningful for shipyards; other
    /// facilities emit an empty `{}` which is already the column default.
    Facility {
        db_id: i64,
        credits: i64,
        condition: f32,
        reserves_json: String,
        module_stock_json: String,
    },
    /// Population demographics + sentiment.
    Population {
        db_id: i64,
        population_count: i64,
        overall_sentiment: i32,
        food_satisfaction: i32,
        total_wealth: i64,
    },
    /// Celestial body orbital angle + resource state.
    Body {
        db_id: i64,
        current_angle: f32,
        resources_json: String,
    },
    /// Current tick counter for restart resume.
    Tick {
        tick: u64,
    },
    /// Delete a ship row by db_id — fires when the admin destroys a
    /// ship. Without this, the ECS entity despawns but the DB row
    /// remains, so restart resurrects the ship.
    DeleteShip { db_id: i64 },
    /// Symmetric to DeleteShip, for facilities.
    DeleteFacility { db_id: i64 },
}

impl DbWrite {
    /// Dedup key — newer writes replace older ones for the same agent.
    fn key(&self) -> (&'static str, String) {
        match self {
            DbWrite::Ship { db_id, .. } => ("ship", db_id.to_string()),
            DbWrite::Market { db_id, .. } => ("market", db_id.to_string()),
            DbWrite::Faction { id, .. } => ("faction", id.clone()),
            DbWrite::Facility { db_id, .. } => ("facility", db_id.to_string()),
            DbWrite::Population { db_id, .. } => ("population", db_id.to_string()),
            DbWrite::Body { db_id, .. } => ("body", db_id.to_string()),
            DbWrite::Tick { .. } => ("tick", String::new()),
            // Delete keys use a distinct namespace so a subsequent
            // upsert in the same flush doesn't overwrite the delete
            // and resurrect the row.
            DbWrite::DeleteShip { db_id } => ("ship_delete", db_id.to_string()),
            DbWrite::DeleteFacility { db_id } => ("facility_delete", db_id.to_string()),
        }
    }
}

pub struct PersistenceWorker {
    pool: SqlitePool,
    rx: mpsc::Receiver<DbWrite>,
    sweep_interval: std::time::Duration,
}

impl PersistenceWorker {
    pub fn new(
        pool: SqlitePool,
        rx: mpsc::Receiver<DbWrite>,
        sweep_interval: std::time::Duration,
    ) -> Self {
        Self { pool, rx, sweep_interval }
    }

    pub async fn run(mut self) {
        let mut sweep = tokio::time::interval(self.sweep_interval);
        sweep.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let mut buffer: HashMap<(&'static str, String), DbWrite> = HashMap::new();

        info!(
            "PersistenceWorker: sweep interval {}s",
            self.sweep_interval.as_secs()
        );

        loop {
            tokio::select! {
                msg = self.rx.recv() => {
                    match msg {
                        Some(write) => {
                            buffer.insert(write.key(), write);
                        }
                        None => {
                            // Sender dropped — final flush and exit.
                            if !buffer.is_empty() {
                                let taken = std::mem::take(&mut buffer);
                                if let Err(e) = Self::flush(&self.pool, taken.into_values().collect()).await {
                                    warn!("PersistenceWorker final flush failed: {e}");
                                }
                            }
                            info!("PersistenceWorker: channel closed, exiting");
                            return;
                        }
                    }
                }

                _ = sweep.tick() => {
                    if buffer.is_empty() {
                        continue;
                    }
                    let taken = std::mem::take(&mut buffer);
                    let count = taken.len();
                    let started = std::time::Instant::now();
                    match Self::flush(&self.pool, taken.into_values().collect()).await {
                        Ok(()) => debug!("PersistenceWorker: flushed {} writes in {:?}", count, started.elapsed()),
                        Err(e) => warn!("PersistenceWorker flush failed: {e}"),
                    }
                }
            }
        }
    }

    async fn flush(pool: &SqlitePool, writes: Vec<DbWrite>) -> Result<()> {
        let mut tx = pool.begin().await?;

        for write in writes {
            match write {
                DbWrite::Ship {
                    db_id,
                    credits,
                    fuel,
                    position_x,
                    position_y,
                    cargo_json,
                    current_goal,
                    active_contract_id,
                    broke_strikes,
                    hoard_strikes,
                    idle_ticks,
                    fitting_json,
                } => {
                    sqlx::query(
                        "UPDATE ships SET
                           credits=?1, fuel=?2, position_x=?3, position_y=?4,
                           cargo=?5, current_goal=?6, active_contract_id=?7,
                           broke_strikes=?8, hoard_strikes=?9, idle_ticks=?10,
                           fitting=?11,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?12",
                    )
                    .bind(credits)
                    .bind(fuel)
                    .bind(position_x)
                    .bind(position_y)
                    .bind(cargo_json)
                    .bind(current_goal)
                    .bind(active_contract_id)
                    .bind(broke_strikes as i64)
                    .bind(hoard_strikes as i64)
                    .bind(idle_ticks as i64)
                    .bind(fitting_json)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Market {
                    db_id,
                    prices_json,
                    supply_json,
                    demand_json,
                    shortage_ticks_json,
                } => {
                    sqlx::query(
                        "UPDATE markets SET
                           prices=?1, supply=?2, demand=?3, shortage_ticks=?4,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?5",
                    )
                    .bind(prices_json)
                    .bind(supply_json)
                    .bind(demand_json)
                    .bind(shortage_ticks_json)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Faction { id, treasury } => {
                    sqlx::query(
                        "UPDATE factions SET treasury=?1,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?2",
                    )
                    .bind(treasury)
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Facility {
                    db_id,
                    credits,
                    condition,
                    reserves_json,
                    module_stock_json,
                } => {
                    sqlx::query(
                        "UPDATE facilities SET
                           credits=?1, condition=?2, reserves=?3,
                           module_stock=?4,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?5",
                    )
                    .bind(credits)
                    .bind(condition as f64)
                    .bind(reserves_json)
                    .bind(module_stock_json)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Population {
                    db_id,
                    population_count,
                    overall_sentiment,
                    food_satisfaction,
                    total_wealth,
                } => {
                    sqlx::query(
                        "UPDATE populations SET
                           population_count=?1, overall_sentiment=?2,
                           food_satisfaction=?3, total_wealth=?4,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?5",
                    )
                    .bind(population_count)
                    .bind(overall_sentiment as i64)
                    .bind(food_satisfaction as i64)
                    .bind(total_wealth)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Body {
                    db_id,
                    current_angle,
                    resources_json,
                } => {
                    sqlx::query(
                        "UPDATE celestial_bodies SET
                           current_angle=?1, resources=?2,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?3",
                    )
                    .bind(current_angle as f64)
                    .bind(resources_json)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::Tick { tick } => {
                    let value = json!({ "current_tick": tick }).to_string();
                    sqlx::query(
                        "INSERT INTO simulation_state (key, value)
                         VALUES ('tick_counter', ?1)
                         ON CONFLICT(key) DO UPDATE SET
                           value=excluded.value,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
                    )
                    .bind(value)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::DeleteShip { db_id } => {
                    sqlx::query("DELETE FROM ships WHERE id = ?1")
                        .bind(db_id)
                        .execute(&mut *tx)
                        .await?;
                }

                DbWrite::DeleteFacility { db_id } => {
                    sqlx::query("DELETE FROM facilities WHERE id = ?1")
                        .bind(db_id)
                        .execute(&mut *tx)
                        .await?;
                }
            }
        }

        tx.commit().await?;
        Ok(())
    }
}

/// Read the persisted tick counter, if any. Used on startup to resume.
pub async fn load_tick_counter(pool: &SqlitePool) -> u64 {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM simulation_state WHERE key = 'tick_counter'")
            .fetch_optional(pool)
            .await
            .ok()
            .flatten();
    row.and_then(|(v,)| {
        serde_json::from_str::<serde_json::Value>(&v).ok().and_then(|j| {
            j.get("current_tick").and_then(|t| t.as_u64())
        })
    })
    .unwrap_or(0)
}
