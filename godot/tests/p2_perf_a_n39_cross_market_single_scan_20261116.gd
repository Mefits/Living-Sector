extends SceneTree
## Negative regression for the single-pass cross-market N39 ownership guard.
const Guard = preload("res://scripts/sim/phase1/n39_market_owned_write_guard.gd")

var _failed: bool = false

func _initialize() -> void:
    var before: Dictionary = {}
    for i in range(12):
        before["market_%d" % i] = {
            "id": "market_%d" % i,
            "stock": {"ore": i},
            "prices": {"ore": 10},
            "demand": {}, "seed_demand": {},
            "consumption_window": {}, "orders": {},
            "history": {"crisis_notified": {}}
        }
    var after: Dictionary = before.duplicate(true)
    _expect(Guard.validate_owned_write(before, after) == "",
        "independent deep copy should pass")
    after["market_11"]["history"]["injected"] = before["market_0"]["stock"]
    _expect(Guard.validate_owned_write(before, after) ==
        "market_write_aliased_protected_field",
        "cross-market protected storage reparenting must fail")
    after = before.duplicate(true)
    after["market_11"]["stock"] = before["market_0"]["stock"]
    _expect(Guard.validate_owned_write(before, after) ==
        "market_write_aliased_protected_field",
        "cross-market protected-to-protected alias must fail")
    after = before.duplicate(true)
    after["market_11"]["stock"]["ore"] = 999
    _expect(Guard.validate_owned_write(before, after) ==
        "market_write_outside_observation",
        "independent but modified protected stock must fail")
    if _failed:
        quit(1)
    else:
        print("PASS p2_perf_a_n39_cross_market_single_scan_20261116")
        quit(0)

func _expect(ok: bool, label: String) -> void:
    if not ok:
        push_error(label)
        quit(1)
