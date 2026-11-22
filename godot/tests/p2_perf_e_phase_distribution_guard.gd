extends SceneTree
## E negative acceptance: a fabricated p95 must not certify phase improvement.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(1, 101):
        rows.append({"tick": tick, "ships": 10, "dock_queue": 20,
            "markets": 30, "factions": 40})
    var reference: Dictionary = Metrics.phase_window(rows, 100)
    if reference.is_empty():
        _fail("valid 100 paid ticks rejected")
        return
    var valid: Dictionary = reference.duplicate(true)
    if not Metrics.compare_phase_windows(reference, valid, "checkpoint", "checkpoint").get("accepted", false):
        _fail("valid equal distribution rejected")
        return
    var forged: Dictionary = reference.duplicate(true)
    # Preserve total and average, but claim an impossible p95 and maximum.
    forged["phase_p95_usec"]["ships"] = 900
    forged["phase_max_usec"]["ships"] = 900
    if Metrics.compare_phase_windows(reference, forged, "checkpoint", "checkpoint").get("accepted", false):
        _fail("impossible percentile accepted")
        return
    forged = reference.duplicate(true)
    forged["phase_max_usec"]["ships"] = 1100
    if Metrics.compare_phase_windows(reference, forged, "checkpoint", "checkpoint").get("accepted", false):
        _fail("maximum greater than sum accepted")
        return
    forged = reference.duplicate(true)
    forged["phase_p95_usec"]["ships"] = 200
    forged["phase_max_usec"]["ships"] = 200
    if Metrics.compare_phase_windows(reference, forged, "checkpoint", "checkpoint").get("accepted", false):
        _fail("p95 requires six large samples, but sum too small")
        return
    print("P2_PERF_E_PHASE_DISTRIBUTION_GUARD_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_PHASE_DISTRIBUTION_GUARD_FAIL " + reason)
    quit(1)
