//! Hanabi particle effects — engine trails, ship explosions, gate flashes.
//!
//! Three shared `EffectAsset`s built once at startup and referenced
//! by every spawn site. Hanabi's GPU compile happens on first asset
//! upload; sharing handles keeps the cost paid once per app, not per
//! event.
//!
//! ## Effects
//!
//!   * [`EngineTrailEffect`] — cyan exhaust drawn behind every active
//!     ship. The trail entity is a sibling of the ShipEntity (NOT a
//!     child) so trail emission can keep going while the ship's
//!     transform is queried elsewhere — see [`sync_engine_trails`].
//!     Tagged with [`EngineTrailFor`] (carries the ship sim_id) so
//!     [`cleanup_stale_engine_trails`] can despawn orphans.
//!   * [`ExplosionEffect`] — one-shot orange burst spawned by
//!     `cleanup_stale_ships` (in render/mod.rs) at the doomed ship's
//!     last transform. Carries [`ExplosionLifetime`] so the entity
//!     gets despawned ~1.5 s after particles finish.
//!   * [`GateFlashEffect`] — paired flashes at source + destination
//!     gate positions whenever a `ship_gate_jumped` event fires.
//!     Same lifetime-timer self-clean as explosions. Driven by
//!     [`event_driven_flashes`] which reads the events log.
//!
//! [`tick_explosion_lifetimes`] sweeps every entity carrying an
//! ExplosionLifetime each frame and despawns finished ones — Hanabi
//! keeps emitter entities alive after the last particle dies, which
//! would otherwise pile up forever in queries.
//!
//! Extracted from `render/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_hanabi::prelude::*;

use super::{ShipEntity, SCALE_FACTOR, SHIP_GLB_SCALE};
use crate::sim::Sim;

/// Handle to the shared engine-trail particle EffectAsset. Built
/// once at Startup; every ship references the same handle so we
/// pay the GPU compile cost once.
#[derive(Resource)]
pub struct EngineTrailEffect(pub Handle<EffectAsset>);

/// Handle to the shared one-shot explosion EffectAsset. Spawned by
/// `cleanup_stale_ships` at the doomed ship's last position before
/// it despawns. Self-cleans via [`ExplosionLifetime`] timer.
#[derive(Resource)]
pub struct ExplosionEffect(pub Handle<EffectAsset>);

/// Handle to the shared gate-jump flash EffectAsset. Spawned by
/// `gate_jump_flash` at both the source and destination gate
/// positions whenever a `ship_gate_jumped` event fires. Same
/// `ExplosionLifetime` self-clean machinery.
#[derive(Resource)]
pub struct GateFlashEffect(pub Handle<EffectAsset>);

/// Tag + timer attached to a one-shot explosion entity so it can be
/// despawned after its particles finish. Hanabi keeps the entity
/// alive after the last particle dies; without this it'd just
/// linger in queries forever.
#[derive(Component)]
pub struct ExplosionLifetime(pub Timer);

/// Marker on the per-ship particle-effect entity. Carries the
/// ship's sim_id so the per-frame sync system can look up the
/// matching ship transform. Lives as a sibling entity (NOT a child)
/// so the ship's GLB scale (~0.025) doesn't shrink the particles.
#[derive(Component)]
pub struct EngineTrailFor(pub String);

