extends SceneTree
# Standalone: godot --headless --path godot --script res://tests/p2_perf_c_n21_prune_oracle.gd
const N21 = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Paid = preload("res://tests/p2_n21_fifo_paid_source_check.gd")

func _initialize() -> void:
    var world: Dictionary = {"ships": {}, "facilities": {"station": {
        "location": "dock", "dock_queue": []}}}
    var queue: Array = []
    for i in range(240):
        var sid: String = "ship_%03d" % i
        world["ships"][sid] = {"location": "dock", "docked_at": "",
            "transit": {}, "dock_attempt_start_tick": 10,
            "current_bt": BT.sequence([BT.action({"kind": "Dock"})])}
        queue.append(sid)
        if i % 3 == 0:
            queue.append(sid)
    # Negative: invalid head must not reserve a slot or suppress a later valid waiter.
    world["ships"]["ship_000"]["location"] = "elsewhere"
    world["ships"]["ship_006"]["dock_attempt_start_tick"] = null
    queue.insert(0, "missing_ship")
    world["facilities"]["station"]["dock_queue"] = queue
    var expected: Array = []
    for sid in queue:
        if N21._valid_waiter(world, "station", str(sid)) and not expected.has(sid):
            expected.append(sid)
    var untouched: Dictionary = world.duplicate(true)
    assert(N21._prune(world, "station"))
    assert(world["facilities"]["station"]["dock_queue"] == expected)
    assert(untouched["facilities"]["station"]["dock_queue"] == queue)
    assert(not N21._prune(world, "station"))
    # Existing independent paid FIFO oracle: fee, exact wallet, receipt replay,
    # insolvent head, and stale transit rejection must remain unchanged.
    var paid: Dictionary = Paid.run_checks()
    assert(paid.get("ok", false), str(paid))
    print("P2_PERF_C_N21_PRUNE_ORACLE_PASS")
    quit()
