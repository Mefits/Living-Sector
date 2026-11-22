extends SceneTree
## Oracle for repeated event snapshots and all mutation/invalidation paths.
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var q = Queue.new()
    var oracle: Dictionary = {}
    for i in range(96):
        var id: String = "e%03d" % i
        var due: int = 1 + (i % 7)
        var phase: int = i % 3
        var entity: String = "unit%02d" % (95 - i)
        var payload: Dictionary = {"nested": {"value": i}}
        assert(q.schedule(id, due, phase, entity, "test", payload))
        oracle[id] = {"id": id, "due_tick": due, "phase": phase,
            "entity_id": entity, "sequence": i + 1, "kind": "test",
            "payload": payload.duplicate(true)}
        payload["nested"]["value"] = -1
    _check(q, oracle, 97)
    # Repeated snapshots must not share nested payloads with queue or each other.
    var first: Dictionary = q.snapshot()
    first["pending"][0]["payload"]["nested"]["value"] = -999
    first["pending"].clear()
    _check(q, oracle, 97)
    # Cancel after sorted cache was populated, including swap-remove.
    for id in ["e000", "e047", "e095"]:
        assert(q.cancel(id))
        oracle.erase(id)
        _check(q, oracle, 97)
    assert(not q.cancel("e000"))
    # A new row must invalidate the cached sorted order and sequence.
    assert(q.schedule("late", 1, 0, "unit00", "test",
        {"nested": {"value": 123}}))
    oracle["late"] = {"id": "late", "due_tick": 1, "phase": 0,
        "entity_id": "unit00", "sequence": 97, "kind": "test",
        "payload": {"nested": {"value": 123}}}
    _check(q, oracle, 98)
    # Dispatch must remove only the exact boundary, preserve tie-breaks,
    # and invalidate snapshot order without leaking mutable queue payload.
    var expected_due: Array = []
    for row in oracle.values():
        if row["due_tick"] == 1 and row["phase"] == 0:
            expected_due.append(row)
    expected_due.sort_custom(_less)
    var due: Array[Dictionary] = q.take_due(1, 0)
    assert(due == expected_due)
    for row in expected_due:
        oracle.erase(row["id"])
    if not due.is_empty():
        due[0]["payload"]["nested"]["value"] = -777
    _check(q, oracle, 98)
    assert(q.take_due(1, 0).is_empty())
    # Failed restore must leave all indexes, sequences and cache intact.
    var before: Dictionary = q.snapshot()
    var invalid: Dictionary = before.duplicate(true)
    invalid["pending"].append(invalid["pending"][0].duplicate(true))
    assert(not q.restore(invalid, 0, 3))
    assert(q.snapshot() == before)
    # Successful restore replaces all borrowed rows and rebuilds both indexes.
    var restored = Queue.new()
    assert(restored.restore(before, 0, 3))
    assert(restored.snapshot() == before)
    var detached: Dictionary = before.duplicate(true)
    if not detached["pending"].is_empty():
        detached["pending"][0]["payload"]["nested"]["value"] = -1234
    assert(restored.snapshot() == q.snapshot())
    for tick in range(1, 8):
        for phase in range(3):
            var expected: Array = []
            for row in oracle.values():
                if row["due_tick"] == tick and row["phase"] == phase:
                    expected.append(row)
            expected.sort_custom(_less)
            assert(restored.take_due(tick, phase) == expected)
            for row in expected:
                oracle.erase(row["id"])
            _check(restored, oracle, 98)
    assert(restored.pending_count() == 0)
    print("PASS p2_perf_d_event_snapshot_reuse")
    quit(0)

func _check(q, oracle: Dictionary, next_sequence: int) -> void:
    var expected: Array = oracle.values()
    expected.sort_custom(_less)
    var snapshot: Dictionary = q.snapshot()
    assert(snapshot["next_sequence"] == next_sequence)
    assert(snapshot["pending"] == expected)
    assert(q.pending_count() == expected.size())
    assert(q.snapshot() == snapshot)

func _less(a: Dictionary, b: Dictionary) -> bool:
    if a["due_tick"] != b["due_tick"]:
        return a["due_tick"] < b["due_tick"]
    if a["phase"] != b["phase"]:
        return a["phase"] < b["phase"]
    if a["entity_id"] != b["entity_id"]:
        return a["entity_id"] < b["entity_id"]
    return a["sequence"] < b["sequence"]
