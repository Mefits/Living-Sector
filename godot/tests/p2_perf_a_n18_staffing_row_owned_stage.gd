extends SceneTree
# N39 N18 staffing stage: changed-row ownership and full-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n18_staffing_row_owned_stage.gd

func _stage(source: Dictionary, assignments: Dictionary) -> Dictionary:
    var previous: Dictionary = source["facilities"]
    if assignments.size() != previous.size():
        return {}
    for id in previous:
        if not assignments.has(id) or typeof(assignments[id]) != TYPE_INT:
            return {}
    var staged: Dictionary = source.duplicate()
    var facilities: Dictionary = previous.duplicate()
    for id in previous:
        var row: Dictionary = previous[id]
        if row.has("assigned_workers") and int(row["assigned_workers"]) == int(assignments[id]):
            continue
        var owned: Dictionary = row.duplicate(true)
        owned["assigned_workers"] = int(assignments[id])
        facilities[id] = owned
    staged["facilities"] = facilities
    return staged

func _oracle(source: Dictionary, assignments: Dictionary) -> Dictionary:
    var full: Dictionary = source.duplicate(true)
    for id in full["facilities"]:
        full["facilities"][id]["assigned_workers"] = int(assignments[id])
    return full

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {
            "changed": {"assigned_workers": 3, "credits": 200,
                "reserves": {"tools": 4.0}, "dock_queue": [{"ship": "s"}]},
            "same": {"assigned_workers": 8, "credits": 300,
                "reserves": {"ore": 7.0}, "dock_queue": []},
            "legacy": {"credits": 400, "reserves": {"food": 1.0}}},
        "markets": {"m": {"supply": {"ore": 9.0}}},
        "ships": {"s": {"cargo": {"ore": 5.0}}},
        "contract_board": {"contracts": {"c": {"receipts": [1, 2]}}}
    }
    var original: Dictionary = world.duplicate(true)
    var assignments: Dictionary = {"changed": 5, "same": 8, "legacy": 0}
    var stage: Dictionary = _stage(world, assignments)
    assert(stage == _oracle(world, assignments),
        "changed-row stage differs from complete World deep-copy oracle")
    assert(world == original, "staging modified authoritative World")
    assert(stage["facilities"]["changed"]["dock_queue"] == world["facilities"]["changed"]["dock_queue"])
    assert(stage["markets"] == world["markets"])
    assert(stage["contract_board"] == world["contract_board"])

    # Negative: an aborted stage must not mutate a nested reserve or dock
    # queue on a changed row. The unchanged row is deliberately read-only.
    stage["facilities"]["changed"]["reserves"]["tools"] = -1.0
    stage["facilities"]["changed"]["dock_queue"].append({"ship": "intruder"})
    assert(world == original, "changed row leaked a mutable alias")
    assert(stage["facilities"]["same"]["assigned_workers"] == 8)

    # Missing, extra and non-integer assignments reject before stage creation.
    assert(_stage(world, {"changed": 5, "same": 8}).is_empty())
    assert(_stage(world, {"changed": 5, "same": 8, "legacy": 0, "extra": 1}).is_empty())
    assert(_stage(world, {"changed": 5, "same": "8", "legacy": 0}).is_empty())
    assert(world == original, "rejected assignments changed source World")

    # Negative oracle: a shallow changed-row update would mutate canonical
    # assigned_workers, demonstrating why per-row detach is necessary.
    var unsafe: Dictionary = world.duplicate()
    unsafe["facilities"] = world["facilities"].duplicate()
    unsafe["facilities"]["changed"]["assigned_workers"] = -42
    assert(world["facilities"]["changed"]["assigned_workers"] == -42)
    quit(0)
