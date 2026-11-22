extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_paired_paid_tick_drift.gd")

func _samples(start_tick: int, worker_extra: int) -> Array:
    var rows: Array = []
    for i in range(100):
        rows.append({"valid": true, "paid_ticks": 1,
            "after_tick": start_tick + i,
            "direct_advance_wall_usec": 100 + i,
            "advance_wall_usec": 100 + i + worker_extra,
            "projection_wall_usec": 3,
            "request_wall_usec": 110 + i + worker_extra})
    return rows

func _initialize() -> void:
    var first: Array = _samples(1, 10)
    var early: Dictionary = Probe.accept(100, first,
        {"accepted": true, "exact": true, "tick": 100})
    if not early.get("accepted", false) or early["paired_delta_total_usec"] != 1000 or (
            early["paired_delta_p95_usec"] != 10 or
            early["request_unattributed_total_usec"] != 700 or
            early["worker_slower_ticks"] != 100):
        _fail("valid aligned window " + str(early))
        return
    var late: Dictionary = Probe.accept(300, _samples(201, 20),
        {"accepted": true, "exact": true, "tick": 300})
    var growth: Dictionary = Probe.compare(early, late)
    if not growth.get("accepted", false) or (
            growth["paired_total_delta_change_usec"] != 1000 or
            growth["paired_p95_delta_change_usec"] != 10):
        _fail("paired growth " + str(growth))
        return
    var bad: Array = first.duplicate(true)
    bad[49]["after_tick"] = 99
    if Probe.accept(100, bad, {"accepted": true, "exact": true,
            "tick": 100}).get("accepted", false):
        _fail("wrong source clock accepted")
        return
    bad = first.duplicate(true)
    bad[30]["request_wall_usec"] = bad[30]["advance_wall_usec"]
    if Probe.accept(100, bad, {"accepted": true, "exact": true,
            "tick": 100}).get("accepted", false):
        _fail("request underreports projection")
        return
    bad = first.duplicate(true)
    bad[0]["direct_advance_wall_usec"] = -1
    if Probe.accept(100, bad, {"accepted": true, "exact": true,
            "tick": 100}).get("accepted", false):
        _fail("negative time accepted")
        return
    if Probe.accept(100, first, {"accepted": true, "exact": false,
            "tick": 100}).get("accepted", false):
        _fail("forged parity accepted")
        return
    var forged: Dictionary = late.duplicate(true)
    forged["paired_delta_total_usec"] += 1
    if Probe.compare(early, forged).get("accepted", false):
        _fail("forged total accepted")
        return
    forged = late.duplicate(true)
    forged["worker_slower_ticks"] = 99
    if Probe.compare(early, forged).get("accepted", false):
        _fail("forged sign count accepted")
        return
    forged = late.duplicate(true)
    forged["from_tick"] = 100
    if Probe.compare(early, forged).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    forged = late.duplicate(true)
    forged["time_kind"] = "cpu"
    if Probe.compare(early, forged).get("accepted", false):
        _fail("false CPU attribution accepted")
        return
    first[0]["advance_wall_usec"] = 999999
    if early["paired_delta_total_usec"] != 1000:
        _fail("mutable sample alias")
        return
    print("P2_PERF_E_PAIRED_DRIFT_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_PAIRED_DRIFT_FAIL " + reason)
    quit(1)
