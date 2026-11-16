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
