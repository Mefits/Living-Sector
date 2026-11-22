extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")

func _initialize() -> void:
    var probe = Probe.new()
    assert(probe.paid_phase_distribution(100).is_empty())
    for tick in range(1, 101):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, tick, true)
    var summary: Dictionary = probe.paid_phase_distribution(100)
    assert(summary.get("observed_paid_ticks", 0) == 100)
    assert(summary["phase_total_usec"]["ships"] == 5050)
    assert(summary["phase_avg_usec"]["ships"] == 50.5)
    assert(summary["phase_p95_usec"]["ships"] == 95)
    assert(summary["phase_max_usec"]["ships"] == 100)
    assert(summary["requires_authoritative_source_clock_confirmation"])
    summary["phase_total_usec"]["ships"] = -1
    assert(probe.paid_phase_distribution(100)["phase_total_usec"]["ships"] == 5050)
    probe._record_phase_elapsed("ships", 101, 1, false)
    assert(probe.paid_phase_distribution(100).is_empty())
    print("PASS p2_perf_e_phase_distribution_20261117")
    quit()
