//! Render mirror — Bevy entities that shadow the sim's hecs entities,
//! sized+positioned each frame by reading directly from the sim
//! Resource. Bundle 2c scope: placeholder geometry (boxes for ships,
//! spheres for bodies, cylinders for facilities) so we can verify the
//! scaling + camera feel at the 1500-ship stress. Proper procedural
//! ship meshes come in Bundle 3.

use bevy::prelude::*;
use bevy_egui::EguiContexts;
use sim_core::{
    agents::{
        celestial_body::{BodyIdentity, BodyOrbit},
        facility::{FacilityIdentity, FacilityLocation},
        ship::{ShipIdentity, ShipPosition, ShipTransit},
    },
};

use crate::sim::Sim;
use crate::ui::{SelectedFacility, SelectedShip};

/// Scale factor from universe units → world units. Matches Godot's
/// `GameState.SCALE_FACTOR` so the two clients place everything at
/// the same coordinates (handy while both exist during the port).
pub const SCALE_FACTOR: f32 = 10.0;

/// Placeholder sizes (world units). Ships tiny, facilities medium,
/// bodies big — mirrors the visual hierarchy of the Godot client
/// without any procedural detail. The galactic-overview camera sits
/// 500+ wu from focus and systems are spread over ~4000 wu, so
/// bodies need to be visibly bigger than the realistic ratio would
/// suggest — otherwise they read as flyspecks at max zoom-out.
const SHIP_SIZE: f32 = 0.4;
const FACILITY_SIZE: f32 = 1.5;
const BODY_SIZE: f32 = 5.0;

pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        // Spawn entities after the sim has loaded (PostStartup ensures
        // `Sim::load_world` has populated the store).
        app.add_systems(
                PostStartup,
                (spawn_mirror_entities, spawn_starfield, spawn_nebulae),
            )
            .add_systems(
                Update,
                (
                    sync_positions,
                    highlight_selected,
                    draw_transit_lines,
                    draw_gate_rings,
                    draw_construction_sites,
                    raycast_select,
                    cleanup_stale_ships,
                ),
            );
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
    pub sim_id: String,
}

#[derive(Component)]
pub struct BodyEntity {
    pub sim_id: String,
}

/// Shared meshes + materials for the placeholder geometry. Stashed on
/// a Resource so every entity references the same GPU handle — one
/// draw call per archetype instead of per-entity. Ship material is
/// per-faction (see `ship_mat_for`) so the placeholder fleet reads
/// as factions at a glance.
#[derive(Resource)]
struct PlaceholderAssets {
    /// One mesh per ship class — freighter wider, courier sleek, etc.
    /// Fallback for unknown class strings falls back to the `default`
    /// key. Shared handles → instancing still works per-archetype.
    ship_mesh_by_class: std::collections::HashMap<String, Handle<Mesh>>,
    ship_mesh_default: Handle<Mesh>,
    ship_mat_by_faction: std::collections::HashMap<String, Handle<StandardMaterial>>,
    ship_mat_fallback: Handle<StandardMaterial>,
    facility_mesh: Handle<Mesh>,
    facility_mat: Handle<StandardMaterial>,
    body_mesh: Handle<Mesh>,
    body_mat: Handle<StandardMaterial>,
}

impl PlaceholderAssets {
    fn ship_mat_for(&self, faction: &str) -> Handle<StandardMaterial> {
        self.ship_mat_by_faction
            .get(faction)
            .cloned()
            .unwrap_or_else(|| self.ship_mat_fallback.clone())
    }

    fn ship_mesh_for(&self, class: &str) -> Handle<Mesh> {
        self.ship_mesh_by_class
            .get(class)
            .cloned()
            .unwrap_or_else(|| self.ship_mesh_default.clone())
    }
}

