extends SceneTree
const Graph = preload("res://scripts/sim/route_graph.gd")
const Admission = preload("res://scripts/sim/route_admission.gd")

func _initialize() -> void:
    var graph = Graph.new()
    var worlds: Array = [{"system": {"id": "test"}, "facilities": [], "nav_sites": [],
        "travel_routes": [{"from": "A", "to": "B", "distance": 900.0},
                          {"from": "B", "to": "C", "distance": 3.0}]}]
    assert(graph.load_worlds(worlds))
    var positions: Dictionary = {"A": Vector2(1, 1), "B": Vector2(4, 5), "C": Vector2(7, 9)}
    var before: Dictionary = positions.duplicate(true)
    var gate = Admission.new()
    var good: Dictionary = gate.check_path(graph, ["A", "B", "C"], positions)
    assert(good["ok"] and is_equal_approx(good["world_distance"], 10.0))
    assert(not gate.check_leg(graph, "B", "A", positions)["ok"])
    assert(not gate.check_leg(graph, "A", "C", positions)["ok"])
    assert(not gate.check_leg(graph, "A", "A", positions)["ok"])
    assert(not gate.check_leg(graph, "A", "unknown", positions)["ok"])
    assert(not gate.check_leg(graph, "A", "B", {"A": Vector2.ZERO})["ok"])
    assert(not gate.check_leg(graph, "A", "B", {"A": Vector2.ZERO, "B": Vector2.ZERO})["ok"])
    assert(not gate.check_path(graph, ["A", "C", "B"], positions)["ok"])
    assert(positions == before)
    assert(graph.edge_count() == 2)
    print("N56 ROUTE ADMISSION PASS")
    quit(0)
