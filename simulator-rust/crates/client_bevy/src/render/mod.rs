//! Render mirror — Bevy entities that shadow the sim's hecs entities,
//! sized+positioned each frame by reading directly from the sim
//! Resource. Bundle 2c scope: placeholder geometry (boxes for ships,
//! spheres for bodies, cylinders for facilities) so we can verify the
//! scaling + camera feel at the 1500-ship stress. Proper procedural
//! ship meshes come in Bundle 3.

use bevy::prelude::*;
use bevy_egui::EguiContexts;
use sim_core::agents::{
    celestial_body::{BodyIdentity, BodyOrbit},
    facility::{FacilityIdentity, FacilityLocation},
    ship::{ShipIdentity, ShipPosition, ShipTransit},
};

use crate::sim::Sim;
use crate::ui::{SelectedFacility, SelectedShip};

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
const SHIP_SIZE: f32 = 0.05;
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
/// Facility selection-ring radius (world units). Replaces the
/// `FACILITY_SIZE * SELECT_SCALE * 1.3` formula from the cylinder-
/// placeholder era. Sized to wrap a STATION_SCALE-scaled station
/// (~4 wu) with comfortable margin; tune if STATION_SCALE moves.
const FACILITY_SELECT_RING_RADIUS: f32 = 1.0;

pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        // Stations preload in Startup so the Handle<Scene>s exist
        // by the time spawn_mirror_entities runs in PostStartup.
        // Asset bytes load asynchronously; SceneBundle just shows
        // an empty parent until the gltf streams in (typically a
        // frame or two on local disk).
        app.init_resource::<ShipTrails>()
            .add_systems(Startup, load_station_models)
            .add_systems(
                PostStartup,
                (
                    spawn_mirror_entities,
                    spawn_starfield,
                    spawn_nebulae,
                    spawn_system_suns,
                ),
            )
            .add_systems(
                Update,
                (
                    sync_positions,
                    follow_facilities_to_bodies,
                    highlight_selected,
                    draw_selection_rings,
                    update_ship_trails,
                    draw_ship_trails,
                    draw_gate_rings,
                    draw_orbit_rings,
                    draw_construction_sites,
                    raycast_select,
                    cleanup_stale_ships,
                    reconcile_new_ships,
                ),
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

/// Marker components so the per-frame position-sync query can narrow
/// its work + so click-to-select can tell categories apart later.
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
/// - **courier**: smallest (~0.5 wu max axis) → fast, narrow
/// - **freighter / tanker / miner**: medium (~1 wu) → workhorses
/// - **hauler**: largest (~5 wu) → industrial behemoth
///
/// Spread chosen to match the user's "0.25 → 1 → 5" hierarchy so
/// silhouettes at galactic zoom encode role without a label.
fn ship_dimensions(class: &str) -> (f32, f32, f32) {
    let base = SHIP_SIZE;
    match class {
        "courier" => (base * 0.20, base * 0.20, base * 0.55),
        "freighter" => (base * 0.70, base * 0.50, base * 1.4),
        "hauler" => (base * 2.20, base * 1.50, base * 4.50),
        "tanker" => (base * 0.55, base * 0.70, base * 1.3),
        "miner" => (base * 0.50, base * 0.50, base * 1.10),
        _ => (base * 0.5, base * 0.5, base * 1.5),
    }
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
        ShipSize::Large => 1.6,
        ShipSize::Huge => 2.5,
        ShipSize::Massive => 5.0,
    }
}

/// Hull colors per faction — lifted from the Godot
/// `client/scripts/tools/procedural_ship.gd::FACTION_PALETTES` table
/// so the two clients read the same at parity. Unknown factions use
/// the `fallback` material (independent-grey).
fn faction_palette() -> &'static [(&'static str, [f32; 3])] {
    &[
        ("terran-authority", [0.85, 0.90, 0.92]),
        ("mars-syndicate", [0.55, 0.24, 0.16]),
        ("belt-coalition", [0.72, 0.64, 0.34]),
        ("frontier-ventures", [0.50, 0.60, 0.42]),
        ("crucible-mining", [0.26, 0.30, 0.34]),
        ("the-doughtys", [0.70, 0.50, 0.80]),
        ("independent", [0.58, 0.58, 0.60]),
        // Factions not in the Godot palette — picked to be
        // distinguishable at distance. Revisit when we do real
        // procedural ships and can pull from a shared palette crate.
        ("vega-conclave", [0.35, 0.60, 0.85]),
        ("outer-reach", [0.85, 0.55, 0.30]),
    ]
}

