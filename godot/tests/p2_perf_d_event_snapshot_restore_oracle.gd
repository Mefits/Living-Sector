extends SceneTree
# Astra II-C D: legacy deep-copy-before-sort oracle vs owned sorted snapshot,
# atomic indexed restore, cancellation, payload isolation and due ordering.
const Queue = preload("res://scripts/sim/event_queue.gd")

func _legacy_snapshot(q: RefCounted) -> Dictionary:
    # Original algorithm: deep clone first, then sort the detached records.
    var ordered: Array[Dictionary] = q._pending.duplicate(true)
    ordered.sort_custom(Callable(q, "_less"))
    return {"next_sequence": q._next_sequence, "pending": ordered}

func _initialize() -> void:
    var q = Queue.new()
    for i in range(400):
        var due_tick: int = 20 + i % 7
        var phase: int = i % 3
        var entity: String = "entity-%03d" % (399 - i % 29)
        assert(q.schedule("event-%03d" % i, due_tick, phase, entity,
            "transfer", {"nested": [{"amount": i, "tags": [i, i + 1]}]}))
    for i in range(0, 400, 9):
        assert(q.cancel("event-%03d" % i))
    var oracle: Dictionary = _legacy_snapshot(q)
    var actual: Dictionary = q.snapshot()
    assert(actual == oracle)
    assert(actual["pending"].size() == q.pending_count())
    # A returned snapshot must not alias the live event payload tree.
    actual["pending"][0]["payload"]["nested"][0]["tags"][0] = -999
    assert(q.snapshot() == oracle)
    var restored = Queue.new()
    assert(restored.restore(oracle, 19, 3))
    assert(restored.snapshot() == oracle)
    # Restored records must not alias the supplied serialized data.
    oracle["pending"][0]["payload"]["nested"][0]["amount"] = -1
    assert(restored.snapshot() != oracle)
    var baseline: Dictionary = restored.snapshot()
    var bad_sequence: Dictionary = baseline.duplicate(true)
    bad_sequence["pending"][1]["sequence"] = bad_sequence["pending"][0]["sequence"]
    assert(not restored.restore(bad_sequence, 19, 3))
    assert(restored.snapshot() == baseline)
    var bad_payload: Dictionary = baseline.duplicate(true)
    bad_payload["pending"][-1]["payload"] = 17
    assert(not restored.restore(bad_payload, 19, 3))
    assert(restored.snapshot() == baseline)
    var bad_phase: Dictionary = baseline.duplicate(true)
    bad_phase["pending"][-1]["phase"] = 3
    assert(not restored.restore(bad_phase, 19, 3))
    assert(restored.snapshot() == baseline)
    # Verify index cancellation and canonical due ordering against the
    # independent sorted snapshot, including mixed phase boundaries.
    var expected: Array = baseline["pending"]
    var dispatched: Array = []
    for tick in range(20, 27):
        for phase in range(3):
            for row in restored.take_due(tick, phase):
                dispatched.append(row)
            assert(restored.take_due(tick, phase).is_empty())
    assert(dispatched == expected)
    assert(restored.pending_count() == 0)
    assert(restored.snapshot()["pending"].is_empty())
    print("p2_perf_d_event_snapshot_restore_oracle PASS")
    quit()
