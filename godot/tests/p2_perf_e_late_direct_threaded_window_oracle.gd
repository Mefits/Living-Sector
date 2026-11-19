extends SceneTree
## Detached positive/negative oracle for bounded early/late direct-thread windows.
const Acceptance = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var early: Dictionary = _window(1, 100, 100.0, 120.0, 20.0)
    var late: Dictionary = _window(201, 300, 220.0, 280.0, 60.0)
    var growth: Dictionary = Acceptance.compare_late_windows(early, late)
    if not growth.get("accepted", false):
        _fail("valid non-overlapping parity windows rejected: " + str(growth))
        return
    if growth["deltas"]["direct_advance_wall_avg_usec_delta_usec"] != 120.0 or (
            absf(float(growth["deltas"]["worker_request_wall_avg_usec_ratio"]) - 340.0 / 140.0) > 0.00001):
        _fail("growth attribution incorrect")
        return
    if Acceptance.compare_late_windows(late, early).get("accepted", false):
        _fail("reversed windows accepted")
        return
    var bad: Dictionary = late.duplicate(true)
    bad["from_tick"] = 100
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("forged tick coverage accepted")
        return
    bad = late.duplicate(true)
    bad["from_tick"] = 101
    bad["to_tick"] = 200
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    bad = late.duplicate(true)
    bad["observed_paid_ticks"] = 99
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("missing paid tick accepted")
        return
    bad = late.duplicate(true)
    bad["worker_request_wall_avg_usec"] = 200.0
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("request shorter than advance+projection accepted")
        return
    bad = late.duplicate(true)
    bad["worker_projection_wall_avg_usec"] = -1.0
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("negative projection accepted")
        return
    bad = late.duplicate(true)
    bad["time_kind"] = "cpu"
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("false CPU label accepted")
        return
    bad = late.duplicate(true)
    bad["accepted"] = false
    if Acceptance.compare_late_windows(early, bad).get("accepted", false):
        _fail("unverified source window accepted")
        return
    print("P2_PERF_E_LATE_DIRECT_THREAD_WINDOW_ORACLE_PASS")
    quit(0)

func _window(first: int, last: int, direct_usec: float,
        advance_usec: float, projection_usec: float) -> Dictionary:
    return {"accepted": true, "from_tick": first, "to_tick": last,
        "observed_paid_ticks": 100, "direct_advance_wall_avg_usec": direct_usec,
        "worker_advance_wall_avg_usec": advance_usec,
        "worker_projection_wall_avg_usec": projection_usec,
        "worker_request_wall_avg_usec": advance_usec + projection_usec,
        "time_kind": "elapsed_wall_not_cpu"}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_LATE_DIRECT_THREAD_WINDOW_ORACLE_FAIL " + reason)
    quit(1)
