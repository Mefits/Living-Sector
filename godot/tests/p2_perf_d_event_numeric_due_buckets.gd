extends SceneTree
# Run: godot --headless --path godot --script res://tests/p2_perf_d_event_numeric_due_buckets.gd
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    var reference: Array[Dictionary] = []
    # Mixed ticks/phases, duplicate entities, and intentionally reverse IDs.
    for i in range(320):
        var id: String = "evt_%03d" % (319 - i)
        var due: int = 10 + (i * 7) % 31
        var phase: int = (i * 3) % 5
        var entity: String = "entity_%02d" % ((i * 11) % 17)
        var payload: Dictionary = {"nested": {"value": i}}
        assert(q.schedule(id, due, phase, entity, "known", payload))
        payload["nested"]["value"] = -1
        reference.append({"id": id, "due_tick": due, "phase": phase,
            "entity_id": entity, "sequence": i + 1, "kind": "known",
            "payload": {"nested": {"value": i}}})
    assert(not q.schedule("evt_319", 10, 0, "entity", "known"))
    assert(not q.schedule("bad", 0, 0, "entity", "known"))
    assert(not q.schedule("bad", 10, 256, "entity", "known"))
    for i in range(0, 320, 9):
        var id: String = "evt_%03d" % (319 - i)
        assert(q.cancel(id))
        assert(not q.cancel(id))
        for j in range(reference.size() - 1, -1, -1):
            if reference[j]["id"] == id:
                reference.remove_at(j)
                break
    var original: Dictionary = q.snapshot()
    var invalid: Dictionary = original.duplicate(true)
    invalid["pending"][0]["sequence"] = 0
    assert(not q.restore(invalid, 0, 5))
    assert(q.snapshot() == original)
    var restored = Queue.new()
    assert(restored.restore(original, 0, 5))
    # Snapshot is detached from both queue and caller's input.
    original["pending"][0]["payload"]["nested"]["value"] = -99
    assert(restored.snapshot() == q.snapshot())
    for tick in range(1, 45):
        for phase in range(5):
            var expected: Array[Dictionary] = []
            for item in reference:
                if item["due_tick"] == tick and item["phase"] == phase:
                    expected.append(item.duplicate(true))
            expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
                if a["entity_id"] != b["entity_id"]:
                    return a["entity_id"] < b["entity_id"]
                return a["sequence"] < b["sequence"])
            assert(q.take_due(tick, phase) == expected)
            assert(restored.take_due(tick, phase) == expected)
            assert(q.take_due(tick, phase).is_empty())
    assert(q.pending_count() == 0)
    assert(restored.pending_count() == 0)
    # Reusing a removed ID is valid; sequence must remain monotonic.
    assert(q.schedule("evt_319", 55, 1, "entity", "unknown", {"v": 1}))
    assert(q.take_due(55, 1)[0]["sequence"] == 321)
    assert(q.snapshot()["pending"].is_empty())
    print("PASS p2_perf_d_event_numeric_due_buckets")
    quit(0)
