extends SceneTree
# N39 run_tick L196: owned lifecycle stage vs full-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n39_l196_owned_lifecycle.gd

func _initialize() -> void:
    var original: Dictionary = {
        "facilities": {"f": {"credits": 100, "reserves": {"tools": 3.0}, "condition": 0.8}},
        "markets": {"m": {"supply": {"tools": 10.0}, "prices": {"tools": 2}}},
        "populations": {"p": {"wealth": 20, "employed_fraction": 0.0}},
        "ships": {"s": {"cargo": {"ore": 7}}},
        "contract_board": {"contracts": {"c": {"receipt": ["old"]}}}
    }
    var oracle: Dictionary = original.duplicate(true)
    oracle["facilities"]["f"]["condition"] = 0.9
    oracle["facilities"]["f"]["reserves"]["tools"] = 4.0
    oracle["markets"]["m"]["supply"]["tools"] = 9.0
    oracle["populations"]["p"]["wealth"] = 21

    var stage: Dictionary = original.duplicate()
    stage["facilities"] = original["facilities"].duplicate(true)
    stage["markets"] = original["markets"].duplicate(true)
    stage["populations"] = original["populations"].duplicate(true)
    stage["facilities"]["f"]["condition"] = 0.9
    stage["facilities"]["f"]["reserves"]["tools"] = 4.0
    stage["markets"]["m"]["supply"]["tools"] = 9.0
    stage["populations"]["p"]["wealth"] = 21
    assert(stage == oracle, "L196 owned stage differs from full-copy oracle")
    assert(original["facilities"]["f"]["condition"] == 0.8)
    assert(original["facilities"]["f"]["reserves"]["tools"] == 3.0)
    assert(original["markets"]["m"]["supply"]["tools"] == 10.0)
    assert(original["populations"]["p"]["wealth"] == 20)

    # Negative: a rejected stage must never leak nested market or wage writes.
    var rejected: Dictionary = original.duplicate()
    rejected["facilities"] = original["facilities"].duplicate(true)
    rejected["markets"] = original["markets"].duplicate(true)
    rejected["populations"] = original["populations"].duplicate(true)
    rejected["markets"]["m"]["supply"]["tools"] = -99.0
    rejected["populations"]["p"]["wealth"] = -99
    assert(original["markets"]["m"]["supply"]["tools"] == 10.0)
    assert(original["populations"]["p"]["wealth"] == 20)

    # Negative oracle: a shallow market root would alias authoritative stock.
    var unsafe: Dictionary = original.duplicate()
    unsafe["markets"]["m"]["supply"]["tools"] = -1.0
    assert(original["markets"]["m"]["supply"]["tools"] == -1.0,
        "negative fixture must demonstrate unowned market alias")
    quit(0)
