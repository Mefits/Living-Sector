extends SceneTree
## Run with Godot --headless --path godot --script res://tests/p2_perf_a_market_owned_write_guard_check.gd
const Guard = preload("res://scripts/sim/phase1/n39_market_owned_write_guard.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
var _failed: bool = false

func _initialize() -> void:
    var old: Dictionary = {"earth": _market()}
    var unchanged: Dictionary = old.duplicate(true)
    _expect(Guard.validate_owned_write(old, unchanged) == "", "unchanged")
    # Equal dictionary contents are insufficient if the before/after rows
    # share mutable storage: a forbidden in-place stock write is invisible.
    _expect(Guard.validate_owned_write(old, old) ==
        "market_write_aliased_baseline", "reject_same_market_map")
    var aliased_rows: Dictionary = {"earth": old["earth"]}
    _expect(Guard.validate_owned_write(old, aliased_rows) ==
        "market_write_aliased_baseline", "reject_shared_market_row")
    # Distinct row dictionaries are insufficient when protected stock is shared.
    var shallow_row: Dictionary = old["earth"].duplicate(false)
    var nested_alias: Dictionary = {"earth": shallow_row}
    _expect(Guard.validate_owned_write(old, nested_alias) ==
        "market_write_aliased_protected_field", "reject_nested_stock_alias")
    var nested_array_old: Dictionary = {"earth": _market()}
    nested_array_old["earth"]["audit"] = {"entries": [1, 2]}
    var nested_array_after: Dictionary = nested_array_old.duplicate(true)
    nested_array_after["earth"]["audit"]["entries"] = nested_array_old["earth"]["audit"]["entries"]
    _expect(Guard.validate_owned_write(nested_array_old, nested_array_after) ==
        "market_write_aliased_protected_field", "reject_deep_array_alias")
    var independent_nested: Dictionary = nested_array_old.duplicate(true)
    _expect(Guard.validate_owned_write(nested_array_old, independent_nested) == "",
        "accept_deep_detached_protected")
    var detached_rows: Dictionary = old.duplicate(true)
    _expect(Guard.validate_owned_write(old, detached_rows) == "",
        "accept_detached_equal_rows")
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
    # Combined shadow validation is alias-safe and rejects malformed N150
    # observations even when all protected fields remain unchanged.
    var shadow_live: Dictionary = {"earth": _market()}
    var shadow_before: Dictionary = Guard.capture_protected_fields(shadow_live)
    _expect(Guard.validate_shadow_boundary(shadow_before, shadow_live) == "",
        "shadow_valid")
    shadow_live["earth"]["prices"]["ore"] = -4.0
    _expect(Guard.validate_shadow_boundary(shadow_before, shadow_live) ==
        "invalid_market_price", "shadow_invalid_price")
    shadow_live["earth"]["prices"]["ore"] = 10.0
    shadow_live["earth"]["history"]["crisis_notified"]["ore"] = "yes"
    _expect(Guard.validate_shadow_boundary(shadow_before, shadow_live) ==
        "invalid_native_market_crisis_flag", "shadow_invalid_flag")
    shadow_live["earth"]["history"]["crisis_notified"]["ore"] = true
    shadow_live["earth"]["stock"]["ore"] = 19.0
    _expect(Guard.validate_shadow_boundary(shadow_before, shadow_live) ==
        "market_write_outside_observation", "shadow_protected_mutation")
    shadow_live["earth"]["stock"]["ore"] = 20.0
    shadow_live["earth"]["id"] = "mars"
    _expect(Guard.validate_shadow_boundary(shadow_before, shadow_live) ==
        "market_write_outside_observation", "shadow_identity_mutation")
    var no_identity: Dictionary = {"earth": {"credits": 100}}
    var no_id_live: Dictionary = {"earth": {"credits": 100,
        "prices": {}, "demand": {}, "seed_demand": {},
        "consumption_window": {}, "orders": {}, "history": {}}}
    _expect(Guard.validate_shadow_boundary(no_identity, no_id_live) ==
        "market_write_missing_protected_identity", "shadow_missing_identity")
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
