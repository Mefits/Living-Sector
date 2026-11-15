extends RefCounted
## E: detached, latest-only committed UI projection mailbox.
## This is NOT World, N9, SaveState or a replacement for N158.
## Only primitive/Array/Dictionary trees may cross the worker/UI boundary.
## The producer must build a small presentation projection after a completed
## authoritative tick; NEVER pass a live World or full N38 checkpoint here.
var _mutex: Mutex = Mutex.new()
var _tick: int = -1
var _epoch: int = 0
var _view: Dictionary = {}

func publish_committed(tick: int, projection: Dictionary) -> bool:
    if tick < 0 or not _detached_data_only(projection):
        return false
    # Duplicate BEFORE locking: producer retains no mutable alias to mailbox.
    var owned: Dictionary = projection.duplicate(true)
    _mutex.lock()
    if tick <= _tick:
        _mutex.unlock()
        return false
    _view = owned
    _tick = tick
    _mutex.unlock()
    return true

## UI receives a deep detached copy, never the mailbox's stored object.
func read_latest() -> Dictionary:
    _mutex.lock()
    var result: Dictionary = {
        "tick": _tick, "epoch": _epoch,
        "ready": _tick >= 0, "view": _view.duplicate(true)}
    _mutex.unlock()
    return result

## Only invoke after an acknowledged load/new seed boundary. A saved game
## may restore to an earlier tick, so reject stale frames from prior epochs.
## The caller must serialize this operation with the worker command FIFO.
func reset_after_load() -> void:
    _mutex.lock()
    _epoch += 1
    _tick = -1
    _view = {}
    _mutex.unlock()

func _detached_data_only(value: Variant) -> bool:
    match typeof(value):
        TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR:
            return true
        TYPE_ARRAY:
            for item in value:
                if not _detached_data_only(item):
                    return false
            return true
        TYPE_DICTIONARY:
            for key in value:
                if not _detached_data_only(key) or not _detached_data_only(value[key]):
                    return false
            return true
        _:
            # Objects, Packed* arrays and resources are deliberately rejected:
            # no implicit reference sharing or hidden live simulation handles.
            return false
