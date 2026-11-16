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
    # Snapshot is detached from live mutable rows, unlike a World alias.
    var live: Dictionary = old.duplicate(true)
    var protected_snapshot: Dictionary = Guard.capture_protected_fields(live)
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) == "",
        "snapshot_unchanged")
    live["earth"]["prices"]["ore"] = 14.0
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) == "",
        "snapshot_allows_observation")
    live["earth"]["stock"]["ore"] = 888.0
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) ==
        "market_write_outside_observation", "snapshot_catches_in_place_stock")
    live["earth"]["stock"]["ore"] = 20.0
    live["earth"]["credits"] = 888
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) ==
        "market_write_outside_observation", "snapshot_catches_in_place_credit")
    live["earth"]["credits"] = 100
    live["earth"]["forged_wallet"] = 1
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) ==
        "market_write_added_protected_field", "snapshot_rejects_extra_field")
    live["earth"].erase("forged_wallet")
    live["earth"].erase("stock")
    _expect(Guard.validate_protected_snapshot(protected_snapshot, live) ==
        "market_write_removed_protected_field", "snapshot_rejects_removed_field")
    _expect(protected_snapshot["earth"]["stock"]["ore"] == 20.0,
        "snapshot_deep_detached")
    # Malformed live market rows must never turn into a silently accepted
    # empty snapshot (or be healed by replacing a bad row after capture).
    var malformed_live: Dictionary = {"earth": 42}
    var malformed_snapshot: Dictionary = Guard.capture_protected_fields(malformed_live)
    _expect(Guard.validate_protected_snapshot(malformed_snapshot, malformed_live) ==
        "market_write_invalid_row", "snapshot_rejects_malformed_row")
    malformed_live["earth"] = _market()
    _expect(Guard.validate_protected_snapshot(malformed_snapshot, malformed_live) ==
        "market_write_invalid_row", "snapshot_rejects_healed_malformed_row")
    var mixed_live: Dictionary = {"earth": _market(), "mars": []}
    var mixed_snapshot: Dictionary = Guard.capture_protected_fields(mixed_live)
    _expect(Guard.validate_protected_snapshot(mixed_snapshot, mixed_live) ==
        "market_write_invalid_row", "snapshot_rejects_mixed_invalid_rows")
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
