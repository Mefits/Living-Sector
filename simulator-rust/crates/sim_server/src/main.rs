//! `simulator` binary — boots the sim, runs the tick loop, serves HTTP + WS.
//!
//! ## Startup sequence
//! 1. Initialize tracing with `RUST_LOG` filter (stderr)
//! 2. Open SQLite pool (WAL, single writer) and run migrations
//! 3. Seed DB from `priv/data/*.json` if empty (idempotent upserts)
//! 4. Load `WorldRegistry` and `AgentStore` from DB
//! 5. Spawn `engine::run_tick_loop` and `axum::serve` as sibling tokio tasks
//! 6. Print `sim:ready ws=... http=...` to stdout so Godot can connect
//! 7. Wait for SIGINT/SIGTERM; on signal, flip the running flag and let the
//!    tick loop settle before exiting
//!
//! ## Env vars
//! - `RUST_LOG` — tracing filter (default: `simulator=info,sim_core=info`)
//! - `WORLD_SPEED` — game-time multiplier (default 0.25; `4.0` for demos)
//! - `BIND_ADDR` — HTTP/WS bind (default `127.0.0.1:8080`)
//! - `DATABASE_PATH` — SQLite path (default next to binary)
//! - `DATA_DIR` — world JSON root (default auto-resolves to dev or release path)
//! - `SPACESIM_PARENT_PID` — when set, the sim polls this PID every 2s and
//!   initiates a graceful shutdown if it's gone. Set by Godot's
//!   `server_manager.gd` so the sim doesn't outlive a crashing client.
//!   Absent when running via `cargo run` directly — watcher no-ops.

mod app_state;
mod control;
mod db;
mod engine;
mod http;
mod snapshot;
mod ws;

use anyhow::Result;
use app_state::AppState;
use axum::{
    routing::{get, post},
    Router,
};
use control::ControlCommand;
use engine::{RunningFlag, TickCounter};
use sim_core::simulation::config::TickConfig;
use snapshot::SnapshotCache;
use std::sync::{
    atomic::{AtomicBool, AtomicU32, AtomicU64},
    Arc,
};
use std::io::Write;
use tokio::sync::{broadcast, mpsc};
use tracing::info;
use tracing_subscriber::{fmt, EnvFilter};

