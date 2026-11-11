use super::*;
use serde_json::Value;
use sim_core::agents::{
    construction::ConstructionSite,
    population::{PopDemographics, PopEconomy},
};
use sim_db::{
    persistence::{load_tick_counter, PersistenceWorker},
    pool, seeder, spawner,
};
use std::{path::Path, sync::RwLock};

const GENESIS: TickConfig = TickConfig {
    ticks_per_second: 8,
    world_speed: 1.0,
};
const LIMIT: u64 = 10_000;

async fn run_until(
    pool: &sqlx::SqlitePool,
    end_tick: u64,
    stop_event: Option<&str>,
) -> (Vec<(u64, Value)>, Arc<SnapshotCache>) {
    let timing = if std::env::var("LIVING_SECTOR_GALAXY").as_deref() == Ok("1") {
        TickConfig { ticks_per_second: 16, world_speed: 16.0 }
    } else { GENESIS };
    let registry = Arc::new(spawner::load_registry(pool).await.unwrap());
    let mut world = World::new();
    let mut store = spawner::load_agents(&mut world, pool, &registry, &timing)
        .await
        .unwrap();
    crate::runtime::initialize_faction_relations(&mut world, &mut store);
    run_contract_pump(&mut world, &mut store, 5);

    let snapshots = SnapshotCache::new();
    let (events, mut receiver) = broadcast::channel::<Arc<ServerMsg>>(1024);
    let collect_events = tokio::spawn(async move {
        let mut observed = Vec::new();
        loop {
            match receiver.recv().await {
                Ok(message) => {
                    if let ServerMsg::Events { tick, events } = message.as_ref() {
                        observed.extend(events.iter().cloned().map(|event| (*tick, event)));
                    }
                }
                Err(broadcast::error::RecvError::Closed) => break,
                Err(error) => panic!("lost engine events: {error}"),
            }
        }
        observed
    });
    let (_control, control_rx) = mpsc::channel(1);
    let (persist, persist_rx) = mpsc::channel(1024);
    let (_flush, flush_rx) = mpsc::channel(1);
    let worker = tokio::spawn(
        PersistenceWorker::new(pool.clone(), persist_rx, flush_rx, Duration::from_secs(300)).run(),
    );
    let tick = Arc::new(AtomicU64::new(load_tick_counter(pool).await));
    run_tick_loop(
        world,
        store,
        registry,
        timing,
        tick.clone(),
        Arc::new(AtomicBool::new(true)),
        snapshots.clone(),
        Default::default(),
        Default::default(),
        Default::default(),
        Default::default(),
        Default::default(),
        Arc::new(RwLock::new(Default::default())),
        Default::default(),
        Default::default(),
        events,
        control_rx,
        persist,
        pool.clone(),
        Default::default(),
        Some((end_tick, stop_event)),
    )
    .await;
    worker.await.unwrap();
    let last_tick = tick.load(Ordering::Relaxed);
    if stop_event.is_none() {
        assert_eq!(last_tick, end_tick);
    }
    assert_eq!(
        load_tick_counter(pool).await,
        last_tick,
        "final economic checkpoint"
    );
    (collect_events.await.unwrap(), snapshots)
}

fn for_location<'a>(
    events: &'a [(u64, Value)],
    kind: &str,
    field: &str,
    location: &str,
) -> Vec<(u64, &'a Value)> {
    events
        .iter()
        .filter(|(_, event)| event["kind"] == kind && event[field] == location)
        .map(|(tick, event)| (*tick, event))
        .collect()
}

async fn scalar(pool: &sqlx::SqlitePool, query: &str) -> i64 {
    sqlx::query_scalar(query).fetch_one(pool).await.unwrap()
}

