extends RefCounted
## E / N158: real opt-in owner THREAD for the existing authoritative runner.
## The runner and SaveState live ONLY on the worker. This is a parity harness
## boundary, not a UI backend: main.gd still uses its original synchronous N158.
## UI may only exchange detached scalar commands and completed snapshots.
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _wake: Semaphore = Semaphore.new()
var _commands: Array[Dictionary] = []
var _answers: Array[Dictionary] = []
var _launched: bool = false
var _stopping: bool = false
var _next_ticket: int = 1

## There is exactly one live Runner, constructed inside the owning thread.
## Never create an additional World, N9 ledger, clock or economy simulation.
func launch(source_seed: Dictionary) -> bool:
    if _launched or source_seed.is_empty():
        return false
    var seed: Dictionary = source_seed.duplicate(true)
    _launched = true
    var result: Error = _thread.start(Callable(self, "_owner_loop").bind(seed))
    if result != OK:
        _launched = false
        return false
    return true

## A returned ticket is NOT an acknowledgement. Poll until its actual result.
## Do not hand live SceneTree objects, Runner or World into this API.
func submit(kind: String, payload: Dictionary = {}) -> int:
    if kind not in ["pause", "resume", "speed", "step", "checkpoint",
            "save", "load", "restore"]:
        return -1
    if not _safe_payload(payload):
        return -1
    if kind == "step" and (typeof(payload.get("count")) != TYPE_INT or
            int(payload["count"]) < 1 or int(payload["count"]) > 64):
        return -1
    if kind == "speed" and (typeof(payload.get("value")) not in [TYPE_FLOAT, TYPE_INT] or
            not is_finite(float(payload["value"])) or float(payload["value"]) <= 0.0):
        return -1
    if kind in ["save", "load"] and (typeof(payload.get("path")) != TYPE_STRING or
            not String(payload["path"]).begins_with("user://tests/")):
        return -1
    if kind == "restore" and not (payload.get("checkpoint") is Dictionary):
        return -1
    _mutex.lock()
    if not _launched or _stopping or _commands.size() >= 256:
        _mutex.unlock()
        return -1
    var ticket: int = _next_ticket
    _next_ticket += 1
    _commands.append({"ticket": ticket, "kind": kind,
        "payload": payload.duplicate(true)})
    _mutex.unlock()
    _wake.post()
    return ticket

func poll_answer() -> Dictionary:
    _mutex.lock()
    var result: Dictionary = {}
    if not _answers.is_empty():
        result = _answers.pop_front().duplicate(true)
    _mutex.unlock()
    return result

## Must be invoked on teardown AFTER callers stop submitting commands.
## Joining can block if the owner is mid-tick; never call from _process().
func close() -> void:
    _mutex.lock()
    var running: bool = _launched
    _stopping = true
    _mutex.unlock()
    if running:
        _wake.post()
        _thread.wait_to_finish()
    _mutex.lock()
    _launched = false
    _mutex.unlock()

func _owner_loop(seed: Dictionary) -> void:
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _publish({"ticket": 0, "kind": "boot", "ok": false,
            "error": sim.boot_error()})
        return
    _publish({"ticket": 0, "kind": "boot", "ok": true,
        "tick": sim.tick_count, "ships": sim.fleet_snapshot().size()})
    var frozen: bool = false
    while true:
        _wake.wait()
        _mutex.lock()
        var stop: bool = _stopping
        var command: Dictionary = {}
        if not stop and not _commands.is_empty():
            command = _commands.pop_front()
        _mutex.unlock()
        if stop:
            break
        if command.is_empty():
            continue
        var ticket: int = int(command["ticket"])
        var kind: String = str(command["kind"])
        if frozen:
            _publish({"ticket": ticket, "kind": kind, "ok": false,
                "error": "authoritative_owner_frozen"})
            continue
        var payload: Dictionary = command["payload"]
        var answer: Dictionary = {"ticket": ticket, "kind": kind, "ok": false}
        match kind:
            "pause", "resume":
                answer["ok"] = sim.queue_control(kind)
                if answer["ok"]:
                    sim.advance_frame(0.0)
            "speed":
                answer["ok"] = sim.queue_control("speed", float(payload["value"]))
                if answer["ok"]:
                    sim.advance_frame(0.0)
            "step":
                answer["ok"] = sim.queue_control("step", int(payload["count"]))
                if answer["ok"]:
                    sim.advance_frame(0.0)
            "checkpoint":
                answer["checkpoint"] = sim.checkpoint()
                answer["ok"] = true
            "restore":
                # A failed authoritative restore MUST freeze this owner.
                answer["ok"] = sim.restore_checkpoint(payload["checkpoint"], seed)
                if not answer["ok"]:
                    answer["error"] = "checkpoint_restore_rejected"
                    frozen = true
            "save":
                answer["ok"] = Saves.save_runner(sim, str(payload["path"])) == OK
                if not answer["ok"]:
                    answer["error"] = "n38_save_failed"
            "load":
                var outcome: Dictionary = Saves.load_runner(sim, seed, str(payload["path"]))
                answer["ok"] = bool(outcome.get("ok", false))
                if not answer["ok"]:
                    answer["error"] = str(outcome.get("error", "n38_load_failed"))
                    # A failed load may not be safe to continue without a
                    # verified rollback; forbid further economy mutations.
                    frozen = true
        var phase_failure: Dictionary = sim.last_phase_failure()
        if not phase_failure.is_empty():
            answer["ok"] = false
            answer["error"] = "native_phase_failure"
            answer["phase_failure"] = phase_failure.duplicate(true)
            frozen = true
        answer["tick"] = sim.tick_count
        answer["paused"] = sim.clock.paused
        answer["speed"] = sim.clock.world_speed
        _publish(answer)
    # sim is released on this same owner thread. No live reference escapes.

func _publish(answer: Dictionary) -> void:
    var detached: Dictionary = answer.duplicate(true)
    _mutex.lock()
    _answers.append(detached)
    _mutex.unlock()

## Commands may contain JSON/N38 trees, but no live objects or callables.
## Count and depth guards keep malicious/cyclic input from recursive scans.
func _safe_payload(value: Variant, depth: int = 0) -> bool:
    if depth > 48:
        return false
    match typeof(value):
        TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return true
        TYPE_ARRAY:
            if value.size() > 200000:
                return false
            for item in value:
                if not _safe_payload(item, depth + 1):
                    return false
            return true
        TYPE_DICTIONARY:
            if value.size() > 200000:
                return false
            for key in value:
                if not _safe_payload(key, depth + 1) or (
                        not _safe_payload(value[key], depth + 1)):
                    return false
            return true
        _:
            return false
