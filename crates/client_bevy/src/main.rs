//! Bevy client for the spaceproject simulator, embedded flavour.
//!
//! Bundle 2a scope: wire the sim in as a Bevy Resource, run its tick
//! loop on `FixedUpdate` at 125 ms cadence, log a one-line heartbeat
//! every wall-clock second so we can see it's alive. No render yet —
//! Bundle 2b spawns Bevy entities mirroring the sim state.

use bevy::prelude::*;
use bevy::render::settings::{Backends, RenderCreation, WgpuSettings};
use bevy::render::view::screenshot::{save_to_disk, Screenshot};
use bevy::render::RenderPlugin;
use bevy::window::PrimaryWindow;
use bevy::winit::{UpdateMode, WinitSettings};
use std::time::Duration;

mod audio;
mod camera;
mod render;
mod sim;
mod ui;

/// Top-level app state. `MainMenu` is the title screen — sim is
/// frozen, panels hidden, but the 3D scene (starfield + nebulas,
/// bodies) keeps rendering as a backdrop. `InGame` is the running
/// simulation with full UI. The Bevy `States` plumbing gates
/// per-system runs via `.run_if(in_state(...))`.
#[derive(States, Clone, Copy, Eq, PartialEq, Hash, Debug, Default)]
pub enum AppState {
    #[default]
    MainMenu,
    InGame,
}

/// View sub-mode while the player is `InGame`. `Orbit` is the
/// existing top-down god-view (orbit camera, all UI panels). `Interior`
/// is the FPS walking-skeleton mode where the player is inside a
/// ship-room and the orbit world keeps rendering through a window
/// quad via a render-target camera.
///
/// **Why a sub-state and not a sibling AppState:** transitioning out
/// of `AppState::InGame` fires `OnExit(InGame)` in `render::mod.rs`,
/// which despawns every `GameWorld`-tagged entity (ships, bodies,
/// facilities). The interior view's `OutsideCam` needs those alive
/// to render. As a sub-state, we never leave `InGame` — the
/// despawn never fires, the world stays put, and only camera +
/// input swap.
///
/// **Lifecycle.** Bevy's `SubStates` derive auto-registers this as
/// existing only while `AppState == InGame`. Entering `MainMenu`
/// drops the sub-state; re-entering `InGame` re-initialises it to
/// `Orbit`. F2 toggles between the two; Escape in `Interior` returns
/// to `Orbit` (Escape in `Orbit` keeps its existing
/// close-top-panel / open-pause-menu behaviour from
/// `ui/panel_stack.rs`).
#[derive(SubStates, Clone, Copy, Eq, PartialEq, Hash, Debug, Default)]
#[source(AppState = AppState::InGame)]
pub enum InGameView {
    #[default]
    Orbit,
    Interior,
}

