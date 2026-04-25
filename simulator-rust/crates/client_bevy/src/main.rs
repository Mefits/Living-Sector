//! Bevy client for the spaceproject simulator, embedded flavour.
//!
//! Bundle 2a scope: wire the sim in as a Bevy Resource, run its tick
//! loop on `FixedUpdate` at 125 ms cadence, log a one-line heartbeat
//! every wall-clock second so we can see it's alive. No render yet —
//! Bundle 2b spawns Bevy entities mirroring the sim state.

use bevy::prelude::*;
use bevy::render::view::screenshot::ScreenshotManager;
use bevy::window::PrimaryWindow;
use bevy::winit::{UpdateMode, WinitSettings};
use std::time::Duration;

mod audio;
mod camera;
mod render;
mod sim;
mod ui;

fn main() {
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
                        resolution: (1280., 720.).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(bevy::log::LogPlugin {
                    level: bevy::log::Level::INFO,
                    filter: "info,client_bevy=info,wgpu=warn,naga=warn".into(),
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
        .add_plugins(sim::SimPlugin)
        .add_plugins(render::RenderPlugin)
        .add_plugins(camera::CameraPlugin)
        .add_plugins(ui::UiPlugin)
        .add_plugins(audio::AudioPlugin)
        .add_systems(Startup, setup_scene)
        .add_systems(Update, (heartbeat_system, screenshot_key))
        .run();
}

/// Lighting only — camera is spawned by `CameraPlugin` with its own
/// orbit-camera component. Bundle 3 will add a starfield / nebula
/// backdrop; this keeps scene setup minimal.
fn setup_scene(mut commands: Commands) {
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 10_000.0,
            // Critical for FPS at 1600+ ships: a shadow-casting
            // directional light with that many meshes kills the
            // frame budget on M1's integrated GPU (observed: 1 FPS
            // at full fleet). Space is lit ambient-plus-key anyway,
            // so dropping shadows is basically invisible.
            shadows_enabled: false,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.8, 0.3, 0.0)),
        ..default()
    });
    // Dim ambient so the directional light isn't the only thing lighting
    // anything — placeholder materials are pretty matte and go near-black
    // on the shadow side without ambient fill. Dropped to 80 (was 200)
    // so ships + facilities don't wash out against the new black clear
    // color.
    commands.insert_resource(AmbientLight {
        color: Color::srgb(0.2, 0.25, 0.35),
        brightness: 80.0,
    });
    info!("client_bevy: window up, sim embedded.");
}

/// F12 captures a PNG of the primary window to `/tmp/bevy_screenshot.png`
/// via Bevy's built-in ScreenshotManager. A quick way to verify what's
/// actually on screen during headless / backgrounded testing — Claude
/// can Read the saved PNG directly.
///
/// Also auto-captures once when the `CLIENT_BEVY_AUTO_SCREENSHOT` env
/// var is set: the system fires after ~120 frames (≈2s at 60 fps)
/// then sets the flag to stop repeated saves. This makes self-verify
/// from a short-lived background smoke test feasible.
fn screenshot_key(
    keys: Res<ButtonInput<KeyCode>>,
    primary: Query<Entity, With<PrimaryWindow>>,
    mut screenshots: ResMut<ScreenshotManager>,
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

    let Ok(window) = primary.get_single() else { return };
    let path = "/tmp/bevy_screenshot.png";
    if let Err(e) = screenshots.save_screenshot_to_disk(window, path) {
        warn!("client_bevy: screenshot failed: {e}");
    } else {
        info!("client_bevy: screenshot → {path}");
    }
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
