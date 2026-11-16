extends RefCounted
## N43: data-only world coordinates, never renderer/screen coordinates.
## Frozen Rust: celestial_body::BodyOrbit::universe_position(),
## facility::FacilityOrbit + facility_orbit_initial_angle/position().
## Route distance is only routing cost; it is NOT world-space geometry.

const WorldModel = preload("res://scripts/sim/world_model.gd")
const SatelliteProfile = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")
const NativeChart = preload("res://scripts/sim/phase2/unified_n142_original_colony_chart.gd")
const FACILITY_ORBIT_RADIUS: float = 0.55
const FACILITY_ORBIT_PERIOD: float = 8000.0
const HASH_OFFSET: int = 2166136261
const HASH_PRIME: int = 16777619
const HASH_MASK: int = 0xffffffff

var _bodies: Dictionary = {}
var _locations: Dictionary = {}
var _fingerprint: String = ""
var _loaded: bool = false

func load_seed(seed: Dictionary) -> bool:
    var checked = WorldModel.new()
    if not checked.load_seed(seed):
        return false
    var staged_bodies: Dictionary = {}
    var staged_locations: Dictionary = {}
    for item in seed.get("worlds", []):
        if not (item is Dictionary):
            return false
        var source_world: Dictionary = item
        var system: Dictionary = source_world.get("system", {})
        var sid: String = str(system.get("id", ""))
        var raw_offset: Variant = system.get("universe_offset", null)
        if sid.is_empty() or not (raw_offset is Array) or raw_offset.size() != 2:
            return false
        if not _finite_number(raw_offset[0]) or not _finite_number(raw_offset[1]):
            return false
        var offset := Vector2(float(raw_offset[0]), float(raw_offset[1]))
        var system_bodies: Dictionary = {}
        var verified_sol: bool = (
            sid == "system-sol" and str(
                checked.system_by_id(sid).get(
                    "navigation_geometry_profile", "")) ==
                SatelliteProfile.NAVIGATION_GEOMETRY_VERSION)
        for source in source_world.get("bodies", []):
            if not (source is Dictionary):
                return false
            var raw_body: Dictionary = source
            var bid: String = str(raw_body.get("id", ""))
            # WorldModel is the SINGLE owner of the derived, versioned
            # physical Sol satellite metadata. Do not independently guess
            # moon parents in the ship resolver.
            var checked_info: Dictionary = checked.body_by_id(bid)
            if checked_info.is_empty() or not (
                    checked_info.get("value") is Dictionary):
                return false
            var body: Dictionary = checked_info["value"]
            var radius: Variant = body.get("orbit_radius", null)
            if bid.is_empty() or staged_bodies.has(bid) or not _finite_number(radius):
                return false
            if float(radius) < 0.0:
                return false
            var period: Variant = body.get(
                "satellite_orbit_period_native", body.get("orbit_period", null))
            if not _finite_number(period) or float(period) <= 0.0:
                return false
            var parent_id: String = str(body.get("parent_body_id", ""))
            var local_radius: Variant = body.get("satellite_orbit_radius_native", null)
            if not parent_id.is_empty() and (
                    str(body.get("type", "")) != "moon" or
                    not _finite_number(local_radius) or float(local_radius) <= 0.0):
                return false
            var station_radius: float = FACILITY_ORBIT_RADIUS
            var native_body_radius: float = 0.0
            if verified_sol:
                native_body_radius = SatelliteProfile.physical_radius_native(bid)
                if native_body_radius > 0.0:
                    station_radius = SatelliteProfile.compact_station_orbit_radius(bid)
            staged_bodies[bid] = {
                "system_id": sid, "radius": float(radius), "period": float(period),
                "offset": offset, "parent_id": parent_id,
                "local_radius": float(local_radius) if not parent_id.is_empty() else 0.0,
                "station_radius": station_radius,
                "physical_radius": native_body_radius
            }
            system_bodies[bid] = true
        for source in source_world.get("facilities", []):
            if not (source is Dictionary):
                return false
            var facility: Dictionary = source
            var loc: String = str(facility.get("location", ""))
            var body_id: String = str(facility.get("body", ""))
            var capacity: Variant = facility.get("docking_capacity", 0)
            # Godot JSON may decode integral numbers as floats.
            if not _finite_number(capacity) or float(capacity) < 0.0 or float(capacity) != float(int(capacity)):
                return false
            if not _register(staged_locations, loc, body_id, sid, int(capacity) > 0, system_bodies):
                return false
        for source in source_world.get("nav_sites", []):
            if not (source is Dictionary):
                return false
            var site: Dictionary = source
            if not _register(staged_locations, str(site.get("name", "")),
                    str(site.get("body", "")), sid, false, system_bodies):
                return false
    # Explicit future parent-relative metadata must be internally valid:
    # same source system, no missing parents, no orbital cycles/deep chains.
    # The original Rust source files have no parent IDs. The WorldModel
    # profile provides physically coherent Sol moon metadata in the
    # derived runtime without changing those files.
    for bid in staged_bodies:
        var seen: Dictionary = {}
        var current: String = str(bid)
        var depth: int = 0
        while not current.is_empty():
            if seen.has(current) or not staged_bodies.has(current):
                return false
            seen[current] = true
            depth += 1
            if depth > 4:
                return false
            var info: Dictionary = staged_bodies[current]
            if str(info["system_id"]) != str(staged_bodies[bid]["system_id"]):
                return false
            current = str(info.get("parent_id", ""))
    # Native Rust spawner::chart_colony_routes registers empty planet
    # endpoints before any ship, market, household or facility exists.
    # An unbuilt colony target is the real planet's moving orbit, not
    # a fictitious stationary dock or free settlement.
    var chart: Dictionary = NativeChart.chart(seed.get("worlds", []))
    if not chart.get("ok", false):
        return false
    for colony_location in chart.get("charted", {}):
        var entry: Dictionary = chart["charted"][colony_location]
        var bid: String = str(entry["body_id"])
        var sid: String = str(entry["system_id"])
        if not staged_bodies.has(bid) or str(staged_bodies[bid]["system_id"]) != sid:
            return false
        var catalog: Dictionary = {}
        catalog[bid] = true
        if not _register(staged_locations, str(colony_location), bid, sid, false, catalog):
            return false
    if staged_bodies.is_empty() or staged_locations.is_empty():
        return false
    _bodies = staged_bodies
    _locations = staged_locations
    _fingerprint = checked.seed_fingerprint()
    _loaded = true
    return true

