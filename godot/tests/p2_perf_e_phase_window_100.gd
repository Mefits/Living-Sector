extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(1, 101):
        rows.append({"tick": tick, "ships": 1000, "dock_queue": 200,
            "markets": 300, "factions": 400})
    var result: Dictionary = Metrics.phase_window(rows, 100)
    assert(result.get("observed_paid_ticks", 0) == 100)
    assert(result["phase_total_usec"]["ships"] == 100000)
    assert(result["phase_avg_usec"]["dock_queue"] == 200.0)
    assert(result["time_kind"] == "elapsed_wall_not_cpu")
    rows[50]["tick"] = 49
    assert(Metrics.phase_window(rows, 100).is_empty())
    rows[50]["tick"] = 51
    rows[50].erase("markets")
    assert(Metrics.phase_window(rows, 100).is_empty())
    rows[50]["markets"] = -1
    assert(Metrics.phase_window(rows, 100).is_empty())
    rows[50]["markets"] = 300
    rows.pop_back()
    assert(Metrics.phase_window(rows, 100).is_empty())
    print("P2_PERF_E_PHASE_WINDOW_100_PASS")
    quit()
