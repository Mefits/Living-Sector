extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var valid: Dictionary = {"valid": true, "paid_ticks": 1, "after_tick": 100,
        "advance_wall_usec": 70, "projection_wall_usec": 30,
        "request_wall_usec": 100}
    assert(Metrics.accept_single_paid_tick_sample(valid, 99, 100))
    assert(not Metrics.accept_single_paid_tick_sample(valid, 98, 100))
    assert(not Metrics.accept_single_paid_tick_sample(valid, 100, 100))
    var bad: Dictionary = valid.duplicate(true)
    bad["request_wall_usec"] = 99
    assert(not Metrics.accept_single_paid_tick_sample(bad, 99, 100))
    bad = valid.duplicate(true)
    bad["after_tick"] = 101
    assert(not Metrics.accept_single_paid_tick_sample(bad, 99, 100))
    bad = valid.duplicate(true)
    bad["advance_wall_usec"] = -1
    assert(not Metrics.accept_single_paid_tick_sample(bad, 99, 100))
    bad = valid.duplicate(true)
    bad["paid_ticks"] = 2
    assert(not Metrics.accept_single_paid_tick_sample(bad, 99, 100))
    print("PERF_E_EXACT_PAID_TICK_SAMPLE_PASS")
    quit()
