extends RefCounted
## E: opt-in deterministic worker-side tick admission. Not a TickRunner.
## Only the single N158 owner invokes these methods; no SceneTree or World access.
## The owner executes exactly one authoritative tick for each granted admission,
## then calls finish_tick(). Never skip logical ticks to catch up with wall time.
const MAX_ACCUMULATED_SECONDS: float = 60.0
const MAX_FRAME_DELTA: float = 1.0
var _paused: bool = true
var _speed: float = 1.0
var _tick_seconds: float = 1.0
var _credit: float = 0.0
var _steps: int = 0
var _inflight: bool = false
var _frozen: bool = false
var _completed: int = 0

func configure(tick_seconds: float) -> bool:
    if _inflight or not is_finite(tick_seconds) or tick_seconds <= 0.0:
        return false
    _tick_seconds = tick_seconds
    _credit = 0.0
    return true

## A worker must only apply these AFTER the FIFO owner accepts the command.
## Save/load are performed by the authoritative runner, never by this scheduler.
func apply_control(kind: String, payload: Dictionary = {}) -> bool:
    if _frozen or _inflight:
        return false
    match kind:
        "pause":
            if not payload.is_empty():
                return false
            _paused = true
            return true
        "resume":
            if not payload.is_empty():
                return false
            _paused = false
            return true
        "step":
            if not payload.is_empty():
                return false
            _steps += 1
            return true
        "speed":
            if payload.size() != 1 or not payload.has("value"):
                return false
            var value: Variant = payload["value"]
            if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
                return false
            var candidate: float = float(value)
            if not is_finite(candidate) or candidate <= 0.0:
                return false
            _speed = candidate
            return true
    return false

## Feed elapsed real time once, on the worker owner. Clamp invalid/long frames
## to avoid a huge catch-up burst; credit remains bounded, never silently
## consume pending simulation ticks.
func add_elapsed(delta: float) -> bool:
    if _frozen or not is_finite(delta) or delta < 0.0:
        return false
    if not _paused:
        _credit = minf(MAX_ACCUMULATED_SECONDS, _credit + minf(delta, MAX_FRAME_DELTA) * _speed)
    return true

func begin_tick() -> bool:
    if _frozen or _inflight:
        return false
    if _steps > 0:
        _steps -= 1
    elif not _paused and _credit >= _tick_seconds:
        _credit -= _tick_seconds
    else:
        return false
    _inflight = true
    return true

## Call only after N158 successfully committed its World/N9 transaction.
## On failure, freeze without publishing a frame or acknowledging success.
func finish_tick(success: bool) -> bool:
    if not _inflight:
        return false
    _inflight = false
    if not success:
        _frozen = true
        return false
    _completed += 1
    return true

## A successful N38 load resets timing/steps but never changes World itself.
func reset_after_load() -> bool:
    if _inflight or _frozen:
        return false
    _credit = 0.0
    _steps = 0
    return true

func snapshot() -> Dictionary:
    return {
        "paused": _paused, "speed": _speed, "credit": _credit,
        "steps": _steps, "inflight": _inflight, "frozen": _frozen,
        "completed": _completed, "tick_seconds": _tick_seconds
    }
