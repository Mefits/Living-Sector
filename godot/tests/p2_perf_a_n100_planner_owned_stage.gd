extends SceneTree
# N100 planner-only owned publish vs legacy deep World oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n100_planner_owned_stage.gd

func _stage(source: Dictionary) -> Dictionary:
    var staged: Dictionary = source.duplicate(false)
    staged["native_planner_records"] = source["native_planner_records"].duplicate(true)
    return staged

func _initialize() -> void:
    var source: Dictionary = {
        "native_planner_records": {"f1": {"status": "old", "ledger": {"steps": [1]}}},
        "native_planner_last_tick": 60,
        "ships": {"ship1": {"cargo": {"ore": 5}}},
        "markets": {"earth": {"supply": {"water": 20}}},
        "faction_treasuries": {"f1": 900}}
    var original: Dictionary = source.duplicate(true)
    var oracle: Dictionary = source.duplicate(true)
    var staged: Dictionary = _stage(source)
    for candidate in [oracle, staged]:
        candidate["native_planner_records"]["f1"] = {
            "status": "n98_planned_not_dispatched",
            "ledger": {"steps": [{"action": "mine"}]}}
        candidate["native_planner_last_tick"] = 120
    assert(staged == oracle, "N100 owned planner stage diverged from full World oracle")
    assert(source == original, "planner stage mutated authoritative World")
    assert(staged["ships"] == original["ships"], "planner stage changed ships")
    assert(staged["markets"] == original["markets"], "planner stage changed markets")
    staged["native_planner_records"]["f1"]["ledger"]["steps"].append({"action": "haul"})
    assert(source == original, "nested planner record leaked into World")
    var rejected: Dictionary = _stage(source)
    rejected["native_planner_records"]["f1"]["status"] = "invalid"
    assert(source == original, "rejected planner proposal modified World")
    var unsafe: Dictionary = original.duplicate(false)
    unsafe["native_planner_records"] = original["native_planner_records"].duplicate(false)
    unsafe["native_planner_records"]["f1"]["ledger"]["steps"].append(2)
    assert(original["native_planner_records"]["f1"]["ledger"]["steps"].size() == 2,
        "negative shallow-alias fixture failed to demonstrate corruption")
    quit(0)
