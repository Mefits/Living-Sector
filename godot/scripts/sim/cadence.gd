extends RefCounted
## Tick-based phase cadence, independent of FPS and world_speed.
## Future phase implementations must explicitly opt in; this does not
## invent Rust production/market periodicity or invoke placeholder systems.

var _rules: Dictionary = {}

func configure(phase: String, period_ticks: int, offset_ticks: int = 0) -> bool:
    if phase.is_empty() or period_ticks < 1 or period_ticks > 1000000:
        return false
    if offset_ticks < 0 or offset_ticks >= period_ticks:
        return false
    _rules[phase] = {"period": period_ticks, "offset": offset_ticks}
    return true

func remove(phase: String) -> bool:
    if not _rules.has(phase):
        return false
    _rules.erase(phase)
    return true

func is_due(phase: String, tick: int) -> bool:
    if tick < 1 or not _rules.has(phase):
        return false
    var rule: Dictionary = _rules[phase]
    return (tick - int(rule["offset"])) % int(rule["period"]) == 0

func snapshot() -> Dictionary:
    return _rules.duplicate(true)

func restore(data: Dictionary, allowed_phases: Array[String]) -> bool:
    var staged: Dictionary = {}
    for key in data:
        if not (key is String) or not allowed_phases.has(key):
            return false
        var rule: Variant = data[key]
        if not (rule is Dictionary):
            return false
        var p: Variant = rule.get("period", null)
        var o: Variant = rule.get("offset", null)
        if not _whole(p) or not _whole(o) or int(p) < 1 or int(p) > 1000000 or int(o) >= int(p):
            return false
        staged[key] = {"period": int(p), "offset": int(o)}
    _rules = staged
    return true

func _whole(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 9007199254740991.0 and float(int(value)) == float(value)
