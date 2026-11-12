extends SceneTree
## Run: godot --headless --path godot --script res://tests/n60_route_itinerary_check.gd
const Graph = preload("res://scripts/sim/route_graph.gd")
const Gate = preload("res://scripts/sim/route_itinerary_admission.gd")
var failures: Array[String] = []

func _initialize() -> void:
    var graph = Graph.new()
    var worlds := [{"system": {"id": "s1"}, "facilities": [], "nav_sites": [],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 2.0},
            {"from": "B", "to": "C", "distance": 3.0},
            {"from": "C", "to": "A", "distance": 8.0},
            {"from": "A", "to": "C", "distance": 9.0}
        ]}]
    _check(graph.load_worlds(worlds), "graph_load")
    var gate = Gate.new()
    var before: Dictionary = graph.snapshot()
    var good: Dictionary = gate.admit(graph, "A", "C", ["A", "B", "C"], 5.0)
    _check(good.get("accepted", false), "valid_multihop")
    _check(good.get("hop_count", 0) == 2, "two_legs")
    _check(is_equal_approx(float(good.get("distance", -1.0)), 5.0), "native_weight")
    _check(not gate.admit(graph, "C", "B", ["C", "B"]).get("accepted", false), "directionality")
    _check(not gate.admit(graph, "A", "C", ["A", "B", "A", "C"]).get("accepted", false), "loop")
    _check(not gate.admit(graph, "A", "C", ["A", "B", "C"], 5.5).get("accepted", false), "stale_weight")
    _check(not gate.admit(graph, "A", "C", ["B", "C"]).get("accepted", false), "stale_start")
    _check(not gate.admit(graph, "A", "C", ["A", "X", "C"]).get("accepted", false), "unknown_location")
    _check(not gate.admit(graph, "A", "A", ["A"]).get("accepted", false), "no_travel")
    _check(not gate.admit_planner_result(graph, "A", "C", {"reachable": true, "locations": ["A", "B", "C"], "distance": 7.0}).get("accepted", false), "planner_tamper")
    _check(gate.admit_planner_result(graph, "A", "C", graph.shortest_path("A", "C")).get("accepted", false), "planner_roundtrip")
    _check(graph.snapshot() == before, "read_only")
    if failures.is_empty():
        print("N60 PASS: directed itinerary admission")
        quit(0)
    else:
        push_error("N60 FAIL: " + ", ".join(failures))
        quit(1)

func _check(ok: bool, name: String) -> void:
    if not ok:
        failures.append(name)
