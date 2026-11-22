extends SceneTree
# Astra II-B: actual N39 blocked recipe/mining shared stage versus the
# previous deep-copy oracle, including rejected/malformed input and aliases.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _initialize() -> void:
    var bridge = N39.new()
    var original: Dictionary = {
        "facilities": {
            "farm": {"work_blocked_reason": "", "work_shift": {
                "produced_outputs": {"food": 3}, "last_recipe_ticks": [2, 4]},
                "dock_queue": [{"ship_id": "hauler"}]},
            "mine": {"work_blocked_reason": "no_extractable_resource",
                "reserves": {"ore": [1, 2]}}},
        "markets": {"earth": {"supply": {"food": 9}}},
        "populations": {"p": {"wealth": 8}},
        "native_receipts": [{"id": "old"}]}
    var frozen: Dictionary = original.duplicate(true)
    var oracle: Dictionary = original.duplicate(true)
    oracle["facilities"]["farm"]["work_blocked_reason"] = "food_storage_full"
    var staged: Dictionary = bridge.call("_stage_blocked_facility",
        original, "farm", "food_storage_full")
    assert(staged == oracle, "blocked row differs from full deep-copy oracle")
    assert(original == frozen, "blocked stage mutated authoritative source")
    assert(staged["markets"] == original["markets"])
    assert(staged["populations"] == original["populations"])
    # Nested mutations to the changed row cannot leak into the old World.
    staged["facilities"]["farm"]["work_shift"]["produced_outputs"]["food"] = 99
    staged["facilities"]["farm"]["dock_queue"][0]["ship_id"] = "changed"
    assert(original == frozen, "blocked stage leaked a nested facility alias")
    # Repeated blocked reason is a no-op, and must preserve all data.
    var same: Dictionary = bridge.call("_stage_blocked_facility",
        original, "mine", "no_extractable_resource")
    assert(same == original)
    # Negative oracle: old shallow row write corrupts authoritative World.
    var unsafe: Dictionary = original.duplicate()
    unsafe["facilities"] = original["facilities"].duplicate()
    unsafe["facilities"]["farm"]["work_blocked_reason"] = "bad"
    assert(original["facilities"]["farm"]["work_blocked_reason"] == "bad")
    assert(frozen["facilities"]["farm"]["work_blocked_reason"] == "")
    # A missing or malformed facility must never create a new actor.
    assert(bridge.call("_stage_blocked_facility", frozen, "unknown", "x").is_empty())
    assert(bridge.call("_stage_blocked_facility",
        {"facilities": {"farm": []}}, "farm", "x").is_empty())
    assert(frozen["markets"]["earth"]["supply"]["food"] == 9)
    print("PASS p2_perf_a_n39_blocked_owned")
    quit(0)
