extends SceneTree
## N42 CODE_UNVERIFIED:
## godot --headless --path godot --script res://tests/n42_world_integrity_check.gd
const Audit = preload("res://scripts/sim/world_integrity_audit.gd")

func _initialize() -> void:
    var auditor = Audit.new()
    var before: Dictionary = _world()
    var valid: Dictionary = auditor.audit_snapshot(before)
    assert(valid["ok"])
    assert(valid["total_credits"] == 100)
    assert(is_equal_approx(float(valid["goods"]["ore"]), 20.0))
    var after: Dictionary = before.duplicate(true)
    after["credits"]["buyer"] = 70
    after["credits"]["seller"] = 30
    after["stores"]["mine"]["ore"] = 12.0
    after["cargo"]["ship-1"]["ore"] = 8.0
    assert(auditor.audit_closed_transfer(before, after)["ok"])
    assert(before["stores"]["mine"]["ore"] == 20.0)
    assert(before["credits"]["buyer"] == 100)
    var minted: Dictionary = after.duplicate(true)
    minted["credits"]["seller"] = 31
    assert(auditor.audit_closed_transfer(before, minted)["errors"].has("credits_not_conserved"))
    var phantom: Dictionary = after.duplicate(true)
    phantom["cargo"]["ship-1"]["ore"] = 9.0
    assert(auditor.audit_closed_transfer(before, phantom)["errors"].has("goods_not_conserved:ore"))
    var mismatch: Dictionary = after.duplicate(true)
    mismatch["dock"]["ship-1"] = "unknown"
    assert(auditor.audit_snapshot(mismatch)["errors"].has("dock_location_mismatch:ship-1"))
    var missing_owner: Dictionary = after.duplicate(true)
    missing_owner["ship_owner"].erase("ship-1")
    assert(auditor.audit_snapshot(missing_owner)["errors"].has("missing_ship_owner:ship-1"))
    var negative: Dictionary = after.duplicate(true)
    negative["stores"]["mine"]["ore"] = -1.0
    assert(not auditor.audit_snapshot(negative)["ok"])
    var nan_value: Dictionary = after.duplicate(true)
    nan_value["cargo"]["ship-1"]["ore"] = NAN
    assert(not auditor.audit_snapshot(nan_value)["ok"])
    var incomplete: Dictionary = {"credits": {}}
    assert(not auditor.audit_snapshot(incomplete)["ok"])
    var replay: Dictionary = after.duplicate(true)
    assert(auditor.audit_closed_transfer(after, replay)["ok"])
    print("N42_WORLD_INTEGRITY_OK")
    quit(0)

func _world() -> Dictionary:
    return {
        "credits": {"buyer": 100, "seller": 0},
        "stores": {"mine": {"ore": 20.0}, "port": {"ore": 0.0}},
        "cargo": {"ship-1": {"ore": 0.0}},
        "ship_owner": {"ship-1": "faction-a"},
        "ship_location": {"ship-1": "port"},
        "dock": {"ship-1": "port"}
    }
