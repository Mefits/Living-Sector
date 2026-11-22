extends RefCounted
## E-owned post-N38 restart continuation oracle. No retained World references.
const PARITY = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const MAX_STEPS: int = 4

static func accept_step(previous_tick: int, direct_tick: int,
        direct_checkpoint: Dictionary, worker_step: Dictionary,
        worker_checkpoint: Dictionary, direct_usec: int,
        worker_request_usec: int) -> Dictionary:
    var expected: int = previous_tick + 1
    if previous_tick < 1 or direct_tick != expected or (
            typeof(direct_checkpoint.get("tick")) != TYPE_INT or
            int(direct_checkpoint["tick"]) != expected):
        return {"accepted": false, "reason": "direct_source_clock"}
    if worker_step.get("ok", false) != true or (
            worker_step.get("advanced", false) != true or
            typeof(worker_step.get("tick")) != TYPE_INT or
            int(worker_step["tick"]) != expected):
        return {"accepted": false, "reason": "worker_paid_step"}
    if worker_checkpoint.get("ok", false) != true or (
            typeof(worker_checkpoint.get("tick")) != TYPE_INT or
            int(worker_checkpoint["tick"]) != expected):
        return {"accepted": false, "reason": "worker_checkpoint_clock"}
    var candidate: Variant = worker_checkpoint.get("checkpoint")
    if not (candidate is Dictionary) or typeof(candidate.get("tick")) != TYPE_INT or (
            int(candidate["tick"]) != expected):
        return {"accepted": false, "reason": "worker_checkpoint_missing"}
    if direct_usec < 0 or worker_request_usec < 0:
        return {"accepted": false, "reason": "invalid_elapsed"}
    var timing: Variant = worker_step.get("timing")
    if not (timing is Dictionary) or (
            typeof(timing.get("advance_wall_usec")) != TYPE_INT or
            typeof(timing.get("request_wall_usec")) != TYPE_INT or
            typeof(timing.get("projection_wall_usec")) != TYPE_INT):
        return {"accepted": false, "reason": "missing_worker_timing"}
    if int(timing["advance_wall_usec"]) < 0 or int(timing["projection_wall_usec"]) < 0 or (
            int(timing["request_wall_usec"]) < int(timing["advance_wall_usec"]) +
            int(timing["projection_wall_usec"])):
        return {"accepted": false, "reason": "worker_timing_attribution"}
    var parity: Dictionary = PARITY.compare(direct_checkpoint, candidate)
    if parity.get("equal", false) != true:
        return {"accepted": false, "reason": "post_restart_state_divergence",
            "difference": parity.get("difference", {})}
    return {"accepted": true, "tick": expected, "exact": true,
        "direct_wall_usec": direct_usec, "worker_request_wall_usec": worker_request_usec,
        "worker_advance_wall_usec": int(timing["advance_wall_usec"]),
        "time_kind": "elapsed_wall_not_cpu"}

static func summarize(restart_tick: int, rows: Array) -> Dictionary:
    if restart_tick < 1 or rows.is_empty() or rows.size() > MAX_STEPS:
        return {"accepted": false, "reason": "invalid_continuation_length"}
    var direct_total: int = 0
    var worker_total: int = 0
    var worker_advance_total: int = 0
    for i in range(rows.size()):
        var row: Variant = rows[i]
        if not (row is Dictionary) or row.get("accepted", false) != true or (
                row.get("exact", false) != true or
                typeof(row.get("tick")) != TYPE_INT or
                int(row["tick"]) != restart_tick + i + 1 or
                row.get("time_kind", "") != "elapsed_wall_not_cpu"):
            return {"accepted": false, "reason": "incomplete_or_forged_continuation"}
        for key in ["direct_wall_usec", "worker_request_wall_usec", "worker_advance_wall_usec"]:
            if typeof(row.get(key)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_continuation_timing"}
        if int(row["worker_request_wall_usec"]) < int(row["worker_advance_wall_usec"]):
            return {"accepted": false, "reason": "worker_request_underflow"}
        direct_total += int(row["direct_wall_usec"])
        worker_total += int(row["worker_request_wall_usec"])
        worker_advance_total += int(row["worker_advance_wall_usec"])
    return {"accepted": true, "restart_tick": restart_tick,
        "last_paid_tick": restart_tick + rows.size(), "paid_steps": rows.size(),
        "direct_total_wall_usec": direct_total,
        "worker_request_total_wall_usec": worker_total,
        "worker_advance_total_wall_usec": worker_advance_total,
        "exact_parity_each_step": true, "time_kind": "elapsed_wall_not_cpu",
        "performance_claim": false}
