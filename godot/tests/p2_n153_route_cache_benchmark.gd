extends SceneTree
## Same original N4 directed Dijkstra work for the baseline and candidate.
## 140-node directed corridor, with 400 repeated source->destination
## lookups like N153 checks across many ships/contracts. Prints timings;
## a cache miss still uses the unmodified original algorithm.
const Graph = preload("res://scripts/sim/route_graph.gd")
const COUNT: int = 140
const LOOKUPS: int = 400

func _initialize() -> void:
    var routes: Array = []
    for i in range(COUNT - 1):
        routes.append({"from": "s%03d" % i, "to": "s%03d" % (i + 1),
            "distance": 1.0})
    var g := Graph.new()
    if not g.load_worlds([{"system": {"id": "large-directed"},
            "facilities": [], "nav_sites": [], "travel_routes": routes}]):
        _fail("benchmark directed source route graph rejected")
        return
    var first: Dictionary = g.shortest_path("s000", "s139")
    if not first.get("reachable", false) or (
            first["locations"].size() != COUNT or
            float(first["distance"]) != float(COUNT - 1)):
        _fail("benchmark Dijkstra route not source-equivalent")
        return
    var started: int = Time.get_ticks_usec()
    for _i in range(LOOKUPS):
        var route: Dictionary = g.shortest_path("s000", "s139")
        if route["locations"].size() != COUNT or (
                float(route["distance"]) != float(COUNT - 1)):
            _fail("reused route differs from source truth")
            return
    var elapsed: int = Time.get_ticks_usec() - started
    var hit: int = -1
    if g.has_method("path_cache_stats"):
        hit = int(g.call("path_cache_stats").get("hits", -1))
    print("N153_ROUTE_REPEAT_BENCH_PASS total_usec=" + str(elapsed) +
        " lookups=" + str(LOOKUPS) + " hops=" + str(COUNT - 1) +
        " cached_hits=" + str(hit))
    quit(0)

func _fail(reason: String) -> void:
    push_error("N153_ROUTE_REPEAT_BENCH_FAIL: " + reason)
    quit(1)
