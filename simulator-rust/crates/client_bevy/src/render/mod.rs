//! Render mirror — Bevy entities that shadow the sim's hecs entities,
//! sized+positioned each frame by reading directly from the sim
//! Resource. Bundle 2c scope: placeholder geometry (boxes for ships,
//! spheres for bodies, cylinders for facilities) so we can verify the
//! scaling + camera feel at the 1500-ship stress. Proper procedural
//! ship meshes come in Bundle 3.

use bevy::prelude::*;
use bevy_egui::EguiContexts;
use bevy_hanabi::prelude::*;
use sim_core::agents::{
    celestial_body::{BodyBiome, BodyIdentity, BodyOrbit},
    facility::{FacilityIdentity, FacilityLocation},
    ship::{ShipIdentity, ShipPosition, ShipTransit},
};

use crate::sim::Sim;
use crate::ui::{SelectedFacility, SelectedShip};

mod asteroid;
mod nebula;
mod planet;
mod starfield;
use asteroid::{
    build_asteroid_mesh, build_field as build_asteroid_field,
    config_for_body as asteroid_config_for_body, material_for_asteroid, seed_for as asteroid_seed_for,
    AsteroidConfig,
};
use nebula::{nebula_params, NebulaMaterial, NebulaMaterialPlugin};
use planet::{
    cloud_for_body, params_for_body, rings_for_body, CloudMaterial, CloudMaterialPlugin,
    CloudParams, HaloMaterial, HaloMaterialPlugin, HaloParams, PlanetMaterial,
    PlanetMaterialPlugin, StarProfile,
};
use starfield::StarfieldPlugin;

/// Scale factor from universe units → world units. Bumped from
/// Godot's `GameState.SCALE_FACTOR = 10` because Bevy renders the
/// sun + bodies at a coherent absolute size hierarchy (sun ~35 wu,
/// planets ~20 wu) — at 10× spread, inner-system orbital radii
/// (~4-15 sim units → 40-150 wu) clipped into the sun, and
/// inter-system distances were just a few hundred wu so systems
/// blended together at galactic zoom. 60× spreads everything: a
/// Mercury-like 4 sim-unit orbit lands 240 wu out from a 35-wu
/// sun, and inter-system gaps land in the multi-thousand-wu range
/// so each system reads as its own cluster against the starfield.
/// Camera initial distance + far clip + nebula / star shell radii
/// scale with this — keep them in sync if it changes.
pub const SCALE_FACTOR: f32 = 100.0;

/// Visual size hierarchy (world units). One coherent ladder so
/// proportions read at any zoom: a medium ship = 1 wu, and every
/// other class scales relative to it.
///
/// ```text
///   sun            ~14 wu  (biggest, anchors each system)
///   planet body    ~7 wu   (visible, sub-orbit-radius)
///   moon / asteroid ~4 wu  (between station and planet)
///   station         ~4 wu  (mid-tier dock)
///   gate ring       ~6 wu  (wider, navigation portal)
///   ship (large)    ~5 wu  (hauler)
///   ship (medium)   ~1 wu  (freighter / tanker / miner)
///   ship (small)    ~0.5 wu (courier)
/// ```
///
/// Sized small relative to `SCALE_FACTOR = 60` orbital distances:
/// inner-system bodies at ~5 sim units → 300 wu orbit, so a 7-wu
/// planet occupies a few percent of its orbit radius (real-ish
/// solar-system feel). Bigger bodies looked correct in isolation
/// but dominated their own orbits at the new spread.
const BODY_SIZE: f32 = 4.0;

/// Uniform scale applied to a freshly-spawned station SceneBundle.
/// The Godot GLBs are ~80-unit hulls in their source coords; 0.125
/// brings them down to ≈10 wu — 10× a medium ship, half a planet.
/// **The one knob to twist if stations look wrong** —
/// `FACILITY_SIZE` doesn't exist anymore; that was the cylinder-
/// placeholder height before GLBs landed.
const STATION_SCALE: f32 = 0.05;
/// Gates get a wider scale than stations because the ring
/// silhouette needs to read as a portal you fly through, not a
/// dense bulk. ~6 wu across.
const GATE_SCALE: f32 = 0.075;
/// Uniform scale applied to a freshly-spawned ship SceneBundle.
/// The Godot ship GLBs (Spitfire/Dispatcher/Imperial/Challenger/
/// Executioner) are ~10-unit hulls in their source coords; 0.025
/// brings a Medium ship to ≈0.25 wu — same order as the cuboid
/// placeholders we replaced. `ship_size_multiplier` layers tier
/// scale on top so a Massive hauler reads ~3.5× this.
const SHIP_GLB_SCALE: f32 = 0.025;
pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        // Stations preload in Startup so the Handle<Scene>s exist
        // by the time spawn_mirror_entities runs in PostStartup.
        // Asset bytes load asynchronously; SceneBundle just shows
        // an empty parent until the gltf streams in (typically a
        // frame or two on local disk).
        app.add_plugins((
                PlanetMaterialPlugin,
                CloudMaterialPlugin,
                HaloMaterialPlugin,
                NebulaMaterialPlugin,
                StarfieldPlugin,
                HanabiPlugin,
            ))
            .init_resource::<ShipTrails>()
            .add_systems(
                Startup,
                (
                    load_station_models,
                    load_ship_models,
                    build_engine_trail_effect,
                    build_explosion_effect,
                    build_gate_flash_effect,
                ),
            )
            // Nebulas spawn at PostStartup (they're stable backdrop
            // — the user wants them visible in the menu scene too).
            // Game-world entities (ships / facilities / bodies / suns)
            // wait for `OnEnter(InGame)` so the title screen reads
            // as its own scene, not the world hiding behind a label.
            .add_systems(PostStartup, spawn_nebulae)
            // Tick-position snapshot. Runs in FixedUpdate AFTER
            // sim::tick_sim so the captured `curr` reflects the
            // freshly-applied tick state. sync_positions / follow_
            // facilities_to_bodies (in Update) lerp prev → curr by
            // `Time::<Fixed>::overstep_fraction()` for smooth motion
            // independent of sim cadence (8 tps × tick_mult).
            .add_systems(
                FixedUpdate,
                snapshot_tick_positions
                    .after(crate::sim::tick_sim)
                    .run_if(in_state(crate::AppState::InGame)),
            )
            // `.after(load_world)` is critical: both crates schedule
            // OnEnter(InGame) systems and Bevy gives no default
            // ordering between them. Without the explicit dependency
            // render's spawn pass would sometimes run before sim
            // had populated the AgentStore, so bodies / suns came
            // up empty until you bounced back to the main menu.
            .add_systems(
                bevy::prelude::OnEnter(crate::AppState::InGame),
                (spawn_mirror_entities, spawn_system_suns, reset_camera_for_game)
                    .after(crate::sim::load_world),
            )
            .add_systems(
                bevy::prelude::OnExit(crate::AppState::InGame),
                cleanup_game_world,
            )
            // Two Update tuples — Bevy caps system param tuples at 16
            // and the render set has outgrown that. Split is purely
            // mechanical (no ordering constraints between them).
            //
            // Both gated on `AppState::InGame` so menu scene doesn't
            // run sync / raycast / reconcile work — also stops
            // `reconcile_new_ships` from re-spawning ship entities
            // immediately after `cleanup_game_world` despawns them.
            .add_systems(
                Update,
                (
                    sync_positions,
                    follow_facilities_to_bodies,
                    rotate_spinners,
                    rotate_tumblers,
                    highlight_selected,
                    draw_selection_rings,
                    update_ship_trails,
                    draw_ship_trails,
                    draw_transit_intent_lines,
                    draw_gate_rings,
                    draw_orbit_rings,
                    draw_construction_sites,
                    raycast_select,
                    cleanup_stale_ships,
                    reconcile_new_ships,
                    reconcile_new_facilities,
                )
                    .run_if(in_state(crate::AppState::InGame)),
            )
            .add_systems(
                Update,
                (
                    raycast_context_menu,
                    apply_camera_follow,
                    sync_engine_trails,
                    cleanup_stale_engine_trails,
                    tick_explosion_lifetimes,
                    event_driven_flashes,
                )
                    .run_if(in_state(crate::AppState::InGame)),
            );
    }
}

/// Preloaded `Handle<Scene>` for each station GLB. We map the sim's
/// `FacilityIdentity.facility_type` string onto a slot here at spawn
/// time — same mapping the Godot client used (see
/// `client/scripts/world/facility.gd::TYPE_MODELS`) so the visual
/// vocabulary stays consistent across the two clients.
#[derive(Resource)]
struct StationModels {
    station: Handle<Scene>,
    outpost: Handle<Scene>,
    mining_rig: Handle<Scene>,
    refinery: Handle<Scene>,
    factory: Handle<Scene>,
    farm: Handle<Scene>,
    gate: Handle<Scene>,
    shipyard: Handle<Scene>,
    default: Handle<Scene>,
}

impl StationModels {
    fn for_type(&self, facility_type: &str) -> Handle<Scene> {
        match facility_type {
            "station" => self.station.clone(),
            "outpost" => self.outpost.clone(),
            "mining_rig" => self.mining_rig.clone(),
            "refinery" => self.refinery.clone(),
            "factory" => self.factory.clone(),
            "farm" => self.farm.clone(),
            "gate" => self.gate.clone(),
            "shipyard" => self.shipyard.clone(),
            _ => self.default.clone(),
        }
    }
}

fn load_station_models(asset_server: Res<AssetServer>, mut commands: Commands) {
    // glTF subasset path: "<file>.glb#Scene0" loads the first
    // (typically only) scene the file declares. The Bevy GltfPlugin
    // ships in DefaultPlugins.
    commands.insert_resource(StationModels {
        station: asset_server.load("stations/station01.glb#Scene0"),
        outpost: asset_server.load("stations/station05.glb#Scene0"),
        mining_rig: asset_server.load("stations/station03_base.glb#Scene0"),
        refinery: asset_server.load("stations/station02_base.glb#Scene0"),
        factory: asset_server.load("stations/station06_base.glb#Scene0"),
        farm: asset_server.load("stations/station05.glb#Scene0"),
        gate: asset_server.load("stations/station02_ring.glb#Scene0"),
        shipyard: asset_server.load("stations/station06_base.glb#Scene0"),
        default: asset_server.load("stations/station01.glb#Scene0"),
    });
}