#[tokio::main]
async fn main() -> Result<()> {
    // Logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("simulator=info,sim_core=info,tower_http=warn"));
    fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .init();

    info!("Simulator starting...");

    // Database
    let db_path = resolve_db_path();
    info!("DB: {db_path}");
    let pool = db::pool::create_pool(&db_path).await?;
    db::pool::run_migrations(&pool).await?;
    info!("Migrations: done");

    if !db::seeder::is_seeded(&pool).await? {
        let data_dir = resolve_data_dir();
        info!("Seeding from {}", data_dir.display());
        db::seeder::seed_all(&pool, &data_dir).await?;
    } else {
        info!("DB already seeded — skipping");
    }

    // Config
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

    // Load world
    let registry = db::spawner::load_registry(&pool).await?;
    let mut store = db::spawner::load_agents(&pool, &registry, &config).await?;
    // Pump the contract board on a fresh seed so the first client to
    // connect isn't looking at an empty ledger. No-op when the board
    // was hydrated from DB by the loader.
    engine::run_contract_pump(&mut store, 5);
    let registry = Arc::new(registry);

    let summary = store.summary();
    info!("World loaded: {summary}");
    let agent_count_initial = (summary.ships
        + summary.markets
        + summary.facilities
        + summary.populations
        + summary.factions
        + summary.bodies) as u64;

    // Shared state
    let snapshots = SnapshotCache::new();
    let tick_counter: TickCounter = Arc::new(AtomicU64::new(0));
    let running: RunningFlag = Arc::new(AtomicBool::new(true));
    let interval_ms = Arc::new(AtomicU64::new(config.tick_interval_ms()));
    let ticks_per_second = Arc::new(AtomicU32::new(config.ticks_per_second));
    let world_speed_bits = Arc::new(AtomicU32::new(config.world_speed.to_bits()));
    let agent_count = Arc::new(AtomicU64::new(agent_count_initial));
    let tick_compute_p50_us = Arc::new(AtomicU64::new(0));
    let tick_compute_p99_us = Arc::new(AtomicU64::new(0));
    let observers: Arc<std::sync::RwLock<Vec<app_state::Observer>>> =
        Arc::new(std::sync::RwLock::new(Vec::new()));
    let lod_d1 = Arc::new(AtomicU64::new(0));
    let lod_d2 = Arc::new(AtomicU64::new(0));
    let lod_d5 = Arc::new(AtomicU64::new(0));
    let lod_d10 = Arc::new(AtomicU64::new(0));
    let lod_d20 = Arc::new(AtomicU64::new(0));
    let lod_d50 = Arc::new(AtomicU64::new(0));

    let (broadcast_tx, _) = broadcast::channel(64);
    let (control_tx, control_rx) = mpsc::channel::<ControlCommand>(64);
    let (persist_tx, persist_rx) = mpsc::channel::<db::persistence::DbWrite>(4096);
    let (persist_flush_tx, persist_flush_rx) =
        mpsc::channel::<tokio::sync::oneshot::Sender<()>>(8);

    let app_state = AppState {
        snapshots: snapshots.clone(),
        registry: registry.clone(),
        tick: tick_counter.clone(),
        running: running.clone(),
        interval_ms: interval_ms.clone(),
        ticks_per_second: ticks_per_second.clone(),
        world_speed_bits: world_speed_bits.clone(),
        agent_count: agent_count.clone(),
        broadcast_tx: broadcast_tx.clone(),
        control_tx: control_tx.clone(),
        persist_flush_tx: persist_flush_tx.clone(),
        db_path: Some(db_path.clone()),
        db_pool: Arc::new(pool.clone()),
        tick_compute_p50_us: tick_compute_p50_us.clone(),
        tick_compute_p99_us: tick_compute_p99_us.clone(),
        observers: observers.clone(),
        lod_d1: lod_d1.clone(),
        lod_d2: lod_d2.clone(),
        lod_d5: lod_d5.clone(),
        lod_d10: lod_d10.clone(),
        lod_d20: lod_d20.clone(),
        lod_d50: lod_d50.clone(),
    };

    // HTTP + WS server
    let addr: std::net::SocketAddr = std::env::var("BIND_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:8080".into())
        .parse()?;
    let app = build_router(app_state.clone());

    let server_handle = tokio::spawn(async move {
        let listener = tokio::net::TcpListener::bind(addr).await.expect("bind failed");
        info!("HTTP+WS listening on http://{addr}");
        axum::serve(listener, app).await.expect("server error");
    });

    // Resume tick counter from DB if available
    let resumed_tick = db::persistence::load_tick_counter(&pool).await;
    if resumed_tick > 0 {
        info!("Resuming from persisted tick={resumed_tick}");
        tick_counter.store(resumed_tick, std::sync::atomic::Ordering::Relaxed);
    }

    // Persistence worker
    let persist_handle = {
        let pool = pool.clone();
        tokio::spawn(async move {
            db::persistence::PersistenceWorker::new(
                pool,
                persist_rx,
                persist_flush_rx,
                std::time::Duration::from_secs(5),
            )
            .run()
            .await;
        })
    };

    // Tick loop in its own task
    let tick_handle = {
        let snapshots = snapshots.clone();
        let tick_counter = tick_counter.clone();
        let running = running.clone();
        let interval_ms = interval_ms.clone();
        let ticks_per_second = ticks_per_second.clone();
        let world_speed_bits = world_speed_bits.clone();
        let tick_compute_p50_us = tick_compute_p50_us.clone();
        let tick_compute_p99_us = tick_compute_p99_us.clone();
        let observers = observers.clone();
        let lod_counters = (
            lod_d1.clone(),
            lod_d2.clone(),
            lod_d5.clone(),
            lod_d10.clone(),
            lod_d20.clone(),
            lod_d50.clone(),
        );
        let broadcast_tx = broadcast_tx.clone();
        tokio::spawn(async move {
            engine::run_tick_loop(
                store,
                registry,
                config,
                tick_counter,
                running,
                snapshots,
                interval_ms,
                ticks_per_second,
                world_speed_bits,
                tick_compute_p50_us,
                tick_compute_p99_us,
                observers,
                lod_counters,
                broadcast_tx,
                control_rx,
                persist_tx,
            )
            .await;
        })
    };

    // Not `println!`: when Godot spawns the sim via `OS.create_process`
    // on Windows, the child inherits Godot's (GUI-app, console-less) stdio
    // handles. `println!` panics on write failure and would kill the sim
    // before it can bind. `writeln!` returns a Result we can discard.
    let _ = writeln!(
        std::io::stdout(),
        "sim:ready ws=ws://{addr}/ws http=http://{addr}/api tick=0"
    );

    // Arm the parent-process watcher when the client tells us who the
    // parent is. Emits a notification if the parent disappears so the
    // main select! can shut down the same way a SIGTERM would.
    let parent_gone = std::sync::Arc::new(tokio::sync::Notify::new());
    spawn_parent_watcher(parent_gone.clone());

    // Graceful shutdown: wait for SIGINT / SIGTERM, parent-dead, or any
    // handle to finish. Stop the tick loop, let the current tick
    // complete, then exit cleanly.
    tokio::select! {
        r = server_handle => { info!("HTTP server ended: {:?}", r); }
        r = tick_handle => { info!("Tick loop ended: {:?}", r); }
        r = persist_handle => { info!("Persistence worker ended: {:?}", r); }
        _ = shutdown_signal() => {
            info!("Shutdown signal received — stopping tick loop");
            running.store(false, std::sync::atomic::Ordering::Relaxed);
            // Give the tick loop + persistence worker up to 1s for final flush
            tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
            info!("Final tick: {}", tick_counter.load(std::sync::atomic::Ordering::Relaxed));
            info!("Shutdown complete.");
        }
        _ = parent_gone.notified() => {
            info!("Parent process exited — stopping tick loop");
            running.store(false, std::sync::atomic::Ordering::Relaxed);
            tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
            info!("Final tick: {}", tick_counter.load(std::sync::atomic::Ordering::Relaxed));
            info!("Shutdown complete (parent gone).");
        }
    }
    Ok(())
}

