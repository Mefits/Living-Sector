extends SceneTree
## PERF E: deterministic attribution arithmetic, no native simulation needed.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var one: Dictionary = Metrics.summarize(100, 101, 1000, 1400, 1525)
    if not _expect(one.get("valid", false) and one["paid_ticks"] == 1
            and one["advance_wall_usec"] == 400
            and one["projection_wall_usec"] == 125
            and one["request_wall_usec"] == 525
            and one["advance_wall_usec_per_paid_tick"] == 400.0,
            "single paid tick"):
        return
    var zero: Dictionary = Metrics.summarize(101, 101, 2000, 2100, 2200)
    if not _expect(zero["paid_ticks"] == 0
            and zero["advance_wall_usec_per_paid_tick"] == -1.0
            and zero["projection_wall_usec"] == 100,
            "zero tick request must not inflate paid tick average"):
        return
    var multi: Dictionary = Metrics.summarize(101, 103, 3000, 3600, 3700)
    if not _expect(multi["paid_ticks"] == 2
            and multi["advance_wall_usec_per_paid_tick"] == 300.0,
            "multi tick request"):
        return
    if not _expect(not Metrics.summarize(8, 7, 1, 2, 3)["valid"]
            and not Metrics.summarize(8, 9, 3, 2, 4)["valid"]
            and not Metrics.summarize(8, 9, 1, 5, 4)["valid"],
            "reject tick regression and inverted timestamps"):
        return
    print("P2_PERF_E_WORKER_REQUEST_TIMING_BOUNDARY_PASS")
    quit(0)

func _expect(condition: bool, reason: String) -> bool:
    if not condition:
        push_error("P2_PERF_E_WORKER_REQUEST_TIMING_BOUNDARY_FAIL " + reason)
        quit(1)
        return false
    return true
