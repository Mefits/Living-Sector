extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(1, 101):
        # Outliers in the final six rows must affect nearest-rank p95.
        var cost: int = 100 if tick <= 94 else 900
        rows.append({"tick": tick, "ships": cost, "dock_queue": 0,
            "markets": tick, "factions": 42})
    var result: Dictionary = Metrics.phase_window(rows, 100)
    assert(result["phase_p95_usec"]["ships"] == 900)
    assert(result["phase_max_usec"]["ships"] == 900)
    assert(result["phase_avg_usec"]["ships"] == 148.0)
    assert(result["phase_p95_usec"]["dock_queue"] == 0)
    assert(result["phase_p95_usec"]["markets"] == 95)
    assert(result["phase_max_usec"]["markets"] == 100)
    assert(result["phase_total_usec"]["markets"] == 5050)
    # A single outlier does not contaminate the nearest-rank p95.
    rows[94]["ships"] = 100
    assert(Metrics.phase_window(rows, 100)["phase_p95_usec"]["ships"] == 100)
    # Repeated/missing source ticks must never produce a percentile.
    rows[50]["tick"] = 50
    assert(Metrics.phase_window(rows, 100).is_empty())
    print("P2_PERF_E_PHASE_P95_BOUNDARY_PASS")
    quit()
