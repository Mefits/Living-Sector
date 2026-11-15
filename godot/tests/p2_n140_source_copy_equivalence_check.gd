extends SceneTree
## Verifies N140 read-only handoff to the original N84 source executor.
## No fake transit/credit receipts and no physical gameplay mutation.
## godot --headless --path godot --script res://tests/p2_n140_source_copy_equivalence_check.gd
const Dispatch = preload("res://scripts/sim/phase2/unified_n140_ship_ai_dispatch.gd")
const SourceAI = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

class UnusedGraph:
    extends RefCounted

func _initialize() -> void:
    var plan: Dictionary = BT.sequence([BT.action({"kind": "Undock"})])
    if not BT.validate(plan):
        _fail("invalid original N84 source tree")
        return
    var ship: Dictionary = {
        "id": "ship-a", "location": "earth-station", "docked_at": "earth-port",
        "transit": {}, "current_goal": "mine", "current_bt": plan,
        "active_contract_id": "", "credits": 1000, "cargo": {},
        "transaction": {}, "dock_attempt_start_tick": null
    }
    var sleeper: Dictionary = ship.duplicate(true)
    sleeper["id"] = "ship-b"
    sleeper["current_goal"] = "idle"
    sleeper["current_bt"] = null
    sleeper["cargo"] = {"ice": 2}
    var world: Dictionary = {
        "ships": {"ship-a": ship, "ship-b": sleeper},
        "ship_next_token": 5,
        "contract_board": {"contracts": {}},
        "markets": {"earth-station": {"owner": "earth-port"}},
        "facilities": {"earth-port": {"location": "earth-station",
            "type": "station", "docking_capacity": 2, "abandoned": false}},
        "cargo_receipts": {"historical": {"ok": true}},
        "dock_receipts": {"earlier": {"ship_id": "ship-b", "tick": 1}}
    }
    var original: Dictionary = world.duplicate(true)
    var graph := UnusedGraph.new()
    # Baseline is the former N140 full-deep-copy forwarding semantics.
    var full_clone: Dictionary = world.duplicate(true)
    full_clone["ships"] = {"ship-a": world["ships"]["ship-a"].duplicate(true)}
    var baseline: Dictionary = SourceAI.propose(
        full_clone, graph, {}, 42, 1.0, 1)
    var result: Dictionary = Dispatch.propose(
        world, graph, {}, 42, 1.0, {"ship-a": 1}, 1)
    if not baseline.get("ok", false) or not result.get("ok", false):
        _fail("source N84/N140 rejected original dock release")
        return
    if result.get("commands", []) != baseline.get("commands", []) or (
            result.get("trace", []) != baseline.get("trace", []) or
            result.get("changed") != baseline.get("changed") or
            result.get("next_token") != baseline.get("next_token") or
            result["ships"]["ship-a"] != baseline["ships"]["ship-a"]):
        _fail("N140 forwarding changed a source N84 decision or cursor")
        return
    var commands: Array = result.get("commands", [])
    if commands.size() != 1 or str(commands[0].get("kind", "")) != "ReleaseDock":
        _fail("the original N146 physical release intent disappeared")
        return
    if world != original or result["ships"]["ship-b"] != original["ships"]["ship-b"]:
        _fail("source N39 World or sleeping actor changed during preview")
        return
    result["ships"]["ship-a"]["credits"] = -1
    result["ships"]["ship-b"]["cargo"]["ice"] = 99
    if world != original:
        _fail("N140 result aliases mutable N39 ship or cargo data")
        return
    var empty: Dictionary = Dispatch.propose(
        world, graph, {}, 43, 1.0, {}, 1)
    if not empty.get("ok", false) or empty.get("changed", true) or (
            not empty.get("commands", []).is_empty() or world != original):
        _fail("sleeping N140 gate mutated source world or dispatched")
        return
    print("P2_N140_N84_SHALLOW_FORWARDING_SOURCE_PARITY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N140_COPY_GUARD_FAIL: " + reason)
    quit(1)
