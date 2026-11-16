extends SceneTree
## N4 outgoing() flat-row detach oracle: preserve order and independent ownership.
## Run: godot --headless --path godot --script res://tests/p2_perf_c_outgoing_detach_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var world: Dictionary = {
        "system": {"id": "sys"},
        "travel_routes": [
            {"from": "A", "to": "C", "distance": 3.0},
            {"from": "A", "to": "B", "distance": 2.0},
            {"from": "B", "to": "C", "distance": 1.0}
        ]
    }
    assert(graph.load_worlds([world]))
    var baseline: Array = graph.outgoing("A")
    assert(baseline.size() == 2)
    assert(baseline[0]["to"] == "B")
    assert(baseline[1]["to"] == "C")
    assert(is_equal_approx(float(baseline[0]["distance"]), 2.0))
    var original_path: Dictionary = graph.shortest_path("A", "C")
    var original_snapshot: Dictionary = graph.snapshot()
    # A caller can rewrite both the outer Array and the inner edge rows.
    var edited: Array = graph.outgoing("A")
    edited[0]["to"] = "BAD"
    edited[0]["distance"] = -100.0
    edited[0]["system_id"] = "BAD"
    edited.append({"to": "FAKE", "distance": 0.01})
    edited.remove_at(1)
    assert(graph.outgoing("A") == baseline)
    assert(graph.shortest_path("A", "C") == original_path)
    assert(graph.snapshot() == original_snapshot)
    # A separate returned row remains isolated even after editing baseline.
    baseline[1]["distance"] = 999.0
    assert(is_equal_approx(float(graph.outgoing("A")[1]["distance"]), 3.0))
    var absent: Array = graph.outgoing("UNKNOWN")
    absent.append({"to": "A", "distance": 1.0})
    assert(graph.outgoing("UNKNOWN").is_empty())
    # Successful reload and failed reload retain original ownership contracts.
    var bad: Dictionary = world.duplicate(true)
    bad["travel_routes"].append({"from": "C", "to": "D", "distance": -1.0})
    assert(not graph.load_worlds([bad]))
    assert(graph.snapshot() == original_snapshot)
    assert(graph.load_worlds([world]))
    assert(graph.outgoing("A")[0]["to"] == "B")
    print("P2_PERF_C_OUTGOING_DETACH_ORACLE_PASS")
    quit(0)