/// Preloaded `Handle<Scene>` for each ship-class GLB. Mapping
/// matches the Godot client's authored hulls (lifted from
/// `client/assets/ships/`):
/// - **courier** → Spitfire (sleek fighter, fast)
/// - **freighter** → Dispatcher (mid transport)
/// - **hauler** → Imperial (largest hull)
/// - **tanker** → Challenger (workhorse mid-weight)
/// - **miner** → Executioner (industrial bulk)
///
/// Faction tinting is lost vs. the placeholder era — the GLBs ship
/// with their own painted materials. We could overwrite them
/// per-faction in a later pass, but the user explicitly preferred
/// the authored look over the procedural cuboids.
#[derive(Resource)]
struct ShipModels {
    courier: Handle<Scene>,
    freighter: Handle<Scene>,
    hauler: Handle<Scene>,
    tanker: Handle<Scene>,
    miner: Handle<Scene>,
    default: Handle<Scene>,
}

impl ShipModels {
    fn for_class(&self, class: &str) -> Handle<Scene> {
        match class {
            "courier" => self.courier.clone(),
            "freighter" => self.freighter.clone(),
            "hauler" => self.hauler.clone(),
            "tanker" => self.tanker.clone(),
            "miner" => self.miner.clone(),
            _ => self.default.clone(),
        }
    }
}

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

