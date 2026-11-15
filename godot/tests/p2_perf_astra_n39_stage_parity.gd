extends SceneTree
## Same-build A/B: legacy full-world stages vs owned N39 operating-domain stages
## and true no-op N91/N143 bypass. No synthetic ship, money or planner changes.
## Exact canonical checkpoint hashes; N38 disk restart at tick 360.
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const Frame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")

const CHECKS: Array[int] = [1, 60, 120, 240, 360, 361, 420]

func _initialize() -> void:
    OS.set_environment("LS_PROFILE_NATIVE_PHASES", "0")
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("source seed missing")
        return
    var base: Dictionary = _run(seed, true)
    if not base.get("ok", false):
        _fail("legacy arm " + str(base))
        return
    var optimized: Dictionary = _run(seed, false)
    if not optimized.get("ok", false):
        _fail("owned arm " + str(optimized))
        return
    if base["checks"] != optimized["checks"]:
        _fail("source N9/N38 state diverged: " + str(base["checks"]) +
            " vs " + str(optimized["checks"]))
        return
    # A detached owned-domain stage must never leak write access to N39.
    OS.set_environment("LS_PERF_N39_FORCE_LEGACY_STAGES", "0")
    var live = Runner.new()
    if not live.start_from_seed(seed):
        _fail("isolation fixture failed to boot")
        return
    var before: Dictionary = live.production.world_snapshot()
    var staged: Dictionary = live.production._copy_owned_world(
        "alias_negative_test", ["facilities", "markets", "populations"])
    for domain in ["facilities", "markets", "populations"]:
        var ids: Array = staged[domain].keys()
        if ids.is_empty():
            _fail("missing owned domain " + domain)
            return
        # Mutate the caller's separate nested owned object only.
        staged[domain][ids[0]]["__untrusted_alias_probe"] = true
    if live.production.world_snapshot() != before:
        _fail("owned staged domain escaped into authoritative World")
        return
    print("P2_PERF_ASTRA_N39_STAGE_PARITY_PASS checkpoints=" + str(CHECKS) +
        " legacy_ms=" + str(base["elapsed_ms"]) +
        " optimized_ms=" + str(optimized["elapsed_ms"]) +
        " owned_alias_isolation=true")
    quit(0)

func _run(seed: Dictionary, legacy: bool) -> Dictionary:
    OS.set_environment("LS_PERF_N39_FORCE_LEGACY_STAGES",
        "1" if legacy else "0")
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        return {"ok": false, "error": "N158 boot"}
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        return {"ok": false, "error": "clock setup"}
    sim.advance_frame(0.0)
    var begin_ms: int = Time.get_ticks_msec()
    var checks: Dictionary = {}
    for tick in range(1, 421):
        if not sim.queue_control("step", 1):
            return {"ok": false, "error": "N1 step " + str(tick)}
        sim.advance_frame(0.0)
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            return {"ok": false, "error": "phase " + str(tick) +
                " " + str(sim.last_phase_failure())}
        if not CHECKS.has(tick):
            continue
        var snap: Dictionary = sim.checkpoint()
        checks[str(tick)] = JSON.stringify(snap, "", true, true).sha256_text()
        if tick != 360:
            continue
        var path: String = "user://tests/astra-n39-" + (
            "legacy" if legacy else "optimized") + ".json"
        if DirAccess.make_dir_recursive_absolute(
                ProjectSettings.globalize_path("user://tests")) != OK:
            return {"ok": false, "error": "save dir"}
        if Saves.save_runner(sim, path) != OK:
            return {"ok": false, "error": "N38 save"}
        var next = Runner.new()
        if not next.start_from_seed(seed):
            return {"ok": false, "error": "N38 boot"}
        var load: Dictionary = Saves.load_runner(next, seed, path)
        if not load.get("ok", false):
            return {"ok": false, "error": "N38 reload " + str(load)}
        var proof: Dictionary = Frame.verify_authoritative_frame(
            snap, next.checkpoint())
        if not proof.get("ok", false):
            return {"ok": false, "error": "N38 parity " + str(proof)}
        sim = next
    return {"ok": true, "checks": checks,
        "elapsed_ms": Time.get_ticks_msec() - begin_ms}

func _fail(reason: String) -> void:
    push_error("P2_PERF_ASTRA_N39_STAGE_PARITY_FAIL: " + reason)
    quit(1)
