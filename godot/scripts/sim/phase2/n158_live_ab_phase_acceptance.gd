extends RefCounted
## E: independent bounded phase/callsite oracle for a real paid N158 A/B window.
## Receives detached scalar reports, never a mutable World or N9 journal.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]
const WINDOW: int = 100
const MAX_USEC: int = 60000000

static func accept(ab: Dictionary, distribution: Dictionary,
        sites: Dictionary, source_end_tick: int) -> Dictionary:
    if ab.get("accepted") != true or ab.get("checkpoint_time_excluded") != true or (
            ab.get("performance_claim") != false or
            ab.get("time_kind") != "elapsed_wall_not_cpu" or
            typeof(ab.get("paid_ticks")) != TYPE_INT or ab["paid_ticks"] != WINDOW or
            typeof(ab.get("from_tick")) != TYPE_INT or
            typeof(ab.get("to_tick")) != TYPE_INT or
            ab["from_tick"] != source_end_tick - WINDOW + 1 or
            ab["to_tick"] != source_end_tick):
        return _reject("uncertified_paid_window")
    for report in [distribution, sites]:
        if report.get("time_kind") != "elapsed_wall_not_cpu" or (
                report.get("observed_paid_ticks") != WINDOW or
                report.get("from_tick") != ab["from_tick"] or
                report.get("to_tick") != source_end_tick):
            return _reject("unmatched_source_clock")
    if distribution.get("requires_authoritative_source_clock_confirmation") != true:
        return _reject("missing_source_clock_gate")
    var totals: Variant = distribution.get("phase_total_usec")
    var avgs: Variant = distribution.get("phase_avg_usec")
    var p95: Variant = distribution.get("phase_p95_usec")
    var maxima: Variant = distribution.get("phase_max_usec")
    var calls: Variant = distribution.get("phase_calls")
    var active: Variant = distribution.get("phase_active_paid_ticks")
    var callsites: Variant = sites.get("sites")
    for obj in [totals, avgs, p95, maxima, calls, active, callsites]:
        if not (obj is Dictionary) or obj.size() != PHASES.size():
            return _reject("incomplete_phase_domain")
    var result: Dictionary = {}
    var sum_phase: int = 0
    for phase in PHASES:
        var row: Variant = callsites.get(phase)
        if not (row is Dictionary):
            return _reject("missing_callsite")
        for metric in [totals.get(phase), p95.get(phase), maxima.get(phase),
                calls.get(phase), active.get(phase), row.get("calls"),
                row.get("active_paid_ticks"), row.get("total_usec"),
                row.get("p95_per_call_usec"), row.get("max_per_call_usec")]:
            if typeof(metric) != TYPE_INT or metric < 0 or metric > MAX_USEC * WINDOW:
                return _reject("invalid_phase_metric")
        for metric in [avgs.get(phase), row.get("avg_per_call_usec")]:
            if typeof(metric) not in [TYPE_INT, TYPE_FLOAT] or (
                    not is_finite(float(metric)) or float(metric) < 0.0):
                return _reject("invalid_average")
        var total: int = totals[phase]
        var count: int = calls[phase]
        var active_ticks: int = active[phase]
        if count < 1 or count > WINDOW * 10000 or active_ticks < 1 or (
                active_ticks > WINDOW or active_ticks > count or
                row["calls"] != count or row["active_paid_ticks"] != active_ticks or
                row["total_usec"] != total or
                abs(float(avgs[phase]) - float(total) / WINDOW) > 0.0001 or
                abs(float(row["avg_per_call_usec"]) - float(total) / count) > 0.0001 or
                p95[phase] > maxima[phase] or
                row["p95_per_call_usec"] > row["max_per_call_usec"] or
                row["max_per_call_usec"] > total or maxima[phase] > total):
            return _reject("forged_phase_accounting")
        sum_phase += total
        result[phase] = {"calls": count, "active_paid_ticks": active_ticks,
            "total_usec": total, "avg_per_paid_tick_usec": avgs[phase],
            "p95_per_paid_tick_usec": p95[phase],
            "p95_per_call_usec": row["p95_per_call_usec"]}
    # Phase stopwatch is nested inside paid-step timing; it cannot exceed
    # the wall time of the profiled arm (checkpoint is excluded from both).
    if typeof(ab.get("profiled_total_usec")) != TYPE_INT or (
            ab["profiled_total_usec"] < sum_phase):
        return _reject("phase_exceeds_paid_wall")
    return {"accepted": true, "from_tick": ab["from_tick"],
        "to_tick": source_end_tick, "phase": result,
        "measured_phase_total_usec": sum_phase,
        "unattributed_paid_wall_usec": ab["profiled_total_usec"] - sum_phase,
        "time_kind": "elapsed_wall_not_cpu",
        "parity_required": true, "performance_claim": false}

static func _reject(reason: String) -> Dictionary:
    return {"accepted": false, "reason": reason}