pub(super) fn build_engine_trail_effect(
    mut effects: ResMut<Assets<EffectAsset>>,
    mut commands: Commands,
) {
    // Cyan exhaust gradient — bright core fading to dim blue, then
    // transparent. Three keys is enough for a smooth ramp without
    // banding.
    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, Vec4::new(0.55, 0.95, 1.0, 1.0));
    color_gradient.add_key(0.5, Vec4::new(0.25, 0.55, 1.0, 0.7));
    color_gradient.add_key(1.0, Vec4::new(0.05, 0.10, 0.40, 0.0));

    // Particle size in entity-local units; trail entity scales by
    // the ship's size_multiplier (0.5..=4.0) so a Massive hauler's
    // particles render up to 4× this. Native ship hull is ~10 units
    // × SHIP_GLB_SCALE 0.025 × size_mult = 0.25 wu × size_mult, so
    // a 0.04-base particle reads as ~16% of hull length — small
    // enough to look like discrete exhaust dots, big enough to see.
    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.04));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let mut module = Module::default();

    // Tight spawn radius. Wider than this and the exhaust looks
    // like a cloud, not a thrust column.
    let init_pos = SetPositionSphereModifier {
        center: module.lit(Vec3::ZERO),
        radius: module.lit(0.01),
        dimension: ShapeDimension::Volume,
    };

    // Velocity points -Z (the entity faces the ship's forward, so
    // particles eject backward) with a small spread. Slow enough
    // that lifetime × velocity gives a trail roughly equal to ship
    // hull length rather than 6× longer.
    let init_vel = SetVelocitySphereModifier {
        center: module.lit(Vec3::new(0.0, 0.0, -0.4)),
        speed: module.lit(0.15),
    };

    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        module.lit(0.4_f32),
    );

    // 30 particles/sec/ship × ~282 ships ≈ 8500/sec aggregate. With
    // 0.6 s lifetime that's <5200 live particles total. Comfortably
    // within hanabi's per-effect 512 cap × N effects budget on M1.
    let spawner = Spawner::rate(30.0_f32.into());

    let effect = EffectAsset::new(512, spawner, module)
        .with_name("engine_trail")
        .init(init_pos)
        .init(init_vel)
        .init(init_lifetime)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        });

    let handle = effects.add(effect);
    commands.insert_resource(EngineTrailEffect(handle));
}

pub(super) fn build_explosion_effect(
    mut effects: ResMut<Assets<EffectAsset>>,
    mut commands: Commands,
) {
    // Hot-flash → orange → fade. Stays warm enough to read as fire,
    // not just blue-shifted hanabi default.
    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, Vec4::new(1.0, 0.95, 0.55, 1.0));
    color_gradient.add_key(0.3, Vec4::new(1.0, 0.55, 0.20, 0.95));
    color_gradient.add_key(1.0, Vec4::new(0.30, 0.10, 0.05, 0.0));

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.40));
    size_gradient.add_key(0.5, Vec3::splat(0.30));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let mut module = Module::default();

    let init_pos = SetPositionSphereModifier {
        center: module.lit(Vec3::ZERO),
        radius: module.lit(0.05),
        dimension: ShapeDimension::Volume,
    };
    // Radial outward burst — speed 6 wu/s, sphere distribution so it
    // reads as a 3D shockwave from any camera angle.
    let init_vel = SetVelocitySphereModifier {
        center: module.lit(Vec3::ZERO),
        speed: module.lit(6.0),
    };
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        module.lit(1.0_f32),
    );

    // Once: emit 80 particles in a single burst at spawn.
    let spawner = Spawner::once(80.0_f32.into(), true);

    let effect = EffectAsset::new(256, spawner, module)
        .with_name("explosion")
        .init(init_pos)
        .init(init_vel)
        .init(init_lifetime)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        });

    let handle = effects.add(effect);
    commands.insert_resource(ExplosionEffect(handle));
}

pub(super) fn build_gate_flash_effect(
    mut effects: ResMut<Assets<EffectAsset>>,
    mut commands: Commands,
) {
    // Cyan-white flash gradient. Fades fast — gate jumps are
    // instantaneous events, the visual should pop and disappear.
    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, Vec4::new(0.85, 1.0, 1.0, 1.0));
    color_gradient.add_key(0.4, Vec4::new(0.45, 0.85, 1.0, 0.8));
    color_gradient.add_key(1.0, Vec4::new(0.10, 0.30, 0.70, 0.0));

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.50));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let mut module = Module::default();

    let init_pos = SetPositionSphereModifier {
        center: module.lit(Vec3::ZERO),
        radius: module.lit(0.10),
        dimension: ShapeDimension::Volume,
    };
    let init_vel = SetVelocitySphereModifier {
        center: module.lit(Vec3::ZERO),
        speed: module.lit(3.0),
    };
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        module.lit(0.5_f32),
    );

    let spawner = Spawner::once(40.0_f32.into(), true);

    let effect = EffectAsset::new(128, spawner, module)
        .with_name("gate_flash")
        .init(init_pos)
        .init(init_vel)
        .init(init_lifetime)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        });

    let handle = effects.add(effect);
    commands.insert_resource(GateFlashEffect(handle));
}

