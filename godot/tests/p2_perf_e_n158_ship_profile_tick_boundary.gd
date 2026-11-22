extends SceneTree
## Opt-in profiler regression; never advances canonical N158/World.
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var samples: Array = []
    if Runtime.ship_profile_elapsed_for_tick({"tick": 10, "usec": 100}, 10, 125) != 25:
        _fail("valid same-tick elapsed rejected")
        return
    if Runtime.ship_profile_elapsed_for_tick({"tick": 10, "usec": 100}, 11, 125) != -1:
        _fail("cross-tick begin accepted")
        return
    if Runtime.ship_profile_elapsed_for_tick({"tick": 10, "usec": 100}, 10, 99) != -1:
        _fail("negative elapsed accepted")
        return
    if Runtime.ship_profile_elapsed_for_tick({}, 10, 125) != -1:
        _fail("missing begin accepted")
        return
    for i in range(Runtime.SHIP_PROFILE_WINDOW + 20):
        Runtime.append_bounded_ship_profile_sample(samples, i)
    if samples.size() != Runtime.SHIP_PROFILE_WINDOW:
        _fail("profile window unbounded")
        return
    if int(samples.front()) != 20 or int(samples.back()) != Runtime.SHIP_PROFILE_WINDOW + 19:
        _fail("profile window did not retain newest samples")
        return
    print("P2_PERF_E_N158_SHIP_PROFILE_TICK_BOUNDARY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_N158_SHIP_PROFILE_TICK_BOUNDARY_FAIL: " + reason)
    quit(1)
