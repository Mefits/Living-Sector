extends SceneTree
## N158 profiler oracle: real instrumentation storage must remain bounded,
## reject overflow/failed paid ticks, and discard evidence after clock rewind.
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

func _initialize() -> void:
    var probe = Probe.new()
    _fill(probe, 1, 100)
    var first: Dictionary = probe.paid_phase_totals(100)
    assert(first.get("observed_paid_ticks", 0) == 100)
    for phase in PHASES:
        assert(first["phase_calls"][phase] == 100)
        assert(first["phase_total_usec"][phase] == 200)
    var detached: Dictionary = probe.paid_callsite_costs(100)
    assert(detached.get("sites", {}).get("ships", {}).get("calls", 0) == 100)
    # Deliberately exceed the bounded per-tick observation budget.
    for i in range(Probe.MAX_PHASE_CALLS_PER_TICK + 1):
        probe._record_phase_elapsed("ships", 101, 1, true)
    assert(probe.paid_phase_window(101).is_empty())
    assert(probe._retained_call_samples == 0)
    assert(probe._paid_rows.is_empty())
    # A rejected tick cannot poison windows after it ages out.
    _fill(probe, 102, 201)
    assert(probe.paid_phase_totals(201).get("observed_paid_ticks", 0) == 100)
    assert(probe._retained_call_samples <= Probe.MAX_RETAINED_CALL_SAMPLES)
    # Restart/rewind must clear old samples AND lifetime aggregates.
    probe._record_phase_elapsed("ships", 1, 7, true)
    assert(probe._retained_call_samples == 1)
    assert(probe.phase_metrics()["ships"]["calls"] == 1)
    assert(probe.paid_phase_window(201).is_empty())
    _fill(probe, 2, 100)
    var restarted: Dictionary = probe.paid_phase_totals(100)
    assert(restarted.get("observed_paid_ticks", 0) == 100)
    assert(restarted["phase_total_usec"]["ships"] == 205)
    # An actual failed phase invalidates the candidate paid-tick window.
    probe._record_phase_elapsed("markets", 101, 1, false)
    assert(probe.paid_phase_window(101).is_empty())
    assert(probe._retained_call_samples == 0)
    # A negative elapsed time is never accepted as paid evidence.
    probe._record_phase_elapsed("ships", 102, -1, true)
    assert(probe.paid_phase_window(102).is_empty())
    print("P2_PERF_E_PHASE_OBSERVATION_BOUND_RESET PASS")
    quit(0)

func _fill(probe, first_tick: int, last_tick: int) -> void:
    for tick in range(first_tick, last_tick + 1):
        for phase in PHASES:
            probe._record_phase_elapsed(phase, tick, 2, true)
