extends RefCounted
## Regression for N4 strict heap / legacy approximate-distance selection.
const Graph = preload("res://scripts/sim/route_graph.gd")
const ExistingOracle = preload("res://tests/p2_perf_c_route_heap_oracle.gd")

static func _world(edges: Array) -> Dictionary:
    return {"system": {"id": "near-tie"}, "facilities": [],
        "nav_sites": [], "travel_routes": edges}

static func _edge(a: String, b: String, d: float) -> Dictionary:
    return {"from": a, "to": b, "distance": d}

static func run() -> bool:
    var graph: RefCounted = Graph.new()
    # A smaller distance and lexicographically smaller *longer* distance
    # are approximately equal: a non-transitive heap comparator can reorder.
    var edges: Array = [
        _edge("S", "Z", 1.0),
        _edge("S", "A", 1.0000001),
        _edge("Z", "T", 1.0),
        _edge("A", "T", 0.9999999),
        _edge("S", "T", 4.0),
        _edge("Z", "X", 2.0),
        _edge("A", "X", 1.9999999)]
    if not graph.load_worlds([_world(edges)]):
        return false
    var nodes: Array = ["S", "Z", "A", "T", "X", "MISSING"]
    if not ExistingOracle._compare(graph, nodes):
        return false
    # Cache invalidation after a successful reload, including a negative
    # route that becomes reachable and a positive route that disappears.
    var old: Dictionary = graph.shortest_path("S", "T")
    if not graph.load_worlds([_world([_edge("S", "T", 0.25)])]):
        return false
    if graph.shortest_path("S", "T") == old:
        return false
    if not ExistingOracle._compare(graph, nodes):
        return false
    var new_route: Dictionary = graph.shortest_path("S", "T")
    if graph.load_worlds([_world([_edge("S", "S", 1.0)])]):
        return false
    if graph.shortest_path("S", "T") != new_route:
        return false
    # Many near-equal competing frontiers and stale tentative entries.
    var dense: Array = []
    var names: Array = []
    for i in range(24):
        names.append("N%02d" % i)
    for i in range(names.size()):
        for j in range(names.size()):
            if i != j:
                dense.append(_edge(names[i], names[j],
                    1.0 + float((i * 11 + j * 7) % 3) * 0.0000001))
    if not graph.load_worlds([_world(dense)]):
        return false
    return ExistingOracle._compare(graph, names)
