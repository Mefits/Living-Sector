extends RefCounted
## Opt-in due-event index. Not wired into the authoritative EventQueue.
## Keys are exact (tick, phase); ordering is delegated to the same comparator.
## Values are detached copies, so callers cannot mutate the index via aliases.

const MAX_EVENTS: int = 100000
const MAX_TICK: int = 9007199254740991

var _buckets: Dictionary = {}
var _event_keys: Dictionary = {}
var _sequences: Dictionary = {} # sequence -> event id, unique across pending records
var _positions: Dictionary = {} # event id -> position in its bucket
var _count: int = 0

func rebuild(events: Array) -> bool:
    var buckets: Dictionary = {}
    var keys: Dictionary = {}
    var positions: Dictionary = {}
    var sequences: Dictionary = {}
    if events.size() > MAX_EVENTS:
        return false
    for value in events:
        if not (value is Dictionary):
            return false
        var event: Dictionary = value
        if not _valid(event):
            return false
        var id: String = event["id"]
        if keys.has(id) or sequences.has(event["sequence"]):
            return false
        sequences[event["sequence"]] = true
        var key: String = _key(int(event["due_tick"]), int(event["phase"]))
        if not buckets.has(key):
            buckets[key] = []
        var bucket: Array = buckets[key]
        positions[id] = bucket.size()
        bucket.append(event.duplicate(true))
        keys[id] = key
    _buckets = buckets
    _event_keys = keys
    _sequences = sequences
    _positions = positions
    _count = events.size()
    return true

func add(event: Dictionary) -> bool:
    if not _valid(event):
        return false
    var id: String = event["id"]
    if _event_keys.has(id) or _sequences.has(event["sequence"]) or _count >= MAX_EVENTS:
        return false
    var key: String = _key(int(event["due_tick"]), int(event["phase"]))
    if not _buckets.has(key):
        _buckets[key] = []
    var bucket: Array = _buckets[key]
    _positions[id] = bucket.size()
    bucket.append(event.duplicate(true))
    _event_keys[id] = key
    _sequences[event["sequence"]] = id
    _count += 1
    return true

func remove(event_id: String) -> bool:
    if not _event_keys.has(event_id):
        return false
    var key: String = _event_keys[event_id]
    var bucket: Array = _buckets[key]
    # Swap-with-last is safe: take_due sorts by the original stable comparator.
    # Avoid a linear scan and Array.remove_at shifts on each cancellation.
    var index: int = int(_positions[event_id])
    var removed_sequence: int = int(bucket[index]["sequence"])
    var last: int = bucket.size() - 1
    if index != last:
        var moved: Dictionary = bucket[last]
        bucket[index] = moved
        _positions[moved["id"]] = index
    bucket.pop_back()
    if bucket.is_empty():
        _buckets.erase(key)
    _sequences.erase(removed_sequence)
    _positions.erase(event_id)
    _event_keys.erase(event_id)
    _count -= 1
    return true

func take_due(tick: int, phase: int) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var key: String = _key(tick, phase)
    if not _buckets.has(key):
        return result
    var bucket: Array = _buckets[key]
    for item in bucket:
        var event: Dictionary = item
        result.append(event.duplicate(true))
        _event_keys.erase(event["id"])
        _sequences.erase(event["sequence"])
        _positions.erase(event["id"])
    _count -= bucket.size()
    _buckets.erase(key)
    result.sort_custom(Callable(self, "_less"))
    return result

func pending_count() -> int:
    return _count

func _key(tick: int, phase: int) -> String:
    return str(tick) + ":" + str(phase)

func _valid(event: Dictionary) -> bool:
    for key in ["id", "due_tick", "phase", "entity_id", "sequence", "kind", "payload"]:
        if not event.has(key):
            return false
    return event["id"] is String and not event["id"].is_empty() \
        and event["due_tick"] is int and event["due_tick"] >= 1 and event["due_tick"] <= MAX_TICK \
        and event["phase"] is int and event["phase"] >= 0 and event["phase"] <= 255 \
        and event["entity_id"] is String and not event["entity_id"].is_empty() \
        and event["sequence"] is int and event["sequence"] >= 1 and event["sequence"] < MAX_TICK \
        and event["kind"] is String and not event["kind"].is_empty() \
        and event["payload"] is Dictionary

func _less(a: Dictionary, b: Dictionary) -> bool:
    for key in ["due_tick", "phase"]:
        if int(a[key]) != int(b[key]):
            return int(a[key]) < int(b[key])
    if str(a["entity_id"]) != str(b["entity_id"]):
        return str(a["entity_id"]) < str(b["entity_id"])
    return int(a["sequence"]) < int(b["sequence"])
