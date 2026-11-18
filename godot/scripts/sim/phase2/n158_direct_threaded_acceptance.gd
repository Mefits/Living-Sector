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

## Detached authoritative N39 size comparison at paid checkpoint boundaries.
## Exact snapshot oracle still checks full state; these counters localize growth.
## N9 journal and event queue are intentionally NOT inferred from World.
static func compare_size_boundary(tick: int, direct: Dictionary,
        worker: Dictionary) -> Dictionary:
    const SIZE = preload("res://scripts/sim/phase2/n158_authoritative_size_probe.gd")
    if not SIZE.CHECKPOINTS.has(tick):
        return {"accepted": false, "reason": "unsupported_size_boundary"}
    var snapshots: Array[Dictionary] = []
    for checkpoint in [direct, worker]:
        if typeof(checkpoint.get("tick", null)) != TYPE_INT or int(checkpoint["tick"]) != tick:
            return {"accepted": false, "reason": "source_tick_mismatch"}
        var native: Variant = checkpoint.get("native_production")
        if not (native is Dictionary) or not (native.get("world") is Dictionary):
            return {"accepted": false, "reason": "missing_detached_world"}
        var measured: Dictionary = SIZE.measure(tick, native["world"])
        if not measured.get("valid", false):
            return {"accepted": false, "reason": str(measured.get("reason", "invalid_size"))}
        snapshots.append(measured)
    var left: Dictionary = snapshots[0]
    var right: Dictionary = snapshots[1]
    # Do not compare only totals: one missing receipt category must be visible.
    for key in ["ships", "facilities", "dock_waiting", "contracts",
            "receipt_categories", "missing"]:
        if left.get(key) != right.get(key):
            return {"accepted": false, "reason": "size_divergence_" + key,
                "direct": left.duplicate(true), "worker": right.duplicate(true)}
    return {"accepted": true, "tick": tick, "counts": left.duplicate(true),
        "n9_and_events_measured": false}

## Compare actual checkpoint counts across independent early/late boundaries.
## Missing categories remain missing; never silently treat absence as zero.
static func compare_size_growth(early: Dictionary, late: Dictionary) -> Dictionary:
    if not early.get("accepted", false) or not late.get("accepted", false):
        return {"accepted": false, "reason": "unverified_size_boundary"}
    var first: int = int(early.get("tick", -1))
    var last: int = int(late.get("tick", -1))
    if first < 1 or last <= first:
        return {"accepted": false, "reason": "non_increasing_boundary"}
    var a: Variant = early.get("counts")
    var b: Variant = late.get("counts")
    if not (a is Dictionary) or not (b is Dictionary):
        return {"accepted": false, "reason": "missing_size_counts"}
    if not (a.get("receipt_categories") is Dictionary) or not (
            b.get("receipt_categories") is Dictionary):
        return {"accepted": false, "reason": "invalid_receipt_categories"}
    if a.get("missing", []) != b.get("missing", []):
        return {"accepted": false, "reason": "changed_size_coverage"}
    var delta: Dictionary = {}
    for key in ["ships", "facilities", "dock_waiting", "contracts"]:
        if typeof(a.get(key, null)) != TYPE_INT or typeof(b.get(key, null)) != TYPE_INT:
            return {"accepted": false, "reason": "missing_count_" + key}
        delta[key] = int(b[key]) - int(a[key])
    var receipts: Dictionary = {}
    var ac: Dictionary = a["receipt_categories"]
    var bc: Dictionary = b["receipt_categories"]
    if ac.keys().size() != bc.keys().size():
        return {"accepted": false, "reason": "changed_receipt_coverage"}
    for key in ac:
        if not bc.has(key) or typeof(ac[key]) != TYPE_INT or typeof(bc[key]) != TYPE_INT:
            return {"accepted": false, "reason": "changed_receipt_coverage"}
        receipts[key] = int(bc[key]) - int(ac[key])
    delta["receipt_categories"] = receipts
    return {"accepted": true, "from_tick": first, "to_tick": last,
        "delta": delta, "n9_and_events_measured": false}