func _register(target: Dictionary, location: String, body_id: String,
        system_id: String, station: bool, system_bodies: Dictionary) -> bool:
    if location.is_empty() or body_id.is_empty() or not system_bodies.has(body_id):
        return false
    if target.has(location):
        var previous: Dictionary = target[location]
        if previous["body_id"] != body_id or previous["system_id"] != system_id:
            # A single name cannot silently select a body/system.
            return false
        previous["station"] = bool(previous["station"]) or station
        return true
    target[location] = {
        "system_id": system_id, "body_id": body_id, "station": station
    }
    return true

func is_loaded() -> bool:
    return _loaded

func is_mapped(location: String) -> bool:
    return _loaded and _locations.has(location)

func location_count() -> int:
    return _locations.size()


## Actual source system ID of a navigation location after N14 arrival.
## It is NOT inferred from screen coordinates or from a ship's home system.
func system_for_location(location: String) -> String:
    return str(_locations[location]["system_id"]) if _loaded and _locations.has(location) else ""

## Original frozen BodyIdentity.system_name for a real facility's
## Body ID; new facilities may be at locations absent from the seed's
## initial N43 nav registry. Source bodies NEVER come from UI pixels.
func system_for_body(body_id: String) -> String:
    return str(_bodies[body_id]["system_id"]) if _loaded and _bodies.has(body_id) else ""

## Original WorldRegistry location -> BodyIdentity link used by Rust
## ship/mod.rs::observe_prices. Do not infer from display coords.
func body_for_location(location: String) -> String:
    return str(_locations[location]["body_id"]) if _loaded and _locations.has(location) else ""


## Exactly the physical radius used by N43 and N14 stations. The
## original foreign-system 0.55 orbit is retained until verified geometry.
func station_radius_for_location(location: String) -> float:
    if not _loaded or not _locations.has(location):
        return -1.0
    var bid: String = str(_locations[location]["body_id"])
    return float(_bodies.get(bid, {}).get(
        "station_radius", FACILITY_ORBIT_RADIUS))


## Exact final approach to Sol physical bodies. Not a tolerance used for
## screen-space picking or a free Rust 0.01-unit arrival bubble.
func arrival_tolerance_for_location(location: String) -> float:
    if not _loaded or not _locations.has(location):
        return -1.0
    var bid: String = str(_locations[location]["body_id"])
    var body_radius: float = float(_bodies.get(bid, {}).get(
        "physical_radius", 0.0))
    if body_radius <= 0.0:
        return 0.01 # frozen legacy behavior elsewhere
    return clampf(body_radius * 0.20, 0.000003, 0.00008)


