extends SceneTree
# Run: godot --headless --path godot --script res://tests/p2_perf_d_due_bulk_boundary_20261117.gd
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    assert(q.schedule("later", 9, 1, "z", "known", {"nested": {"value": 1}}))
    assert(q.schedule("b", 5, 2, "b", "known"))
    assert(q.schedule("a", 5, 2, "a", "unknown"))
    assert(q.schedule("c", 5, 2, "a", "known"))
    assert(q.schedule("cancel", 5, 2, "x", "known"))
    assert(q.cancel("cancel"))
    assert(not q.cancel("missing"))
    assert(q.take_due(5, 1).is_empty())
    var saved: Dictionary = q.snapshot()
    var restored = Queue.new()
    assert(restored.restore(saved, 4, 4))
    var expected: Array = ["a", "c", "b"]
    for queue in [q, restored]:
        var due: Array[Dictionary] = queue.take_due(5, 2)
        assert(due.size() == expected.size())
        for i in range(expected.size()):
            assert(due[i]["id"] == expected[i])
        assert(queue.take_due(5, 2).is_empty())
        assert(queue.pending_count() == 1)
        assert(queue.schedule("new", 5, 2, "n", "known"))
        assert(queue.take_due(5, 2).size() == 1)
        var later: Array[Dictionary] = queue.take_due(9, 1)
        assert(later.size() == 1 and later[0]["id"] == "later")
        assert(queue.pending_count() == 0)
    var broken: Dictionary = saved.duplicate(true)
    broken["pending"].append(broken["pending"][0].duplicate(true))
    assert(not restored.restore(broken, 4, 4))
    assert(restored.pending_count() == 0)
    print("PASS p2_perf_d_due_bulk_boundary_20261117")
    quit(0)
