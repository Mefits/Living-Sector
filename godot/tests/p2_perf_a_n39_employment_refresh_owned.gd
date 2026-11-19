extends SceneTree
# Astra II-B: N39 recipe employment owned-write stage versus the actual
# N39 Payroll.refresh_employment implementation (not a rewritten oracle).
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")

func _owned(state: Dictionary, tick: int, external_workers: Dictionary) -> Dictionary:
    var counts: Dictionary = Payroll.occupied(state, tick, external_workers)
    var staged: Dictionary = state.duplicate(false)
    var rows: Dictionary = state["populations"].duplicate()
    var changed: bool = false
    for id in state["populations"]:
        var old: Dictionary = state["populations"][id]
        var capacity: float = maxf(1.0, float(old["count"]) * 0.6)
        var fraction: float = clampf(float(counts.get(id, 0)) / capacity, 0.0, 1.0)
        if old.has("employed_fraction") and float(old["employed_fraction"]) == fraction:
            continue
        var detached: Dictionary = old.duplicate(true)
        detached["employed_fraction"] = fraction
        rows[id] = detached
        changed = true
    if changed:
        staged["populations"] = rows
    return staged

func _initialize() -> void:
    # No facilities/work shifts: source occupied() returns zero for every
    # household; this still exercises the actual paid-cadence refresh.
    var state: Dictionary = {"populations": {
        "changed": {"count": 100, "faction": "a", "location": "earth",
            "employed_fraction": 0.8, "nested": {"history": [1]}},
        "same": {"count": 20, "faction": "a", "location": "mars",
            "employed_fraction": 0.0, "nested": {"history": [2]}},
        "missing": {"count": 4, "faction": "b", "location": "mars",
            "nested": {"history": [3]}}},
        "facilities": {}, "ships": {}}
    var original: Dictionary = state.duplicate(true)
    var oracle: Dictionary = state.duplicate(true)
    Payroll.refresh_employment(oracle, 5, {})
    var owned: Dictionary = _owned(state, 5, {})
    assert(owned == oracle)
    assert(state == original)
    assert(owned["populations"]["changed"]["employed_fraction"] == 0.0)
    assert(owned["populations"]["missing"].has("employed_fraction"))
    # Negative: an invalid subsequent stage must not mutate the original
    # household or its nested mutable graph (rollback/alias isolation).
    owned["populations"]["changed"]["nested"]["history"].append(9)
    owned["populations"]["missing"]["nested"]["history"].append(8)
    assert(state == original)
    # Unchanged rows must not be deep-copied. Re-running the stage is no-op.
    assert(owned["populations"]["same"] == state["populations"]["same"])
    var repeated: Dictionary = _owned(oracle, 10, {})
    assert(repeated == oracle)
    # Negative: bad population capacity must not publish partial writes.
    var invalid: Dictionary = state.duplicate(true)
    invalid["populations"]["changed"]["count"] = 0
    var attempted: Dictionary = _owned(invalid, 5, {})
    assert(attempted["populations"]["changed"]["employed_fraction"] == 0.0)
    assert(invalid["populations"]["changed"]["employed_fraction"] == 0.8)
    print("PASS p2_perf_a_n39_employment_refresh_owned")
    quit()
