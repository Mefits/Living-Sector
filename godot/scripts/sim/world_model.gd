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

func load_seed(seed: Dictionary) -> bool:
    if seed.has("error") or not seed.has("worlds") or not seed.has("factions"):
        return false
    var systems: Dictionary = {}
    var bodies: Dictionary = {}
    var facilities: Dictionary = {}
    var routes: Dictionary = {}
    var copies: Array = []
    for incoming_world in seed["worlds"]:
        if not (incoming_world is Dictionary):
            return false
        # Scene/UI code must never alter the seed's source structures.
        var world: Dictionary = incoming_world.duplicate(true)
        var system: Dictionary = world.get("system", {})
        var sid: String = str(system.get("id", ""))
        if sid.is_empty() or systems.has(sid):
            return false
        systems[sid] = world
        for body in world.get("bodies", []):
            var bid: String = str(body.get("id", ""))
            if bid.is_empty() or bodies.has(bid):
                return false
            bodies[bid] = {"system_id": sid, "value": body}
        for facility in world.get("facilities", []):
            var fid: String = str(facility.get("id", ""))
            if fid.is_empty() or facilities.has(fid):
                return false
            facilities[fid] = {"system_id": sid, "value": facility}
        for route in world.get("travel_routes", []):
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
    var coords: Array = world.get("system", {}).get("universe_offset", [0, 0])
    if coords.size() != 2:
        return Vector2.ZERO
    # Native universe_offset is an arbitrary world-space coordinate, NOT ly.
    return Vector2(float(coords[0]), float(coords[1]))
