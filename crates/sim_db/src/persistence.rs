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
use tokio::sync::{mpsc, oneshot};
use tracing::{debug, info, warn};

/// Stable IDs only: ECS Entity handles are resolved anew on load.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ShipResumeState {
    #[serde(default)]
    pub crew_savings: i64,
    pub location_name: Option<String>,
    pub docked_db_id: Option<i64>,
    pub system_id: String,
    pub universe_offset: (f32, f32),
    pub transit: Option<sim_core::agents::ship::Transit>,
    pub cargo_age: HashMap<sim_core::economy::commodities::Commodity, u64>,
    pub cargo_origin: HashMap<sim_core::economy::commodities::Commodity, (String, f32)>,
}

/// Creation metadata; runtime balances/reserves follow in the same frame.
#[derive(Debug, Clone)]
pub struct ConstructedFacilityRow {
    pub db_id: i64,
    pub source_site_id: String,
    pub name: String,
    pub facility_type: String,
    pub faction_id: String,
    pub body_id: String,
    pub location_id: i64,
    pub location_name: String,
    pub docking_capacity: u32,
    pub credits: i64,
    pub reputation: i32,
    pub condition: f32,
}

/// A single persist request. The engine emits these per-tick; the worker
/// batches + dedups before touching SQLite.
#[derive(Debug, Clone)]
pub enum DbWrite {
    ConstructedFacility { row: ConstructedFacilityRow },
    ColonyPopulation { db_id: i64, label: String, location: String, faction: String },
    ColonyEstablished { db_id: i64, location: String },
    /// One admitted tick: merge all members synchronously before any flush.
    /// Never deduplicate frames themselves: they contain incremental dirty rows.
    EconomicFrame { writes: Vec<DbWrite> },
    Ship {
        db_id: i64,
        credits: i64,
        fuel: f32,
        position_x: f32,
        position_y: f32,
        cargo_json: String,
        resume_json: String,
        current_goal: String,
        active_contract_id: Option<String>,
        broke_strikes: u8,
        hoard_strikes: u8,
        idle_ticks: u32,
        /// JSON object mapping slot name → module slug (or null). Always
        /// emitted so the stored row stays in sync after any refit,
        /// without requiring a separate DbWrite variant.
        fitting_json: String,
        /// JSON object `{level, xp, retrofit_points}` for ship progression.
        /// Flushed whenever any field on the ship changes.
        progression_json: String,
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
        /// `{slot: slug | null}` JSON mirror of `FacilityFitting`.
        /// Always emitted on any facility flush so tier-2/3 swaps land
        /// in the DB the same sweep they mutate RAM.
        fitting_json: String,
        /// JSON mirror of `FacilityCrew` (Phase 19a). Empty `{}`
        /// encodes "use type default on next load"; a populated
        /// object round-trips crew_count / morale / hunger / food_debt.
        crew_state_json: String,
    },
    /// Slowly moving station orbital phase. Persisted independently of
    /// economic balances to avoid marking every facility economically dirty.
    FacilityOrbit { db_id: i64, orbit_angle: f32 },
    /// Population demographics + sentiment.
    Population {
        employed_fraction: f32,
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
    /// Phase 19g: append a retirement row when a ship gets
    /// decommissioned. Retained after the ships table row is
    /// deleted so the client can render a post-mortem trail.
    RetireShip { row: RetirementRow },
    /// Phase 19c-d: construction-site upsert. Sites persist across
    /// restarts so a half-built site + its in-flight contract don't
    /// vanish on reboot. INSERT OR REPLACE keyed on `agent_id` —
    /// volume is low (≤ one site per faction-commodity-location) so
    /// upsert overhead is negligible vs. an UPDATE+INSERT split.
    ConstructionSiteUpsert { row: ConstructionSiteRow },
    /// Drop a site row by agent_id — fires when the site materialises
    /// into a real facility (or an admin deletes it).
    ConstructionSiteDelete { agent_id: String },
    /// Full snapshot of the contract board. Included in each admitted economic
    /// frame together with dirty balances and tick. Applied as
    /// DELETE + bulk INSERT in one transaction so removals (paid /
    /// expired) land in the same sweep that upserts still-live
    /// contracts. `rows` is a pre-serialized list of
    /// `(id, type, status, requestor_id, fulfiller_id, commodity,
    ///   quantity, source_loc, dest_loc, payment, initial_payment,
    ///   faction_id, min_reputation, initial_min_reputation,
    ///   mission_category, posted_at_tick, accepted_at_tick,
    ///   expires_at_tick)` tuples — built in the engine so the worker
    ///   stays free of sim_core types.
    ContractBoardSnapshot {
        rows: Vec<ContractRow>,
    },
    /// Phase 20d (persistent trends): one batch of trend samples for
    /// a single market at a single tick — multiple commodities, all
    /// captured in lockstep with the in-memory `MarketTrendSample`.
    /// One row per (market, tick, commodity) lands in
    /// `market_trend_samples`. The dedup key includes `tick` so two
    /// emissions at the same tick collapse, but consecutive emissions
    /// (different ticks) accumulate.
    MarketTrendBatch {
        market_db_id: i64,
        tick: i64,
        /// `(commodity_str, price, supply)` per commodity, prebuilt by
        /// the engine so the worker stays free of sim_core types.
        entries: Vec<(String, f32, f32)>,
    },
}

/// Phase 19g: final snapshot captured when a ship is decommissioned.
/// Pushed through the persistence channel so the INSERT happens on
/// the worker thread, not blocking the tick loop.
#[derive(Debug, Clone)]
pub struct RetirementRow {
    pub agent_id: String,
    pub name: String,
    pub class: String,
    pub faction_id: String,
    pub final_location: String,
    pub final_credits: i64,
    pub final_crew_morale: i32,
    pub final_fuel_pct: i32,
    pub broke_strikes: i32,
    pub hoard_strikes: i32,
    pub retired_at_tick: i64,
    pub reason: String,
}

/// Flat construction-site row pushed by the engine flush sweep.
/// Mirrors the `construction_sites` table schema verbatim.
#[derive(Debug, Clone)]
pub struct ConstructionSiteRow {
    pub labor_state: String,
    pub agent_id: String,
    pub name: String,
    pub facility_type: String,
    pub faction_id: String,
    pub body_id: String,
    pub location_name: String,
    pub commodity: String,
    pub progress_delivered: i64,
    pub progress_required: i64,
    pub position_x: f32,
    pub position_y: f32,
    pub spawned_at_tick: i64,
    pub completed: bool,
}

/// Flat contract row pushed from the engine to the persistence
/// worker. Mirrors the `contracts` table schema after migration 008.
#[derive(Debug, Clone)]
pub struct ContractRow {
    pub id: String,
    pub contract_type: String,
    pub status: String,
    pub requestor_id: String,
    pub fulfiller_id: Option<String>,
    pub commodity: String,
    pub quantity: i64,
    pub source_location: String,
    pub destination_location: String,
    pub payment: i64,
    pub initial_payment: i64,
    pub funding_json: Option<String>,
    pub renewal_count: i64,
    pub faction_id: Option<String>,
    pub min_reputation: i64,
    pub initial_min_reputation: i64,
    pub mission_category: Option<String>,
    pub posted_at_tick: i64,
    pub accepted_at_tick: Option<i64>,
    pub expires_at_tick: i64,
}

impl From<&sim_core::economy::contracts::Contract> for ContractRow {
    fn from(c: &sim_core::economy::contracts::Contract) -> Self {
        Self {
            id: c.id.clone(),
            contract_type: c.contract_type.as_str().to_string(),
            status: match c.status {
                sim_core::economy::contracts::ContractStatus::Posted => "posted",
                sim_core::economy::contracts::ContractStatus::Accepted => "accepted",
                sim_core::economy::contracts::ContractStatus::PickedUp => "picked_up",
                sim_core::economy::contracts::ContractStatus::Delivered => "delivered",
                sim_core::economy::contracts::ContractStatus::Paid => "paid",
                sim_core::economy::contracts::ContractStatus::Expired => "expired",
            }
            .to_string(),
            requestor_id: c.requestor_id.clone(),
            fulfiller_id: c.fulfiller_id.clone(),
            commodity: c.commodity.as_str().to_string(),
            quantity: c.quantity as i64,
            source_location: c.source_location.clone(),
            destination_location: c.destination_location.clone(),
            payment: c.payment,
            initial_payment: if c.initial_payment > 0 {
                c.initial_payment
            } else {
                c.payment
            },
            funding_json: c
                .funding
                .as_ref()
                .map(|f| serde_json::to_string(f).expect("integer contract funding")),
            renewal_count: c.renewal_count as i64,
            faction_id: c.faction_id.clone(),
            min_reputation: c.min_reputation as i64,
            initial_min_reputation: c.initial_min_reputation as i64,
            mission_category: c.mission_category.clone(),
            posted_at_tick: c.posted_at_tick as i64,
            accepted_at_tick: c.accepted_at_tick.map(|t| t as i64),
            expires_at_tick: c.expires_at_tick as i64,
        }
    }
}

#[cfg(test)]
mod escrow_tests {
    use super::*;
    use sim_core::economy::{
        commodities::Commodity,
        contracts::{ContractBoard, ContractStatus, FundingSource},
    };
    use sim_core::simulation::spawner::AgentStore;

