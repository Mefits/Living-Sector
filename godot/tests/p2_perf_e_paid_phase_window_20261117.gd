extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var probe = Probe.new()
    for tick in range(1, 101):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, 10, true)
    var rows: Array = probe.paid_phase_window(100)
    assert(rows.size() == 100, "complete 100-tick phase window")
    var report: Dictionary = Metrics.phase_window(rows, 100)
    assert(report.get("observed_paid_ticks", 0) == 100)
    assert(report["phase_total_usec"]["ships"] == 1000)
    rows[0]["ships"] = 999
    assert(probe.paid_phase_window(100)[0]["ships"] == 10, "detached rows")
    probe._record_phase_elapsed("ships", 101, 5, true)
    assert(probe.paid_phase_window(101).is_empty(), "incomplete last tick")
    for phase in Probe.PHASES:
        probe._record_phase_elapsed(phase, 101, 10, true)
    assert(probe.paid_phase_window(101).size() == 100, "bounded rollover")
    probe._record_phase_elapsed("ships", 105, 10, true)
    assert(probe.paid_phase_window(105).is_empty(), "gap resets window")
    probe._record_phase_elapsed("ships", 106, 10, false)
    assert(probe.paid_phase_window(106).is_empty(), "failed stage excluded")
    print("P2_PERF_E_PAID_PHASE_WINDOW_PASS")
    quit()
