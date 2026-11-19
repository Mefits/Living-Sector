extends SceneTree
## Independent sequential paid-admission oracle for N21's batched N9
## restore/snapshot path. Exercises multiple real paid receipts in one tick.
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

func _world(broke_first: bool = false, stale_first: bool = false) -> Dictionary:
    var ships: Dictionary = {}
    for sid in ["a", "b", "c"]:
        ships[sid] = {"id": sid, "location": "sol", "docked_at": "",
            "transit": {}, "credits": 0 if broke_first and sid == "a" else 1000,
            "faction_id": "f", "dock_attempt_start_tick": 3,
            "current_bt": BT.sequence([BT.action({"kind": "Dock"})])}
    if stale_first:
        ships["a"]["transit"] = {"token": 8}
    return {"ships": ships, "facilities": {"dock": {
        "location": "sol", "faction": "f", "docking_capacity": 3,
        "condition": 1.0, "credits": 100, "dock_queue": ["a", "b", "c"],
        "abandoned": false, "dirty": false}},
        "dock_receipts": {}, "faction_relations": {}}

func _ledger(world: Dictionary) -> Dictionary:
    var bank := Bank.new()
    var accounts: Dictionary = {"facility:dock": 100}
    for sid in ["a", "b", "c"]:
        accounts["ship:" + sid] = int(world["ships"][sid]["credits"])
    assert(bank.import_accounts(accounts))
    return bank.snapshot()

func _sequential_oracle(world: Dictionary, ledger: Dictionary, tick: int) -> Dictionary:
    var staged: Dictionary = world.duplicate(true)
    var current: Dictionary = ledger.duplicate(true)
    var occupancy: Dictionary = {}
    var events: Array = []
    Dock._prune(staged, "dock")
    for sid in (staged["facilities"]["dock"]["dock_queue"] as Array).duplicate():
        var fee: int = Dock._fee(staged, "dock", sid, occupancy)
        if fee < 0 or int(staged["ships"][sid]["credits"]) < fee:
            staged["facilities"]["dock"]["dock_queue"].erase(sid)
            staged["ships"][sid]["dock_attempt_start_tick"] = null
            continue
        # Original path: a fresh dictionary N9 restore + snapshot per ship.
        var result: Dictionary = Dock._admit(
            staged, current, "dock", sid, tick, "fifo_tick", occupancy)
        assert(result.get("ok", false))
        staged = result["world"]
        current = result["ledger_snapshot"]
        events.append(result["receipt"])
    return {"world": staged, "ledger_snapshot": current, "events": events}

func _initialize() -> void:
    for insolvent in [false, true]:
        for stale in [false, true]:
            var world: Dictionary = _world(insolvent, stale)
            var ledger: Dictionary = _ledger(world)
            var before_world: Dictionary = world.duplicate(true)
            var before_ledger: Dictionary = ledger.duplicate(true)
            var oracle: Dictionary = _sequential_oracle(world, ledger, 20)
            var actual: Dictionary = Dock.advance(world, ledger, 20)
            assert(actual.get("ok", false))
            assert(actual["world"] == oracle["world"])
            assert(actual["ledger_snapshot"] == oracle["ledger_snapshot"])
            assert(actual["events"] == oracle["events"])
            assert(world == before_world)
            assert(ledger == before_ledger)
            # No receipt can be replayed or charged again on a retry.
            var retry: Dictionary = Dock.advance(
                actual["world"], actual["ledger_snapshot"], 20)
            assert(retry.get("ok", false))
            assert(not bool(retry.get("changed", false)))
            assert(retry["ledger_snapshot"] == actual["ledger_snapshot"])
            # Both returned objects must detach from input nested state.
            actual["world"]["ships"]["b"]["credits"] = -777
            assert(world == before_world)
    # An invalid N9 snapshot must never produce paid queue admissions.
    var bad_world: Dictionary = _world()
    var invalid: Dictionary = Dock.advance(bad_world, {"invalid": true}, 21)
    assert(not invalid.get("ok", false))
    assert(bad_world["dock_receipts"].is_empty())
    print("PASS p2_perf_c_n21_dock_queue_owned_stage")
    quit(0)