/// Watch the EventsLog for new "warp-y" events and spawn a one-shot
/// flash effect at the relevant world position. Currently handles:
/// - `ship_gate_jumped` → flash at both src + dest gates
/// - `ship_spawned` → flash at the new ship's position (warp-in)
///
/// `Local<u64>` high-water tick mark prevents re-firing flashes
/// for events we've already processed.
pub(super) fn event_driven_flashes(
    mut commands: Commands,
    sim: Res<crate::sim::Sim>,
    events: Res<crate::sim::EventsLog>,
    flash: Option<Res<GateFlashEffect>>,
    mut last_tick: Local<u64>,
) {
    let Some(flash) = flash else { return };
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
    use sim_core::agents::ship::ShipPosition;

    if events.0.is_empty() {
        return;
    }

    let spawn_flash = |commands: &mut Commands, x: f32, y: f32, label: &str| {
        let world = Vec3::new(x * SCALE_FACTOR, 0.5, y * SCALE_FACTOR);
        // ParticleEffectBundle bundles its own Transform +
        // GlobalTransform; spawning them as separate tuple entries
        // panics on duplicate components.
        commands.spawn((
            ParticleEffectBundle {
                transform: Transform::from_translation(world),
                ..ParticleEffectBundle::new(flash.0.clone())
            },
            ExplosionLifetime(Timer::from_seconds(1.0, TimerMode::Once)),
            Name::new(format!("Flash::{label}")),
        ));
    };

    // Single pass over the events log: track high-water tick AND
    // dispatch flashes inline. The gate-position lookup is built
    // lazily on the FIRST ship_gate_jumped event seen this frame —
    // in busy sims most ticks have no gate jumps even though the
    // events log gets pushed every frame, so deferring saves the
    // two hecs queries that earlier always-build versions cost.
    let mut new_high = *last_tick;
    let mut gate_pos: Option<std::collections::HashMap<String, (f32, f32)>> = None;
    for (tick, ev) in events.0.iter() {
        if *tick <= *last_tick {
            continue;
        }
        if *tick > new_high {
            new_high = *tick;
        }
        match ev.get("kind").and_then(|k| k.as_str()) {
            Some("ship_gate_jumped") => {
                if gate_pos.is_none() {
                    let body_pos: std::collections::HashMap<String, (f32, f32)> = sim
                        .store
                        .world
                        .query::<(&BodyIdentity, &BodyOrbit)>()
                        .iter()
                        .map(|(_, (b, o))| (b.body_id.clone(), o.universe_position()))
                        .collect();
                    let mut gp: std::collections::HashMap<String, (f32, f32)> =
                        std::collections::HashMap::new();
                    for (_, (id, loc)) in sim
                        .store
                        .world
                        .query::<(&FacilityIdentity, &FacilityLocation)>()
                        .iter()
                    {
                        if id.facility_type == "gate" {
                            if let Some(&p) = body_pos.get(&id.body_id) {
                                gp.insert(loc.location_name.clone(), p);
                            }
                        }
                    }
                    gate_pos = Some(gp);
                }
                let gp = gate_pos.as_ref().unwrap();
                for key in &["src_gate", "dest_gate"] {
                    let Some(loc_name) = ev.get(*key).and_then(|s| s.as_str()) else {
                        continue;
                    };
                    let Some(&(x, y)) = gp.get(loc_name) else {
                        continue;
                    };
                    spawn_flash(&mut commands, x, y, loc_name);
                }
            }
            Some("ship_spawned") => {
                // Look up the new ship's position from the sim —
                // the event payload doesn't carry coordinates, just
                // the agent_id. reconcile_new_ships will materialise
                // the Bevy entity later this frame; we don't need to
                // wait.
                let Some(ship_id) = ev.get("id").and_then(|s| s.as_str()) else {
                    continue;
                };
                let Some(&entity) = sim.store.ship_by_id.get(ship_id) else {
                    continue;
                };
                let Ok(mut q) = sim.store.world.query_one::<&ShipPosition>(entity) else {
                    continue;
                };
                let Some(pos) = q.get() else { continue };
                let (x, y) = pos.position;
                spawn_flash(&mut commands, x, y, ship_id);
            }
            Some("construction_completed") => {
                // Construction-site materialisations carry an
                // explicit (x, y) payload — pull straight off the
                // event without consulting the sim.
                let pos = ev.get("position");
                let x = pos.and_then(|p| p.get("x")).and_then(|v| v.as_f64());
                let y = pos.and_then(|p| p.get("y")).and_then(|v| v.as_f64());
                if let (Some(x), Some(y)) = (x, y) {
                    let label = ev
                        .get("facility_id")
                        .and_then(|s| s.as_str())
                        .unwrap_or("construction");
                    spawn_flash(&mut commands, x as f32, y as f32, label);
                }
            }
            _ => {}
        }
    }
    *last_tick = new_high;
}

