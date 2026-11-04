mod conflict;
mod construction;
mod freight;
mod governance;
mod industry;
mod legacy_freight;
mod planning;
mod sim;
mod view;

use axum::{
    Json, Router,
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode, header},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sim::Sim;
use std::{
    collections::VecDeque,
    env, fs,
    io::{self, Write},
    net::Ipv4Addr,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use tokio::{
    net::TcpListener,
    sync::{Mutex, broadcast},
    time::MissedTickBehavior,
};

const LOG_LIMIT: usize = 400;
const STEP: Duration = Duration::from_millis(250);
type Shared = Arc<Mutex<Engine>>;

struct Engine {
    sim: Sim,
    running: bool,
    speed: f64,
    save: PathBuf,
    updates: broadcast::Sender<String>,
    save_error: Option<String>,
    history: VecDeque<Value>,
}

impl Engine {
    fn health(&self) -> Value {
        json!({"running": self.running, "tick": self.sim.tick, "world_speed": self.speed,
            "save_error": self.save_error})
    }

    fn step(&mut self) {
        if !self.running {
            return;
        }
        let mut next = self.sim.clone();
        let events = next.step(STEP.as_secs_f64() * self.speed);
        let mut entries = Vec::new();
        for event in &events {
            entries.push(log_entry(&next, "simulation", event));
        }
        let previous = (
            self.sim
                .fleet
                .ships
                .values()
                .filter(|ship| ship.leg.is_some())
                .count(),
            self.sim.smelting_status(),
            self.sim.delivery_status(),
        );
        if previous
            != (
                next.fleet
                    .ships
                    .values()
                    .filter(|ship| ship.leg.is_some())
                    .count(),
                next.smelting_status(),
                next.delivery_status(),
            )
        {
            entries.push(log_entry(
                &next,
                "operations",
                json!({
                    "ships_in_transit": next.fleet.ships.values().filter(|ship| ship.leg.is_some()).count(),
                    "delivery": next.delivery_status(),
                    "smelting": next.smelting_status(),
                    "station_fuel": next.station_fuel(),
                    "belt_fuel": next.belt_fuel(),
                    "metal": next.metal(),
                    "deposit": next.deposit(),
                }),
            ));
        }
        if !entries.is_empty() || next.tick.is_multiple_of(4) {
            let mut history = self.history.clone();
            for entry in entries {
                push_log(&mut history, entry);
            }
            if let Err(error) = save_sim(&self.save, &next, &history) {
                self.fail_save(error);
                return;
            }
            self.history = history;
        }
        self.sim = next;
        let _ = self
            .updates
            .send(view::update(&self.sim, &events).to_string());
    }

    fn fail_save(&mut self, error: io::Error) {
        eprintln!("Save failed: {error}");
        self.running = false;
        self.save_error = Some(error.to_string());
        self.record(
            "save_error",
            json!({"kind": format!("{:?}", error.kind()), "os_code": error.raw_os_error()}),
        );
    }

    fn record(&mut self, kind: &str, details: Value) {
        push_log(&mut self.history, log_entry(&self.sim, kind, details));
    }
}

fn push_log(history: &mut VecDeque<Value>, entry: Value) {
    while history.len() >= LOG_LIMIT {
        history.pop_front();
    }
    history.push_back(entry);
}

fn log_entry(sim: &Sim, kind: &str, details: impl Serialize) -> Value {
    json!({"tick": sim.tick, "world_seconds": sim.seconds, "kind": kind, "details": details})
}

#[derive(Deserialize)]
struct SaveFile {
    #[serde(flatten)]
    sim: Sim,
    #[serde(default)]
    diagnostic_history: VecDeque<Value>,
}

fn load_sim(path: &Path) -> io::Result<SaveFile> {
    match fs::read(path) {
        Ok(bytes) => {
            let mut loaded: SaveFile = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
            loaded.sim.migrate();
            if !loaded.sim.valid() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "invalid simulation state",
                ));
            }
            let skip = loaded.diagnostic_history.len().saturating_sub(LOG_LIMIT);
            loaded.diagnostic_history.drain(..skip);
            Ok(loaded)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let mut sim = Sim::default();
            if env::var("GENESIS_LEADER").as_deref() != Ok("cautious") {
                sim.governance.leader = governance::Leader::Industrial;
            }
            sim.migrate();
            Ok(SaveFile {
                sim,
                diagnostic_history: VecDeque::new(),
            })
        }
        Err(error) => Err(error),
    }
}

