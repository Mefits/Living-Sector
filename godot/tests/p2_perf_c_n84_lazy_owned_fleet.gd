extends SceneTree
## II-C N84: owned-row optimization versus original whole-fleet deep copy.
## Both normal and negative paths must preserve World and result ownership.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

func _fixture(n: int) -> Dictionary:
    var ships: Dictionary = {}
    for i in range(n):
        var id: String = "ship_%03d" % i
        ships[id] = {"id": id, "active_contract_id": "",
            "current_goal": "idle", "location": "A", "docked_at": "",
            "transit": {}, "cargo": {"ore": i},
            "memory": {"visited": ["A"]},
            "current_bt": {"type": "Sequence", "children": [{"type": "Action", "kind": "Dock"}]},
            "transaction": {"items": [i]}}
    return ships

func _initialize() -> void:
    for size in [0, 1, 24, 100, 500]:
        var original: Dictionary = _fixture(size)
        var oracle: Dictionary = original.duplicate(true)
        var staged: Dictionary = N84._owned_fleet_begin(original)
        var owned: Dictionary = {}
        assert(staged == oracle)
        # Two active rows may mutate deeply; the other rows stay read-only.
        for index in [0, 1]:
            if index >= size:
                continue
            var id: String = "ship_%03d" % index
            var row: Dictionary = N84._owned_fleet_row(staged, id, owned)
            row["cargo"]["ore"] = 10000 + index
            row["memory"]["visited"].append("B")
            row["current_bt"]["children"][0]["kind"] = "Travel"
            row["transaction"]["items"].append(77)
            oracle[id]["cargo"]["ore"] = 10000 + index
            oracle[id]["memory"]["visited"].append("B")
            oracle[id]["current_bt"]["children"][0]["kind"] = "Travel"
            oracle[id]["transaction"]["items"].append(77)
            # Repeated ownership acquisition must not erase earlier writes.
            assert(N84._owned_fleet_row(staged, id, owned) == row)
        var sealed: Dictionary = N84._owned_fleet_seal(staged, owned)
        assert(sealed == oracle)
        assert(original == _fixture(size))
        for id in sealed:
            sealed[id]["cargo"]["ore"] = -999
            sealed[id]["memory"]["visited"].append("external")
            sealed[id]["current_bt"]["children"][0]["kind"] = "external"
            sealed[id]["transaction"]["items"].append(-1)
        assert(original == _fixture(size))
        assert(oracle != sealed if size > 0 else oracle == sealed)
    # No eligible ship: real propose still returns an owned fleet and no
    # BT/command mutation, matching the old eager-deep-copy result.
    var graph = Graph.new()
    assert(graph.load_worlds([{"system": {"id": "s"}, "travel_routes": [
        {"from": "A", "to": "B", "distance": 1.0}]}]))
    var world: Dictionary = {"ships": _fixture(24), "ship_next_token": 1,
        "contract_board": {"contracts": {}}}
    var before: Dictionary = world.duplicate(true)
    var no_op: Dictionary = N84.propose(world, graph, {"A": Vector2.ZERO}, 8, 1.0)
    assert(no_op.get("ok", false))
    assert(not no_op.get("changed", true))
    assert(no_op["ships"] == before["ships"])
    assert(world == before)
    no_op["ships"]["ship_000"]["cargo"]["ore"] = 999
    assert(world == before)
    # A BT-active row with an invalid plan must fail without leaking any
    # mutation to the authoritative World, even after lazy ownership.
    world["ships"]["ship_000"]["current_goal"] = "construct"
    world["ships"]["ship_000"]["current_bt"] = {"broken": true}
    before = world.duplicate(true)
    var invalid: Dictionary = N84.propose(world, graph, {"A": Vector2.ZERO}, 8, 1.0)
    assert(not invalid.get("ok", true))
    assert(invalid.get("reason") == "n84_invalid_active_source_plan")
    assert(world == before)
    print("P2_PERF_C_N84_LAZY_OWNED_FLEET_PASS")
    quit(0)
