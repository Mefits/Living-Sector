extends SceneTree
## II-C N153: shared inbound/endpoint preflight must equal uncached N4
## for every directed route, missing endpoint and proposal invalidation.
const Index = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = Graph.new()
    var worlds: Array = [{"system": {"id": "s"}, "travel_routes": [
        {"from": "A", "to": "B", "distance": 2.0},
        {"from": "B", "to": "C", "distance": 3.0},
        {"from": "B", "to": "D", "distance": 4.0},
        {"from": "D", "to": "E", "distance": 1.0}
    ]}]
    assert(graph.load_worlds(worlds))
    var positions: Dictionary = {
        "A": Vector2(0, 0), "B": Vector2(3, 4),
        "C": Vector2(6, 4), "D": Vector2(3, 8), "E": Vector2(4, 8)}
    var roots: Dictionary = {}
    var shared: Dictionary = {}
    var queries: Array = [
        ["A", "B", "C"], ["A", "B", "D"], ["A", "B", "E"],
        ["B", "B", "C"], ["C", "B", "D"], ["A", "B", "C"],
        ["missing", "B", "C"], ["A", "missing", "C"],
        ["A", "B", "missing"], ["A", "C", "B"]
    ]
    for query in queries:
        var here: String = query[0]
        var source: String = query[1]
        var dest: String = query[2]
        var uncached: Dictionary = Index.legs({}, here, source, dest,
            graph, positions, true)
        var cache: Dictionary = Index.offer_route_index(roots, source, dest)
        var indexed: Dictionary = Index.legs(cache, here, source, dest,
            graph, positions, true, shared)
        assert(indexed == uncached)
        # A returned route is not allowed to poison the shared index.
        if indexed.has("steps") and not indexed["steps"].is_empty():
            indexed["steps"][0]["distance"] = -1000.0
            indexed["inbound"].clear()
            assert(Index.legs(cache, here, source, dest,
                graph, positions, true, shared) == uncached)
    assert(shared.get("inbound_routes", {}).has("B"))
    assert(shared["inbound_routes"]["B"].has("A"))
    # Cached geometry is only valid within the original proposal.
    positions["B"] = Vector2(30, 40)
    var fresh: Dictionary = Index.legs({}, "A", "B", "D",
        graph, positions, false, {})
    var stale: Dictionary = Index.legs(
        Index.offer_route_index(roots, "B", "D"), "A", "B", "D",
        graph, positions, false, shared)
    assert(fresh != stale)
    var new_shared: Dictionary = {}
    assert(Index.legs({}, "A", "B", "D", graph, positions,
        false, new_shared) == fresh)
    # A graph replacement must also start a new proposal-local index.
    worlds[0]["travel_routes"] = [
        {"from": "A", "to": "D", "distance": 1.0},
        {"from": "D", "to": "B", "distance": 1.0},
        {"from": "B", "to": "C", "distance": 1.0}]
    assert(graph.load_worlds(worlds))
    var reloaded: Dictionary = Index.legs({}, "A", "B", "C",
        graph, positions, false, {})
    assert(reloaded == Index.legs({}, "A", "B", "C",
        graph, positions, false, {}))
    assert(reloaded["inbound"] == ["A", "D", "B"])
    # Missing position and unreachable directed route remain real negatives.
    positions.erase("D")
    var absent: Dictionary = Index.legs({}, "A", "B", "C",
        graph, positions, false, {})
    assert(absent.has("steps"))
    assert(absent["steps"][0]["present"] == false or
        absent["steps"][1]["present"] == false)
    assert(Index.legs({}, "C", "A", "B", graph, positions,
        false, {}).get("error") == "unreachable_directed_route")
    print("P2_PERF_C_N153_ROUTE_GEOMETRY_PREFLIGHT_PASS")
    quit(0)
