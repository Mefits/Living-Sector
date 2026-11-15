extends RefCounted
## N56: read-only route admission. This never moves a ship, consumes fuel,
## teleports, or settles gate fees. Only a single directed leg is admitted.
## Rust route_actions can fall back to straight Travel on no path; this Godot
## boundary deliberately rejects such fallback until the actual action
## executor's geometry and gate semantics have been ported.
func check_leg(graph: RefCounted, origin: String, destination: String, positions: Dictionary) -> Dictionary:
    if origin.is_empty() or destination.is_empty():
        return {"ok": false, "reason": "missing_location"}
    if origin == destination:
        return {"ok": false, "reason": "same_location"}
    if not graph.has_location(origin) or not graph.has_location(destination):
        return {"ok": false, "reason": "unknown_location"}
    var matches: int = 0
    for edge_value in graph.outgoing(origin):
        if not (edge_value is Dictionary):
            return {"ok": false, "reason": "invalid_edge"}
        var edge: Dictionary = edge_value
        if str(edge.get("to", "")) == destination:
            matches += 1
    if matches != 1:
        return {"ok": false, "reason": "ambiguous_edge" if matches > 1 else "no_directed_edge"}
    if not positions.has(origin) or not positions.has(destination):
        return {"ok": false, "reason": "missing_position"}
    if not _valid_position(positions[origin]) or not _valid_position(positions[destination]):
        return {"ok": false, "reason": "invalid_position"}
    var distance: float = (positions[origin] as Vector2).distance_to(positions[destination] as Vector2)
    if not is_finite(distance) or distance <= 0.0:
        return {"ok": false, "reason": "zero_distance"}
    return {"ok": true, "from": origin, "to": destination, "world_distance": distance}

func check_path(graph: RefCounted, locations: Array, positions: Dictionary) -> Dictionary:
    if locations.size() < 2:
        return {"ok": false, "reason": "short_path"}
    var total: float = 0.0
    for i in range(locations.size() - 1):
        if not (locations[i] is String) or not (locations[i + 1] is String):
            return {"ok": false, "reason": "invalid_location_type"}
        var result: Dictionary = check_leg(graph, locations[i], locations[i + 1], positions)
        if not result["ok"]:
            return {"ok": false, "reason": result["reason"], "leg_index": i}
        total += float(result["world_distance"])
        if not is_finite(total):
            return {"ok": false, "reason": "invalid_total_distance"}
    return {"ok": true, "locations": locations.duplicate(), "world_distance": total}

func _valid_position(value: Variant) -> bool:
    return value is Vector2 and is_finite(value.x) and is_finite(value.y)