/// Class-specific placeholder dimensions (width, height, length) in
/// world units. Nose is +Z (see `sync_positions` rotation math); the
/// rotation + stretched Z gives the sense of travel direction. Picked
/// to read distinctly at the 1600-ship stress:
///
/// - **courier**: slim + long → fast, narrow
/// - **freighter**: wider body → cargo capacity visible
/// - **hauler**: biggest, squat → industrial
/// - **tanker**: medium but tall → rounded silhouette
/// - **miner**: stubby, balanced → industrial compact
fn ship_dimensions(class: &str) -> (f32, f32, f32) {
    let base = SHIP_SIZE;
    match class {
        "courier" => (base * 0.35, base * 0.35, base * 2.0),
        "freighter" => (base * 0.70, base * 0.50, base * 1.6),
        "hauler" => (base * 0.85, base * 0.60, base * 1.8),
        "tanker" => (base * 0.60, base * 0.70, base * 1.5),
        "miner" => (base * 0.55, base * 0.55, base * 1.3),
        _ => (base * 0.5, base * 0.5, base * 1.6),
    }
}

/// Hull colors per faction — lifted from the Godot
/// `client/scripts/tools/procedural_ship.gd::FACTION_PALETTES` table
/// so the two clients read the same at parity. Unknown factions use
/// the `fallback` material (independent-grey).
fn faction_palette() -> &'static [(&'static str, [f32; 3])] {
    &[
        ("terran-authority",   [0.85, 0.90, 0.92]),
        ("mars-syndicate",     [0.55, 0.24, 0.16]),
        ("belt-coalition",     [0.72, 0.64, 0.34]),
        ("frontier-ventures",  [0.50, 0.60, 0.42]),
        ("crucible-mining",    [0.26, 0.30, 0.34]),
        ("the-doughtys",       [0.70, 0.50, 0.80]),
        ("independent",        [0.58, 0.58, 0.60]),
        // Factions not in the Godot palette — picked to be
        // distinguishable at distance. Revisit when we do real
        // procedural ships and can pull from a shared palette crate.
        ("vega-conclave",      [0.35, 0.60, 0.85]),
        ("outer-reach",        [0.85, 0.55, 0.30]),
    ]
}

