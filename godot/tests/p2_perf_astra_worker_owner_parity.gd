extends SceneTree
## A deterministic single-owner worker smoke (16) or full parity test (420).
## This is NOT a Windows FPS benchmark and does NOT enable the GUI worker.
## Godot console:
## --headless --path . --script res://tests/p2_perf_astra_worker_owner_parity.gd -- --ticks=16
## --headless --path . --script res://tests/p2_perf_astra_worker_owner_parity.gd -- --ticks=420
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const Frame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const Worker = preload("res://scripts/sim/phase2/n158_threaded_runner_owner.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var ticks: int = 16
    for arg in OS.get_cmdline_user_args():
        if arg == "--ticks=420":
            ticks = 420
        elif arg != "--ticks=16":
            _fail("unknown flag " + str(arg))
            return
    OS.set_environment("LS_PROFILE_NATIVE_PHASES", "0")
    OS.set_environment("LS_PERF_N39_FORCE_LEGACY_STAGES", "0")
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("original Rust seed missing")
        return
    var marks: Array[int] = [1, 8, 16] if ticks == 16 else [
        1, 60, 120, 240, 360, 361, 420]
    var original: Dictionary = _sequential(seed, ticks, marks)
    if not original.get("ok", false):
        _fail("main-thread baseline failed " + str(original))
        return
    var worker = Worker.new()
    if not worker.start(seed):
        _fail("Thread.start failed")
        return
    var ready: bool = false
    var start_ms: int = Time.get_ticks_msec()
    while Time.get_ticks_msec() - start_ms < 30000 and not ready:
        for outcome in worker.drain_completed():
            if outcome.get("kind") == "boot":
                if not outcome.get("ok", false):
                    _fail("worker boot failed " + str(outcome))
                    worker.shutdown()
                    return
                ready = true
        if not ready:
            await process_frame
    if not ready:
        _fail("worker boot timed out")
        worker.shutdown()
        return
    if not worker.submit({"kind": "control", "action": "pause"}) or not (
            worker.submit({"kind": "control", "action": "speed", "value": 8.0})):
        _fail("worker control queue refused")
        worker.shutdown()
        return
    if not worker.submit({"kind": "batch", "steps": ticks,
            "checkpoints": marks,
            "restart_at": 360 if ticks == 420 else -1,
            "save_path": "user://tests/astra-worker-parity-n38.json"}):
        _fail("worker batch queue refused")
        worker.shutdown()
        return
    var frames: int = 0
    var widest_ui_frame_ms: int = 0
    var last_frame_ms: int = Time.get_ticks_msec()
    var finished: Dictionary = {}
    while Time.get_ticks_msec() - start_ms < 300000:
        for message in worker.drain_completed():
            if message.get("kind") == "batch":
                finished = message
        if not finished.is_empty():
            break
        await process_frame
        frames += 1
        var now: int = Time.get_ticks_msec()
        widest_ui_frame_ms = maxi(widest_ui_frame_ms, now - last_frame_ms)
        last_frame_ms = now
    worker.shutdown()
    if not finished.get("ok", false):
        _fail("worker failed or timed out " + str(finished))
        return
    if finished["checks"] != original["checks"]:
        _fail("N158 World/N9/clock/N38 checks diverged: " +
            str(finished["checks"]) + " vs " + str(original["checks"]))
        return
    if ticks == 420 and not finished.get("n38_restart_verified", false):
        _fail("worker N38 restart missing")
        return
    if frames < 2:
        _fail("worker blocked GUI SceneTree frames (frames=" +
            str(frames) + ")")
        return
    print("P2_PERF_ASTRA_WORKER_OWNER_PARITY_PASS ticks=" + str(ticks) +
        " checks=" + str(marks) +
        " main_frame_callbacks_while_worker_busy=" + str(frames) +
        " longest_headless_callback_gap_ms=" + str(widest_ui_frame_ms) +
        " baseline_wall_ms=" + str(original["elapsed_ms"]) +
        " worker_wall_ms=" + str(finished.get("elapsed_ms", -1)) +
        " no_windows_fps_claim=true")
    quit(0)

func _sequential(seed: Dictionary, ticks: int, marks: Array[int]) -> Dictionary:
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        return {"ok": false, "reason": "baseline boot"}
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        return {"ok": false, "reason": "baseline clock"}
    sim.advance_frame(0.0)
    var checks: Dictionary = {}
    var start_ms: int = Time.get_ticks_msec()
    for tick in range(1, ticks + 1):
        if not sim.queue_control("step", 1):
            return {"ok": false, "reason": "baseline step " + str(tick)}
        sim.advance_frame(0.0)
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            return {"ok": false, "reason": "baseline tick " + str(tick)}
        if not marks.has(tick):
            continue
        var snap: Dictionary = sim.checkpoint()
        checks[str(tick)] = JSON.stringify(snap, "", true, true).sha256_text()
        if tick != 360:
            continue
        if DirAccess.make_dir_recursive_absolute(
                ProjectSettings.globalize_path("user://tests")) != OK:
            return {"ok": false, "reason": "checkpoint dir"}
        var path: String = "user://tests/astra-main-baseline-n38.json"
        if Saves.save_runner(sim, path) != OK:
            return {"ok": false, "reason": "baseline N38 disk save"}
        var fresh = Runner.new()
        if not fresh.start_from_seed(seed):
            return {"ok": false, "reason": "baseline N38 fresh boot"}
        var loaded: Dictionary = Saves.load_runner(fresh, seed, path)
        if not loaded.get("ok", false):
            return {"ok": false, "reason": "baseline N38 load"}
        var proof: Dictionary = Frame.verify_authoritative_frame(
            snap, fresh.checkpoint())
        if not proof.get("ok", false):
            return {"ok": false, "reason": "baseline N38 proof"}
        sim = fresh
    return {"ok": true, "checks": checks,
        "elapsed_ms": Time.get_ticks_msec() - start_ms}

func _fail(reason: String) -> void:
    push_error("P2_PERF_ASTRA_WORKER_OWNER_PARITY_FAIL: " + reason)
    quit(1)
