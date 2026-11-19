extends SceneTree
## E: synthetic instrumentation fixture only; no synthetic economy ticks.
## Run: godot --headless --path godot -s res://tests/p2_perf_e_cadence_phase_callsite_oracle.gd
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const Gate = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

func _initialize() -> void:
    var probe = Probe.new()
    # SourceClock verification is the responsibility of the real benchmark;
    # only phase-call instrumentation is exercised by this fixture.
    for tick in range(1, 101):
        if tick % 5 == 0:
            for phase in PHASES:
                probe._record_phase_elapsed(phase, tick, 10, true)
    var rows: Array = probe.paid_phase_window(100)
    if rows.size() != 100 or int(rows[0]["_calls"]["ships"]) != 0 or (
            int(rows[4]["_calls"]["ships"]) != 1):
        _fail("cadence gaps not represented as zero calls")
        return
    var report: Dictionary = probe.paid_phase_distribution(100)
    if report.is_empty() or int(report["phase_calls"]["ships"]) != 20 or (
            int(report["phase_active_paid_ticks"]["ships"]) != 20 or
            int(report["phase_total_usec"]["ships"]) != 200):
        _fail("phase cadence report")
        return
    var worker: Dictionary = report.duplicate(true)
    worker["phase_total_usec"]["ships"] = 240
    if not Gate.compare_phase_callsite_coverage(report, worker).get("accepted", false):
        _fail("same-seed cadence with different wall time rejected")
        return
    worker["phase_calls"]["ships"] = 19
    if Gate.compare_phase_callsite_coverage(report, worker).get("accepted", false):
        _fail("different call count accepted")
        return
    worker = report.duplicate(true)
    worker["phase_active_paid_ticks"]["ships"] = 101
    if Gate.compare_phase_callsite_coverage(report, worker).get("accepted", false):
        _fail("forged active ticks accepted")
        return
    worker = report.duplicate(true)
    worker.erase("phase_calls")
    if Gate.compare_phase_callsite_coverage(report, worker).get("accepted", false):
        _fail("missing callsite counts accepted")
        return
    var sparse = Probe.new()
    for tick in range(1, 101):
        sparse._record_phase_elapsed("ships", tick, 1, true)
    if not sparse.paid_phase_window(100).is_empty():
        _fail("missing entire instrumented phase accepted")
        return
    var aborted = Probe.new()
    for tick in range(1, 101):
        for phase in PHASES:
            aborted._record_phase_elapsed(phase, tick, 1, true)
    aborted._record_phase_elapsed("ships", 100, 1, false)
    if not aborted.paid_phase_window(100).is_empty():
        _fail("aborted paid candidate accepted")
        return
    print("P2_PERF_E_CADENCE_PHASE_CALLSITE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_CADENCE_PHASE_CALLSITE_FAIL " + reason)
    quit(1)
