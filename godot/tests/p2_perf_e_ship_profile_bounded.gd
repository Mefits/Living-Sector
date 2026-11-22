extends SceneTree
## Bounded profiling storage regression; no simulation changes.
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var samples: Array = []
    for i in range(1024):
        Runtime.append_bounded_ship_profile_sample(samples, i)
    if samples.size() != Runtime.SHIP_PROFILE_WINDOW:
        _fail("unbounded sample storage")
        return
    if samples.front() != 768 or samples.back() != 1023:
        _fail("recent-window order changed")
        return
    Runtime.append_bounded_ship_profile_sample(samples, -50)
    if samples.size() != 256 or samples.front() != 769 or samples.back() != 0:
        _fail("negative elapsed or eviction regression")
        return
    print("P2_PERF_E_SHIP_PROFILE_BOUNDED_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_SHIP_PROFILE_BOUNDED_FAIL: " + reason)
    quit(1)
