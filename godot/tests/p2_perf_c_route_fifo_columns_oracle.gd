extends SceneTree
# Standalone: godot --headless --path godot --script res://tests/p2_perf_c_route_fifo_columns_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var world: Dictionary = {"system": {"id": "one"}, "facilities": [
        {"location": "A"}, {"location": "B"}], "travel_routes": [
        {"from": "A", "to": "B", "distance": 7.0}]}
    assert(graph.load_worlds([world]))
    # Exercise two FIFO compactions, both positive and negative entries.
    for i in range(12290):
        var destination: String = "unknown_%d" % i
        var result: Dictionary = graph.shortest_path("A", destination)
        assert(not result["reachable"])
        assert(result["reason"] == "unknown_location")
    assert(graph.path_cache_stats()["entries"] == graph.MAX_PATH_CACHE)
    assert(graph._path_cache_fifo_starts.size() == graph._path_cache_fifo_destinations.size())
    assert(graph._path_cache_fifo_starts.size() - graph._path_cache_fifo_head == graph.MAX_PATH_CACHE)
    var hits_before: int = int(graph.path_cache_stats()["hits"])
    graph.shortest_path("A", "unknown_12289")
    assert(int(graph.path_cache_stats()["hits"]) == hits_before + 1)
    # The oldest query must have been evicted, not the newest one.
    var misses_before: int = int(graph.path_cache_stats()["misses"])
    graph.shortest_path("A", "unknown_0")
    assert(int(graph.path_cache_stats()["misses"]) == misses_before + 1)
    var good: Dictionary = graph.shortest_path("A", "B")
    assert(good == graph._shortest_path_uncached("A", "B"))
    good["locations"].append("tampered")
    assert(graph.shortest_path("A", "B")["locations"] == ["A", "B"])
    # Failed loads must not mutate the graph or reset cache.
    var before: Dictionary = graph.path_cache_stats()
    assert(not graph.load_worlds([{"system": {"id": ""}}]))
    assert(graph.path_cache_stats() == before)
    assert(graph.shortest_path("A", "B")["distance"] == 7.0)
    assert(graph.load_worlds([world]))
    assert(graph.path_cache_stats()["entries"] == 0)
    assert(graph._path_cache_fifo_starts.is_empty())
    assert(graph._path_cache_fifo_destinations.is_empty())
    print("P2_PERF_C_ROUTE_FIFO_COLUMNS_ORACLE_PASS")
    quit()
