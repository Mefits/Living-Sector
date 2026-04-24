//! Bevy client for the spaceproject simulator.
//!
//! Bundle 1.2 scope: empty window, WS client connects to localhost:8080,
//! prints every received ServerMsg variant to the console. No rendering
//! yet, no UI, no camera.

use bevy::prelude::*;

mod net;

fn main() {
    // tracing_subscriber so we see our own logs alongside bevy's.
    // RUST_LOG=info is the useful default; bump to debug for the ws
    // side while developing.
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,client_bevy=debug,tokio_tungstenite=info".into()),
        )
        .init();

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "spaceproject (bevy)".into(),
                resolution: (1280., 720.).into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(net::NetPlugin)
        .add_systems(Startup, setup_scene)
        .run();
}

/// Placeholder: a light + a camera so the window isn't black.
/// Bundle 2 replaces this with the real world setup.
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
    info!("client_bevy: scene placeholder up, waiting on WS");
}
