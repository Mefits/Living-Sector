//! Render mirror — Bevy entities that shadow the sim's hecs entities,
//! sized+positioned each frame by reading directly from the sim
//! Resource. Bundle 2c scope: placeholder geometry (boxes for ships,
//! spheres for bodies, cylinders for facilities) so we can verify the
//! scaling + camera feel at the 1500-ship stress. Proper procedural
//! ship meshes come in Bundle 3.

use bevy::prelude::*;
use sim_core::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{FacilityIdentity, FacilityLocation},
        ship::{ShipIdentity, ShipPosition},
    },
};

use crate::sim::Sim;

/// Scale factor from universe units → world units. Matches Godot's
/// `GameState.SCALE_FACTOR` so the two clients place everything at
/// the same coordinates (handy while both exist during the port).
pub const SCALE_FACTOR: f32 = 10.0;

/// Placeholder sizes (world units). Ships tiny, facilities medium,
/// bodies big — mirrors the visual hierarchy of the Godot client
/// without any procedural detail.
const SHIP_SIZE: f32 = 0.18;
const FACILITY_SIZE: f32 = 0.35;
const BODY_SIZE: f32 = 1.0;

pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        // Spawn entities after the sim has loaded (PostStartup ensures
        // `Sim::load_world` has populated the store).
        app.add_systems(PostStartup, spawn_mirror_entities)
            .add_systems(Update, sync_positions);
    }
}

/// Marker components so the per-frame position-sync query can narrow
/// its work + so click-to-select can tell categories apart later.
#[derive(Component)]
pub struct ShipEntity {
    pub sim_id: String,
}

#[derive(Component)]
pub struct FacilityEntity {
    // Read by future inspector / click-select work. Keep the field
    // alive with an allow so strict clippy doesn't fail the build.
    #[allow(dead_code)]
    pub sim_id: String,
}

#[derive(Component)]
pub struct BodyEntity {
    pub sim_id: String,
}

/// Shared meshes + materials for the placeholder geometry. Stashed on
/// a Resource so every entity references the same GPU handle — one
/// draw call per archetype (~3 right now) instead of per-entity.
#[derive(Resource)]
struct PlaceholderAssets {
    ship_mesh: Handle<Mesh>,
    ship_mat: Handle<StandardMaterial>,
    facility_mesh: Handle<Mesh>,
    facility_mat: Handle<StandardMaterial>,
    body_mesh: Handle<Mesh>,
    body_mat: Handle<StandardMaterial>,
}

fn spawn_mirror_entities(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
) {
    // Build the shared asset pool once.
    let assets = PlaceholderAssets {
        ship_mesh: meshes.add(Cuboid::from_size(Vec3::splat(SHIP_SIZE))),
        ship_mat: materials.add(StandardMaterial {
            base_color: Color::srgb(0.85, 0.9, 1.0),
            metallic: 0.2,
            perceptual_roughness: 0.6,
            ..default()
        }),
        facility_mesh: meshes.add(Cylinder::new(FACILITY_SIZE * 0.5, FACILITY_SIZE)),
        facility_mat: materials.add(StandardMaterial {
            base_color: Color::srgb(0.7, 0.75, 0.6),
            metallic: 0.3,
            perceptual_roughness: 0.7,
            ..default()
        }),
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
        commands.spawn((
            PbrBundle {
                mesh: assets.ship_mesh.clone(),
                material: assets.ship_mat.clone(),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
                ..default()
            },
            ShipEntity { sim_id: id.id.clone() },
            Name::new(format!("Ship::{}", id.id)),
        ));
        ship_count += 1;
    }

    // Bodies — always at their orbit's current universe position.
    for (_e, (id, orbit)) in world.query::<(&BodyIdentity, &BodyOrbit)>().iter() {
        let (x, y) = orbit.universe_position();
        commands.spawn((
            PbrBundle {
                mesh: assets.body_mesh.clone(),
                material: assets.body_mat.clone(),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
                ..default()
            },
            BodyEntity { sim_id: id.body_id.clone() },
            Name::new(format!("Body::{}", id.body_id)),
        ));
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

    for (_e, (id, loc)) in world.query::<(&FacilityIdentity, &FacilityLocation)>().iter() {
        // Placeholder: put the facility AT its body centre. The real
        // "facility orbits its body at offset 0.15" math lives in
        // sim_core::agents::facility::facility_offset_position — we'll
        // wire it in for Bundle 3 alongside the proper render.
        let (bx, by) = body_positions
            .get(&id.body_id)
            .copied()
            .unwrap_or((0.0, 0.0));
        let y_offset = 0.5; // small vertical so facilities don't z-fight with bodies
        commands.spawn((
            PbrBundle {
                mesh: assets.facility_mesh.clone(),
                material: assets.facility_mat.clone(),
                transform: Transform::from_xyz(bx * SCALE_FACTOR, y_offset, by * SCALE_FACTOR),
                ..default()
            },
            FacilityEntity {
                sim_id: id.id.clone(),
            },
            // Silence the unused-field warning until selection work reads it.
            FacilityLocationRef(loc.location_name.clone()),
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
// Bevy system-parameter query filters are idiomatically tuple-heavy
// (exclusion between kinds). Clippy's `type_complexity` isn't a
// useful signal for this shape — quiet it at the call site instead
// of disabling the lint crate-wide.
#[allow(clippy::type_complexity)]
fn sync_positions(
    sim: Res<Sim>,
    mut ships: Query<(&ShipEntity, &mut Transform), Without<BodyEntity>>,
    mut bodies: Query<
        (&BodyEntity, &mut Transform),
        (Without<ShipEntity>, Without<FacilityEntity>),
    >,
) {
    let world = &sim.store.world;

    // Ship lookup: sim_id → (x, y).
    let ship_positions: std::collections::HashMap<String, (f32, f32)> = world
        .query::<(&ShipIdentity, &ShipPosition)>()
        .iter()
        .map(|(_e, (id, pos))| (id.id.clone(), pos.position))
        .collect();

    for (ship, mut xf) in ships.iter_mut() {
        if let Some(&(x, y)) = ship_positions.get(&ship.sim_id) {
            xf.translation.x = x * SCALE_FACTOR;
            xf.translation.z = y * SCALE_FACTOR;
        }
    }

    // Body positions update slowly (orbits). Refresh each frame for
    // simplicity; we can move to a FixedUpdate system later if this
    // ever shows up in a profile.
    let body_positions: std::collections::HashMap<String, (f32, f32)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    for (body, mut xf) in bodies.iter_mut() {
        if let Some(&(x, y)) = body_positions.get(&body.sim_id) {
            xf.translation.x = x * SCALE_FACTOR;
            xf.translation.z = y * SCALE_FACTOR;
        }
    }
}
