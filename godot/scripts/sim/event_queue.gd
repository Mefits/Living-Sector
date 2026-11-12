extends RefCounted
## Deterministic data-only scheduler. No Godot Nodes per entity.
## Ordering: due_tick, native phase index, entity_id, insertion sequence.
## No event is allowed to mutate resources merely by being dispatched.

const MAX_EVENTS: int = 100000
const MAX_TICK: int = 9007199254740991
var _pending: Array[Dictionary] = []
var _next_sequence: int = 1
var _ids: Dictionary = {}

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
    _pending.append(event)
    return true

func cancel(event_id: String) -> bool:
    if not _ids.has(event_id):
        return false
    for i in range(_pending.size()):
        if _pending[i]["id"] == event_id:
            _pending.remove_at(i)
            _ids.erase(event_id)
            return true
    return false

func take_due(tick: int, phase: int) -> Array[Dictionary]:
    # Past-due events from a restored snapshot are rejected by restore;
    # the phase boundary only consumes exactly matching events.
    var result: Array[Dictionary] = []
    var remaining: Array[Dictionary] = []
    for event in _pending:
        if int(event["due_tick"]) == tick and int(event["phase"]) == phase:
            result.append(event)
            _ids.erase(event["id"])
        else:
            remaining.append(event)
    _pending = remaining
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
    _pending = staged
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