fn spawn_mirror_entities(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
) {
    // Build the shared asset pool once. Ships get one material per
    // faction — materials are cheap; it's the mesh sharing + instancing
    // that actually matters for draw calls.
    // Ship materials get a faction-tinted emissive so ships stay
    // visible as glowing points at galactic-zoom where the
    // placeholder mesh itself subtends a sub-pixel footprint.
    // Tonemapping blooms emissive samples across nearby pixels so a
    // half-pixel ship still reads as a coloured spark. Scale is
    // small enough that at close zoom emissive is just "sheen".
    let emissive_scale = 1.8;
    let mut ship_mat_by_faction = std::collections::HashMap::new();
    for (id, rgb) in faction_palette() {
        let mat = materials.add(StandardMaterial {
            base_color: Color::srgb(rgb[0], rgb[1], rgb[2]),
            emissive: LinearRgba::new(rgb[0], rgb[1], rgb[2], 1.0) * emissive_scale,
            metallic: 0.3,
            perceptual_roughness: 0.55,
            ..default()
        });
        ship_mat_by_faction.insert((*id).to_string(), mat);
    }
    let ship_mat_fallback = materials.add(StandardMaterial {
        base_color: Color::srgb(0.58, 0.58, 0.60),
        emissive: LinearRgba::new(0.58, 0.58, 0.60, 1.0) * emissive_scale,
        metallic: 0.3,
        perceptual_roughness: 0.55,
        ..default()
    });

    // Build one placeholder mesh per ship class plus a default. Each
    // class has its own cuboid proportions — see `ship_dimensions`.
    // Nose is +Z so the rotation math in `sync_positions` lines up.
    let mut ship_mesh_by_class = std::collections::HashMap::new();
    for class in ["courier", "freighter", "hauler", "tanker", "miner"] {
        let (w, h, l) = ship_dimensions(class);
        ship_mesh_by_class.insert(
            class.to_string(),
            meshes.add(Cuboid::new(w, h, l)),
        );
    }
    let (dw, dh, dl) = ship_dimensions("default");
    let ship_mesh_default = meshes.add(Cuboid::new(dw, dh, dl));

    let assets = PlaceholderAssets {
        ship_mesh_by_class,
        ship_mesh_default,
        ship_mat_by_faction,
        ship_mat_fallback,
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
                mesh: assets.ship_mesh_for(&id.class),
                material: assets.ship_mat_for(&id.faction_id),
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

    // Ship lookup: sim_id → (position, heading). Heading is a unit
    // vector in xz-world-space derived from departure→current while
    // in transit; None when docked / idle (keep last heading).
    let ship_state: std::collections::HashMap<String, ((f32, f32), Option<Vec3>)> = world
        .query::<(&ShipIdentity, &ShipPosition, &ShipTransit)>()
        .iter()
        .map(|(_e, (id, pos, transit))| {
            let heading = transit.transit.as_ref().and_then(|t| {
                let (dx, dy) = t.departure_position?;
                let delta = Vec3::new(
                    (pos.position.0 - dx) * SCALE_FACTOR,
                    0.0,
                    (pos.position.1 - dy) * SCALE_FACTOR,
                );
                // Micro-transits (sub-tick progress at departure) can
                // be zero-length; skip those rather than normalizing
                // to NaN.
                if delta.length_squared() > 1e-6 {
                    Some(delta.normalize())
                } else {
                    None
                }
            });
            (id.id.clone(), (pos.position, heading))
        })
        .collect();

    for (ship, mut xf) in ships.iter_mut() {
        if let Some((pos, heading)) = ship_state.get(&ship.sim_id) {
            xf.translation.x = pos.0 * SCALE_FACTOR;
            xf.translation.z = pos.1 * SCALE_FACTOR;
            if let Some(dir) = heading {
                // Face travel direction. `+Z` is the ship's nose in
                // local space (see elongated cuboid above). Rotation
                // around Y only — ships stay level in galactic plane.
                xf.rotation = Quat::from_rotation_y(dir.x.atan2(dir.z));
            }
            // Docked / idle ships keep their last rotation so they
            // don't snap back to identity when a transit ends.
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

/// Selection scale factor — how big the chosen ship/facility gets
/// relative to its peers. Big enough to stand out at galactic
/// zoom where the base placeholder meshes are tiny dots; small
/// enough that it still reads as the same agent up close. 4×
/// makes a 0.4-wu ship visible as a 1.6-wu blob at overview —
/// roughly body-sized, so clearly the selected one in the scene.
const SELECT_SCALE: f32 = 4.0;

/// Per-frame system: enlarge whichever ship and facility are
/// currently selected; reset everyone else. The check is a string
/// compare per entity per frame — ~1700 compares at our scale,
/// trivially cheap vs. the 16.6 ms budget. If it ever shows up we
/// can cache the selected Bevy Entity on change instead.
#[allow(clippy::type_complexity)]
fn highlight_selected(
    selected_ship: Res<SelectedShip>,
    selected_fac: Res<SelectedFacility>,
    mut ships: Query<
        (&ShipEntity, &mut Transform),
        (Without<FacilityEntity>, Without<BodyEntity>),
    >,
    mut facilities: Query<
        (&FacilityEntity, &mut Transform),
        (Without<ShipEntity>, Without<BodyEntity>),
    >,
) {
    let ship_id = selected_ship.0.as_deref();
    for (ship, mut xf) in ships.iter_mut() {
        let wanted = if Some(ship.sim_id.as_str()) == ship_id {
            SELECT_SCALE
        } else {
            1.0
        };
        // Skip the write when the scale already matches to avoid
        // flagging transforms as changed every frame — keeps
        // Bevy's change-detection meaningful if downstream systems
        // start relying on it.
        if (xf.scale.x - wanted).abs() > f32::EPSILON {
            xf.scale = Vec3::splat(wanted);
        }
    }

    let fac_id = selected_fac.0.as_deref();
    for (fac, mut xf) in facilities.iter_mut() {
        let wanted = if Some(fac.sim_id.as_str()) == fac_id {
            SELECT_SCALE
        } else {
            1.0
        };
        if (xf.scale.x - wanted).abs() > f32::EPSILON {
            xf.scale = Vec3::splat(wanted);
        }
    }
}

/// Starfield density — number of stars spawned. Tuned to feel like a
/// populated sky without pressuring the frame budget. All stars are
/// instances of one shared mesh + one shared material so they cost
/// exactly one draw call between them.
const STAR_COUNT: usize = 2000;

/// Radius of the star shell around the galactic-overview focus.
/// Generous so stars read as "distant background" at all zoom levels
/// the camera clamp allows.
const STAR_FIELD_RADIUS: f32 = 4000.0;

/// One-time PostStartup spawn: scatter STAR_COUNT tiny emissive
/// spheres in a shell around origin, seeded off `Sim.world_seed` so
/// the constellations are stable across restarts. Godot does the
/// same trick for its nebula-cloud backdrop (see the world_seed
/// wiring in sim_server's WS `server_hello` frame).
fn spawn_starfield(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
) {
    use rand::{rngs::StdRng, Rng, SeedableRng};

    let seed = sim.world_seed;
    let mut rng = StdRng::seed_from_u64(seed);

    // Shared mesh + material. Small radius — perceived star size is
    // dominated by HDR bloom / emissive intensity, not geometry.
    let mesh = meshes.add(Sphere::new(0.8));
    let material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.95, 0.95, 1.0),
        emissive: LinearRgba::new(1.0, 1.0, 1.2, 1.0) * 3.0,
        unlit: true,
        ..default()
    });

    for _ in 0..STAR_COUNT {
        // Uniform on a sphere via the z-and-theta method, then scale
        // by a radius sampled with a mild bias toward the outer
        // shell so stars don't cluster at the near side of the
        // camera when zoomed in.
        let z: f32 = rng.gen_range(-1.0..1.0);
        let theta: f32 = rng.gen_range(0.0..std::f32::consts::TAU);
        let r_xy = (1.0 - z * z).sqrt();
        let dir = Vec3::new(r_xy * theta.cos(), z, r_xy * theta.sin());
        // Ratio 0.7..1.0 gives a filled shell rather than hollow one,
        // reads as "stars at many distances" at any zoom.
        let radius = STAR_FIELD_RADIUS * rng.gen_range(0.7f32..1.0);
        let pos = dir * radius;

        commands.spawn((
            PbrBundle {
                mesh: mesh.clone(),
                material: material.clone(),
                transform: Transform::from_translation(pos),
                ..default()
            },
            Name::new("Star"),
        ));
    }
    info!(
        "client_bevy: spawned {} stars (world_seed={})",
        STAR_COUNT, seed,
    );
}

/// Number of nebula clouds. Kept small — each is a big translucent
/// sphere; too many overlap into an opaque fog.
const NEBULA_COUNT: usize = 14;

/// Shell radius the nebula clouds sit at. Past the star shell
/// (STAR_FIELD_RADIUS = 4000) so clouds read as deep-background
/// volumes and can't occlude foreground bodies/ships.
const NEBULA_FIELD_RADIUS: f32 = 9000.0;

/// Per-cloud sphere radius range (min, max). At NEBULA_FIELD_RADIUS
/// distance these still project to respectable backdrop blobs
/// without dominating the scene.
const NEBULA_RADIUS_RANGE: (f32, f32) = (200.0, 400.0);

/// Paint a handful of translucent colored spheres around origin as
/// nebula clouds, seeded off `Sim.world_seed`. Hues vary per-instance
/// and per-seed so the same world shows the same clouds every boot
/// but different worlds look distinct. Unlit emissive so the clouds
/// don't darken behind bodies and stations.
fn spawn_nebulae(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
) {
    use rand::{rngs::StdRng, Rng, SeedableRng};

    // Offset the seed so the nebulae don't phase-lock with the
    // starfield's layout — same world, different dice.
    let seed = sim.world_seed.wrapping_add(0xBADC0FFEE0DDF00Du64);
    let mut rng = StdRng::seed_from_u64(seed);

    // Shared low-res sphere — nebulae are always soft blobs; poly
    // count doesn't matter.
    let mesh = meshes.add(Sphere::new(1.0));

    for _ in 0..NEBULA_COUNT {
        // Pick a direction on the shell (same z-theta method as
        // stars) and a middle-distance radius.
        let z: f32 = rng.gen_range(-1.0..1.0);
        let theta: f32 = rng.gen_range(0.0..std::f32::consts::TAU);
        let r_xy = (1.0 - z * z).sqrt();
        let dir = Vec3::new(r_xy * theta.cos(), z * 0.4, r_xy * theta.sin());
        let distance = NEBULA_FIELD_RADIUS * rng.gen_range(0.7f32..1.0);
        let pos = dir * distance;

        // Per-cloud radius + hue. Bias colours toward purples,
        // teals, and dusty oranges — the classic "galaxy nebula"
        // palette — rather than rainbow noise.
        let radius = rng.gen_range(NEBULA_RADIUS_RANGE.0..NEBULA_RADIUS_RANGE.1);
        let hue_roll: f32 = rng.gen_range(0.0f32..1.0);
        let (r, g, b) = if hue_roll < 0.34 {
            // purple/violet
            (0.35, 0.22, 0.55)
        } else if hue_roll < 0.67 {
            // teal/cyan
            (0.18, 0.40, 0.48)
        } else {
            // dusty orange
            (0.55, 0.32, 0.20)
        };
        // Intensity + alpha tuned low — at NEBULA_FIELD_RADIUS
        // distance these still read as visible colour gradients
        // against pure black. Too high and a cloud becomes a
        // foreground haze that blots out ships.
        let intensity = rng.gen_range(0.10f32..0.22);
        let mat = materials.add(StandardMaterial {
            base_color: Color::srgba(r, g, b, 0.04),
            emissive: LinearRgba::new(r, g, b, 1.0) * intensity,
            unlit: true,
            alpha_mode: AlphaMode::Blend,
            ..default()
        });

        commands.spawn((
            PbrBundle {
                mesh: mesh.clone(),
                material: mat,
                transform: Transform::from_translation(pos).with_scale(Vec3::splat(radius)),
                ..default()
            },
            Name::new("Nebula"),
        ));
    }
    info!(
        "client_bevy: spawned {} nebula clouds (world_seed={})",
        NEBULA_COUNT, sim.world_seed,
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
    ships: Query<(Entity, &ShipEntity)>,
) {
    for (e, ship) in ships.iter() {
        if !sim.store.ship_by_id.contains_key(&ship.sim_id) {
            commands.entity(e).despawn_recursive();
        }
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

    let Ok(window) = windows.get_single() else { return };
    let Some(cursor) = window.cursor_position() else { return };
    let Ok((camera, cam_xf)) = cameras.get_single() else { return };
    let Some(ray) = camera.viewport_to_world(cam_xf, cursor) else { return };

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
    let outer = Color::srgba(0.95, 0.75, 0.35, 0.85);
    let inner = Color::srgba(0.5, 0.95, 0.65, 0.85);
    let normal = Dir3::Y;

    for (_e, site) in world.query::<&ConstructionSite>().iter() {
        let (x, y) = site.position;
        let center = Vec3::new(x * SCALE_FACTOR, 0.4, y * SCALE_FACTOR);
        // Outer scaffold ring — constant radius.
        gizmos
            .circle(center, normal, SITE_OUTER_RADIUS, outer)
            .resolution(48);
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
        let Some(&(x, y)) = body_positions.get(&id.body_id) else { continue };
        let center = Vec3::new(x * SCALE_FACTOR, 0.5, y * SCALE_FACTOR);
        gizmos
            .circle(center, normal, GATE_RING_RADIUS, color)
            .resolution(48);
    }
}

/// Draw a faint line from each in-transit ship's departure point to
/// its current position, using Bevy Gizmos. Read-only per-frame;
/// Gizmos are batched into a single draw call so the cost is linear
/// in the number of ACTIVE transits (usually a modest fraction of
/// the fleet). If perf ever complains we can throttle by only
/// drawing lines for ships within a distance threshold of the
/// camera, but at 1600 ships total it's cheap enough to skip that.
fn draw_transit_lines(sim: Res<Sim>, mut gizmos: Gizmos) {
    let world = &sim.store.world;
    // Dim grey so the lines read as "a trail behind the ship" rather
    // than fighting the ships for attention at zoomed-out scales.
    let color = Color::srgba(0.55, 0.60, 0.70, 0.35);

    for (_e, (transit, pos)) in world.query::<(&ShipTransit, &ShipPosition)>().iter() {
        let Some(t) = &transit.transit else { continue };
        let Some((dx, dy)) = t.departure_position else { continue };
        let start = Vec3::new(dx * SCALE_FACTOR, 0.0, dy * SCALE_FACTOR);
        let end = Vec3::new(
            pos.position.0 * SCALE_FACTOR,
            0.0,
            pos.position.1 * SCALE_FACTOR,
        );
        gizmos.line(start, end, color);
    }
}