## N9 and Source events live in the N158 checkpoint envelope, not N39 World.
## Read only detached committed snapshots. No historical journal copies beyond
## the checkpoint already required for exact direct/thread parity.
static func source_growth_counts(tick: int, checkpoint: Dictionary) -> Dictionary:
    if tick not in [100, 300, 600, 900] or typeof(checkpoint.get("tick")) != TYPE_INT or int(checkpoint["tick"]) != tick:
        return {"valid": false, "reason": "invalid_source_tick"}
    var native: Variant = checkpoint.get("native_production")
    if not (native is Dictionary):
        return {"valid": false, "reason": "missing_native_checkpoint"}
    var ledger: Variant = native.get("ledger")
    if not (ledger is Dictionary):
        return {"valid": false, "reason": "missing_n9_ledger"}
    var receipts: Variant = ledger.get("receipts")
    if not (receipts is Array) and not (receipts is Dictionary):
        return {"valid": false, "reason": "invalid_n9_receipts"}
    var event_state: Variant = checkpoint.get("events")
    if not (event_state is Dictionary):
        return {"valid": false, "reason": "missing_source_events"}
    var pending: Variant = event_state.get("pending")
    if not (pending is Array):
        return {"valid": false, "reason": "invalid_pending_events"}
    for receipt in (receipts.values() if receipts is Dictionary else receipts):
        if not (receipt is Dictionary):
            return {"valid": false, "reason": "malformed_n9_receipt"}
    for event in pending:
        if not (event is Dictionary):
            return {"valid": false, "reason": "malformed_source_event"}
    return {"valid": true, "tick": tick, "n9_receipts": receipts.size(),
        "source_pending_events": pending.size()}

static func compare_source_growth_boundary(tick: int, direct: Dictionary,
        worker: Dictionary) -> Dictionary:
    var left: Dictionary = source_growth_counts(tick, direct)
    var right: Dictionary = source_growth_counts(tick, worker)
    if not left.get("valid", false):
        return {"accepted": false, "reason": "direct_" + str(left.get("reason", "invalid"))}
    if not right.get("valid", false):
        return {"accepted": false, "reason": "worker_" + str(right.get("reason", "invalid"))}
    if left != right:
        return {"accepted": false, "reason": "source_size_divergence",
            "direct": left, "worker": right}
    return {"accepted": true, "tick": tick, "counts": left.duplicate(true)}

static func compare_source_growth(early: Dictionary, late: Dictionary) -> Dictionary:
    if not early.get("accepted", false) or not late.get("accepted", false):
        return {"accepted": false, "reason": "unverified_source_boundary"}
    var a: Variant = early.get("counts")
    var b: Variant = late.get("counts")
    if not (a is Dictionary) or not (b is Dictionary) or not a.get("valid", false) or not b.get("valid", false):
        return {"accepted": false, "reason": "missing_source_counts"}
    if typeof(a.get("tick")) != TYPE_INT or typeof(b.get("tick")) != TYPE_INT or (
            int(a["tick"]) >= int(b["tick"]) or
            int(a["tick"]) != int(early.get("tick", -1)) or
            int(b["tick"]) != int(late.get("tick", -1))):
        return {"accepted": false, "reason": "invalid_source_growth_ticks"}
    var delta: Dictionary = {}
    for key in ["n9_receipts", "source_pending_events"]:
        if typeof(a.get(key)) != TYPE_INT or typeof(b.get(key)) != TYPE_INT or (
                int(a[key]) < 0 or int(b[key]) < 0):
            return {"accepted": false, "reason": "invalid_count_" + key}
        delta[key] = int(b[key]) - int(a[key])
    return {"accepted": true, "from_tick": a["tick"], "to_tick": b["tick"],
        "delta": delta, "counts_early": a.duplicate(true),
        "counts_late": b.duplicate(true)}


