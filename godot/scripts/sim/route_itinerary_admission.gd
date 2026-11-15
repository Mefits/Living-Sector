extends RefCounted
## N60: read-only admission for a planned sequence of directed native route legs.
## The Rust seed travel_routes distance is an abstract routing weight, NOT
## ship displacement, light-years, fuel cost or a teleport authorization.
## All errors fail closed; this component never mutates graph, fleet or money.

const MAX_HOPS := 256

func admit(graph: RefCounted, origin: String, destination: String, locations: Array, expected_distance: float = -1.0) -> Dictionary:
    if origin.is_empty() or destination.is_empty():
        return _reject("empty_endpoint")
    if not graph.has_location(origin) or not graph.has_location(destination):
        return _reject("unknown_endpoint")
    if locations.is_empty() or locations.size() > MAX_HOPS + 1:
        return _reject("invalid_length")
    if locations.size() < 2 or origin == destination:
        return _reject("no_travel")
    if not (locations[0] is String) or not (locations[locations.size() - 1] is String):
        return _reject("invalid_location")
    if locations[0] != origin or locations[locations.size() - 1] != destination:
        return _reject("stale_endpoints")
    if not is_finite(expected_distance):
        return _reject("invalid_expected_distance")
    var visited: Dictionary = {}
    var legs: Array = []
    var total := 0.0
    for i in range(locations.size()):
        var location: Variant = locations[i]
        if not (location is String) or location.is_empty():
            return _reject("invalid_location")
        if not graph.has_location(location):
            return _reject("unknown_location")
        if visited.has(location):
            return _reject("repeated_location")
        visited[location] = true
        if i == 0:
            continue
        var previous: String = locations[i - 1]
        var matched := false
        var weight := 0.0
        var system_id := ""
        for edge in graph.outgoing(previous):
            if not (edge is Dictionary):
                return _reject("invalid_edge")
            if str(edge.get("to", "")) == location:
                if matched:
                    return _reject("duplicate_edge")
                var raw: Variant = edge.get("distance", null)
                if not (raw is int or raw is float):
                    return _reject("invalid_edge")
                weight = float(raw)
                if not is_finite(weight) or weight <= 0.0:
                    return _reject("invalid_edge")
                system_id = str(edge.get("system_id", ""))
                matched = true
        if not matched:
            return _reject("missing_directed_edge")
        total += weight
        if not is_finite(total):
            return _reject("distance_overflow")
        legs.append({"from": previous, "to": location, "distance": weight, "system_id": system_id})
    if expected_distance >= 0.0 and not is_equal_approx(expected_distance, total):
        return _reject("stale_distance")
    return {"accepted": true, "reason": "ok", "origin": origin,
        "destination": destination, "locations": locations.duplicate(),
        "legs": legs, "distance": total, "hop_count": legs.size()}

func admit_planner_result(graph: RefCounted, origin: String, destination: String, result: Dictionary) -> Dictionary:
    if result.get("reachable", false) != true:
        return _reject("unreachable_plan")
    var raw: Variant = result.get("locations", null)
    var distance: Variant = result.get("distance", null)
    if not (raw is Array) or not (distance is int or distance is float):
        return _reject("invalid_plan")
    if float(distance) < 0.0:
        return _reject("invalid_plan")
    return admit(graph, origin, destination, raw, float(distance))

func _reject(reason: String) -> Dictionary:
    return {"accepted": false, "reason": reason}
