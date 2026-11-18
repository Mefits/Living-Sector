extends RefCounted
## PERF E: exact paid-source-window report. Input rows are detached scalar data
## captured after authoritative SourceClock advancement; never reads live World.
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const SIZE = preload("res://scripts/sim/phase2/n158_authoritative_size_probe.gd")
const LIMIT: int = 100

static func summarize(end_tick: int, steps: Array, phases: Array,
        world: Dictionary, n9_receipts: int, event_count: int) -> Dictionary:
    if not METRICS.CHECKPOINTS.has(end_tick) or steps.size() != LIMIT:
        return {"valid": false, "reason": "incomplete_paid_window"}
    var samples: Array[int] = []
    var total: int = 0
    for i in range(LIMIT):
        var row: Variant = steps[i]
        if not (row is Dictionary) or typeof(row.get("tick", null)) != TYPE_INT or (
                int(row["tick"]) != end_tick - LIMIT + 1):
            return {"valid": false, "reason": "source_clock_gap"}
        if typeof(row.get("elapsed_usec", null)) != TYPE_INT or int(row["elapsed_usec"]) < 0:
            return {"valid": false, "reason": "invalid_step_duration"}
        samples.append(int(row["elapsed_usec"]))
        total += int(row["elapsed_usec"])
    var phase: Dictionary = METRICS.phase_window(phases, end_tick)
    if phase.is_empty():
        return {"valid": false, "reason": "incomplete_phase_window"}
    var measured: Dictionary = SIZE.measure(end_tick, world)
    if measured.get("valid", false) != true:
        return {"valid": false, "reason": measured.get("reason", "invalid_size")}
    if n9_receipts < 0 or event_count < 0:
        return {"valid": false, "reason": "missing_authoritative_counts"}
    samples.sort()
    return {"valid": true, "from_tick": end_tick - 99, "to_tick": end_tick,
        "paid_ticks": LIMIT, "source_step_wall_avg_usec": float(total) / LIMIT,
        "source_step_wall_p95_usec": samples[94],
        "source_step_wall_max_usec": samples[99],
        "phase": phase.duplicate(true), "world_sizes": measured.duplicate(true),
        "n9_receipts": n9_receipts, "source_events": event_count,
        "time_kind": "elapsed_wall_not_cpu",
        "worker_request_measured": false, "performance_measured": true}

static func validate_pair(earlier: Dictionary, later: Dictionary) -> Dictionary:
    if earlier.get("valid", false) != true or later.get("valid", false) != true:
        return {"valid": false, "reason": "invalid_window"}
    if int(later.get("to_tick", -1)) <= int(earlier.get("to_tick", -1)):
        return {"valid": false, "reason": "non_increasing_tick"}
    if earlier.get("paid_ticks", -1) != LIMIT or later.get("paid_ticks", -1) != LIMIT:
        return {"valid": false, "reason": "incomplete_coverage"}
    if earlier.get("time_kind", "") != "elapsed_wall_not_cpu" or (
            later.get("time_kind", "") != "elapsed_wall_not_cpu"):
        return {"valid": false, "reason": "clock_kind"}
    var delta: Dictionary = {"valid": true, "from_tick": earlier["to_tick"],
        "to_tick": later["to_tick"], "step_wall_avg_delta_usec":
        float(later["source_step_wall_avg_usec"]) - float(earlier["source_step_wall_avg_usec"]),
        "n9_receipts_delta": int(later["n9_receipts"]) - int(earlier["n9_receipts"]),
        "source_events_delta": int(later["source_events"]) - int(earlier["source_events"]),
        "phase_avg_delta_usec": {}}
    for name in ["ships", "dock_queue", "markets", "factions"]:
        if not earlier["phase"]["phase_avg_usec"].has(name) or (
                not later["phase"]["phase_avg_usec"].has(name)):
            return {"valid": false, "reason": "missing_phase_" + name}
        delta["phase_avg_delta_usec"][name] = float(
            later["phase"]["phase_avg_usec"][name]) - float(
            earlier["phase"]["phase_avg_usec"][name])
    return delta
