extends SceneTree
const Integrity = preload("res://scripts/sim/phase2/n158_paid_tick_sample_integrity.gd")

func _initialize() -> void:
    var first: Array = _samples(100, 30, 40)
    var parity: Dictionary = {"accepted": true, "exact": true, "tick": 100}
    var early: Dictionary = Integrity.accept(100, first, parity)
    if not early.get("accepted", false):
        _fail("valid paid window rejected " + str(early))
        return
    if early["worker_request_overhead_total_usec"] != 500 or (
            early["direct_slower_ticks"] != 0 or early["worker_slower_ticks"] != 100):
        _fail("incorrect independent accounting")
        return
    var late: Dictionary = Integrity.accept(300, _samples(300, 60, 40),
        {"accepted": true, "exact": true, "tick": 300})
    if not late.get("accepted", false) or not Integrity.compare(early, late).get(
            "accepted", false):
        _fail("non-overlapping paid windows rejected")
        return
    # Mutating the original window cannot alter the detached scalar report.
    first[0]["direct_advance_wall_usec"] = 999
    if early["totals_usec"]["direct_advance_wall_usec"] != 3000:
        _fail("mutable sample alias retained")
        return
    var bad: Array = _samples(100, 30, 40)
    bad[45]["after_tick"] = 47
    if Integrity.accept(100, bad, parity).get("accepted", false):
        _fail("source clock discontinuity accepted")
        return
    bad = _samples(100, 30, 40)
    bad[12]["request_wall_usec"] = 1
    if Integrity.accept(100, bad, parity).get("accepted", false):
        _fail("worker request underflow accepted")
        return
    bad = _samples(100, 30, 40)
    bad[4]["direct_advance_wall_usec"] = -1
    if Integrity.accept(100, bad, parity).get("accepted", false):
        _fail("negative direct timing accepted")
        return
    if Integrity.accept(100, _samples(100, 30, 40), {
            "accepted": true, "exact": false, "tick": 100}).get("accepted", false):
        _fail("non-exact checkpoint accepted")
        return
    var forged: Dictionary = late.duplicate(true)
    forged["worker_request_overhead_total_usec"] += 1
    if Integrity.compare(early, forged).get("accepted", false):
        _fail("forged overhead accepted")
        return
    forged = late.duplicate(true)
    forged["direct_minus_worker_advance_total_usec"] = 0
    if Integrity.compare(early, forged).get("accepted", false):
        _fail("forged direct-worker difference accepted")
        return
    forged = late.duplicate(true)
    forged["direct_slower_ticks"] = 100
    if Integrity.compare(early, forged).get("accepted", false):
        _fail("forged outcome counts accepted")
        return
    forged = late.duplicate(true)
    forged["from_tick"] = 100
    if Integrity.compare(early, forged).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    print("P2_PERF_E_PAID_TICK_SAMPLE_INTEGRITY_PASS")
    quit(0)

func _samples(end_tick: int, direct_usec: int, worker_usec: int) -> Array:
    var result: Array = []
    for tick in range(end_tick - 99, end_tick + 1):
        result.append({"valid": true, "paid_ticks": 1, "after_tick": tick,
            "advance_wall_usec": worker_usec, "projection_wall_usec": 10,
            "request_wall_usec": worker_usec + 15,
            "direct_advance_wall_usec": direct_usec})
    return result

func _fail(message: String) -> void:
    push_error("P2_PERF_E_PAID_TICK_SAMPLE_INTEGRITY_FAIL " + message)
    quit(1)
