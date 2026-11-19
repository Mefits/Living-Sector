extends SceneTree
# Run with Godot --headless --path godot --script res://tests/p2_perf_d_event_due_counts_20261116.gd
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    # Schedule events with multiple future boundaries and equal entity IDs.
    for i in range(240):
        var tick: int = 10 + i % 17
        var phase: int = i % 4
        var id: String = "event_%d" % i
        var entity: String = "entity_%d" % (i % 9)
        assert(q.schedule(id, tick, phase, entity, "probe", {"nested": [i]}))
    for i in range(0, 240, 7):
        var id: String = "event_%d" % i
        assert(q.cancel(id))
    # Negative restore must not corrupt the derived index.
    var before: Dictionary = q.snapshot()
    var bad: Dictionary = before.duplicate(true)
    bad["pending"][0]["sequence"] = 0
    assert(not q.restore(bad, 0, 4))
    assert(q.snapshot() == before)
    # Successful restore must reconstruct counts and preserve ordering.
    var restored = Queue.new()
    assert(restored.restore(before, 0, 4))
    for tick in range(1, 32):
        for phase in range(4):
            var expected: Array[Dictionary] = []
            for event in before["pending"]:
                if int(event["due_tick"]) == tick and int(event["phase"]) == phase:
                    expected.append(event.duplicate(true))
            assert(q.take_due(tick, phase) == expected)
            assert(restored.take_due(tick, phase) == expected)
            assert(q.take_due(tick, phase).is_empty())
    assert(q.pending_count() == 0)
    assert(restored.pending_count() == 0)
    print("PASS p2_perf_d_event_due_counts_20261116")
    quit(0)