fn build_engine_trail_effect(
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

fn build_explosion_effect(
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

fn build_gate_flash_effect(
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
fn event_driven_flashes(
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
fn tick_explosion_lifetimes(
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

fn load_ship_models(asset_server: Res<AssetServer>, mut commands: Commands) {
    commands.insert_resource(ShipModels {
        courier: asset_server.load("ships/Spitfire.gltf#Scene0"),
        freighter: asset_server.load("ships/Dispatcher.gltf#Scene0"),
        hauler: asset_server.load("ships/Imperial.gltf#Scene0"),
        tanker: asset_server.load("ships/Challenger.gltf#Scene0"),
        miner: asset_server.load("ships/Executioner.gltf#Scene0"),
        default: asset_server.load("ships/Dispatcher.gltf#Scene0"),
    });
}

/// Marker components so the per-frame position-sync query can narrow
/// its work + so click-to-select can tell categories apart later.
/// Marker on every game-only render entity (ships, facilities,
/// bodies, suns, sun children, engine trails). Lets
/// `cleanup_game_world` despawn the whole game scene cleanly when
/// the user returns to the main menu, without disturbing the
/// always-on backdrop (starfield, nebulas) or UI/camera.
#[derive(Component)]
pub struct GameWorld;

#[derive(Component)]
pub struct ShipEntity {
    pub sim_id: String,
    /// Per-ship Transform.scale baseline derived from `ShipIdentity.size`
    /// at spawn. Tiny=0.25 → Massive=5.0 so silhouettes encode the
    /// hull tier alongside the class proportions baked into
    /// `ship_dimensions`. `highlight_selected` multiplies this by
    /// `SELECT_SCALE` for the chosen ship — same layering pattern
    /// `FacilityEntity.base_scale` uses.
    pub base_scale: f32,
}

#[derive(Component)]
pub struct FacilityEntity {
    pub sim_id: String,
    /// Per-model spawn scale (STATION_SCALE / GATE_SCALE). Stored
    /// because `highlight_selected` writes `Transform::scale` every
    /// frame, and without this we'd lose the model scale the moment
    /// the selection system ran. The selection scale is layered on
    /// top: `xf.scale = base_scale * (selected ? SELECT_SCALE : 1.0)`.
    pub base_scale: f32,
    /// Body the facility orbits. Per-frame the follow system reads
    /// this body's current `BodyOrbit` position and offsets it via
    /// `sim_core::agents::facility::facility_offset_position` — the
    /// SAME helper the sim uses to pin docked ships and aim transit
    /// arrivals. Single source of truth = no station/ship drift.
    pub body_id: String,
}

#[derive(Component)]
pub struct BodyEntity {
    pub sim_id: String,
}

/// Per-entity tick interpolation buffer. Sim ticks at 8/sec
/// (125 ms cadence) but render runs at 60+ fps; without
/// interpolation positions snap on every tick boundary, producing
/// the "stuttery" look at low world-speed multipliers. Each
/// FixedUpdate after `tick_sim`, [`snapshot_tick_positions`]
/// rolls `curr → prev` and stamps the new sim position into
/// `curr`. [`sync_positions`] / [`follow_facilities_to_bodies`]
/// lerp between the two using `Time::<Fixed>::overstep_fraction()`
/// so motion is smooth at any render cadence. Coords are universe-
/// space (`(f32, f32)` x/z), pre-`SCALE_FACTOR`. Attached to ships
/// and bodies; facilities follow their bodies so they don't need
/// their own buffer.
#[derive(Component, Clone, Copy)]
pub struct InterpPos {
    prev: (f32, f32),
    curr: (f32, f32),
}

impl InterpPos {
    fn at(p: (f32, f32)) -> Self {
        Self { prev: p, curr: p }
    }

    fn lerp(&self, alpha: f32) -> (f32, f32) {
        let a = alpha.clamp(0.0, 1.0);
        (
            self.prev.0 + (self.curr.0 - self.prev.0) * a,
            self.prev.1 + (self.curr.1 - self.prev.1) * a,
        )
    }
}

/// Shared body sphere + fallback material for the celestial-body
/// renderer. Ships used to share a placeholder pool here too; that
/// path was deleted in favour of authored GLBs (`ShipModels`).
#[derive(Resource)]
struct PlaceholderAssets {
    body_mesh: Handle<Mesh>,
    /// Kept around so the loop that builds it stays valid; bodies
    /// now use `PlanetMaterial` (per-body procedural) so this isn't
    /// referenced post-spawn.
    #[allow(dead_code)]
    body_mat: Handle<StandardMaterial>,
}

/// Multiplier applied to the per-class cuboid based on the ship's
/// `ShipIdentity.size` tier. Layered on top of `ship_dimensions` so
/// class encodes role-shape and size encodes hull tier — a Tiny
/// hauler still reads as a hauler proportionally, just shrunk.
///
/// Range matches the user's "0.25 → 1 → 5" hierarchy: Medium = 1.0
/// (no scale), Tiny = 0.25 (sub-pixel courier), Massive = 5.0
/// (fleet flagship). The same scale also drives `highlight_selected`
/// so the per-ship `Transform.scale` reads from one source.
fn ship_size_multiplier(size: sim_core::simulation::config::ShipSize) -> f32 {
    use sim_core::simulation::config::ShipSize;
    match size {
        ShipSize::Tiny => 0.25,
        ShipSize::Small => 0.5,
        ShipSize::Medium => 1.0,
        ShipSize::Large => 1.5,
        ShipSize::Huge => 2.0,
        ShipSize::Massive => 3.5,
    }
}

/// Per-frame rotation tag for child entities (ring planes, cloud
/// shells, sun molten-layer shells). One small system iterates all
/// of them and rotates by `axis * speed * dt` — same trick Godot's
/// `_process` uses on rings/clouds/sun. Local-space rotation, so a
/// tilted ring spins around its own up axis instead of yawing the
/// whole plane.
#[derive(Component)]
struct Spin {
    axis: Vec3,
    speed_rad_per_sec: f32,
}

fn rotate_spinners(time: Res<Time>, mut q: Query<(&Spin, &mut Transform)>) {
    let dt = time.delta_seconds();
    for (spin, mut xf) in q.iter_mut() {
        let q_rot = Quat::from_axis_angle(spin.axis, spin.speed_rad_per_sec * dt);
        xf.rotate_local(q_rot);
    }
}

/// Three-axis angular velocity (rad/s). Asteroids tumble on all
/// three axes simultaneously rather than spinning cleanly on one,
/// matching `procedural_asteroid.gd`'s `_process` behaviour.
#[derive(Component)]
struct Tumble(Vec3);

fn rotate_tumblers(time: Res<Time>, mut q: Query<(&Tumble, &mut Transform)>) {
    let dt = time.delta_seconds();
    for (t, mut xf) in q.iter_mut() {
        xf.rotate_local_x(t.0.x * dt);
        xf.rotate_local_y(t.0.y * dt);
        xf.rotate_local_z(t.0.z * dt);
    }
}

/// Build a flat annulus mesh on the XZ plane (galactic plane).
/// Bevy's `Annulus` primitive lives on the XY plane by default, so
/// we mesh it then rotate the vertex buffer 90° around X to land on
/// XZ. Single-sided geometry — the spawn site uses `cull_mode: None`
/// so the ring is visible from above and below.
fn annulus_mesh(inner: f32, outer: f32, segments: u32) -> Mesh {
    use bevy::math::primitives::Annulus;
    let mut mesh = Annulus::new(inner, outer)
        .mesh()
        .resolution(segments.max(8) as usize)
        .build();
    // Annulus mesh is XY-plane (normal +Z). Rotate vertices to XZ
    // (normal +Y) so the disk lies on the orbital plane.
    let rot = Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2);
    if let Some(bevy::render::mesh::VertexAttributeValues::Float32x3(positions)) =
        mesh.attribute_mut(Mesh::ATTRIBUTE_POSITION)
    {
        for p in positions.iter_mut() {
            let v = rot * Vec3::from_array(*p);
            *p = v.to_array();
        }
    }
    if let Some(bevy::render::mesh::VertexAttributeValues::Float32x3(normals)) =
        mesh.attribute_mut(Mesh::ATTRIBUTE_NORMAL)
    {
        for n in normals.iter_mut() {
            let v = rot * Vec3::from_array(*n);
            *n = v.to_array();
        }
    }
    mesh
}

/// `OnExit(InGame)` cleanup: despawn everything tagged `GameWorld`.
/// Returns the scene to its main-menu shape — starfield + nebulas
/// remain (they're untagged), but bodies / ships / facilities /
/// suns / engine trails all go.
fn cleanup_game_world(
    mut commands: Commands,
    entities: Query<Entity, With<GameWorld>>,
) {
    let mut count = 0usize;
    for e in entities.iter() {
        commands.entity(e).despawn_recursive();
        count += 1;
    }
    info!("client_bevy: cleaned up {} game-world entities", count);
}

/// `OnEnter(InGame)` camera setup. Snap the orbit camera back to
/// its initial galactic-overview pose so the user sees the inner
/// solar system the moment they hit Start, regardless of whatever
/// pose was active during the menu (or last session before they
/// returned to main menu).
fn reset_camera_for_game(
    mut q: Query<(&mut crate::camera::OrbitCamera, &mut Transform)>,
) {
    let Ok((mut orbit, mut xf)) = q.get_single_mut() else { return };
    *orbit = crate::camera::OrbitCamera::initial();
    *xf = orbit.transform();
}

#[allow(clippy::too_many_arguments)]
fn spawn_mirror_entities(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut planet_materials: ResMut<Assets<PlanetMaterial>>,
    mut cloud_materials: ResMut<Assets<CloudMaterial>>,
    sim: Res<Sim>,
    stations: Res<StationModels>,
    ships: Res<ShipModels>,
    engine_trail: Res<EngineTrailEffect>,
) {
    // Ships now use authored GLBs (per-class scenes streamed via
    // ShipModels). The placeholder cuboid + faction-emissive material
    // pool was deleted with the rest of Bundle 4a's procedural ship
    // path. Bodies still use shared sphere mesh + StandardMaterial.
    let assets = PlaceholderAssets {
        body_mesh: meshes.add(Sphere::new(BODY_SIZE * 0.5)),
        body_mat: materials.add(StandardMaterial {
            base_color: Color::srgb(0.45, 0.55, 0.75),
            metallic: 0.0,
            perceptual_roughness: 0.95,
            ..default()
        }),
    };

    let world = &sim.store.world;
    let mut ship_count = 0;
    let mut facility_count = 0;
    let mut body_count = 0;

    // Ships. Spawn one Bevy entity per hecs ship; the per-frame sync
    // copies position across each tick. We grab the full universe
    // position (system offset + local position) from `ShipPosition`.
    for (_e, (id, pos)) in world.query::<(&ShipIdentity, &ShipPosition)>().iter() {
        let (x, y) = pos.position;
        // GLB hulls are ~10 native units; SHIP_GLB_SCALE brings them
        // to ~0.25 wu, then size_multiplier layers tier scale.
        let base_scale = SHIP_GLB_SCALE * ship_size_multiplier(id.size);
        // Spawn the engine-trail effect as a sibling (not a child) so
        // it doesn't inherit the ship's tiny scale. Sync system below
        // glues its transform to the ship each frame.
        commands.spawn((
            ParticleEffectBundle::new(engine_trail.0.clone()),
            EngineTrailFor(id.id.clone()),
            GameWorld,
            Name::new(format!("EngineTrail::{}", id.id)),
        ));
        commands.spawn((
            SceneBundle {
                scene: ships.for_class(&id.class),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR)
                    .with_scale(Vec3::splat(base_scale)),
                ..default()
            },
            ShipEntity {
                sim_id: id.id.clone(),
                base_scale,
            },
            InterpPos::at((x, y)),
            GameWorld,
            Name::new(format!("Ship::{}", id.id)),
        ));
        ship_count += 1;
    }

    // Bodies — always at their orbit's current universe position.
    // Two render paths split on `body_type`:
    //   - `asteroid` / `belt`: lumpy displaced UV-sphere mesh +
    //     planet shader with rocky palette + multi-axis Tumble.
    //   - everything else (planet, moon, gas-giant): smooth ico
    //     sphere + PlanetMaterial + optional rings + cloud shell.
    //
    // Children inherit the parent's Transform via Bevy's
    // GlobalTransform propagation, so rings / clouds orbit with
    // their planet for free.
    let body_radius = BODY_SIZE * 0.5;
    for (_e, (id, orbit, biome)) in world
        .query::<(&BodyIdentity, &BodyOrbit, &BodyBiome)>()
        .iter()
    {
        let (x, y) = orbit.universe_position();
        let xf = Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR);
        let is_rock = matches!(id.body_type.as_str(), "asteroid" | "belt");
        if is_rock {
            // Asteroid / belt path. Mirrors orbital_body.gd's
            // split:
            //   - asteroid: lead rock + 14-baby spherical-shell
            //     halo around it.
            //   - belt: no lead, 55-baby disc.
            let cfg = asteroid_config_for_body(&id.body_id, &biome.biome);
            let seed = asteroid_seed_for(&id.body_id);
            let is_belt = id.body_type == "belt";

            // Shared baby mesh + material — we spawn many entities
            // but they all reference the same handles so Bevy's
            // renderer batches them into one draw call. Smaller
            // poly count than the lead since babies are far away.
            let baby_mesh_handle = {
                let baby_cfg = AsteroidConfig {
                    radial_segments: 10,
                    rings: 6,
                    deformation: 0.45,
                    deform_frequency: 1.8,
                    deform_octaves: 2,
                    ..cfg.clone()
                };
                meshes.add(build_asteroid_mesh(seed.wrapping_add(0xBABE), 1.0, &baby_cfg))
            };
            let baby_mat_handle =
                planet_materials.add(material_for_asteroid(&cfg, &id.body_id));

            // Parent: the body's transform anchor. For asteroid
            // bodies the parent also carries the lead-rock mesh;
            // for belt bodies the parent is just an empty
            // SpatialBundle and only the children have geometry.
            let mut parent_cmd = if is_belt {
                commands.spawn((
                    SpatialBundle::from_transform(xf),
                    BodyEntity {
                        sim_id: id.body_id.clone(),
                    },
                    InterpPos::at((x, y)),
                    GameWorld,
                    Name::new(format!("Body::{}", id.body_id)),
                ))
            } else {
                let lead_mesh = meshes.add(build_asteroid_mesh(seed, body_radius, &cfg));
                let lead_mat = planet_materials.add(material_for_asteroid(&cfg, &id.body_id));
                commands.spawn((
                    MaterialMeshBundle::<PlanetMaterial> {
                        mesh: lead_mesh,
                        material: lead_mat,
                        transform: xf,
                        ..default()
                    },
                    BodyEntity {
                        sim_id: id.body_id.clone(),
                    },
                    InterpPos::at((x, y)),
                    Tumble(cfg.tumble),
                    GameWorld,
                    Name::new(format!("Body::{}", id.body_id)),
                ))
            };

            let field = build_asteroid_field(&id.body_id, &id.body_type, body_radius);
            parent_cmd.with_children(|parent| {
                for (idx, rock) in field.iter().enumerate() {
                    let mut t = Transform::from_translation(rock.position);
                    t.rotation = rock.rotation;
                    t.scale = Vec3::splat(rock.scale);
                    parent.spawn((
                        MaterialMeshBundle::<PlanetMaterial> {
                            mesh: baby_mesh_handle.clone(),
                            material: baby_mat_handle.clone(),
                            transform: t,
                            ..default()
                        },
                        Tumble(rock.tumble),
                        Name::new(format!("Rock::{}::{}", id.body_id, idx)),
                    ));
                }
            });

            body_count += 1;
            continue;
        }

        let mat = planet_materials.add(PlanetMaterial {
            params: params_for_body(&id.body_id, &biome.biome),
        });
        let rings = rings_for_body(&id.body_id, &biome.biome);
        let cloud = cloud_for_body(&id.body_id, &biome.biome);
        commands
            .spawn((
                MaterialMeshBundle::<PlanetMaterial> {
                    mesh: assets.body_mesh.clone(),
                    material: mat,
                    transform: xf,
                    ..default()
                },
                BodyEntity {
                    sim_id: id.body_id.clone(),
                },
                InterpPos::at((x, y)),
                GameWorld,
                Name::new(format!("Body::{}", id.body_id)),
            ))
            .with_children(|parent| {
                // Rings — flat annulus tilted around X. Builds one
                // mesh per ring config so per-ring colour + opacity
                // stay independent (Saturn's two bands are distinct).
                // Inner/outer multiplied by body_radius to land in
                // world units.
                for ring in &rings {
                    let mesh = meshes.add(annulus_mesh(
                        ring.inner_rel * body_radius,
                        ring.outer_rel * body_radius,
                        ring.segments,
                    ));
                    let mat = materials.add(StandardMaterial {
                        base_color: Color::srgba(
                            ring.color.x,
                            ring.color.y,
                            ring.color.z,
                            ring.color.w,
                        ),
                        alpha_mode: bevy::prelude::AlphaMode::Blend,
                        cull_mode: None, // two-sided: visible from above + below
                        unlit: true,
                        ..default()
                    });
                    let mut xf = Transform::IDENTITY;
                    xf.rotation =
                        Quat::from_rotation_x(ring.tilt_x_deg.to_radians());
                    parent.spawn((
                        PbrBundle {
                            mesh,
                            material: mat,
                            transform: xf,
                            ..default()
                        },
                        // Slow ring spin around the ring's local up
                        // axis (post-tilt). Matches Godot's
                        // `rotate_object_local(Vector3.UP, ...)`.
                        Spin {
                            axis: Vec3::Y,
                            speed_rad_per_sec: 0.06,
                        },
                        Name::new(format!("Ring::{}", id.body_id)),
                    ));
                }

                // Cloud shell — slightly larger sphere with the
                // procedural cloud shader. AlphaMode::Blend so the
                // planet underneath shows through cloud-free patches.
                if let Some(cfg) = cloud {
                    let r = body_radius * cfg.height_rel;
                    let mesh = meshes.add(Sphere::new(r).mesh().ico(3).unwrap());
                    let mat = cloud_materials.add(CloudMaterial { params: cfg.params });
                    parent.spawn((
                        MaterialMeshBundle::<CloudMaterial> {
                            mesh,
                            material: mat,
                            transform: Transform::IDENTITY,
                            ..default()
                        },
                        // Clouds drift around the planet's polar axis
                        // visibly faster than the planet itself rotates,
                        // selling the atmospheric layer.
                        Spin {
                            axis: Vec3::Y,
                            speed_rad_per_sec: 0.04,
                        },
                        Name::new(format!("Clouds::{}", id.body_id)),
                    ));
                }
            });
        body_count += 1;
    }

    // Facilities — follow their parent body, so compute body_pos from
    // the body's orbit, then apply the facility's small orbital offset
    // (same math the Godot side + sim_server use).
    let body_positions: std::collections::HashMap<String, (f32, f32)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    for (_e, (id, loc)) in world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
    {
        // Bundle 4a: GLB station models replace the cylinder
        // placeholder. Mapping mirrors the Godot client's
        // `facility.gd::TYPE_MODELS`. Gates use the ring model and
        // get a wider scale (they're navigation waypoints the
        // player needs to spot at mid-zoom). Other types use one of
        // the box/dome silhouettes scaled to fit alongside body
        // spheres.
        let body_center = body_positions
            .get(&id.body_id)
            .copied()
            .unwrap_or((0.0, 0.0));
        // Authoritative dock-point offset: same helper the sim
        // uses to pin docked ships, so render coords agree with
        // sim coords every tick.
        let (fx, fy) = sim_core::agents::facility::facility_offset_position(body_center, &id.id);
        let y_offset = 0.5; // tiny vertical so facilities don't z-fight w/ bodies
        let is_gate = id.facility_type == "gate";
        let scale = if is_gate { GATE_SCALE } else { STATION_SCALE };
        let mut transform = Transform::from_xyz(fx * SCALE_FACTOR, y_offset, fy * SCALE_FACTOR)
            .with_scale(Vec3::splat(scale));
        if is_gate {
            // Ring model's source axis is +X; rotating 90° around Y
            // puts the hole along +Z so the ring reads as an
            // upright portal a ship flies into. Same trick as
            // facility.gd's `rotation_degrees = Vector3(0, 90, 0)`.
            transform.rotate_y(std::f32::consts::FRAC_PI_2);
        }
        commands.spawn((
            SceneBundle {
                scene: stations.for_type(&id.facility_type),
                transform,
                ..default()
            },
            FacilityEntity {
                sim_id: id.id.clone(),
                base_scale: scale,
                body_id: id.body_id.clone(),
            },
            FacilityLocationRef(loc.location_name.clone()),
            GameWorld,
            Name::new(format!("Facility::{}", id.id)),
        ));
        facility_count += 1;
    }

    commands.insert_resource(assets);
    info!(
        "client_bevy: spawned {} ships, {} bodies, {} facilities as placeholder meshes",
        ship_count, body_count, facility_count
    );
}

/// Kept as a component so the facility's location name is queryable
/// later (click-to-select / inspector panels). Unused in 2c — the
/// `#[allow(dead_code)]` goes away once the details panel reads it.
#[derive(Component)]
#[allow(dead_code)]
struct FacilityLocationRef(pub String);

/// Per-frame sync: walk all ship Bevy entities, look up their hecs
/// sibling by sim_id, copy position. Bodies drift slowly so we sync
/// them too. Facilities follow their body — update together.
///
/// Bundle 2c does the naive version (hashmap lookup per entity per
/// frame). At 1600 ships this is ~1600 dict lookups per frame which
/// is trivial for a Rust hashmap — stays well under the 16.6 ms
/// budget even without optimisation. If perf ever complains the
/// cure is caching the hecs Entity handle in the Bevy component so
/// we skip the id→entity lookup.
/// Roll `curr → prev` and read the freshly-ticked sim positions
/// into `curr` for every interpolated entity. Runs in `FixedUpdate`
/// after `tick_sim` so the snapshot reflects the just-applied tick
/// state. Pair with [`sync_positions`] / [`follow_facilities_to_bodies`]
/// which read both fields on every render frame and lerp between
/// them using the fixed-update overstep.
#[allow(clippy::type_complexity)]
fn snapshot_tick_positions(
    sim: Res<Sim>,
    mut ships: Query<(&ShipEntity, &mut InterpPos), Without<BodyEntity>>,
    mut bodies: Query<(&BodyEntity, &mut InterpPos), Without<ShipEntity>>,
) {
    let world = &sim.store.world;

    let mut ship_query = world.query::<(&ShipIdentity, &ShipPosition)>();
    let ship_pos: std::collections::HashMap<&str, (f32, f32)> = ship_query
        .iter()
        .map(|(_e, (id, p))| (id.id.as_str(), p.position))
        .collect();
    for (ship, mut interp) in ships.iter_mut() {
        if let Some(&p) = ship_pos.get(ship.sim_id.as_str()) {
            interp.prev = interp.curr;
            interp.curr = p;
        }
    }

    let mut body_query = world.query::<(&BodyIdentity, &BodyOrbit)>();
    let body_pos: std::collections::HashMap<&str, (f32, f32)> = body_query
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.as_str(), orbit.universe_position()))
        .collect();
    for (body, mut interp) in bodies.iter_mut() {
        if let Some(&p) = body_pos.get(body.sim_id.as_str()) {
            interp.prev = interp.curr;
            interp.curr = p;
        }
    }
}

