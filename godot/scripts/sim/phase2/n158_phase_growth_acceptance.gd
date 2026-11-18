extends RefCounted
## PERF E: compare independent, exact-checkpoint-gated phase windows.
## Only scalar detached evidence; no World, checkpoint, or worker ownership.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]
const WINDOW: int = 100
const TIME_KIND: String = "elapsed_wall_not_cpu"

static func accept_window(end_tick: int, gate: Dictionary) -> Dictionary:
    if end_tick < WINDOW or gate.get("accepted", false) != true or (
            gate.get("tick", -1) != end_tick or gate.get("time_kind", "") != TIME_KIND):
        return {"accepted": false, "reason": "unverified_checkpoint_gate"}
    var sides: Dictionary = {}
    for side in ["direct", "worker"]:
        var report: Variant = gate.get(side + "_phase")
        if not (report is Dictionary) or (
                report.get("from_tick", -1) != end_tick - WINDOW + 1 or
                report.get("to_tick", -1) != end_tick or
                report.get("observed_paid_ticks", -1) != WINDOW or
                report.get("time_kind", "") != TIME_KIND):
            return {"accepted": false, "reason": "invalid_" + side + "_bounds"}
        var totals: Variant = report.get("phase_total_usec")
        var calls: Variant = report.get("phase_calls")
        var active: Variant = report.get("phase_active_paid_ticks")
        var averages: Variant = report.get("phase_avg_usec")
        var p95: Variant = report.get("phase_p95_usec")
        var maxima: Variant = report.get("phase_max_usec")
        var dictionaries: Array = [totals, calls, active, averages, p95, maxima]
        for dictionary in dictionaries:
            if not (dictionary is Dictionary) or dictionary.size() != PHASES.size():
                return {"accepted": false, "reason": "missing_" + side + "_phase_fields"}
        var compact: Dictionary = {}
        for phase in PHASES:
            for dictionary in dictionaries:
                if not dictionary.has(phase):
                    return {"accepted": false, "reason": "missing_" + phase}
            if typeof(totals[phase]) != TYPE_INT or typeof(calls[phase]) != TYPE_INT or (
                    typeof(active[phase]) != TYPE_INT or typeof(p95[phase]) != TYPE_INT or
                    typeof(maxima[phase]) != TYPE_INT or
                    typeof(averages[phase]) not in [TYPE_FLOAT, TYPE_INT]):
                return {"accepted": false, "reason": "invalid_" + phase + "_types"}
            var total: int = totals[phase]
            var count: int = calls[phase]
            var used: int = active[phase]
            var percentile: int = p95[phase]
            var maximum: int = maxima[phase]
            var average: float = float(averages[phase])
            if total < 0 or count < 1 or count > 10000 or used < 1 or used > WINDOW or (
                    used > count or percentile < 0 or maximum < percentile or
                    maximum > total or not is_finite(average) or average < 0.0 or
                    absf(average * WINDOW - float(total)) > 0.01):
                return {"accepted": false, "reason": "invalid_" + phase + "_statistics"}
            compact[phase] = {
                "calls": count, "active_paid_ticks": used,
                "total_wall_usec": total, "p95_paid_tick_usec": percentile,
                "max_paid_tick_usec": maximum,
                "per_paid_tick_usec": float(total) / WINDOW,
                "per_active_tick_usec": float(total) / float(used),
                "per_call_usec": float(total) / float(count)}
        sides[side] = compact
    for phase in PHASES:
        if sides["direct"][phase]["calls"] != sides["worker"][phase]["calls"] or (
                sides["direct"][phase]["active_paid_ticks"] != sides["worker"][phase]["active_paid_ticks"]):
            return {"accepted": false, "reason": "cadence_divergence_" + phase}
    return {"accepted": true, "from_tick": end_tick - WINDOW + 1,
        "to_tick": end_tick, "direct": sides["direct"], "worker": sides["worker"],
        "time_kind": TIME_KIND, "performance_claim": false}

static func compare(early: Dictionary, late: Dictionary) -> Dictionary:
    if early.get("accepted", false) != true or late.get("accepted", false) != true or (
            early.get("time_kind", "") != TIME_KIND or late.get("time_kind", "") != TIME_KIND or
            typeof(early.get("from_tick")) != TYPE_INT or
            typeof(early.get("to_tick")) != TYPE_INT or
            typeof(late.get("from_tick")) != TYPE_INT or
            typeof(late.get("to_tick")) != TYPE_INT or
            early["to_tick"] - early["from_tick"] != WINDOW - 1 or
            late["to_tick"] - late["from_tick"] != WINDOW - 1 or
            early["to_tick"] >= late["from_tick"]):
        return {"accepted": false, "reason": "invalid_independent_windows"}
    var deltas: Dictionary = {}
    for side in ["direct", "worker"]:
        if not (early.get(side) is Dictionary) or not (late.get(side) is Dictionary) or (
                early[side].size() != PHASES.size() or late[side].size() != PHASES.size()):
            return {"accepted": false, "reason": "missing_" + side + "_coverage"}
        var per_phase: Dictionary = {}
        for phase in PHASES:
            var a: Variant = early[side].get(phase)
            var b: Variant = late[side].get(phase)
            if not (a is Dictionary) or not (b is Dictionary):
                return {"accepted": false, "reason": "missing_" + phase}
            for sample in [a, b]:
                for key in ["calls", "active_paid_ticks", "total_wall_usec",
                        "per_paid_tick_usec", "per_active_tick_usec", "per_call_usec"]:
                    if not sample.has(key) or typeof(sample[key]) not in [TYPE_INT, TYPE_FLOAT] or (
                            not is_finite(float(sample[key])) or float(sample[key]) < 0.0):
                        return {"accepted": false, "reason": "invalid_" + phase + "_" + key}
                if int(sample["calls"]) < 1 or int(sample["active_paid_ticks"]) < 1 or (
                        int(sample["active_paid_ticks"]) > WINDOW or
                        int(sample["calls"]) < int(sample["active_paid_ticks"]) or
                        absf(float(sample["total_wall_usec"]) / float(sample["calls"]) -
                            float(sample["per_call_usec"])) > 0.01 or
                        absf(float(sample["total_wall_usec"]) / WINDOW -
                            float(sample["per_paid_tick_usec"])) > 0.01):
                    return {"accepted": false, "reason": "inconsistent_" + phase}
            var values: Dictionary = {}
            for key in ["calls", "active_paid_ticks", "total_wall_usec",
                    "per_paid_tick_usec", "per_active_tick_usec", "per_call_usec"]:
                values[key + "_delta"] = float(b[key]) - float(a[key])
                values[key + "_ratio"] = (float(b[key]) / float(a[key])
                    if float(a[key]) > 0.0 else -1.0)
            per_phase[phase] = values
        deltas[side] = per_phase
    for phase in PHASES:
        for boundary in [early, late]:
            if boundary["direct"][phase]["calls"] != boundary["worker"][phase]["calls"] or (
                    boundary["direct"][phase]["active_paid_ticks"] !=
                    boundary["worker"][phase]["active_paid_ticks"]):
                return {"accepted": false, "reason": "cross_owner_cadence_" + phase}
    return {"accepted": true, "early_end_tick": early["to_tick"],
        "late_end_tick": late["to_tick"], "deltas": deltas,
        "time_kind": TIME_KIND, "performance_claim": false}
