extends SceneTree
const Growth = preload("res://scripts/sim/phase2/n158_phase_growth_acceptance.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

func _initialize() -> void:
    var first: Dictionary = _gate(100, 100)
    var last: Dictionary = _gate(300, 200)
    var a: Dictionary = Growth.accept_window(100, first)
    var b: Dictionary = Growth.accept_window(300, last)
    if not a.get("accepted", false) or not b.get("accepted", false):
        _fail("positive windows rejected")
        return
    var growth: Dictionary = Growth.compare(a, b)
    if not growth.get("accepted", false) or (
            growth["deltas"]["direct"]["ships"]["per_call_usec_delta"] != 100.0):
        _fail("positive cadence-normalized growth rejected")
        return
    if not _reject_window(100, first, "worker", "phase_calls", "ships", 3):
        return
    if not _reject_window(100, first, "worker", "phase_total_usec", "ships", -1):
        return
    if not _reject_window(100, first, "worker", "phase_p95_usec", "ships", 999999):
        return
    if not _reject_window(100, first, "worker", "phase_avg_usec", "ships", NAN):
        return
    var wrong: Dictionary = first.duplicate(true)
    wrong["tick"] = 101
    if Growth.accept_window(100, wrong).get("accepted", false):
        _fail("forged checkpoint gate accepted")
        return
    wrong = first.duplicate(true)
    wrong["direct_phase"]["phase_calls"].erase("markets")
    if Growth.accept_window(100, wrong).get("accepted", false):
        _fail("missing phase accepted")
        return
    wrong = first.duplicate(true)
    wrong["direct_phase"]["from_tick"] = 2
    if Growth.accept_window(100, wrong).get("accepted", false):
        _fail("forged paid tick bounds accepted")
        return
    var overlap: Dictionary = b.duplicate(true)
    overlap["from_tick"] = 100
    if Growth.compare(a, overlap).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    var corrupt: Dictionary = b.duplicate(true)
    corrupt["worker"]["ships"]["per_call_usec"] = 999999.0
    if Growth.compare(a, corrupt).get("accepted", false):
        _fail("forged normalized worker timing accepted")
        return
    var altered: Dictionary = b.duplicate(true)
    altered["worker"]["ships"]["calls"] += 1
    altered["worker"]["ships"]["per_call_usec"] = (
        float(altered["worker"]["ships"]["total_wall_usec"]) /
        float(altered["worker"]["ships"]["calls"]))
    if Growth.compare(a, altered).get("accepted", false):
        _fail("late cadence mismatch accepted")
        return
    # Returned metrics must be detached; mutating the report must not mutate inputs.
    var original: int = first["direct_phase"]["phase_calls"]["ships"]
    a["direct"]["ships"]["calls"] = 123
    if first["direct_phase"]["phase_calls"]["ships"] != original:
        _fail("mutable alias escaped")
        return
    print("P2_PERF_E_PHASE_GROWTH_PASS")
    quit(0)

func _gate(tick: int, duration: int) -> Dictionary:
    var gate: Dictionary = {"accepted": true, "tick": tick,
        "time_kind": "elapsed_wall_not_cpu"}
    for side in ["direct", "worker"]:
        var totals: Dictionary = {}
        var calls: Dictionary = {}
        var active: Dictionary = {}
        var averages: Dictionary = {}
        var p95: Dictionary = {}
        var maxima: Dictionary = {}
        for phase in PHASES:
            totals[phase] = duration * 100
            calls[phase] = 100
            active[phase] = 100
            averages[phase] = float(duration)
            p95[phase] = duration
            maxima[phase] = duration
        gate[side + "_phase"] = {"from_tick": tick - 99, "to_tick": tick,
            "observed_paid_ticks": 100, "time_kind": "elapsed_wall_not_cpu",
            "phase_total_usec": totals, "phase_calls": calls,
            "phase_active_paid_ticks": active, "phase_avg_usec": averages,
            "phase_p95_usec": p95, "phase_max_usec": maxima}
    return gate

func _reject_window(tick: int, source: Dictionary, side: String,
        key: String, phase: String, value: Variant) -> bool:
    var wrong: Dictionary = source.duplicate(true)
    wrong[side + "_phase"][key][phase] = value
    if Growth.accept_window(tick, wrong).get("accepted", false):
        _fail("forged " + side + " " + key + " accepted")
        return false
    return true

func _fail(message: String) -> void:
    push_error("P2_PERF_E_PHASE_GROWTH_FAIL " + message)
    quit(1)
