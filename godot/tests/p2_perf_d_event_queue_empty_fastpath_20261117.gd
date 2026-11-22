extends RefCounted
## Regression for the empty-scheduler dispatch fast path.
const EventQueue = preload("res://scripts/sim/event_queue.gd")

static func run() -> bool:
    var queue = EventQueue.new()
    if not queue.take_due(1, 0).is_empty():
        return false
    if not queue.schedule("a", 2, 0, "station", "unknown", {"nested": {"v": 1}}):
        return false
    if not queue.take_due(1, 0).is_empty():
        return false
    if not queue.cancel("a"):
        return false
    if not queue.take_due(2, 0).is_empty():
        return false
    if not queue.schedule("b", 3, 0, "z", "unknown"):
        return false
    if not queue.schedule("c", 3, 0, "a", "unknown"):
        return false
    var due: Array[Dictionary] = queue.take_due(3, 0)
    if due.size() != 2 or due[0]["id"] != "c" or due[1]["id"] != "b":
        return false
    if not queue.take_due(3, 0).is_empty():
        return false
    var restored = EventQueue.new()
    if not restored.restore(queue.snapshot(), 3, 2):
        return false
    if not restored.take_due(4, 0).is_empty():
        return false
    return restored.pending_count() == 0
