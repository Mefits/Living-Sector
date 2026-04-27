//! Hanabi particle effects — TEMPORARILY STUBBED.
//!
//! `bevy_hanabi` is disabled for the duration of the Bevy 0.14 → 0.18
//! upgrade. The original implementation is preserved alongside this
//! file as `particles.rs.disabled` and will be restored after the
//! Bevy upgrade lands. Hanabi 0.13 also caused a 30-second macOS Metal
//! GPU stall on certain saved DBs that disabling fully resolved; the
//! upgrade pulls in newer wgpu that should fix the underlying issue.
//!
//! This stub keeps the public type names + system signatures so the
//! rest of `render/` continues to compile, but every system is a
//! no-op. Re-enable by:
//!   1. `mv particles.rs.disabled particles.rs` (and delete this stub)
//!   2. add `bevy_hanabi` back to Cargo.toml
//!   3. add `HanabiPlugin` back to RenderPlugin

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

pub(super) fn build_engine_trail_effect(mut commands: Commands) {
    commands.insert_resource(EngineTrailEffect);
}

pub(super) fn build_explosion_effect(mut commands: Commands) {
    commands.insert_resource(ExplosionEffect);
}

pub(super) fn build_gate_flash_effect(mut commands: Commands) {
    commands.insert_resource(GateFlashEffect);
}

pub(super) fn sync_engine_trails(_query: Query<()>) {}

pub(super) fn cleanup_stale_engine_trails(
    _commands: Commands,
    _sim: Res<Sim>,
    _trails: Query<(Entity, &EngineTrailFor)>,
) {
}

pub(super) fn tick_explosion_lifetimes(
    _commands: Commands,
    _time: Res<Time>,
    _query: Query<(Entity, &mut ExplosionLifetime)>,
) {
}

pub(super) fn event_driven_flashes(
    _commands: Commands,
    _events: Res<crate::sim::EventsLog>,
    _flash: Option<Res<GateFlashEffect>>,
    _last_tick: Local<u64>,
    _sim: Res<Sim>,
) {
}