// Bevy system-parameter query filters are idiomatically tuple-heavy
// (exclusion between kinds). Clippy's `type_complexity` isn't a
// useful signal for this shape — quiet it at the call site instead
// of disabling the lint crate-wide.
#[allow(clippy::type_complexity)]
fn sync_positions(
    sim: Res<Sim>,
    fixed: Res<Time<Fixed>>,
    mut ships: Query<(&ShipEntity, &InterpPos, &mut Transform), Without<BodyEntity>>,
    mut bodies: Query<
        (&InterpPos, &mut Transform),
        (With<BodyEntity>, Without<ShipEntity>, Without<FacilityEntity>),
    >,
) {
    let alpha = fixed.overstep_fraction();
    let world = &sim.store.world;

    // Heading lookup is still per-tick (we only update direction
    // when the sim says transit data changed). No alloc on the
    // headed-set for idle ships — ShipTransit's transit is None.
    let mut ship_query = world.query::<(&ShipIdentity, &ShipTransit)>();
    let ship_heading: std::collections::HashMap<&str, Option<Vec3>> = ship_query
        .iter()
        .map(|(_e, (id, transit))| {
            let heading = transit.transit.as_ref().and_then(|t| {
                let (dx, dy) = t.departure_position?;
                // Heading is end-of-transit minus start. Use the
                // current InterpPos.curr later — read direction
                // from the sim's current target so it doesn't
                // wobble during the lerp toward each tick.
                let _ = (dx, dy);
                Some((dx, dy))
            });
            (id.id.as_str(), heading.map(|(dx, dy)| Vec3::new(dx, 0.0, dy)))
        })
        .collect();

    for (ship, interp, mut xf) in ships.iter_mut() {
        let (x, z) = interp.lerp(alpha);
        xf.translation.x = x * SCALE_FACTOR;
        xf.translation.z = z * SCALE_FACTOR;
        if let Some(Some(departure)) = ship_heading.get(ship.sim_id.as_str()) {
            // Face travel direction (+Z is local nose). Compute
            // from current curr-pos minus departure rather than
            // the lerped value so heading stays stable during the
            // fractional-tick interpolation.
            let dx = interp.curr.0 - departure.x;
            let dz = interp.curr.1 - departure.z;
            if dx * dx + dz * dz > 1e-6 {
                xf.rotation = Quat::from_rotation_y(dx.atan2(dz));
            }
        }
        // Docked / idle ships keep their last rotation.
    }

    for (interp, mut xf) in bodies.iter_mut() {
        let (x, z) = interp.lerp(alpha);
        xf.translation.x = x * SCALE_FACTOR;
        xf.translation.z = z * SCALE_FACTOR;
    }
}

/// Per-frame: re-pin every facility to its body's current orbit
/// position + the same dock-point offset the sim uses. Without this,
/// stations stay at their spawn-time position while bodies orbit out
/// from underneath them.
///
/// Critically, this calls `sim_core::agents::facility::facility_offset_position`
/// — the SAME helper the sim uses to (a) pin docked ships to the
/// station, (b) aim ship transit arrivals. One source of truth for
/// "where is the station?", so docked ships never drift away from
/// their station and ships approaching always arrive on-station.
#[allow(clippy::type_complexity)]
fn follow_facilities_to_bodies(
    fixed: Res<Time<Fixed>>,
    bodies: Query<(&BodyEntity, &InterpPos), Without<FacilityEntity>>,
    mut facilities: Query<
        (&FacilityEntity, &mut Transform),
        (Without<ShipEntity>, Without<BodyEntity>),
    >,
) {
    let alpha = fixed.overstep_fraction();
    // Read body positions from InterpPos (universe coords, pre-
    // SCALE_FACTOR) instead of the sim store. Same alpha as
    // sync_positions so a station stays glued to its planet
    // through the lerp — otherwise stations would orbit at the
    // tick cadence while planets glided smoothly past them.
    let body_positions: std::collections::HashMap<&str, (f32, f32)> = bodies
        .iter()
        .map(|(b, ip)| (b.sim_id.as_str(), ip.lerp(alpha)))
        .collect();

    for (fac, mut xf) in facilities.iter_mut() {
        if let Some(&body_center) = body_positions.get(fac.body_id.as_str()) {
            let (fx, fy) = sim_core::agents::facility::facility_offset_position(
                body_center,
                fac.sim_id.as_str(),
            );
            // Y stays at spawn (the small z-fight offset).
            xf.translation.x = fx * SCALE_FACTOR;
            xf.translation.z = fy * SCALE_FACTOR;
        }
    }
}

/// Per-frame system: pin every ship and facility's Transform.scale
/// to its `base_scale` (set at spawn from size tier / GLB scale).
/// Selection no longer scales the entity — `draw_selection_rings`
/// handles the visual indicator. Kept as a pin (not just a one-time
/// spawn write) so any other system that mutates Transform.scale
/// (GLB scene materialisation, future tweens) can't desync it.
#[allow(clippy::type_complexity)]
fn highlight_selected(
    mut ships: Query<(&ShipEntity, &mut Transform), (Without<FacilityEntity>, Without<BodyEntity>)>,
    mut facilities: Query<
        (&FacilityEntity, &mut Transform),
        (Without<ShipEntity>, Without<BodyEntity>),
    >,
) {
    for (ship, mut xf) in ships.iter_mut() {
        // Skip the write when the scale already matches to avoid
        // flagging transforms as changed every frame.
        if (xf.scale.x - ship.base_scale).abs() > f32::EPSILON {
            xf.scale = Vec3::splat(ship.base_scale);
        }
    }
    for (fac, mut xf) in facilities.iter_mut() {
        if (xf.scale.x - fac.base_scale).abs() > f32::EPSILON {
            xf.scale = Vec3::splat(fac.base_scale);
        }
    }
}

/// World-unit radius of the visible "sun" at each star system's
/// universe_offset. ~2× a planet body (7 wu) so the system primary
/// clearly anchors the orbital geometry. Sized small relative to
/// the inter-orbit spread so inner planets don't clip into it.
const SUN_RADIUS: f32 = 8.0;

