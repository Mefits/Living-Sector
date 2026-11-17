extends SceneTree
# Negative oracle: dispatched records have sole ownership after removal.
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    var source: Dictionary = {"nested": {"values": [1, 2]}}
    assert(q.schedule("late", 12, 1, "z", "unknown", {"v": 9}))
    assert(q.schedule("first", 11, 2, "b", "known", source))
    assert(q.schedule("second", 11, 2, "a", "unknown", {"nested": [7]}))
    assert(q.schedule("cancelled", 11, 2, "c", "known", {}))
    assert(q.cancel("cancelled"))
    assert(not q.cancel("cancelled"))
    source["nested"]["values"][0] = 999
    var before: Dictionary = q.snapshot()
    var due: Array[Dictionary] = q.take_due(11, 2)
    assert(due.size() == 2)
    assert(due[0]["id"] == "second")
    assert(due[1]["id"] == "first")
    assert(due[1]["payload"]["nested"]["values"][0] == 1)
    due[1]["payload"]["nested"]["values"][0] = -100
    due[0]["payload"]["nested"].append(99)
    assert(q.pending_count() == 1)
    assert(q.snapshot()["pending"][0]["id"] == "late")
    assert(q.take_due(11, 2).is_empty())
    var restored = Queue.new()
    assert(restored.restore(before, 10, 3))
    var restored_due: Array[Dictionary] = restored.take_due(11, 2)
    assert(restored_due.size() == 2)
    assert(restored_due[1]["payload"]["nested"]["values"][0] == 1)
    assert(restored.take_due(11, 2).is_empty())
    assert(restored.take_due(12, 1).size() == 1)
    assert(restored.pending_count() == 0)
    print("p2_perf_d_due_transfer_ownership_20261117 PASS")
    quit()
