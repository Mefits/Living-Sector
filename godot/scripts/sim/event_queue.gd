extends RefCounted
## Deterministic data-only scheduler. No Godot Nodes per entity.
## Ordering: due_tick, native phase index, entity_id, insertion sequence.
## No event is allowed to mutate resources merely by being dispatched.

const MAX_EVENTS: int = 100000
const MAX_TICK: int = 9007199254740991
var _pending: Array[Dictionary] = []
var _next_sequence: int = 1
var _ids: Dictionary = {}
# Position map for O(1) cancellation; _pending remains the sole event store.
var _positions: Dictionary = {}
# Counts only: authoritative event records remain in _pending.
# A missing boundary avoids scanning all future events.
var _due_counts: Dictionary = {}
# Boundary -> event ids; cancellation remains O(1) via _positions.
# This index is rebuilt atomically on restore and is not serialized.
var _due_ids: Dictionary = {}

func _due_key(tick: int, phase: int) -> String:
    return str(tick) + ":" + str(phase)

func _count_due(tick: int, phase: int, delta: int) -> void:
    var key: String = _due_key(tick, phase)
    var count: int = int(_due_counts.get(key, 0)) + delta
    if count <= 0:
        _due_counts.erase(key)
    else:
        _due_counts[key] = count

func schedule(event_id: String, due_tick: int, phase: int, entity_id: String, kind: String, payload: Dictionary = {}) -> bool:
    if event_id.is_empty() or entity_id.is_empty() or kind.is_empty():
        return false
    if due_tick < 1 or due_tick > MAX_TICK or phase < 0 or phase > 255:
        return false
    if _ids.has(event_id) or _pending.size() >= MAX_EVENTS or _next_sequence >= MAX_TICK:
        return false
    var event: Dictionary = {
        "id": event_id, "due_tick": due_tick, "phase": phase,
        "entity_id": entity_id, "sequence": _next_sequence,
        "kind": kind, "payload": payload.duplicate(true)
    }
    _next_sequence += 1
    _ids[event_id] = true
    _positions[event_id] = _pending.size()
    _pending.append(event)
    _count_due(due_tick, phase, 1)
    var boundary: String = _due_key(due_tick, phase)
    if not _due_ids.has(boundary):
        _due_ids[boundary] = {}
    _due_ids[boundary][event_id] = true
    return true

func cancel(event_id: String) -> bool:
    if not _ids.has(event_id):
        return false
    # Swapping with the last record avoids shifting every later event.
    # Dispatch and snapshot both sort by the canonical comparator, not array position.
    var index: int = int(_positions[event_id])
    var removed: Dictionary = _pending[index]
    var boundary: String = _due_key(int(removed["due_tick"]), int(removed["phase"]))
    _count_due(int(removed["due_tick"]), int(removed["phase"]), -1)
    if _due_ids.has(boundary):
        _due_ids[boundary].erase(event_id)
        if _due_ids[boundary].is_empty():
            _due_ids.erase(boundary)
    var last: int = _pending.size() - 1
    if index != last:
        var moved: Dictionary = _pending[last]
        _pending[index] = moved
        _positions[str(moved["id"])] = index
    _pending.pop_back()
    _positions.erase(event_id)
    _ids.erase(event_id)
    return true

func take_due(tick: int, phase: int) -> Array[Dictionary]:
    # Only visit events in this boundary; canonical sorting is independent
    # of the swap-removal storage order.
    var boundary: String = _due_key(tick, phase)
    if not _due_ids.has(boundary):
        return []
    var ids: Array = _due_ids[boundary].keys()
    var result: Array[Dictionary] = []
    for event_id in ids:
        if not _positions.has(event_id):
            continue
        var event: Dictionary = _pending[int(_positions[event_id])]
        result.append(event)
        cancel(str(event_id))
    result.sort_custom(Callable(self, "_less"))
    return result.duplicate(true)

func pending_count() -> int:
    return _pending.size()

func snapshot() -> Dictionary:
    var ordered: Array[Dictionary] = _pending.duplicate(true)
    ordered.sort_custom(Callable(self, "_less"))
    return {"next_sequence": _next_sequence, "pending": ordered}

func restore(data: Dictionary, committed_tick: int, phase_count: int) -> bool:
    var next: Variant = data.get("next_sequence", null)
    var records: Variant = data.get("pending", null)
    if not _whole(next, 1) or not (records is Array) or records.size() > MAX_EVENTS:
        return false
    var staged: Array[Dictionary] = []
    var seen_ids: Dictionary = {}
    var seen_sequences: Dictionary = {}
    for item in records:
        if not (item is Dictionary):
            return false
        var id: Variant = item.get("id")
        var entity: Variant = item.get("entity_id")
        var kind: Variant = item.get("kind")
        var due: Variant = item.get("due_tick")
        var phase: Variant = item.get("phase")
        var seq: Variant = item.get("sequence")
        var payload: Variant = item.get("payload")
        if not (id is String) or id.is_empty() or not (entity is String) or entity.is_empty():
            return false
        if not (kind is String) or kind.is_empty() or not (payload is Dictionary):
            return false
        if not _whole(due, committed_tick + 1) or not _whole(phase, 0) or int(phase) >= phase_count:
            return false
        if not _whole(seq, 1) or int(seq) >= int(next):
            return false
        if seen_ids.has(id) or seen_sequences.has(int(seq)):
            return false
        seen_ids[id] = true
        seen_sequences[int(seq)] = true
        staged.append({"id": id, "due_tick": int(due), "phase": int(phase),
            "entity_id": entity, "sequence": int(seq), "kind": kind,
            "payload": payload.duplicate(true)})
    var staged_counts: Dictionary = {}
    var staged_due_ids: Dictionary = {}
    for event in staged:
        var key: String = _due_key(int(event["due_tick"]), int(event["phase"]))
        staged_counts[key] = int(staged_counts.get(key, 0)) + 1
        if not staged_due_ids.has(key):
            staged_due_ids[key] = {}
        staged_due_ids[key][str(event["id"])] = true
    var staged_positions: Dictionary = {}
    for i in range(staged.size()):
        staged_positions[str(staged[i]["id"])] = i
    _pending = staged
    _positions = staged_positions
    _due_counts = staged_counts
    _due_ids = staged_due_ids
    _ids = seen_ids
    _next_sequence = int(next)
    return true

func _less(a: Dictionary, b: Dictionary) -> bool:
    for key in ["due_tick", "phase"]:
        if int(a[key]) != int(b[key]):
            return int(a[key]) < int(b[key])
    if str(a["entity_id"]) != str(b["entity_id"]):
        return str(a["entity_id"]) < str(b["entity_id"])
    return int(a["sequence"]) < int(b["sequence"])

func _whole(v: Variant, minimum: int) -> bool:
    if not (v is int or v is float) or not is_finite(float(v)):
        return false
    return float(v) >= float(minimum) and float(v) <= float(MAX_TICK) and float(int(v)) == float(v)