## Star center is the unchanged source system offset. Only verified Sol
## uses the physical star exclusion radius; all other star metrics unknown.
func verified_solar_exclusion(system_id: String) -> Dictionary:
    if system_id != "system-sol":
        return {}
    if not _loaded or not _bodies.has("earth") or not (
            float(_bodies["earth"].get("physical_radius", 0.0)) > 0.0):
        return {}
    return {"id": "sol-star", "center": _bodies["earth"]["offset"],
        "radius": 0.20, "system_id": system_id}


## One bounded planet list per real N140 system/tick. A station may
## take a route past several bodies, but collision tests only consider
## real physical radii, not oversized display glyphs or fake orbits.
## The caller caches this result across every fired ship in that system.
func verified_planet_obstacles(system_id: String,
        model: RefCounted) -> Array:
    if not _loaded or system_id != "system-sol" or model == null or (
            not model.has_method("orbital_snapshot") or
            not model.has_method("seed_fingerprint") or
            model.seed_fingerprint() != _fingerprint):
        return []
    if not _bodies.has("earth") or float(_bodies["earth"].get(
            "physical_radius", 0.0)) <= 0.0:
        return []
    var computed: Dictionary = _body_positions_from_angles(
        model.orbital_snapshot())
    if not computed.get("ok", false):
        return []
    var obstacles: Array = []
    var ids: Array = _bodies.keys()
    ids.sort()
    for bid in ids:
        var body: Dictionary = _bodies[bid]
        if str(body["system_id"]) != system_id:
            continue
        var radius: float = float(body.get("physical_radius", 0.0))
        if radius <= 0.0:
            continue
        # 3% clearance around the real surface, not a fake visual
        # marker radius. Unknown bodies cannot be guessed safely.
        obstacles.append({
            "id": str(bid),
            "center": computed["positions"][bid],
            "radius": radius * 1.03
        })
    return obstacles


## Frozen Rust BodyOrbit::universe_offset comes from the original
## registered source system, NOT the rendered body's orbital position.
## N97 mine must prove ship.system_id == target body system before
## comparing these offsets (equal offsets alone do not prove it).
func source_system_offset_for_body(body_id: String) -> Array:
    if not _loaded or not _bodies.has(body_id):
        return []
    var source: Variant = _bodies[body_id].get("offset", null)
    if not (source is Vector2):
        return []
    return [source.x, source.y]


## Build physical native world positions from the SAME orbital angles
## as N14, station geometry and predictive ephemerides. Explicit source
## metadata and versioned verified Sol satellite profiles share the
## same position resolver; unknown moons are never reparented.
func _resolve_body_position(body_id: String, angles: Dictionary,
        known: Dictionary, ancestors: Dictionary) -> Variant:
    if known.has(body_id):
        return known[body_id]
    if ancestors.has(body_id) or not _bodies.has(body_id):
        return null
    var info: Dictionary = _bodies[body_id]
    var angle: Variant = angles.get(body_id, null)
    if not _finite_number(angle) or float(angle) < 0.0 or float(angle) >= 360.0:
        return null
    var theta: float = deg_to_rad(float(angle))
    var center: Vector2 = info["offset"]
    var radius: float = float(info["radius"])
    var parent_id: String = str(info.get("parent_id", ""))
    if not parent_id.is_empty():
        var nested_ancestors: Dictionary = ancestors.duplicate()
        nested_ancestors[body_id] = true
        var parent_position: Variant = _resolve_body_position(
            parent_id, angles, known, nested_ancestors)
        if not (parent_position is Vector2):
            return null
        center = parent_position
        radius = float(info["local_radius"])
    var result: Vector2 = center + Vector2(cos(theta), sin(theta)) * radius
    known[body_id] = result
    return result


func _body_positions_from_angles(angles: Dictionary) -> Dictionary:
    if angles.size() != _bodies.size():
        return {"ok": false, "error": "body_angle_count_mismatch"}
    var known: Dictionary = {}
    for bid in _bodies:
        if not (_resolve_body_position(str(bid), angles,
                known, {}) is Vector2):
            return {"ok": false, "error": "invalid_body_orbit"}
    return {"ok": true, "positions": known}


## The same native body position used by the route resolver and N14.
func body_universe_position(body_id: String, model: RefCounted) -> Dictionary:
    if not _loaded or model == null or not _bodies.has(body_id) or not (
            model.has_method("orbital_snapshot")):
        return {"ok": false, "reason": "unknown_original_body_or_model"}
    if model.has_method("seed_fingerprint") and (
            model.seed_fingerprint() != _fingerprint):
        return {"ok": false, "reason": "wrong_original_seed"}
    var known: Dictionary = {}
    var result: Variant = _resolve_body_position(
        body_id, model.orbital_snapshot(), known, {})
    if not (result is Vector2):
        return {"ok": false, "reason": "invalid_body_orbit"}
    return {"ok": true, "position": result}


