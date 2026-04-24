//! Bevy client for the spaceproject simulator, embedded flavour.
//!
//! Bundle 2a scope: wire the sim in as a Bevy Resource, run its tick
//! loop on `FixedUpdate` at 125 ms cadence, log a one-line heartbeat
//! every wall-clock second so we can see it's alive. No render yet —
//! Bundle 2b spawns Bevy entities mirroring the sim state.

use bevy::prelude::*;
use std::time::Duration;

mod sim;

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
        .add_systems(Startup, setup_scene)
        .add_systems(Update, heartbeat_system)
        .run();
}

/// Placeholder scene for Bundle 2a: one camera + one directional light,
/// so the window isn't black while we prove the tick loop works.
/// Bundle 2b replaces this with the real world setup.
fn setup_scene(mut commands: Commands) {
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(0.0, 5.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        Name::new("MainCamera"),
    ));
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 10_000.0,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.8, 0.3, 0.0)),
        ..default()
    });
    info!("client_bevy: window up, sim embedded. See tick counter below.");
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
