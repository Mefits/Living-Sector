extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var stage: Dictionary = {"calls": 2, "window_limit": 256,
        "total_usec": 30, "average_usec": 15.0,
        "p95_usec": 20, "max_usec": 20}
    var report: Dictionary = {"enabled": true, "stages": {"motion": stage}}
    var result: Dictionary = Metrics.checkpoint_ship_subphases(100, report)
    assert(result.get("paid_tick", -1) == 100)
    assert(result.get("coverage", "") == "last_bounded_subphase_calls_not_paid_ticks")
    assert(result["stages"]["motion"]["calls"] == 2)
    stage["calls"] = 1
    assert(result["stages"]["motion"]["calls"] == 2)
    assert(Metrics.checkpoint_ship_subphases(101, report).is_empty())
    assert(Metrics.checkpoint_ship_subphases(100, {"enabled": false, "stages": {}}).is_empty())
    stage["calls"] = 257
    assert(Metrics.checkpoint_ship_subphases(100, report).is_empty())
    stage["calls"] = 2
    stage["average_usec"] = 99.0
    assert(Metrics.checkpoint_ship_subphases(100, report).is_empty())
    stage["average_usec"] = 15.0
    stage["p95_usec"] = 21
    assert(Metrics.checkpoint_ship_subphases(100, report).is_empty())
    print("PASS p2_perf_e_ship_subphase_checkpoint_evidence")
    quit(0)
