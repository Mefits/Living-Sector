mod db;
mod engine;
mod http;
mod ws;

use anyhow::Result;
use engine::{RunningFlag, TickCounter};
use sim_core::simulation::config::TickConfig;
use std::sync::{
    atomic::{AtomicBool, AtomicU64},
    Arc,
};
use tracing::info;
use tracing_subscriber::{EnvFilter, fmt};

#[tokio::main]
async fn main() -> Result<()> {
    // --- Logging ---
    // Write to stderr with an explicit filter. We don't use try_from_default_env
    // because falling back silently when RUST_LOG is malformed confuses debugging.
    // The [[bin]] name is "simulator", so events from sim_server's modules
    // appear under target "simulator::<mod>", not "sim_server::<mod>".
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("simulator=info,sim_core=info"));
    fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .init();

    info!("Simulator starting...");

    // --- Database ---
    let db_path = resolve_db_path();
    info!("DB: {db_path}");
    let pool = db::pool::create_pool(&db_path).await?;
    db::pool::run_migrations(&pool).await?;
    info!("Migrations: done");

    // --- Seed if empty ---
    if !db::seeder::is_seeded(&pool).await? {
        let data_dir = resolve_data_dir();
        info!("Seeding from {}", data_dir.display());
        db::seeder::seed_all(&pool, &data_dir).await?;
    } else {
        info!("DB already seeded — skipping");
    }

    // --- Load world ---
    let config = {
        let mut c = TickConfig::DEFAULT;
        if let Ok(ws) = std::env::var("WORLD_SPEED") {
            if let Ok(v) = ws.parse::<f32>() {
                c.world_speed = v;
                info!("WORLD_SPEED override: {v}");
            }
        }
        c
    };
    let registry = db::spawner::load_registry(&pool).await?;
    let store = db::spawner::load_agents(&pool, &registry, &config).await?;
    let registry = Arc::new(registry);

    let summary = store.summary();
    info!("World loaded: {summary}");

    // --- Engine ---
    let tick_counter: TickCounter = Arc::new(AtomicU64::new(0));
    let running: RunningFlag = Arc::new(AtomicBool::new(true));

    // Signal Godot (or any parent process watching stdout)
    println!("sim:ready ws=ws://127.0.0.1:8080/ws tick=0");

    engine::run_tick_loop(store, registry, config, tick_counter, running).await;

    Ok(())
}

fn resolve_db_path() -> String {
    // Env override → fallback to sibling of binary → fallback to ./sim.db
    std::env::var("DATABASE_PATH").unwrap_or_else(|_| {
        let exe = std::env::current_exe().ok();
        exe.and_then(|p| p.parent().map(|d| d.join("sim.db")))
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "sim.db".to_string())
    })
}

fn resolve_data_dir() -> std::path::PathBuf {
    // Env override → sibling priv/data → cargo workspace priv/data
    if let Ok(path) = std::env::var("DATA_DIR") {
        return std::path::PathBuf::from(path);
    }
    // Try next to the binary (release layout)
    if let Ok(exe) = std::env::current_exe() {
        let candidate = exe
            .parent()
            .unwrap_or(&exe)
            .join("priv")
            .join("data");
        if candidate.exists() {
            return candidate;
        }
    }
    // Dev layout: cargo workspace root's priv/data
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("priv")
        .join("data")
}
