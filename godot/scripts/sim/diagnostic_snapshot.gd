extends RefCounted
## P1 read-only diagnostic projection. Not a persistence schema or live
## economy snapshot. Rust: sim_core/agents/ship/snapshot.rs builds snapshots
## from authoritative components; the UI never owns mutable game state.
## This projection only reports fields actually loaded in the P1 world.

static func capture(runner: RefCounted) -> Dictionary:
    if not runner.is_started():
        return {"error": "world_not_started"}
    var worlds: Array = runner.world.worlds()
    var factions: Array = runner.world.factions()
    var system_ids: Array[String] = []
    var body_ids: Array[String] = []
    var facility_ids: Array[String] = []
    var route_keys: Array[String] = []
    var ship_count: int = 0
    var market_count: int = 0
    var population_count: int = 0
    var warnings: Array[String] = []
    var seen: Dictionary = {}
    for world in worlds:
        var system: Dictionary = world.get("system", {})
        var sid: String = str(system.get("id", ""))
        _register_id(sid, "system", seen, warnings)
        system_ids.append(sid)
        for body in world.get("bodies", []):
            var bid: String = str(body.get("id", ""))
            _register_id(bid, "body", seen, warnings)
            body_ids.append(bid)
            var period: float = float(body.get("orbit_period", 0.0))
            var angle: float = float(body.get("current_angle", -1.0))
            if not is_finite(period) or period <= 0.0 or not is_finite(angle) or angle < 0.0 or angle >= 360.0:
                warnings.append("invalid_orbit:" + bid)
        for facility in world.get("facilities", []):
            var fid: String = str(facility.get("id", ""))
            _register_id(fid, "facility", seen, warnings)
            facility_ids.append(fid)
        for route in world.get("travel_routes", []):
            route_keys.append(str(route.get("from", "")) + ">" + str(route.get("to", "")) + ":" + str(route.get("distance", "")))
        ship_count += world.get("ships", []).size()
        market_count += world.get("markets", []).size()
        population_count += world.get("populations", []).size()
    system_ids.sort()
    body_ids.sort()
    facility_ids.sort()
    route_keys.sort()
    warnings.sort()
    var angles: Dictionary = runner.world.orbital_snapshot()
    var ordered_angles: Array[Dictionary] = []
    for bid in body_ids:
        ordered_angles.append({"id": bid, "angle": angles.get(bid, null)})
    return {
        "kind": "p1-read-only-diagnostics",
        "tick": runner.tick_count,
        "seed_fingerprint": runner.world.seed_fingerprint(),
        "systems": system_ids,
        "bodies": body_ids,
        "facilities": facility_ids,
        "routes": route_keys,
        "faction_count": factions.size(),
        "ship_count": ship_count,
        "market_count": market_count,
        "population_count": population_count,
        "orbital_angles": ordered_angles,
        "warnings": warnings,
        "implemented_phases": Array(runner.implemented_phases()),
        "economic_state_available": false
    }

static func _register_id(id: String, category: String, seen: Dictionary, warnings: Array[String]) -> void:
    if id.is_empty():
        warnings.append("missing_id:" + category)
    elif seen.has(category + ":" + id):
        warnings.append("duplicate_id:" + category + ":" + id)
    else:
        seen[category + ":" + id] = true
