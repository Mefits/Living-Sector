extends SceneTree
# Astra II-B: N141 non-colony household ownership and B3 deep fallback.
# This regression compares owned-row staging with the legacy full deep-copy
# oracle and verifies rejected later shifts never mutate the source graph.

func _stage(source: Dictionary, paid: Array, colony: bool) -> Dictionary:
    var staged: Dictionary = source.duplicate(false)
    staged["populations"] = (source["populations"].duplicate(true)
        if colony else source["populations"].duplicate(false))
    var owned: Dictionary = {}
    for change in paid:
        var id: String = str(change["id"])
        if not staged["populations"].has(id):
            return {"error": "missing_household"}
        if not colony and not owned.has(id):
            staged["populations"][id] = staged["populations"][id].duplicate(true)
            owned[id] = true
        staged["populations"][id]["wealth"] += int(change["wages"])
        staged["populations"][id]["employed_fraction"] = float(change["employed"])
    return staged

func _oracle(source: Dictionary, paid: Array) -> Dictionary:
    var staged: Dictionary = source.duplicate(true)
    for change in paid:
        var id: String = str(change["id"])
        if not staged["populations"].has(id):
            return {"error": "missing_household"}
        staged["populations"][id]["wealth"] += int(change["wages"])
        staged["populations"][id]["employed_fraction"] = float(change["employed"])
    return staged

func _initialize() -> void:
    var source: Dictionary = {
        "populations": {
            "a": {"wealth": 100, "employed_fraction": 0.0,
                "nested": {"reserves": [1, 2]}},
            "b": {"wealth": 80, "employed_fraction": 0.0,
                "nested": {"reserves": [3]}},
            "untouched": {"wealth": 42, "employed_fraction": 0.0,
                "nested": {"reserves": [7]}}},
        "ships": {"s": {"cargo": {"ore": 4}}}}
    var original: Dictionary = source.duplicate(true)
    var paid: Array = [
        {"id": "a", "wages": 5, "employed": 0.25},
        {"id": "b", "wages": 3, "employed": 0.5},
        {"id": "a", "wages": 2, "employed": 0.75}]
    var staged: Dictionary = _stage(source, paid, false)
    assert(staged == _oracle(source, paid))
    assert(source == original)
    staged["populations"]["a"]["nested"]["reserves"].append(9)
    assert(source == original)
    var rejected: Dictionary = _stage(source, paid + [
        {"id": "missing", "wages": 99, "employed": 1.0}], false)
    assert(rejected.get("error", "") == "missing_household")
    assert(source == original)
    var colony: Dictionary = _stage(source, paid, true)
    assert(colony == _oracle(source, paid))
    colony["populations"]["untouched"]["nested"]["reserves"].append(11)
    assert(source == original)
    print("PASS p2_perf_a_n141_population_owned")
    quit()
