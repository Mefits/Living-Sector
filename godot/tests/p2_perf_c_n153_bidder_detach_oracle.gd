extends SceneTree
# Regression: proposal-scoped N153 route results must not share mutable
# containers between competing ships or paid delivery offers.
const Graph = preload("res://scripts/sim/route_graph.gd")
const Index = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")

func _initialize() -> void:
    var graph = Graph.new()
    var world: Dictionary = {"system": {"id": "s"}, "facilities": [
        {"location": "A"}, {"location": "B"}, {"location": "C"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 1.0},
            {"from": "B", "to": "C", "distance": 1.0}]}
    assert(graph.load_worlds([world]))
    var positions: Dictionary = {"A": Vector2.ZERO,
        "B": Vector2(10, 0), "C": Vector2(20, 0)}
    var roots: Dictionary = {}
    var cache: Dictionary = Index.offer_route_index(roots, "B", "C")
    var original: Dictionary = Index.legs(cache, "A", "B", "C", graph, positions)
    assert(original["steps"].size() == 2)
    var expected: Dictionary = original.duplicate(true)
    # A caller changing route/fuel geometry must not poison the next bid.
    original["steps"][0]["distance"] = -900.0
    original["steps"].append({"present": false, "distance": -1.0})
    original["inbound"].clear()
    original["outbound"].clear()
    var repeated: Dictionary = Index.legs(cache, "A", "B", "C", graph, positions)
    assert(repeated == expected)
    repeated["steps"][1]["present"] = false
    var third: Dictionary = Index.legs(cache, "A", "B", "C", graph, positions)
    assert(third == expected)
    # The cached shared outbound geometry remains untouched for another ship.
    var other: Dictionary = Index.legs(cache, "B", "B", "C", graph, positions)
    assert(other["steps"].size() == 1)
    assert(is_equal_approx(float(other["steps"][0]["distance"]), 10.0))
    # A fresh proposal after a position change must recompute geometry.
    positions["B"] = Vector2(15, 0)
    var fresh: Dictionary = Index.legs(
        Index.offer_route_index({}, "B", "C"), "A", "B", "C", graph, positions)
    assert(is_equal_approx(float(fresh["steps"][0]["distance"]), 15.0))
    # Negative results must also be detached.
    var bad: Dictionary = Index.legs(cache, "UNKNOWN", "B", "C", graph, positions)
    assert(bad.get("error", "") == "native_route_endpoint_unmapped")
    bad["error"] = "changed"
    assert(Index.legs(cache, "UNKNOWN", "B", "C", graph, positions).get("error", "") == "native_route_endpoint_unmapped")
    print("P2_PERF_C_N153_BIDDER_DETACH_ORACLE_PASS")
    quit()
