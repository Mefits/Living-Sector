extends RefCounted
## PERF E: detached wall-clock attribution for one authoritative worker request.
## These are monotonic elapsed microseconds, NOT thread CPU time or GUI FPS.
## A request can advance zero, one, or multiple paid SourceClock ticks.
static func summarize(before_tick: int, after_tick: int,
        request_start_usec: int, advance_end_usec: int,
        projection_end_usec: int) -> Dictionary:
    var paid: int = after_tick - before_tick
    var valid: bool = paid >= 0 and request_start_usec >= 0 and (
        request_start_usec <= advance_end_usec and
        advance_end_usec <= projection_end_usec)
    if not valid:
        return {"valid": false, "paid_ticks": paid}
    var advance_usec: int = advance_end_usec - request_start_usec
    var projection_usec: int = projection_end_usec - advance_end_usec
    var request_usec: int = projection_end_usec - request_start_usec
    return {
        "valid": true,
        "paid_ticks": paid,
        "advance_wall_usec": advance_usec,
        "projection_wall_usec": projection_usec,
        "request_wall_usec": request_usec,
        # A zero-tick request MUST NOT be counted as a paid tick.
        "advance_wall_usec_per_paid_tick": (
            float(advance_usec) / float(paid) if paid > 0 else -1.0)
    }

## Opt-in, constant-memory checkpoint counter. Caller supplies primitive counts
## from the authoritative owner after commit; no World/ledger aliases are retained.
## Windows are exact paid-tick boundaries, not worker request numbers.
const CHECKPOINTS: Array[int] = [100, 300, 600, 900]
const COUNT_KEYS: Array[String] = ["receipts", "contracts", "dock", "events", "ships"]

static func checkpoint_counts(paid_tick: int, counts: Dictionary) -> Dictionary:
    if not CHECKPOINTS.has(paid_tick):
        return {}
    var snapshot: Dictionary = {"paid_tick": paid_tick}
    for key in COUNT_KEYS:
        if not counts.has(key) or typeof(counts[key]) != TYPE_INT or int(counts[key]) < 0:
            return {}
        snapshot[key] = int(counts[key])
    return snapshot

## Compare snapshots without assuming growth is a leak. Negative deltas
## (settlement/cleanup) are valid and must not be clamped.
static func count_delta(earlier: Dictionary, later: Dictionary) -> Dictionary:
    if not earlier.has("paid_tick") or not later.has("paid_tick"):
        return {}
    var start_tick: int = int(earlier["paid_tick"])
    var end_tick: int = int(later["paid_tick"])
    if not CHECKPOINTS.has(start_tick) or not CHECKPOINTS.has(end_tick) or end_tick <= start_tick:
        return {}
    var delta: Dictionary = {"from_tick": start_tick, "to_tick": end_tick}
    for key in COUNT_KEYS:
        if not earlier.has(key) or not later.has(key):
            return {}
        if typeof(earlier[key]) != TYPE_INT or typeof(later[key]) != TYPE_INT:
            return {}
        delta[key] = int(later[key]) - int(earlier[key])
    return delta

