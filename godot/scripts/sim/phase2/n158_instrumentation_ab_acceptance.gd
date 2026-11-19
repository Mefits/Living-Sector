extends RefCounted
## E: paired opt-in profiler cost experiment. Callers own two independently
## seeded runtimes. This module never reads or retains authoritative World.
## Each callable advances EXACTLY one real paid tick and returns detached
## checkpoint + measured elapsed microseconds. No skipped/fictional ticks.
const MAX_TICKS: int = 100
const MAX_USEC: int = 60000000

static func run_pair(first_tick: int, count: int, plain_step: Callable,
        profiled_step: Callable, exact_checkpoint: Callable,
        checkpoint_stride: int = 1) -> Dictionary:
    if first_tick < 1 or count < 1 or count > MAX_TICKS or (
            checkpoint_stride < 1 or checkpoint_stride > count or
            not plain_step.is_valid() or not profiled_step.is_valid() or
            not exact_checkpoint.is_valid()):
        return {"accepted": false, "reason": "invalid_configuration"}
    var plain: Array[int] = []
    var profiled: Array[int] = []
    var deltas: Array[int] = []
    var profile_costs: Array[int] = []
    var parity_gates: int = 0
    for i in range(count):
        var tick: int = first_tick + i
        # Alternate execution order to avoid systematically privileging an arm.
        var p: Dictionary
        var q: Dictionary
        if i % 2 == 0:
            p = plain_step.call(tick)
            q = profiled_step.call(tick)
        else:
            q = profiled_step.call(tick)
            p = plain_step.call(tick)
        for arm in [p, q]:
            if arm.get("ok", false) != true or (
                    typeof(arm.get("tick", null)) != TYPE_INT or arm["tick"] != tick):
                return {"accepted": false, "reason": "source_clock_or_failed_tick",
                    "tick": tick}
            for field in ["elapsed_usec", "instrumentation_usec"]:
                if typeof(arm.get(field, null)) != TYPE_INT or (
                        arm[field] < 0 or arm[field] > MAX_USEC):
                    return {"accepted": false, "reason": "invalid_timing", "tick": tick}
        var is_gate: bool = (i + 1) % checkpoint_stride == 0 or i == count - 1
        for arm in [p, q]:
            if is_gate and not (arm.get("checkpoint") is Dictionary):
                return {"accepted": false, "reason": "missing_checkpoint", "tick": tick}
            if not is_gate and arm.has("checkpoint"):
                return {"accepted": false, "reason": "unexpected_checkpoint", "tick": tick}
        if p["instrumentation_usec"] != 0 or (
                q["instrumentation_usec"] > q["elapsed_usec"]):
            return {"accepted": false, "reason": "instrumentation_accounting",
                "tick": tick}
        # Comparator must compare complete detached N38/N39/N9/BT/RNG state,
        # not only a digest, tick, count or selected fields.
        if is_gate:
            if exact_checkpoint.call(p["checkpoint"], q["checkpoint"]) != true:
                return {"accepted": false, "reason": "checkpoint_divergence", "tick": tick}
            parity_gates += 1
        var plain_usec: int = p["elapsed_usec"]
        var profiled_usec: int = q["elapsed_usec"]
        plain.append(plain_usec)
        profiled.append(profiled_usec)
        deltas.append(profiled_usec - plain_usec)
        profile_costs.append(q["instrumentation_usec"])
    var report: Dictionary = _summary(first_tick, plain, profiled, deltas, profile_costs)
    report["checkpoint_stride"] = checkpoint_stride
    report["parity_gates"] = parity_gates
    report["parity_kind"] = "every_paid_tick" if checkpoint_stride == 1 else "periodic_full_state"
    return report

static func _summary(first_tick: int, plain: Array[int], profiled: Array[int],
        deltas: Array[int], profile_costs: Array[int]) -> Dictionary:
    var n: int = deltas.size()
    if n == 0 or n > MAX_TICKS or plain.size() != n or (
            profiled.size() != n or profile_costs.size() != n):
        return {"accepted": false, "reason": "incomplete_samples"}
    var plain_total: int = 0
    var profiled_total: int = 0
    var measured_cost: int = 0
    var positive: int = 0
    for i in range(n):
        plain_total += plain[i]
        profiled_total += profiled[i]
        measured_cost += profile_costs[i]
        if deltas[i] > 0:
            positive += 1
    var sorted_delta: Array[int] = deltas.duplicate()
    sorted_delta.sort()
    return {"accepted": true, "from_tick": first_tick,
        "to_tick": first_tick + n - 1, "paid_ticks": n,
        "plain_total_usec": plain_total, "profiled_total_usec": profiled_total,
        "measured_instrumentation_total_usec": measured_cost,
        "observed_delta_total_usec": profiled_total - plain_total,
        "delta_p50_usec": sorted_delta[int(ceil(n * 0.50)) - 1],
        "delta_p95_usec": sorted_delta[int(ceil(n * 0.95)) - 1],
        "positive_delta_ticks": positive,
        "order": "alternating", "time_kind": "elapsed_wall_not_cpu",
        "performance_claim": false}

