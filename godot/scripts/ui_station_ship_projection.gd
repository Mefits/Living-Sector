extends RefCounted
## Sol-only, read-only screen-coordinate reconciliation.
## N14 and N43 keep their authoritative native positions: this code
## does NOT alter velocity, fuel, docking, AI, or any canonical N39 data.
## Native star-centric display compression shrinks a 400 km station
## orbit to <1 px, while the planet glyph is much larger than scale.
## Correct only the nearby vessel marker toward the display-only
## orbital station, and smoothly remove that correction farther away.
const N43 = preload("res://scripts/sim/ships/native_location_resolver.gd")
const SolOrbits = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")
const MIN_LOCAL_BLEND_RADIUS: float = 0.015
const MAX_LOCAL_BLEND_RADIUS: float = 0.03

static func native_body_position(bodies: Dictionary, system_offset: Vector2,
        body_id: String, seen: Dictionary = {}) -> Dictionary:
    if body_id.is_empty() or not bodies.has(body_id) or seen.has(body_id) or (
            seen.size() >= 4):
        return {"ok": false}
    var body: Dictionary = bodies[body_id]
    var angle: float = deg_to_rad(float(body.get("current_angle", 0.0)))
    var direction: Vector2 = Vector2(cos(angle), sin(angle))
    var parent_id: String = str(body.get("parent_body_id", ""))
    if not parent_id.is_empty():
        var next_seen: Dictionary = seen.duplicate()
        next_seen[body_id] = true
        var parent: Dictionary = native_body_position(
            bodies, system_offset, parent_id, next_seen)
        var local_radius: float = float(
            body.get("satellite_orbit_radius_native", 0.0))
        if not parent.get("ok", false) or local_radius <= 0.0:
            return {"ok": false}
        return {"ok": true,
            "position": parent["position"] + direction * local_radius}
    return {"ok": true, "position": system_offset +
        direction * float(body.get("orbit_radius", 0.0))}


static func station_native_position(bodies: Dictionary,
        system_offset: Vector2, body_id: String,
        location: String, native_units: float) -> Dictionary:
    if not is_finite(native_units) or native_units < 0.0:
        return {"ok": false}
    var parent: Dictionary = native_body_position(
        bodies, system_offset, body_id)
    var local_radius: float = SolOrbits.compact_station_orbit_radius(
        body_id)
    if not parent.get("ok", false) or local_radius <= 0.0:
        return {"ok": false}
    var angle: float = deg_to_rad(fposmod(float(
        N43.initial_facility_angle(location)) +
        360.0 * native_units / SolOrbits.STATION_ORBIT_PERIOD_NATIVE, 360.0))
    return {"ok": true, "position": parent["position"] +
        Vector2(cos(angle), sin(angle)) * local_radius,
        "native_radius": local_radius}


## A physical ship leaving a 800-km dock is still physically only a
## fraction of a *native* Earth radius away. The presentation draws Earth
## as an enormous selectable disc. Straight global radial projection
## therefore puts the authentic near-Earth ship INSIDE that display disc.
## Do not fade the dock's screen offset toward Earth's CENTER as before.
## Instead use the real planetocentric DIRECTION and maintain a bounded
## display clearance until the underlying system map catches up.
##
## This is a pure CanvasItem projection. Ships inside the actual physical
## surface are intentionally left uncorrected so a simulation collision
## is not hidden by the interface. One Sol station => O(ships), with no
## N14 aim_point, world traversal, rendering node, or economy mutation.
const SCREEN_TRANSITION_MULTIPLIER: float = 1.6

static func corrected_screen(native_position: Vector2,
        global_screen: Vector2, station_records: Array) -> Vector2:
    var chosen: Dictionary = {}
    var chosen_gap: float = INF
    for station in station_records:
        if not (station is Dictionary) or not (
                station.get("native") is Vector2) or not (
                station.get("screen") is Vector2) or not (
                station.get("body_native") is Vector2) or not (
                station.get("body_screen") is Vector2) or not (
                station.get("body_global_screen") is Vector2):
            continue
        var center: Vector2 = station["body_native"]
        var distance: float = native_position.distance_to(center)
        var true_radius: float = float(
            station.get("body_native_radius", -1.0))
        if not is_finite(distance) or true_radius <= 0.0 or (
                distance <= true_radius):
            # Actual surface intersections remain visible and diagnosable.
            continue
        var native_delta: Vector2 = native_position - center
        var screen_delta: Vector2 = global_screen - (
            station["body_global_screen"] as Vector2)
        var unscaled_distance: float = screen_delta.length()
        var ring_radius: float = float(
            station.get("screen_orbit_radius", 0.0))
        if ring_radius <= 0.0 or unscaled_distance >= (
                ring_radius * SCREEN_TRANSITION_MULTIPLIER):
            continue
        if distance < chosen_gap:
            chosen_gap = distance
            chosen = station
    if chosen.is_empty():
        return global_screen
    if native_position.distance_to(
            chosen["native"] as Vector2) <= 0.0000001:
        return chosen["screen"] # exact native N14–N43 docking pixel
    var native_direction: Vector2 = native_position - (
        chosen["body_native"] as Vector2)
    var outward: Vector2 = Vector2(
        native_direction.x, -native_direction.y).normalized()
    var screen_displacement: Vector2 = global_screen - (
        chosen["body_global_screen"] as Vector2)
    var baseline: float = screen_displacement.length()
    var minimum: float = float(chosen["screen_orbit_radius"])
    # Use a MONOTONIC outward mapping: not a stationary rim clamp or
    # fading station offset that sends vessels into the globe center.
    # As the uncorrected screen displacement grows, the safety boost
    # vanishes smoothly and the system map takes over.
    var x: float = clampf(
        baseline / (minimum * SCREEN_TRANSITION_MULTIPLIER), 0.0, 1.0)
    var smooth: float = x * x * (3.0 - 2.0 * x)
    var radial: float = baseline + minimum * (1.0 - smooth)
    var safe_point: Vector2 = (
        chosen["body_screen"] as Vector2) + outward * radial
    return safe_point.lerp(global_screen, smooth)
