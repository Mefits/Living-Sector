extends SceneTree
const Queue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var errors: int = 0
    var q = Queue.new()
    errors += _check(q.schedule("a", 8, 2, "z", "known", {"nested": {"n": 1}}), "schedule a")
    errors += _check(q.schedule("b", 8, 2, "a", "unknown_kind", {}), "unknown kind remains data")
    errors += _check(q.schedule("c", 8, 2, "m", "known", {}), "schedule c")
    errors += _check(q.schedule("future", 9, 2, "f", "known", {}), "schedule future")
    errors += _check(q.cancel("c") and not q.cancel("c"), "cancel and repeat cancel")
    var original: Dictionary = q.snapshot()
    var due: Array[Dictionary] = q.take_due(8, 2)
    errors += _check(due.size() == 2, "multi-event take_due must not access removed _ids")
    if due.size() == 2:
        errors += _check(due[0]["id"] == "b" and due[1]["id"] == "a", "canonical entity ordering")
    errors += _check(q.pending_count() == 1 and q.take_due(8, 2).is_empty(), "no duplicate dispatch")
    errors += _check(q.cancel("future") and q.pending_count() == 0, "positions survive swap removal")
    var restored = Queue.new()
    errors += _check(restored.restore(original, 7, 4), "restore detached queue")
    errors += _check(restored.take_due(8, 2).size() == 2, "restored multi-event dispatch")
    errors += _check(restored.take_due(9, 2).size() == 1, "future boundary preserved")
    errors += _check(not restored.cancel("unknown"), "unknown cancellation")
    print("PERF D event queue removed-index regression: ", "PASS" if errors == 0 else "%d FAILURES" % errors)
    quit(0 if errors == 0 else 1)

func _check(condition: bool, label: String) -> int:
    if not condition:
        push_error("PERF D: " + label)
        return 1
    return 0