/// Despawn explosion entities once their lifetime timer expires.
/// 1.5× the longest particle lifetime so the entity sticks around
/// long enough to render every particle, then disappears.
pub(super) fn tick_explosion_lifetimes(
    mut commands: Commands,
    time: Res<Time>,
    mut explosions: Query<(Entity, &mut ExplosionLifetime)>,
) {
    for (entity, mut life) in explosions.iter_mut() {
        if life.0.tick(time.delta()).finished() {
            commands.entity(entity).despawn_recursive();
        }
    }
}
/// hidden, so docked ships read as engines-off instantly without a
/// per-instance EffectInitializers mutation.
#[allow(clippy::type_complexity)]
pub(super) fn sync_engine_trails(
    sim: Res<Sim>,
    ships: Query<(&ShipEntity, &Transform), Without<EngineTrailFor>>,
    mut trails: Query<
        (&EngineTrailFor, &mut Transform, &mut Visibility),
        Without<ShipEntity>,
    >,
) {
    use sim_core::agents::ship::ShipPosition;
    if ships.is_empty() {
        return;
    }
    // Build the per-ship lookup with ONE pass over the hecs world
    // instead of one query_one per trail per frame. At 282 ships /
    // 60 fps the previous shape was ~17k query_ones/sec just for
    // the docked-at gate; that quietly dominated the particle
    // system's frame cost. One world.query::<(ShipIdentity,
    // ShipPosition)>() walks every ship once and stores
    // (docked, sim_id) pairs into a HashMap keyed by string.
    use sim_core::agents::ship::ShipIdentity;
    let docked_by_id: std::collections::HashMap<String, bool> = sim
        .store
        .world
        .query::<(&ShipIdentity, &ShipPosition)>()
        .iter()
        .map(|(_, (id, pos))| (id.id.clone(), pos.docked_at.is_some()))
        .collect();

    // Stash both transform AND base_scale so the trail can size
    // itself per-ship: tiny couriers get a small trail, massive
    // haulers a big one. base_scale already factors SHIP_GLB_SCALE
    // × size_multiplier; divide out the constant to recover the
    // class-size-only factor.
    let lookup: std::collections::HashMap<&str, (&Transform, f32)> = ships
        .iter()
        .map(|(s, t)| (s.sim_id.as_str(), (t, s.base_scale / SHIP_GLB_SCALE)))
        .collect();
    for (trail_for, mut trail_xf, mut vis) in trails.iter_mut() {
        let Some(&(ship_xf, size_mult)) = lookup.get(trail_for.0.as_str()) else {
            continue;
        };
        // Aft offset in ship-local frame (-Z behind nose), rotated
        // into world space. The native gltf hull is ~10 units long
        // × SHIP_GLB_SCALE 0.025 × size_mult ≈ 0.25 × size_mult wu
        // in world units. Pushing the emitter ~half a hull length
        // back (0.13 × size_mult) plants it at the engine nozzles;
        // particles emerge from the model itself rather than the
        // big visible gap the old 1.5 × size_mult offset caused.
        let aft = ship_xf.rotation * Vec3::new(0.0, 0.0, -0.13 * size_mult);
        trail_xf.translation = ship_xf.translation + aft;
        trail_xf.rotation = ship_xf.rotation;
        trail_xf.scale = Vec3::splat(size_mult.clamp(0.5, 4.0));

        // Engines-off when docked. Falls through to Visible if the
        // sim lookup fails (better-than-nothing for racing spawns
        // where the index hasn't caught up).
        let docked = docked_by_id.get(&trail_for.0).copied().unwrap_or(false);
        let want = if docked {
            Visibility::Hidden
        } else {
            Visibility::Visible
        };
        if *vis != want {
            *vis = want;
        }
    }
}

/// Despawn engine-trail entities whose ship sim_id is no longer
/// in the sim's index — sibling analogue of `cleanup_stale_ships`
/// for the ParticleEffectBundle.
pub(super) fn cleanup_stale_engine_trails(
    mut commands: Commands,
    sim: Res<Sim>,
    trails: Query<(Entity, &EngineTrailFor)>,
) {
    for (entity, trail_for) in trails.iter() {
        if !sim.store.ship_by_id.contains_key(&trail_for.0) {
            commands.entity(entity).despawn_recursive();
        }
    }
}
