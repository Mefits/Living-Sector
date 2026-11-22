extends SceneTree
## N84 contract row ownership: rejected saved BT and failed N104 resume
## must not mutate authoritative World. A successful read-only idle fleet
## must still return a detached result (legacy deep-copy oracle).
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

func _ship(bt: Variant) -> Dictionary:
    return {"id": "ship_c", "active_contract_id": "contract_c",
        "current_goal": "delivery", "current_bt": bt,
        "location": "A", "docked_at": "", "transit": {},
        "cargo": {"ore": 4}, "memory": {"visited": ["A"]},
        "transaction": {"state": "idle", "items": [4]},
        "cargo_capacity": 10, "fuel": 0.0}

func _world(bt: Variant) -> Dictionary:
    return {"ships": {"ship_c": _ship(bt)},
        "ship_next_token": 1,
        "contract_board": {"contracts": {"contract_c": {
            "id": "contract_c", "status": "accepted",
            "fulfiller_id": "ship_c", "contract_type": "delivery",
            "commodity": "ore", "quantity": 5,
            "source_location": "MISSING_SOURCE",
            "destination_location": "MISSING_DEST"}}}}

func _initialize() -> void:
    var graph = Graph.new()
    assert(graph.load_worlds([{"system": {"id": "s"},
        "travel_routes": [{"from": "A", "to": "B", "distance": 1.0}]}]))
    var positions: Dictionary = {"A": Vector2.ZERO, "B": Vector2(1, 0)}
    # Invalid contract BT is rejected before any row is acquired; the
    # exact reason/actor and all nested state match the legacy oracle.
    var world: Dictionary = _world({"broken": true})
    var oracle: Dictionary = world.duplicate(true)
    var rejected: Dictionary = N84.propose(world, graph, positions, 8, 1.0)
    assert(not rejected.get("ok", true))
    assert(rejected.get("reason") == "n84_invalid_saved_plan")
    assert(rejected.get("ship_id") == "ship_c")
    assert(world == oracle)
    # A missing plan invokes the original N104 source resume, but no
    # physical route/source exists. No fabricated transit, cargo or order.
    world = _world(null)
    oracle = world.duplicate(true)
    var resumed: Dictionary = N84.propose(world, graph, positions, 8, 1.0)
    assert(resumed.get("ok", false))
    assert(not resumed.get("changed", true))
    assert(resumed.get("commands", []).is_empty())
    assert(resumed["ships"] == oracle["ships"])
    assert(world == oracle)
    assert(resumed["trace"].size() == 1)
    assert(str(resumed["trace"][0].get("reason", "")).begins_with(
        "n104_wait_source_resume_"))
    # Result ownership is independent even for rejected read-only resume.
    resumed["ships"]["ship_c"]["cargo"]["ore"] = -99
    resumed["ships"]["ship_c"]["memory"]["visited"].append("X")
    resumed["ships"]["ship_c"]["transaction"]["items"].append(999)
    assert(world == oracle)
    # The old full-fleet deep copy and the lazy seal have identical values.
    var legacy: Dictionary = oracle["ships"].duplicate(true)
    var owned: Dictionary = N84._owned_fleet_begin(oracle["ships"])
    assert(N84._owned_fleet_seal(owned, {}) == legacy)
    print("P2_PERF_C_N84_CONTRACT_READONLY_RESUME_PASS")
    quit(0)