fn spawn_mirror_entities(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
    stations: Res<StationModels>,
) {
    // Build the shared asset pool once. Ships get one material per
    // faction — materials are cheap; it's the mesh sharing + instancing
    // that actually matters for draw calls.
    // Ship materials get a faction-tinted emissive so ships stay
    // visible as glowing points at galactic-zoom where the
    // placeholder mesh itself subtends just a few pixels even at
    // SHIP_SIZE=1.0. Tonemapping blooms emissive samples across
    // surrounding pixels so a tiny ship reads as a bright spark.
    // 4.0 was tuned visually so a fleet at Earth shows as a
    // distinct cluster of coloured dots, not a single body smear.
    let emissive_scale = 4.0;
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
        ship_mesh_by_class.insert(class.to_string(), meshes.add(Cuboid::new(w, h, l)));
    }
    let (dw, dh, dl) = ship_dimensions("default");
    let ship_mesh_default = meshes.add(Cuboid::new(dw, dh, dl));

    let assets = PlaceholderAssets {
        ship_mesh_by_class,
        ship_mesh_default,
        ship_mat_by_faction,
        ship_mat_fallback,
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
        let base_scale = ship_size_multiplier(id.size);
        commands.spawn((
            PbrBundle {
                mesh: assets.ship_mesh_for(&id.class),
                material: assets.ship_mat_for(&id.faction_id),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR)
                    .with_scale(Vec3::splat(base_scale)),
                ..default()
            },
            ShipEntity {
                sim_id: id.id.clone(),
                base_scale,
            },
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
            BodyEntity {
                sim_id: id.body_id.clone(),
            },
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
        let (fx, fy) =
            sim_core::agents::facility::facility_offset_position(body_center, &id.id);
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

    // Ship lookup keyed by &str so we don't clone 1604 Strings into
    // a HashMap every render frame (was a hot allocation source at
    // fleet scale on M1). Bind the QueryBorrow first so it lives
    // long enough for the &str borrows to outlive the `collect`.
    let mut ship_query = world.query::<(&ShipIdentity, &ShipPosition, &ShipTransit)>();
    let ship_state: std::collections::HashMap<&str, ((f32, f32), Option<Vec3>)> = ship_query
        .iter()
        .map(|(_e, (id, pos, transit))| {
            let heading = transit.transit.as_ref().and_then(|t| {
                let (dx, dy) = t.departure_position?;
                let delta = Vec3::new(
                    (pos.position.0 - dx) * SCALE_FACTOR,
                    0.0,
                    (pos.position.1 - dy) * SCALE_FACTOR,
                );
                if delta.length_squared() > 1e-6 {
                    Some(delta.normalize())
                } else {
                    None
                }
            });
            (id.id.as_str(), (pos.position, heading))
        })
        .collect();

    for (ship, mut xf) in ships.iter_mut() {
        if let Some((pos, heading)) = ship_state.get(ship.sim_id.as_str()) {
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

    // Body positions update slowly (orbits). 35 entries — keep
    // &str keys for consistency with ships above.
    let mut body_query = world.query::<(&BodyIdentity, &BodyOrbit)>();
    let body_positions: std::collections::HashMap<&str, (f32, f32)> = body_query
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.as_str(), orbit.universe_position()))
        .collect();

    for (body, mut xf) in bodies.iter_mut() {
        if let Some(&(x, y)) = body_positions.get(body.sim_id.as_str()) {
            xf.translation.x = x * SCALE_FACTOR;
            xf.translation.z = y * SCALE_FACTOR;
        }
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
fn follow_facilities_to_bodies(
    sim: Res<Sim>,
    mut facilities: Query<
        (&FacilityEntity, &mut Transform),
        (Without<ShipEntity>, Without<BodyEntity>),
    >,
) {
    let world = &sim.store.world;
    let mut body_query = world.query::<(&BodyIdentity, &BodyOrbit)>();
    let body_positions: std::collections::HashMap<&str, (f32, f32)> = body_query
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.as_str(), orbit.universe_position()))
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
    mut ships: Query<(&ShipEntity, &mut Transform), (Without<FacilityEntity>, Without<BodyEntity>)>,
    mut facilities: Query<
        (&FacilityEntity, &mut Transform),
        (Without<ShipEntity>, Without<BodyEntity>),
    >,
) {
    let ship_id = selected_ship.0.as_deref();
    for (ship, mut xf) in ships.iter_mut() {
        // Layer selection on top of the ship's base_scale (size
        // tier). Without this multiplier the per-tier scale gets
        // clobbered to 1.0 the first frame after spawn.
        let mult = if Some(ship.sim_id.as_str()) == ship_id {
            SELECT_SCALE
        } else {
            1.0
        };
        let wanted = ship.base_scale * mult;
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
        // Layer selection on top of the model's base scale (set at
        // spawn). Without this multiplier the GLB's STATION_SCALE
        // gets clobbered to 1.0 the first frame after spawn.
        let mult = if Some(fac.sim_id.as_str()) == fac_id {
            SELECT_SCALE
        } else {
            1.0
        };
        let wanted = fac.base_scale * mult;
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
const STAR_FIELD_RADIUS: f32 = 24000.0;

/// World-unit radius of the visible "sun" at each star system's
/// universe_offset. ~2× a planet body (7 wu) so the system primary
/// clearly anchors the orbital geometry. Sized small relative to
/// the inter-orbit spread so inner planets don't clip into it.
const SUN_RADIUS: f32 = 8.0;

/// One-time PostStartup spawn: place a yellow emissive sphere at
/// every star system's universe_offset so the player has a fixed
/// reference point to see body orbits against. Without this, six
/// systems' worth of orbiting bodies look like floating islands —
/// no obvious centre of rotation. Reads `Sim.registry.systems`
/// because that's where the seeder stashed the system → offset
/// table (same source as ship/body universe coords).
fn spawn_system_suns(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    sim: Res<Sim>,
) {
    let mesh = meshes.add(Sphere::new(SUN_RADIUS).mesh().ico(3).unwrap());
    // Emissive yellow well into HDR so bloom paints a corona around
    // the sphere — same trick the ship/body materials use to read
    // at galactic zoom. RGBA 1.0 base, 6×/4×/0.6× emissive.
    let mat = materials.add(StandardMaterial {
        base_color: Color::srgb(1.0, 0.85, 0.3),
        emissive: LinearRgba::new(6.0, 4.0, 0.6, 1.0),
        unlit: true,
        ..default()
    });

    let mut count = 0usize;
    for (name, sys) in sim.registry.systems.iter() {
        let (x, y) = sys.universe_offset;
        commands.spawn((
            PbrBundle {
                mesh: mesh.clone(),
                material: mat.clone(),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
                ..default()
            },
            Name::new(format!("Sun::{}", name)),
        ));
        count += 1;
    }
    info!("client_bevy: spawned {} system suns", count);
}

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
const NEBULA_FIELD_RADIUS: f32 = 45000.0;

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
fn cleanup_stale_ships(mut commands: Commands, sim: Res<Sim>, ships: Query<(Entity, &ShipEntity)>) {
    for (e, ship) in ships.iter() {
        if !sim.store.ship_by_id.contains_key(&ship.sim_id) {
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
fn reconcile_new_ships(
    mut commands: Commands,
    sim: Res<Sim>,
    assets: Option<Res<PlaceholderAssets>>,
    ships: Query<&ShipEntity>,
) {
    let Some(assets) = assets else { return };
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
        let base_scale = ship_size_multiplier(id.size);
        commands.spawn((
            PbrBundle {
                mesh: assets.ship_mesh_for(&id.class),
                material: assets.ship_mat_for(&id.faction_id),
                transform: Transform::from_xyz(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR)
                    .with_scale(Vec3::splat(base_scale)),
                ..default()
            },
            ShipEntity {
                sim_id: sim_id.clone(),
                base_scale,
            },
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
    // 1.5 Hz sine, range 0.85..1.15 so the pulse reads as a gentle
    // breath rather than a strobe.
    let t = time.elapsed_seconds();
    let pulse = 1.0 + 0.15 * (t * std::f32::consts::TAU * 0.6).sin();

    // Cyan, high intensity so the bloom post-process picks it up and
    // the ring glows even when small.
    let color = Color::srgb(0.4, 1.0, 1.5);
    let normal = Dir3::Y;

    if let Some(id) = selected_ship.0.as_deref() {
        for (ship, xf) in ships.iter() {
            if ship.sim_id == id {
                let r = SHIP_SIZE * SELECT_SCALE * 1.6 * pulse;
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
                let r = FACILITY_SELECT_RING_RADIUS * pulse;
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

/// Trail length in samples. Godot kept 60 (~7.5s at 8tps); Bevy's
/// `Update` schedule fires per render frame (~60 Hz), so 60 samples
/// = 1s of history. Plenty visible without dominating the screen.
const TRAIL_MAX_LEN: usize = 60;

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
        while history.len() > TRAIL_MAX_LEN {
            history.pop_front();
        }
    }

    trails.history.retain(|k, _| live.contains(k));
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
