extends SceneTree
const Acceptance = preload("res://scripts/sim/phase2/n158_live_ab_phase_acceptance.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var ab: Dictionary = {"accepted": true, "from_tick": 201, "to_tick": 300,
        "paid_ticks": 100, "profiled_total_usec": 10000,
        "checkpoint_time_excluded": true, "performance_claim": false,
        "time_kind": "elapsed_wall_not_cpu"}
    var distribution: Dictionary = {"from_tick": 201, "to_tick": 300,
        "observed_paid_ticks": 100, "time_kind": "elapsed_wall_not_cpu",
        "requires_authoritative_source_clock_confirmation": true,
        "phase_total_usec": {}, "phase_avg_usec": {},
        "phase_p95_usec": {}, "phase_max_usec": {},
        "phase_calls": {}, "phase_active_paid_ticks": {}}
    var sites: Dictionary = {"from_tick": 201, "to_tick": 300,
        "observed_paid_ticks": 100, "time_kind": "elapsed_wall_not_cpu",
        "sites": {}}
    for phase in PHASES:
        distribution["phase_total_usec"][phase] = 100
        distribution["phase_avg_usec"][phase] = 1.0
        distribution["phase_p95_usec"][phase] = 2
        distribution["phase_max_usec"][phase] = 5
        distribution["phase_calls"][phase] = 10
        distribution["phase_active_paid_ticks"][phase] = 10
        sites["sites"][phase] = {"calls": 10, "active_paid_ticks": 10,
            "total_usec": 100, "avg_per_call_usec": 10.0,
            "p95_per_call_usec": 12, "max_per_call_usec": 20}
    var accepted: Dictionary = Acceptance.accept(ab, distribution, sites, 300)
    if not accepted.get("accepted", false) or (
            accepted.get("unattributed_paid_wall_usec") != 9600):
        _fail("positive exact totals")
        return
    var clone: Dictionary = accepted.duplicate(true)
    distribution["phase_total_usec"]["ships"] = 999
    if Acceptance.accept(ab, distribution, sites, 300).get("accepted", false):
        _fail("forged total accepted")
        return
    distribution["phase_total_usec"]["ships"] = 100
    sites["sites"]["ships"]["calls"] = 9
    if Acceptance.accept(ab, distribution, sites, 300).get("accepted", false):
        _fail("forged callsite count accepted")
        return
    sites["sites"]["ships"]["calls"] = 10
    if Acceptance.accept(ab, distribution, sites, 301).get("accepted", false):
        _fail("source clock mismatch accepted")
        return
    var forged: Dictionary = ab.duplicate(true)
    forged["profiled_total_usec"] = 300
    if Acceptance.accept(forged, distribution, sites, 300).get("accepted", false):
        _fail("nested phase overcount accepted")
        return
    var missing: Dictionary = sites.duplicate(true)
    missing["sites"].erase("markets")
    if Acceptance.accept(ab, distribution, missing, 300).get("accepted", false):
        _fail("missing phase accepted")
        return
    var alias_test: Dictionary = distribution.duplicate(true)
    alias_test["phase_total_usec"]["ships"] = 1234
    if distribution["phase_total_usec"]["ships"] != 100 or (
            clone["phase"]["ships"]["total_usec"] != 100):
        _fail("mutable report alias")
        return
    print("P2_PERF_E_LIVE_AB_PHASE_ACCEPTANCE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_LIVE_AB_PHASE_ACCEPTANCE_FAIL " + reason)
    quit(1)
