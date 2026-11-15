extends SceneTree
## Directed source route equivalence: cache may not alter Dijkstra
## tie-break, mutate an earlier returned route, or survive topology reload.
const Graph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph := Graph.new()
    var routes: Array = [
        {"from": "a", "to": "b", "distance": 1.0},
        {"from": "a", "to": "c", "distance": 1.0},
        {"from": "b", "to": "d", "distance": 1.0},
        {"from": "c", "to": "d", "distance": 1.0}]
    if not graph.load_worlds([{"system": {"id": "fixture"},
            "facilities": [{"location": "a"}], "nav_sites": [],
            "travel_routes": routes}]):
        _fail("cannot load original directed N4 fixture")
        return
    var original: Dictionary = graph.shortest_path("a", "d")
    if not original.get("reachable", false) or (
            original.get("locations", []) != ["a", "b", "d"] or
            float(original.get("distance", -1.0)) != 2.0):
        _fail("N4 lexicographic Dijkstra parity lost: " + str(original))
        return
    if graph.shortest_path("d", "a").get("reachable", true):
        _fail("N4 invented source-reverse path")
        return
    var unknown: Dictionary = graph.shortest_path("a", "unknown")
    if unknown != {"reachable": false, "reason": "unknown_location"} or (
            graph.shortest_path("a", "unknown") != unknown):
        _fail("N4 negative shortest-path cached result changed")
        return
    original["locations"].clear()
    original["distance"] = -700.0
    var again: Dictionary = graph.shortest_path("a", "d")
    if again["locations"] != ["a", "b", "d"] or (
            float(again["distance"]) != 2.0):
        _fail("external mutation modified cached N4 route")
        return
    var stats: Dictionary = graph.path_cache_stats()
    if int(stats.get("hits", -1)) != 2 or (
            int(stats.get("misses", -1)) != 3 or
            int(stats.get("entries", -1)) != 3):
        _fail("cache did not record strictly repeated route pairs " + str(stats))
        return
    var before: Dictionary = graph.snapshot()
    var invalid: Array = routes.duplicate(true)
    invalid[0]["distance"] = -1.0
    if graph.load_worlds([{"system": {"id": "invalid"},
            "facilities": [], "nav_sites": [], "travel_routes": invalid}]):
        _fail("malformed graph illegally replaced source routes")
        return
    if graph.snapshot() != before or graph.shortest_path("a", "d") != again:
        _fail("failed source reload invalidated or mutated live topology")
        return
    var replacement: Array = routes.duplicate(true)
    replacement[3]["distance"] = 0.25
    if not graph.load_worlds([{"system": {"id": "updated"},
            "facilities": [], "nav_sites": [], "travel_routes": replacement}]):
        _fail("new valid directed route graph rejected")
        return
    stats = graph.path_cache_stats()
    if stats["entries"] != 0 or stats["hits"] != 0 or stats["misses"] != 0:
        _fail("successful topology reload failed to invalidate route cache")
        return
    var changed: Dictionary = graph.shortest_path("a", "d")
    if changed["locations"] != ["a", "c", "d"] or (
            not is_equal_approx(float(changed["distance"]), 1.25)):
        _fail("stale cached route persisted after graph replacement")
        return
    if graph.shortest_path("d", "a").get("reachable", true):
        _fail("reloaded raw mode stopped being directed")
        return
    print("P2_N153_ROUTE_CACHE_PARITY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N153_ROUTE_CACHE_PARITY_FAIL: " + reason)
    quit(1)