/// One-time PostStartup spawn: place a procedural sun at every
/// star system's universe_offset. Three layers, each a child of
/// the parent sun entity so they share its position:
///
///   1. **Surface**: PlanetMaterial with `Preset::Star` — turbulent
///      yellow/orange FBM at high emission_strength so bloom paints
///      a natural corona around the boiling sphere.
///   2. **Molten outer layer**: CloudMaterial tinted hot orange,
///      slowly spinning. Reads as the chromosphere churning above
///      the photosphere.
///   3. **Halo**: HaloMaterial Fresnel shell at 1.6× radius — bright
///      at silhouette, transparent at centre, so the sun reads as
///      a corona out to a few wu past the disc.
fn spawn_system_suns(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut planet_materials: ResMut<Assets<PlanetMaterial>>,
    mut cloud_materials: ResMut<Assets<CloudMaterial>>,
    mut halo_materials: ResMut<Assets<HaloMaterial>>,
    sim: Res<Sim>,
) {
    let mut count = 0usize;
    for (name, sys) in sim.registry.systems.iter() {
        let (x, y) = sys.universe_offset;
        let profile = StarProfile::for_type(sys.star_type.as_deref());
        let r = SUN_RADIUS * profile.radius_mul;
        // Per-star seed so two systems don't render identical
        // turbulence patterns. Hash the system name, FNV-style.
        let mut h: u64 = 0xcbf29ce484222325;
        for b in name.as_bytes() {
            h ^= *b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        let star_seed = Vec3::new(
            (h as f32 / u64::MAX as f32) * 1000.0 - 500.0,
            (((h >> 21) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0,
            (((h >> 42) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0,
        );

        // Per-star meshes so each sun's halo radius scales with its
        // type. Could be cached per radius_mul if perf shows up, but
        // we have <10 stars total — negligible.
        let core_mesh = meshes.add(Sphere::new(r).mesh().ico(4).unwrap());
        let molten_mesh = meshes.add(Sphere::new(r * 1.04).mesh().ico(4).unwrap());
        let halo_mesh_inner = meshes.add(Sphere::new(r * 1.25).mesh().ico(5).unwrap());
        let halo_mesh_mid = meshes.add(Sphere::new(r * 1.6).mesh().ico(5).unwrap());
        let halo_mesh_outer = meshes.add(Sphere::new(r * 2.2).mesh().ico(5).unwrap());

        let surface_mat = planet_materials.add(PlanetMaterial {
            params: profile.star_params(star_seed),
        });
        let molten_mat = cloud_materials.add(CloudMaterial {
            params: CloudParams {
                cloud_color: profile.molten_color,
                seed_offset: star_seed * 0.7,
                cloud_opacity: 0.55,
                cloud_coverage: 0.45,
                cloud_softness: 0.20,
                cloud_frequency: 1.8,
                cloud_lacunarity: 2.1,
                cloud_gain: 0.6,
                cloud_octaves: 4,
                _pad: Vec3::ZERO,
            },
        });
        let halo_inner_mat = halo_materials.add(HaloMaterial {
            params: HaloParams {
                color: profile.halo_color,
                intensity: 0.45,
                falloff: 1.4,
                _pad: Vec2::ZERO,
            },
        });
        let halo_mid_mat = halo_materials.add(HaloMaterial {
            params: HaloParams {
                color: profile.halo_color * 0.85,
                intensity: 0.22,
                falloff: 1.0,
                _pad: Vec2::ZERO,
            },
        });
        let halo_outer_mat = halo_materials.add(HaloMaterial {
            params: HaloParams {
                color: profile.halo_color * 0.65,
                intensity: 0.10,
                falloff: 0.7,
                _pad: Vec2::ZERO,
            },
        });

        commands
            .spawn((
                MaterialMeshBundle::<PlanetMaterial> {
                    mesh: core_mesh,
                    material: surface_mat,
                    transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
                    ..default()
                },
                GameWorld,
                Name::new(format!("Sun::{}", name)),
            ))
            .with_children(|parent| {
                parent.spawn((
                    MaterialMeshBundle::<CloudMaterial> {
                        mesh: molten_mesh,
                        material: molten_mat,
                        transform: Transform::IDENTITY,
                        ..default()
                    },
                    Spin {
                        axis: Vec3::new(0.2, 1.0, 0.1).normalize(),
                        speed_rad_per_sec: 0.05,
                    },
                    Name::new(format!("Sun::{}::molten", name)),
                ));
                for (idx, (mesh, mat)) in [
                    (halo_mesh_inner, halo_inner_mat),
                    (halo_mesh_mid, halo_mid_mat),
                    (halo_mesh_outer, halo_outer_mat),
                ]
                .into_iter()
                .enumerate()
                {
                    parent.spawn((
                        MaterialMeshBundle::<HaloMaterial> {
                            mesh,
                            material: mat,
                            transform: Transform::IDENTITY,
                            ..default()
                        },
                        Name::new(format!("Sun::{}::halo{}", name, idx)),
                    ));
                }
            });
        count += 1;
    }
    info!("client_bevy: spawned {} system suns", count);
}

/// Number of nebula clouds. Capped at 10 (matches Godot
/// nebula_field.gd) — extra grid cells exist as fallbacks when an
/// inset-skipped cell wastes a slot, but only this many actually
/// spawn.
const NEBULA_COUNT: usize = 10;

/// Paint a handful of translucent colored spheres around origin as
/// nebula clouds, seeded off `Sim.world_seed`. Hues vary per-instance
/// and per-seed so the same world shows the same clouds every boot
/// but different worlds look distinct. Unlit emissive so the clouds
/// don't darken behind bodies and stations.
/// Per-axis Y depth + horizontal radius of the nebula backdrop
/// field, plus inset radius around the camera focus that nebulae
/// avoid. Matches Godot's `nebula_field.gd` constants
/// (FIELD_Y / FIELD_Y_JITTER / FIELD_RADIUS_WORLD / INSET_RADIUS_WORLD)
/// scaled up 10× for our SCALE_FACTOR=100 universe.
const NEBULA_FIELD_Y: f32 = -2000.0;
const NEBULA_FIELD_Y_JITTER: f32 = 600.0;
const NEBULA_FIELD_HALF_EXTENT: f32 = 14000.0;
const NEBULA_INSET_RADIUS: f32 = 1200.0;
/// Per-nebula radius range. Big enough that distant clouds still
/// subtend a visible angle from the play plane; small enough that
/// neighbouring clouds don't overlap into a uniform haze.
const NEBULA_RADIUS_MIN: f32 = 900.0;
const NEBULA_RADIUS_MAX: f32 = 2200.0;

fn spawn_nebulae(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut nebula_materials: ResMut<Assets<NebulaMaterial>>,
    sim: Res<Sim>,
) {
    use rand::{rngs::StdRng, Rng, SeedableRng};

    // Offset the seed so the nebulae don't phase-lock with the
    // starfield's layout — same world, different dice.
    let seed = sim.world_seed.wrapping_add(0xBADC0FFEE0DDF00Du64);
    let mut rng = StdRng::seed_from_u64(seed);

    // Jittered-grid cell list. Mirrors `_shuffled_cells` from
    // nebula_field.gd: 4×3 grid across the field, Fisher-Yates
    // shuffled with the seeded RNG so each save keeps the same
    // distribution but different worlds get different layouts.
    const GRID_COLS: usize = 4;
    const GRID_ROWS: usize = 3;
    let cell_w = (2.0 * NEBULA_FIELD_HALF_EXTENT) / GRID_COLS as f32;
    let cell_h = (2.0 * NEBULA_FIELD_HALF_EXTENT) / GRID_ROWS as f32;
    let mut cells: Vec<(f32, f32)> = (0..GRID_ROWS)
        .flat_map(|row| {
            (0..GRID_COLS).map(move |col| {
                let cx = -NEBULA_FIELD_HALF_EXTENT + cell_w * (col as f32 + 0.5);
                let cz = -NEBULA_FIELD_HALF_EXTENT + cell_h * (row as f32 + 0.5);
                (cx, cz)
            })
        })
        .collect();
    // Fisher-Yates with our deterministic RNG.
    for i in (1..cells.len()).rev() {
        let j = rng.gen_range(0..=i);
        cells.swap(i, j);
    }

    // Shared low-poly sphere; the shader does the heavy lifting,
    // so geometry detail doesn't matter.
    let mesh = meshes.add(Sphere::new(1.0).mesh().ico(2).unwrap());

    let mut placed: u32 = 0;
    let inset_sq = NEBULA_INSET_RADIUS * NEBULA_INSET_RADIUS;
    let limit = NEBULA_COUNT as u32;
    for (cx, cz) in cells {
        if placed >= limit {
            break;
        }
        // Bounded jitter inside the cell, matching Godot's 0.35×
        // half-cell range.
        let jx = rng.gen_range(-cell_w * 0.35..cell_w * 0.35);
        let jz = rng.gen_range(-cell_h * 0.35..cell_h * 0.35);
        let x = cx + jx;
        let z = cz + jz;
        if x * x + z * z < inset_sq {
            continue; // skip — too close to the camera focus
        }
        let y =
            NEBULA_FIELD_Y + rng.gen_range(-NEBULA_FIELD_Y_JITTER..NEBULA_FIELD_Y_JITTER);
        let pos = Vec3::new(x, y, z);

        let radius = rng.gen_range(NEBULA_RADIUS_MIN..NEBULA_RADIUS_MAX);
        // Per-axis shape: flattened Y so the cloud reads as a
        // sheet rather than a perfect sphere.
        let shape = Vec3::new(
            rng.gen_range(0.8f32..1.6),
            rng.gen_range(0.25f32..0.7),
            rng.gen_range(0.8f32..1.6),
        );

        // Build per-cloud NebulaParams with Godot's randomised
        // ranges. radial_falloff floor of 5.0 + density_threshold
        // floor of 0.63 keeps the cloud volumetric instead of
        // reading as a solid disc.
        let mut params = nebula_params(placed, sim.world_seed);
        params.density = rng.gen_range(0.7f32..1.3);
        params.brightness = rng.gen_range(0.45f32..0.85);
        params.noise_frequency = rng.gen_range(1.0f32..2.0);
        params.noise_warp = rng.gen_range(0.5f32..1.1);
        params.wisp_strength = rng.gen_range(0.5f32..1.1);
        params.radial_falloff = rng.gen_range(5.0f32..6.5);
        params.density_threshold = rng.gen_range(0.63f32..0.72);
        params.color_mix_shift = rng.gen_range(0.35f32..0.65);
        let mat = nebula_materials.add(NebulaMaterial { params });

        let xf = Transform::from_translation(pos).with_scale(shape * radius);
        // Glacial tumble — light-year-scale cloud shouldn't
        // visibly rotate during a play session. Per-axis ±0.002
        // rad/sec — full turn ≈ 50 minutes.
        let tumble = Vec3::new(
            rng.gen_range(-0.002f32..0.002),
            rng.gen_range(-0.002f32..0.002),
            rng.gen_range(-0.002f32..0.002),
        );
        commands.spawn((
            MaterialMeshBundle::<NebulaMaterial> {
                mesh: mesh.clone(),
                material: mat,
                transform: xf,
                ..default()
            },
            Tumble(tumble),
            Name::new("Nebula"),
        ));
        placed += 1;
    }
    info!(
        "client_bevy: spawned {} nebula clouds (world_seed={})",
        placed, sim.world_seed,
    );
}

/// Cleanup pass — despawn Bevy ship render entities whose sim_id is
/// no longer in `sim.store.ship_by_id`. Runs each frame; at typical
/// scale that's 1600 dict lookups, trivial. Kicks in after an admin
/// Delete Ship (Bundle 3x) so ghost ships don't linger in the scene.
/// Does not currently handle facility or body deletes because nothing
/// in the client deletes those yet; add parallel cleanup systems when
/// those admin actions land.
fn cleanup_stale_ships(
    mut commands: Commands,
    sim: Res<Sim>,
    explosion: Option<Res<ExplosionEffect>>,
    ships: Query<(Entity, &ShipEntity, &Transform)>,
) {
    for (e, ship, xf) in ships.iter() {
        if !sim.store.ship_by_id.contains_key(&ship.sim_id) {
            // Spawn a one-shot explosion at the ship's last known
            // position before we yank the entity. ExplosionLifetime
            // timer cleans up the particle entity 1.5 s later.
            if let Some(ref ex) = explosion {
                // ParticleEffectBundle already includes Transform +
                // GlobalTransform — passing them as separate tuple
                // entries panics with "duplicate components". Set
                // the transform inline on the bundle instead.
                commands.spawn((
                    ParticleEffectBundle {
                        transform: Transform::from_translation(xf.translation),
                        ..ParticleEffectBundle::new(ex.0.clone())
                    },
                    ExplosionLifetime(Timer::from_seconds(1.5, TimerMode::Once)),
                    Name::new(format!("Explosion::{}", ship.sim_id)),
                ));
            }
            commands.entity(e).despawn_recursive();
        }
    }
}

/// Reconcile newly-spawned sim ships into the Bevy scene. Mirror of
/// [`cleanup_stale_ships`]: iterate sim.store.ship_by_id and spawn a
/// render entity for any sim_id not yet present in the Bevy ships
/// query. Runs every frame; membership check is a HashSet build +
/// lookup so the cost scales with live ship count, not spawn-rate.
/// Kicks in after admin Spawn Ship — the sim spawn path only
/// touches hecs, so this bridge surfaces new ships visually.
/// Mirror of `reconcile_new_ships` for facilities. The Add Facility
/// admin dialog spawns a hecs FacilityEntity post-startup; without
/// this system there'd be no Bevy render entity for it. Iterates
/// hecs facilities, spawns a SceneBundle for any that don't already
/// have a matching Bevy `FacilityEntity`. Same StationModels lookup
/// + STATION_SCALE / GATE_SCALE handling as the startup spawn.
fn reconcile_new_facilities(
    mut commands: Commands,
    sim: Res<Sim>,
    stations: Option<Res<StationModels>>,
    facilities: Query<&FacilityEntity>,
) {
    let Some(stations) = stations else { return };
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};

    let known: std::collections::HashSet<&str> =
        facilities.iter().map(|f| f.sim_id.as_str()).collect();

    // Body positions for offset math — same approach the startup
    // path uses. Cheap at <30 bodies.
    let body_positions: std::collections::HashMap<String, (f32, f32)> = sim
        .store
        .world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    for (_e, (id, loc)) in sim
        .store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
    {
        if known.contains(id.id.as_str()) {
            continue;
        }
        let body_center = body_positions
            .get(&id.body_id)
            .copied()
            .unwrap_or((0.0, 0.0));
        let (fx, fy) =
            sim_core::agents::facility::facility_offset_position(body_center, &id.id);
        let y_offset = 0.5;
        let is_gate = id.facility_type == "gate";
        let scale = if is_gate { GATE_SCALE } else { STATION_SCALE };
        let mut transform =
            Transform::from_xyz(fx * SCALE_FACTOR, y_offset, fy * SCALE_FACTOR)
                .with_scale(Vec3::splat(scale));
        if is_gate {
            transform.rotate_y(std::f32::consts::FRAC_PI_2);
        }
        commands.spawn((
            SceneBundle {
                scene: stations.for_type(&id.facility_type),
                transform,
                ..default()
            },
            FacilityEntity {
                sim_id: id.id.clone(),
                base_scale: scale,
                body_id: id.body_id.clone(),
            },
            FacilityLocationRef(loc.location_name.clone()),
            GameWorld,
            Name::new(format!("Facility::{}", id.id)),
        ));
    }
}

fn reconcile_new_ships(
    mut commands: Commands,
    sim: Res<Sim>,
    ship_models: Option<Res<ShipModels>>,
    engine_trail: Option<Res<EngineTrailEffect>>,
    ships: Query<&ShipEntity>,
) {
    let Some(ship_models) = ship_models else { return };
    let Some(engine_trail) = engine_trail else { return };
    // Build set of known sim_ids as &str — avoids 1604 String
    // allocations every render frame (was a hot allocation source
    // at fleet scale on M1).
    let known: std::collections::HashSet<&str> = ships.iter().map(|s| s.sim_id.as_str()).collect();

    for (sim_id, &entity) in sim.store.ship_by_id.iter() {
        if known.contains(sim_id.as_str()) {
            continue;
        }
        let Ok(mut q) = sim
            .store
            .world
            .query_one::<(&ShipIdentity, &ShipPosition)>(entity)
        else {
            continue;
        };
        let Some((id, pos)) = q.get() else { continue };
        let (x, y) = pos.position;
        let base_scale = SHIP_GLB_SCALE * ship_size_multiplier(id.size);
        commands.spawn((
            ParticleEffectBundle::new(engine_trail.0.clone()),
            EngineTrailFor(sim_id.clone()),
            GameWorld,
            Name::new(format!("EngineTrail::{sim_id}")),
        ));
        commands.spawn((
            SceneBundle {
                scene: ship_models.for_class(&id.class),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR)
                    .with_scale(Vec3::splat(base_scale)),
                ..default()
            },
            ShipEntity {
                sim_id: sim_id.clone(),
                base_scale,
            },
            InterpPos::at((x, y)),
            GameWorld,
            Name::new(format!("Ship::{sim_id}")),
        ));
    }
}

/// Screen-space radius (fraction of distance from camera) used as the
/// ray-sphere hit threshold. At 1% of distance a clicked pixel picks
/// anything within roughly 10 px at typical FOV — loose enough to be
/// forgiving, tight enough to not pick through adjacent ships.
const PICK_RADIUS_FRAC: f32 = 0.015;

/// Left-click raycast against ship + facility render entities, sets
/// the matching Selected* resource on hit. Skips when egui wants the
/// pointer (so clicks on panel widgets don't fire a world pick) and
/// when the click started on nothing (leaves selection unchanged —
/// empty-clicks don't deselect, matching Godot's feel). Uses a
/// screen-space-aware pick radius so the threshold doesn't become
/// unusable when zoomed out.
#[allow(clippy::too_many_arguments)]
fn raycast_select(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut selected_ship: ResMut<SelectedShip>,
    mut selected_fac: ResMut<SelectedFacility>,
    mut egui_ctx: EguiContexts,
) {
    if !buttons.just_pressed(MouseButton::Left) {
        return;
    }
    // Skip world picks when the click is on an egui window.
    if egui_ctx.ctx_mut().is_pointer_over_area() {
        return;
    }

    let Ok(window) = windows.get_single() else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    let Ok((camera, cam_xf)) = cameras.get_single() else {
        return;
    };
    let Some(ray) = camera.viewport_to_world(cam_xf, cursor) else {
        return;
    };

    // Track best (smallest) depth across all candidates so we pick the
    // nearest thing the ray touches.
    enum Hit {
        Ship(String),
        Facility(String),
    }
    let mut best: Option<(f32, Hit)> = None;

    for (ship, xf) in ships.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Ship(ship.sim_id.clone())));
            }
        }
    }
    for (fac, xf) in facilities.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        // Facilities are visually bigger than ships, so widen the pick
        // radius slightly in kind.
        let r = dist * PICK_RADIUS_FRAC * 1.4;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Facility(fac.sim_id.clone())));
            }
        }
    }

    match best {
        Some((_, Hit::Ship(id))) => {
            selected_ship.0 = Some(id);
            selected_fac.0 = None;
        }
        Some((_, Hit::Facility(id))) => {
            selected_fac.0 = Some(id);
            selected_ship.0 = None;
        }
        None => {
            // Empty click — leave existing selection alone. Matches
            // the Godot feel where clicking starry space doesn't
            // deselect. Users close the details panel to deselect.
        }
    }
}

