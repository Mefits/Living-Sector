extends RefCounted
## E / N158: real opt-in owner THREAD for the existing authoritative runner.
## The runner and SaveState live ONLY on the worker. This is a parity harness
## boundary; main.gd may opt in, but the default stays synchronous until
## verified. Only detached scalars, checkpoints and bounded view data cross.
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const RequestMetrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const SizeProbe = preload("res://scripts/sim/phase2/n158_authoritative_size_probe.gd")

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
            "save", "load", "restore", "frame"]:
        return -1
    if not _safe_payload(payload):
        return -1
    if kind == "step" and (typeof(payload.get("count")) != TYPE_INT or
            int(payload["count"]) < 1 or int(payload["count"]) > 64):
        return -1
    if kind == "speed" and (typeof(payload.get("value")) not in [TYPE_FLOAT, TYPE_INT] or
            not is_finite(float(payload["value"])) or float(payload["value"]) <= 0.0 or
            float(payload["value"]) > 16.0):
        return -1
    if kind == "frame":
        if typeof(payload.get("delta")) not in [TYPE_FLOAT, TYPE_INT] or (
                not is_finite(float(payload["delta"])) or
                float(payload["delta"]) < 0.0 or float(payload["delta"]) > 0.25):
            return -1
        for flag in ["view", "observer"]:
            if payload.has(flag) and typeof(payload[flag]) != TYPE_BOOL:
                return -1
    if kind in ["save", "load"]:
        if typeof(payload.get("path")) != TYPE_STRING:
            return -1
        var path: String = String(payload["path"])
        if (not path.begins_with("user://tests/") and
                not path.begins_with("user://saves/")) or (
                path.contains("..") or path.contains("\\\\") or path.length() > 240):
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
    # E: exactly the last 100 single-paid-tick request timings, detached scalars.
    # Multi-tick requests invalidate coverage; never divide their elapsed time.
    var paid_tick_timings: Array[Dictionary] = []
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
        var began_usec: int = Time.get_ticks_usec()
        var before_tick: int = sim.tick_count
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
            "frame":
                # The sole authoritative N158 advances off the SceneTree thread.
                # GUI submits at most one frame command at a time; no catch-up
                # bursts or artificial logical ticks are introduced here.
                sim.advance_frame(float(payload["delta"]))
                answer["ok"] = true
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
        var advance_end_usec: int = Time.get_ticks_usec()
        # Legacy sim_usec excludes FrameView construction, but also includes
        # command handling; do not present it as thread CPU or per-tick cost.
        answer["sim_usec"] = maxi(0, advance_end_usec - began_usec)
        answer["advanced"] = sim.tick_count != before_tick
        if answer["ok"] and kind in ["frame", "step", "load", "restore"] and (
                kind != "frame" or answer["advanced"] or
                bool(payload.get("view", false)) or
                bool(payload.get("observer", false))):
            # Read only after the full phase/transaction commit. The UI never
            # touches sim, sim.world, production or live Ledger directly.
            answer["calendar_text"] = sim.calendar.display_text(sim.tick_count)
            answer["angles"] = sim.world.orbital_snapshot()
            if kind in ["load", "restore", "step"] or (kind == "frame" and (
                    bool(payload.get("view", false)) or
                    bool(payload.get("observer", false)))):
                var economy: Dictionary = sim.economy_snapshot()
                answer["economy"] = economy
                answer["summary"] = sim.economy_summary(economy)
                if kind in ["load", "restore"] or bool(payload.get("observer", false)):
                    answer["native"] = sim.checkpoint().get(
                        "native_production", {})
        # Four bounded measurements, only after a successfully paid source tick.
        # Reuse the detached economy projection when it already exists.
        # This snapshot is diagnostic and cannot change authoritative state.
        if answer["ok"] and sim.tick_count > before_tick and (
                SizeProbe.CHECKPOINTS.has(sim.tick_count)):
            var size_start_usec: int = Time.get_ticks_usec()
            var size_world: Dictionary = answer.get("economy", {})
            if size_world.is_empty():
                size_world = sim.economy_snapshot()
            answer["size_probe"] = SizeProbe.measure(sim.tick_count, size_world)
            answer["size_probe_wall_usec"] = Time.get_ticks_usec() - size_start_usec
            # Existing opt-in native profiler; detached bounded scalars only.
            answer["ship_subphase_profile"] = RequestMetrics.checkpoint_ship_subphases(
                sim.tick_count, sim.profile_native_ship_subphases())
        var projection_end_usec: int = Time.get_ticks_usec()
        answer["timing"] = RequestMetrics.summarize(before_tick, sim.tick_count,
            began_usec, advance_end_usec, projection_end_usec)
        # Only completed, successful, single-paid-tick requests are attributable.
        # The window includes FrameView/projection elapsed separately; not CPU.
        if answer["ok"] and int(answer["timing"].get("paid_ticks", 0)) == 1:
            var sample: Dictionary = answer["timing"].duplicate(true)
            sample["after_tick"] = sim.tick_count
            paid_tick_timings.append(sample)
            if paid_tick_timings.size() > 100:
                paid_tick_timings.pop_front()
            if RequestMetrics.CHECKPOINTS.has(sim.tick_count):
                answer["paid_tick_window"] = RequestMetrics.bounded_paid_tick_window(
                    paid_tick_timings, sim.tick_count)
        elif sim.tick_count > before_tick or kind in ["restore", "load"]:
            # Gaps and state rewinds cannot be stitched into a valid 100-tick run.
            paid_tick_timings.clear()
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
