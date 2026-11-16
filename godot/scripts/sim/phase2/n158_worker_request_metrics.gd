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
