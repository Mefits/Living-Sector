extends SceneTree
# Standalone: godot --headless --path godot --script res://tests/p2_perf_c_route_fifo_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var world = {"system": {"id": "s"}, "facilities": [
        {"location": "A"}, {"location": "B"}, {"location": "C"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 2.0},
            {"from": "B", "to": "C", "distance": 3.0}]}
    assert(graph.load_worlds([world]))
    var first: Dictionary = graph.shortest_path("A", "C")
    assert(first.get("reachable") == true)
    assert(is_equal_approx(float(first["distance"]), 5.0))
    first["locations"].append("CORRUPTION")
    assert(graph.shortest_path("A", "C")["locations"] == ["A", "B", "C"])
    # Force >4096 unique pairs with distinct unknown locations; negative
    # entries are legitimate and must obey the same bounded eviction policy.
    for i in range(4100):
        var missed: Dictionary = graph.shortest_path("unknown_%d" % i, "C")
        assert(not missed["reachable"])
        assert(missed["reason"] == "unknown_location")
    var stats: Dictionary = graph.path_cache_stats()
    assert(stats["entries"] == graph.MAX_PATH_CACHE)
    # FIFO must retain recently queried paths instead of clearing the entire
    # cache. A fresh query to the newest pair must be a cache hit.
    var hits_before: int = int(stats["hits"])
    graph.shortest_path("unknown_4099", "C")
    assert(graph.path_cache_stats()["hits"] == hits_before + 1)
    # Compare cached vs uncached oracle after eviction and topology reload.
    for pair in [["A", "C"], ["C", "A"], ["B", "B"], ["missing", "A"]]:
        assert(graph.shortest_path(pair[0], pair[1]) == graph._shortest_path_uncached(pair[0], pair[1]))
    assert(graph.load_worlds([world]))
    assert(graph.path_cache_stats()["entries"] == 0)
    assert(graph.shortest_path("C", "A")["reason"] == "no_directed_path")
    print("P2_PERF_C_ROUTE_FIFO_ORACLE_PASS")
    quit()