    #[tokio::test]
    async fn strategy_block_creation_and_site_removal_rollback_together() {
        let pool = crate::pool::create_pool("sqlite::memory:").await.unwrap();
        crate::pool::run_migrations(&pool).await.unwrap();
        for sql in [
            "INSERT INTO star_systems (id,name) VALUES (1,'sol')",
            "INSERT INTO celestial_bodies (id,body_id,name,body_type,orbit_radius,orbit_period,current_angle,star_system_id) VALUES (1,'earth','Earth','planet',1,100,0,1)",
            "INSERT INTO locations (id,name,loc_type,celestial_body_id) VALUES (1,'port','station',1)",
            "INSERT INTO factions (id,name,faction_type,treasury) VALUES ('owner','Owner','normal',1000)",
            "INSERT INTO construction_sites (agent_id,name,facility_type,faction_id,body_id,location_name,commodity,progress_required,position_x,position_y,spawned_at_tick) VALUES ('site','Factory','factory','owner','earth','port','ore',10,0,0,0)",
        ] { sqlx::query(sql).execute(&pool).await.unwrap(); }
        let mut buffer = HashMap::new();
        PersistenceWorker::buffer_write(&mut buffer, DbWrite::EconomicFrame { writes: vec![
            DbWrite::ConstructionSiteDelete { agent_id: "site".into() },
            DbWrite::Faction { id: "owner".into(), treasury: 800 },
            DbWrite::ConstructedFacility { row: ConstructedFacilityRow { db_id: -1, source_site_id: "site".into(),
                name: "Factory".into(), facility_type: "factory".into(), faction_id: "owner".into(),
                body_id: "earth".into(), location_id: 1, location_name: "port".into(), docking_capacity: 4,
                credits: 200, reputation: 50, condition: 1.0 } },
        ]});
        sqlx::query("CREATE TRIGGER fail_site_delete BEFORE DELETE ON construction_sites BEGIN SELECT RAISE(ABORT, 'checkpoint failure'); END")
            .execute(&pool).await.unwrap();
        assert!(PersistenceWorker::flush_buffer(&pool, &mut buffer).await.is_err());
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM facilities").fetch_one(&pool).await.unwrap();
        assert_eq!(count, 0);
        let balance: i64 = sqlx::query_scalar("SELECT treasury FROM factions WHERE id='owner'").fetch_one(&pool).await.unwrap();
        assert_eq!(balance, 1000);
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM construction_sites").fetch_one(&pool).await.unwrap();
        assert_eq!(count, 1);
        assert_eq!(buffer.len(), 3);
        sqlx::query("DROP TRIGGER fail_site_delete").execute(&pool).await.unwrap();
        PersistenceWorker::flush_buffer(&pool, &mut buffer).await.unwrap();
        PersistenceWorker::flush_buffer(&pool, &mut buffer).await.unwrap();
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM facilities WHERE construction_site_id='site'").fetch_one(&pool).await.unwrap();
        assert_eq!(count, 1);
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM construction_sites").fetch_one(&pool).await.unwrap();
        assert_eq!(count, 0);
        let total: i64 = sqlx::query_scalar("SELECT (SELECT treasury FROM factions WHERE id='owner') + (SELECT credits FROM facilities WHERE id=-1)").fetch_one(&pool).await.unwrap();
        assert_eq!(total, 1000);
        pool.close().await;
    }

