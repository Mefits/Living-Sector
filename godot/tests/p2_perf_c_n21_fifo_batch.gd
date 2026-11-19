extends SceneTree
## II-C N21: quoted-vs-uncached paid admission, queue ownership, FIFO negatives.
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")

class FakeBank:
    extends RefCounted
    var transfers: Array = []
    func transfer(op: String, src: String, dst: String,
            amount: int, tick: int, memo: String) -> Dictionary:
        transfers.append([op, src, dst, amount, tick, memo])
        return {"ok": true}
    func snapshot() -> Dictionary:
        return {"transfers": transfers.duplicate(true)}

func _world(queue: Array) -> Dictionary:
    return {"facilities": {"dock": {
        "location": "sol", "faction": "a", "docking_capacity": 8,
        "condition": 1.0, "credits": 100, "dock_queue": queue.duplicate()}},
        "ships": {"s1": {"location": "sol", "docked_at": "",
            "credits": 100000, "dock_attempt_start_tick": 1},
            "s2": {"location": "sol", "docked_at": "",
            "credits": 100000, "dock_attempt_start_tick": 1}},
        "dock_receipts": {}, "faction_relations": {}}

func _compare(queue: Array, sid: String) -> void:
    var source: Dictionary = _world(queue)
    var old_world: Dictionary = source.duplicate(true)
    var new_world: Dictionary = source.duplicate(true)
    var occupancy_a: Dictionary = {"dock": 0}
    var occupancy_b: Dictionary = {"dock": 0}
    var quote: int = Dock._fee(new_world, "dock", sid, occupancy_b)
    assert(quote >= 0)
    var old_bank: FakeBank = FakeBank.new()
    var new_bank: FakeBank = FakeBank.new()
    var legacy: Dictionary = Dock._admit(old_world, old_bank,
        "dock", sid, 11, "fifo_tick", occupancy_a)
    var indexed: Dictionary = Dock._admit(new_world, new_bank,
        "dock", sid, 11, "fifo_tick", occupancy_b, quote)
    assert(legacy.get("ok", false) and indexed.get("ok", false))
    assert(legacy["world"] == indexed["world"])
    assert(legacy["receipt"] == indexed["receipt"])
    assert(old_bank.transfers == new_bank.transfers)
    assert(occupancy_a == occupancy_b)
    assert(source["facilities"]["dock"]["dock_queue"] == queue)
    assert(source["ships"]["s1"]["docked_at"] == "")
    assert(indexed["world"]["facilities"]["dock"]["dock_queue"] ==
        (["s2"] if sid == "s1" and queue == ["s1", "s2"] else
        (["s1"] if sid == "s2" and queue == ["s1", "s2"] else [])))

func _initialize() -> void:
    _compare(["s1", "s2"], "s1") # paid FIFO head
    _compare(["s1", "s2"], "s2") # paid fast path non-head
    _compare(["s1"], "s1")
    # Invalid quoted fee must reject without a transfer or any mutation.
    var w: Dictionary = _world(["s1"])
    var before: Dictionary = w.duplicate(true)
    var bank: FakeBank = FakeBank.new()
    var bad: Dictionary = Dock._admit(w, bank, "dock", "s1", 12,
        "fifo_tick", {"dock": 0}, -1)
    assert(not bad.get("ok", false))
    assert(bank.transfers.is_empty())
    assert(w == before)
    # A full dock cannot admit even with a valid cached quote.
    var full: Dictionary = _world(["s1"])
    var price: int = Dock._fee(full, "dock", "s1", {"dock": 8})
    var denied: Dictionary = Dock._admit(full, FakeBank.new(),
        "dock", "s1", 12, "fifo_tick", {"dock": 8}, price)
    assert(not denied.get("ok", false))
    # Run the existing paid-tick oracle as an end-to-end contract guard.
    var Paid = load("res://tests/p2_n21_fifo_paid_source_check.gd")
    var paid: Dictionary = Paid.run_checks()
    assert(paid.get("ok", false), str(paid))
    print("P2_PERF_C_N21_FIFO_BATCH_PASS")
    quit(0)
