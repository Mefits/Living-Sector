extends SceneTree
## N4 cache-hit isolation regression. Run with Godot --headless --script.
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var worlds: Array = [{
        "system": {"id": "sys"},
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 2.0},
            {"from": "B", "to": "C", "distance": 3.0}
        ]
    }]
    assert(graph.load_worlds(worlds))
    var original: Dictionary = graph.shortest_path("A", "C")
    assert(original.get("reachable", false))
    assert(original["locations"] == ["A", "B", "C"])
    var cached: Dictionary = graph.shortest_path("A", "C")
    assert(cached == original)
    # Mutating a hit must not change the cache or a previous caller.
    cached["locations"][0] = "MUTATED"
    cached["distance"] = -99.0
    cached["extra"] = {"mutable": true}
    assert(original["locations"] == ["A", "B", "C"])
    var again: Dictionary = graph.shortest_path("A", "C")
    assert(again == original)
    # A miss's returned route must also be independent of the cached copy.
    var reverse: Dictionary = graph.shortest_path("C", "A")
    assert(not reverse.get("reachable", true))
    reverse["reason"] = "mutated"
    assert(graph.shortest_path("C", "A").get("reason") == "no_directed_path")
    var unknown: Dictionary = graph.shortest_path("missing", "A")
    unknown["reason"] = "mutated"
    assert(graph.shortest_path("missing", "A").get("reason") == "unknown_location")
    # Successful topology replacement invalidates the old route and cache.
    worlds[0]["travel_routes"][1]["distance"] = 7.0
    assert(graph.load_worlds(worlds))
    var changed: Dictionary = graph.shortest_path("A", "C")
    assert(is_equal_approx(float(changed["distance"]), 9.0))
    assert(changed["locations"] == ["A", "B", "C"])
    print("P2_PERF_C_ROUTE_FLAT_DETACH_ORACLE_PASS")
    quit(0)
