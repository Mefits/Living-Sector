extends SceneTree
## N150 paid-path oracle: native bulk duplication of fully retained windows
## versus the original per-row deep-copy/filter/accumulate algorithm.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _oracle(flow: Dictionary, cutoff: int) -> Dictionary:
    var owned: Dictionary = {}
    for key in flow:
        if key != "consumption_window":
            var value: Variant = flow[key]
            owned[key] = value.duplicate(true) if value is Dictionary or value is Array else value
    var windows: Dictionary = {}
    var observed: Dictionary = {}
    var source: Dictionary = flow["consumption_window"]
    var slugs: Array = source.keys()
    slugs.sort()
    for slug in slugs:
        var entries: Variant = source[slug]
        if not (entries is Array):
            return {"ok": false, "reason": "invalid_native_consumption_window"}
        var kept: Array = []
        var amount: float = 0.0
        for entry in entries:
            if not (entry is Dictionary) or typeof(entry.get("tick")) != TYPE_INT or not (typeof(entry.get("qty")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(entry.get("qty")))):
                return {"ok": false, "reason": "invalid_consumption_sample"}
            if int(entry["tick"]) >= cutoff:
                kept.append(entry.duplicate(true))
                amount += float(entry["qty"])
        windows[slug] = kept
        if amount > 0.0:
            observed[slug] = amount
    owned["consumption_window"] = windows
    return {"ok": true, "flow": owned, "observed": observed}

func _check(flow: Dictionary, cutoff: int) -> void:
    var expected: Dictionary = _oracle(flow, cutoff)
    var actual: Dictionary = Market._owned_flow_without_expired(flow, cutoff)
    assert(actual == expected)
    if not actual.get("ok", false):
        return
    var pristine: Dictionary = flow.duplicate(true)
    for slug in actual["flow"]["consumption_window"]:
        var entries: Array = actual["flow"]["consumption_window"][slug]
        if not entries.is_empty():
            entries[0]["qty"] = -999.0
    assert(flow == pristine)
    if actual["flow"].has("seed_demand"):
        actual["flow"]["seed_demand"]["ore"] = -999
    assert(flow == pristine)

func _initialize() -> void:
    var flow: Dictionary = {"seed_demand": {"ore": 1.0},
        "consumption_window": {"ore": [], "water": [], "fuel": []},
        "extension": {"nested": [1, 2]}}
    for i in range(1200):
        flow["consumption_window"]["ore"].append({"tick": 100 + i,
            "qty": 0.125 if i % 2 == 0 else 0.375, "nested": {"i": i}})
        flow["consumption_window"]["water"].append({"tick": i,
            "qty": 1.0 / 3.0, "nested": {"i": i}})
    _check(flow, 0) # bulk-copy all, including empty windows
    _check(flow, 500) # mixed expired and retained rows
    _check(flow, 2000) # all expired
    _check(flow, 100) # exact cutoff boundary
    flow["consumption_window"]["fuel"].append({"tick": 1, "qty": NAN})
    _check(flow, 2000) # invalid expired row still rejects
    flow["consumption_window"]["fuel"].clear()
    flow["consumption_window"]["fuel"].append({"tick": "bad", "qty": 1.0})
    _check(flow, 0)
    flow["consumption_window"]["fuel"] = {"not": "an array"}
    _check(flow, 0)
    print("PASS p2_perf_d_n150_sparse_window")
    quit()
