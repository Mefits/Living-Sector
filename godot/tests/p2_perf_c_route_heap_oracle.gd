extends RefCounted
## Independent O(V^2) reference for the original N4 directed route selection.
const Graph = preload("res://scripts/sim/route_graph.gd")

static func _oracle(graph: RefCounted, start: String, destination: String) -> Dictionary:
    if not graph.has_location(start) or not graph.has_location(destination):
        return {"reachable": false, "reason": "unknown_location"}
    if start == destination:
        return {"reachable": true, "locations": [start], "distance": 0.0}
    var best: Dictionary = {start: 0.0}
    var paths: Dictionary = {start: start}
    var prev: Dictionary = {}
    var visited: Dictionary = {}
    while true:
        var current: String = ""
        var smallest: float = INF
        var path_key: String = ""
        for node in best:
            if visited.has(node):
                continue
            var candidate: float = float(best[node])
            var key: String = str(paths[node])
            if current.is_empty() or candidate < smallest or (is_equal_approx(candidate, smallest) and key < path_key):
                current = str(node)
                smallest = candidate
                path_key = key
        if current.is_empty():
            break
        if current == destination:
            var locations: Array[String] = [destination]
            var cursor: String = destination
            while cursor != start:
                cursor = str(prev[cursor])
                locations.push_front(cursor)
            return {"reachable": true, "locations": locations, "distance": smallest}
        visited[current] = true
        for edge in graph.outgoing(current):
            var target: String = str(edge["to"])
            if visited.has(target):
                continue
            var candidate: float = smallest + float(edge["distance"])
            var key: String = path_key + "/" + target
            if not best.has(target) or candidate < float(best[target]) or (is_equal_approx(candidate, float(best[target])) and key < str(paths[target])):
                best[target] = candidate
                paths[target] = key
                prev[target] = current
    return {"reachable": false, "reason": "no_directed_path"}

static func _world(edges: Array) -> Dictionary:
    return {"system": {"id": "oracle-system"}, "facilities": [],
        "nav_sites": [], "travel_routes": edges}

static func _edge(a: String, b: String, distance: float) -> Dictionary:
    return {"from": a, "to": b, "distance": distance}

static func _compare(graph: RefCounted, nodes: Array) -> bool:
    for source in nodes:
        for destination in nodes:
            var expected: Dictionary = _oracle(graph, str(source), str(destination))
            var first: Dictionary = graph.shortest_path(str(source), str(destination))
            if first != expected:
                push_error("C N4 oracle mismatch %s -> %s: %s / %s" % [source, destination, first, expected])
                return false
            if first.get("locations") is Array:
                first["locations"].append("MUTATED_BY_CALLER")
            first["reachable"] = false
            if graph.shortest_path(str(source), str(destination)) != expected:
                push_error("C N4 cache mutable alias %s -> %s" % [source, destination])
                return false
    return true

static func run() -> bool:
    var graph: RefCounted = Graph.new()
    var edges: Array = [
        _edge("A", "B", 1.0), _edge("A", "C", 1.0),
        _edge("B", "D", 2.0), _edge("C", "D", 2.0),
        _edge("D", "E", 1.0), _edge("C", "E", 5.0),
        _edge("E", "F", 1.0), _edge("B", "F", 9.0),
        _edge("G", "H", 2.0)]
    if not graph.load_worlds([_world(edges)]):
        return false
    if not _compare(graph, ["A", "B", "C", "D", "E", "F", "G", "H", "UNKNOWN"]):
        return false
    # Reload must invalidate positive and negative cached paths.
    if not graph.load_worlds([_world([_edge("A", "F", 0.5), _edge("F", "B", 1.0)])]):
        return false
    if not _compare(graph, ["A", "B", "F", "C", "UNKNOWN"]):
        return false
    var before: Dictionary = graph.shortest_path("A", "B")
    if graph.load_worlds([_world([_edge("A", "A", 1.0)])]):
        return false
    if graph.shortest_path("A", "B") != before:
        return false
    # Dense directed graph stresses multiple stale tentative heap entries.
    var dense: Array = []
    var names: Array = []
    for i in range(35):
        names.append("N%02d" % i)
    for i in range(names.size()):
        for j in range(names.size()):
            if i != j:
                dense.append(_edge(names[i], names[j], float(1 + ((i * 17 + j * 7) % 19))))
    if not graph.load_worlds([_world(dense)]):
        return false
    return _compare(graph, names)
