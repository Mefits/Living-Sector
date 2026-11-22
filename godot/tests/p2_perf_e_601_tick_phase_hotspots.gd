extends SceneTree
## Read-only bounded native simulation profile. This is a short true paid
## clean-seed run to tick601 (no fabricated flights or infinite 10k CI).
## It measures headless CPU TPS, NOT Windows F5 FPS or render stalls.
const NativeData = preload("res://scripts/native_data.gd")
const TimedN158 = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const MAX_WALL_MSEC: int = 540000
const LAST_WINDOW: int = 100

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen clean seed unavailable")
        return
    var sim = TimedN158.new()
    if not sim.start_from_seed(seed):
        _fail("frozen seed rejected: " + sim.boot_error())
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("cannot establish source x8 step cadence")
        return
    sim.advance_frame(0.0)
    var run_started: int = Time.get_ticks_msec()
    var window_usec: Array[int] = []
    var all_usec: int = 0
    for tick in range(1, 602):
        if Time.get_ticks_msec() - run_started >= MAX_WALL_MSEC:
            _fail("bounded run timeout at completed tick " + str(sim.tick_count))
            return
        if not sim.queue_control("step", 1):
            _fail("source step admission rejected at tick " + str(tick))
            return
        var began: int = Time.get_ticks_usec()
        sim.advance_frame(0.0)
        var elapsed: int = maxi(0, Time.get_ticks_usec() - began)
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            _fail("source tick failed at " + str(tick)
                + ": " + JSON.stringify(sim.last_phase_failure()))
            return
        all_usec += elapsed
        window_usec.append(elapsed)
        if window_usec.size() > LAST_WINDOW:
            window_usec.pop_front()
        if tick in [100, 300, 420, 500, 600, 601]:
            var last: Array[int] = window_usec.duplicate()
            last.sort()
            var p95_us: int = last[clampi(
                ceili(float(last.size()) * 0.95) - 1, 0, last.size() - 1)]
            var total_window_us: int = 0
            for sample in last:
                total_window_us += sample
            var profile: Dictionary = sim.production.native_schema_profile()
            print("P2_PERF_E_PHASE_TICK ", JSON.stringify({
                "tick": tick, "speed": sim.clock.world_speed,
                "window_ticks": last.size(),
                "window_average_ms": snappedf(float(total_window_us) /
                    float(last.size()) / 1000.0, 0.01),
                "window_p95_ms": snappedf(float(p95_us) / 1000.0, 0.01),
                "cumulative_wall_s": snappedf(float(all_usec) / 1000000.0, 0.001),
                "phases": _top(sim.phase_metrics(), 12),
                "n39_copy_sites": _top(profile.get("copies", {}), 10),
                "n39_schema_sites": _top(profile.get("schema", {}), 10)
            }))
    print("P2_PERF_E_601_TICK_SOURCE_PROFILE_PASS tick=601")
    quit(0)

func _top(stats: Dictionary, limit: int) -> Array:
    var rows: Array = []
    for key in stats:
        var row: Variant = stats[key]
        if not (row is Dictionary):
            continue
        rows.append({"name": str(key), "calls": int(row.get("calls", 0)),
            "total_ms": snappedf(float(row.get("total_usec", 0)) / 1000.0, 0.01),
            "max_ms": snappedf(float(row.get("max_usec", 0)) / 1000.0, 0.01)})
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["total_ms"]) > float(b["total_ms"]))
    return rows.slice(0, mini(limit, rows.size()))

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_601_TICK_SOURCE_PROFILE_FAIL " + reason)
    quit(1)
