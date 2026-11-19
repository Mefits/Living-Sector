extends SceneTree
const Queue = preload("res://scripts/sim/event_queue.gd")
const Index = preload("res://scripts/sim/event_due_index_experimental.gd")

func _initialize() -> void:
    var source = Queue.new()
    var index = Index.new()
    for i in range(320):
        var due: int = 1 + (i * 17) % 23
        var phase: int = (i * 7) % 5
        var entity: String = "entity_%03d" % ((i * 13) % 29)
        assert(source.schedule("event_%d" % i, due, phase, entity, "test", {"nested": [i]}))
    for i in range(0, 320, 9):
        assert(source.cancel("event_%d" % i))
    var snap: Dictionary = source.snapshot()
    assert(index.rebuild(snap))
    assert(index.pending_count() == source.pending_count())
    # Invalid rebuild is atomic and leaves all buckets untouched.
    assert(not index.rebuild({"pending": [{"id": "bad"}]}))
    assert(index.pending_count() == source.pending_count())
    snap["pending"][0]["payload"]["nested"][0] = -100
    for tick in range(1, 24):
        for phase in range(5):
            var expected: Array[Dictionary] = source.take_due(tick, phase)
            var actual: Array[Dictionary] = index.take_due(tick, phase)
            assert(expected == actual)
            if not actual.is_empty():
                actual[0]["payload"]["nested"][0] = -200
            assert(index.take_due(tick, phase).is_empty())
    assert(source.pending_count() == 0)
    assert(index.pending_count() == 0)
    # Large 64-bit due_tick must not collide with low 32-bit boundaries.
    assert(source.schedule("far", 4294967297, 1, "z", "test"))
    assert(source.schedule("near", 1, 1, "a", "test"))
    assert(index.rebuild(source.snapshot()))
    assert(index.take_due(1, 1) == source.take_due(1, 1))
    assert(index.take_due(4294967297, 1) == source.take_due(4294967297, 1))
    print("PASS p2_perf_d_due_index_oracle")
    quit()
