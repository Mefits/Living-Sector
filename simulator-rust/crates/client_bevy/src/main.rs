//! Bevy client for the spaceproject simulator, embedded flavour.
//!
//! Bundle 2a scope: wire the sim in as a Bevy Resource, run its tick
//! loop on `FixedUpdate` at 125 ms cadence, log a one-line heartbeat
//! every wall-clock second so we can see it's alive. No render yet —
//! Bundle 2b spawns Bevy entities mirroring the sim state.

use bevy::prelude::*;
use std::time::Duration;

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
        // Fixed-timestep schedule drives the sim tick independently of
        // render frame rate. Matches the sim_server default of 125 ms
        // per tick (8 tps). World-speed UI will rescale this later.
        .insert_resource(Time::<Fixed>::from_seconds(sim::DEFAULT_TICK_INTERVAL_S))
        .add_plugins(sim::SimPlugin)
        .add_plugins(render::RenderPlugin)
        .add_plugins(camera::CameraPlugin)
        .add_plugins(ui::UiPlugin)
        .add_systems(Startup, setup_scene)
        .add_systems(Update, heartbeat_system)
        .run();
}

/// Lighting only — camera is spawned by `CameraPlugin` with its own
/// orbit-camera component. Bundle 3 will add a starfield / nebula
/// backdrop; this keeps scene setup minimal.
fn setup_scene(mut commands: Commands) {
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 10_000.0,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.8, 0.3, 0.0)),
        ..default()
    });
    // Dim ambient so the directional light isn't the only thing lighting
    // anything — placeholder materials are pretty matte and go near-black
    // on the shadow side without ambient fill.
    commands.insert_resource(AmbientLight {
        color: Color::srgb(0.2, 0.25, 0.35),
        brightness: 200.0,
    });
    info!("client_bevy: window up, sim embedded.");
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
