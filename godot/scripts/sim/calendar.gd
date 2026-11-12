extends RefCounted
## Calendar is a projection of committed simulation steps, never wall-clock time.
## One native time unit is deliberately NOT assumed to equal one game hour.
## Rust orbital advancement uses world_speed / TPS per executed tick.

const DEFAULT_HOURS_PER_NATIVE_UNIT: float = 0.0 # Unknown until Rust balance audit.
const MAX_HOURS_PER_UNIT: float = 1000000.0

var native_time_units: float = 0.0
var hours_per_native_unit: float = DEFAULT_HOURS_PER_NATIVE_UNIT

func set_hours_per_native_unit(value: float) -> bool:
    if not is_finite(value) or value < 0.0 or value > MAX_HOURS_PER_UNIT:
        return false
    hours_per_native_unit = value
    return true

func advance_committed_tick(native_delta: float) -> bool:
    if not is_finite(native_delta) or native_delta < 0.0:
        return false
    if not is_finite(native_time_units + native_delta):
        return false
    native_time_units += native_delta
    return true

func elapsed_hours() -> float:
    if hours_per_native_unit == 0.0:
        return -1.0
    return native_time_units * hours_per_native_unit

func display_text(tick: int) -> String:
    if hours_per_native_unit == 0.0:
        return "Тик %d · нативное время %.4f (часы не откалиброваны)" % [tick, native_time_units]
    var hours: float = elapsed_hours()
    var days: int = int(floor(hours / 24.0))
    return "Тик %d · день %d, час %.2f (калибровка)" % [tick, days, fposmod(hours, 24.0)]

func snapshot() -> Dictionary:
    return {"native_time_units": native_time_units, "hours_per_native_unit": hours_per_native_unit}

func restore(value: Dictionary) -> bool:
    var units: Variant = value.get("native_time_units", null)
    var factor: Variant = value.get("hours_per_native_unit", null)
    if not (units is float or units is int) or not (factor is float or factor is int):
        return false
    if not is_finite(float(units)) or float(units) < 0.0:
        return false
    if not is_finite(float(factor)) or float(factor) < 0.0 or float(factor) > MAX_HOURS_PER_UNIT:
        return false
    native_time_units = float(units)
    hours_per_native_unit = float(factor)
    return true
