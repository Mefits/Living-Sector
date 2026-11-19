extends SceneTree
# godot --headless --path godot --script res://tests/p2_perf_c_native_seed_pair_order_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func _initialize() -> void:
    var graph = RouteGraph.new()
    var world: Dictionary = {
        "system": {"id": "seed"},
        "bodies": [
            {"id": "body-a", "type": "planet", "orbit_radius": 1.0},
            {"id": "body-b", "type": "planet", "orbit_radius": 2.0}],
        "nav_sites": [
            {"name": "A", "body": "body-a"},
            {"name": "B", "body": "body-b"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 7.0},
            {"from": "B", "to": "A", "distance": 11.0},
            {"from": "A", "to": "B", "distance": 13.0}]}
    # Rust native seeder upserts both directions for each input row.
    # The final row must win for both directions, without extra edges.
    assert(graph.load_worlds([world], true))
    var forward: Dictionary = graph.shortest_path("A", "B")
    var backward: Dictionary = graph.shortest_path("B", "A")
    assert(forward["reachable"] and backward["reachable"])
    assert(forward["locations"] == ["A", "B"])
    assert(backward["locations"] == ["B", "A"])
    assert(float(forward["distance"]) == 13.0)
    assert(float(backward["distance"]) == 13.0)
    var edges: Array = graph.snapshot()["edges"]
    var seen_forward: int = 0
    var seen_backward: int = 0
    for edge in edges:
        if edge["from"] == "A" and edge["to"] == "B":
            seen_forward += 1
            assert(float(edge["distance"]) == 13.0)
        if edge["from"] == "B" and edge["to"] == "A":
            seen_backward += 1
            assert(float(edge["distance"]) == 13.0)
    assert(seen_forward == 1 and seen_backward == 1)
    # Raw source mode must reject duplicate directed rows and leave
    # the previous native graph and its cached paths unchanged.
    assert(not graph.load_worlds([world], false))
    assert(graph.shortest_path("A", "B") == forward)
    assert(graph.shortest_path("B", "A") == backward)
    print("P2_PERF_C_NATIVE_SEED_PAIR_ORDER_ORACLE_PASS")
    quit()
