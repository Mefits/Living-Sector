extends SceneTree
# Native seed upsert / chart INSERT OR IGNORE oracle.
# godot --headless --path godot --script res://tests/p2_perf_c_native_route_upsert_oracle.gd
const RouteGraph = preload("res://scripts/sim/route_graph.gd")
const NativeChart = preload("res://scripts/sim/phase2/unified_n142_original_colony_chart.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "system": {"id": "S"},
        "bodies": [
            {"id": "p1", "type": "planet", "orbit_radius": 1.0},
            {"id": "p2", "type": "planet", "orbit_radius": 2.0}],
        "facilities": [
            {"location": "A", "body": "p1"},
            {"location": "B", "body": "p2"}],
        "travel_routes": [
            {"from": "A", "to": "B", "distance": 5.0},
            {"from": "B", "to": "A", "distance": 7.0},
            {"from": "A", "to": "B", "distance": 3.0},
            {"from": "B", "to": "A", "distance": 9.0}]}
    var graph = RouteGraph.new()
    assert(graph.load_worlds([world], true))
    # Naive Rust seeder reference: every source route upserts both directions,
    # including reversed input records, then N142 inserts missing edges only.
    var expected: Dictionary = {}
    for route in world["travel_routes"]:
        for pair in [[route["from"], route["to"]], [route["to"], route["from"]]]:
            expected[str(pair[0]) + "|" + str(pair[1])] = float(route["distance"])
    var chart: Dictionary = NativeChart.chart([world])
    assert(chart.get("ok", false))
    for edge in chart["edges"]:
        var key: String = str(edge["from"]) + "|" + str(edge["to"])
        if not expected.has(key):
            expected[key] = float(edge["distance"])
    var snapshot: Dictionary = graph.snapshot()
    assert(int(snapshot["edges"].size()) == expected.size())
    for edge in snapshot["edges"]:
        var key: String = str(edge["from"]) + "|" + str(edge["to"])
        assert(expected.has(key))
        assert(is_equal_approx(float(edge["distance"]), float(expected[key])))
    assert(is_equal_approx(float(expected["A|B"]), 9.0))
    assert(is_equal_approx(float(expected["B|A"]), 9.0))
    assert(graph.shortest_path("A", "B") == graph._shortest_path_uncached("A", "B"))
    # A failed replacement must retain old graph and route cache.
    var before: Dictionary = graph.snapshot()
    var old_route: Dictionary = graph.shortest_path("A", "B")
    assert(not graph.load_worlds([{"system": {"id": ""}}], true))
    assert(graph.snapshot() == before)
    assert(graph.shortest_path("A", "B") == old_route)
    print("P2_PERF_C_NATIVE_ROUTE_UPSERT_ORACLE_PASS")
    quit()
