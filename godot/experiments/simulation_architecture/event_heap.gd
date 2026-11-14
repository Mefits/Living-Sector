extends RefCounted
## Deterministic min-heap: time, phase, entity, sequence.
## Phase 0 = arrive, 1 = depart, 2 = production.
var _heap: Array[Dictionary] = []
var _sequence: int = 0
var peak: int = 0

func empty() -> bool:
    return _heap.is_empty()

func due_time() -> int:
    return 9223372036854775807 if _heap.is_empty() else int(_heap[0]["tick"])

func push(tick: int, phase: int, entity: int) -> void:
    var event: Dictionary = {
        "tick": tick, "phase": phase, "entity": entity, "seq": _sequence
    }
    _sequence += 1
    _heap.append(event)
    var index: int = _heap.size() - 1
    while index > 0:
        var parent: int = int(floor(float(index - 1) / 2.0))
        if not _before(_heap[index], _heap[parent]):
            break
        var temporary: Dictionary = _heap[parent]
        _heap[parent] = _heap[index]
        _heap[index] = temporary
        index = parent
    peak = maxi(peak, _heap.size())

func pop() -> Dictionary:
    if _heap.is_empty():
        return {}
    var first: Dictionary = _heap[0]
    var tail: Dictionary = _heap.pop_back()
    if _heap.is_empty():
        return first
    _heap[0] = tail
    var index: int = 0
    while true:
        var left: int = index * 2 + 1
        if left >= _heap.size():
            break
        var right: int = left + 1
        var child: int = left
        if right < _heap.size() and _before(_heap[right], _heap[left]):
            child = right
        if not _before(_heap[child], _heap[index]):
            break
        var temporary: Dictionary = _heap[index]
        _heap[index] = _heap[child]
        _heap[child] = temporary
        index = child
    return first

func _before(a: Dictionary, b: Dictionary) -> bool:
    for key in ["tick", "phase", "entity", "seq"]:
        var av: int = int(a[key])
        var bv: int = int(b[key])
        if av != bv:
            return av < bv
    return false