    #[tokio::test]
    async fn flight_recovery_sqlite_roundtrip_restores_transit_docks_and_cargo() {
        use sim_core::agents::ship::{ShipPosition, ShipTransit, ShipCargo, ShipEconomy, ShipAI, Transit};
        let pool = crate::pool::create_pool("sqlite::memory:").await.unwrap();
        crate::pool::run_migrations(&pool).await.unwrap();
        for sql in [
            "INSERT INTO star_systems (id,name) VALUES (1,'sol')",
            "INSERT INTO celestial_bodies (id,body_id,name,body_type,orbit_radius,orbit_period,current_angle,star_system_id) VALUES (1,'earth','Earth','planet',1,100,0,1)",
            "INSERT INTO locations (id,name,loc_type,celestial_body_id) VALUES (1,'port','station',1)",
            "INSERT INTO facilities (id,name,facility_type,location_id) VALUES (7,'Station','station',1)",
            "INSERT INTO ships (id,name,docked_at,location_name,transit_from,transit_to,transit_departure_tick,transit_arrival_tick) VALUES (10,'Runner',7,'obsolete','old','stale',1,2)",
        ] { sqlx::query(sql).execute(&pool).await.unwrap(); }
        for mode in 0..3 {
            let transit = (mode == 0).then(|| Transit { from: "source".into(), to: "port".into(),
                departure_tick: 20, arrival_tick: 80, departure_position: Some((3.0, 4.0)),
                distance_total: 100.0, distance_travelled: 45.0 });
            let resume = ShipResumeState {
                crew_savings: 77,
                location_name: (mode != 0).then(|| "port".into()),
                docked_db_id: (mode == 1).then_some(7), system_id: "sol".into(),
                universe_offset: (12.0, 34.0), transit,
                cargo_age: [(Commodity::Ore, 18)].into(),
                cargo_origin: [(Commodity::Ore, ("source".into(), 3.5))].into(),
            };
            PersistenceWorker::flush(&pool, vec![DbWrite::Ship {
                db_id: 10, credits: 900, fuel: 55.0, position_x: 8.0, position_y: 9.0,
                cargo_json: "{\"ore\":10}".into(), resume_json: serde_json::to_string(&resume).unwrap(),
                current_goal: "fulfill_delivery".into(), active_contract_id: Some("held".into()),
                broke_strikes: 0, hoard_strikes: 0, idle_ticks: 0,
                fitting_json: "{}".into(), progression_json: "{}".into(),
            }]).await.unwrap();
            let mut world = bevy_ecs::prelude::World::new();
            let store = crate::spawner::load_agents(&mut world, &pool,
                &sim_core::world::registry::WorldRegistry::default(),
                &sim_core::simulation::config::TickConfig::DEFAULT).await.unwrap();
            let ship = store.ship_by_id["ship-runner"];
            let pos = world.get::<ShipPosition>(ship).unwrap();
            assert_eq!(world.get::<sim_core::agents::ship::ShipCrew>(ship).unwrap().wages_credits, 77);
            assert_eq!(pos.location_name, resume.location_name);
            assert_eq!(pos.position, (8.0, 9.0));
            assert_eq!(pos.universe_offset, (12.0, 34.0));
            assert_eq!(pos.docked_at.is_some(), mode == 1);
            if let Some(dock) = pos.docked_at {
                assert!(world.get::<sim_core::agents::facility::FacilityStorage>(dock).unwrap().docked_ships.contains(&ship));
            }
            assert_eq!(serde_json::to_value(&world.get::<ShipTransit>(ship).unwrap().transit).unwrap(),
                serde_json::to_value(&resume.transit).unwrap());
            let cargo = world.get::<ShipCargo>(ship).unwrap();
            assert_eq!(cargo.cargo[&Commodity::Ore], 10);
            assert_eq!(cargo.cargo_age[&Commodity::Ore], 18);
            assert_eq!(cargo.cargo_origin[&Commodity::Ore], ("source".into(), 3.5));
            assert_eq!(world.get::<ShipEconomy>(ship).unwrap().active_contract_id.as_deref(), Some("held"));
            assert_eq!(world.get::<ShipAI>(ship).unwrap().current_goal, "fulfill_delivery");
        }
        pool.close().await;
    }

