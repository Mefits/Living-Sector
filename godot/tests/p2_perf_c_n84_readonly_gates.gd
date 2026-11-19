extends SceneTree
## II-C N84: read-only validation must not mutate World or change rejection
## priority when the active row has nested cargo/BT/memory data.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

func _ship() -> Dictionary:
    return {"id": "s", "active_contract_id": "", "current_goal": "construct",
        "location": "A", "docked_at": "", "transit": {},
        "cargo": {"ore": 7}, "memory": {"visited": ["A"]},
        "transaction": {"items": [{"qty": 3}]},
        "current_bt": {"broken": true}}

func _world() -> Dictionary:
    return {"ships": {"s": _ship()}, "ship_next_token": 1,
        "contract_board": {"contracts": {}}, "construction_sites": {}}

func _initialize() -> void:
    var graph = Graph.new()
    assert(graph.load_worlds([{"system": {"id": "s0"},
        "travel_routes": [{"from": "A", "to": "B", "distance": 1.0}]}]))
    var positions: Dictionary = {"A": Vector2.ZERO, "B": Vector2.RIGHT}
    var world: Dictionary = _world()
    var baseline: Dictionary = world.duplicate(true)
    var invalid_plan: Dictionary = N84.propose(world, graph, positions, 10, 1.0)
    assert(not invalid_plan.get("ok", true))
    assert(invalid_plan.get("reason") == "n84_invalid_active_source_plan")
    assert(world == baseline)

    # An invalid N104 obligation must reject before attempting to resume BT.
    world = _world()
    world["ships"]["s"]["active_contract_id"] = "missing"
    world["ships"]["s"]["current_goal"] = "idle"
    world["ships"]["s"]["current_bt"] = null
    baseline = world.duplicate(true)
    var missing: Dictionary = N84.propose(world, graph, positions, 10, 1.0)
    assert(not missing.get("ok", true))
    assert(missing.get("reason") == "n84_missing_actual_n104_obligation")
    assert(world == baseline)

    # The same proof must reject an incorrectly assigned posted obligation.
    world["contract_board"]["contracts"]["missing"] = {
        "status": "accepted", "fulfiller_id": "other"}
    baseline = world.duplicate(true)
    var wrong_owner: Dictionary = N84.propose(world, graph, positions, 10, 1.0)
    assert(not wrong_owner.get("ok", true))
    assert(wrong_owner.get("reason") == "n84_missing_actual_n104_obligation")
    assert(world == baseline)

    # Positive no-op oracle: sleeping rows remain identical and the returned
    # detached fleet cannot mutate the source's nested data.
    world = _world()
    world["ships"]["s"]["current_goal"] = "idle"
    baseline = world.duplicate(true)
    var idle: Dictionary = N84.propose(world, graph, positions, 10, 1.0)
    assert(idle.get("ok", false))
    assert(not idle.get("changed", true))
    assert(idle["ships"] == baseline["ships"])
    idle["ships"]["s"]["cargo"]["ore"] = -100
    idle["ships"]["s"]["memory"]["visited"].append("B")
    assert(world == baseline)
    print("P2_PERF_C_N84_READONLY_GATES_PASS")
    quit(0)
