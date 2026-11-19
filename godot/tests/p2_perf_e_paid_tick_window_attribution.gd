extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var samples: Array = []
    for tick in range(1, 101):
        var entry: Dictionary = Metrics.summarize(tick - 1, tick, 1000, 1000 + tick * 10, 1100 + tick * 10)
        entry["after_tick"] = tick
        samples.append(entry)
    var result: Dictionary = Metrics.bounded_paid_tick_window(samples, 100)
    assert(result["complete"])
    assert(result["observed_paid_ticks"] == 100)
    assert(result["advance_wall_avg_usec"] == 505.0)
    assert(result["advance_wall_p95_usec"] == 950)
    assert(result["projection_wall_avg_usec"] == 100.0)
    assert(result["request_wall_avg_usec"] == 605.0)
    assert(result["time_kind"] == "elapsed_wall_not_cpu")
    var partial: Array = samples.slice(0, 99)
    assert(not Metrics.bounded_paid_tick_window(partial, 100)["complete"])
    var multi: Array = samples.duplicate(true)
    multi[50]["paid_ticks"] = 2
    assert(Metrics.bounded_paid_tick_window(multi, 100).is_empty())
    var duplicate: Array = samples.duplicate(true)
    duplicate[50]["after_tick"] = 50
    assert(Metrics.bounded_paid_tick_window(duplicate, 100).is_empty())
    var broken: Array = samples.duplicate(true)
    broken[50]["request_wall_usec"] += 1
    assert(Metrics.bounded_paid_tick_window(broken, 100).is_empty())
    var zero: Array = samples.duplicate(true)
    zero[50]["paid_ticks"] = 0
    assert(Metrics.bounded_paid_tick_window(zero, 100).is_empty())
    assert(Metrics.bounded_paid_tick_window(samples, 101).is_empty())
    print("P2_PERF_E_PAID_TICK_WINDOW_ATTRIBUTION PASS")
    quit(0)
