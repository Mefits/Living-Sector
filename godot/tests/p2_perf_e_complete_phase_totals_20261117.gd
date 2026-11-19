extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")

func _initialize() -> void:
    var probe = Probe.new()
    for tick in range(1, 101):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, 10, true)
    var good: Dictionary = probe.paid_phase_totals(100)
    assert(good.get("observed_paid_ticks", 0) == 100)
    assert(good["phase_total_usec"]["ships"] == 1000)
    good["phase_total_usec"]["ships"] = -1
    assert(probe.paid_phase_totals(100)["phase_total_usec"]["ships"] == 1000,
        "returned summary must be detached")
    probe._record_phase_elapsed("ships", 101, 900, true)
    assert(probe.paid_phase_totals(101).is_empty(),
        "partial paid tick cannot be counted")
    probe._record_phase_elapsed("dock_queue", 101, 900, false)
    assert(probe.paid_phase_totals(101).is_empty(),
        "failed tick must invalidate candidate")
    for tick in range(102, 202):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, 12, true)
    assert(probe.paid_phase_totals(201)["phase_total_usec"]["ships"] == 1200,
        "aborted samples must not leak into recovered window")
    print("P2_PERF_E_COMPLETE_PHASE_TOTALS_PASS")
    quit()