/// Right-click variant of [`raycast_select`]. Hits a ship or
/// facility under the cursor → writes a `ContextMenuRequest` so the
/// UI can render a popup at the screen position with action items
/// (Inspect / Follow / POV / Destroy). Skips when egui owns the
/// pointer so right-clicks on panels don't surface a world menu.
fn raycast_context_menu(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut menu_req: ResMut<crate::ui::ContextMenuRequest>,
    mut egui_ctx: EguiContexts,
) {
    if !buttons.just_pressed(MouseButton::Right) {
        return;
    }
    if egui_ctx.ctx_mut().is_pointer_over_area() {
        return;
    }
    let Ok(window) = windows.get_single() else { return };
    let Some(cursor) = window.cursor_position() else { return };
    let Ok((camera, cam_xf)) = cameras.get_single() else { return };
    let Some(ray) = camera.viewport_to_world(cam_xf, cursor) else {
        return;
    };

    enum Hit {
        Ship(String),
        Facility(String),
    }
    let mut best: Option<(f32, Hit)> = None;
    for (ship, xf) in ships.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Ship(ship.sim_id.clone())));
            }
        }
    }
    for (fac, xf) in facilities.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC * 1.4;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Facility(fac.sim_id.clone())));
            }
        }
    }

    let target = match best {
        Some((_, Hit::Ship(id))) => Some(crate::ui::ContextMenuTarget::Ship(id)),
        Some((_, Hit::Facility(id))) => Some(crate::ui::ContextMenuTarget::Facility(id)),
        None => return, // empty right-click leaves any open menu alone
    };

    *menu_req = crate::ui::ContextMenuRequest {
        target,
        screen_pos: Vec2::new(cursor.x, cursor.y),
    };
}

