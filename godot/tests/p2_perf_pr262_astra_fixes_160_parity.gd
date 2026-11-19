extends SceneTree
## Bounded live same-seed A/B on the two Astra code packages.
## This is an early-tick parity gate, NOT proof of late-tick speed or FPS.
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const END_TICK: int = 160
const SAMPLES: Array[int] = [1, 32, 64, 120, 160]
const LIMIT_MSEC: int = 125000
const LEGACY_FLAGS: Array[String] = [
    "LS_RUNTIME_FULL_WORLD_READS",
    "LS_LATE_CONTRACT_LEGACY",
    "LS_LATE_FUNDING_LEGACY"
]

func _initialize() -> void:
    var old_env: Dictionary = {}
    for flag in LEGACY_FLAGS:
        old_env[flag] = OS.get_environment(flag)
    var prior: Dictionary = _run_mode(true)
    var candidate: Dictionary = _run_mode(false)
    for flag in LEGACY_FLAGS:
        OS.set_environment(flag, str(old_env[flag]))
    if not prior.get("ok", false) or not candidate.get("ok", false):
        _fail("mode failed legacy=" + str(prior) + " optimized=" + str(candidate))
        return
    for tick in SAMPLES:
        var key: String = str(tick)
        if prior["digests"].get(key, "") != candidate["digests"].get(key, ""):
            _fail("authoritative checkpoint divergence at tick=" + key +
                " legacy=" + str(prior["digests"].get(key)) +
                " candidate=" + str(candidate["digests"].get(key)))
            return
    print("P2_ASTRA_TWO_FIXES_160_PARITY_PASS ", JSON.stringify({
        "ticks": END_TICK, "checkpoints": SAMPLES,
        "seed": "native_current_world", "exact_digests": true,
        "legacy_elapsed_s": prior["elapsed_s"],
        "optimized_elapsed_s": candidate["elapsed_s"]
    }))
    quit(0)

func _run_mode(legacy: bool) -> Dictionary:
    for flag in LEGACY_FLAGS:
        OS.set_environment(flag, "1" if legacy else "0")
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        return {"ok": false, "reason": "no_seed"}
    var sim = Runtime.new()
    if not sim.start_from_seed(seed):
        return {"ok": false, "reason": "boot:" + str(sim.boot_error())}
    if not sim.queue_control("pause") or not sim.queue_control("speed", 16.0):
        return {"ok": false, "reason": "controls"}
    sim.advance_frame(0.0)
    if sim.tick_count != 0:
        return {"ok": false, "reason": "initial_tick"}
    var started: int = Time.get_ticks_msec()
    var digests: Dictionary = {}
    for expected in range(1, END_TICK + 1):
        if Time.get_ticks_msec() - started > LIMIT_MSEC:
            return {"ok": false, "reason": "timeout", "tick": sim.tick_count}
        if not sim.queue_control("step", 1):
            return {"ok": false, "reason": "queue_step", "tick": expected}
        sim.advance_frame(0.0)
        if sim.tick_count != expected or not sim.last_phase_failure().is_empty():
            return {"ok": false, "reason": "native_tick_failure", "tick": expected,
                "details": sim.last_phase_failure()}
        if SAMPLES.has(expected):
            var world: Dictionary = sim.checkpoint()
            if world.is_empty():
                return {"ok": false, "reason": "empty_checkpoint", "tick": expected}
            digests[str(expected)] = JSON.stringify(world, "", true, true).sha256_text()
    return {"ok": true, "digests": digests, "elapsed_s":
        snappedf(float(Time.get_ticks_msec() - started) / 1000.0, 0.01)}

func _fail(reason: String) -> void:
    push_error("P2_ASTRA_TWO_FIXES_160_PARITY_FAIL " + reason)
    quit(1)