    #[tokio::test]
    async fn lifecycle_tombstone_wins_over_stale_site_upsert() {
        let pool = crate::pool::create_pool("sqlite::memory:").await.unwrap();
        crate::pool::run_migrations(&pool).await.unwrap();
        let row = ConstructionSiteRow {
            labor_state: "{}".into(),
            agent_id: "site".into(), name: "Site".into(), facility_type: "factory".into(),
            faction_id: "issuer".into(), body_id: "earth".into(), location_name: "port".into(),
            commodity: "ore".into(), progress_delivered: 10, progress_required: 10,
            position_x: 0.0, position_y: 0.0, spawned_at_tick: 1, completed: true,
        };
        // Force the formerly unsafe order: delete followed by an older upsert.
        PersistenceWorker::flush(&pool, vec![
            DbWrite::ConstructionSiteDelete { agent_id: "site".into() },
            DbWrite::ConstructionSiteUpsert { row },
        ]).await.unwrap();
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM construction_sites")
            .fetch_one(&pool).await.unwrap();
        assert_eq!(count, 0);
        pool.close().await;
    }

    #[tokio::test]
    async fn checkpoint_rollback_retains_complete_frames_for_retry() {
        let pool = crate::pool::create_pool("sqlite::memory:").await.unwrap();
        crate::pool::run_migrations(&pool).await.unwrap();
        sqlx::query("INSERT INTO factions (id, name, faction_type, treasury) VALUES ('issuer', 'Issuer', 'normal', 880)")
            .execute(&pool).await.unwrap();
        let mut board = ContractBoard::new();
        let id = board.post_delivery_for("issuer".into(), None, Commodity::Ore,
            10, "source".into(), "port".into(), 120, 0, 1000);
        board.register_prepaid(&id, FundingSource::Faction);
        PersistenceWorker::flush(&pool, vec![
            DbWrite::ContractBoardSnapshot { rows: board.iter().map(ContractRow::from).collect() },
            DbWrite::Tick { tick: 1 },
        ]).await.unwrap();
        board.get_mut(&id).unwrap().funding.as_mut().unwrap().reserved = 150;
        let mut buffer = HashMap::new();
        PersistenceWorker::buffer_write(&mut buffer, DbWrite::EconomicFrame { writes: vec![
            DbWrite::Faction { id: "issuer".into(), treasury: 850 },
            DbWrite::ContractBoardSnapshot { rows: board.iter().map(ContractRow::from).collect() },
            DbWrite::Tick { tick: 2 },
        ]});
        // A later frame omits an unchanged payer. It must not discard that
        // payer's still-uncommitted debit from the preceding frame.
        PersistenceWorker::buffer_write(&mut buffer, DbWrite::EconomicFrame { writes: vec![
            DbWrite::ContractBoardSnapshot { rows: board.iter().map(ContractRow::from).collect() },
            DbWrite::Tick { tick: 3 },
        ]});
        sqlx::query("CREATE TRIGGER checkpoint_fail BEFORE INSERT ON contracts BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END")
            .execute(&pool).await.unwrap();
        assert!(PersistenceWorker::flush_buffer(&pool, &mut buffer).await.is_err());
        assert_eq!(buffer.len(), 3);
        let balance: i64 = sqlx::query_scalar("SELECT treasury FROM factions WHERE id='issuer'")
            .fetch_one(&pool).await.unwrap();
        assert_eq!(balance, 880);
        let json: String = sqlx::query_scalar("SELECT funding_json FROM contracts")
            .fetch_one(&pool).await.unwrap();
        assert_eq!(serde_json::from_str::<serde_json::Value>(&json).unwrap()["reserved"], 120);
        assert_eq!(super::load_tick_counter(&pool).await, 1);
        sqlx::query("DROP TRIGGER checkpoint_fail").execute(&pool).await.unwrap();
        PersistenceWorker::flush_buffer(&pool, &mut buffer).await.unwrap();
        assert!(buffer.is_empty());
        let balance: i64 = sqlx::query_scalar("SELECT treasury FROM factions WHERE id='issuer'")
            .fetch_one(&pool).await.unwrap();
        let mut restored = AgentStore::new();
        crate::spawner::load_contracts(&pool, &mut restored).await.unwrap();
        assert_eq!(balance + restored.contracts.get(&id).unwrap().funding.as_ref().unwrap().reserved, 1000);
        assert_eq!(super::load_tick_counter(&pool).await, 3);
        pool.close().await;
    }