## Summarize actual one-paid-tick requests at fixed windows. Requests spanning
## multiple ticks cannot be attributed to an individual source tick; reject them
## rather than silently dividing wall time and calling it CPU time.
## Samples are primitive detached dictionaries, never references to World.
static func bounded_paid_tick_window(samples: Array, end_tick: int) -> Dictionary:
    if not CHECKPOINTS.has(end_tick):
        return {}
    var start_tick: int = maxi(1, end_tick - 99)
    var times: Array[int] = []
    var projection_total: int = 0
    var request_total: int = 0
    var last_tick: int = start_tick - 1
    for sample in samples:
        if typeof(sample) != TYPE_DICTIONARY:
            return {}
        var entry: Dictionary = sample
        if not entry.get("valid", false) or entry.get("paid_ticks", -1) != 1:
            return {}
        if not entry.has("after_tick") or typeof(entry["after_tick"]) != TYPE_INT:
            return {}
        var tick: int = entry["after_tick"]
        if tick <= last_tick or tick < start_tick or tick > end_tick:
            return {}
        for field in ["advance_wall_usec", "projection_wall_usec", "request_wall_usec"]:
            if not entry.has(field) or typeof(entry[field]) != TYPE_INT or entry[field] < 0:
                return {}
        if entry["request_wall_usec"] != entry["advance_wall_usec"] + entry["projection_wall_usec"]:
            return {}
        times.append(entry["advance_wall_usec"])
        projection_total += entry["projection_wall_usec"]
        request_total += entry["request_wall_usec"]
        last_tick = tick
    if times.is_empty():
        return {}
    times.sort()
    var n: int = times.size()
    var p95_index: int = ceili(float(n) * 0.95) - 1
    var advance_total: int = request_total - projection_total
    return {
        "from_tick": start_tick, "to_tick": end_tick,
        "observed_paid_ticks": n, "expected_paid_ticks": end_tick - start_tick + 1,
        "complete": n == end_tick - start_tick + 1 and last_tick == end_tick,
        "advance_wall_avg_usec": float(advance_total) / float(n),
        "advance_wall_p95_usec": times[p95_index],
        "projection_wall_avg_usec": float(projection_total) / float(n),
        "request_wall_avg_usec": float(request_total) / float(n),
        "time_kind": "elapsed_wall_not_cpu"
    }


## Strict same-seed checkpoint comparator for E acceptance. A timing improvement
## is NOT accepted when paid-tick coverage, source checkpoint identity, or
## detached data counts disagree. Timing is wall elapsed, never CPU/FPS.
## Caller supplies immutable scalar checkpoint fingerprints from N38/BT/RNG
## and exact primitive counts, never a live World reference.
static func compare_checkpoint_pair(baseline: Dictionary, candidate: Dictionary) -> Dictionary:
    for field in ["from_tick", "to_tick", "observed_paid_ticks", "expected_paid_ticks",
            "complete", "source_fingerprint", "counts", "advance_wall_avg_usec",
            "projection_wall_avg_usec", "request_wall_avg_usec"]:
        if not baseline.has(field) or not candidate.has(field):
            return {"accepted": false, "reason": "missing_" + field}
    # A missing or placeholder fingerprint must never certify source parity.
    # The caller must supply an authoritative N38/BT/RNG-derived digest.
    for side in [baseline, candidate]:
        if typeof(side["source_fingerprint"]) != TYPE_STRING or String(side["source_fingerprint"]).strip_edges().is_empty():
            return {"accepted": false, "reason": "invalid_source_fingerprint"}
        if side.get("time_kind", "") != "elapsed_wall_not_cpu":
            return {"accepted": false, "reason": "invalid_time_kind"}
        if typeof(side["from_tick"]) != TYPE_INT or typeof(side["to_tick"]) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_tick_boundary"}
        if not CHECKPOINTS.has(int(side["to_tick"])) or int(side["from_tick"]) != maxi(1, int(side["to_tick"]) - 99):
            return {"accepted": false, "reason": "invalid_tick_window"}
        if typeof(side["observed_paid_ticks"]) != TYPE_INT or typeof(side["expected_paid_ticks"]) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_tick_coverage"}
    # A caller-provided complete=true is not evidence of full coverage.
    # Derive the exact 100-tick boundary from the fixed checkpoint window.
    for side in [baseline, candidate]:
        var required_ticks: int = int(side["to_tick"]) - int(side["from_tick"]) + 1
        if required_ticks != 100 or int(side["expected_paid_ticks"]) != required_ticks:
            return {"accepted": false, "reason": "invalid_expected_coverage"}
        if int(side["observed_paid_ticks"]) != required_ticks:
            return {"accepted": false, "reason": "incomplete_coverage"}
    if baseline["complete"] != true or candidate["complete"] != true:
        return {"accepted": false, "reason": "incomplete_window"}
    for field in ["from_tick", "to_tick", "observed_paid_ticks", "expected_paid_ticks",
            "source_fingerprint"]:
        if baseline[field] != candidate[field]:
            return {"accepted": false, "reason": "mismatch_" + field}
    if baseline["observed_paid_ticks"] != baseline["expected_paid_ticks"]:
        return {"accepted": false, "reason": "incomplete_coverage"}
    for side in [baseline, candidate]:
        if typeof(side["counts"]) != TYPE_DICTIONARY:
            return {"accepted": false, "reason": "invalid_counts"}
        for key in COUNT_KEYS:
            if not side["counts"].has(key) or typeof(side["counts"][key]) != TYPE_INT or side["counts"][key] < 0:
                return {"accepted": false, "reason": "invalid_count_" + key}
        for field in ["advance_wall_avg_usec", "projection_wall_avg_usec", "request_wall_avg_usec"]:
            if (typeof(side[field]) != TYPE_FLOAT and typeof(side[field]) != TYPE_INT) or not is_finite(float(side[field])) or float(side[field]) < 0.0:
                return {"accepted": false, "reason": "invalid_time_" + field}
        if absf(float(side["advance_wall_avg_usec"]) + float(side["projection_wall_avg_usec"]) - float(side["request_wall_avg_usec"])) > 0.01:
            return {"accepted": false, "reason": "invalid_attribution"}
    for key in COUNT_KEYS:
        if baseline["counts"][key] != candidate["counts"][key]:
            return {"accepted": false, "reason": "mismatch_count_" + key}
    var old_usec: float = float(baseline["advance_wall_avg_usec"])
    var new_usec: float = float(candidate["advance_wall_avg_usec"])
    return {
        "accepted": true, "reason": "parity_matched",
        "advance_wall_delta_usec": new_usec - old_usec,
        "advance_wall_ratio": (new_usec / old_usec if old_usec > 0.0 else -1.0),
        "projection_wall_delta_usec": float(candidate["projection_wall_avg_usec"]) - float(baseline["projection_wall_avg_usec"]),
        "request_wall_delta_usec": float(candidate["request_wall_avg_usec"]) - float(baseline["request_wall_avg_usec"]),
        "improved": new_usec < old_usec
    }

