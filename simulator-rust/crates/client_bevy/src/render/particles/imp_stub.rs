//! Hanabi particle effects — macOS no-op stub.
//!
//! `bevy_hanabi` 0.18 has a wgpu validation panic on Metal at pipeline
//! creation, so on macOS we compile this stub instead of the real
//! implementation in `particles_hanabi.rs`. Routed by `target_os`
//! through `particles.rs`. Same public type + system signatures so
//! the rest of `render/` compiles either way; every system is a
//! no-op here.

use bevy::prelude::*;

use crate::sim::Sim;

/// Stub — no asset handle, no effect.
#[derive(Resource, Default)]
pub struct EngineTrailEffect;

/// Stub — no asset handle, no effect.
#[derive(Resource, Default)]
pub struct ExplosionEffect;

/// Stub — no asset handle, no effect.
#[derive(Resource, Default)]
pub struct GateFlashEffect;

/// Lifetime timer left on whatever explosion entity used to carry one.
/// Without hanabi spawning the entities, nothing inserts this; the
/// type stays so cleanup systems can still query for it.
#[derive(Component)]
pub struct ExplosionLifetime(pub Timer);

/// Marker for per-ship engine-trail entity. Without hanabi, no entity
/// is spawned with this component, but the type stays so the
/// cleanup system signature still typechecks.
#[derive(Component)]
pub struct EngineTrailFor(pub String);

pub fn build_engine_trail_effect(mut commands: Commands) {
    commands.insert_resource(EngineTrailEffect);
}

pub fn build_explosion_effect(mut commands: Commands) {
    commands.insert_resource(ExplosionEffect);
}

pub fn build_gate_flash_effect(mut commands: Commands) {
    commands.insert_resource(GateFlashEffect);
}

pub fn sync_engine_trails(_query: Query<()>) {}

pub fn cleanup_stale_engine_trails(
    _commands: Commands,
    _sim: Res<Sim>,
    _trails: Query<(Entity, &EngineTrailFor)>,
) {
}

pub fn tick_explosion_lifetimes(
    _commands: Commands,
    _time: Res<Time>,
    _query: Query<(Entity, &mut ExplosionLifetime)>,
) {
}

pub fn event_driven_flashes(
    _commands: Commands,
    _events: Res<crate::sim::EventsLog>,
    _flash: Option<Res<GateFlashEffect>>,
    _last_tick: Local<u64>,
    _sim: Res<Sim>,
) {
}
