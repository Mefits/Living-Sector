extends SceneTree
## Detached E acceptance: cannot label a phase speedup without source parity.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var old_rows: Array = []
    var new_rows: Array = []
    for tick in range(1, 101):
        old_rows.append({"tick": tick, "ships": 200, "dock_queue": 90,
            "markets": 50, "factions": 40})
        new_rows.append({"tick": tick, "ships": 120, "dock_queue": 90,
            "markets": 50, "factions": 40})
    var old_window: Dictionary = Metrics.phase_window(old_rows, 100)
    var new_window: Dictionary = Metrics.phase_window(new_rows, 100)
    if old_window.is_empty() or new_window.is_empty():
        _fail("valid windows rejected")
        return
    var result: Dictionary = Metrics.compare_phase_windows(
        old_window, new_window, "exact-n38-checkpoint", "exact-n38-checkpoint")
    if not result.get("accepted", false) or (
            result["phase_deltas"]["ships"]["avg_delta_usec"] != -80.0) or (
            result["phase_deltas"]["dock_queue"]["avg_delta_usec"] != 0.0):
        _fail("valid same-seed phase attribution")
        return
    if Metrics.compare_phase_windows(old_window, new_window, "", "").get("accepted", false):
        _fail("empty source fingerprint accepted")
        return
    if Metrics.compare_phase_windows(old_window, new_window, "a", "b").get("accepted", false):
        _fail("source divergence accepted")
        return
    var incomplete: Dictionary = new_window.duplicate(true)
    incomplete["observed_paid_ticks"] = 99
    if Metrics.compare_phase_windows(old_window, incomplete, "a", "a").get("accepted", false):
        _fail("incomplete paid tick coverage accepted")
        return
    var corrupt: Dictionary = new_window.duplicate(true)
    corrupt["phase_total_usec"]["ships"] = -1
    if Metrics.compare_phase_windows(old_window, corrupt, "a", "a").get("accepted", false):
        _fail("negative phase duration accepted")
        return
    var mismatch: Dictionary = new_window.duplicate(true)
    mismatch["phase_avg_usec"]["ships"] = 0.0
    if Metrics.compare_phase_windows(old_window, mismatch, "a", "a").get("accepted", false):
        _fail("inconsistent average accepted")
        return
    new_rows[0]["tick"] = 1.0
    if not Metrics.phase_window(new_rows, 100).is_empty():
        _fail("noninteger source tick accepted")
        return
    print("P2_PERF_E_PHASE_PARITY_COMPARATOR_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_PHASE_PARITY_COMPARATOR_FAIL " + reason)
    quit(1)
