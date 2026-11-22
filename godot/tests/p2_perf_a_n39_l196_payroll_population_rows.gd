extends SceneTree
# Astra II-B: exact L196 N156 household ownership model.
# Run later: godot --headless --path godot --script res://tests/p2_perf_a_n39_l196_payroll_population_rows.gd
# No Godot runtime was available during authoring.

func _owned(source: Dictionary, candidates: Array) -> Dictionary:
    var stage: Dictionary = source.duplicate(false)
    if candidates.is_empty():
        return stage
    var locations: Dictionary = {}
    for candidate in candidates:
        var id: String = str(candidate.get("facility_id", ""))
        if not source["facilities"].has(id):
            return {}
        var employer: Dictionary = source["facilities"][id]
        var faction: String = str(employer.get("faction", ""))
        if not locations.has(faction):
            locations[faction] = {}
        locations[faction][str(employer.get("location", ""))] = true
    var populations: Dictionary = source["populations"].duplicate(false)
    for id in source["populations"]:
        var person: Dictionary = source["populations"][id]
        var faction: String = str(person.get("faction", ""))
        if locations.has(faction) and locations[faction].has(str(person.get("location", ""))):
            populations[id] = person.duplicate(true)
    stage["populations"] = populations
    return stage

func _oracle(source: Dictionary, candidates: Array) -> Dictionary:
    if candidates.is_empty():
        return source.duplicate(false)
    var stage: Dictionary = source.duplicate(false)
    stage["populations"] = source["populations"].duplicate(true)
    return stage

func _pay(stage: Dictionary, population_id: String, amount: int) -> void:
    var household: Dictionary = stage["populations"][population_id]
    household["wealth"] += amount
    household["employed_fraction"] = 0.5
    household["history"]["wages"].append(amount)

func _fixture() -> Dictionary:
    return {
        "facilities": {
            "a": {"faction": "red", "location": "earth"},
            "b": {"faction": "red", "location": "mars"},
            "c": {"faction": "blue", "location": "earth"},
            "d": {"faction": "red", "location": "earth"}},
        "populations": {
            "p1": {"faction": "red", "location": "earth", "wealth": 10,
                "employed_fraction": 0.0, "history": {"wages": []}},
            "p2": {"faction": "red", "location": "mars", "wealth": 20,
                "employed_fraction": 0.0, "history": {"wages": []}},
            "p3": {"faction": "blue", "location": "earth", "wealth": 30,
                "employed_fraction": 0.0, "history": {"wages": []}},
            "p4": {"faction": "red", "location": "earth", "wealth": 40,
                "employed_fraction": 0.0, "history": {"wages": []}}},
        "ships": {"ship": {"cargo": {"ore": 10}}}
    }

func _initialize() -> void:
    var source: Dictionary = _fixture()
    var frozen: Dictionary = source.duplicate(true)
    var candidates: Array = [{"facility_id": "a"}, {"facility_id": "d"},
        {"facility_id": "b"}]
    var stage: Dictionary = _owned(source, candidates)
    var oracle: Dictionary = _oracle(source, candidates)
    # Two paid repairs in one location and another on Mars: later payroll
    # observes earlier wages/occupation, but all eligible rows are detached.
    for id in ["p1", "p4", "p2"]:
        _pay(stage, id, 3)
        _pay(oracle, id, 3)
    assert(stage == oracle, "owned multi-repair payroll differs from full-copy oracle")
    assert(source == frozen, "paid wages leaked into canonical World")
    # Negative: a blocked repair performs no household writes, and a later
    # rejected Schema/ledger stage must not publish any paid nested history.
    stage["populations"]["p1"]["history"]["wages"].append(99)
    assert(source == frozen, "nested wage history escaped rollback")
    # An unrelated faction at the SAME location must not be detached, and
    # same faction at a DIFFERENT location must not be detached either.
    var earth: Dictionary = _owned(source, [{"facility_id": "a"}])
    assert(earth["populations"]["p2"] is Dictionary)
    assert(earth["populations"]["p3"] is Dictionary)
    _pay(earth, "p1", 1)
    _pay(earth, "p4", 1)
    var earth_oracle: Dictionary = _oracle(source, [{"facility_id": "a"}])
    _pay(earth_oracle, "p1", 1)
    _pay(earth_oracle, "p4", 1)
    assert(earth == earth_oracle, "same-faction/location household selection diverged")
    assert(source == frozen, "single-location payroll mutated other colonies")
    # Empty and invalid candidate paths do not allocate or mutate households.
    assert(_owned(source, []).has("populations"))
    assert(_owned(source, [{"facility_id": "missing"}]).is_empty())
    assert(source == frozen, "invalid employer leaked a write")
    # Negative control: shallow rows are demonstrably unsafe for wages.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["populations"] = frozen["populations"].duplicate(false)
    unsafe["populations"]["p1"]["history"]["wages"].append(77)
    assert(frozen["populations"]["p1"]["history"]["wages"] == [77],
        "negative alias fixture did not reproduce a leak")
    assert(source["populations"]["p1"]["history"]["wages"].is_empty(),
        "negative alias fixture unexpectedly changed authoritative source")
    quit(0)
