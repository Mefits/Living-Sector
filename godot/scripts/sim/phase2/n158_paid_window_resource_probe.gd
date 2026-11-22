extends RefCounted
## PERF E: bounded per-paid-tick tail latency and shared-process allocator evidence.
## Never call this CPU time, RSS, or per-worker memory: direct and worker share
## one process and allocator. Retain only scalar values, no World or receipts.
const WINDOW: int = 100
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const KEYS: Array[String] = [
    "direct_advance_wall_usec", "advance_wall_usec",
    "request_wall_usec", "projection_wall_usec"]

static func _percentile(sorted: Array[int], numerator: int) -> int:
    return sorted[ceili(float(sorted.size() * numerator) / 100.0) - 1]

static func measure(end_tick: int, samples: Array, parity: Dictionary,
        allocator_bytes: int, allocator_peak_bytes: int) -> Dictionary:
    if end_tick < WINDOW or samples.size() != WINDOW:
        return {"accepted": false, "reason": "incomplete_paid_window"}
    if parity.get("accepted", false) != true or parity.get("exact", false) != true or (
            int(parity.get("tick", -1)) != end_tick):
        return {"accepted": false, "reason": "exact_boundary_required"}
    if allocator_bytes < 0 or allocator_peak_bytes < allocator_bytes:
        return {"accepted": false, "reason": "invalid_allocator_observation"}
    var distributions: Dictionary = {}
    for key in KEYS:
        distributions[key] = []
    for i in range(WINDOW):
        if not (samples[i] is Dictionary):
            return {"accepted": false, "reason": "invalid_sample"}
        var sample: Dictionary = samples[i]
        var tick: int = end_tick - WINDOW + i + 1
        if not METRICS.accept_single_paid_tick_sample(sample, tick - 1, tick):
            return {"accepted": false, "reason": "invalid_source_clock"}
        for key in KEYS:
            if typeof(sample.get(key, null)) != TYPE_INT or int(sample[key]) < 0:
                return {"accepted": false, "reason": "invalid_duration_" + key}
            distributions[key].append(int(sample[key]))
        if int(sample["request_wall_usec"]) < (
                int(sample["advance_wall_usec"]) + int(sample["projection_wall_usec"])):
            return {"accepted": false, "reason": "invalid_request_attribution"}
    var tails: Dictionary = {}
    for key in KEYS:
        var ordered: Array[int] = distributions[key]
        ordered.sort()
        var total: int = 0
        for duration in ordered:
            total += duration
        tails[key] = {"avg_usec": float(total) / WINDOW,
            "p50_usec": _percentile(ordered, 50),
            "p95_usec": _percentile(ordered, 95),
            "p99_usec": _percentile(ordered, 99),
            "max_usec": ordered.back()}
    return {"accepted": true, "from_tick": end_tick - WINDOW + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW,
        "tails": tails, "allocator_static_bytes": allocator_bytes,
        "allocator_peak_bytes": allocator_peak_bytes,
        "memory_kind": "shared_process_engine_static_not_rss",
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}

static func compare(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or row.get("memory_kind", "") != (
                "shared_process_engine_static_not_rss") or row.get("time_kind", "") != (
                "elapsed_wall_not_cpu"):
            return {"accepted": false, "reason": "unverified_evidence"}
        if int(row.get("to_tick", -1)) - int(row.get("from_tick", -1)) != 99 or (
                int(row.get("observed_paid_ticks", -1)) != WINDOW):
            return {"accepted": false, "reason": "invalid_window_bounds"}
        if typeof(row.get("allocator_static_bytes", null)) != TYPE_INT or (
                typeof(row.get("allocator_peak_bytes", null)) != TYPE_INT or
                int(row["allocator_static_bytes"]) < 0 or
                int(row["allocator_peak_bytes"]) < int(row["allocator_static_bytes"])):
            return {"accepted": false, "reason": "invalid_memory"}
        for key in KEYS:
            var stats: Variant = row.get("tails", {}).get(key)
            if not (stats is Dictionary):
                return {"accepted": false, "reason": "missing_tail_" + key}
            var previous: float = -1.0
            for metric in ["p50_usec", "p95_usec", "p99_usec", "max_usec"]:
                if typeof(stats.get(metric, null)) != TYPE_INT or (
                        int(stats[metric]) < previous):
                    return {"accepted": false, "reason": "invalid_tail_" + key}
                previous = float(stats[metric])
            if typeof(stats.get("avg_usec", null)) not in [TYPE_FLOAT, TYPE_INT] or (
                    not is_finite(float(stats["avg_usec"])) or
                    float(stats["avg_usec"]) < 0.0 or
                    float(stats["avg_usec"]) > float(stats["max_usec"])):
                return {"accepted": false, "reason": "invalid_average_" + key}
    if int(early["to_tick"]) >= int(late["from_tick"]):
        return {"accepted": false, "reason": "overlapping_windows"}
    var deltas: Dictionary = {}
    for key in KEYS:
        deltas[key] = {}
        for metric in ["avg_usec", "p50_usec", "p95_usec", "p99_usec", "max_usec"]:
            deltas[key][metric + "_delta"] = (
                float(late["tails"][key][metric]) - float(early["tails"][key][metric]))
    return {"accepted": true, "early_tick": early["to_tick"],
        "late_tick": late["to_tick"], "tail_deltas": deltas,
        "allocator_static_delta_bytes": int(late["allocator_static_bytes"]) -
            int(early["allocator_static_bytes"]),
        "allocator_peak_delta_bytes": int(late["allocator_peak_bytes"]) -
            int(early["allocator_peak_bytes"]),
        "memory_kind": "shared_process_engine_static_not_rss",
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}
