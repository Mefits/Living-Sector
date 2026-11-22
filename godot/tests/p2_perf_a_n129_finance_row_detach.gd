extends SceneTree
# Astra II-B N129: paid finance uses row-owned writes and a full Schema/N9
# oracle remains responsible for validating the complete staged World.

func _apply(source: Dictionary, treasuries: Dictionary,
        facility_credits: Dictionary, population_wealth: Dictionary,
        full_copy: bool) -> Dictionary:
    var stage: Dictionary = source.duplicate(true) if full_copy else source.duplicate(false)
    if not full_copy:
        stage["faction_treasuries"] = source["faction_treasuries"].duplicate(true)
        stage["facilities"] = source["facilities"].duplicate(false)
        stage["populations"] = source["populations"].duplicate(false)
    if treasuries.size() != stage["faction_treasuries"].size() or (
            facility_credits.size() != stage["facilities"].size()) or (
            population_wealth.size() != stage["populations"].size()):
        return {"error": "roster"}
    for id in stage["faction_treasuries"]:
        if not treasuries.has(id):
            return {"error": "treasury"}
        stage["faction_treasuries"][id] = int(treasuries[id])
    for id in stage["facilities"]:
        if not facility_credits.has(id):
            return {"error": "facility"}
        var row: Dictionary = stage["facilities"][id]
        var credits: int = int(facility_credits[id])
        if credits != int(row["credits"]):
            if not full_copy:
                row = row.duplicate(true)
                stage["facilities"][id] = row
            row["dirty"] = true
            row["credits"] = credits
    for id in stage["populations"]:
        if not population_wealth.has(id):
            return {"error": "population"}
        var row: Dictionary = stage["populations"][id]
        var wealth: int = int(population_wealth[id])
        if wealth != int(row["wealth"]):
            if not full_copy:
                row = row.duplicate(true)
                stage["populations"][id] = row
            row["sentiment_dirty"] = true
            row["wealth"] = wealth
    stage["faction_finance_last_tick"] = 25
    return stage

func _initialize() -> void:
    var source: Dictionary = {
        "faction_treasuries": {"f": 200},
        "facilities": {
            "paid": {"credits": 80, "dirty": false,
                "reserves": {"ore": [2, 3]}},
            "idle": {"credits": 70, "dirty": false,
                "reserves": {"ore": [4]}}},
        "populations": {
            "relief": {"wealth": 30, "sentiment_dirty": false,
                "nested": {"food": [1, 2]}},
            "idle": {"wealth": 40, "sentiment_dirty": false,
                "nested": {"food": [5]}}},
        "ships": {"s": {"cargo": [9]}},
        "faction_finance_last_tick": 0}
    var baseline: Dictionary = source.duplicate(true)
    var treasury: Dictionary = {"f": 205}
    var facilities: Dictionary = {"paid": 75, "idle": 70}
    var populations: Dictionary = {"relief": 35, "idle": 40}
    var owned: Dictionary = _apply(source, treasury, facilities, populations, false)
    var oracle: Dictionary = _apply(source, treasury, facilities, populations, true)
    assert(owned == oracle)
    assert(source == baseline)
    assert(owned["facilities"]["paid"] != source["facilities"]["paid"])
    owned["facilities"]["paid"]["reserves"]["ore"].append(99)
    owned["populations"]["relief"]["nested"]["food"].append(99)
    assert(source == baseline)
    # A rejected late roster validation must not leak earlier staged writes.
    var rejected: Dictionary = _apply(source, treasury, facilities,
        {"relief": 35}, false)
    assert(rejected.get("error", "") == "roster")
    assert(source == baseline)
    var rejected_after_facility: Dictionary = _apply(source, treasury,
        facilities, {"relief": 35, "wrong": 40}, false)
    assert(rejected_after_facility.get("error", "") == "population")
    assert(source == baseline)
    # An all-no-op finance cycle preserves exact flags and values.
    var unchanged: Dictionary = _apply(source, {"f": 200},
        {"paid": 80, "idle": 70}, {"relief": 30, "idle": 40}, false)
    assert(unchanged == _apply(source, {"f": 200},
        {"paid": 80, "idle": 70}, {"relief": 30, "idle": 40}, true))
    assert(source == baseline)
    print("PASS p2_perf_a_n129_finance_row_detach")
    quit()
