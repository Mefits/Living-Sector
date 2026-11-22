extends SceneTree
## PERF E: bounded genuine late-tick phase + ledger/world size diagnosis.
## No fake movement, no production writes, no 35-minute CI.
const NativeData = preload("res://scripts/native_data.gd")
const Timed = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const MAX_RUNTIME_MS: int = 480000
const HARD_TICK: int = 2600
const REPORT_WINDOW: int = 100

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed unavailable")
        return
    var sim = Timed.new()
    if not sim.start_from_seed(seed):
        _fail("source refused seed " + str(sim.boot_error()))
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 16.0):
        _fail("source clock controls refused")
        return
    sim.advance_frame(0.0)
    var begun_ms: int = Time.get_ticks_msec()
    var last_timing: Dictionary = sim.phase_metrics()
    var last_copy: Dictionary = sim.production.native_schema_profile()
    var window: Array[int] = []
    var last_report_tick: int = 0
    for step in range(1, HARD_TICK + 1):
        if Time.get_ticks_msec() - begun_ms > MAX_RUNTIME_MS:
            _report(sim, window, last_report_tick, last_timing,
                last_copy, begun_ms, "WALL_BUDGET", step - 1)
            print("P2_PERF_E_LATE_TICK_BOUNDED_PASS stop=wall_budget tick=",
                sim.tick_count)
            quit(0)
            return
        if not sim.queue_control("step", 1):
            _fail("step rejected at " + str(step))
            return
        var before: int = Time.get_ticks_usec()
        sim.advance_frame(0.0)
        var elapsed: int = maxi(0, Time.get_ticks_usec() - before)
        if sim.tick_count != step or not sim.last_phase_failure().is_empty():
            _fail("paid step or native phase rejected at " + str(step)
                + ": " + JSON.stringify(sim.last_phase_failure()))
            return
        window.append(elapsed)
        if window.size() > REPORT_WINDOW:
            window.pop_front()
        if step in [100, 300, 600, 900, 1200, 1500, 1800, 2100, 2300, 2500, 2600]:
            _report(sim, window, last_report_tick, last_timing,
                last_copy, begun_ms, "MILESTONE", step)
            last_report_tick = step
            last_timing = sim.phase_metrics()
            last_copy = sim.production.native_schema_profile()
    print("P2_PERF_E_LATE_TICK_BOUNDED_PASS stop=target tick=", sim.tick_count)
    quit(0)

func _report(sim, window: Array[int], previous_tick: int,
        before_phases: Dictionary, before_copies: Dictionary,
        began_ms: int, why: String, tick: int) -> void:
    var sorted: Array[int] = window.duplicate()
    sorted.sort()
    var sum_usec: int = 0
    for value in window:
        sum_usec += value
    var pct95: int = 0
    if not sorted.is_empty():
        pct95 = sorted[clampi(ceili(float(sorted.size()) * 0.95) - 1,
            0, sorted.size() - 1)]
    var phases: Array = _diff(sim.phase_metrics(), before_phases)
    var copies: Array = _diff(sim.production.native_schema_profile().get(
        "copies", {}), before_copies.get("copies", {}))
    var schema: Array = _diff(sim.production.native_schema_profile().get(
        "schema", {}), before_copies.get("schema", {}))
    var receipt_count: int = -1
    var ledger_size: int = -1
    # Query strictly read-only counters from actual single authoritative N9.
    var ledger: Variant = sim.production.get("_ledger")
    if ledger != null and ledger.has_method("receipt_count"):
        receipt_count = int(ledger.receipt_count())
    if ledger != null and ledger.has_method("snapshot"):
        # No full Ledger.snapshot at milestones: that is a measured hotpath.
        ledger_size = -1
    print("P2_PERF_E_LATE_TICK_WINDOW ", JSON.stringify({
        "tick": tick, "reason": why,
        "window_begin_tick": previous_tick,
        "window_end_tick": tick,
        "runtime_s": snappedf(float(Time.get_ticks_msec() - began_ms) / 1000.0, 0.01),
        "window_average_ms": snappedf(float(sum_usec) / 1000.0 /
            float(maxi(1, window.size())), 0.01),
        "window_p95_ms": snappedf(float(pct95) / 1000.0, 0.01),
        "window_size": window.size(), "receipt_count": receipt_count,
        "phases": phases.slice(0, mini(12, phases.size())),
        "copies": copies.slice(0, mini(10, copies.size())),
        "schema": schema.slice(0, mini(10, schema.size()))
    }))

func _diff(now: Dictionary, previous: Dictionary) -> Array:
    var result: Array = []
    for key in now:
        var current: Dictionary = now[key]
        var past: Dictionary = previous.get(key, {})
        var change_usec: int = int(current.get("total_usec", 0)) - int(
            past.get("total_usec", 0))
        if change_usec <= 0:
            continue
        result.append({"name": str(key), "total_ms": snappedf(
            float(change_usec) / 1000.0, 0.01), "calls": int(
            current.get("calls", 0)) - int(past.get("calls", 0)),
            "max_ms": snappedf(float(current.get("max_usec", 0)) / 1000.0, 0.01)})
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["total_ms"]) > float(b["total_ms"]))
    return result

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_LATE_TICK_BOUNDED_FAIL " + reason)
    quit(1)
