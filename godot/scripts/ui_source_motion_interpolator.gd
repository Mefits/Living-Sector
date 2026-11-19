extends RefCounted
## Display-only source-snapshot interpolation, modeled on the frozen
## Rust/Bevy InterpPos (prev/curr + frame-time alpha).
## NEVER advance World/Clock, fabricate N14 transit or change N38 snapshots.

static func alpha(start_usec: int, duration_usec: int, now_usec: int) -> float:
    if start_usec < 0 or duration_usec <= 0:
        return 1.0
    return clampf(float(maxi(0, now_usec - start_usec)) /
        float(duration_usec), 0.0, 1.0)

static func sample_duration(previous_usec: int, now_usec: int,
        initial_usec: int = 160000) -> int:
    if previous_usec <= 0 or now_usec <= previous_usec:
        return initial_usec
    # The previous 650ms cap caused visible stops whenever a source tick
    # took >650ms (e.g. ~1.4s near tick 2300). Follow the last *observed*
    # interval with a small jitter reserve, bounded to 3.5s. No prediction
    # beyond the newer authoritative position, no synthetic N39 movement.
    # If source processing exceeds even this interval, hold at the committed
    # endpoint rather than fabricating the next ship/planet location.
    return clampi(ceili(float(now_usec - previous_usec) * 1.15),
        50000, 3500000)

static func orbit_angle(previous: float, current: float,
        fraction: float) -> float:
    if not is_finite(previous) or not is_finite(current):
        return current
    var progress: float = clampf(fraction, 0.0, 1.0)
    # Use the shortest continuous turn across the 0° / 360° seam,
    # e.g. 359 -> 1 travels 2 degrees, not backwards 358 degrees.
    var delta: float = fposmod(current - previous + 180.0, 360.0) - 180.0
    return fposmod(previous + delta * progress, 360.0)

static func transit_position(previous: Variant, current: Variant,
        fraction: float) -> Variant:
    if not valid_xy(current):
        return current
    if not valid_xy(previous):
        return (current as Array).duplicate()
    var start: Array = previous
    var target: Array = current
    var t: float = clampf(fraction, 0.0, 1.0)
    return [lerpf(float(start[0]), float(target[0]), t),
        lerpf(float(start[1]), float(target[1]), t)]

static func valid_xy(value: Variant) -> bool:
    if not (value is Array) or value.size() != 2:
        return false
    for item in value:
        if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or (
                not is_finite(float(item))):
            return false
    return true
