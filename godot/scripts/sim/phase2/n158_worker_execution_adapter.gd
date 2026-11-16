extends RefCounted
## E: opt-in owner-side execution adapter. It never constructs a World or Runner.
## The caller supplies authoritative N158 tick and detached projection callbacks.
## No callback may touch SceneTree when invoked from a worker thread.
const CONTROL = preload("res://scripts/sim/phase2/n158_worker_control_coordinator.gd")
var _control = CONTROL.new()
var _owner_busy: bool = false

func ui_enqueue(kind: String, payload: Dictionary = {}) -> int:
    return _control.ui_enqueue(kind, payload)

func ui_read_frame() -> Dictionary:
    return _control.ui_read_frame()

func ui_read_ack(ticket: int) -> Dictionary:
    return _control.ui_read_ack(ticket)

func ui_status() -> Dictionary:
    return _control.ui_status()

func owner_configure(tick_seconds: float) -> bool:
    return _control.owner_configure(tick_seconds)

## tick_executor: () -> Dictionary {success: bool, tick: int}
## projection_executor: (tick: int) -> Dictionary of detached presentation data
## persistence_executor: (kind: String, slot: String) -> bool
## All callbacks run synchronously on the SAME owner thread.
## Drain the FIFO BEFORE admitting a tick. Save/load therefore execute only
## at a completed tick boundary, never during an N39 transaction.
func owner_pump(delta: float, tick_executor: Callable, projection_executor: Callable, persistence_executor: Callable = Callable()) -> Dictionary:
    if _owner_busy:
        return {"success": false, "error": "reentrant_owner"}
    if not tick_executor.is_valid() or not projection_executor.is_valid():
        return {"success": false, "error": "missing_executor"}
    _owner_busy = true
    var commands: int = 0
    while commands < 256:
        var item: Dictionary = _control.owner_drain_one(persistence_executor)
        if item.is_empty():
            break
        commands += 1
        if not bool(item.get("success", false)) and bool(_control.ui_status().get("failed", false)):
            _owner_busy = false
            return {"success": false, "error": "command_bridge_frozen", "commands": commands}
    if not _control.owner_add_elapsed(delta):
        _owner_busy = false
        return {"success": false, "error": "elapsed_rejected", "commands": commands}
    if not _control.owner_begin_tick():
        _owner_busy = false
        return {"success": true, "advanced": false, "commands": commands}
    var outcome: Variant = tick_executor.call()
    var valid: bool = typeof(outcome) == TYPE_DICTIONARY and typeof(outcome.get("success")) == TYPE_BOOL and bool(outcome["success"]) and typeof(outcome.get("tick")) == TYPE_INT and int(outcome["tick"]) >= 0
    if not valid:
        _control.owner_finish_tick(false)
        _owner_busy = false
        return {"success": false, "error": "authoritative_tick_failed", "commands": commands}
    var tick: int = int(outcome["tick"])
    if not _control.owner_finish_tick(true):
        _control.owner_freeze("tick_finish_failed")
        _owner_busy = false
        return {"success": false, "error": "tick_finish_failed", "commands": commands}
    var projection: Variant = projection_executor.call(tick)
    if typeof(projection) != TYPE_DICTIONARY or not _control.owner_publish_committed(tick, projection):
        _control.owner_freeze("committed_projection_failed")
        _owner_busy = false
        return {"success": false, "error": "committed_projection_failed", "commands": commands}
    _owner_busy = false
    return {"success": true, "advanced": true, "tick": tick, "commands": commands}
