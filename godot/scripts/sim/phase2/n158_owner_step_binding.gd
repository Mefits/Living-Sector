extends RefCounted
## PERF E experimental N158 binding for controlled single-step parity tests.
## This is NOT a worker and does not create or own a second World/TickRunner.
## The caller owns the authoritative runner and must call only at a safe
## completed-tick boundary on its designated owner thread.
## Do not enable in main.gd until N38/BT/RNG parity is established.

var _runner: RefCounted
var _busy: bool = false

func bind_authoritative(runner: RefCounted) -> bool:
    if _busy or runner == null:
        return false
    if not runner.has_method("queue_control") or not runner.has_method("advance_frame"):
        return false
    if not runner.has_method("is_started") or not runner.has_method("last_phase_failure"):
        return false
    if not runner.is_started() or not String(runner.last_phase_failure()).is_empty():
        return false
    if runner.clock == null:
        return false
    _runner = runner
    return true

## Returns an execution callback for n158_worker_execution_adapter.
## This deliberate single-step probe requires a PAUSED N158. It never
## advances on wall time and never changes speed/balance/AI budget.
func tick_executor() -> Dictionary:
    if _busy or _runner == null:
        return {"success": false, "error": "unbound_or_reentrant"}
    if not _runner.is_started() or not String(_runner.last_phase_failure()).is_empty():
        return {"success": false, "error": "runner_not_healthy"}
    if _runner.clock == null or not bool(_runner.clock.paused):
        return {"success": false, "error": "requires_paused_runner"}
    _busy = true
    var before: int = int(_runner.tick_count)
    if not _runner.queue_control("step", 1):
        _busy = false
        return {"success": false, "error": "step_command_rejected"}
    _runner.advance_frame(0.0)
    var after: int = int(_runner.tick_count)
    var healthy: bool = String(_runner.last_phase_failure()).is_empty()
    _busy = false
    if not healthy or after != before + 1:
        return {"success": false, "error": "tick_not_exactly_once", "before": before, "after": after}
    return {"success": true, "tick": after}

## Only scalar presentation data crosses the UI boundary. No World, clock,
## ledger, ship, RefCounted or mutable model object is exposed.
func projection_executor(tick: int) -> Dictionary:
    if _busy or _runner == null or _runner.clock == null:
        return {}
    if not _runner.is_started() or not String(_runner.last_phase_failure()).is_empty():
        return {}
    if tick != int(_runner.tick_count):
        return {}
    return {
        "tick": tick,
        "paused": bool(_runner.clock.paused),
        "speed": float(_runner.clock.world_speed)
    }