fn main() {
    // Phase D: `--headless` retires the standalone `simulator` binary.
    // It boots a tokio runtime and runs `sim_server::runtime::run()`
    // (the same code the old binary called) instead of the Bevy app.
    // Without `--headless`, the regular Bevy windowed client runs
    // exactly as before. Same binary, two modes.
    if std::env::args().any(|a| a == "--headless") {
        // Install the same tracing subscriber sim_server's binary
        // used to set up. We do it here rather than inside `runtime`
        // so the windowed branch can keep its bevy::log::LogPlugin
        // ownership of the subscriber slot.
        use tracing_subscriber::{fmt, EnvFilter};
        let filter = EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| {
                EnvFilter::new("simulator=info,sim_core=info,sim_server=info,tower_http=warn")
            });
        fmt()
            .with_env_filter(filter)
            .with_writer(std::io::stderr)
            .with_target(true)
            .init();

        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");
        if let Err(e) = rt.block_on(sim_server::runtime::run()) {
            eprintln!("headless server error: {e}");
            std::process::exit(1);
        }
        return;
    }

    // Let Bevy's LogPlugin own the global tracing subscriber — it
    // already installs one and fights ours for the slot otherwise
    // ("Could not set global logger" error on startup). We configure
    // the same filter through its LogPlugin instead.
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "spaceproject (bevy, embedded)".into(),
                        resolution: (1280u32, 720u32).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(bevy::log::LogPlugin {
                    level: bevy::log::Level::INFO,
                    filter: "info,client_bevy=info,wgpu=warn,naga=warn".into(),
                    ..default()
                })
                // Force the wgpu backend per-platform. On Windows, DX12
                // hits a swapchain state-tracking bug with HDR + bloom +
                // bevy_hanabi 0.13 (RENDER_TARGET vs PRESENT mismatch on
                // wgpu 0.20). Vulkan on NVIDIA/AMD/Intel is the stable
                // path; Metal is the only backend on macOS anyway. Linux
                // gets Vulkan too. The env var WGPU_BACKEND still
                // overrides this if a player needs to escape hatch.
                .set(RenderPlugin {
                    render_creation: RenderCreation::Automatic(WgpuSettings {
                        backends: Some(if cfg!(target_os = "macos") {
                            Backends::METAL
                        } else {
                            Backends::VULKAN
                        }),
                        ..default()
                    }),
                    ..default()
                }),
        )
        // Clear to black so space looks like space rather than the
        // default bevy grey. Nebula clouds + starfield sit against
        // true black now.
        .insert_resource(ClearColor(Color::BLACK))
        // Keep ticking at full speed even when the window loses
        // focus (alt-tab, Terminal foreground, etc.). Bevy's
        // default for a desktop app is to throttle unfocused
        // windows to ReactiveLowPower, which shows up as "1 FPS"
        // when the user glances at the window behind another app.
        // For a sim that's actually running work each frame we
        // want continuous.
        .insert_resource(WinitSettings {
            focused_mode: UpdateMode::Continuous,
            unfocused_mode: UpdateMode::Continuous,
        })
        // Fixed-timestep schedule drives the sim tick independently of
        // render frame rate. Matches the sim_server default of 125 ms
        // per tick (8 tps). World-speed UI will rescale this later.
        .insert_resource(Time::<Fixed>::from_seconds(sim::DEFAULT_TICK_INTERVAL_S))
        .init_state::<AppState>()
        // M0 (FPS interior): InGameView is a sub-state of InGame —
        // see the type docs above for the cleanup-blocker reasoning.
        // The InteriorPlugin (M0 task 2) will register OnEnter /
        // OnExit handlers against this sub-state; for now the toggle
        // key is wired but the interior scene itself isn't spawned.
        .add_sub_state::<InGameView>()
        .add_plugins(sim::SimPlugin)
        .add_plugins(render::RenderPlugin)
        .add_plugins(camera::CameraPlugin)
        .add_plugins(ui::UiPlugin)
        .add_plugins(audio::AudioPlugin)
        .add_systems(Startup, setup_scene)
        .add_systems(
            Update,
            (
                heartbeat_system,
                screenshot_key,
                frame_pulse,
                interior_toggle_key.run_if(in_state(AppState::InGame)),
            ),
        )
        .run();
}

/// Lighting only — camera is spawned by `CameraPlugin` with its own
/// orbit-camera component. Bundle 3 will add a starfield / nebula
/// backdrop; this keeps scene setup minimal.
fn setup_scene(mut commands: Commands) {
    commands.spawn((
        DirectionalLight {
            illuminance: 10_000.0,
            // Critical for FPS at 1600+ ships: a shadow-casting
            // directional light with that many meshes kills the
            // frame budget on M1's integrated GPU (observed: 1 FPS
            // at full fleet). Space is lit ambient-plus-key anyway,
            // so dropping shadows is basically invisible.
            shadows_enabled: false,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.8, 0.3, 0.0)),
    ));
    // Dim ambient so the directional light isn't the only thing lighting
    // anything — placeholder materials are pretty matte and go near-black
    // on the shadow side without ambient fill. Dropped to 80 (was 200)
    // so ships + facilities don't wash out against the new black clear
    // color.
    // Bevy 0.18: AmbientLight is now a per-camera Component;
    // the world-wide ambient lives on the GlobalAmbientLight Resource.
    commands.insert_resource(bevy::light::GlobalAmbientLight {
        color: Color::srgb(0.2, 0.25, 0.35),
        brightness: 80.0,
        affects_lightmapped_meshes: true,
    });
    info!("client_bevy: window up, sim embedded.");
}