/// Per-frame: copy each ship's world rotation onto its engine-trail
/// sibling, plus translate aft by a small offset so the exhaust
/// emitter sits behind the hull. Scale on the trail entity stays at
/// 1 — the trail is NOT a child of the ship, so it isn't subject to
/// SHIP_GLB_SCALE / size_multiplier shrinkage. Particle sizes set
/// inside the EffectAsset render in world units accordingly.
///
/// Also gates emission on transit: if the matching sim ship is
/// docked, the trail entity goes Visibility::Hidden — hanabi's
/// default `simulation_condition: WhenVisible` halts emission while
/// hidden, so docked ships read as engines-off instantly without a
/// per-instance EffectInitializers mutation.
#[allow(clippy::type_complexity)]
fn sync_engine_trails(
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
fn cleanup_stale_engine_trails(
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

/// Read `CameraFollow` each frame; if a target is set, look up the
/// matching ShipEntity / FacilityEntity Bevy transform and write its
/// translation into `OrbitCamera.focus`. Optional one-shot
/// `snap_distance` (set by the POV menu item) collapses the orbit
/// distance to a closer "above the shoulder" view, then clears
/// itself. Manual user pan in `orbit_camera_input` clears the follow
/// target so muscle memory wins.
#[allow(clippy::type_complexity)]
fn apply_camera_follow(
    time: Res<Time>,
    mut follow: ResMut<crate::camera::CameraFollow>,
    mut camera_q: Query<
        (&mut crate::camera::OrbitCamera, &mut Transform),
        (Without<ShipEntity>, Without<FacilityEntity>, Without<BodyEntity>),
    >,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut prev: Local<Option<crate::camera::CameraFollowTarget>>,
) {
    let Some(target) = follow.target.clone() else {
        *prev = None;
        return;
    };
    let Ok((mut orbit, mut cam_xf)) = camera_q.get_single_mut() else { return };
    // First frame after target is set: snap focus instantly so the
    // user sees the camera respond to the menu click. Subsequent
    // frames lerp for smooth tracking. Without this snap a click
    // when the camera was far from the target reads as "nothing
    // happened" because the 12% lerp per frame is invisible at
    // galactic-overview distances.
    let just_locked = match (&*prev, &target) {
        (Some(crate::camera::CameraFollowTarget::Ship(a)), crate::camera::CameraFollowTarget::Ship(b)) => a != b,
        (Some(crate::camera::CameraFollowTarget::Facility(a)), crate::camera::CameraFollowTarget::Facility(b)) => a != b,
        (Some(_), _) => true,
        (None, _) => true,
    };
    let translation = match &target {
        crate::camera::CameraFollowTarget::Ship(id) => ships
            .iter()
            .find(|(s, _)| s.sim_id == *id)
            .map(|(_, xf)| xf.translation),
        crate::camera::CameraFollowTarget::Facility(id) => facilities
            .iter()
            .find(|(f, _)| f.sim_id == *id)
            .map(|(_, xf)| xf.translation),
    };
    // Also pull the target's rotation when we're in POV mode so we
    // can derive a chase-camera yaw from the ship's heading.
    let rotation = match &target {
        crate::camera::CameraFollowTarget::Ship(id) => ships
            .iter()
            .find(|(s, _)| s.sim_id == *id)
            .map(|(_, xf)| xf.rotation),
        crate::camera::CameraFollowTarget::Facility(id) => facilities
            .iter()
            .find(|(f, _)| f.sim_id == *id)
            .map(|(_, xf)| xf.rotation),
    };

    if let Some(t) = translation {
        match follow.mode {
            crate::camera::CameraFollowMode::Lock => {
                if just_locked {
                    // Snap fully on the first frame so the user
                    // sees the camera respond to their click, then
                    // lerp from there.
                    orbit.focus = t;
                    info!(
                        "client_bevy: camera follow → {:?} (lock @ {:?})",
                        target, t
                    );
                } else {
                    // Smooth follow: ease toward the target so a
                    // fast ship doesn't yank the camera frame-to-
                    // frame. Time-aware exponential smoothing —
                    // 1 - exp(-rate*dt) — gives a framerate-
                    // independent settle time. RATE = 8 means
                    // ~12% closing per 16 ms frame, ~99% in ~580 ms.
                    const RATE: f32 = 8.0;
                    let alpha = 1.0 - (-RATE * time.delta_seconds()).exp();
                    orbit.focus = orbit.focus.lerp(t, alpha);
                }
                if let Some(d) = follow.snap_distance.take() {
                    orbit.distance = d;
                }
            }
            crate::camera::CameraFollowMode::Pov => {
                // Third-person chase camera. Sit slightly above +
                // behind the ship, look along its heading. Override
                // orbit yaw / pitch / distance from the ship's
                // forward direction so the user can't accidentally
                // drag the camera off-axis.
                //
                // Ship's nose is +Z in local space (see
                // sync_positions rotation math). Forward in world =
                // rotation * Vec3::Z. Camera should be eye-behind-
                // and-above-ship looking forward, so:
                //   yaw points the eye-to-focus direction along
                //        ship-forward (offset = -forward × distance)
                //   pitch tilts down a touch for cinematic feel
                let forward = rotation
                    .map(|r| r * Vec3::Z)
                    .unwrap_or(Vec3::Z);
                // OrbitCamera's offset formula from .transform():
                //   offset = (cp*sy, -sp, cp*cy) * distance
                // We want offset to point from focus to eye, with eye
                // BEHIND the nose (i.e. opposite of ship-forward).
                // In the y=0 plane that means yaw such that
                //   (sy, ., cy) ≈ -(forward.x, ., forward.z)
                let target_yaw = (-forward.x).atan2(-forward.z);
                orbit.focus = t;
                orbit.yaw = target_yaw;
                orbit.pitch = -0.18; // slight tilt down (~10°)
                orbit.distance = 1.5; // close-third-person
                if just_locked {
                    info!(
                        "client_bevy: camera follow → {:?} (pov, yaw {:.2})",
                        target, target_yaw
                    );
                }
                // Clear any leftover snap_distance — POV owns the
                // distance.
                follow.snap_distance = None;
            }
        }
        // Push the orbit state into the camera Transform so the
        // render pipeline actually sees the change. Without this
        // the follow updates orbit.focus / orbit.distance silently
        // and the visible camera doesn't move until the user pans.
        *cam_xf = orbit.transform();
        *prev = Some(target);
    } else {
        // Target despawned (ship retired, facility deleted) — drop
        // the follow so we don't keep querying for a missing id.
        follow.target = None;
        follow.snap_distance = None;
        *prev = None;
    }
}

/// Standard ray-sphere hit test. Returns the depth along the ray if
/// the ray enters the sphere, None otherwise. We project the sphere
/// centre onto the ray, then reject when the perpendicular distance
/// exceeds the radius. "Behind camera" filtered via the early t<0.
fn ray_sphere_hit(ray: &Ray3d, center: Vec3, radius: f32) -> Option<f32> {
    let dir = ray.direction.as_vec3();
    let to_center = center - ray.origin;
    let t = to_center.dot(dir);
    if t < 0.0 {
        return None;
    }
    let closest = ray.origin + dir * t;
    let perp2 = (center - closest).length_squared();
    if perp2 <= radius * radius {
        Some(t)
    } else {
        None
    }
}

/// Gate-ring world-unit radius. A touch larger than the facility
/// placeholder cylinder so the ring encloses rather than overlaps.
/// Tuned at 0.7 to read as "distinct from a station" at zoom-out
/// without becoming dominant in the scene.
const GATE_RING_RADIUS: f32 = 0.7;

/// Outer radius of a construction site scaffold ring. Larger than
/// gates so it reads as "work in progress, not a destination".
const SITE_OUTER_RADIUS: f32 = 0.9;

/// Draw construction-site scaffold rings for every
/// `ConstructionSite` in the sim. Outer amber ring = scaffold
/// boundary; filled amber arc = progress fraction. Scene is
/// gizmo-only — construction sites spawn + despawn dynamically
/// (faction::run_construction_cycle + engine::materialize_facility),
/// and a gizmo approach doesn't require a matching Bevy-entity
/// lifecycle. Cheap at ~10–30 active sites in a typical DB.
fn draw_construction_sites(sim: Res<Sim>, mut gizmos: Gizmos) {
    use sim_core::agents::construction::ConstructionSite;

    let world = &sim.store.world;
    // Green scaffold + brighter green progress arc. The previous
    // amber outer was indistinguishable from gate rings (also amber)
    // — players read it as "warp gate at Venus / Trojan cluster",
    // which is wrong. Green reads as "build in progress" and pairs
    // with the inner progress arc.
    let outer = Color::srgba(0.45, 0.85, 0.55, 0.55);
    let inner = Color::srgba(0.6, 1.0, 0.75, 0.95);
    let normal = Dir3::Y;

    for (_e, site) in world.query::<&ConstructionSite>().iter() {
        let (x, y) = site.position;
        let center = Vec3::new(x * SCALE_FACTOR, 0.4, y * SCALE_FACTOR);
        // Outer scaffold ring — constant radius.
        gizmos
            .circle(center, normal, SITE_OUTER_RADIUS, outer)
            .resolution(48);
        // Crosshair tick-marks inside the ring so a freshly-spawned
        // (0% progress) site still reads as a build site, not just
        // an empty circle. Two short axis-aligned spokes from the
        // centre.
        let spoke = SITE_OUTER_RADIUS * 0.35;
        gizmos.line(
            center + Vec3::new(-spoke, 0.0, 0.0),
            center + Vec3::new(spoke, 0.0, 0.0),
            outer,
        );
        gizmos.line(
            center + Vec3::new(0.0, 0.0, -spoke),
            center + Vec3::new(0.0, 0.0, spoke),
            outer,
        );
        // Inner progress ring — radius scales with progress 0..=1 so
        // it reads as a filling disk from the centre outward. No
        // partial-arc API, so a second smaller ring is the cheap
        // substitute.
        let progress = site.progress().clamp(0.0, 1.0);
        if progress > 0.0 {
            let r = SITE_OUTER_RADIUS * progress;
            gizmos.circle(center, normal, r, inner).resolution(32);
        }
    }
}

/// Draw a pulsing ring around the selected ship / facility so the
/// user can find their selection in a dense scene. Complements the
/// scale-up in `highlight_selected` — a 4× ship at galactic zoom is
/// still tiny; a pulsing cyan ring is visible at any zoom level.
/// Pulse is time-based (sine of wall-clock seconds) so it doesn't
/// get faster with sim speed.
#[allow(clippy::type_complexity)]
fn draw_selection_rings(
    time: Res<Time>,
    selected_ship: Res<SelectedShip>,
    selected_fac: Res<SelectedFacility>,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut gizmos: Gizmos,
) {
    // Pulse amplitude as a fraction of the base ring radius. Slow
    // 0.6 Hz sine, range 0.85..1.15 so the pulse reads as a gentle
    // breath rather than a strobe.
    let t = time.elapsed_seconds();
    let pulse = 1.0 + 0.15 * (t * std::f32::consts::TAU * 0.6).sin();

    // Amber — high-intensity warm channel so bloom amps it to a
    // bright orange-gold halo, distinct from the cyan transit
    // streaks and the green construction rings.
    let color = Color::srgb(1.6, 1.1, 0.4);
    let normal = Dir3::Y;

    if let Some(id) = selected_ship.0.as_deref() {
        for (ship, xf) in ships.iter() {
            if ship.sim_id == id {
                // Recover the size_multiplier alone (0.25..=3.5)
                // from base_scale = SHIP_GLB_SCALE × size_mult, then
                // 0.4 wu × size_mult × ~6 = a ring 2.4× the hull
                // length at default size. Comfortable halo at every
                // size tier.
                let size_mult = ship.base_scale / SHIP_GLB_SCALE;
                let r = 0.4 * size_mult * pulse;
                gizmos
                    .circle(xf.translation, normal, r, color)
                    .resolution(32);
                break;
            }
        }
    }
    if let Some(id) = selected_fac.0.as_deref() {
        for (fac, xf) in facilities.iter() {
            if fac.sim_id == id {
                // Facility hulls render at base_scale × ~80-unit
                // native gltf, so STATION_SCALE 0.05 → ~4 wu world
                // size, GATE_SCALE 0.075 → ~6 wu. Multiplier 50
                // gives 2.5 wu / 3.75 wu rings — wraps each with
                // breathing room. Replaces the old hard-coded
                // FACILITY_SELECT_RING_RADIUS = 1.0 (stuck inside
                // the station silhouette).
                let r = fac.base_scale * 50.0 * pulse;
                gizmos
                    .circle(xf.translation, normal, r, color)
                    .resolution(48);
                break;
            }
        }
    }
}

/// Draw a faint amber ring around every gate facility each frame via
/// Bevy Gizmos. Gates are just another FacilityEntity with
/// `facility_type == "gate"` in sim-core, but visually they need to
/// stand apart from stations so the player can navigate
/// inter-system jump routes. Read-only per-frame; one gizmo circle
/// per gate is effectively free at the scales we see (<30 gates).
fn draw_gate_rings(sim: Res<Sim>, mut gizmos: Gizmos) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::FacilityIdentity;

    let world = &sim.store.world;

    // Resolve body_id → universe position once up front; facility
    // orbit centre is just the body centre for visualisation
    // purposes (the small 0.15 offset doesn't matter at this
    // scale).
    let body_positions: std::collections::HashMap<String, (f32, f32)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    // Amber, slightly translucent. Matches the "caution: traverse
    // here" connotation stations don't carry.
    let color = Color::srgba(0.95, 0.75, 0.35, 0.85);
    let normal = Dir3::Y; // ring lies flat on the galactic plane

    for (_e, id) in world.query::<&FacilityIdentity>().iter() {
        if id.facility_type != "gate" {
            continue;
        }
        let Some(&(x, y)) = body_positions.get(&id.body_id) else {
            continue;
        };
        let center = Vec3::new(x * SCALE_FACTOR, 0.5, y * SCALE_FACTOR);
        gizmos
            .circle(center, normal, GATE_RING_RADIUS, color)
            .resolution(48);
    }
}

/// Draw a faint cyan circle for each body's orbit around its system
/// primary. Centre = system universe_offset; radius = orbit_radius
/// (sim units → world units via SCALE_FACTOR). Bodies with
/// orbit_radius ≈ 0 are the system primary themselves, skip those.
///
/// Doubles as alignment-debug: if a station drifts off its body's
/// orbital path, the geometry shows it immediately. Single source
/// of truth for "where is body X right now" (the orbit ring) makes
/// any sim/render coordinate divergence visible.
fn draw_orbit_rings(sim: Res<Sim>, mut gizmos: Gizmos) {
    let world = &sim.store.world;
    // Cool blue, low alpha so 35 rings don't crowd the view.
    let color = Color::srgba(0.40, 0.65, 0.85, 0.18);
    let normal = Dir3::Y; // ring on galactic plane

    for (_e, orbit) in world.query::<&BodyOrbit>().iter() {
        if orbit.orbit_radius < 0.01 {
            // Effectively the system primary — no ring to draw.
            continue;
        }
        let (cx, cy) = orbit.universe_offset;
        let center = Vec3::new(cx * SCALE_FACTOR, 0.0, cy * SCALE_FACTOR);
        let radius = orbit.orbit_radius * SCALE_FACTOR;
        // Resolution scales with circumference so big outer-system
        // rings stay smooth without wasting verts on small inner
        // ones. Capped at 96 — beyond that the eye can't tell.
        let resolution = ((radius * 0.5) as usize).clamp(32, 96);
        gizmos
            .circle(center, normal, radius, color)
            .resolution(resolution);
    }
}

/// Per-ship rolling history of recent world-space positions. Ports
/// `_trail_history` from Godot's `ship.gd`. Capped at `TRAIL_MAX_LEN`
/// per ship; `update_ship_trails` pushes the latest position each
/// frame for ships in transit and trims; `draw_ship_trails` renders
/// the strip with a quadratic alpha fade (oldest invisible →
/// newest opaque) and red→orange colour shift along the length.
///
/// Cleared whenever a ship stops transiting, so the trail vanishes
/// once the ship docks instead of lingering behind a stationary
/// dot. Same behaviour as Godot's `_is_moving` gate.
#[derive(Resource, Default)]
struct ShipTrails {
    history: std::collections::HashMap<String, std::collections::VecDeque<Vec3>>,
}

/// Baseline trail length in samples (Medium ship). Tiny ships get
/// proportionally shorter trails, Massive ships proportionally
/// longer, so the trail reads at the same visual angular scale
/// against the hull regardless of ship size — a Massive freighter
/// with a 60-sample trail has the streak buried behind its own
/// silhouette. Linear scale by `base_scale`, clamped so we don't
/// pay for absurdly long trails behind tiny couriers OR draw
/// 600-segment trails for the largest hulls.
const TRAIL_BASELINE_LEN: usize = 60;

/// Per-ship max trail length in samples, scaled by its size tier.
/// Tiny=15, Medium=60, Massive=300. Cap matches user expectation
/// that Huge/Massive trails should be "visible past the hull".
fn trail_max_len_for(base_scale: f32) -> usize {
    let scaled = (TRAIL_BASELINE_LEN as f32 * base_scale) as usize;
    scaled.clamp(15, 300)
}

/// Sample each in-transit ship's current world position into its
/// rolling history. Stationary / docked ships have their history
/// cleared so the trail fades away as the ship sits at a station.
/// Drops history for ships that no longer exist.
#[allow(clippy::type_complexity)]
fn update_ship_trails(
    sim: Res<Sim>,
    mut trails: ResMut<ShipTrails>,
    ships: Query<(&ShipEntity, &Transform), (Without<FacilityEntity>, Without<BodyEntity>)>,
) {
    let world = &sim.store.world;

    // Build the in-transit set once so the per-ship inner loop is a
    // hashmap lookup, not a hecs scan. Same approach `sync_positions`
    // uses for ship state.
    let in_transit: std::collections::HashSet<String> = world
        .query::<(&ShipIdentity, &ShipTransit)>()
        .iter()
        .filter(|(_, (_, t))| t.transit.is_some())
        .map(|(_, (id, _))| id.id.clone())
        .collect();

    // Live-ship set so we can drop trails for despawned ships.
    let mut live: std::collections::HashSet<String> =
        std::collections::HashSet::with_capacity(ships.iter().count());

    for (ship, xf) in ships.iter() {
        live.insert(ship.sim_id.clone());
        let history = trails.history.entry(ship.sim_id.clone()).or_default();
        if !in_transit.contains(&ship.sim_id) {
            // Not moving — drop history so the trail disappears.
            history.clear();
            continue;
        }
        history.push_back(xf.translation);
        let cap = trail_max_len_for(ship.base_scale);
        while history.len() > cap {
            history.pop_front();
        }
    }

    trails.history.retain(|k, _| live.contains(k));
}

/// Draw a faint dashed line from each in-transit ship to its
/// destination station. Ports Godot `transit_lines.gd` — the
/// "intent" line, separate from the exhaust trail behind the ship.
/// Dashes are evenly spaced so long inter-system runs and short
/// intra-system hops both read consistently. Brighter alpha for
/// the currently selected ship, dim for the rest.
fn draw_transit_intent_lines(sim: Res<Sim>, selected_ship: Res<SelectedShip>, mut gizmos: Gizmos) {
    let world = &sim.store.world;

    // Build location_name → world destination (body universe pos +
    // facility offset, matching what the sim aimed the transit at).
    // Many facilities share a location, so this dedups by name —
    // first-write wins; sim ships travel to the location, not a
    // specific facility id, so any facility at the location is
    // a valid endpoint marker.
    let body_positions: std::collections::HashMap<String, (f32, f32)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();
    let mut loc_to_world: std::collections::HashMap<String, Vec3> =
        std::collections::HashMap::new();
    for (_e, (fac_id, loc)) in world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
    {
        if loc_to_world.contains_key(&loc.location_name) {
            continue;
        }
        let Some(body_center) = body_positions.get(&fac_id.body_id).copied() else {
            continue;
        };
        let (fx, fy) =
            sim_core::agents::facility::facility_offset_position(body_center, &fac_id.id);
        loc_to_world.insert(
            loc.location_name.clone(),
            Vec3::new(fx * SCALE_FACTOR, 0.0, fy * SCALE_FACTOR),
        );
    }

    // Faint indigo for the all-ships pass; punchier blue for the
    // selected ship (mirrors Godot's BASE / SELECTED split).
    let base_color = Color::srgba(0.50, 0.60, 0.90, 0.10);
    let selected_color = Color::srgba(0.70, 0.80, 1.00, 0.55);
    let selected_id = selected_ship.0.as_deref();

    // Constant dash count per line so length is decoupled from
    // visual density — short and long runs both look the same.
    const DASH_SEGMENTS: usize = 24;

    for (_e, (id, transit, pos)) in world
        .query::<(&ShipIdentity, &ShipTransit, &ShipPosition)>()
        .iter()
    {
        let Some(t) = &transit.transit else { continue };
        let Some(end) = loc_to_world.get(&t.to).copied() else {
            continue;
        };
        let start = Vec3::new(
            pos.position.0 * SCALE_FACTOR,
            0.0,
            pos.position.1 * SCALE_FACTOR,
        );
        let color = if Some(id.id.as_str()) == selected_id {
            selected_color
        } else {
            base_color
        };
        // Walk start→end in 2*DASH_SEGMENTS steps; draw the even
        // segments only. Two t-values per dash so the dash spans
        // [t0, t1] of the line.
        let total = (DASH_SEGMENTS * 2) as f32;
        for i in 0..DASH_SEGMENTS {
            let t0 = (i as f32 * 2.0) / total;
            let t1 = (i as f32 * 2.0 + 1.0) / total;
            let a = start.lerp(end, t0);
            let b = start.lerp(end, t1);
            gizmos.line(a, b, color);
        }
    }
}

/// Render the rolling trails as faded gizmo line segments. Per-segment
/// alpha = `t² * 0.35` where `t = 0` (oldest) → `1` (newest) so
/// segments fade out at the tail like an exhaust streak. Colour
/// shifts red (old) → orange/yellow (new) following Godot's
/// `ship.gd::_update_trail`. Gizmos batch into one draw call so
/// the cost is "active-trails × samples-per-trail" line segments —
/// at 200 in-transit ships × 60 samples = 12k segments, batched
/// fine.
fn draw_ship_trails(trails: Res<ShipTrails>, mut gizmos: Gizmos) {
    for history in trails.history.values() {
        let n = history.len();
        if n < 2 {
            continue;
        }
        let last = (n - 1) as f32;
        let mut iter = history.iter();
        let mut prev = match iter.next() {
            Some(p) => *p,
            None => continue,
        };
        for (i, &point) in iter.enumerate() {
            // i+1 = vertex index of `point` (since iter started at 1).
            let t = (i as f32 + 1.0) / last;
            let alpha = t * t * 0.35;
            let color = Color::srgba(1.0, 0.3 + t * 0.4, 0.1, alpha);
            gizmos.line(prev, point, color);
            prev = point;
        }
    }
}
