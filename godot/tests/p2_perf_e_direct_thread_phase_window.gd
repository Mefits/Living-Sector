extends SceneTree
## PERF E: positive and negative oracle for real opt-in phase attribution.
const Acceptance = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var checkpoint: Dictionary = {"tick": 100, "native_production": {
        "ledger": {"receipts": [{"id": 1}]}, "rng": [7, 11],
        "ships": [{"cargo": 4}]}}
    var direct_phase: Dictionary = _phase(100, 10)
    var worker_phase: Dictionary = _phase(100, 12)
    var response: Dictionary = {"ok": true, "tick": 100,
        "checkpoint": checkpoint.duplicate(true),
        "paid_phase_window": worker_phase.duplicate(true)}
    var paid: Dictionary = {"accepted": true, "to_tick": 100,
        "observed_paid_ticks": 100,
        "direct_advance_wall_avg_usec": 100.0,
        "worker_advance_wall_avg_usec": 110.0}
    if not _accept(checkpoint, response, direct_phase, paid):
        _fail("valid exact paid-phase pair")
        return
    var altered: Dictionary = response.duplicate(true)
    altered["checkpoint"]["native_production"]["ships"][0]["cargo"] = 9
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("cargo divergence")
        return
    altered = response.duplicate(true)
    altered.erase("paid_phase_window")
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("missing worker phase")
        return
    altered = response.duplicate(true)
    altered["paid_phase_window"]["to_tick"] = 99
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("phase tick gap")
        return
    altered = response.duplicate(true)
    altered["paid_phase_window"]["phase_p95_usec"]["ships"] = 9000
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("forged p95")
        return
    altered = response.duplicate(true)
    altered["paid_phase_window"]["phase_total_usec"]["ships"] = 30000
    altered["paid_phase_window"]["phase_avg_usec"]["ships"] = 300.0
    altered["paid_phase_window"]["phase_p95_usec"]["ships"] = 300
    altered["paid_phase_window"]["phase_max_usec"]["ships"] = 300
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("phase exceeds measured advance")
        return
    var broken_paid: Dictionary = paid.duplicate(true)
    broken_paid["observed_paid_ticks"] = 99
    if _accept(checkpoint, response, direct_phase, broken_paid):
        _fail("incomplete paid coverage")
        return
    broken_paid = paid.duplicate(true)
    broken_paid["direct_advance_wall_avg_usec"] = 1.0
    if _accept(checkpoint, response, direct_phase, broken_paid):
        _fail("direct attribution exceeds wall")
        return
    altered = response.duplicate(true)
    altered["paid_phase_window"]["phase_total_usec"].erase("factions")
    if _accept(checkpoint, altered, direct_phase, paid):
        _fail("missing phase")
        return
    print("P2_PERF_E_DIRECT_THREAD_PHASE_WINDOW_PASS")
    quit(0)

func _phase(tick: int, usec: int) -> Dictionary:
    var totals: Dictionary = {}
    var avg: Dictionary = {}
    var p95: Dictionary = {}
    var maxima: Dictionary = {}
    for phase in ["ships", "dock_queue", "markets", "factions"]:
        totals[phase] = 100 * usec
        avg[phase] = float(usec)
        p95[phase] = usec
        maxima[phase] = usec
    return {"from_tick": tick - 99, "to_tick": tick,
        "observed_paid_ticks": 100, "phase_total_usec": totals,
        "phase_avg_usec": avg, "phase_p95_usec": p95,
        "phase_max_usec": maxima, "time_kind": "elapsed_wall_not_cpu"}

func _accept(checkpoint: Dictionary, response: Dictionary,
        direct_phase: Dictionary, paid: Dictionary) -> bool:
    return Acceptance.verify_paid_phase_pair(100, checkpoint, response,
        direct_phase, paid).get("accepted", false)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_DIRECT_THREAD_PHASE_WINDOW_FAIL " + reason)
    quit(1)
