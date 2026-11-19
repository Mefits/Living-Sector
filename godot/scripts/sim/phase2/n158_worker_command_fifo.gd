extends RefCounted
## E: bounded command transport, NOT an executor or second TickRunner.
## The UI enqueues; the single simulation owner calls take_next() and applies
## commands at authoritative tick boundaries. No SceneTree access in this class.
const MAX_PENDING: int = 256
const ALLOWED: Array[String] = ["pause", "resume", "step", "speed", "save", "load"]
var _mutex: Mutex = Mutex.new()
var _pending: Array[Dictionary] = []
var _next_id: int = 1
var _last_taken_id: int = 0
var _last_ack_id: int = 0
var _acks: Dictionary = {}

## Return a monotonically increasing ticket, or -1 for invalid/full requests.
## Payloads must be detached scalar data; save/load use a String slot token,
## not an arbitrary object, file handle, World or callable.
func enqueue(kind: String, payload: Dictionary = {}) -> int:
    if not ALLOWED.has(kind) or not _valid_payload(kind, payload):
        return -1
    var owned: Dictionary = payload.duplicate(true)
    _mutex.lock()
    if _pending.size() >= MAX_PENDING:
        _mutex.unlock()
        return -1
    var ticket: int = _next_id
    _next_id += 1
    _pending.append({"id": ticket, "kind": kind, "payload": owned})
    _mutex.unlock()
    return ticket

## Called ONLY by the one N158 owner, never by the UI. Empty => {}.
func take_next() -> Dictionary:
    _mutex.lock()
    var item: Dictionary = {}
    if not _pending.is_empty():
        item = _pending.pop_front()
        _last_taken_id = int(item["id"])
    _mutex.unlock()
    return item.duplicate(true)

## Owner reports actual completion/failure only AFTER command application.
## Acknowledgement does not execute commands and does not imply save success.
func acknowledge(ticket: int, success: bool, message: String = "") -> bool:
    _mutex.lock()
    if ticket <= _last_ack_id or ticket > _last_taken_id:
        _mutex.unlock()
        return false
    # FIFO owner must acknowledge each taken command in order.
    if ticket != _last_ack_id + 1:
        _mutex.unlock()
        return false
    _last_ack_id = ticket
    _acks[ticket] = {"success": success, "message": message}
    _mutex.unlock()
    return true

## UI polling is detached and does not mutate the owner's acknowledgement.
func read_ack(ticket: int) -> Dictionary:
    _mutex.lock()
    var result: Dictionary = _acks.get(ticket, {}).duplicate(true)
    _mutex.unlock()
    return result

func pending_count() -> int:
    _mutex.lock()
    var count: int = _pending.size()
    _mutex.unlock()
    return count

func _valid_payload(kind: String, payload: Dictionary) -> bool:
    match kind:
        "pause", "resume", "step":
            return payload.is_empty()
        "speed":
            return payload.size() == 1 and payload.has("value") and (
                typeof(payload["value"]) == TYPE_INT or typeof(payload["value"]) == TYPE_FLOAT
            ) and is_finite(float(payload["value"])) and float(payload["value"]) > 0.0
        "save", "load":
            return payload.size() == 1 and payload.has("slot") and (
                typeof(payload["slot"]) == TYPE_STRING
            ) and _valid_slot(String(payload["slot"]))
    return false

## Save/load tokens are opaque identifiers, never paths or URLs. Reject
## separators, traversal, whitespace and control characters at the UI edge.
func _valid_slot(slot: String) -> bool:
    if slot.is_empty() or slot.length() > 128:
        return false
    for index in range(slot.length()):
        var code: int = slot.unicode_at(index)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90)
                or (code >= 97 and code <= 122) or code == 45 or code == 95):
            return false
    return true