    #[tokio::test]
    async fn escrow_sqlite_roundtrip_preserves_reserved_spent_and_legacy_states() {
        let pool = crate::pool::create_pool("sqlite::memory:").await.unwrap();
        crate::pool::run_migrations(&pool).await.unwrap();
        let mut board = ContractBoard::new();
        let funded = board.post_delivery_for(
            "issuer".into(),
            None,
            Commodity::Ore,
            10,
            "source".into(),
            "port".into(),
            120,
            0,
            1000,
        );
        board.register_prepaid(&funded, FundingSource::Faction);
        board.accept(&funded, "ship".into(), 2);
        let c = board.get_mut(&funded).unwrap();
        c.renewal_count = 2;
        let mut order=sim_core::strategy::orders::Order::new("delivery",&funded);
        order.executor_id=Some("ship".into());order.attempt=2;order.state="executing".into();
        c.funding.as_mut().unwrap().station_order=Some(order);

        c.funding.as_mut().unwrap().reserved = 150;
        c.funding.as_mut().unwrap().agreed_payment = Some(150);
        let legacy = board.post_delivery_for(
            "old-issuer".into(),
            None,
            Commodity::Ore,
            10,
            "source".into(),
            "port".into(),
            120,
            0,
            1000,
        );
        PersistenceWorker::flush(
            &pool,
            vec![DbWrite::ContractBoardSnapshot {
                rows: board.iter().map(ContractRow::from).collect(),
            }],
        )
        .await
        .unwrap();
        let mut loaded = AgentStore::new();
        crate::spawner::load_contracts(&pool, &mut loaded)
            .await
            .unwrap();
        assert_eq!(
            loaded.contracts.get(&funded).unwrap().funding,
            board.get(&funded).unwrap().funding
        );
        assert_eq!(loaded.contracts.get(&funded).unwrap().renewal_count, 2);
        assert_eq!(
            loaded.contracts.get(&funded).unwrap().status,
            ContractStatus::Accepted
        );
        assert!(loaded.contracts.get(&legacy).unwrap().funding.is_none());

        loaded
            .contracts
            .cancel_for_facility(Some("issuer"), None, None);
        loaded
            .contracts
            .get_mut(&funded)
            .unwrap()
            .funding
            .as_mut()
            .unwrap()
            .reserved = 0;
        PersistenceWorker::flush(
            &pool,
            vec![DbWrite::ContractBoardSnapshot {
                rows: loaded.contracts.iter().map(ContractRow::from).collect(),
            }],
        )
        .await
        .unwrap();
        let mut restored = AgentStore::new();
        crate::spawner::load_contracts(&pool, &mut restored)
            .await
            .unwrap();
        assert_eq!(
            restored
                .contracts
                .get(&funded)
                .unwrap()
                .funding
                .as_ref()
                .unwrap()
                .reserved,
            0
        );
        assert_eq!(
            restored.contracts.get(&funded).unwrap().status,
            ContractStatus::Expired
        );
        assert!(restored.contracts.get(&legacy).unwrap().funding.is_none());
        pool.close().await;
    }
}

impl DbWrite {
    /// Dedup key — newer writes replace older ones for the same agent.
    fn key(&self) -> (&'static str, String) {
        match self {
            DbWrite::ConstructedFacility { row } => ("facility_create", row.source_site_id.clone()),
            DbWrite::ColonyPopulation { db_id, .. } => ("colony_population", db_id.to_string()),
            DbWrite::ColonyEstablished { db_id, .. } => ("colony_established", db_id.to_string()),
            DbWrite::EconomicFrame { .. } => unreachable!("frames must be unpacked before dedup"),
            DbWrite::Ship { db_id, .. } => ("ship", db_id.to_string()),
            DbWrite::Market { db_id, .. } => ("market", db_id.to_string()),
            DbWrite::Faction { id, .. } => ("faction", id.clone()),
            DbWrite::Facility { db_id, .. } => ("facility", db_id.to_string()),
            DbWrite::FacilityOrbit { db_id, .. } => ("facility_orbit", db_id.to_string()),
            DbWrite::Population { db_id, .. } => ("population", db_id.to_string()),
            DbWrite::Body { db_id, .. } => ("body", db_id.to_string()),
            DbWrite::Tick { .. } => ("tick", String::new()),
            // Delete keys use a distinct namespace so a subsequent
            // upsert in the same flush doesn't overwrite the delete
            // and resurrect the row.
            DbWrite::DeleteShip { db_id } => ("ship_delete", db_id.to_string()),
            DbWrite::DeleteFacility { db_id } => ("facility_delete", db_id.to_string()),
            DbWrite::ContractBoardSnapshot { .. } => ("contract_board", String::new()),
            DbWrite::ConstructionSiteUpsert { row } => ("site", row.agent_id.clone()),
            DbWrite::ConstructionSiteDelete { agent_id } => {
                ("site_delete", agent_id.clone())
            }
            // Retirements are append-only — every emit becomes its
            // own INSERT. Dedup-key includes the agent_id + tick so
            // multiple retirements in a single sweep don't collapse.
            DbWrite::RetireShip { row } => {
                ("retire", format!("{}-{}", row.agent_id, row.retired_at_tick))
            }
            // Phase 20d (persistent trends): keyed on (market, tick).
            // Two emits at the same (market, tick) collapse to one
            // INSERT batch. Different ticks land as separate rows
            // because the batch INSERT uses INSERT OR REPLACE keyed
            // on the table's (market_id, tick, commodity) primary key
            // — same tick re-emission overwrites cleanly.
            DbWrite::MarketTrendBatch { market_db_id, tick, .. } => {
                ("market_trend", format!("{market_db_id}:{tick}"))
            }
        }
    }
}

pub struct PersistenceWorker {
    pool: SqlitePool,
    rx: mpsc::Receiver<DbWrite>,
    /// On-demand flush requests. Admin `save-as` sends one of these
    /// before `VACUUM INTO` so the snapshot is guaranteed-current
    /// rather than up to `sweep_interval` stale.
    flush_rx: mpsc::Receiver<oneshot::Sender<()>>,
    sweep_interval: std::time::Duration,
}

impl PersistenceWorker {
    pub fn new(
        pool: SqlitePool,
        rx: mpsc::Receiver<DbWrite>,
        flush_rx: mpsc::Receiver<oneshot::Sender<()>>,
        sweep_interval: std::time::Duration,
    ) -> Self {
        Self { pool, rx, flush_rx, sweep_interval }
    }

