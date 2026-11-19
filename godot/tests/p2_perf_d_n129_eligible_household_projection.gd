extends RefCounted
## Astra II-C: full original household projection versus eligible-only
## N129 relief input. Both normal and malformed source rows are retained
## in the authoritative population_wealth output, never cached.
const Phase = preload("res://scripts/sim/phase2/unified_native_faction_finance_phase.gd")
const Legacy = preload("res://tests/p2_perf_d_n129_due_scoped_projections.gd")

static func run() -> Dictionary:
    var world: Dictionary = {
        "faction_treasuries": {"a": 50000, "b": 22000},
        "facilities": {
            "fa": {"faction": "a", "location": "earth", "type": "farm", "credits": 2000},
            "fb": {"faction": "b", "location": "mars", "type": "mine", "credits": 5000}},
        "markets": {
            "earth": {"owner": "fa", "supply": {"food": 100.0, "water": 100.0}},
            "mars": {"owner": "fb", "supply": {"food": 100.0, "water": 100.0}}},
        "populations": {}
    }
    for i in range(1600):
        var id: String = "h%04d" % i
        world["populations"][id] = {
            "faction": "a" if i % 2 == 0 else "b",
            "location": "earth-colony" if i % 9 == 0 else "mars",
            "wealth": 100 if i % 23 == 0 else (0 if i % 41 == 0 else 500 + i),
            "food_satisfaction": 20 if i % 7 == 0 else 90}
    world["populations"]["invalid_negative"] = {
        "faction": "a", "location": "earth", "wealth": -1}
    world["populations"]["orphan"] = {
        "faction": "missing", "location": "earth", "wealth": 0}
    for case in [[25, 1], [200, 1], [400, 2], [225, 1], [201, 1]]:
        var tick: int = case[0]
        var multiplier: int = case[1]
        var before: Dictionary = world.duplicate(true)
        var got: Dictionary = Phase.propose(world, tick, multiplier)
        var oracle: Dictionary = Legacy._legacy_oracle(world, tick, multiplier)
        if got != oracle:
            return {"ok": false, "reason": "eligible_household_oracle_mismatch",
                "tick": tick, "multiplier": multiplier}
        if world != before:
            return {"ok": false, "reason": "authoritative_world_mutated"}
    # Invalidation: a previously wealthy row becomes eligible, an eligible
    # row changes faction and a recipient disappears between calls.
    world["populations"]["h0001"]["wealth"] = 0
    world["populations"]["h0001"]["faction"] = "a"
    world["populations"]["h0000"]["wealth"] = 999
    world["populations"].erase("h0041")
    world["populations"]["new"] = {
        "faction": "b", "location": "mars", "wealth": 0,
        "food_satisfaction": 10}
    for tick in [25, 200]:
        var got: Dictionary = Phase.propose(world, tick, 1)
        if got != Legacy._legacy_oracle(world, tick, 1):
            return {"ok": false, "reason": "stale_household_projection",
                "tick": tick}
    var bad: Dictionary = world.duplicate(true)
    bad.erase("populations")
    var rejected: Dictionary = Phase.propose(bad, 25, 1)
    if rejected.get("ok", true) or rejected.get("reason", "") != "n129_missing_source_populations":
        return {"ok": false, "reason": "missing_population_registry_not_rejected"}
    bad = world.duplicate(true)
    bad["markets"]["earth"]["owner"] = "unknown"
    rejected = Phase.propose(bad, 25, 1)
    if rejected.get("ok", true) or rejected.get("reason", "") != "n129_market_without_real_payer":
        return {"ok": false, "reason": "invalid_market_owner_not_rejected"}
    return {"ok": true, "cases": 7, "population_rows": 1602,
        "oracle": "original_full_household_projection"}