/// F12 captures a PNG of the primary window to `/tmp/bevy_screenshot.png`.
/// Bevy 0.15 reshaped the API: spawn a `Screenshot` entity targeting the
/// window, attach a `save_to_disk` observer that fires `ScreenshotCaptured`,
/// and the entity self-cleans after the capture finishes. A quick way to
/// verify what's actually on screen during headless / backgrounded testing —
/// Claude can Read the saved PNG directly.
///
/// Also auto-captures once when the `CLIENT_BEVY_AUTO_SCREENSHOT` env
/// var is set: the system fires after ~120 frames (≈2s at 60 fps)
/// then sets the flag to stop repeated saves. This makes self-verify
/// from a short-lived background smoke test feasible.
fn screenshot_key(
    mut commands: Commands,
    keys: Res<ButtonInput<KeyCode>>,
    primary: Query<Entity, With<PrimaryWindow>>,
    mut frame_counter: Local<u32>,
    mut auto_done: Local<bool>,
) {
    *frame_counter = frame_counter.saturating_add(1);

    let manual = keys.just_pressed(KeyCode::F12);
    // Auto-screenshot via env var. macOS throttles backgrounded
    // Bevy windows to ~1 Hz, so we trigger at frame 3 (≈3s from
    // start) rather than something like frame 180 which would
    // never land under `cargo run &`. Foreground + F12 is the
    // interactive path; this covers headless-smoke verification.
    let auto = !*auto_done
        && *frame_counter >= 90
        && std::env::var("CLIENT_BEVY_AUTO_SCREENSHOT").is_ok();

    if !(manual || auto) {
        return;
    }

    let Ok(window) = primary.single() else { return };
    let path = "/tmp/bevy_screenshot.png";
    commands
        .spawn(Screenshot::window(window))
        .observe(save_to_disk(path));
    info!("client_bevy: screenshot → {path}");
    if auto {
        *auto_done = true;
    }
}

/// Log a one-line heartbeat every wall-clock second while the sim is
/// running. Confirms the embedded tick loop spins. Goes away in 2b.
fn heartbeat_system(
    sim: Res<sim::Sim>,
    time: Res<Time>,
    mut last_emit: Local<Duration>,
) {
    let now = time.elapsed();
    if now.saturating_sub(*last_emit) < Duration::from_secs(1) {
        return;
    }
    *last_emit = now;
    info!(
        "tick={} ships={} facilities={} bodies={} factions={}",
        sim.tick,
        sim.store.ship_by_id.len(),
        sim.store.facility_by_id.len(),
        sim.store.body_by_id.len(),
        sim.store.faction_by_id.len(),
    );
}

/// M0: F2 toggles the `InGameView` sub-state between `Orbit` and
/// `Interior`. Escape while in `Interior` returns to `Orbit` (a
/// safety net for when the cursor is locked and the user wants out
/// fast). Gated on `AppState::InGame` at the call site so neither
/// key fires from the main menu.
///
/// `egui` keyboard gating is intentionally NOT applied to F2 — the
/// interior toggle is a high-level mode switch users want to fire
/// even mid-text-edit (closing whatever panel they were in). Escape
/// stays unfiltered for the same reason: in Interior the cursor is
/// locked anyway, so egui isn't taking input.
fn interior_toggle_key(
    keys: Res<ButtonInput<KeyCode>>,
    current: Res<State<InGameView>>,
    mut next: ResMut<NextState<InGameView>>,
) {
    if keys.just_pressed(KeyCode::F2) {
        let target = match *current.get() {
            InGameView::Orbit => InGameView::Interior,
            InGameView::Interior => InGameView::Orbit,
        };
        info!("client_bevy: InGameView → {target:?}");
        next.set(target);
        return;
    }
    if keys.just_pressed(KeyCode::Escape) && *current.get() == InGameView::Interior {
        info!("client_bevy: Escape from Interior → Orbit");
        next.set(InGameView::Orbit);
    }
}

/// Frame-level slow-frame detector. Measures wall-clock between
/// successive Update invocations; if a single frame took longer than
/// SLOW_FRAME_MS (= main thread was blocked that long), warn with the
/// duration. macOS beach-balls show up as 5+ second frames here. The
/// sim's own slow-tick warning catches sim-side stalls; this catches
/// render-side / panel-side / GPU stalls that the sim warning misses.
fn frame_pulse(mut last: Local<Option<std::time::Instant>>) {
    let now = std::time::Instant::now();
    if let Some(prev) = *last {
        let dt = now.saturating_duration_since(prev);
        // 250 ms is well above 60-fps frame time (16 ms) and even
        // above the FixedUpdate cadence (125 ms). A frame this long
        // is felt as a hitch; multi-second ones are felt as freezes.
        if dt >= Duration::from_millis(250) {
            warn!(
                "client_bevy: slow frame — Update gap of {:.0}ms",
                dt.as_secs_f32() * 1000.0,
            );
        }
    }
    *last = Some(now);
}