fn save_sim(path: &Path, sim: &Sim, history: &VecDeque<Value>) -> io::Result<()> {
    #[derive(Serialize)]
    struct Save<'a> {
        #[serde(flatten)]
        sim: &'a Sim,
        diagnostic_history: &'a VecDeque<Value>,
    }
    let tmp = path.with_extension("json.tmp");
    let bytes = serde_json::to_vec(&Save {
        sim,
        diagnostic_history: history,
    })
    .map_err(io::Error::other)?;
    let mut file = fs::File::create(&tmp)?;
    file.write_all(&bytes)?;
    file.sync_all()?;
    drop(file);
    fs::rename(tmp, path)
}

async fn health(State(state): State<Shared>) -> Json<Value> {
    Json(state.lock().await.health())
}

async fn report(State(state): State<Shared>) -> Json<Value> {
    let engine = state.lock().await;
    Json(view::report(&engine.sim, engine.running, engine.speed))
}

async fn diagnostics(State(state): State<Shared>) -> impl IntoResponse {
    let engine = state.lock().await;
    let report = json!({
        "format": "living-sector-diagnostics-v1",
        "version": env!("CARGO_PKG_VERSION"),
        "os": env::consts::OS,
        "runtime": {"running": engine.running, "speed": engine.speed, "save_failed": engine.save_error.is_some()},
        "state": engine.sim,
        "observer": view::report(&engine.sim, engine.running, engine.speed),
        "events": engine.history,
    });
    (
        [
            (header::CONTENT_TYPE, "application/json; charset=utf-8"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=Living-Sector-diagnostics.json",
            ),
            (header::CACHE_CONTROL, "no-store"),
        ],
        serde_json::to_string_pretty(&report).expect("JSON value serializes"),
    )
}

async fn pause(State(state): State<Shared>, Json(_): Json<Value>) -> Json<Value> {
    let mut engine = state.lock().await;
    engine.running = false;
    engine.record("paused", json!({}));
    if let Err(error) = save_sim(&engine.save, &engine.sim, &engine.history) {
        engine.fail_save(error);
    }
    Json(engine.health())
}

async fn resume(State(state): State<Shared>, Json(_): Json<Value>) -> Json<Value> {
    let mut engine = state.lock().await;
    engine.save_error = None;
    engine.running = true;
    engine.record("resumed", json!({}));
    Json(engine.health())
}

#[derive(Deserialize)]
struct Speed {
    world_speed: f64,
}

async fn set_speed(
    State(state): State<Shared>,
    Json(speed): Json<Speed>,
) -> Result<Json<Value>, StatusCode> {
    if !(0.25..=16.0).contains(&speed.world_speed) {
        return Err(StatusCode::BAD_REQUEST);
    }
    let mut engine = state.lock().await;
    engine.speed = speed.world_speed;
    engine.record("speed", json!({"world_speed": speed.world_speed}));
    Ok(Json(engine.health()))
}

async fn websocket(
    State(state): State<Shared>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    if let Some(origin) = headers.get(header::ORIGIN) {
        let host = headers
            .get(header::HOST)
            .and_then(|value| value.to_str().ok());
        if !host.is_some_and(|host| origin == format!("http://{host}").as_str()) {
            return StatusCode::FORBIDDEN.into_response();
        }
    }
    ws.on_upgrade(move |socket| serve_socket(socket, state))
}