## Observation cost is outside the paid-tick timing sample. The worker value
## includes FIFO/answer polling and is NOT worker thread CPU time. A checkpoint
## is intentionally requested only at milestone boundaries, not on every tick.
static func checkpoint_observation_sample(tick: int, direct_usec: int,
        worker_request_usec: int, direct_checkpoint: Dictionary,
        worker_response: Dictionary) -> Dictionary:
    if tick < 1 or direct_usec < 0 or worker_request_usec < 0:
        return {"accepted": false, "reason": "invalid_observation_duration"}
    if typeof(direct_checkpoint.get("tick", null)) != TYPE_INT or (
            int(direct_checkpoint["tick"]) != tick):
        return {"accepted": false, "reason": "direct_checkpoint_tick"}
    var parity: Dictionary = verify_boundary(tick, direct_checkpoint, worker_response)
    if not parity.get("accepted", false):
        return {"accepted": false, "reason": "checkpoint_parity",
            "difference": parity.get("difference", {})}
    return {"accepted": true, "tick": tick,
        "direct_checkpoint_wall_usec": direct_usec,
        "worker_checkpoint_request_wall_usec": worker_request_usec,
        "time_kind": "elapsed_wall_not_cpu",
        "included_in_paid_tick_window": false}

## A bounded report from exact checkpoints, with no World references retained.
## Missing milestones, duplicates, nonmonotonic ticks, and forged timing are
## rejected rather than misrepresented as measurement evidence.
static func summarize_checkpoint_observations(samples: Array,
        expected_ticks: Array[int]) -> Dictionary:
    if samples.size() != expected_ticks.size() or samples.is_empty() or (
            samples.size() > 8):
        return {"accepted": false, "reason": "incomplete_observations"}
    var direct_total: int = 0
    var worker_total: int = 0
    var direct_max: int = 0
    var worker_max: int = 0
    var detached: Array = []
    var previous: int = -1
    for i in range(samples.size()):
        if typeof(samples[i]) != TYPE_DICTIONARY:
            return {"accepted": false, "reason": "invalid_observation"}
        var row: Dictionary = samples[i]
        var tick: int = expected_ticks[i]
        if tick <= previous or typeof(row.get("tick", null)) != TYPE_INT or (
                int(row["tick"]) != tick or row.get("accepted", false) != true):
            return {"accepted": false, "reason": "observation_boundary"}
        if row.get("time_kind", "") != "elapsed_wall_not_cpu" or (
                row.get("included_in_paid_tick_window", true) != false):
            return {"accepted": false, "reason": "observation_attribution"}
        for key in ["direct_checkpoint_wall_usec", "worker_checkpoint_request_wall_usec"]:
            if typeof(row.get(key, null)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_" + key}
        var d: int = int(row["direct_checkpoint_wall_usec"])
        var w: int = int(row["worker_checkpoint_request_wall_usec"])
        direct_total += d
        worker_total += w
        direct_max = maxi(direct_max, d)
        worker_max = maxi(worker_max, w)
        detached.append({"tick": tick, "direct_usec": d, "worker_request_usec": w})
        previous = tick
    return {"accepted": true, "count": samples.size(), "milestones": detached,
        "direct_total_wall_usec": direct_total, "worker_request_total_wall_usec": worker_total,
        "direct_max_wall_usec": direct_max, "worker_request_max_wall_usec": worker_max,
        "time_kind": "elapsed_wall_not_cpu",
        "included_in_paid_tick_window": false,
        "performance_claim": false}

## Only exact completed source checkpoints authorize phase attribution. Timing
## distributions may differ across threads; the authoritative state may not.
## Reject forged phase totals exceeding the measured full paid-tick advance.
static func verify_paid_phase_pair(tick: int, direct_checkpoint: Dictionary,
        worker_response: Dictionary, direct_phase: Dictionary,
        paid_window: Dictionary) -> Dictionary:
    var boundary: Dictionary = verify_boundary(tick, direct_checkpoint, worker_response)
    if not boundary.get("accepted", false):
        return {"accepted": false, "reason": "source_parity_unverified",
            "difference": boundary.get("difference", {})}
    if typeof(worker_response.get("paid_phase_window", null)) != TYPE_DICTIONARY:
        return {"accepted": false, "reason": "missing_worker_phases"}
    var worker_phase: Dictionary = worker_response["paid_phase_window"]
    if paid_window.get("accepted", false) != true or (
            int(paid_window.get("to_tick", -1)) != tick or
            int(paid_window.get("observed_paid_ticks", -1)) != 100):
        return {"accepted": false, "reason": "paid_window_unverified"}
    # compare_phase_windows validates all four phase distributions, exact
    # 100-paid-tick bounds and their nearest-rank p95 arithmetic.
    var comparison: Dictionary = METRICS.compare_phase_windows(
        direct_phase, worker_phase, "checkpoint_exact", "checkpoint_exact")
    if not comparison.get("accepted", false):
        return {"accepted": false, "reason": "phase_distribution_invalid",
            "detail": comparison}
    var cadence: Dictionary = compare_phase_callsite_coverage(direct_phase, worker_phase)
    if not cadence.get("accepted", false):
        return {"accepted": false, "reason": "phase_cadence_divergence",
            "detail": cadence}
    var total_direct: int = 0
    var total_worker: int = 0
    for phase in ["ships", "dock_queue", "markets", "factions"]:
        total_direct += int(direct_phase["phase_total_usec"][phase])
        total_worker += int(worker_phase["phase_total_usec"][phase])
    # Monotonic wall clocks around each paid advance enclose phase calls.
    # No fake CPU attribution: both are elapsed wall measurements.
    var direct_limit: float = float(paid_window.get(
        "direct_advance_wall_avg_usec", -1.0)) * 100.0
    var worker_limit: float = float(paid_window.get(
        "worker_advance_wall_avg_usec", -1.0)) * 100.0
    if total_direct > direct_limit + 100.0 or total_worker > worker_limit + 100.0:
        return {"accepted": false, "reason": "phase_exceeds_paid_advance"}
    return {"accepted": true, "tick": tick,
        "phase_comparison": comparison.duplicate(true),
        "callsite_coverage": cadence.duplicate(true),
        "direct_phase": direct_phase.duplicate(true),
        "worker_phase": worker_phase.duplicate(true),
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}

## Counts are source-phase invocations, not paid ticks. A cadence-skipped
## phase contributes zero time and zero calls; direct/thread call counts must
## match on the same seed even though elapsed durations may differ.
static func compare_phase_callsite_coverage(direct: Dictionary,
        worker: Dictionary) -> Dictionary:
    var reports: Array = [direct, worker]
    var keys: Array[String] = ["ships", "dock_queue", "markets", "factions"]
    for report in reports:
        if report.get("observed_paid_ticks", -1) != 100:
            return {"accepted": false, "reason": "unverified_paid_coverage"}
        var calls: Variant = report.get("phase_calls")
        var active: Variant = report.get("phase_active_paid_ticks")
        var totals: Variant = report.get("phase_total_usec")
        if not (calls is Dictionary) or not (active is Dictionary) or not (totals is Dictionary):
            return {"accepted": false, "reason": "missing_callsite_counts"}
        if calls.size() != keys.size() or active.size() != keys.size() or totals.size() != keys.size():
            return {"accepted": false, "reason": "unexpected_callsite_keys"}
        for phase in keys:
            if typeof(calls.get(phase)) != TYPE_INT or typeof(active.get(phase)) != TYPE_INT or (
                    typeof(totals.get(phase)) != TYPE_INT):
                return {"accepted": false, "reason": "invalid_callsite_type"}
            var n: int = calls[phase]
            var used: int = active[phase]
            if n < 1 or n > 10000 or used < 1 or used > 100 or used > n or (
                    int(totals[phase]) < 0):
                return {"accepted": false, "reason": "invalid_callsite_coverage"}
    for phase in keys:
        if direct["phase_calls"][phase] != worker["phase_calls"][phase] or (
                direct["phase_active_paid_ticks"][phase] != worker["phase_active_paid_ticks"][phase]):
            return {"accepted": false, "reason": "cadence_mismatch_" + phase}
    return {"accepted": true, "observed_paid_ticks": 100,
        "phase_calls": direct["phase_calls"].duplicate(true),
        "phase_active_paid_ticks": direct["phase_active_paid_ticks"].duplicate(true),
        "time_kind": "elapsed_wall_not_cpu"}
