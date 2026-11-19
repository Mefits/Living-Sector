extends RefCounted
## E-owned independent accounting of *real* paid samples at an exact parity
## checkpoint. Retains only scalars; no N39 World, N9 history or sample aliases.
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const WINDOW: int = 100
const FIELDS: Array[String] = ["direct_advance_wall_usec", "advance_wall_usec",
    "projection_wall_usec", "request_wall_usec"]

static func accept(end_tick: int, samples: Array, parity: Dictionary) -> Dictionary:
    if end_tick < WINDOW or samples.size() != WINDOW:
        return {"accepted": false, "reason": "incomplete_window"}
    if parity.get("accepted", false) != true or parity.get("exact", false) != true or (
            typeof(parity.get("tick", null)) != TYPE_INT or parity["tick"] != end_tick):
        return {"accepted": false, "reason": "exact_parity_required"}
    var totals: Dictionary = {}
    var maxima: Dictionary = {}
    for key in FIELDS:
        totals[key] = 0
        maxima[key] = 0
    var worker_overhead: int = 0
    var worker_overhead_max: int = 0
    var direct_vs_worker: int = 0
    var direct_slower: int = 0
    var worker_slower: int = 0
    var ties: int = 0
    for i in range(WINDOW):
        if not (samples[i] is Dictionary):
            return {"accepted": false, "reason": "invalid_sample"}
        var row: Dictionary = samples[i]
        var tick: int = end_tick - WINDOW + i + 1
        if not METRICS.accept_single_paid_tick_sample(row, tick - 1, tick):
            return {"accepted": false, "reason": "source_clock_or_worker_timing"}
        for key in FIELDS:
            if typeof(row.get(key, null)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_" + key}
            var value: int = int(row[key])
            totals[key] += value
            maxima[key] = maxi(int(maxima[key]), value)
        var request: int = int(row["request_wall_usec"])
        var advance: int = int(row["advance_wall_usec"])
        var projection: int = int(row["projection_wall_usec"])
        if request < advance + projection:
            return {"accepted": false, "reason": "worker_request_underflow"}
        var overhead: int = request - advance - projection
        worker_overhead += overhead
        worker_overhead_max = maxi(worker_overhead_max, overhead)
        var direct: int = int(row["direct_advance_wall_usec"])
        direct_vs_worker += direct - advance
        if direct > advance:
            direct_slower += 1
        elif direct < advance:
            worker_slower += 1
        else:
            ties += 1
    if direct_slower + worker_slower + ties != WINDOW:
        return {"accepted": false, "reason": "sample_count_mismatch"}
    return {"accepted": true, "from_tick": end_tick - WINDOW + 1,
        "to_tick": end_tick, "paid_ticks": WINDOW,
        "totals_usec": totals, "maxima_usec": maxima,
        "worker_request_overhead_total_usec": worker_overhead,
        "worker_request_overhead_max_usec": worker_overhead_max,
        "direct_minus_worker_advance_total_usec": direct_vs_worker,
        "direct_slower_ticks": direct_slower, "worker_slower_ticks": worker_slower,
        "equal_ticks": ties, "time_kind": "elapsed_wall_not_cpu",
        "performance_claim": false}

static func compare(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or row.get("time_kind", "") != (
                "elapsed_wall_not_cpu") or row.get("paid_ticks", -1) != WINDOW:
            return {"accepted": false, "reason": "unverified_window"}
        if typeof(row.get("from_tick", null)) != TYPE_INT or (
                typeof(row.get("to_tick", null)) != TYPE_INT or
                row["to_tick"] - row["from_tick"] != WINDOW - 1):
            return {"accepted": false, "reason": "invalid_bounds"}
        if not (row.get("totals_usec") is Dictionary) or not (
                row.get("maxima_usec") is Dictionary):
            return {"accepted": false, "reason": "missing_accounting"}
        if row["totals_usec"].size() != FIELDS.size() or (
                row["maxima_usec"].size() != FIELDS.size()):
            return {"accepted": false, "reason": "unexpected_fields"}
        for key in FIELDS:
            if typeof(row["totals_usec"].get(key)) != TYPE_INT or (
                    typeof(row["maxima_usec"].get(key)) != TYPE_INT):
                return {"accepted": false, "reason": "invalid_" + key}
            if row["maxima_usec"][key] < 0 or (
                    row["totals_usec"][key] < row["maxima_usec"][key] or
                    row["totals_usec"][key] > WINDOW * row["maxima_usec"][key]):
                return {"accepted": false, "reason": "impossible_" + key}
        if row["totals_usec"]["request_wall_usec"] != (
                row["totals_usec"]["advance_wall_usec"] +
                row["totals_usec"]["projection_wall_usec"] +
                row.get("worker_request_overhead_total_usec", -1)):
            return {"accepted": false, "reason": "overhead_accounting_mismatch"}
        if row["totals_usec"]["direct_advance_wall_usec"] - (
                row["totals_usec"]["advance_wall_usec"]) != row.get(
                "direct_minus_worker_advance_total_usec", null):
            return {"accepted": false, "reason": "paired_accounting_mismatch"}
        var count: int = 0
        for key in ["direct_slower_ticks", "worker_slower_ticks", "equal_ticks"]:
            if typeof(row.get(key, null)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_outcome_count"}
            count += int(row[key])
        if count != WINDOW:
            return {"accepted": false, "reason": "outcome_count_mismatch"}
    if early["to_tick"] >= late["from_tick"]:
        return {"accepted": false, "reason": "overlapping_windows"}
    var deltas: Dictionary = {}
    for key in FIELDS:
        deltas[key] = int(late["totals_usec"][key]) - int(early["totals_usec"][key])
    return {"accepted": true, "early_tick": early["to_tick"],
        "late_tick": late["to_tick"], "total_deltas_usec": deltas,
        "overhead_delta_usec": int(late["worker_request_overhead_total_usec"]) -
            int(early["worker_request_overhead_total_usec"]),
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}
