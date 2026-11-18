extends RefCounted
## Deterministic data-only scheduler. No Godot Nodes per entity.
## Ordering: due_tick, native phase index, entity_id, insertion sequence.
## No event is allowed to mutate resources merely by being dispatched.

const MAX_EVENTS: int = 100000
const MAX_TICK: int = 9007199254740991
var _pending: Array[Dictionary] = []
var _next_sequence: int = 1
# Position map for O(1) cancellation; _pending remains the sole event store.
var _positions: Dictionary = {}
# Integer due_tick -> phase -> event ids. No string boundary allocations in
# paid phase polling. The index is derived; _pending remains authoritative.
# Rebuilt atomically on restore, never serialized.
var _due_ids: Dictionary = {}

func _add_due(event_id: String, due_tick: int, phase: int) -> void:
    if not _due_ids.has(due_tick):
        _due_ids[due_tick] = {}
    var phases: Dictionary = _due_ids[due_tick]
    if not phases.has(phase):
        phases[phase] = {}
    phases[phase][event_id] = true

func _remove_due(event_id: String, due_tick: int, phase: int) -> void:
    if not _due_ids.has(due_tick):
        return
    var phases: Dictionary = _due_ids[due_tick]
    if not phases.has(phase):
        return
    var bucket: Dictionary = phases[phase]
    bucket.erase(event_id)
    if bucket.is_empty():
        phases.erase(phase)
        if phases.is_empty():
            _due_ids.erase(due_tick)

func schedule(event_id: String, due_tick: int, phase: int, entity_id: String, kind: String, payload: Dictionary = {}) -> bool:
    if event_id.is_empty() or entity_id.is_empty() or kind.is_empty():
        return false
    if due_tick < 1 or due_tick > MAX_TICK or phase < 0 or phase > 255:
        return false
    if _positions.has(event_id) or _pending.size() >= MAX_EVENTS or _next_sequence >= MAX_TICK:
        return false
    var event: Dictionary = {
        "id": event_id, "due_tick": due_tick, "phase": phase,
        "entity_id": entity_id, "sequence": _next_sequence,
        "kind": kind, "payload": payload.duplicate(true)
    }
    _next_sequence += 1
    _positions[event_id] = _pending.size()
    _pending.append(event)
    _add_due(event_id, due_tick, phase)
    return true

func cancel(event_id: String) -> bool:
    if not _positions.has(event_id):
        return false
    # Swapping with the last record avoids shifting every later event.
    # Dispatch and snapshot both sort by the canonical comparator, not array position.
    var index: int = int(_positions[event_id])
    var removed: Dictionary = _pending[index]
    _remove_due(event_id, int(removed["due_tick"]), int(removed["phase"]))
    var last: int = _pending.size() - 1
    if index != last:
        var moved: Dictionary = _pending[last]
        _pending[index] = moved
        _positions[str(moved["id"])] = index
    _pending.pop_back()
    _positions.erase(event_id)
    return true

func take_due(tick: int, phase: int) -> Array[Dictionary]:
    # O(1) numeric lookup on the paid phase path, including idle ticks.
    if not _due_ids.has(tick):
        return []
    var phases: Dictionary = _due_ids[tick]
    if not phases.has(phase):
        return []
    var ids: Array = phases[phase].keys()
    var result: Array[Dictionary] = []
    # Consume this entire boundary in one pass. Calling cancel() per item
    # repeatedly rebuilds boundary strings and mutates the same due bucket.
    # The pending array remains the only authoritative event store.
    for event_id in ids:
        if not _positions.has(event_id):
            continue
        var index: int = int(_positions[event_id])
        result.append(_pending[index])
        var last: int = _pending.size() - 1
        if index != last:
            var moved: Dictionary = _pending[last]
            _pending[index] = moved
            _positions[str(moved["id"])] = index
        _pending.pop_back()
        _positions.erase(event_id)
    phases.erase(phase)
    if phases.is_empty():
        _due_ids.erase(tick)
    if result.size() > 1:
        result.sort_custom(Callable(self, "_less"))
    # All returned records were removed from the sole authoritative store.
    # Their payloads were detached on schedule()/restore(), so another deep
    # copy here only scales with the number/size of dispatched events.
    return result

func pending_count() -> int:
    return _pending.size()

func snapshot() -> Dictionary:
    # Sort borrowed records before copying payloads. The comparator only reads
    # immutable scalar ordering fields; copying the whole growing payload
    # tree before sorting wastes allocation and cache bandwidth.
    var sorted_refs: Array[Dictionary] = _pending.duplicate(false)
    sorted_refs.sort_custom(Callable(self, "_less"))
    # Detach after sorting, before exposing any record to the caller.
    return {"next_sequence": _next_sequence, "pending": sorted_refs.duplicate(true)}

func restore(data: Dictionary, committed_tick: int, phase_count: int) -> bool:
    var next: Variant = data.get("next_sequence", null)
    var records: Variant = data.get("pending", null)
    if not _whole(next, 1) or not (records is Array) or records.size() > MAX_EVENTS:
        return false
    var staged: Array[Dictionary] = []
    var seen_ids: Dictionary = {}
    var seen_sequences: Dictionary = {}
    # Build all derived indexes alongside validated, owned records.
    # A failed restore never publishes any of these staged structures.
    var staged_due_ids: Dictionary = {}
    var staged_positions: Dictionary = {}
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
        staged_positions[id] = staged.size()
        staged.append({"id": id, "due_tick": int(due), "phase": int(phase),
            "entity_id": entity, "sequence": int(seq), "kind": kind,
            "payload": payload.duplicate(true)})
        var due_tick: int = int(due)
        var event_phase: int = int(phase)
        if not staged_due_ids.has(due_tick):
            staged_due_ids[due_tick] = {}
        var phases: Dictionary = staged_due_ids[due_tick]
        if not phases.has(event_phase):
            phases[event_phase] = {}
        phases[event_phase][id] = true
    _pending = staged
    _positions = staged_positions
    _due_ids = staged_due_ids
    _next_sequence = int(next)
    return true

func _less(a: Dictionary, b: Dictionary) -> bool:
    # Hot comparator for dispatch and snapshots: avoid constructing an
    # Array of field names and repeated conversions for each comparison.
    var a_tick: int = int(a["due_tick"])
    var b_tick: int = int(b["due_tick"])
    if a_tick != b_tick:
        return a_tick < b_tick
    var a_phase: int = int(a["phase"])
    var b_phase: int = int(b["phase"])
    if a_phase != b_phase:
        return a_phase < b_phase
    var a_entity: String = str(a["entity_id"])
    var b_entity: String = str(b["entity_id"])
    if a_entity != b_entity:
        return a_entity < b_entity
    return int(a["sequence"]) < int(b["sequence"])

func _whole(v: Variant, minimum: int) -> bool:
    if not (v is int or v is float) or not is_finite(float(v)):
        return false
    return float(v) >= float(minimum) and float(v) <= float(MAX_TICK) and float(int(v)) == float(v)
