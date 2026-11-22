extends SceneTree
# Negative regression: live take_due compaction must match canonical ordering,
# preserve cancellation after compaction, and survive restore.
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    for i in range(160):
        var due: int = 5 if i % 3 == 0 else 8
        var phase: int = i % 2
        assert(q.schedule("ev_%d" % i, due, phase, "entity_%d" % (159 - i), "test", {"nested": [i]}))
    assert(not q.cancel("missing"))
    assert(q.cancel("ev_3"))
    assert(q.cancel("ev_159"))
    var baseline: Dictionary = q.snapshot()
    var oracle: Array = []
    for event in baseline["pending"]:
        if int(event["due_tick"]) == 5 and int(event["phase"]) == 0:
            oracle.append(event)
    var actual: Array[Dictionary] = q.take_due(5, 0)
    assert(actual == oracle)
    assert(q.take_due(5, 0).is_empty())
    assert(q.pending_count() == 158 - oracle.size())
    # The moved survivors must still be reachable through their position map.
    assert(q.cancel("ev_1"))
    assert(q.cancel("ev_158"))
    assert(not q.cancel("ev_3"))
    var snapshot: Dictionary = q.snapshot()
    var restored = Queue.new()
    assert(restored.restore(snapshot, 0, 2))
    assert(restored.snapshot() == snapshot)
    var corrupt: Dictionary = snapshot.duplicate(true)
    corrupt["pending"][0]["id"] = ""
    assert(not restored.restore(corrupt, 0, 2))
    assert(restored.snapshot() == snapshot)
    var remaining_oracle: Array = []
    for event in snapshot["pending"]:
        if int(event["due_tick"]) == 8 and int(event["phase"]) == 1:
            remaining_oracle.append(event)
    assert(restored.take_due(8, 1) == remaining_oracle)
    print("p2_perf_d_due_compaction_oracle PASS")
    quit()
