extends SceneTree
## Standalone oracle for swap-with-last cancellation and position invalidation.
## godot --headless --path godot --script res://tests/p2_perf_d_cancel_index_check.gd
const Queue = preload("res://scripts/sim/event_queue.gd")
const Index = preload("res://scripts/sim/phase2/p2_perf_d_due_index.gd")

func _initialize() -> void:
    var legacy = Queue.new()
    var fast = Index.new()
    var ids: Array[String] = []
    for i in range(1200):
        var id: String = "id_%04d" % i
        var tick: int = 1 + (i % 9)
        var phase: int = i % 3
        var entity: String = "entity_%03d" % ((i * 13) % 47)
        assert(legacy.schedule(id, tick, phase, entity, "delivery", {"nested": {"i": i}}))
        ids.append(id)
    assert(fast.rebuild(legacy.snapshot()["pending"]))
    # Cancel first, middle and last positions repeatedly, including moved entries.
    for i in range(ids.size() - 1, -1, -1):
        if i % 3 != 0:
            assert(legacy.cancel(ids[i]))
            assert(fast.remove(ids[i]))
            assert(not fast.remove(ids[i]))
    assert(legacy.pending_count() == fast.pending_count())
    # Reinsert into buckets after swap removals; sequence must remain authoritative.
    for i in range(120):
        var id: String = "replacement_%03d" % i
        assert(legacy.schedule(id, 2, 2, "entity_001", "delivery", {"nested": {"i": i}}))
        var records: Array = legacy.snapshot()["pending"]
        for record in records:
            if record["id"] == id:
                assert(fast.add(record))
                break
    assert(legacy.pending_count() == fast.pending_count())
    for tick in range(1, 10):
        for phase in range(3):
            var expected: Array[Dictionary] = legacy.take_due(tick, phase)
            var actual: Array[Dictionary] = fast.take_due(tick, phase)
            assert(expected == actual, "cancel index ordering mismatch %d/%d" % [tick, phase])
            if not actual.is_empty():
                actual[0]["payload"]["nested"]["i"] = -1
    assert(fast.pending_count() == 0)
    assert(legacy.pending_count() == 0)
    assert(not fast.remove("id_0000"))
    # A failed rebuild must leave the existing index intact.
    var original: Dictionary = {"id": "ok", "due_tick": 7, "phase": 1,
        "entity_id": "entity", "sequence": 1, "kind": "test", "payload": {}}
    assert(fast.rebuild([original]))
    assert(not fast.rebuild([original, original]))
    assert(fast.pending_count() == 1)
    assert(fast.take_due(7, 1)[0]["id"] == "ok")
    print("P2 PERF D cancellation oracle PASS")
    quit(0)
