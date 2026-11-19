extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const Gate = preload("res://scripts/sim/phase2/n158_callsite_cost_acceptance.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

func _initialize() -> void:
    var probe = Probe.new()
    for tick in range(1, 101):
        for phase in PHASES:
            # Two real instrumentation calls per tick; per-call distribution
            # must not silently collapse into per-paid-tick distribution.
            probe._record_phase_elapsed(phase, tick, 2, true)
            probe._record_phase_elapsed(phase, tick, 4, true)
    var costs: Dictionary = probe.paid_callsite_costs(100)
    var phase: Dictionary = probe.paid_phase_distribution(100)
    if costs.is_empty() or phase.is_empty():
        _fail("missing positive sample")
        return
    var exact: Dictionary = {"accepted": true, "tick": 100}
    var ok: Dictionary = Gate.verify(100, exact, costs, costs.duplicate(true),
        phase, phase.duplicate(true))
    if not ok.get("accepted", false):
        _fail("positive callsite oracle: " + str(ok))
        return
    for name in PHASES:
        var site: Dictionary = costs["sites"][name]
        if site["calls"] != 200 or site["total_usec"] != 600 or (
                site["p95_per_call_usec"] != 4 or site["max_per_call_usec"] != 4 or
                site["active_paid_ticks"] != 100):
            _fail("per-call distribution mismatch")
            return
    if Gate.verify(100, {}, costs, costs, phase, phase).get("accepted", false):
        _fail("unverified checkpoint accepted")
        return
    var corrupt: Dictionary = costs.duplicate(true)
    corrupt["sites"]["ships"]["calls"] = 199
    if Gate.verify(100, exact, costs, corrupt, phase, phase).get("accepted", false):
        _fail("forged call count accepted")
        return
    corrupt = costs.duplicate(true)
    corrupt["sites"]["ships"]["total_usec"] += 1
    if Gate.verify(100, exact, costs, corrupt, phase, phase).get("accepted", false):
        _fail("forged total accepted")
        return
    corrupt = costs.duplicate(true)
    corrupt["sites"]["ships"]["p95_per_call_usec"] = 1000
    if Gate.verify(100, exact, costs, corrupt, phase, phase).get("accepted", false):
        _fail("forged p95 accepted")
        return
    corrupt = costs.duplicate(true)
    corrupt["sites"].erase("markets")
    if Gate.verify(100, exact, costs, corrupt, phase, phase).get("accepted", false):
        _fail("missing site accepted")
        return
    var detached: Dictionary = costs.duplicate(true)
    detached["sites"]["ships"]["calls"] = 1
    if costs["sites"]["ships"]["calls"] != 200:
        _fail("mutable alias")
        return
    probe._record_phase_elapsed("ships", 101, 1, false)
    if not probe.paid_callsite_costs(101).is_empty():
        _fail("aborted paid tick accepted")
        return
    print("P2_PERF_E_CALLSITE_COST_ORACLE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_CALLSITE_COST_ORACLE_FAIL " + reason)
    quit(1)
