extends RefCounted
## N153 cached read-only geometry vs original detached oracle; no World alias.
const Index = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

static func run() -> Dictionary:
    var graph = Graph.new()
    if not graph.load_worlds([{"system": {"id": "s"},
            "travel_routes": [
                {"from": "a", "to": "b", "distance": 10.0},
                {"from": "b", "to": "c", "distance": 20.0}],
            "nav_sites": [{"name": "a"}, {"name": "b"}, {"name": "c"}]}]):
        return {"ok": false, "reason": "graph_fixture"}
    var positions: Dictionary = {"a": Vector2.ZERO,
        "b": Vector2(10, 0), "c": Vector2(30, 0)}
    var original: Dictionary = positions.duplicate(true)
    var cache: Dictionary = {}
    var legacy: Dictionary = Index.legs(cache, "a", "b", "c", graph, positions)
    var readonly: Dictionary = Index.legs(cache, "a", "b", "c", graph, positions, false)
    if readonly != legacy or readonly.has("error"):
        return {"ok": false, "reason": "oracle_geometry_mismatch"}
    # The public/default oracle must remain detached, even after a
    # read-only caller inspected the cached rows.
    legacy["steps"][0]["distance"] = 999.0
    legacy["inbound"].append("corrupt")
    var fresh: Dictionary = Index.legs(cache, "a", "b", "c", graph, positions)
    if fresh != readonly or positions != original:
        return {"ok": false, "reason": "default_oracle_alias"}
    var outbound: Array = (readonly["outbound"] as Array).duplicate()
    outbound.append("corrupt")
    if readonly["outbound"] == outbound:
        return {"ok": false, "reason": "published_path_alias"}
    # Unreachable reverse direction must still reject, not reuse
    # the successful route from a different origin.
    var reverse: Dictionary = Index.legs(cache, "c", "b", "c", graph, positions, false)
    var reverse_oracle: Dictionary = Index.legs({}, "c", "b", "c", graph, positions)
    if reverse != reverse_oracle:
        return {"ok": false, "reason": "reverse_route_oracle"}
    # New proposal and moved geometry must not reuse stale cached legs.
    var moved: Dictionary = positions.duplicate(true)
    moved["c"] = Vector2(80, 0)
    var new_route: Dictionary = Index.legs({}, "a", "b", "c", graph, moved, false)
    var moved_oracle: Dictionary = Index.legs({}, "a", "b", "c", graph, moved)
    if new_route != moved_oracle or new_route == readonly:
        return {"ok": false, "reason": "stale_geometry"}
    return {"ok": true}
