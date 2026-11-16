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
