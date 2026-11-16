extends SceneTree
# Regression for bounded N153 geometry copies: outbound rows must be detached,
# while route order, scalar distances and negative sentinels remain unchanged.
const Index = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var source_rows: Array = [
        {"present": true, "distance": 12.5},
        {"present": false, "distance": -1.0}]
    var copy_rows: Array = Index._detach_step_rows(source_rows)
    assert(copy_rows == source_rows)
    assert(copy_rows.size() == 2)
    copy_rows[0]["distance"] = 999.0
    copy_rows[1]["present"] = true
    copy_rows.append({"present": true, "distance": 0.0})
    assert(source_rows.size() == 2)
    assert(is_equal_approx(float(source_rows[0]["distance"]), 12.5))
    assert(not bool(source_rows[1]["present"]))
    var graph = Graph.new()
    var world: Dictionary = {"system": {"id": "s"}, "facilities": [
        {"location": "A"}, {"location": "B"}, {"location": "C"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 1.0},
            {"from": "B", "to": "C", "distance": 1.0}]}
    assert(graph.load_worlds([world]))
    var positions: Dictionary = {"A": Vector2.ZERO,
        "B": Vector2(10, 0), "C": Vector2(25, 0)}
    var cache: Dictionary = Index.offer_route_index({}, "B", "C")
    var first: Dictionary = Index.legs(cache, "A", "B", "C", graph, positions)
    assert(first["steps"].size() == 2)
    assert(is_equal_approx(float(first["steps"][0]["distance"]), 10.0))
    assert(is_equal_approx(float(first["steps"][1]["distance"]), 15.0))
    first["steps"][1]["distance"] = 0.0
    var second: Dictionary = Index.legs(cache, "B", "B", "C", graph, positions)
    assert(second["steps"].size() == 1)
    assert(is_equal_approx(float(second["steps"][0]["distance"]), 15.0))
    second["steps"][0]["present"] = false
    var third: Dictionary = Index.legs(cache, "A", "B", "C", graph, positions)
    assert(is_equal_approx(float(third["steps"][1]["distance"]), 15.0))
    assert(bool(third["steps"][1]["present"]))
    print("P2_PERF_C_N153_FLAT_OUTBOUND_COPY_ORACLE_PASS")
    quit()