/// Watchdog: poll `SPACESIM_PARENT_PID` every 2s; fire the notifier
/// when the parent is gone so main can run the same graceful-exit path
/// as a SIGTERM.
///
/// Behavior matrix:
/// - env var unset → no task spawned (plain `cargo run` unaffected)
/// - env var set + parent alive → poll quietly forever
/// - env var set + parent gone → one-shot notify, task exits
///
/// POSIX uses `kill(pid, 0)` which costs ~a syscall and distinguishes
/// ESRCH (dead) from EPERM (alive, just not ours to signal). Windows
/// is a no-op for now — Godot on Windows should ideally use a Job
/// Object at spawn to auto-kill children rather than rely on polling.
fn spawn_parent_watcher(parent_gone: std::sync::Arc<tokio::sync::Notify>) {
    let Ok(ppid_str) = std::env::var("SPACESIM_PARENT_PID") else {
        return;
    };
    let Ok(ppid) = ppid_str.parse::<i32>() else {
        tracing::warn!(
            value = %ppid_str,
            "SPACESIM_PARENT_PID not a valid pid — watcher disabled"
        );
        return;
    };
    if ppid <= 0 {
        return;
    }
    info!("Parent watcher armed: ppid={ppid}");
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            interval.tick().await;
            if !parent_alive(ppid) {
                tracing::warn!(ppid, "parent process is gone — initiating shutdown");
                parent_gone.notify_one();
                break;
            }
        }
    });
}

/// `kill(pid, 0)` probes process existence + signaling permission.
/// Returns true if the parent is still running (success OR EPERM —
/// meaning the process exists but we'd lack permission to signal it,
/// which is not a "gone" outcome).
#[cfg(unix)]
fn parent_alive(pid: i32) -> bool {
    unsafe {
        if libc::kill(pid, 0) == 0 {
            return true;
        }
        // errno == EPERM → the process exists, we just can't signal it
        // (different uid). Still counts as alive from our POV.
        std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
    }
}

