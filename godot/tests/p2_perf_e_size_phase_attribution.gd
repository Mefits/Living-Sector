extends SceneTree
## PERF E: standalone positive/negative fixture for joint bounded attribution.
const Joint = preload("res://scripts/sim/phase2/n158_size_phase_attribution.gd")
const Phase = preload("res://scripts/sim/phase2/n158_phase_growth_acceptance.gd")

func _initialize() -> void:
    var early: Dictionary = _window(1, 100, 100)
    var late: Dictionary = _window(201, 300, 200)
    var phase_growth: Dictionary = Phase.compare(early, late)
    var world: Dictionary = {"accepted": true, "from_tick": 100,
        "to_tick": 300, "delta": {"ships": 2, "facilities": 1,
        "dock_waiting": -1, "contracts": 4,
        "receipt_categories": {"market": 10, "dock": 2}}}
    var source: Dictionary = {"accepted": true, "from_tick": 100,
        "to_tick": 300, "delta": {"n9_receipts": 12,
        "source_pending_events": -2}}
    var good: Dictionary = Joint.compare(phase_growth, world, source)
    if not good.get("accepted", false):
        _fail("valid checkpoint-gated attribution " + str(good))
        return
    if good["size_delta"]["n9_receipts"] != 12 or (
            good["phase_delta"]["direct"]["ships"]["per_call_usec_delta"] != 100.0):
        _fail("incorrect source/callsite delta")
        return
    var poisoned: Dictionary = good.duplicate(true)
    poisoned["size_delta"]["ships"] = 999
    if good["size_delta"]["ships"] != 2:
        _fail("output mutable alias")
        return
    var bad_source: Dictionary = source.duplicate(true)
    bad_source["to_tick"] = 600
    if Joint.compare(phase_growth, world, bad_source).get("accepted", false):
        _fail("mismatched checkpoint accepted")
        return
    bad_source = source.duplicate(true)
    bad_source["delta"].erase("n9_receipts")
    if Joint.compare(phase_growth, world, bad_source).get("accepted", false):
        _fail("missing N9 accepted")
        return
    var bad_world: Dictionary = world.duplicate(true)
    bad_world["delta"]["receipt_categories"]["market"] = "unknown"
    if Joint.compare(phase_growth, bad_world, source).get("accepted", false):
        _fail("malformed receipt category accepted")
        return
    bad_world = world.duplicate(true)
    bad_world["accepted"] = false
    if Joint.compare(phase_growth, bad_world, source).get("accepted", false):
        _fail("unverified World accepted")
        return
    var bad_phase: Dictionary = phase_growth.duplicate(true)
    bad_phase["deltas"]["worker"]["ships"]["calls_delta"] += 1.0
    if Joint.compare(bad_phase, world, source).get("accepted", false):
        _fail("cadence divergence accepted")
        return
    bad_phase = phase_growth.duplicate(true)
    bad_phase["deltas"]["direct"]["ships"]["per_call_usec_ratio"] = INF
    if Joint.compare(bad_phase, world, source).get("accepted", false):
        _fail("infinite ratio accepted")
        return
    bad_phase = phase_growth.duplicate(true)
    bad_phase["deltas"]["direct"].erase("markets")
    if Joint.compare(bad_phase, world, source).get("accepted", false):
        _fail("missing phase accepted")
        return
    var invalid_window: Dictionary = _window(101, 200, 200)
    if Phase.compare(early, invalid_window).get("accepted", false) != true:
        _fail("independent window fixture")
        return
    if Phase.compare(early, _window(50, 149, 200)).get("accepted", false):
        _fail("overlapping paid windows accepted")
        return
    print("P2_PERF_E_SIZE_PHASE_ATTRIBUTION_PASS")
    quit(0)

func _window(first: int, last: int, per_call: int) -> Dictionary:
    var sides: Dictionary = {}
    for side in ["direct", "worker"]:
        var phases: Dictionary = {}
        for phase in ["ships", "dock_queue", "markets", "factions"]:
            phases[phase] = {"calls": 100, "active_paid_ticks": 100,
                "total_wall_usec": per_call * 100,
                "per_paid_tick_usec": float(per_call),
                "per_active_tick_usec": float(per_call),
                "per_call_usec": float(per_call)}
        sides[side] = phases
    return {"accepted": true, "from_tick": first, "to_tick": last,
        "direct": sides["direct"], "worker": sides["worker"],
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_SIZE_PHASE_ATTRIBUTION_FAIL " + reason)
    quit(1)
