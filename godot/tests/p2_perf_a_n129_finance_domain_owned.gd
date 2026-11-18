extends SceneTree
# Astra II-B: N129 shallow registry + row-owned writes, compared against
# the former full-domain deep-copy implementation. No financial shortcuts.

func _stage(world: Dictionary, treasury: Dictionary, facilities: Dictionary,
        households: Dictionary, old_full_domains: bool) -> Dictionary:
    var stage: Dictionary = world.duplicate(false)
    stage["faction_treasuries"] = world["faction_treasuries"].duplicate(old_full_domains)
    stage["facilities"] = world["facilities"].duplicate(old_full_domains)
    stage["populations"] = world["populations"].duplicate(old_full_domains)
    if treasury.size() != stage["faction_treasuries"].size() or (
            facilities.size() != stage["facilities"].size()) or (
            households.size() != stage["populations"].size()):
        return {"error": "roster"}
    for id in stage["faction_treasuries"]:
        if not treasury.has(id):
            return {"error": "treasury"}
        stage["faction_treasuries"][id] = int(treasury[id])
    for id in stage["facilities"]:
        if not facilities.has(id):
            return {"error": "facility"}
        var credits: int = int(facilities[id])
        var original: Dictionary = world["facilities"][id]
        if credits != int(original["credits"]):
            var row: Dictionary = original.duplicate(true)
            row["credits"] = credits
            row["dirty"] = true
            stage["facilities"][id] = row
    for id in stage["populations"]:
        if not households.has(id):
            return {"error": "population"}
        var wealth: int = int(households[id])
        var original: Dictionary = world["populations"][id]
        if wealth != int(original["wealth"]):
            var row: Dictionary = original.duplicate(true)
            row["wealth"] = wealth
            row["sentiment_dirty"] = true
            stage["populations"][id] = row
    stage["faction_finance_last_tick"] = 30
    return stage

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"a": 1000, "b": 800},
        "facilities": {
            "taxed": {"credits": 110, "dirty": false,
                "reserves": {"ore": [1, 2]}},
            "bailout": {"credits": 0, "dirty": false,
                "reserves": {"ore": [3]}},
            "untouched": {"credits": 900, "dirty": false,
                "reserves": {"ore": [4]}}},
        "populations": {
            "relief": {"wealth": 2, "sentiment_dirty": false,
                "needs": {"food": [5]}},
            "idle": {"wealth": 99, "sentiment_dirty": false,
                "needs": {"food": [6]}}},
        "ships": {"ship": {"cargo": [7]}},
        "faction_finance_last_tick": 0}
    var original: Dictionary = world.duplicate(true)
    var treasuries: Dictionary = {"a": 975, "b": 820}
    var facilities: Dictionary = {"taxed": 95, "bailout": 20, "untouched": 900}
    var households: Dictionary = {"relief": 22, "idle": 99}
    var optimized: Dictionary = _stage(world, treasuries, facilities,
        households, false)
    var oracle: Dictionary = _stage(world, treasuries, facilities,
        households, true)
    assert(optimized == oracle)
    assert(world == original)
    # Changed rows must be isolated even when a later operation fails.
    optimized["facilities"]["taxed"]["reserves"]["ore"].append(12)
    optimized["populations"]["relief"]["needs"]["food"].append(13)
    assert(world == original)
    # The unmodified rows are intentionally shared: the stage must never
    # write them. The full Schema oracle still checks the staged state.
    assert(optimized["facilities"]["untouched"] == world["facilities"]["untouched"])
    assert(optimized["populations"]["idle"] == world["populations"]["idle"])
    for bad_households in [{"relief": 22}, {"relief": 22, "wrong": 99}]:
        var rejected: Dictionary = _stage(world, treasuries, facilities,
            bad_households, false)
        assert(rejected.has("error"))
        assert(world == original)
    var rejected_facility: Dictionary = _stage(world, treasuries,
        {"taxed": 95, "bailout": 20, "wrong": 900}, households, false)
    assert(rejected_facility.get("error", "") == "facility")
    assert(world == original)
    var no_op: Dictionary = _stage(world, {"a": 1000, "b": 800},
        {"taxed": 110, "bailout": 0, "untouched": 900},
        {"relief": 2, "idle": 99}, false)
    assert(no_op == _stage(world, {"a": 1000, "b": 800},
        {"taxed": 110, "bailout": 0, "untouched": 900},
        {"relief": 2, "idle": 99}, true))
    assert(world == original)
    print("PASS p2_perf_a_n129_finance_domain_owned")
    quit()
