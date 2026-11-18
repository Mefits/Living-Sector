extends SceneTree
## FLOW hypothesis: N84 can adopt Bt.tick's already detached tree.
## Run: godot --headless --path godot --script res://tests/p2_perf_flow_n84_bt_detach_oracle.gd
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

func _initialize() -> void:
    var source: Dictionary = Bt.sequence([
        Bt.action({"kind": "Travel", "destination": "Alpha"}),
        Bt.selector([Bt.action({"kind": "Dock"})])
    ])
    var original: Dictionary = source.duplicate(true)
    var calls: int = 0
    var dispatch: Callable = func(_action: Dictionary, _bb: Dictionary) -> Dictionary:
        calls += 1
        return {"status": Bt.SUCCESS, "commands": []}
    var next: Dictionary = Bt.tick(source, dispatch, {})
    if not next.get("ok", false) or calls != 1 or next.get("status") != Bt.RUNNING:
        push_error("FLOW BT oracle: original single-leaf Rust cursor semantics failed")
        quit(1)
        return
    var adopted: Dictionary = next["tree"]
    if source != original or int(source["index"]) != 0 or int(adopted["index"]) != 1:
        push_error("FLOW BT oracle: Bt.tick result aliases or mutates source")
        quit(1)
        return
    adopted["children"][0]["action"]["destination"] = "Changed"
    if source != original:
        push_error("FLOW BT oracle: nested action alias leaked into source")
        quit(1)
        return
    var second: Dictionary = Bt.tick(adopted, dispatch, {})
    if not second.get("ok", false) or calls != 2 or int(second["tree"]["index"]) != 0:
        push_error("FLOW BT oracle: persisted cursor progression changed")
        quit(1)
        return
    if int(adopted["index"]) != 1:
        push_error("FLOW BT oracle: second tick mutated adopted tree")
        quit(1)
        return
    var script_text: String = FileAccess.get_file_as_string(
        "res://scripts/sim/phase2/unified_ship_ai_execution.gd")
    if not script_text.contains('ship["current_bt"] = next["tree"]') or script_text.contains(
            'ship["current_bt"] = next["tree"].duplicate(true)'):
        push_error("FLOW BT oracle: N84 still clones the already detached BT")
        quit(1)
        return
    print("P2_PERF_FLOW_N84_BT_DETACH_ORACLE_PASS")
    quit(0)
