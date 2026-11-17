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


## An orbital icon is drawn outside a deliberately oversized planet glyph.
## At an actual docked station coordinate this maps EXACTLY onto its icon.
## The correction fades to zero outside a bounded native neighborhood,
## avoiding independent free-floating station/ship display geometries.
## 500 ships x 1 station => 500 trivial distance checks; no N14 solver.
static func corrected_screen(native_position: Vector2,
        global_screen: Vector2, station_records: Array) -> Vector2:
    var chosen: Dictionary = {}
    var best_ratio: float = INF
    for station in station_records:
        if not (station is Dictionary) or not (
                station.get("native") is Vector2) or not (
                station.get("screen") is Vector2) or not (
                station.get("native_global_screen") is Vector2):
            continue
        var local_radius: float = float(
            station.get("native_radius", 0.0))
        if local_radius <= 0.0:
            continue
        var fade_radius: float = clampf(
            local_radius * 100.0,
            MIN_LOCAL_BLEND_RADIUS, MAX_LOCAL_BLEND_RADIUS)
        var gap: float = native_position.distance_to(
            station["native"])
        var ratio: float = gap / fade_radius
        if ratio >= 1.0 or ratio >= best_ratio:
            continue
        best_ratio = ratio
        chosen = station
    if chosen.is_empty():
        return global_screen
    var t: float = clampf(best_ratio, 0.0, 1.0)
    var weight: float = 1.0 - t * t * (3.0 - 2.0 * t)
    return global_screen + (
        (chosen["screen"] as Vector2) -
        (chosen["native_global_screen"] as Vector2)) * weight
