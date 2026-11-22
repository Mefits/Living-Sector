extends RefCounted
## PERF E: paired same-seed elapsed-time evidence from real paid tick boundaries.
## This is NOT CPU time or a speedup claim. One 100-tick scalar window only.
## A worker request includes scheduling/polling; advance is measured separately.
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const WINDOW: int = 100
const MAX_DURATION_USEC: int = 600000000
const FIELDS: Array[String] = ["direct_advance_wall_usec", "advance_wall_usec",
    "request_wall_usec", "projection_wall_usec"]

static func _tail(values: Array[int], percentile: int) -> int:
    values.sort()
    return values[ceili(float(values.size() * percentile) / 100.0) - 1]

static func accept(end_tick: int, samples: Array, parity: Dictionary) -> Dictionary:
    if end_tick < WINDOW or samples.size() != WINDOW:
        return {"accepted": false, "reason": "incomplete_paid_window"}
    if parity.get("accepted", false) != true or parity.get("exact", false) != true or (
            typeof(parity.get("tick")) != TYPE_INT or int(parity["tick"]) != end_tick):
        return {"accepted": false, "reason": "exact_checkpoint_required"}
    var direct_total: int = 0
    var worker_total: int = 0
    var request_total: int = 0
    var projection_total: int = 0
    var deltas: Array[int] = []
    var request_overhead: Array[int] = []
    var worker_slower: int = 0
    var direct_slower: int = 0
    var equal_ticks: int = 0
    var first_half_delta: int = 0
    var second_half_delta: int = 0
    var max_abs_delta: int = 0
    for i in range(WINDOW):
        if not (samples[i] is Dictionary):
            return {"accepted": false, "reason": "invalid_sample"}
        var row: Dictionary = samples[i]
        var tick: int = end_tick - WINDOW + i + 1
        if not METRICS.accept_single_paid_tick_sample(row, tick - 1, tick):
            return {"accepted": false, "reason": "source_clock_mismatch"}
        for key in FIELDS:
            if typeof(row.get(key)) != TYPE_INT or int(row[key]) < 0 or (
                    int(row[key]) > MAX_DURATION_USEC):
                return {"accepted": false, "reason": "invalid_duration_" + key}
        var direct_usec: int = row["direct_advance_wall_usec"]
        var worker_usec: int = row["advance_wall_usec"]
        var request_usec: int = row["request_wall_usec"]
        var projection_usec: int = row["projection_wall_usec"]
        if request_usec < worker_usec + projection_usec:
            return {"accepted": false, "reason": "request_underreports_work"}
        var delta: int = worker_usec - direct_usec
        deltas.append(delta)
        request_overhead.append(request_usec - worker_usec - projection_usec)
        direct_total += direct_usec
        worker_total += worker_usec
        request_total += request_usec
        projection_total += projection_usec
        max_abs_delta = maxi(max_abs_delta, absi(delta))
        if delta > 0:
            worker_slower += 1
        elif delta < 0:
            direct_slower += 1
        else:
            equal_ticks += 1
        if i < WINDOW / 2:
            first_half_delta += delta
        else:
            second_half_delta += delta
    var median_delta: int = _tail(deltas, 50)
    var p95_delta: int = _tail(deltas, 95)
    var p95_request_overhead: int = _tail(request_overhead, 95)
    return {"accepted": true, "from_tick": end_tick - WINDOW + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW,
        "direct_total_usec": direct_total, "worker_total_usec": worker_total,
        "request_total_usec": request_total, "projection_total_usec": projection_total,
        "paired_delta_total_usec": worker_total - direct_total,
        "paired_delta_median_usec": median_delta,
        "paired_delta_p95_usec": p95_delta,
        "paired_delta_max_abs_usec": max_abs_delta,
        "request_unattributed_total_usec": request_total - worker_total - projection_total,
        "request_unattributed_p95_usec": p95_request_overhead,
        "worker_slower_ticks": worker_slower, "direct_slower_ticks": direct_slower,
        "equal_ticks": equal_ticks,
        "first_half_delta_total_usec": first_half_delta,
        "second_half_delta_total_usec": second_half_delta,
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}

static func compare(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or row.get("time_kind", "") != (
                "elapsed_wall_not_cpu") or row.get("performance_claim", true) != false:
            return {"accepted": false, "reason": "unverified_window"}
        if typeof(row.get("from_tick")) != TYPE_INT or (
                typeof(row.get("to_tick")) != TYPE_INT or
                int(row["to_tick"]) - int(row["from_tick"]) != WINDOW - 1 or
                row.get("observed_paid_ticks") != WINDOW):
            return {"accepted": false, "reason": "invalid_window_bounds"}
        for key in ["direct_total_usec", "worker_total_usec", "request_total_usec",
                "projection_total_usec", "request_unattributed_total_usec",
                "request_unattributed_p95_usec", "paired_delta_max_abs_usec",
                "worker_slower_ticks", "direct_slower_ticks", "equal_ticks"]:
            if typeof(row.get(key)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_" + key}
        for key in ["paired_delta_total_usec", "paired_delta_median_usec",
                "paired_delta_p95_usec", "first_half_delta_total_usec",
                "second_half_delta_total_usec"]:
            if typeof(row.get(key)) != TYPE_INT:
                return {"accepted": false, "reason": "invalid_" + key}
        if int(row["worker_slower_ticks"]) + int(row["direct_slower_ticks"]) + (
                int(row["equal_ticks"])) != WINDOW or (
                int(row["paired_delta_total_usec"]) != int(row["worker_total_usec"]) -
                    int(row["direct_total_usec"]) or
                int(row["paired_delta_total_usec"]) != int(row["first_half_delta_total_usec"]) +
                    int(row["second_half_delta_total_usec"]) or
                int(row["request_unattributed_total_usec"]) != int(row["request_total_usec"]) -
                    int(row["worker_total_usec"]) - int(row["projection_total_usec"]) or
                int(row["request_unattributed_total_usec"]) < 0 or
                int(row["paired_delta_median_usec"]) > int(row["paired_delta_p95_usec"]) or
                absi(int(row["paired_delta_p95_usec"])) > int(row["paired_delta_max_abs_usec"])):
            return {"accepted": false, "reason": "forged_pair_attribution"}
    if int(early["to_tick"]) >= int(late["from_tick"]):
        return {"accepted": false, "reason": "overlapping_windows"}
    return {"accepted": true, "early_end_tick": early["to_tick"],
        "late_end_tick": late["to_tick"],
        "paired_total_delta_change_usec": int(late["paired_delta_total_usec"]) -
            int(early["paired_delta_total_usec"]),
        "paired_p95_delta_change_usec": int(late["paired_delta_p95_usec"]) -
            int(early["paired_delta_p95_usec"]),
        "request_overhead_change_usec": int(late["request_unattributed_total_usec"]) -
            int(early["request_unattributed_total_usec"]),
        "worker_slower_tick_change": int(late["worker_slower_ticks"]) -
            int(early["worker_slower_ticks"]),
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}