## Map current committed World orbital angles to a deterministic,
## forward-predictable N14 trajectory WITHOUT mutating World or clock.
## Physical parent-relative components are enabled by explicit seed
## metadata or the verified, versioned Sol model profile.
func _components_for_body(body_id: String, angles: Dictionary,
        seen: Dictionary) -> Array:
    if not _bodies.has(body_id) or seen.has(body_id):
        return []
    var info: Dictionary = _bodies[body_id]
    var angle: Variant = angles.get(body_id, null)
    if not _finite_number(angle) or float(angle) < 0.0 or float(angle) >= 360.0:
        return []
    var result: Array = []
    var parent_id: String = str(info.get("parent_id", ""))
    if not parent_id.is_empty():
        var next_seen: Dictionary = seen.duplicate()
        next_seen[body_id] = true
        result = _components_for_body(parent_id, angles, next_seen)
        if result.is_empty():
            return []
    var r: float = float(info["local_radius"]) if not parent_id.is_empty() else (
        float(info["radius"]))
    result.append({"radius": r, "angle": float(angle),
        "period": float(info["period"])})
    return result


func ephemeris_for_location(location: String, model: RefCounted,
        elapsed_native_units: float, origin_known: bool = true) -> Dictionary:
    if not _loaded or not _locations.has(location) or model == null or (
            not model.has_method("orbital_snapshot")) or (
            not model.has_method("seed_fingerprint")) or (
            model.seed_fingerprint() != _fingerprint):
        return {"ok": false, "reason": "unmapped_or_unverified_location"}
    if not origin_known or not _finite_number(elapsed_native_units) or (
            elapsed_native_units < 0.0):
        return {"ok": false, "reason": "unknown_native_time"}
    var info: Dictionary = _locations[location]
    var body_id: String = str(info["body_id"])
    var orbits: Array = _components_for_body(
        body_id, model.orbital_snapshot(), {})
    if orbits.is_empty():
        return {"ok": false, "reason": "missing_body_ephemeris"}
    if bool(info["station"]):
        orbits.append({"radius": float(_bodies[body_id]["station_radius"]),
            "angle": fposmod(
                float(initial_facility_angle(location)) +
                360.0 * elapsed_native_units / FACILITY_ORBIT_PERIOD, 360.0),
            "period": FACILITY_ORBIT_PERIOD})
    if orbits.size() > 4:
        return {"ok": false, "reason": "ephemeris_depth_exceeded"}
    return {"ok": true, "trajectory": {
        "center": _bodies[body_id]["offset"],
        "components": orbits
    }}


## Derive every mapped location from CURRENT orbital angles and committed
## native elapsed time, not from route length, seed angle, or UI projection.
func positions_from_world(model: RefCounted, elapsed_native_units: float,
        origin_known: bool = true) -> Dictionary:
    if not _loaded or model == null or not model.has_method("orbital_snapshot"):
        return {"ok": false, "error": "uninitialized_resolver"}
    if not origin_known or not _finite_number(elapsed_native_units) or (
            elapsed_native_units < 0.0):
        return {"ok": false, "error": "unknown_or_invalid_native_time"}
    if not model.has_method("seed_fingerprint") or (
            model.seed_fingerprint() != _fingerprint):
        return {"ok": false, "error": "seed_fingerprint_mismatch"}
    var computed: Dictionary = _body_positions_from_angles(
        model.orbital_snapshot())
    if not computed.get("ok", false):
        return computed
    var body_positions: Dictionary = computed["positions"]
    var positions: Dictionary = {}
    for loc in _locations:
        var info: Dictionary = _locations[loc]
        var body_center: Vector2 = body_positions[info["body_id"]]
        if bool(info["station"]):
            var initial_angle: float = float(initial_facility_angle(str(loc)))
            var phase: float = deg_to_rad(fposmod(
                initial_angle +
                360.0 * elapsed_native_units / FACILITY_ORBIT_PERIOD, 360.0))
            positions[loc] = body_center + Vector2(
                cos(phase), sin(phase)) * float(
                _bodies[str(info["body_id"])]["station_radius"])
        else:
            positions[loc] = body_center
    return {"ok": true, "positions": positions}


## Exact FNV-1a u32 wrapping used in frozen Rust facility components.
static func initial_facility_angle(location: String) -> int:
    var value: int = HASH_OFFSET
    for byte_value in location.to_utf8_buffer():
        value = ((value ^ int(byte_value)) * HASH_PRIME) & HASH_MASK
    return value % 360

static func _finite_number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))
