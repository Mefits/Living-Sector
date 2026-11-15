extends SceneTree
## Run with Godot --headless --path godot --script res://tests/p2_perf_a_market_owned_write_guard_check.gd
const Guard = preload("res://scripts/sim/phase1/n39_market_owned_write_guard.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
var _failed: bool = false

func _initialize() -> void:
    var old: Dictionary = {"earth": _market()}
    var unchanged: Dictionary = old.duplicate(true)
    _expect(Guard.validate_owned_write(old, unchanged) == "", "unchanged")
    var observation: Dictionary = old.duplicate(true)
    observation["earth"]["prices"]["ore"] = 12.0
    observation["earth"]["history"]["crisis_notified"]["ore"] = true
    _expect(Guard.validate_owned_write(old, observation) == "", "valid_observation")
    var forged_stock: Dictionary = observation.duplicate(true)
    forged_stock["earth"]["stock"]["ore"] = 999.0
    _expect(Guard.validate_owned_write(old, forged_stock) ==
        "market_write_outside_observation", "stock_mutation")
    var forged_credit: Dictionary = observation.duplicate(true)
    forged_credit["earth"]["credits"] = 999
    _expect(Guard.validate_owned_write(old, forged_credit) ==
        "market_write_outside_observation", "credit_mutation")
    var extra: Dictionary = observation.duplicate(true)
    extra["earth"]["hidden"] = {"minted": true}
    _expect(Guard.validate_owned_write(old, extra) ==
        "market_write_row_shape_changed", "extra_field")
    var missing: Dictionary = observation.duplicate(true)
    missing.erase("earth")
    _expect(Guard.validate_owned_write(old, missing) ==
        "market_write_cardinality_changed", "removed_market")
    var malformed: Dictionary = observation.duplicate(true)
    malformed["earth"]["prices"]["ore"] = -1.0
    _expect(Guard.validate_owned_write(old, malformed) != "", "invalid_price")
    # Local acceptance must NEVER stand in for the full Schema oracle:
    # this deliberately incomplete World is rejected by the original.
    _expect(Schema.validate({"markets": observation}) != "",
        "full_schema_oracle_remains_required")
    if not _failed:
        print("P2_PERF_A_MARKET_OWNED_WRITE_GUARD_PASS")
    quit(1 if _failed else 0)

func _market() -> Dictionary:
    return {"id": "earth", "credits": 100,
        "stock": {"ore": 20.0},
        "prices": {"ore": 10.0}, "demand": {},
        "seed_demand": {}, "consumption_window": {},
        "orders": {}, "history": {"crisis_notified": {}}}

func _expect(ok: bool, label: String) -> void:
    if not ok:
        push_error("P2_PERF_A_MARKET_OWNED_WRITE_GUARD_FAIL: " + label)
        _failed = true
