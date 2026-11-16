extends RefCounted
## N84 DockDwell: cached single-pass N21 receipt lookup versus original
## per-ship full scan. No N9 payment, cargo, fuel or World mutation.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _oracle(receipts: Dictionary, ship_id: String) -> int:
    var latest: int = -1
    for receipt in receipts.values():
        if str(receipt.get("ship_id", "")) == ship_id and str(receipt.get("action", "")) == "dock":
            latest = maxi(latest, int(receipt.get("tick", -1)))
    return latest

static func run() -> Dictionary:
    var world: Dictionary = {"ships": {}, "dock_receipts": {},
        "contract_board": {"contracts": {}}}
    for i in range(4000):
        world["dock_receipts"]["receipt_%04d" % i] = {
            "ship_id": "ship_%03d" % (i % 120),
            "action": "undock" if i % 7 == 0 else "dock",
            "tick": i % 350}
    var original: Dictionary = world.duplicate(true)
    var scratch: Dictionary = {}
    for i in range(120):
        var sid: String = "ship_%03d" % i
        world["ships"][sid] = {"id": sid, "docked_at": "station",
            "location": "A", "active_contract_id": "",
            "fuel": 20 + i, "cargo": {"ore": i}, "credits": 100 + i}
        var actual: Dictionary = N84._dispatch({"kind": "DockDwell", "seconds": 3},
            {}, world, null, {}, sid, 400, 1.0, 1, scratch)
        var last: int = _oracle(world["dock_receipts"], sid)
        var expected: String = Bt.SUCCESS if last >= 0 and 400 - last >= 24 else Bt.RUNNING
        if str(actual.get("status", "")) != expected:
            return {"ok": false, "reason": "dwell_oracle_" + sid}
    if not scratch.has("_ready"):
        return {"ok": false, "reason": "cache_not_used"}
    # Negative: an undocked ship cannot use a cached dock receipt.
    world["ships"]["ship_000"]["docked_at"] = ""
    var negative: Dictionary = N84._dispatch({"kind": "DockDwell", "seconds": 0},
        {}, world, null, {}, "ship_000", 400, 1.0, 1, scratch)
    if str(negative.get("status", "")) != Bt.RUNNING:
        return {"ok": false, "reason": "undocked_false_success"}
    # New paid tick must not inherit a stale latest receipt cursor.
    world["ships"]["ship_000"]["docked_at"] = "station"
    world["dock_receipts"]["new_paid_dock"] = {
        "ship_id": "ship_000", "action": "dock", "tick": 400}
    var fresh: Dictionary = {}
    var after: Dictionary = N84._dispatch({"kind": "DockDwell", "seconds": 3},
        {}, world, null, {}, "ship_000", 400, 1.0, 1, fresh)
    if str(after.get("status", "")) != Bt.RUNNING:
        return {"ok": false, "reason": "stale_paid_dock_receipt"}
    if original["dock_receipts"].size() != 4000:
        return {"ok": false, "reason": "source_receipts_changed"}
    for i in range(120):
        var sid: String = "ship_%03d" % i
        if int(world["ships"][sid]["fuel"]) != 20 + i or int(world["ships"][sid]["cargo"]["ore"]) != i:
            return {"ok": false, "reason": "cargo_fuel_mutated"}
    return {"ok": true}
