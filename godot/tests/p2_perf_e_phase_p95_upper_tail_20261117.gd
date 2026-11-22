extends SceneTree
## PERF E negative regression: a forged p95 cannot hide an impossible total.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(1, 101):
        rows.append({"tick": tick, "ships": 10, "dock_queue": 10, "markets": 10, "factions": 10})
    var baseline: Dictionary = Metrics.phase_window(rows, 100)
    var candidate: Dictionary = baseline.duplicate(true)
    if not _check(Metrics.compare_phase_windows(baseline, candidate, "same", "same").get("accepted", false), "valid window rejected"):
        return
    # 100 samples, p95=10 and max=100 imply total <= 95*10+5*100=1450.
    # A forged total of 1500 and matching mean previously passed all guards.
    candidate["phase_total_usec"]["ships"] = 1500
    candidate["phase_avg_usec"]["ships"] = 15.0
    candidate["phase_max_usec"]["ships"] = 100
    if not _check(Metrics.compare_phase_windows(baseline, candidate, "same", "same").get("reason", "") == "impossible_p95_upper_ships", "forged upper tail accepted"):
        return
    print("P2_PERF_E_PHASE_P95_UPPER_TAIL_PASS")
    quit(0)

func _check(ok: bool, reason: String) -> bool:
    if not ok:
        push_error("P2_PERF_E_PHASE_P95_UPPER_TAIL_FAIL " + reason)
        quit(1)
        return false
    return true
