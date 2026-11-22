extends RefCounted
## PERF E: bounded, exact-checkpoint-gated joint size/phase growth evidence.
## Correlation is descriptive, never a claim that a collection caused a slowdown.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]
const SIZES: Array[String] = ["ships", "facilities", "dock_waiting", "contracts",
    "n9_receipts", "source_pending_events"]
const TIME_KIND: String = "elapsed_wall_not_cpu"

static func compare(phase_growth: Dictionary, world_growth: Dictionary,
        source_growth: Dictionary) -> Dictionary:
    if phase_growth.get("accepted", false) != true or (
            phase_growth.get("time_kind", "") != TIME_KIND or
            phase_growth.get("performance_claim", true) != false or
            world_growth.get("accepted", false) != true or
            source_growth.get("accepted", false) != true):
        return {"accepted": false, "reason": "unverified_input"}
    var first: Variant = phase_growth.get("early_end_tick")
    var last: Variant = phase_growth.get("late_end_tick")
    if typeof(first) != TYPE_INT or typeof(last) != TYPE_INT or (
            first not in [100, 300, 600] or last not in [300, 600, 900] or
            last <= first or world_growth.get("from_tick") != first or
            world_growth.get("to_tick") != last or
            source_growth.get("from_tick") != first or
            source_growth.get("to_tick") != last):
        return {"accepted": false, "reason": "unmatched_checkpoints"}
    var wd: Variant = world_growth.get("delta")
    var sd: Variant = source_growth.get("delta")
    if not (wd is Dictionary) or not (sd is Dictionary):
        return {"accepted": false, "reason": "missing_size_delta"}
    var sizes: Dictionary = {}
    for key in SIZES:
        var raw: Variant = (sd.get(key) if key in ["n9_receipts",
            "source_pending_events"] else wd.get(key))
        if typeof(raw) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_size_" + key}
        sizes[key] = raw
    var receipts: Variant = wd.get("receipt_categories")
    if not (receipts is Dictionary):
        return {"accepted": false, "reason": "missing_receipt_categories"}
    var receipt_delta: Dictionary = {}
    for category in receipts:
        if typeof(receipts[category]) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_receipt_category"}
        receipt_delta[str(category)] = receipts[category]
    var deltas: Variant = phase_growth.get("deltas")
    if not (deltas is Dictionary) or deltas.size() != 2:
        return {"accepted": false, "reason": "missing_owner_deltas"}
    var phases: Dictionary = {}
    for side in ["direct", "worker"]:
        var owner: Variant = deltas.get(side)
        if not (owner is Dictionary) or owner.size() != PHASES.size():
            return {"accepted": false, "reason": "incomplete_phase_coverage"}
        var phase_rows: Dictionary = {}
        for phase in PHASES:
            var row: Variant = owner.get(phase)
            if not (row is Dictionary):
                return {"accepted": false, "reason": "missing_phase_" + phase}
            var metrics: Dictionary = {}
            for metric in ["calls", "active_paid_ticks", "total_wall_usec",
                    "per_paid_tick_usec", "per_active_tick_usec", "per_call_usec"]:
                var delta_key: String = metric + "_delta"
                var ratio_key: String = metric + "_ratio"
                if typeof(row.get(delta_key)) not in [TYPE_INT, TYPE_FLOAT] or (
                        typeof(row.get(ratio_key)) not in [TYPE_INT, TYPE_FLOAT] or
                        not is_finite(float(row[delta_key])) or
                        not is_finite(float(row[ratio_key])) or
                        float(row[ratio_key]) < -1.0):
                    return {"accepted": false, "reason": "invalid_phase_" + phase}
                metrics[delta_key] = float(row[delta_key])
                metrics[ratio_key] = float(row[ratio_key])
            phase_rows[phase] = metrics
        phases[side] = phase_rows
    # Calls/cadence are deterministic. A change between windows is legitimate,
    # but both owners must report the same delta on the same seed.
    for phase in PHASES:
        for metric in ["calls_delta", "active_paid_ticks_delta"]:
            if phases["direct"][phase][metric] != phases["worker"][phase][metric]:
                return {"accepted": false, "reason": "cadence_delta_divergence"}
    return {"accepted": true, "from_tick": first, "to_tick": last,
        "size_delta": sizes, "receipt_category_delta": receipt_delta,
        "phase_delta": phases, "time_kind": TIME_KIND,
        "correlation_only": true, "performance_claim": false}