/// Windows equivalent: open the process with minimal query rights,
/// check exit code, close handle. Treats an OpenProcess failure as
/// "parent is gone" (most common cause: process exited, pid recycled
/// or slot freed). Clean exit code (non-STILL_ACTIVE) also means
/// gone.
#[cfg(windows)]
fn parent_alive(pid: i32) -> bool {
    use windows_sys::Win32::Foundation::{CloseHandle, STILL_ACTIVE};
    use windows_sys::Win32::System::Threading::{
        GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    if pid <= 0 {
        return false;
    }
    unsafe {
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid as u32);
        // windows-sys 0.52: HANDLE is `isize`, NULL == 0. Docs: OpenProcess
        // returns NULL on failure (pid reaped, slot freed, access denied).
        if handle == 0 {
            // Can't open → probably exited (ERROR_INVALID_PARAMETER on a
            // reaped pid is the usual outcome). Treat as gone.
            return false;
        }
        let mut code: u32 = 0;
        let ok = GetExitCodeProcess(handle, &mut code) != 0;
        CloseHandle(handle);
        // STILL_ACTIVE (259) means the process is running. Any other
        // exit code means it already terminated and the OS is just
        // keeping the handle around. A GetExitCodeProcess failure is
        // treated as "assume alive" to avoid false shutdowns.
        if ok { code == STILL_ACTIVE as u32 } else { true }
    }
}

#[cfg(not(any(unix, windows)))]
fn parent_alive(_pid: i32) -> bool {
    // Any other platform: watcher stays armed but always reports
    // "alive" — better than false shutdowns. POSIX covers macOS and
    // Linux; Windows has its own branch above. Fallback is unlikely
    // to fire in practice.
    true
}

/// Wait for SIGINT (Ctrl-C) on Unix/Windows, or SIGTERM on Unix.
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl-C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        use tokio::signal::unix::{signal, SignalKind};
        signal(SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

fn build_router(state: AppState) -> Router {
    use axum::routing::delete;
    use http::{admin, api};
    use tower_http::cors::{Any, CorsLayer};

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/ws", get(ws::handler::ws_upgrade))
        .route("/api/health", get(api::health))
        .route("/api/report", get(api::report))
        .route("/api/ships", get(api::ships))
        .route("/api/markets", get(api::markets))
        .route("/api/facilities", get(api::facilities))
        .route("/api/construction_sites", get(api::construction_sites))
        .route("/api/retirements", get(api::retirements))
        .route("/api/populations", get(api::populations))
        .route("/api/factions", get(api::factions))
        .route("/api/positions", get(api::positions))
        .route("/api/contracts", get(api::contracts))
        .route("/api/observers", get(api::observers))
        .route("/api/agent/{id}", get(api::agent_by_id))
        .route("/api/sim/pause", post(api::sim_pause))
        .route("/api/sim/resume", post(api::sim_resume))
        .route("/api/sim/speed", post(api::sim_speed))
        .route("/api/sim/step", post(api::sim_step))
        // Phase 11g: admin (god-mode) endpoints.
        .route("/api/admin/ships", post(admin::create_ship))
        .route("/api/admin/ships/{id}", delete(admin::destroy_ship))
        .route("/api/admin/ships/{id}/refit", post(admin::refit_ship))
        .route("/api/admin/ships/{id}/grant-xp", post(admin::grant_ship_xp))
        .route("/api/admin/facilities", post(admin::create_facility))
        .route("/api/admin/facilities/{id}", delete(admin::destroy_facility))
        .route("/api/admin/facilities/{id}/refit", post(admin::refit_facility))
        .route(
            "/api/admin/markets/{location}/supply",
            post(admin::market_supply_delta),
        )
        .route("/api/admin/save", post(admin::save))
        .route("/api/admin/save-as", post(admin::save_as))
        .with_state(state)
        .layer(cors)
}

fn resolve_db_path() -> String {
    std::env::var("DATABASE_PATH").unwrap_or_else(|_| {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("sim.db")))
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "sim.db".to_string())
    })
}

fn resolve_data_dir() -> std::path::PathBuf {
    if let Ok(path) = std::env::var("DATA_DIR") {
        return std::path::PathBuf::from(path);
    }
    if let Ok(exe) = std::env::current_exe() {
        let candidate = exe.parent().unwrap_or(&exe).join("priv").join("data");
        if candidate.exists() {
            return candidate;
        }
    }
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("priv")
        .join("data")
}
