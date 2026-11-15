extends RefCounted
## Experimental strict single-owner N158 worker. The authoritative Runner,
## N39 World, ledger, clock and BT never escape this Thread. No SceneTree,
## CanvasItem, Node or rendering API may be called from the worker.
##
## The GUI owns only a queue of commands and detached, COMPLETED checkpoint
## publications. This is an isolation prototype, not yet enabled in main.gd.
## Do not make it default until GUI adapters and Windows acceptance pass.
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const Frame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _wake: Semaphore = Semaphore.new()
var _live: bool = false
var _pending: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _seed: Dictionary = {}
## The following object is created, read and destroyed ONLY on _thread.
## Never inspect or return it from a GUI/main-thread method.
var _owner_runner: RefCounted = null

func start(seed: Dictionary) -> bool:
    _mutex.lock()
    if _live:
        _mutex.unlock()
        return false
    _seed = seed.duplicate(true)
    _pending.clear()
    _results.clear()
    _live = true
    _mutex.unlock()
    var error: Error = _thread.start(Callable(self, "_thread_main"))
    if error != OK:
        _mutex.lock()
        _live = false
        _mutex.unlock()
        return false
    return true

## A command is ALWAYS detached from its producer. Worker consumes it
## in FIFO order. No GameWorld/Runner method is called on the UI thread.
func submit(command: Dictionary) -> bool:
    if command.is_empty():
        return false
    _mutex.lock()
    var accepted: bool = _live
    if accepted:
        _pending.append(command.duplicate(true))
    _mutex.unlock()
    if accepted:
        _wake.post()
    return accepted

## Caller takes exclusive ownership of completed messages. No mutable
## Worker World, Ledger, clock, BT or SceneTree reference is returned.
func drain_completed() -> Array[Dictionary]:
    _mutex.lock()
    var published: Array[Dictionary] = _results
    _results = []
    _mutex.unlock()
    return published

func shutdown() -> void:
    _mutex.lock()
    var was_live: bool = _live
    if was_live:
        _pending.append({"kind": "stop"})
    _mutex.unlock()
    if was_live:
        _wake.post()
        _thread.wait_to_finish()
    _mutex.lock()
    _live = false
    _mutex.unlock()

func _publish(result: Dictionary) -> void:
    _mutex.lock()
    _results.append(result)
    _mutex.unlock()

func _thread_main() -> void:
    _owner_runner = Runner.new()
    if not _owner_runner.start_from_seed(_seed):
        _publish({"kind": "boot", "ok": false,
            "reason": str(_owner_runner.boot_error())})
        _owner_runner = null
        _mutex.lock()
        _live = false
        _mutex.unlock()
        return
    _publish({"kind": "boot", "ok": true,
        "tick": _owner_runner.tick_count})
    while true:
        _wake.wait()
        _mutex.lock()
        var command: Dictionary = {}
        if not _pending.is_empty():
            command = _pending.pop_front()
        _mutex.unlock()
        if command.is_empty():
            continue
        if str(command.get("kind", "")) == "stop":
            break
        _publish(_execute(command))
    _owner_runner = null
    _mutex.lock()
    _live = false
    _mutex.unlock()

