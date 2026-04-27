//! Gizmo overlays — selection rings, gate rings, orbits, construction
//! sites, transit-intent lines, and per-ship motion trails.
//!
//! Gizmos are immediate-mode lines/circles drawn each frame; they
//! don't carry their own ECS entities, which is exactly the right
//! shape for transient overlays (selection halo) and dynamic-set
//! indicators (construction sites that materialize away mid-game).
//! Cheap at the typical 10–30 sites + ~500 ships scale; rendering is
//! deferred to a single batched call by Bevy.
//!
//! ## What lives here
//!
//!   * [`draw_construction_sites`] — green scaffold ring + filled
//!     progress arc per active `ConstructionSite`. Crosshair tick-marks
//!     so a 0%-progress site still reads as "build in progress".
//!   * [`draw_selection_rings`] — pulsing cyan rings around the
//!     currently-selected ship and facility. HDR-bright so the bloom
//!     pass keeps them findable at any zoom.
//!   * [`draw_gate_rings`] — amber ring per `facility_type == "gate"`
//!     so jump points read as distinct from stations.
//!   * [`draw_orbit_rings`] — faint dotted ring per planet body to
//!     orient the eye at galactic zoom.
//!   * [`draw_transit_intent_lines`] — when a ship is selected and in
//!     transit, dashed green line from departure to destination.
//!   * Per-ship motion trails — [`update_ship_trails`] tracks the
//!     last N positions per ship; [`draw_ship_trails`] renders them as
//!     fading orange lines. Trail length scales with ship class via
//!     [`trail_max_len_for`].
//!
//! Extracted from `render/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;

use super::{BodyEntity, FacilityEntity, ShipEntity, SCALE_FACTOR, SHIP_GLB_SCALE};
use crate::sim::Sim;
use crate::ui::{SelectedFacility, SelectedShip};
use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
use sim_core::agents::ship::{ShipIdentity, ShipPosition, ShipTransit};

/// Build an Isometry3d that places a Gizmos circle on the orbital
/// (XZ) plane at `center`. Bevy 0.18 changed the default Gizmos circle
/// to draw in the XY plane (normal +Z); orbital rings + gate rings +
/// selection rings should lie flat on the XZ plane (normal +Y), so
/// every site needs an explicit -π/2 rotation around X.
#[inline]
fn orbital_iso(center: Vec3) -> Isometry3d {
    Isometry3d::new(
        center,
        Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2),
    )
}

/// Gate-ring world-unit radius. A touch larger than the facility
/// placeholder cylinder so the ring encloses rather than overlaps.
/// Tuned at 0.7 to read as "distinct from a station" at zoom-out
/// without becoming dominant in the scene.
pub(super) const GATE_RING_RADIUS: f32 = 0.7;

/// Outer radius of a construction site scaffold ring. Larger than
/// gates so it reads as "work in progress, not a destination".
pub(super) const SITE_OUTER_RADIUS: f32 = 0.9;

/// Draw construction-site scaffold rings for every
/// `ConstructionSite` in the sim. Outer amber ring = scaffold
/// boundary; filled amber arc = progress fraction. Scene is
/// gizmo-only — construction sites spawn + despawn dynamically
/// (faction::run_construction_cycle + engine::materialize_facility),
/// and a gizmo approach doesn't require a matching Bevy-entity
/// lifecycle. Cheap at ~10–30 active sites in a typical DB.
pub(super) fn draw_construction_sites(sim: Res<Sim>, mut gizmos: Gizmos) {
    use sim_core::agents::construction::ConstructionSite;

    let world = &sim.store.world;
    // Green scaffold + brighter green progress arc. The previous
    // amber outer was indistinguishable from gate rings (also amber)
    // — players read it as "warp gate at Venus / Trojan cluster",
    // which is wrong. Green reads as "build in progress" and pairs
    // with the inner progress arc.
    let outer = Color::srgba(0.45, 0.85, 0.55, 0.55);
    let inner = Color::srgba(0.6, 1.0, 0.75, 0.95);

    for (_e, site) in world.query::<&ConstructionSite>().iter() {
        let (x, y) = site.position;
        let center = Vec3::new(x * SCALE_FACTOR, 0.4, y * SCALE_FACTOR);
        // Outer scaffold ring — constant radius. Bevy 0.15+ Gizmos
        // takes an Isometry3d; the default rotation puts the circle
        // in the XZ plane (matches old `normal = Dir3::Y` behaviour).
        gizmos
            .circle(orbital_iso(center), SITE_OUTER_RADIUS, outer)
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
            gizmos
                .circle(orbital_iso(center), r, inner)
                .resolution(32);
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
pub(super) fn draw_selection_rings(
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
    let t = time.elapsed_secs();
    let pulse = 1.0 + 0.15 * (t * std::f32::consts::TAU * 0.6).sin();

    // Amber — high-intensity warm channel so bloom amps it to a
    // bright orange-gold halo, distinct from the cyan transit
    // streaks and the green construction rings.
    let color = Color::srgb(1.6, 1.1, 0.4);

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
                    .circle(orbital_iso(xf.translation), r, color)
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
                    .circle(orbital_iso(xf.translation), r, color)
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
pub(super) fn draw_gate_rings(sim: Res<Sim>, mut gizmos: Gizmos) {
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

    for (_e, id) in world.query::<&FacilityIdentity>().iter() {
        if id.facility_type != "gate" {
            continue;
        }
        let Some(&(x, y)) = body_positions.get(&id.body_id) else {
            continue;
        };
        let center = Vec3::new(x * SCALE_FACTOR, 0.5, y * SCALE_FACTOR);
        gizmos
            .circle(orbital_iso(center), GATE_RING_RADIUS, color)
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
pub(super) fn draw_orbit_rings(sim: Res<Sim>, mut gizmos: Gizmos) {
    let world = &sim.store.world;
    // Cool blue, low alpha so 35 rings don't crowd the view.
    let color = Color::srgba(0.40, 0.65, 0.85, 0.18);

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
        let resolution = ((radius * 0.5) as u32).clamp(32, 96);
        gizmos
            .circle(orbital_iso(center), radius, color)
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
pub(super) struct ShipTrails {
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
pub(super) fn trail_max_len_for(base_scale: f32) -> usize {
    let scaled = (TRAIL_BASELINE_LEN as f32 * base_scale) as usize;
    scaled.clamp(15, 300)
}

/// Sample each in-transit ship's current world position into its
/// rolling history. Stationary / docked ships have their history
/// cleared so the trail fades away as the ship sits at a station.
/// Drops history for ships that no longer exist.
#[allow(clippy::type_complexity)]
pub(super) fn update_ship_trails(
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
pub(super) fn draw_transit_intent_lines(sim: Res<Sim>, selected_ship: Res<SelectedShip>, mut gizmos: Gizmos) {
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
pub(super) fn draw_ship_trails(trails: Res<ShipTrails>, mut gizmos: Gizmos) {
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
