extends RefCounted
## E-owned real direct/thread boundary gate. No World ownership or fake ticks.
## The caller supplies detached completed N158 checkpoints from both owners.
const ORACLE = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const WINDOW: int = 100

static func verify_boundary(tick: int, direct: Dictionary,
        worker_response: Dictionary) -> Dictionary:
    if tick < 1 or worker_response.get("ok", false) != true or (
            int(worker_response.get("tick", -1)) != tick):
        return {"accepted": false, "reason": "worker_boundary_not_committed"}
    if typeof(worker_response.get("checkpoint", null)) != TYPE_DICTIONARY:
        return {"accepted": false, "reason": "missing_worker_checkpoint"}
    var candidate: Dictionary = worker_response["checkpoint"]
    if typeof(direct.get("tick", null)) != TYPE_INT or (
            typeof(candidate.get("tick", null)) != TYPE_INT or
            int(direct["tick"]) != tick or int(candidate["tick"]) != tick):
        return {"accepted": false, "reason": "source_clock_divergence"}
    var parity: Dictionary = ORACLE.compare(direct, candidate)
    if not parity.get("equal", false):
        return {"accepted": false, "reason": "exact_checkpoint_divergence",
            "difference": parity.get("difference", {})}
    return {"accepted": true, "tick": tick, "exact": true}

static func summarize_window(end_tick: int, samples: Array) -> Dictionary:
    if samples.size() != WINDOW:
        return {"accepted": false, "reason": "incomplete_window"}
    var worker_samples: Array = []
    var direct_total: int = 0
    var direct_times: Array[int] = []
    for i in range(WINDOW):
        var sample: Variant = samples[i]
        if not sample is Dictionary:
            return {"accepted": false, "reason": "invalid_sample"}
        var tick: int = end_tick - WINDOW + 1 + i
        if not METRICS.accept_single_paid_tick_sample(sample, tick - 1, tick):
            return {"accepted": false, "reason": "invalid_paid_tick"}
        if typeof(sample.get("direct_advance_wall_usec", null)) != TYPE_INT or (
                int(sample["direct_advance_wall_usec"]) < 0):
            return {"accepted": false, "reason": "invalid_direct_timing"}
        direct_total += int(sample["direct_advance_wall_usec"])
        direct_times.append(int(sample["direct_advance_wall_usec"]))
        worker_samples.append(sample.duplicate(true))
    var worker: Dictionary = METRICS.bounded_paid_tick_window(worker_samples, end_tick)
    if not worker.get("complete", false) or int(worker.get("observed_paid_ticks", -1)) != WINDOW:
        return {"accepted": false, "reason": "invalid_worker_window"}
    direct_times.sort()
    return {"accepted": true, "from_tick": end_tick - WINDOW + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW,
        "direct_advance_wall_avg_usec": float(direct_total) / float(WINDOW),
        "direct_advance_wall_p95_usec": direct_times[94],
        "worker_advance_wall_avg_usec": worker["advance_wall_avg_usec"],
        "worker_advance_wall_p95_usec": worker["advance_wall_p95_usec"],
        "worker_request_wall_avg_usec": worker["request_wall_avg_usec"],
        "worker_projection_wall_avg_usec": worker["projection_wall_avg_usec"],
        "time_kind": "elapsed_wall_not_cpu",
        "performance_claim": false}

## Compare independently parity-verified early/late windows without treating
## differing source ticks as identical checkpoints or claiming CPU time.
static func compare_late_windows(early: Dictionary, late: Dictionary) -> Dictionary:
    for side in [early, late]:
        if side.get("accepted", false) != true or side.get("time_kind", "") != "elapsed_wall_not_cpu":
            return {"accepted": false, "reason": "unverified_window"}
        if typeof(side.get("from_tick", null)) != TYPE_INT or typeof(side.get("to_tick", null)) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_tick_bounds"}
        if int(side["to_tick"]) - int(side["from_tick"]) != 99 or side.get("observed_paid_ticks", -1) != 100:
            return {"accepted": false, "reason": "incomplete_coverage"}
        for key in ["direct_advance_wall_avg_usec", "worker_advance_wall_avg_usec",
                "worker_request_wall_avg_usec", "worker_projection_wall_avg_usec"]:
            if typeof(side.get(key, null)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(side[key])) or float(side[key]) < 0.0:
                return {"accepted": false, "reason": "invalid_" + key}
        if float(side["worker_request_wall_avg_usec"]) + 0.01 < (
                float(side["worker_advance_wall_avg_usec"]) + float(side["worker_projection_wall_avg_usec"])):
            return {"accepted": false, "reason": "invalid_worker_attribution"}
    if int(early["to_tick"]) >= int(late["from_tick"]):
        return {"accepted": false, "reason": "overlapping_or_reversed_windows"}
    var delta: Dictionary = {}
    for key in ["direct_advance_wall_avg_usec", "worker_advance_wall_avg_usec",
            "worker_request_wall_avg_usec", "worker_projection_wall_avg_usec"]:
        delta[key + "_delta_usec"] = float(late[key]) - float(early[key])
        delta[key + "_ratio"] = (float(late[key]) / float(early[key])
            if float(early[key]) > 0.0 else -1.0)
    return {"accepted": true, "early_end_tick": early["to_tick"],
        "late_end_tick": late["to_tick"], "deltas": delta,
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}
