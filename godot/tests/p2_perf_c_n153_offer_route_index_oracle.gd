extends SceneTree
# Standalone: godot --headless --path godot --script res://tests/p2_perf_c_n153_offer_route_index_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")
const Index = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var world: Dictionary = {"system": {"id": "s"}, "facilities": [
        {"location": "A"}, {"location": "B"}, {"location": "C"}, {"location": "D"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 1.0},
            {"from": "B", "to": "C", "distance": 1.0},
            {"from": "B", "to": "D", "distance": 1.0}]}
    assert(graph.load_worlds([world]))
    var positions: Dictionary = {"A": Vector2(0, 0), "B": Vector2(10, 0),
        "C": Vector2(20, 0), "D": Vector2(10, 20)}
    var roots: Dictionary = {}
    var first: Dictionary = Index.offer_route_index(roots, "B", "C")
    var a: Dictionary = Index.legs(first, "A", "B", "C", graph, positions)
    assert(a["inbound"] == ["A", "B"])
    assert(a["outbound"] == ["B", "C"])
    assert(a["steps"].size() == 2)
    assert(is_equal_approx(float(a["steps"][0]["distance"]), 10.0))
    # A second paid offer with the same endpoints must not recalculate
    # geometry for the same ship location during this proposal.
    var again: Dictionary = Index.offer_route_index(roots, "B", "C")
    assert(again.size() == 3)
    assert(again.has(0))
    assert(Index.legs(again, "A", "B", "C", graph, positions) == a)
    assert(roots["B"]["C"].size() == 3)
    # A second ship location reuses outbound geometry, not inbound geometry.
    var at_source: Dictionary = Index.legs(again, "B", "B", "C", graph, positions)
    assert(at_source["outbound"] == a["outbound"])
    assert(at_source["steps"].size() == 1)
    assert(again.size() == 4)
    assert(is_equal_approx(float(at_source["steps"][0]["distance"]), 10.0))
    # Changing the returned per-ship steps must not mutate the outbound
    # scalar cache, or the next independent ship's fuel estimate.
    at_source["steps"][0]["distance"] = -1.0
    assert(is_equal_approx(float(again[1][0]["distance"]), 10.0))
    # Distinct destination and source must never inherit stale legs.
    var other: Dictionary = Index.offer_route_index(roots, "B", "D")
    var d: Dictionary = Index.legs(other, "A", "B", "D", graph, positions)
    assert(d["outbound"] == ["B", "D"])
    assert(is_equal_approx(float(d["steps"][1]["distance"]), 20.0))
    assert(other.size() == 3)
    assert(Index.offer_route_index(roots, "C", "B").is_empty())
    # World positions may change between ticks/restart: fresh proposal
    # roots must produce new geometry, never reuse old mutable World data.
    positions["B"] = Vector2(15, 0)
    var fresh: Dictionary = {}
    var updated: Dictionary = Index.legs(
        Index.offer_route_index(fresh, "B", "C"), "A", "B", "C", graph, positions)
    assert(is_equal_approx(float(updated["steps"][0]["distance"]), 15.0))
    assert(is_equal_approx(float(a["steps"][0]["distance"]), 10.0))
    # The cache never manufactures a directed reverse route.
    var reverse: Dictionary = Index.legs(
        Index.offer_route_index(fresh, "C", "B"), "A", "C", "B", graph, positions)
    assert(reverse.get("error", "") == "unreachable_directed_route")
    print("P2_PERF_C_N153_OFFER_ROUTE_INDEX_ORACLE_PASS")
    quit()