static func compare_windows(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or row.get("order", "") != (
                "alternating") or row.get("time_kind", "") != "elapsed_wall_not_cpu":
            return {"accepted": false, "reason": "unverified_arm"}
        if typeof(row.get("from_tick", null)) != TYPE_INT or (
                typeof(row.get("to_tick", null)) != TYPE_INT or
                typeof(row.get("paid_ticks", null)) != TYPE_INT or
                row["paid_ticks"] < 1 or row["paid_ticks"] > MAX_TICKS or
                row["to_tick"] - row["from_tick"] + 1 != row["paid_ticks"]):
            return {"accepted": false, "reason": "invalid_bounds"}
        if row.has("checkpoint_stride"):
            if typeof(row.get("parity_gates", null)) != TYPE_INT or (
                    typeof(row["checkpoint_stride"]) != TYPE_INT or
                    row["checkpoint_stride"] < 1 or
                    row["checkpoint_stride"] > row["paid_ticks"] or
                    row["parity_gates"] != ceili(float(row["paid_ticks"]) / float(row["checkpoint_stride"])):
                return {"accepted": false, "reason": "forged_parity_coverage"}
        for key in ["plain_total_usec", "profiled_total_usec",
                "measured_instrumentation_total_usec", "observed_delta_total_usec"]:
            if typeof(row.get(key, null)) != TYPE_INT:
                return {"accepted": false, "reason": "invalid_totals"}
        if row["plain_total_usec"] < 0 or row["profiled_total_usec"] < 0 or (
                row["measured_instrumentation_total_usec"] < 0 or
                row["observed_delta_total_usec"] !=
                row["profiled_total_usec"] - row["plain_total_usec"]):
            return {"accepted": false, "reason": "forged_accounting"}
    if early["to_tick"] >= late["from_tick"]:
        return {"accepted": false, "reason": "overlapping_windows"}
    return {"accepted": true, "early_tick": early["to_tick"],
        "late_tick": late["to_tick"],
        "overhead_drift_usec": late["observed_delta_total_usec"] -
            early["observed_delta_total_usec"],
        "instrumentation_drift_usec": late["measured_instrumentation_total_usec"] -
            early["measured_instrumentation_total_usec"],
        "performance_claim": false}

## Compares independently seeded, fully completed strict and periodic experiments.
## Neither report's wall-time delta is called CPU cost; this is observation
## contamination evidence, not a speedup claim. Each arm still pays every tick.
static func compare_checkpoint_modes(strict: Array, periodic: Array) -> Dictionary:
    if strict.is_empty() or strict.size() != periodic.size():
        return {"accepted": false, "reason": "incomplete_mode_windows"}
    var rows: Array = []
    var strict_total: int = 0
    var periodic_total: int = 0
    for i in range(strict.size()):
        var a: Dictionary = strict[i]
        var b: Dictionary = periodic[i]
        for report in [a, b]:
            if report.get("accepted", false) != true or (
                    report.get("order", "") != "alternating" or
                    report.get("time_kind", "") != "elapsed_wall_not_cpu"):
                return {"accepted": false, "reason": "unverified_mode", "window": i}
            if typeof(report.get("from_tick", null)) != TYPE_INT or (
                    typeof(report.get("to_tick", null)) != TYPE_INT or
                    typeof(report.get("paid_ticks", null)) != TYPE_INT or
                    report["paid_ticks"] < 1 or report["paid_ticks"] > MAX_TICKS or
                    report["to_tick"] - report["from_tick"] + 1 != report["paid_ticks"]):
                return {"accepted": false, "reason": "invalid_window", "window": i}
            for key in ["plain_total_usec", "profiled_total_usec",
                    "observed_delta_total_usec", "measured_instrumentation_total_usec",
                    "checkpoint_stride", "parity_gates"]:
                if typeof(report.get(key, null)) != TYPE_INT:
                    return {"accepted": false, "reason": "missing_metric", "window": i}
            if report["plain_total_usec"] < 0 or report["profiled_total_usec"] < 0 or (
                    report["measured_instrumentation_total_usec"] < 0 or
                    report["observed_delta_total_usec"] !=
                    report["profiled_total_usec"] - report["plain_total_usec"]):
                return {"accepted": false, "reason": "forged_totals", "window": i}
            var stride: int = report["checkpoint_stride"]
            if stride < 1 or stride > report["paid_ticks"] or (
                    report["parity_gates"] != ceili(float(report["paid_ticks"]) / float(stride))):
                return {"accepted": false, "reason": "forged_gates", "window": i}
        if a["checkpoint_stride"] != 1 or b["checkpoint_stride"] <= 1:
            return {"accepted": false, "reason": "wrong_mode", "window": i}
        if a["from_tick"] != b["from_tick"] or a["to_tick"] != b["to_tick"] or (
                a["paid_ticks"] != b["paid_ticks"]):
            return {"accepted": false, "reason": "different_paid_ticks", "window": i}
        if i > 0 and (strict[i - 1]["to_tick"] >= a["from_tick"] or
                periodic[i - 1]["to_tick"] >= b["from_tick"]):
            return {"accepted": false, "reason": "overlap", "window": i}
        var strict_cost: int = a["plain_total_usec"] + a["profiled_total_usec"]
        var periodic_cost: int = b["plain_total_usec"] + b["profiled_total_usec"]
        strict_total += strict_cost
        periodic_total += periodic_cost
        rows.append({"from_tick": a["from_tick"], "to_tick": a["to_tick"],
            "strict_gates": a["parity_gates"], "periodic_gates": b["parity_gates"],
            "strict_paid_wall_usec": strict_cost,
            "periodic_paid_wall_usec": periodic_cost,
            "paid_wall_difference_usec": strict_cost - periodic_cost,
            "strict_profiler_delta_usec": a["observed_delta_total_usec"],
            "periodic_profiler_delta_usec": b["observed_delta_total_usec"]})
    return {"accepted": true, "windows": rows,
        "strict_paid_wall_usec": strict_total,
        "periodic_paid_wall_usec": periodic_total,
        "paid_wall_difference_usec": strict_total - periodic_total,
        "observation_kind": "independent_sequential_runs_not_cpu",
        "checkpoint_time_excluded": true, "performance_claim": false}
