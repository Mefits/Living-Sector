extends SceneTree
# godot --headless --path godot --script res://tests/p2_perf_c_raw_route_index_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var routes: Array = []
    # Dense directed topology exercises raw duplicate membership at scale.
    for i in range(40):
        for j in range(40):
            if i != j:
                routes.append({"from": "L%d" % i, "to": "L%d" % j,
                    "distance": float(1 + ((i * 37 + j * 11) % 17))})
    var world: Dictionary = {"system": {"id": "raw"}, "travel_routes": routes}
    assert(graph.load_worlds([world], false))
    assert(graph.edge_count() == 1560)
    assert(graph.outgoing("L0").size() == 39)
    var baseline: Dictionary = graph.snapshot()
    var path: Dictionary = graph.shortest_path("L0", "L39")
    assert(path == graph._shortest_path_uncached("L0", "L39"))
    var cached: Dictionary = graph.path_cache_stats()
    # Duplicate across separate worlds is still illegal in raw directed mode.
    var duplicate: Dictionary = {"system": {"id": "other"},
        "travel_routes": [{"from": "L0", "to": "L39", "distance": 999.0}]}
    assert(not graph.load_worlds([world, duplicate], false))
    assert(graph.snapshot() == baseline)
    assert(graph.path_cache_stats() == cached)
    assert(graph.shortest_path("L0", "L39") == path)
    # Opposite direction is distinct, and neither may silently upsert.
    var small: Dictionary = {"system": {"id": "small"}, "travel_routes": [
        {"from": "A", "to": "B", "distance": 2.0},
        {"from": "B", "to": "A", "distance": 7.0}]}
    assert(graph.load_worlds([small], false))
    assert(graph.edge_count() == 2)
    assert(graph.shortest_path("A", "B")["distance"] == 2.0)
    assert(graph.shortest_path("B", "A")["distance"] == 7.0)
    assert(graph.path_cache_stats()["entries"] == 2)
    assert(not graph.load_worlds([{"system": {"id": "invalid"},
        "travel_routes": [{"from": "A", "to": "B", "distance": 1.0},
            {"from": "A", "to": "B", "distance": 3.0}]}], false))
    assert(graph.edge_count() == 2)
    print("P2_PERF_C_RAW_ROUTE_INDEX_ORACLE_PASS")
    quit()
