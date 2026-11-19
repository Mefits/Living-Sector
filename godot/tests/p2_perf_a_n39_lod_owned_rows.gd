extends SceneTree
# Astra II-B: real N39 LOD cursor transition following row-owned N18.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n39_lod_owned_rows.gd

func _legacy(world: Dictionary, tick: int) -> Dictionary:
    var next: Dictionary = world.duplicate(true)
    var ids: Array = next["facilities"].keys()
    ids.sort()
    var fired: Dictionary = {}
    for id in ids:
        var f: Dictionary = next["facilities"][id]
        if not f.has("lod_divisor") or int(f["lod_divisor"]) <= 1:
            fired[id] = true
        elif tick >= int(f.get("lod_next_tick", 0)):
            fired[id] = true
            f["lod_next_tick"] = tick + int(f["lod_divisor"])
    return {"world": next, "fired": fired}

func _owned(world: Dictionary, tick: int) -> Dictionary:
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var fired: Dictionary = {}
    var cursor: Dictionary = {}
    for id in ids:
        var f: Dictionary = world["facilities"][id]
        if not f.has("lod_divisor") or int(f["lod_divisor"]) <= 1:
            fired[id] = true
        elif tick >= int(f.get("lod_next_tick", 0)):
            fired[id] = true
            cursor[id] = tick + int(f["lod_divisor"])
    if cursor.is_empty():
        return {"world": world.duplicate(), "fired": fired}
    var next: Dictionary = world.duplicate()
    next["facilities"] = world["facilities"].duplicate()
    for id in ids:
        if cursor.has(id):
            var row: Dictionary = next["facilities"][id].duplicate(true)
            row["lod_next_tick"] = cursor[id]
            next["facilities"][id] = row
    return {"world": next, "fired": fired}

func _initialize() -> void:
    var original: Dictionary = {
        "facilities": {
            "always": {"assigned_workers": 2, "reserves": {"ore": 4}},
            "due": {"lod_divisor": 5, "lod_next_tick": 10,
                "assigned_workers": 3, "dock_queue": [{"ship": "s"}]},
            "sleep": {"lod_divisor": 7, "lod_next_tick": 14,
                "reserves": {"fuel": 8}},
            "one": {"lod_divisor": 1, "lod_next_tick": 2}},
        "ships": {"s": {"cargo": {"ore": 10}}}}
    var frozen: Dictionary = original.duplicate(true)
    for tick in [9, 10, 11, 14, 20, 21]:
        var oracle: Dictionary = _legacy(original, tick)
        var owned: Dictionary = _owned(original, tick)
        assert(owned["world"] == oracle["world"], "LOD owned stage differs from deep oracle")
        assert(owned["fired"] == oracle["fired"], "LOD fired set or cadence changed")
        assert(original == frozen, "LOD stage mutated canonical World")
        if tick >= 10:
            owned["world"]["facilities"]["due"]["dock_queue"][0]["ship"] = "changed"
            assert(original == frozen, "due row nested mutable alias escaped")
        # No-op stage rows remain read-only; the caller must never mutate
        # them before another explicit owned-write transition.
    var unsafe: Dictionary = original.duplicate()
    unsafe["facilities"] = original["facilities"].duplicate()
    unsafe["facilities"]["due"]["lod_next_tick"] = 999
    assert(original["facilities"]["due"]["lod_next_tick"] == 999,
        "negative alias fixture did not expose the old in-place write")
    assert(frozen["facilities"]["due"]["lod_next_tick"] == 10)
    quit(0)
