extends SceneTree
## C/N84 regression: autonomous BTs are validated once before dispatch,
## while contracted BTs retain the post-recovery validation. This source
## guard intentionally does not claim behavioral replay or timing parity.
const SCRIPT_PATH = "res://scripts/sim/phase2/unified_ship_ai_execution.gd"

func _initialize() -> void:
    var file := FileAccess.open(SCRIPT_PATH, FileAccess.READ)
    if file == null:
        push_error("N84 source unavailable")
        quit(1)
        return
    var source := file.get_as_text()
    var first := 'if not (assigned_bt is Dictionary) or not Bt.validate(assigned_bt):'
    var second := 'if not (bt is Dictionary) or (contract_id != "" and not Bt.validate(bt)):'
    if source.count(first) != 1 or source.count(second) != 1:
        push_error("N84 autonomous/contract validation guards changed")
        quit(1)
        return
    if source.find(first) >= source.find(second):
        push_error("N84 autonomous validation must precede contract fallback")
        quit(1)
        return
    if source.find('return {"ok": false, "reason": "n84_invalid_active_source_plan"') < 0 or source.find('return {"ok": false, "reason": "n84_invalid_saved_plan"') < 0:
        push_error("N84 negative invalid-plan rejection removed")
        quit(1)
        return
    print("PASS: N84 duplicate BT validation source guards")
    quit(0)
