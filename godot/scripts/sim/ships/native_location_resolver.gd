extends RefCounted
## N43: data-only world coordinates, never renderer/screen coordinates.
## Frozen Rust: celestial_body::BodyOrbit::universe_position(),
## facility::FacilityOrbit + facility_orbit_initial_angle/position().
## Route distance is only routing cost; it is NOT world-space geometry.

const WorldModel = preload("res://scripts/sim/world_model.gd")
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
        for source in source_world.get("bodies", []):
            if not (source is Dictionary):
                return false
            var body: Dictionary = source
            var bid: String = str(body.get("id", ""))
            var radius: Variant = body.get("orbit_radius", null)
            if bid.is_empty() or staged_bodies.has(bid) or not _finite_number(radius):
                return false
            if float(radius) < 0.0:
                return false
            staged_bodies[bid] = {"system_id": sid, "radius": float(radius), "offset": offset}
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

## Original WorldRegistry location -> BodyIdentity link used by Rust
## ship/mod.rs::observe_prices. Do not infer from display coords.
func body_for_location(location: String) -> String:
    return str(_locations[location]["body_id"]) if _loaded and _locations.has(location) else ""

## Derive every mapped location from CURRENT orbital angles and committed
## native elapsed time, not from route length, seed angle, or a UI projection.
## If an old checkpoint lacks the clock origin, station phase is unknown.
func positions_from_world(model: RefCounted, elapsed_native_units: float,
        origin_known: bool = true) -> Dictionary:
    if not _loaded or model == null or not model.has_method("orbital_snapshot"):
        return {"ok": false, "error": "uninitialized_resolver"}
    if not origin_known or not _finite_number(elapsed_native_units) or elapsed_native_units < 0.0:
        return {"ok": false, "error": "unknown_or_invalid_native_time"}
    if not model.has_method("seed_fingerprint") or model.seed_fingerprint() != _fingerprint:
        return {"ok": false, "error": "seed_fingerprint_mismatch"}
    var angles: Dictionary = model.orbital_snapshot()
    if angles.size() != _bodies.size():
        return {"ok": false, "error": "body_count_mismatch"}
    var body_positions: Dictionary = {}
    for bid in _bodies:
        var angle: Variant = angles.get(bid, null)
        if not _finite_number(angle) or float(angle) < 0.0 or float(angle) >= 360.0:
            return {"ok": false, "error": "missing_or_invalid_body_angle"}
        var info: Dictionary = _bodies[bid]
        var theta: float = deg_to_rad(float(angle))
        var offset: Vector2 = info["offset"]
        var radius: float = float(info["radius"])
        body_positions[bid] = offset + Vector2(cos(theta), sin(theta)) * radius
    var positions: Dictionary = {}
    for loc in _locations:
        var info: Dictionary = _locations[loc]
        var body_center: Vector2 = body_positions[info["body_id"]]
        if bool(info["station"]):
            var initial_angle: float = float(initial_facility_angle(str(loc)))
            var phase: float = deg_to_rad(fposmod(
                initial_angle + 360.0 * elapsed_native_units / FACILITY_ORBIT_PERIOD, 360.0))
            positions[loc] = body_center + Vector2(cos(phase), sin(phase)) * FACILITY_ORBIT_RADIUS
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
