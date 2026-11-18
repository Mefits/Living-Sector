extends SceneTree
## PERF E: bounded true paid-source-tick windows, not worker/FPS/CPU claims.
## Default cap 900 paid ticks / 480s; no long 2600 CI.
const NativeData = preload("res://scripts/native_data.gd")
const Timed = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const REPORT = preload("res://scripts/sim/phase2/n158_source_window_report.gd")
const MAX_RUNTIME_MS: int = 480000
const HARD_TICK: int = 900
const WINDOW: int = 100

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs/late-growth"))
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
    var resume: String = OS.get_environment("LS_LATE_RESUME")
    if not resume.is_empty():
        var input = FileAccess.open(resume, FileAccess.READ)
        if input == null or not sim.restore_checkpoint(input.get_var(), seed):
            _fail("resume rejected")
            return
    var started: int = Time.get_ticks_msec()
    var steps: Array = []
    var previous: Dictionary = {}
    for tick in range(sim.tick_count + 1, HARD_TICK + 1):
        if Time.get_ticks_msec() - started >= MAX_RUNTIME_MS:
            print("P2_PERF_E_LATE_GROWTH_BOUNDED_STOP ", JSON.stringify({
                "reason": "wall_budget", "last_paid_tick": sim.tick_count,
                "wall_budget_ms": MAX_RUNTIME_MS}))
            quit(0)
            return
        if not sim.queue_control("step", 1):
            _fail("step rejected " + str(tick))
            return
        var began: int = Time.get_ticks_usec()
        sim.advance_frame(0.0)
        var elapsed: int = Time.get_ticks_usec() - began
        if sim.tick_count != tick or not sim.last_phase_failure().is_empty():
            _fail("source paid tick failed " + str(tick) + ": " +
                JSON.stringify(sim.last_phase_failure()))
            return
        steps.append({"tick": tick, "elapsed_usec": elapsed})
        if steps.size() > WINDOW:
            steps.pop_front()
        if tick in [100, 300, 600, 900]:
            var phases: Array = sim.paid_phase_window(tick)
            var snapshot: Dictionary = sim.checkpoint()
            if typeof(snapshot.get("native_production", null)) != TYPE_DICTIONARY or (
                    typeof(snapshot["native_production"].get("world", null)) != TYPE_DICTIONARY):
                _fail("missing detached N39 checkpoint at " + str(tick))
                return
            var ledger: Variant = sim.production.get("_ledger")
            var receipts: int = -1
            if ledger != null and ledger.has_method("receipt_count"):
                receipts = int(ledger.receipt_count())
            var events_snapshot: Variant = sim.events.snapshot()
            var event_count: int = -1
            if events_snapshot is Array or events_snapshot is Dictionary:
                event_count = events_snapshot.size()
            var report: Dictionary = REPORT.summarize(tick, steps, phases,
                snapshot["native_production"]["world"], receipts, event_count)
            if report.get("valid", false) != true:
                _fail("invalid paid window at " + str(tick) + ": " +
                    str(report.get("reason", "unknown")))
                return
            # Preserve a genuine full N38/replay checkpoint only at milestones.
            var output = FileAccess.open("res://logs/late-growth/ls-late-" +
                str(tick) + ".bin", FileAccess.WRITE)
            if output == null:
                _fail("cannot write checkpoint " + str(tick))
                return
            output.store_var(snapshot)
            output.close()
            print("P2_PERF_E_LATE_SOURCE_WINDOW ", JSON.stringify(report))
            if not previous.is_empty():
                print("P2_PERF_E_LATE_SOURCE_DELTA ", JSON.stringify(
                    REPORT.validate_pair(previous, report)))
            previous = report.duplicate(true)
    print("P2_PERF_E_LATE_GROWTH_BOUNDED_PASS tick=", sim.tick_count,
        " time_kind=elapsed_wall_not_cpu")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_LATE_GROWTH_BOUNDED_FAIL " + reason)
    quit(1)
