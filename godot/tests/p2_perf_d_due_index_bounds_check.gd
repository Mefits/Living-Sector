extends SceneTree
## Negative oracle for the opt-in due index; not a production backend switch.
const Queue = preload("res://scripts/sim/event_queue.gd")
const Index = preload("res://scripts/sim/phase2/p2_perf_d_due_index.gd")
const MAX_TICK: int = 9007199254740991

func _event(id: String, due: int, seq: int) -> Dictionary:
    return {"id": id, "due_tick": due, "phase": 2, "entity_id": "station",
        "sequence": seq, "kind": "arrival", "payload": {"nested": {"value": seq}}}

func _initialize() -> void:
    var fast = Index.new()
    var queue = Queue.new()
    assert(queue.schedule("a", MAX_TICK, 2, "station", "arrival", {"nested": {"value": 1}}))
    assert(queue.schedule("b", MAX_TICK, 2, "station", "arrival", {"nested": {"value": 2}}))
    assert(fast.rebuild(queue.snapshot()["pending"]))
    var before: int = fast.pending_count()
    assert(not fast.add(_event("overflow", MAX_TICK + 1, 3)))
    assert(not fast.add(_event("bad_sequence", 1, MAX_TICK)))
    assert(not fast.add(_event("duplicate_sequence", 1, 1)))
    assert(not fast.rebuild([_event("x", 1, 7), _event("y", 1, 7)]))
    assert(not fast.rebuild([_event("x", MAX_TICK + 1, 7)]))
    assert(fast.pending_count() == before)
    assert(fast.remove("a"))
    assert(queue.cancel("a"))
    assert(queue.schedule("reuse_sequence", MAX_TICK, 2, "station", "arrival", {"nested": {"value": 1}}))
    var latest: Dictionary = queue.snapshot()
    var replacement: Dictionary = {}
    for event in latest["pending"]:
        if event["id"] == "reuse_sequence":
            replacement = event
            break
    assert(not replacement.is_empty())
    assert(fast.add(replacement))
    var expected: Array[Dictionary] = queue.take_due(MAX_TICK, 2)
    var actual: Array[Dictionary] = fast.take_due(MAX_TICK, 2)
    assert(actual == expected)
    assert(fast.pending_count() == 0)
    assert(not fast.remove("b"))
    assert(fast.rebuild(queue.snapshot()["pending"]))
    print("P2 PERF D due index bounds/rollback PASS")
    quit(0)