async fn credits(pool: &sqlx::SqlitePool) -> i64 {
    scalar(pool, "SELECT
        (SELECT coalesce(sum(treasury),0) FROM factions)
        + (SELECT coalesce(sum(credits),0) FROM facilities)
        + (SELECT coalesce(sum(total_wealth),0) FROM populations)
        + (SELECT coalesce(sum(credits + coalesce(json_extract(resume_json,'$.crew_savings'),0)),0) FROM ships)
        + (SELECT coalesce(sum(coalesce(json_extract(funding_json,'$.reserved'),0)
            + coalesce(json_extract(funding_json,'$.embarked.wealth'),0)),0) FROM contracts)").await
}

async fn verify_scenario(data: &Path, expected_body: &str, alternate: bool) {
    let path = std::env::temp_dir().join(format!(
        "living-sector-colony-{}.sqlite",
        uuid::Uuid::new_v4()
    ));
    struct Cleanup(std::path::PathBuf);
    impl Drop for Cleanup {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }
    let _cleanup = Cleanup(path.clone());
    let pool = pool::create_pool(path.to_str().unwrap()).await.unwrap();
    pool::run_migrations(&pool).await.unwrap();
    seeder::seed_all(&pool, data).await.unwrap();
    if alternate {
        // Alternate world at seed time: remove Mars as a candidate and
        // make the existing Venus body viable. No intervention after tick 0.
        sqlx::query("UPDATE celestial_bodies SET resources=json_remove(resources,'$.ice') WHERE body_id='mars'")
            .execute(&pool).await.unwrap();
        sqlx::query("UPDATE celestial_bodies SET resources=json_set(resources,'$.ore',0.6,'$.ice',0.6) WHERE body_id='venus'")
            .execute(&pool).await.unwrap();
    }
    spawner::chart_colony_routes(&pool).await.unwrap();
    let location = format!("{expected_body}-colony");
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM facilities WHERE body_id=?")
            .bind(expected_body)
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    assert_eq!(
        scalar(&pool, "SELECT count(*) FROM construction_sites").await,
        0
    );
    let population = scalar(&pool, "SELECT sum(population_count) FROM populations").await;
    let initial_credits = credits(&pool).await;
    let ship_ids: Vec<i64> = sqlx::query_scalar("SELECT id FROM ships ORDER BY id")
        .fetch_all(&pool)
        .await
        .unwrap();

    let (mut events, pool) = if alternate {
        let (events, _) = run_until(&pool, LIMIT, Some("passengers_embarked")).await;
        assert!(events
            .iter()
            .any(|(_, e)| e["kind"] == "passengers_embarked"));
        assert_eq!(
            scalar(&pool, "SELECT sum(population_count) FROM populations").await,
            population - 10
        );
        assert_eq!(
            scalar(
                &pool,
                "SELECT count(*) FROM contracts WHERE status='picked_up'
            AND json_extract(funding_json,'$.embarked.origin_population') IS NOT NULL"
            )
            .await,
            1
        );
        assert_eq!(
            credits(&pool).await,
            initial_credits,
            "onboard savings remain part of the ledger"
        );
        pool.close().await;
        let reopened = pool::create_pool(path.to_str().unwrap()).await.unwrap();
        (events, reopened)
    } else {
        (Vec::new(), pool)
    };
    let (tail, snapshots) = run_until(&pool, LIMIT, None).await;
    events.extend(tail);
    let approved = for_location(&events, "colony_approved", "destination", &location);
    let sites = for_location(&events, "construction_site_started", "location", &location);
    let completed = for_location(&events, "construction_completed", "location", &location);
    let arrivals = for_location(&events, "passengers_arrived", "destination", &location);
    let deliveries = for_location(&events, "contract_delivered", "destination", &location);
    if completed.is_empty() {
        let strategy = serde_json::to_value(&*snapshots.strategy.read().unwrap()).unwrap();
        let relevant: Vec<_> = events
            .iter()
            .filter(|(_, e)| {
                e["destination"] == location
                    || e["location"] == location
                    || e["kind"] == "passengers_embarked"
            })
            .collect();
        panic!(
            "{location} stalled: {:?}\nrelevant events: {relevant:?}\nhead: {}",
            snapshots.construction_sites.get(&format!(
                "site-station-{location}-{}",
                approved.first().map_or(0, |e| e.0)
            )),
            strategy["factions"]
        );
    }
    assert_eq!(
        (approved.len(), sites.len(), arrivals.len(), completed.len()),
        (1, 1, 1, 1)
    );
    let (decision_tick, approval) = approved[0];
    let (site_tick, site) = sites[0];
    let (completion_tick, completion) = completed[0];
    assert_eq!(approval["faction_id"], "terran-authority");
    assert_eq!(completion["body_id"], expected_body);
    assert_eq!(completion["facility_type"], "station");
    assert!(decision_tick <= site_tick && site_tick < completion_tick && completion_tick <= LIMIT);
    let embarked = events
        .iter()
        .find(|(_, e)| {
            e["kind"] == "passengers_embarked" && e["contract_id"] == arrivals[0].1["contract_id"]
        })
        .expect("physical boarding");
    assert!(
        site_tick < embarked.0 && embarked.0 < arrivals[0].0 && arrivals[0].0 < completion_tick
    );
    assert_eq!(embarked.1["ship_id"], arrivals[0].1["ship_id"]);
    assert_eq!(embarked.1["wealth"], arrivals[0].1["wealth"]);
    assert_eq!(embarked.1["head_count"], 10);

    let mut goods = 0;
    let mut freight = 0;
    let mut purchase = 0;
    for (_, delivery) in deliveries
        .iter()
        .filter(|(_, e)| e["contract_type"] == "construction")
    {
        let bought = events
            .iter()
            .find(|(_, e)| {
                e["kind"] == "ship_transaction_applied"
                    && e["operation"] == "buy"
                    && e["commodity"] == "metals"
                    && e["contract_id"] == delivery["contract_id"]
                    && e["ship_id"] == delivery["ship_id"]
            })
            .expect("physical market purchase before delivery");
        assert_eq!(bought.1["location"], delivery["source"]);
        assert_eq!(bought.1["requested_quantity"], delivery["quantity"]);
        purchase += bought.1["payment"].as_i64().unwrap();
        goods += delivery["quantity"].as_u64().unwrap();
        freight += delivery["payment"].as_i64().unwrap();
    }
    let shifts: Vec<_> = events
        .iter()
        .filter(|(_, e)| e["kind"] == "construction_labor" && e["site_id"] == site["site_id"])
        .collect();
    let work: u64 = shifts
        .iter()
        .map(|(_, e)| e["workers"].as_u64().unwrap())
        .sum();
    let wages: i64 = shifts
        .iter()
        .map(|(_, e)| e["wages"].as_i64().unwrap())
        .sum();
    assert_eq!((goods, work, wages, freight), (600, 150, 150, 30_000));
    assert!(purchase > 0);
    assert!(shifts.iter().all(|(_, e)| e["executor"].is_string()));
    assert_eq!(shifts.last().unwrap().1["executor"], completion["executor"]);

    let operator =
        snapshots.strategy.read().unwrap().stations.iter().any(|s| {
            s.faction_id == "terran-authority" && s.location == location && s.workforce > 0
        });
    assert!(
        operator,
        "new colony must enter normal station administration"
    );
    let final_ships: Vec<i64> = sqlx::query_scalar("SELECT id FROM ships ORDER BY id")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(final_ships, ship_ids);
    assert_eq!(
        credits(&pool).await,
        initial_credits,
        "world cash, crew savings and funded escrow"
    );
    assert_eq!(
        scalar(&pool, "SELECT sum(population_count) FROM populations").await,
        population
    );

    pool.close().await;
    let pool = pool::create_pool(path.to_str().unwrap()).await.unwrap();
    assert_eq!(credits(&pool).await, initial_credits);
    let registry = spawner::load_registry(&pool).await.unwrap();
    let mut world = World::new();
    let store = spawner::load_agents(&mut world, &pool, &registry, &GENESIS)
        .await
        .unwrap();
    let facilities = &store.facilities_at_location[&location];
    assert_eq!(facilities.len(), 1);
    let station = world
        .get::<sim_core::agents::facility::FacilityIdentity>(facilities[0])
        .unwrap();
    assert_eq!(
        (
            station.facility_type.as_str(),
            station.body_id.as_str(),
            station.faction_id.as_str()
        ),
        ("station", expected_body, "terran-authority")
    );
    assert!(store.market_at_location.contains_key(&location));
    let residents = store.population_by_id[&format!("pop-residents-{location}")];
    assert_eq!(
        world
            .get::<PopDemographics>(residents)
            .unwrap()
            .population_count,
        10
    );
    assert!(world.get::<PopEconomy>(residents).unwrap().total_wealth >= 0);
    assert!(!world
        .query::<&ConstructionSite>()
        .iter(&world)
        .any(|s| s.location_name == location));
    println!("C1 {location}: decision {decision_tick}, site {site_tick}, embark {}, arrival {}, final delivery {}, builder {}, {} paid shifts ({} CR), material purchases {} CR, freight {} CR, passage {} CR, startup capital {} CR, completed {completion_tick}; SQLite restart verified",
        embarked.0, arrivals[0].0, deliveries.last().unwrap().0, completion["executor"], work, wages,
        purchase, freight, arrivals[0].1["payment"], completion["startup_capital"]);
    pool.close().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn autonomous_colonization_and_restart() {
    bevy_tasks::ComputeTaskPool::get_or_init(|| {
        bevy_tasks::TaskPoolBuilder::new().num_threads(2).build()
    });
    let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../priv/genesis/data");
    sim_core::simulation::tuning::WorldTuning::set(
        serde_json::from_slice(&std::fs::read(data.join("tuning.json")).unwrap()).unwrap(),
    );
    verify_scenario(&data, "mars", false).await;
    verify_scenario(&data, "venus", true).await;
}

/// Real engine, paid native actions, no teleport fixtures. Run alone with GALAXY=1.
#[tokio::test]
#[ignore = "run in isolation with LIVING_SECTOR_GALAXY=1"]
async fn galaxy_live_autonomy_and_resume() {
    assert_eq!(std::env::var("LIVING_SECTOR_GALAXY").as_deref(),Ok("1"));
    let path=std::env::temp_dir().join(format!("ls-galaxy-{}.db",uuid::Uuid::new_v4()));
    let pool=pool::create_pool(path.to_str().unwrap()).await.unwrap();
    pool::run_migrations(&pool).await.unwrap();
    let data=Path::new(env!("CARGO_MANIFEST_DIR")).join("../../priv/galaxy/data");
    seeder::seed_all(&pool,&data).await.unwrap();
    spawner::chart_colony_routes(&pool).await.unwrap();
    let (events,snap)=run_until(&pool,6000,None).await;
    let first=snap.strategy.read().unwrap().clone();
    if let Ok(path) = std::env::var("LS_EVENT_TRACE") { std::fs::write(path, serde_json::to_vec(&events).unwrap()).unwrap(); }
    let counts:std::collections::BTreeMap<_,_>=events.iter().fold(std::collections::BTreeMap::<String,usize>::new(),|mut m,(_,e)|{*m.entry(e["kind"].as_str().unwrap_or("unknown").to_owned()).or_default()+=1;m});
    let colony_meals=events.iter().filter(|(_,e)|e["kind"]=="population_purchase"&&e["population_id"].as_str().is_some_and(|id|id.contains("colony"))&&e["quantity"].as_f64().unwrap_or(0.0)>0.0).count();
    let completed_sites: Vec<_> = events.iter().filter(|(_, event)| event["kind"] == "construction_completed")
        .map(|(tick, event)| serde_json::json!({"tick":tick,"type":event["facility_type"],"location":event["location"],"faction":event["faction_id"]})).collect();
    println!("COLONY_MEALS {colony_meals}");
    println!("GALAXY_EVENTS {}",serde_json::to_string(&counts).unwrap());
    for (id, commander) in &first.commanders { println!("{id}: {} technologies, {} completed colonies", commander.technologies.len(), commander.colonies); }
    if let Ok(output)=std::env::var("LS_REPORT_PATH") {std::fs::write(output,serde_json::to_vec_pretty(&serde_json::json!({"tick":6000,"events":counts,"colony_meals":colony_meals,"completed_sites":completed_sites,"strategy":first})).unwrap()).unwrap();}
    assert_eq!(first.commanders.len(),3);
    assert!(colony_meals>0,"a new colony must receive and consume real provisions");
    assert!(first.commanders.values().all(|c|!c.technologies.is_empty()),"every faction must research");
    assert!(first.commanders.values().any(|c|c.colonies>0),"must actually finish a colony");
    assert!(first.commanders.values().any(|c|c.completed_contracts>0),"must fulfill native contracts");
    let saved: String=sqlx::query_scalar("SELECT value FROM simulation_state WHERE key='galaxy_director_v1'").fetch_one(&pool).await.unwrap();
    let checkpoint:sim_core::strategy::director::Director=serde_json::from_str(&saved).unwrap();
    for (id,c) in &first.commanders {assert_eq!(checkpoint.commanders[id].technologies,c.technologies);}
    let (after_restart, resumed)=run_until(&pool,9000,None).await;
    let completed_after_restart: Vec<_> = after_restart.iter().filter(|(_, event)| event["kind"] == "construction_completed")
        .map(|(tick, event)| serde_json::json!({"tick":tick,"type":event["facility_type"],"location":event["location"],"faction":event["faction_id"]})).collect();
    println!("COMPLETED_AFTER_RESTART {}", serde_json::to_string(&completed_after_restart).unwrap());
    if let Ok(output)=std::env::var("LS_REPORT_PATH") {
        let mut report: Value = serde_json::from_slice(&std::fs::read(&output).unwrap()).unwrap();
        report["resumed_tick"] = 9000.into();
        report["completed_after_restart"] = serde_json::json!(completed_after_restart);
        report["resumed_strategy"] = serde_json::to_value(&*resumed.strategy.read().unwrap()).unwrap();
        std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap()).unwrap();
    }
    for (id,c) in &first.commanders {let state=resumed.strategy.read().unwrap();assert!(c.technologies.iter().all(|t|state.commanders[id].technologies.contains(t)));}
    pool.close().await;let _=std::fs::remove_file(path);
}
