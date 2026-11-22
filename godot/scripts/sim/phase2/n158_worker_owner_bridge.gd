extends RefCounted
## E: isolated single-owner command/frame boundary. No thread is started here.
## The future N158 worker alone calls owner_*; UI only calls ui_*.
## No World, SceneTree, N9 or N38 objects cross this boundary.
const FIFO = preload("res://scripts/sim/phase2/n158_worker_command_fifo.gd")
const FRAME = preload("res://scripts/sim/phase2/n158_committed_frame_view.gd")

var _commands = FIFO.new()
var _frames = FRAME.new()
var _mutex: Mutex = Mutex.new()
var _inflight: int = 0
var _load_pending: bool = false
var _last_committed_tick: int = -1
var _failed: bool = false
var _failure: String = ""

func ui_enqueue(kind: String, payload: Dictionary = {}) -> int:
    _mutex.lock()
    var blocked: bool = _failed
    _mutex.unlock()
    if blocked:
        return -1
    return _commands.enqueue(kind, payload)

func ui_read_ack(ticket: int) -> Dictionary:
    return _commands.read_ack(ticket)

func ui_read_frame() -> Dictionary:
    return _frames.read_latest()

func ui_status() -> Dictionary:
    _mutex.lock()
    var result: Dictionary = {
        "inflight": _inflight, "load_pending": _load_pending,
        "last_committed_tick": _last_committed_tick,
        "failed": _failed, "failure": _failure}
    _mutex.unlock()
    result["pending"] = _commands.pending_count()
    return result

## One owner may take one command at a time. Never process the next command
## before reporting the previous command's real execution result.
func owner_take_command() -> Dictionary:
    _mutex.lock()
    if _inflight != 0 or _failed:
        _mutex.unlock()
        return {}
    var item: Dictionary = _commands.take_next()
    if not item.is_empty():
        _inflight = int(item["id"])
        _load_pending = String(item["kind"]) == "load"
    _mutex.unlock()
    return item

## Called only after authoritative application succeeds/fails at a safe boundary.
## Failed load preserves the prior frame; successful load invalidates the epoch.
func owner_finish_command(ticket: int, success: bool, message: String = "") -> bool:
    _mutex.lock()
    if ticket <= 0 or ticket != _inflight:
        _mutex.unlock()
        return false
    if _load_pending and success:
        _frames.reset_after_load()
        _last_committed_tick = -1
    var accepted: bool = _commands.acknowledge(ticket, success, message)
    if accepted:
        _inflight = 0
        _load_pending = false
    _mutex.unlock()
    return accepted

## Publish only AFTER the authoritative tick transaction fully commits.
## This method never advances simulation, computes a tick or reads World.
func owner_publish_committed(tick: int, projection: Dictionary) -> bool:
    _mutex.lock()
    if _failed or _load_pending or _inflight != 0 or tick <= _last_committed_tick:
        _mutex.unlock()
        return false
    var accepted: bool = _frames.publish_committed(tick, projection)
    if accepted:
        _last_committed_tick = tick
    _mutex.unlock()
    return accepted

## Fatal worker failure freezes presentation and future command acceptance.
## The last valid frame remains available for diagnostics, not as live state.
func owner_freeze(reason: String) -> void:
    _mutex.lock()
    _failed = true
    _failure = reason
    _mutex.unlock()