func _execute(command: Dictionary) -> Dictionary:
    var kind: String = str(command.get("kind", ""))
    match kind:
        "control":
            var action: String = str(command.get("action", ""))
            var value: Variant = command.get("value", null)
            var accepted: bool = _owner_runner.queue_control(action, value)
            if accepted:
                _owner_runner.advance_frame(0.0)
            return {"kind": "control", "ok": accepted,
                "tick": _owner_runner.tick_count,
                "paused": _owner_runner.clock.paused,
                "speed": _owner_runner.clock.world_speed,
                "failure": _owner_runner.last_phase_failure()}
        "advance":
            var before: int = _owner_runner.tick_count
            _owner_runner.advance_frame(float(command.get("delta", 0.0)))
            return {"kind": "advance", "ok":
                _owner_runner.last_phase_failure().is_empty(),
                "tick": _owner_runner.tick_count,
                "advanced": _owner_runner.tick_count - before,
                "paused": _owner_runner.clock.paused,
                "failure": _owner_runner.last_phase_failure()}
        "checkpoint":
            # Checkpoint is deliberately detached, made ONLY AFTER a
            # completed tick. Request sparingly: large journal history.
            return {"kind": "checkpoint", "ok": true,
                "tick": _owner_runner.tick_count,
                "snapshot": _owner_runner.checkpoint()}
        "batch":
            return _run_steps(command)
        "save":
            var path: String = str(command.get("path", ""))
            if not path.begins_with("user://") or not (
                    _owner_runner.last_phase_failure().is_empty()):
                return {"kind": "save", "ok": false,
                    "reason": "unsafe_save_or_failed_tick"}
            var saved: Error = Saves.save_runner(_owner_runner, path)
            return {"kind": "save", "ok": saved == OK,
                "tick": _owner_runner.tick_count, "code": saved}
        "load":
            var load_path: String = str(command.get("path", ""))
            if not load_path.begins_with("user://"):
                return {"kind": "load", "ok": false,
                    "reason": "path_not_user_storage"}
            var outcome: Dictionary = Saves.load_runner(
                _owner_runner, _seed, load_path)
            return {"kind": "load",
                "ok": bool(outcome.get("ok", false)),
                "tick": _owner_runner.tick_count,
                "detail": outcome}
        _:
            return {"kind": kind, "ok": false, "reason": "unknown_command"}

## Sequential, deterministic original N1 steps. For test mode only.
## The worker can save N38 at an exact boundary and verify a fresh owner
## before accepting the NEXT command; the GUI never gets an incomplete
## mutable checkpoint. No artificial ship movement or funding.
func _run_steps(command: Dictionary) -> Dictionary:
    var steps: int = int(command.get("steps", 0))
    if steps < 1 or steps > 10000 or not _owner_runner.clock.paused:
        return {"kind": "batch", "ok": false, "reason": "invalid_step_batch"}
    var selected: Array = command.get("checkpoints", [])
    var restart_tick: int = int(command.get("restart_at", -1))
    var save_path: String = str(command.get("save_path",
        "user://tests/astra-thread-owner-n38.json"))
    var checks: Dictionary = {}
    var start: int = Time.get_ticks_msec()
    for i in range(steps):
        if not _owner_runner.queue_control("step", 1):
            return {"kind": "batch", "ok": false,
                "reason": "step_rejected", "tick": _owner_runner.tick_count}
        _owner_runner.advance_frame(0.0)
        var tick: int = _owner_runner.tick_count
        if not _owner_runner.last_phase_failure().is_empty():
            return {"kind": "batch", "ok": false, "tick": tick,
                "failure": _owner_runner.last_phase_failure()}
        if not selected.has(tick) and tick != restart_tick:
            continue
        var snapshot: Dictionary = _owner_runner.checkpoint()
        if selected.has(tick):
            checks[str(tick)] = JSON.stringify(
                snapshot, "", true, true).sha256_text()
        if tick != restart_tick:
            continue
        if not save_path.begins_with("user://") or (
                DirAccess.make_dir_recursive_absolute(
                    ProjectSettings.globalize_path("user://tests")) != OK):
            return {"kind": "batch", "ok": false,
                "reason": "N38_test_path_invalid", "tick": tick}
        if Saves.save_runner(_owner_runner, save_path) != OK:
            return {"kind": "batch", "ok": false,
                "reason": "N38_disk_save_failed", "tick": tick}
        var fresh = Runner.new()
        if not fresh.start_from_seed(_seed):
            return {"kind": "batch", "ok": false,
                "reason": "N38_fresh_boot_failed", "tick": tick}
        var load_result: Dictionary = Saves.load_runner(
            fresh, _seed, save_path)
        if not load_result.get("ok", false) or fresh.tick_count != tick:
            return {"kind": "batch", "ok": false,
                "reason": "N38_disk_restore_failed", "tick": tick}
        var parity: Dictionary = Frame.verify_authoritative_frame(
            snapshot, fresh.checkpoint())
        if not parity.get("ok", false):
            return {"kind": "batch", "ok": false,
                "reason": "N38_worker_checkpoint_diverged",
                "tick": tick, "detail": parity}
        _owner_runner = fresh
    return {"kind": "batch", "ok": true,
        "tick": _owner_runner.tick_count, "checks": checks,
        "elapsed_ms": Time.get_ticks_msec() - start,
        "n38_restart_verified": restart_tick >= 0}
