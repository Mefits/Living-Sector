extends SceneTree
## Standalone headless oracle: godot --headless --path godot --script res://tests/p2_perf_d_due_index_check.gd
const Queue = preload("res://scripts/sim/event_queue.gd")
const Index = preload("res://scripts/sim/phase2/p2_perf_d_due_index.gd")

func _initialize() -> void:
    var queue = Queue.new()
    var index = Index.new()
    var ids: Array[String] = []
    for i in range(240):
        var id: String = "ev_%03d" % i
        var tick: int = 1 + (i * 17) % 37
        var phase: int = (i * 7) % 8
        var entity: String = "entity_%02d" % ((i * 13) % 11)
        var payload: Dictionary = {"nested": {"v": i}}
        assert(queue.schedule(id, tick, phase, entity, "test", payload))
        ids.append(id)
    assert(index.rebuild(queue.snapshot()["pending"]))
    # Cancels and subsequent additions must preserve insertion sequence tie breaks.
    for i in range(0, ids.size(), 9):
        assert(queue.cancel(ids[i]))
        assert(index.remove(ids[i]))
    for i in range(20):
        var id: String = "late_%02d" % i
        assert(queue.schedule(id, 4, 2, "same", "test", {"i": i}))
        var pending: Array = queue.snapshot()["pending"]
        var record: Dictionary = {}
        for event in pending:
            if event["id"] == id:
                record = event
                break
        assert(index.add(record))
    assert(queue.pending_count() == index.pending_count())
    # Mutation of returned data cannot corrupt internal index.
    var snapshot: Dictionary = queue.snapshot()
    var before: int = index.pending_count()
    assert(not index.rebuild([{"id": "broken"}]))
    assert(index.pending_count() == before)
    assert(index.rebuild(snapshot["pending"]))
    for tick in range(1, 39):
        for phase in range(8):
            var expected: Array[Dictionary] = queue.take_due(tick, phase)
            var actual: Array[Dictionary] = index.take_due(tick, phase)
            assert(expected == actual, "due order mismatch tick=%d phase=%d" % [tick, phase])
            if not actual.is_empty():
                actual[0]["payload"]["nested"] = {"corrupted": true}
    assert(queue.pending_count() == 0)
    assert(index.pending_count() == 0)
    print("P2 PERF D due index oracle PASS")
    quit(0)
