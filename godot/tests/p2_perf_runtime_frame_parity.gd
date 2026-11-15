extends SceneTree
## Same-build A/B proof for S5 frame reuse ONLY. All other S3 owned
## projections are identical in both arms. Runs the real original
## N158/N39 economy with a strict N38 disk restart at tick360.
## No CI triggering, no artificial ships or manual contracts.
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const Frame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const CHECKS: Array[int] = [1, 60, 120, 240, 360, 361, 420]

func _initialize() -> void:
    OS.set_environment("LS_PROFILE_NATIVE_PHASES", "0")
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("original seed missing: " + str(seed))
        return
    var savedir: String = ProjectSettings.globalize_path("user://tests")
    if DirAccess.make_dir_recursive_absolute(savedir) != OK:
        _fail("cannot prepare profile save directory")
        return
    var baseline: Dictionary = _run(seed, true)
    if not baseline.get("ok", false):
        _fail("legacy faction-frame arm failed: " + str(baseline))
        return
    var candidate: Dictionary = _run(seed, false)
    if not candidate.get("ok", false):
        _fail("optimized faction-frame arm failed: " + str(candidate))
        return
    if baseline["checkpoints"] != candidate["checkpoints"]:
        _fail("N158/N39 N9/N38 checkpoints diverged, baseline=" +
            str(baseline["checkpoints"]) + " optimized=" +
            str(candidate["checkpoints"]))
        return
    print("P2_PERF_RUNTIME_FACTION_FRAME_PARITY_PASS checkpoints=" +
        str(CHECKS) + " original_elapsed_ms=" +
        str(baseline["elapsed_ms"]) + " optimized_elapsed_ms=" +
        str(candidate["elapsed_ms"]) +
        " no_claim_of_full_game_speedup=true")
    quit(0)

func _run(seed: Dictionary, original_frame: bool) -> Dictionary:
    OS.set_environment("LS_PERF_NO_FACTION_FRAME_REUSE",
        "1" if original_frame else "0")
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        return {"ok": false, "reason": "source boot rejected"}
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        return {"ok": false, "reason": "N1 control rejected"}
    sim.advance_frame(0.0)
    if not sim.clock.paused or sim.clock.tick_multiplier() != 1:
        return {"ok": false, "reason": "native clock mismatch"}
    var started: int = Time.get_ticks_msec()
    var checkpoints: Dictionary = {}
    for tick in range(1, 421):
        if not sim.queue_control("step", 1):
            return {"ok": false, "reason": "step rejected at " + str(tick)}
        sim.advance_frame(0.0)
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            return {"ok": false, "reason": "native tick rejected at " +
                str(tick) + " failure=" + str(sim.last_phase_failure())}
        if not CHECKS.has(tick):
            continue
        var snap: Dictionary = sim.checkpoint()
        if snap.is_empty() or not snap.has("native_production"):
            return {"ok": false, "reason": "N38 missing at tick=" + str(tick)}
        checkpoints[str(tick)] = JSON.stringify(snap, "", true, true).sha256_text()
        if tick != 360:
            continue
        var path: String = "user://tests/perf-runtime-frame-" + (
            "original" if original_frame else "optimized") + ".json"
        if Saves.save_runner(sim, path) != OK:
            return {"ok": false, "reason": "N38 disk save rejected"}
        var fresh = Runner.new()
        if not fresh.start_from_seed(seed):
            return {"ok": false, "reason": "N38 fresh original boot rejected"}
        var disk: Dictionary = Saves.load_runner(fresh, seed, path)
        if not disk.get("ok", false) or fresh.tick_count != 360:
            return {"ok": false, "reason": "N38 disk reload rejected " + str(disk)}
        var verified: Dictionary = Frame.verify_authoritative_frame(
            snap, fresh.checkpoint())
        if not verified.get("ok", false):
            return {"ok": false, "reason": "N38 frame changed " + str(verified)}
        sim = fresh
    return {"ok": true, "checkpoints": checkpoints,
        "elapsed_ms": Time.get_ticks_msec() - started}

func _fail(message: String) -> void:
    push_error("P2_PERF_RUNTIME_FACTION_FRAME_PARITY_FAIL: " + message)
    quit(1)
