extends SceneTree
## Targeted regression for row-batched protected alias traversal.
## Run: godot --headless --path godot --script res://tests/p2_perf_a_batched_market_alias_check.gd
const Guard = preload("res://scripts/sim/phase1/n39_market_owned_write_guard.gd")

func _initialize() -> void:
    var before: Dictionary = {
        "earth": _market("earth"), "mars": _market("mars")}
    var detached: Dictionary = before.duplicate(true)
    _check(Guard.validate_owned_write(before, detached) == "",
        "detached_multi_market")
    var same_row: Dictionary = before.duplicate(true)
    same_row["earth"]["history"]["leak"] = before["earth"]["audit"]["nested"]
    _check(Guard.validate_owned_write(before, same_row) ==
        "market_write_aliased_protected_field", "same_row_second_protected")
    var other_row: Dictionary = before.duplicate(true)
    other_row["mars"]["history"]["leak"] = before["earth"]["audit"]["nested"]
    _check(Guard.validate_owned_write(before, other_row) ==
        "market_write_aliased_protected_field", "cross_market_second_protected")
    var independent_illegal: Dictionary = before.duplicate(true)
    independent_illegal["mars"]["stock"]["ore"] = 500.0
    _check(Guard.validate_owned_write(before, independent_illegal) ==
        "market_write_outside_observation", "detached_protected_write")
    print("P2_PERF_A_BATCHED_MARKET_ALIAS_PASS")
    quit(0)

func _market(identity: String) -> Dictionary:
    return {"id": identity, "credits": 100, "stock": {"ore": 20.0},
        "audit": {"nested": {"items": [1, 2]}},
        "prices": {"ore": 10.0}, "demand": {}, "seed_demand": {},
        "consumption_window": {}, "orders": {},
        "history": {"crisis_notified": {}}}

func _check(ok: bool, label: String) -> void:
    if not ok:
        push_error("P2_PERF_A_BATCHED_MARKET_ALIAS_FAIL: " + label)
        quit(1)
