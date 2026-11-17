extends SceneTree
# Targeted negative oracle for event ordering after comparator hotpath change.
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    assert(q.schedule("z", 8, 2, "b", "known", {"nested": [1]}))
    assert(q.schedule("a", 8, 2, "a", "unknown", {}))
    assert(q.schedule("c", 8, 1, "z", "known", {}))
    assert(q.schedule("d", 9, 0, "a", "known", {}))
    assert(q.schedule("e", 8, 2, "a", "known", {}))
    assert(q.cancel("d"))
    assert(not q.cancel("missing"))
    var snapshot = q.snapshot()
    var ids: Array[String] = []
    for event in snapshot["pending"]:
        ids.append(str(event["id"]))
    assert(ids == ["c", "a", "e", "z"])
    var restored = Queue.new()
    assert(restored.restore(snapshot, 7, 3))
    assert(restored.take_due(8, 1).size() == 1)
    var due = restored.take_due(8, 2)
    assert(due.size() == 3)
    assert(due[0]["id"] == "a")
    assert(due[1]["id"] == "e")
    assert(due[2]["id"] == "z")
    assert(restored.take_due(8, 2).is_empty())
    assert(restored.pending_count() == 0)
    var bad = snapshot.duplicate(true)
    bad["pending"][1]["sequence"] = bad["pending"][0]["sequence"]
    assert(not q.restore(bad, 7, 3))
    assert(q.snapshot() == snapshot)
    print("p2_perf_d_event_order_comparator_20261117 PASS")
    quit()
