extends SceneTree
# godot --headless --path godot --script res://tests/p2_perf_c_route_relaxation_oracle.gd
# Independent pre-optimization Dijkstra oracle, including approximate ties.
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var routes: Array = []
    for i in range(24):
        for j in range(24):
            if i == j:
                continue
            routes.append({"from": "N%02d" % i, "to": "N%02d" % j,
                "distance": float(1 + ((i * 19 + j * 7) % 11))})
    # Explicit equal-cost alternatives exercise lexicographic path choice.
    var world: Dictionary = {"system": {"id": "oracle"}, "travel_routes": routes}
    assert(graph.load_worlds([world]))
    for i in range(24):
        for j in range(24):
            var start: String = "N%02d" % i
            var destination: String = "N%02d" % j
            var expected: Dictionary = _original_dijkstra(graph, start, destination)
            assert(graph.shortest_path(start, destination) == expected)
            assert(graph.shortest_path(start, destination) == expected)
    for pair in [["N00", "missing"], ["missing", "N00"]]:
        assert(graph.shortest_path(pair[0], pair[1]) == _original_dijkstra(graph, pair[0], pair[1]))
    # A small graph with near-equal floating-point alternatives.
    var near = RouteGraph.new()
    assert(near.load_worlds([{"system": {"id": "near"}, "travel_routes": [
        {"from": "A", "to": "B", "distance": 1.0},
        {"from": "A", "to": "C", "distance": 1.00000001},
        {"from": "B", "to": "D", "distance": 1.0},
        {"from": "C", "to": "D", "distance": 1.0}]}]))
    for pair in [["A", "D"], ["D", "A"], ["A", "C"]]:
        assert(near.shortest_path(pair[0], pair[1]) == _original_dijkstra(near, pair[0], pair[1]))
    print("P2_PERF_C_ROUTE_RELAXATION_ORACLE_PASS")
    quit()

# Copied control algorithm from the unoptimized route_graph.gd, using only
# detached outgoing() data; deliberately no early dominated-edge filter.
func _original_dijkstra(graph, start: String, destination: String) -> Dictionary:
    if not graph.has_location(start) or not graph.has_location(destination):
        return {"reachable": false, "reason": "unknown_location"}
    if start == destination:
        return {"reachable": true, "locations": [start], "distance": 0.0}
    var best: Dictionary = {start: 0.0}
    var paths: Dictionary = {start: start}
    var previous: Dictionary = {}
    var visited: Dictionary = {}
    while true:
        var current: String = ""
        var smallest: float = INF
        var path_key: String = ""
        for node in best:
            if visited.has(node):
                continue
            var candidate: float = float(best[node])
            var candidate_path: String = str(paths[node])
            if current.is_empty() or candidate < smallest or (is_equal_approx(candidate, smallest) and candidate_path < path_key):
                current = str(node)
                smallest = candidate
                path_key = candidate_path
        if current.is_empty():
            break
        if current == destination:
            var route: Array[String] = [destination]
            var cursor: String = destination
            while cursor != start:
                cursor = str(previous[cursor])
                route.push_front(cursor)
            return {"reachable": true, "locations": route, "distance": smallest}
        visited[current] = true
        for edge in graph.outgoing(current):
            var target: String = str(edge["to"])
            if visited.has(target):
                continue
            var candidate: float = smallest + float(edge["distance"])
            var candidate_path: String = path_key + "/" + target
            if not best.has(target) or candidate < float(best[target]) or (is_equal_approx(candidate, float(best[target])) and candidate_path < str(paths[target])):
                best[target] = candidate
                paths[target] = candidate_path
                previous[target] = current
    return {"reachable": false, "reason": "no_directed_path"}
