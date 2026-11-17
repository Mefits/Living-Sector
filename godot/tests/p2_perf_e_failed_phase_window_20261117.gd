extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")

func _initialize() -> void:
    var probe = Probe.new()
    for tick in range(1, 101):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, 10, true)
    assert(probe.paid_phase_window(100).size() == 100)
    # A failed late phase must invalidate previously accepted stages.
    probe._record_phase_elapsed("ships", 101, 10, true)
    probe._record_phase_elapsed("dock_queue", 101, 10, false)
    for phase in Probe.PHASES:
        probe._record_phase_elapsed(phase, 101, 10, true)
    assert(probe.paid_phase_window(101).is_empty(), "failed tick must not be resurrected")
    # Only 100 subsequent contiguous successful ticks can restore evidence.
    for tick in range(102, 202):
        for phase in Probe.PHASES:
            probe._record_phase_elapsed(phase, tick, 10, true)
    assert(probe.paid_phase_window(201).size() == 100, "clean window recovers")
    print("P2_PERF_E_FAILED_PHASE_WINDOW_PASS")
    quit()
