extends SceneTree
## Targeted positive and negative oracle for paid-window resource attribution.
const Probe = preload("res://scripts/sim/phase2/n158_paid_window_resource_probe.gd")

func _initialize() -> void:
    var samples: Array = []
    for tick in range(1, 101):
        samples.append({"valid": true, "paid_ticks": 1, "after_tick": tick,
            "advance_wall_usec": tick, "projection_wall_usec": 1,
            "request_wall_usec": tick + 2,
            "direct_advance_wall_usec": 2 * tick})
    var parity: Dictionary = {"accepted": true, "exact": true, "tick": 100}
    var early: Dictionary = Probe.measure(100, samples, parity, 1024, 2048)
    if not early.get("accepted", false):
        _fail("valid window " + str(early))
        return
    if early["tails"]["direct_advance_wall_usec"]["p50_usec"] != 100 or (
            early["tails"]["direct_advance_wall_usec"]["p95_usec"] != 190 or
            early["tails"]["direct_advance_wall_usec"]["p99_usec"] != 198):
        _fail("nearest rank tail arithmetic")
        return
    var late_samples: Array = samples.duplicate(true)
    for i in range(100):
        late_samples[i]["after_tick"] = i + 201
        late_samples[i]["direct_advance_wall_usec"] += 100
    var late: Dictionary = Probe.measure(300, late_samples,
        {"accepted": true, "exact": true, "tick": 300}, 1536, 4096)
    var growth: Dictionary = Probe.compare(early, late)
    if not growth.get("accepted", false) or (
            growth["allocator_static_delta_bytes"] != 512 or
            growth["tail_deltas"]["direct_advance_wall_usec"]["p99_usec_delta"] != 100.0):
        _fail("valid late comparison " + str(growth))
        return
    var tampered: Array = samples.duplicate(true)
    tampered[42]["after_tick"] = 99
    if Probe.measure(100, tampered, parity, 1024, 2048).get("accepted", false):
        _fail("source clock forgery accepted")
        return
    tampered = samples.duplicate(true)
    tampered[4]["request_wall_usec"] = 0
    if Probe.measure(100, tampered, parity, 1024, 2048).get("accepted", false):
        _fail("request shorter than paid work accepted")
        return
    if Probe.measure(100, samples, {"accepted": true, "exact": false,
            "tick": 100}, 1024, 2048).get("accepted", false):
        _fail("missing exact parity accepted")
        return
    if Probe.measure(100, samples, parity, 4096, 2048).get("accepted", false):
        _fail("impossible allocator peak accepted")
        return
    var forged: Dictionary = late.duplicate(true)
    forged["tails"]["advance_wall_usec"]["p99_usec"] = -1
    if Probe.compare(early, forged).get("accepted", false):
        _fail("forged p99 accepted")
        return
    forged = late.duplicate(true)
    forged["from_tick"] = 100
    if Probe.compare(early, forged).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    forged = late.duplicate(true)
    forged["memory_kind"] = "rss"
    if Probe.compare(early, forged).get("accepted", false):
        _fail("mislabelled allocator as RSS accepted")
        return
    print("P2_PERF_E_PAID_RESOURCE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_PAID_RESOURCE_FAIL " + reason)
    quit(1)
