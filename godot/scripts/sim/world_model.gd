extends RefCounted
## First Godot world model, intentionally independent of SceneTree.
## Identity and geometry are taken verbatim from the imported Rust seed.
## No economy, production, movement, AI or ticks are simulated here.

var _worlds: Array = []
var _factions: Array = []
var _systems_by_id: Dictionary = {}
var _bodies_by_id: Dictionary = {}
var _facilities_by_id: Dictionary = {}
var _routes_by_location: Dictionary = {}
var _source_path: String = ""
var _seed_stats: Dictionary = {}
var _loaded: bool = false
var _seed_fingerprint: String = ""

func load_seed(seed: Dictionary) -> bool:
    if seed.has("error"):
        return false
    var incoming_worlds: Variant = seed.get("worlds", null)
    var incoming_factions: Variant = seed.get("factions", null)
    if not (incoming_worlds is Array) or not (incoming_factions is Array):
        return false
    var systems: Dictionary = {}
    var bodies: Dictionary = {}
    var facilities: Dictionary = {}
    var routes: Dictionary = {}
    var copies: Array = []
    for incoming_world in incoming_worlds:
        if not (incoming_world is Dictionary):
            return false
        # Scene/UI code must never alter the seed's source structures.
        var world: Dictionary = incoming_world.duplicate(true)
        var system_value: Variant = world.get("system", null)
        if not (system_value is Dictionary):
            return false
        var system: Dictionary = system_value
        var sid: String = str(system.get("id", ""))
        if sid.is_empty() or systems.has(sid):
            return false
        var body_list: Variant = world.get("bodies", [])
        var facility_list: Variant = world.get("facilities", [])
        var route_list: Variant = world.get("travel_routes", [])
        if not (body_list is Array) or not (facility_list is Array) or not (route_list is Array):
            return false
        systems[sid] = world
        for body_value in body_list:
            if not (body_value is Dictionary):
                return false
            var body: Dictionary = body_value
            var bid: String = str(body.get("id", ""))
            if bid.is_empty() or bodies.has(bid):
                return false
            var period_value: Variant = body.get("orbit_period", null)
            var angle_value: Variant = body.get("current_angle", null)
            if not (period_value is int or period_value is float) or not (angle_value is int or angle_value is float):
                return false
            if not is_finite(float(period_value)) or float(period_value) <= 0.0:
                return false
            if not is_finite(float(angle_value)) or float(angle_value) < 0.0 or float(angle_value) >= 360.0:
                return false
            bodies[bid] = {"system_id": sid, "value": body}
        for facility_value in facility_list:
            if not (facility_value is Dictionary):
                return false
            var facility: Dictionary = facility_value
            var fid: String = str(facility.get("id", ""))
            if fid.is_empty() or facilities.has(fid):
                return false
            facilities[fid] = {"system_id": sid, "value": facility}
        for route_value in route_list:
            if not (route_value is Dictionary):
                return false
            var route: Dictionary = route_value
            var from_id: String = str(route.get("from", ""))
            if from_id.is_empty():
                return false
            if not routes.has(from_id):
                routes[from_id] = []
            routes[from_id].append(route)
        copies.append(world)
    _worlds = copies
    _factions = seed["factions"].duplicate(true)
    _systems_by_id = systems
    _bodies_by_id = bodies
    _facilities_by_id = facilities
    _routes_by_location = routes
    _source_path = str(seed.get("source", ""))
    _seed_stats = seed.get("seed_stats", {}).duplicate(true)
    _seed_fingerprint = JSON.stringify([_worlds, _factions]).sha256_text()
    _loaded = true
    return true

func is_loaded() -> bool:
    return _loaded

func worlds() -> Array:
    return _worlds.duplicate(true)

func factions() -> Array:
    return _factions.duplicate(true)

func seed_stats() -> Dictionary:
    return _seed_stats.duplicate(true)

func source_path() -> String:
    return _source_path

func system_by_id(system_id: String) -> Dictionary:
    if not _systems_by_id.has(system_id):
        return {}
    return _systems_by_id[system_id].duplicate(true)

func body_by_id(body_id: String) -> Dictionary:
    if not _bodies_by_id.has(body_id):
        return {}
    return _bodies_by_id[body_id].duplicate(true)

func facility_by_id(facility_id: String) -> Dictionary:
    if not _facilities_by_id.has(facility_id):
        return {}
    return _facilities_by_id[facility_id].duplicate(true)

func direct_routes_from(location: String) -> Array:
    if not _routes_by_location.has(location):
        return []
    return _routes_by_location[location].duplicate(true)

func seed_universe_position(system_id: String) -> Vector2:
    var world: Dictionary = _systems_by_id.get(system_id, {})
    var raw_coords: Variant = world.get("system", {}).get("universe_offset", null)
    if not (raw_coords is Array) or raw_coords.size() != 2:
        return Vector2.ZERO
    if not (raw_coords[0] is int or raw_coords[0] is float) or not (raw_coords[1] is int or raw_coords[1] is float):
        return Vector2.ZERO
    if not is_finite(float(raw_coords[0])) or not is_finite(float(raw_coords[1])):
        return Vector2.ZERO
    # Native universe_offset is an arbitrary world-space coordinate, NOT ly.
    return Vector2(float(raw_coords[0]), float(raw_coords[1]))

## Rust BodyOrbit::advance: 360 / orbit_period * tick_scale, wrapped to 360.
## Only orbital angles change in P1. Markets, stocks, ships and factions do NOT
## advance until their Rust rules are actually ported.
func advance_orbits(tick_scale: float) -> void:
    if not _loaded or not is_finite(tick_scale) or tick_scale < 0.0:
        return
    for body_id in _bodies_by_id:
        var info: Dictionary = _bodies_by_id[body_id]
        var body: Dictionary = info["value"]
        var period_value: Variant = body.get("orbit_period", null)
        var angle_value: Variant = body.get("current_angle", null)
        if not (period_value is int or period_value is float) or not (angle_value is int or angle_value is float):
            continue
        var period: float = float(period_value)
        var old_angle: float = float(angle_value)
        if not is_finite(period) or period <= 0.0 or not is_finite(old_angle):
            continue
        body["current_angle"] = fposmod(
            old_angle + (360.0 / period) * tick_scale, 360.0
        )

func seed_fingerprint() -> String:
    return _seed_fingerprint

func orbital_snapshot() -> Dictionary:
    var angles: Dictionary = {}
    for body_id in _bodies_by_id:
        angles[body_id] = float(_bodies_by_id[body_id]["value"].get("current_angle", 0.0))
    return angles

func restore_orbital_snapshot(angles: Dictionary) -> bool:
    # Full preflight before any mutation: invalid / partial saves fail atomically.
    if not _loaded or angles.size() != _bodies_by_id.size():
        return false
    for body_id in _bodies_by_id:
        if not angles.has(body_id):
            return false
        var value: Variant = angles[body_id]
        if not (value is float or value is int):
            return false
        if not is_finite(float(value)) or float(value) < 0.0 or float(value) >= 360.0:
            return false
    for body_id in _bodies_by_id:
        var body: Dictionary = _bodies_by_id[body_id]["value"]
        body["current_angle"] = float(angles[body_id])
    return true
