extends SceneTree
# Run with: godot --headless --path godot --script res://tests/p2_perf_d_cancel_position_oracle_20261116.gd
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var queue = Queue.new()
    var reference: Array[Dictionary] = []
    for i in range(120):
        var id: String = "event_%d" % i
        var due: int = 10 + (i % 4)
        var phase: int = i % 3
        var entity: String = "entity_%d" % (119 - i)
        assert(queue.schedule(id, due, phase, entity, "unknown_event", {"nested": [i]}))
        reference.append({"id": id, "due_tick": due, "phase": phase, "entity_id": entity, "sequence": i + 1})
    # First/middle/last cancellation, including a moved last element.
    for i in [0, 47, 119, 46, 118, 1]:
        var id: String = "event_%d" % i
        assert(queue.cancel(id))
        assert(not queue.cancel(id))
        for j in range(reference.size() - 1, -1, -1):
            if reference[j]["id"] == id:
                reference.remove_at(j)
    assert(not queue.cancel("missing"))
    var before_bad: Dictionary = queue.snapshot()
    var invalid: Dictionary = before_bad.duplicate(true)
    invalid["pending"][0]["id"] = ""
    assert(not queue.restore(invalid, 9, 3))
    assert(queue.snapshot() == before_bad)
    var restored = Queue.new()
    assert(restored.restore(queue.snapshot(), 9, 3))
    assert(restored.cancel("event_2"))
    assert(queue.cancel("event_2"))
    for j in range(reference.size() - 1, -1, -1):
        if reference[j]["id"] == "event_2":
            reference.remove_at(j)
    for tick in range(10, 14):
        for phase in range(3):
            var expected: Array[Dictionary] = []
            for item in reference:
                if item["due_tick"] == tick and item["phase"] == phase:
                    expected.append(item)
            expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
                if a["entity_id"] != b["entity_id"]:
                    return a["entity_id"] < b["entity_id"]
                return a["sequence"] < b["sequence"])
            var actual: Array[Dictionary] = queue.take_due(tick, phase)
            var replay: Array[Dictionary] = restored.take_due(tick, phase)
            assert(actual == replay)
            assert(actual.size() == expected.size())
            for k in range(actual.size()):
                assert(actual[k]["id"] == expected[k]["id"])
            assert(queue.take_due(tick, phase).is_empty())
    assert(queue.pending_count() == 0)
    assert(restored.pending_count() == 0)
    print("PASS p2_perf_d_cancel_position_oracle")
    quit(0)
