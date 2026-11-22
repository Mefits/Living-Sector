extends RefCounted
## PERF E: bounded end-to-end acceptance of two completed N158 source windows.
## No World reads, no live aliases, no simulated ticks. All input snapshots must
## be detached at the same authoritative completed SourceClock boundary.
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const ORACLE = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]

## Rows and request samples must cover exactly the SAME 100 paid ticks.
## Refuse averages of multi-tick worker requests: they cannot prove per-tick cost.
static func capture(end_tick: int, phase_rows: Array, request_rows: Array,
        counts: Dictionary, completed_checkpoint: Dictionary) -> Dictionary:
    if phase_rows.size() != 100 or request_rows.size() != 100:
        return {"valid": false, "reason": "incomplete_source_window"}
    if typeof(completed_checkpoint.get("paid_tick", null)) != TYPE_INT or (
            int(completed_checkpoint["paid_tick"]) != end_tick):
        return {"valid": false, "reason": "checkpoint_tick_mismatch"}
    var phases: Dictionary = METRICS.phase_window(phase_rows, end_tick)
    if phases.is_empty():
        return {"valid": false, "reason": "invalid_phase_window"}
    var requests: Dictionary = METRICS.bounded_paid_tick_window(request_rows, end_tick)
    if requests.is_empty() or requests.get("complete", false) != true:
        return {"valid": false, "reason": "invalid_request_window"}
    if phases["from_tick"] != requests["from_tick"] or (
            phases["to_tick"] != requests["to_tick"]):
        return {"valid": false, "reason": "window_boundary_mismatch"}
    var sizes: Dictionary = METRICS.checkpoint_counts(end_tick, counts)
    if sizes.is_empty():
        return {"valid": false, "reason": "invalid_authoritative_sizes"}
    # Reject caller-owned mutable references. Detached evidence is copied once,
    # at capture; all returned evidence is independent of future caller edits.
    return {"valid": true, "from_tick": phases["from_tick"],
        "to_tick": end_tick, "phases": phases.duplicate(true),
        "requests": requests.duplicate(true), "sizes": sizes.duplicate(true),
        "checkpoint": completed_checkpoint.duplicate(true)}

## Accept a speed comparison ONLY after exact source-state parity, including
## N9/N38/BT/RNG/cargo/contract domains present in the checkpoint.
## Differences in counts are rejected even if an incomplete checkpoint omits
## a corresponding domain. No speedup is claimed from this function.
static func compare(direct: Dictionary, worker: Dictionary) -> Dictionary:
    for side in [direct, worker]:
        if side.get("valid", false) != true:
            return {"accepted": false, "reason": "invalid_capture"}
        if typeof(side.get("checkpoint", null)) != TYPE_DICTIONARY or (
                typeof(side.get("sizes", null)) != TYPE_DICTIONARY):
            return {"accepted": false, "reason": "missing_evidence"}
        if typeof(side.get("phases", null)) != TYPE_DICTIONARY or (
                typeof(side.get("requests", null)) != TYPE_DICTIONARY):
            return {"accepted": false, "reason": "missing_timing"}
        if side.get("from_tick", -1) != side["to_tick"] - 99 or (
                side["requests"].get("complete", false) != true):
            return {"accepted": false, "reason": "incomplete_coverage"}
        if side["requests"].get("observed_paid_ticks", -1) != 100 or (
                side["phases"].get("observed_paid_ticks", -1) != 100):
            return {"accepted": false, "reason": "incomplete_coverage"}
        if side["requests"].get("time_kind", "") != "elapsed_wall_not_cpu" or (
                side["phases"].get("time_kind", "") != "elapsed_wall_not_cpu"):
            return {"accepted": false, "reason": "invalid_clock_kind"}
    if direct["from_tick"] != worker["from_tick"] or direct["to_tick"] != worker["to_tick"]:
        return {"accepted": false, "reason": "different_paid_tick_windows"}
    var parity: Dictionary = ORACLE.compare(direct["checkpoint"], worker["checkpoint"])
    if not parity["equal"]:
        return {"accepted": false, "reason": "checkpoint_divergence",
            "difference": parity["difference"]}
    if direct["sizes"] != worker["sizes"]:
        return {"accepted": false, "reason": "size_divergence"}
    # Revalidate phase summaries rather than trusting caller-supplied values.
    var phases: Dictionary = METRICS.compare_phase_windows(
        direct["phases"], worker["phases"], "exact_checkpoint", "exact_checkpoint")
    if not phases.get("accepted", false):
        return {"accepted": false, "reason": "invalid_phase_distribution",
            "detail": phases.get("reason", "")}
    var old: float = float(direct["requests"].get("advance_wall_avg_usec", -1.0))
    var new: float = float(worker["requests"].get("advance_wall_avg_usec", -1.0))
    if not is_finite(old) or not is_finite(new) or old < 0.0 or new < 0.0:
        return {"accepted": false, "reason": "invalid_advance_time"}
    for side in [direct, worker]:
        var request_avg: float = float(side["requests"].get("request_wall_avg_usec", -1.0))
        var projection_avg: float = float(side["requests"].get("projection_wall_avg_usec", -1.0))
        var advance_avg: float = float(side["requests"].get("advance_wall_avg_usec", -1.0))
        if not is_finite(request_avg) or not is_finite(projection_avg) or (
                request_avg < 0.0 or projection_avg < 0.0 or (
                absf(request_avg - projection_avg - advance_avg) > 0.01)):
            return {"accepted": false, "reason": "invalid_request_attribution"}
    var phase_delta: Dictionary = {}
    for phase in PHASES:
        phase_delta[phase] = float(worker["phases"]["phase_avg_usec"][phase]) - (
            float(direct["phases"]["phase_avg_usec"][phase]))
    return {"accepted": true, "reason": "exact_checkpoint_and_sizes",
        "from_tick": direct["from_tick"], "to_tick": direct["to_tick"],
        "advance_wall_delta_usec": new - old,
        "request_wall_delta_usec": float(worker["requests"]["request_wall_avg_usec"]) - (
            float(direct["requests"]["request_wall_avg_usec"])),
        "phase_avg_delta_usec": phase_delta,
        "time_kind": "elapsed_wall_not_cpu", "performance_measured": false}