## Bounded A/C/D phase timing adapter; one row per real paid tick.
static func phase_window(rows: Array, end_tick: int) -> Dictionary:
    if not CHECKPOINTS.has(end_tick) or rows.size() != 100:
        return {}
    var totals: Dictionary = {}
    for i in range(100):
        var row: Variant = rows[i]
        if typeof(row) != TYPE_DICTIONARY or row.get("tick", -1) != end_tick - 99 + i:
            return {}
        for phase in ["ships", "dock_queue", "markets", "factions"]:
            if not row.has(phase) or typeof(row[phase]) != TYPE_INT or int(row[phase]) < 0:
                return {}
            totals[phase] = int(totals.get(phase, 0)) + int(row[phase])
    var averages: Dictionary = {}
    var p95: Dictionary = {}
    var maxima: Dictionary = {}
    # Fixed 100-row window: sort only bounded scalar samples, never World rows.
    # Nearest-rank p95 = sorted[94] for 100 paid ticks.
    for phase in totals:
        averages[phase] = float(totals[phase]) / 100.0
        var durations: Array[int] = []
        for row in rows:
            durations.append(int(row[phase]))
        durations.sort()
        p95[phase] = durations[94]
        maxima[phase] = durations[99]
    return {"from_tick": end_tick - 99, "to_tick": end_tick,
        "observed_paid_ticks": 100, "phase_total_usec": totals,
        "phase_avg_usec": averages, "phase_p95_usec": p95,
        "phase_max_usec": maxima, "time_kind": "elapsed_wall_not_cpu"}
