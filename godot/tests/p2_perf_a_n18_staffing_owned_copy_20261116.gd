extends SceneTree
## N18 stage ownership regression: a shallow World root must detach the
## facilities subtree before any assignment. Other domains remain read-only.
func _initialize() -> void:
    var source: Dictionary = {
        "facilities": {"f1": {"assigned_workers": 2, "stock": {"ore": 7}}},
        "ships": {"s1": {"cargo": {"ore": 4}}},
        "station_administration": [{"old": true}]}
    var baseline: Dictionary = source.duplicate(true)
    var staged: Dictionary = source.duplicate()
    staged["facilities"] = source["facilities"].duplicate(true)
    staged["facilities"]["f1"]["assigned_workers"] = 5
    staged["facilities"]["f1"]["stock"]["ore"] = 3
    staged["station_administration"] = [{"new": true}]
    assert(source == baseline, "N18 staffing mutated authoritative source")
    assert(staged["facilities"]["f1"]["assigned_workers"] == 5)
    assert(staged["facilities"]["f1"]["stock"]["ore"] == 3)
    assert(not is_same(staged["facilities"], source["facilities"]),
        "N18 facilities must be owned")
    assert(not is_same(staged["facilities"]["f1"], source["facilities"]["f1"]),
        "N18 nested facility must be owned")
    assert(is_same(staged["ships"], source["ships"]),
        "N18 read-only domains should not be cloned")
    # Negative regression: a shallow-only stage MUST leak writes.
    var unsafe: Dictionary = source.duplicate()
    unsafe["facilities"]["f1"]["assigned_workers"] = 99
    assert(source["facilities"]["f1"]["assigned_workers"] == 99,
        "negative shallow alias fixture did not detect unsafe write")
    quit(0)
