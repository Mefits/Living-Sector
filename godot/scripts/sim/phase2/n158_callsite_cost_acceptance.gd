extends RefCounted
## PERF E: independent bounded callsite evidence, gated by exact N158 checkpoint.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

static func verify(tick: int, exact_gate: Dictionary, direct: Dictionary,
        worker: Dictionary, phase_direct: Dictionary, phase_worker: Dictionary) -> Dictionary:
    if exact_gate.get("accepted", false) != true or int(exact_gate.get("tick", -1)) != tick:
        return {"accepted": false, "reason": "checkpoint_not_exact"}
    if tick < 100 or tick % 100 != 0:
        return {"accepted": false, "reason": "invalid_boundary"}
    for report in [direct, worker]:
        if report.get("time_kind", "") != "elapsed_wall_not_cpu" or (
                report.get("from_tick", -1) != tick - 99 or
                report.get("to_tick", -1) != tick or
                report.get("observed_paid_ticks", -1) != 100):
            return {"accepted": false, "reason": "invalid_window"}
        var sites: Variant = report.get("sites")
        if not (sites is Dictionary) or sites.size() != PHASES.size():
            return {"accepted": false, "reason": "missing_sites"}
    for phase in PHASES:
        for side in range(2):
            var report: Dictionary = direct if side == 0 else worker
            var aggregate: Dictionary = phase_direct if side == 0 else phase_worker
            var site: Variant = report["sites"].get(phase)
            if not (site is Dictionary):
                return {"accepted": false, "reason": "missing_" + phase}
            for key in ["calls", "active_paid_ticks", "total_usec",
                    "p95_per_call_usec", "max_per_call_usec"]:
                if typeof(site.get(key)) != TYPE_INT or int(site[key]) < 0:
                    return {"accepted": false, "reason": "invalid_" + phase + "_" + key}
            if typeof(site.get("avg_per_call_usec")) not in [TYPE_INT, TYPE_FLOAT]:
                return {"accepted": false, "reason": "invalid_average"}
            var n: int = site["calls"]
            var active: int = site["active_paid_ticks"]
            var total: int = site["total_usec"]
            if n < 1 or n > 1000000 or active < 1 or active > 100 or active > n or (
                    site["p95_per_call_usec"] > site["max_per_call_usec"] or
                    site["max_per_call_usec"] > total or
                    not is_finite(float(site["avg_per_call_usec"])) or
                    absf(float(site["avg_per_call_usec"]) * float(n) - float(total)) > 0.01):
                return {"accepted": false, "reason": "invalid_distribution_" + phase}
            if not (aggregate.get("phase_calls") is Dictionary) or not (
                    aggregate.get("phase_total_usec") is Dictionary) or not (
                    aggregate.get("phase_active_paid_ticks") is Dictionary):
                return {"accepted": false, "reason": "missing_aggregate"}
            if aggregate["phase_calls"].get(phase) != n or (
                    aggregate["phase_total_usec"].get(phase) != total or
                    aggregate["phase_active_paid_ticks"].get(phase) != active):
                return {"accepted": false, "reason": "aggregate_divergence_" + phase}
        if direct["sites"][phase]["calls"] != worker["sites"][phase]["calls"] or (
                direct["sites"][phase]["active_paid_ticks"] != worker["sites"][phase]["active_paid_ticks"]):
            return {"accepted": false, "reason": "callsite_cadence_divergence_" + phase}
    return {"accepted": true, "tick": tick, "direct": direct.duplicate(true),
        "worker": worker.duplicate(true), "time_kind": "elapsed_wall_not_cpu",
        "performance_claim": false}
