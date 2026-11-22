extends SceneTree
# N39 N151 consumption: all three mutable write domains must be detached.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n151_consumption_owned_domains.gd

func _initialize() -> void:
    var original: Dictionary = {
        "populations": {"p": {"wealth": 100, "sentiment": {"food": 0.4}}},
        "facilities": {"f": {"credits": 20, "stock": {"ore": 3}}},
        "markets": {"m": {"supply": {"food": 9.0}, "consumption_window": {"food": [1]}}},
        "ships": {"s": {"cargo": {"ore": 8}}},
        "contract_board": {"receipts": [{"id": "old"}]}
    }
    var baseline: Dictionary = original.duplicate(true)
    var oracle: Dictionary = original.duplicate(true)
    oracle["populations"]["p"]["wealth"] = 85
    oracle["populations"]["p"]["sentiment"]["food"] = 0.7
    oracle["facilities"]["f"]["credits"] = 35
    oracle["markets"]["m"]["supply"]["food"] = 7.0
    oracle["markets"]["m"]["consumption_window"]["food"].append(2)

    var staged: Dictionary = original.duplicate()
    staged["populations"] = original["populations"].duplicate(true)
    staged["facilities"] = original["facilities"].duplicate(true)
    staged["markets"] = original["markets"].duplicate(true)
    staged["populations"]["p"]["wealth"] = 85
    staged["populations"]["p"]["sentiment"]["food"] = 0.7
    staged["facilities"]["f"]["credits"] = 35
    staged["markets"]["m"]["supply"]["food"] = 7.0
    staged["markets"]["m"]["consumption_window"]["food"].append(2)
    assert(staged == oracle, "N151 owned stage must equal full World copy")
    assert(original == baseline, "N151 stage must not mutate authoritative World")

    # Rejection after a partially staged purchase must leave all owners intact.
    var rejected: Dictionary = original.duplicate()
    rejected["populations"] = original["populations"].duplicate(true)
    rejected["facilities"] = original["facilities"].duplicate(true)
    rejected["markets"] = original["markets"].duplicate(true)
    rejected["populations"]["p"]["wealth"] = -1
    rejected["facilities"]["f"]["credits"] = -1
    rejected["markets"]["m"]["supply"]["food"] = -1.0
    assert(original == baseline, "rejected N151 transfer leaked to authority")

    # Negative fixture: a shallow map leaves nested market supply aliased.
    var unsafe: Dictionary = original.duplicate()
    unsafe["markets"] = original["markets"].duplicate()
    unsafe["markets"]["m"]["supply"]["food"] = -1.0
    assert(original["markets"]["m"]["supply"]["food"] == -1.0,
        "negative fixture must demonstrate mutable alias risk")
    quit(0)
