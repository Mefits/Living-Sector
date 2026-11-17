extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(1, 101):
        var projection: int = 1000 if tick >= 96 else 10
        var advance: int = 100 if tick >= 96 else 20
        rows.append({"valid": true, "paid_ticks": 1, "after_tick": tick,
            "advance_wall_usec": advance, "projection_wall_usec": projection,
            "request_wall_usec": advance + projection})
    var window: Dictionary = Metrics.bounded_paid_tick_window(rows, 100)
    assert(window.get("complete", false))
    assert(window["observed_paid_ticks"] == 100)
    assert(window["advance_wall_p95_usec"] == 20)
    assert(window["projection_wall_p95_usec"] == 10)
    assert(window["request_wall_p95_usec"] == 30)
    assert(is_equal_approx(window["projection_wall_avg_usec"], 59.5))
    assert(is_equal_approx(window["request_wall_avg_usec"], 83.5))
    var invalid: Array = rows.duplicate(true)
    invalid[50]["after_tick"] = 49
    assert(Metrics.bounded_paid_tick_window(invalid, 100).is_empty())
    print("PERF_E_WORKER_PROJECTION_P95_PASS")
    quit()
