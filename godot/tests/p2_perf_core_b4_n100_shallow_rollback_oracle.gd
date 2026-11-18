extends SceneTree
# HYPOTHESIS / TEST_UNVERIFIED: B4 prior root must be equivalent to a deep
# rollback snapshot when N100 changes only its owned planner registry.
# Run: godot --headless --path godot --script res://tests/p2_perf_core_b4_n100_shallow_rollback_oracle.gd

func _initialize() -> void:
    var world: Dictionary = {
        "ships": {"ship-a": {"cargo": {"ore": 5}}},
        "markets": {"earth": {"supply": {"water": 30}}},
        "research_receipts": [{"tick": 1, "payload": {"x": [1, 2, 3]}}],
        "contract_board": {"contracts": {"c1": {"status": "paid"}}},
        "native_planner_records": {"f1": {"ledger": {"steps": [1]}}},
        "native_planner_last_tick": 60}
    var before: Dictionary = world.duplicate(true)
    var prior_deep: Dictionary = world.duplicate(true)
    var prior_owned: Dictionary = world.duplicate(false)
    var staged: Dictionary = world.duplicate(false)
    staged["native_planner_records"] = world["native_planner_records"].duplicate(true)
    staged["native_planner_records"]["f1"]["ledger"]["steps"].append(2)
    staged["native_planner_last_tick"] = 120
    world = staged
    assert(world != before, "negative fixture did not change planner state")
    world = prior_owned
    assert(world == prior_deep, "owned-root rollback differs from deep rollback")
    assert(world == before, "N100-only stage corrupted authoritative World")
    # A rejected nested planner mutation must be isolated from the prior root.
    var rejected: Dictionary = world.duplicate(false)
    rejected["native_planner_records"] = world["native_planner_records"].duplicate(true)
    rejected["native_planner_records"]["f1"]["ledger"]["steps"].append(99)
    assert(world == before, "rejected N100 proposal mutated prior planner records")
    # Negative oracle: shallow copy without detaching owned registry is unsafe.
    var unsafe: Dictionary = before.duplicate(false)
    unsafe["native_planner_records"]["f1"]["ledger"]["steps"].append(7)
    assert(before["native_planner_records"]["f1"]["ledger"]["steps"].size() == 2,
        "negative aliasing fixture failed")
    print("P2_PERF_CORE_B4_N100_SHALLOW_ROLLBACK_ORACLE_PASS")
    quit(0)
