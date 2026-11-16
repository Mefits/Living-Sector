extends RefCounted
## Experimental detached due-index for a validated EventQueue snapshot.
## Not wired into live N158. Rebuild after any schedule/cancel/restore mutation.
## The authoritative EventQueue remains the source of truth.
var _by_boundary: Dictionary = {}
var _count: int = 0

func rebuild(snapshot: Dictionary) -> bool:
    var records: Variant = snapshot.get("pending", null)
    if not (records is Array) or records.size() > 100000:
        return false
    var staged: Dictionary = {}
    var seen: Dictionary = {}
    for item in records:
        if not (item is Dictionary):
            return false
        for field in ["id", "entity_id", "kind", "due_tick", "phase", "sequence", "payload"]:
            if not item.has(field):
                return false
        if not (item["id"] is String) or str(item["id"]).is_empty() or seen.has(item["id"]):
            return false
        if not (item["entity_id"] is String) or str(item["entity_id"]).is_empty() or not (item["kind"] is String) or str(item["kind"]).is_empty():
            return false
        if not (item["payload"] is Dictionary):
            return false
        if not (item["due_tick"] is int) or not (item["phase"] is int) or not (item["sequence"] is int):
            return false
        var due: int = item["due_tick"]
        var phase: int = item["phase"]
        if due < 1 or due > 9007199254740991 or phase < 0 or phase > 255 or int(item["sequence"]) < 1:
            return false
        seen[item["id"]] = true
        # Nested integer keys preserve full 64-bit due ticks.
        if not staged.has(due):
            staged[due] = {}
        var phases: Dictionary = staged[due]
        if not phases.has(phase):
            phases[phase] = []
        var bucket: Array = phases[phase]
        bucket.append(item.duplicate(true))
    for due in staged:
        var phases: Dictionary = staged[due]
        for phase in phases:
            var bucket: Array = phases[phase]
            bucket.sort_custom(Callable(self, "_less"))
    _by_boundary = staged
    _count = records.size()
    return true

func take_due(tick: int, phase: int) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if not _by_boundary.has(tick):
        return result
    var phases: Dictionary = _by_boundary[tick]
    if not phases.has(phase):
        return result
    for event in phases[phase]:
        result.append(event.duplicate(true))
    _count -= result.size()
    phases.erase(phase)
    if phases.is_empty():
        _by_boundary.erase(tick)
    return result

func pending_count() -> int:
    return _count

func _less(a: Dictionary, b: Dictionary) -> bool:
    if str(a["entity_id"]) != str(b["entity_id"]):
        return str(a["entity_id"]) < str(b["entity_id"])
    return int(a["sequence"]) < int(b["sequence"])