async fn serve_socket(mut socket: WebSocket, state: Shared) {
    let (mut updates, initial) = {
        let engine = state.lock().await;
        (
            engine.updates.subscribe(),
            view::update(&engine.sim, &[]).to_string(),
        )
    };
    if socket.send(Message::Text(initial.into())).await.is_err() {
        return;
    }
    loop {
        tokio::select! {
            incoming = socket.recv() => {
                if matches!(incoming, None | Some(Err(_)) | Some(Ok(Message::Close(_)))) { break; }
            }
            frame = updates.recv() => match frame {
                Ok(frame) => if socket.send(Message::Text(frame.into())).await.is_err() { break; },
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    }
}

const PAGE: &str = include_str!("../observer/index.html");
const STYLE: &str = include_str!("../observer/styles.css");
const APP: &str = include_str!("../observer/app.js");
const MODEL: &str = include_str!("../observer/model.js");

fn asset(content_type: &'static str, content: &'static str) -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, content_type),
            (header::CACHE_CONTROL, "no-store"),
        ],
        content,
    )
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = env::var("GENESIS_PORT").map_or(Ok(17860), |value| value.parse::<u16>())?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port)).await?;
    let address = listener.local_addr()?;
    let save = match env::var_os("GENESIS_SAVE_PATH") {
        Some(path) => PathBuf::from(path),
        None => env::current_exe()?.with_file_name("genesis-clean-v1.json"),
    };
    let loaded = load_sim(&save)
        .map_err(|error| io::Error::new(error.kind(), format!("{}: {error}", save.display())))?;
    let (updates, _) = broadcast::channel(32);
    let state = Arc::new(Mutex::new(Engine {
        sim: loaded.sim,
        history: loaded.diagnostic_history,
        running: false,
        speed: 1.0,
        save,
        updates,
        save_error: None,
    }));
    let app = Router::new()
        .route("/", get(|| async { Html(PAGE) }))
        .route("/observer", get(|| async { Html(PAGE) }))
        .route(
            "/observer/styles.css",
            get(|| async { asset("text/css; charset=utf-8", STYLE) }),
        )
        .route(
            "/observer/app.js",
            get(|| async { asset("text/javascript; charset=utf-8", APP) }),
        )
        .route(
            "/observer/model.js",
            get(|| async { asset("text/javascript; charset=utf-8", MODEL) }),
        )
        .route(
            "/observer/orbital-structures.webp",
            get(|| async {
                (
                    [(header::CONTENT_TYPE, "image/webp")],
                    include_bytes!("../observer/assets/orbital-structures.webp").as_slice(),
                )
            }),
        )
        .route("/api/health", get(health))
        .route("/api/report", get(report))
        .route("/api/diagnostics", get(diagnostics))
        .route("/api/sim/pause", post(pause))
        .route("/api/sim/resume", post(resume))
        .route("/api/sim/speed", post(set_speed))
        .route("/ws", get(websocket))
        .with_state(state.clone());
    let tick_state = state.clone();
    let task = tokio::spawn(async move {
        let mut interval = tokio::time::interval(STEP);
        interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
        loop {
            interval.tick().await;
            tick_state.lock().await.step();
        }
    });

    let url = format!("http://{address}/observer");
    println!("Genesis Clean: {url}");
    #[cfg(windows)]
    if env::var_os("GENESIS_NO_BROWSER").is_none() {
        let _ = std::process::Command::new("rundll32.exe")
            .args(["url.dll,FileProtocolHandler", &url])
            .spawn();
    }

    tokio::select! {
        result = axum::serve(listener, app) => result?,
        _ = tokio::signal::ctrl_c() => {
            task.abort();
            let engine = state.lock().await;
            if engine.sim.tick > 0 { save_sim(&engine.save, &engine.sim, &engine.history)?; }
        }
    }
    Ok(())
}