    // No await while unpacking a frame: a sweep cannot observe half a tick.
    fn buffer_write(buffer: &mut HashMap<(&'static str, String), DbWrite>, write: DbWrite) {
        match write {
            DbWrite::EconomicFrame { writes } => {
                for write in writes { Self::buffer_write(buffer, write); }
            }
            write => { buffer.insert(write.key(), write); }
        }
    }

    async fn flush_buffer(pool: &SqlitePool, buffer: &mut HashMap<(&'static str, String), DbWrite>) -> Result<()> {
        // Keep the exact admitted state on errors. Clear only after COMMIT.
        Self::flush(pool, buffer.values().cloned().collect()).await?;
        buffer.clear();
        Ok(())
    }

    pub async fn run(mut self) {
        let mut sweep = tokio::time::interval(self.sweep_interval);
        sweep.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let mut buffer = HashMap::new();
        let mut flush_open = true;
        info!("PersistenceWorker: sweep interval {}s", self.sweep_interval.as_secs());
        loop {
            tokio::select! {
                msg = self.rx.recv() => {
                    match msg {
                        Some(write) => Self::buffer_write(&mut buffer, write),
                        None => {
                            if let Err(e) = Self::flush_buffer(&self.pool, &mut buffer).await {
                                warn!("PersistenceWorker final flush failed: {e}");
                            }
                            info!("PersistenceWorker: channel closed, exiting");
                            return;
                        }
                    }
                }
                req = self.flush_rx.recv(), if flush_open => {
                    let Some(ack) = req else { flush_open = false; continue; };
                    // The flush request uses a separate channel. Drain the writes
                    // already queued, bounded by the length at this boundary.
                    let queued = self.rx.len();
                    for _ in 0..queued {
                        if let Ok(write) = self.rx.try_recv() {
                            Self::buffer_write(&mut buffer, write);
                        }
                    }
                    match Self::flush_buffer(&self.pool, &mut buffer).await {
                        Ok(()) => { let _ = ack.send(()); }
                        // Dropping ack makes save-as fail rather than report a
                        // successful export after a failed checkpoint.
                        Err(e) => warn!("PersistenceWorker on-demand flush failed; retained for retry: {e}"),
                    }
                }
                _ = sweep.tick() => {
                    if buffer.is_empty() { continue; }
                    match Self::flush_buffer(&self.pool, &mut buffer).await {
                        Ok(()) => debug!("PersistenceWorker: committed pending writes"),
                        Err(e) => warn!("PersistenceWorker flush failed; retained for retry: {e}"),
                    }
                }
            }
        }
    }

    async fn flush(pool: &SqlitePool, mut writes: Vec<DbWrite>) -> Result<()> {
        // HashMap iteration is arbitrary. Tombstones must win over earlier
        // queued updates/upserts in this same transaction (especially sites).
        writes.sort_by_key(|write| match write {
            DbWrite::ConstructedFacility { .. } => 0,
            DbWrite::ColonyPopulation { .. } | DbWrite::ColonyEstablished { .. } => 1,
            DbWrite::DeleteShip { .. } | DbWrite::DeleteFacility { .. }
                | DbWrite::ConstructionSiteDelete { .. } => 3,
            _ => 2,
        });
        let mut tx = pool.begin().await?;

        for write in writes {
            match write {
                DbWrite::ConstructedFacility { row } => {
                    sqlx::query("INSERT INTO facilities (id, construction_site_id, name, facility_type,
                        location_id, location_name, body_id, faction_id, docking_capacity, services,
                        condition, reputation, credits, reserves, docked_ships)
                        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,
                            CASE WHEN ?4='construction_dock' THEN '[]' ELSE '[\"market\"]' END,
                            ?10,?11,?12,'{}','[]')")
                        .bind(row.db_id).bind(row.source_site_id).bind(row.name).bind(row.facility_type)
                        .bind(row.location_id).bind(row.location_name).bind(row.body_id).bind(row.faction_id)
                        .bind(row.docking_capacity as i64).bind(row.condition as f64)
                        .bind(row.reputation as i64).bind(row.credits).execute(&mut *tx).await?;
                }
                DbWrite::ColonyPopulation { db_id, label, location, faction } => {
                    sqlx::query("INSERT INTO populations (id,label,demographic,facility_id,facility_location,
                        faction_id,population_count,total_wealth,growth_rate,employed_fraction,consumption)
                        VALUES (?1,?2,'workers',?1,?3,?4,0,0,0,0,'{\"food\":1,\"water\":0.6}')")
                        .bind(db_id).bind(label).bind(location).bind(faction).execute(&mut *tx).await?;
                }
                DbWrite::ColonyEstablished { db_id, location } => {
                    sqlx::query("UPDATE facilities SET facility_type='station', services='[\"market\"]' WHERE id=?1 AND facility_type='construction_dock'")
                        .bind(db_id).execute(&mut *tx).await?;
                    sqlx::query("INSERT INTO markets (id,facility_id,facility_location) VALUES (?1,?1,?2)")
                        .bind(db_id).bind(location).execute(&mut *tx).await?;
                }
                DbWrite::EconomicFrame { .. } => anyhow::bail!("unpacked economic frame expected"),
                DbWrite::Ship {
                    db_id,
                    credits,
                    fuel,
                    position_x,
                    position_y,
                    cargo_json,
                    resume_json,
                    current_goal,
                    active_contract_id,
                    broke_strikes,
                    hoard_strikes,
                    idle_ticks,
                    fitting_json,
                    progression_json,
                } => {
                    sqlx::query(
                        "UPDATE ships SET
                           credits=?1, fuel=?2, position_x=?3, position_y=?4,
                           cargo=?5, current_goal=?6, active_contract_id=?7,
                           broke_strikes=?8, hoard_strikes=?9, idle_ticks=?10,
                           fitting=?11, progression=?12, resume_json=?14,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?13",
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
                    .bind(progression_json)
                    .bind(db_id)
                    .bind(resume_json)
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
                    fitting_json,
                    crew_state_json,
                } => {
                    sqlx::query(
                        "UPDATE facilities SET
                           credits=?1, condition=?2, reserves=?3,
                           module_stock=?4, fitting=?5, crew_state=?6,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?7",
                    )
                    .bind(credits)
                    .bind(condition as f64)
                    .bind(reserves_json)
                    .bind(module_stock_json)
                    .bind(fitting_json)
                    .bind(crew_state_json)
                    .bind(db_id)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::FacilityOrbit { db_id, orbit_angle } => {
                    sqlx::query("UPDATE facilities SET orbit_angle=?1 WHERE id=?2")
                        .bind(orbit_angle as f64)
                        .bind(db_id)
                        .execute(&mut *tx)
                        .await?;
                }
                DbWrite::Population {
                    employed_fraction,
                    db_id,
                    population_count,
                    overall_sentiment,
                    food_satisfaction,
                    total_wealth,
                } => {
                    sqlx::query(
                        "UPDATE populations SET
                           population_count=?1, overall_sentiment=?2,
                           food_satisfaction=?3, total_wealth=?4, employed_fraction=?6,
                           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                         WHERE id=?5",
                    )
                    .bind(population_count)
                    .bind(overall_sentiment as i64)
                    .bind(food_satisfaction as i64)
                    .bind(total_wealth)
                    .bind(db_id)
                    .bind(employed_fraction)
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

                DbWrite::ConstructionSiteUpsert { row } => {
                    sqlx::query(
                        "INSERT INTO construction_sites (
                             agent_id, name, facility_type, faction_id,
                             body_id, location_name, commodity,
                             progress_delivered, progress_required,
                             position_x, position_y,
                             spawned_at_tick, completed, labor_state
                         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                         ON CONFLICT(agent_id) DO UPDATE SET
                             name=excluded.name,
                             facility_type=excluded.facility_type,
                             faction_id=excluded.faction_id,
                             body_id=excluded.body_id,
                             location_name=excluded.location_name,
                             commodity=excluded.commodity,
                             progress_delivered=excluded.progress_delivered,
                             progress_required=excluded.progress_required,
                             position_x=excluded.position_x,
                             position_y=excluded.position_y,
                             completed=excluded.completed,
                             labor_state=excluded.labor_state,
                             updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
                    )
                    .bind(&row.agent_id)
                    .bind(&row.name)
                    .bind(&row.facility_type)
                    .bind(&row.faction_id)
                    .bind(&row.body_id)
                    .bind(&row.location_name)
                    .bind(&row.commodity)
                    .bind(row.progress_delivered)
                    .bind(row.progress_required)
                    .bind(row.position_x as f64)
                    .bind(row.position_y as f64)
                    .bind(row.spawned_at_tick)
                    .bind(row.completed as i64)
                    .bind(&row.labor_state)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::ConstructionSiteDelete { agent_id } => {
                    sqlx::query("DELETE FROM construction_sites WHERE agent_id = ?1")
                        .bind(&agent_id)
                        .execute(&mut *tx)
                        .await?;
                }

                DbWrite::RetireShip { row } => {
                    sqlx::query(
                        "INSERT INTO retired_ships (
                             agent_id, name, class, faction_id,
                             final_location, final_credits,
                             final_crew_morale, final_fuel_pct,
                             broke_strikes, hoard_strikes,
                             retired_at_tick, reason
                         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
                    )
                    .bind(&row.agent_id)
                    .bind(&row.name)
                    .bind(&row.class)
                    .bind(&row.faction_id)
                    .bind(&row.final_location)
                    .bind(row.final_credits)
                    .bind(row.final_crew_morale as i64)
                    .bind(row.final_fuel_pct as i64)
                    .bind(row.broke_strikes as i64)
                    .bind(row.hoard_strikes as i64)
                    .bind(row.retired_at_tick)
                    .bind(&row.reason)
                    .execute(&mut *tx)
                    .await?;
                }

                DbWrite::ContractBoardSnapshot { rows } => {
                    // Full-board replace: cheap because the board is
                    // small (hundreds of rows) and it keeps the DB in
                    // lockstep with the in-memory ContractBoard
                    // without tracking per-contract dirty bits.
                    sqlx::query("DELETE FROM contracts")
                        .execute(&mut *tx)
                        .await?;
                    for r in rows {
                        sqlx::query(
                            "INSERT INTO contracts (
                                id, contract_type, status,
                                requestor_type, requestor_id,
                                fulfiller_type, fulfiller_id,
                                commodity, quantity, quantity_remaining,
                                source_location, destination_location,
                                payment, initial_payment, funding_json, renewal_count,
                                faction_id, min_reputation, initial_min_reputation,
                                mission_category,
                                posted_at_tick, accepted_at_tick, expires_at_tick
                            ) VALUES (
                                ?1, ?2, ?3,
                                'facility', ?4,
                                CASE WHEN ?5 IS NULL THEN NULL ELSE 'ship' END, ?5,
                                ?6, ?7, ?7,
                                ?8, ?9,
                                ?10, ?11, ?19, ?20,
                                ?12, ?13, ?14,
                                ?15,
                                ?16, ?17, ?18
                            )",
                        )
                        .bind(&r.id)
                        .bind(&r.contract_type)
                        .bind(&r.status)
                        .bind(&r.requestor_id)
                        .bind(r.fulfiller_id.as_deref())
                        .bind(&r.commodity)
                        .bind(r.quantity)
                        .bind(&r.source_location)
                        .bind(&r.destination_location)
                        .bind(r.payment)
                        .bind(r.initial_payment)
                        .bind(r.faction_id.as_deref())
                        .bind(r.min_reputation)
                        .bind(r.initial_min_reputation)
                        .bind(r.mission_category.as_deref())
                        .bind(r.posted_at_tick)
                        .bind(r.accepted_at_tick)
                        .bind(r.expires_at_tick)
                        .bind(r.funding_json.as_deref())
                        .bind(r.renewal_count)
                        .execute(&mut *tx)
                        .await?;
                    }
                }

                DbWrite::MarketTrendBatch {
                    market_db_id,
                    tick,
                    entries,
                } => {
                    // INSERT OR REPLACE on the (market_id, tick,
                    // commodity) primary key — re-emission at the
                    // same tick (e.g. boot pump that ran the loop
                    // twice) overwrites without growing the table.
                    for (commodity, price, supply) in entries {
                        sqlx::query(
                            "INSERT OR REPLACE INTO market_trend_samples
                             (market_id, tick, commodity, price, supply)
                             VALUES (?1, ?2, ?3, ?4, ?5)",
                        )
                        .bind(market_db_id)
                        .bind(tick)
                        .bind(&commodity)
                        .bind(price as f64)
                        .bind(supply as f64)
                        .execute(&mut *tx)
                        .await?;
                    }
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

/// Load the world seed from `simulation_state`, or mint a fresh one
/// and persist it on first boot. Returned directly — the server sticks
/// it into [`AppState`] and exposes it via `/api/health` so clients
/// (Godot's nebula-cloud generator, etc.) can seed deterministically
/// and get the same layout every restart.
///
/// The first-boot seed is derived from system-time nanos; subsequent
/// boots round-trip through SQLite so the landmark look stays stable
/// as long as the DB lives.
pub async fn load_or_init_world_seed(pool: &SqlitePool) -> u64 {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM simulation_state WHERE key = 'world_seed'")
            .fetch_optional(pool)
            .await
            .ok()
            .flatten();
    if let Some((v,)) = row {
        if let Some(seed) = serde_json::from_str::<serde_json::Value>(&v)
            .ok()
            .and_then(|j| j.get("seed").and_then(|s| s.as_u64()))
        {
            return seed;
        }
    }
    // First boot (or corrupted row) — mint + persist.
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0xC0FFEE);
    let value = serde_json::json!({ "seed": seed }).to_string();
    let _ = sqlx::query(
        "INSERT INTO simulation_state (key, value)
         VALUES ('world_seed', ?1)
         ON CONFLICT(key) DO UPDATE SET
           value=excluded.value,
           updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')",
    )
    .bind(value)
    .execute(pool)
    .await;
    seed
}

/// Run `VACUUM INTO '<dest>'` against the pool, copying the entire
/// database to a new file. SQLite handles page locking + integrity.
/// The caller is responsible for ensuring `dest` is a safe, owned
/// path — the query interpolates it into the SQL directly because
/// VACUUM INTO doesn't support parameter binding.
pub async fn save_as(pool: &SqlitePool, dest: &str) -> Result<()> {
    let query = format!("VACUUM INTO '{dest}'");
    sqlx::query(&query).execute(pool).await?;
    Ok(())
}

/// Load the retirement ledger. Returns up to `limit` rows newest-
/// first (by tick then by insertion id). Safe to call at startup —
/// the table is written only by the persistence worker, so a
/// snapshot load can't race live writes. Clients that need a rolling
/// view should re-invoke periodically.
pub async fn load_retirements(pool: &SqlitePool, limit: i64) -> Result<Vec<RetirementRow>> {
    use sqlx::Row;
    let rows = sqlx::query(
        "SELECT agent_id, name, class, faction_id, final_location,
                final_credits, final_crew_morale, final_fuel_pct,
                broke_strikes, hoard_strikes, retired_at_tick, reason
         FROM retired_ships
         ORDER BY retired_at_tick DESC, id DESC
         LIMIT ?1",
    )
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| RetirementRow {
            agent_id: r.get::<String, _>("agent_id"),
            name: r.get::<String, _>("name"),
            class: r.get::<String, _>("class"),
            faction_id: r.get::<String, _>("faction_id"),
            final_location: r.get::<String, _>("final_location"),
            final_credits: r.get::<i64, _>("final_credits"),
            final_crew_morale: r.get::<i64, _>("final_crew_morale") as i32,
            final_fuel_pct: r.get::<i64, _>("final_fuel_pct") as i32,
            broke_strikes: r.get::<i64, _>("broke_strikes") as i32,
            hoard_strikes: r.get::<i64, _>("hoard_strikes") as i32,
            retired_at_tick: r.get::<i64, _>("retired_at_tick"),
            reason: r.get::<String, _>("reason"),
        })
        .collect())
}
