extends SceneTree
# N129 wallet stage ownership against full deep-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n129_wallet_owned_stage.gd

const OWNED: Array[String] = ["faction_treasuries", "facilities", "populations"]

func _initialize() -> void:
    var source: Dictionary = {
        "faction_treasuries": {"f": 1000},
        "facilities": {"factory": {"credits": 200, "dirty": false,
            "stock": {"ore": 12}}},
        "populations": {"colony": {"wealth": 50, "sentiment_dirty": false,
            "needs": {"water": 4}}},
        "ships": {"ship": {"cargo": {"ore": 9}}},
        "contract_board": {"contracts": {"c": {"status": "active"}}}}
    var frozen: Dictionary = source.duplicate(true)
    var oracle: Dictionary = source.duplicate(true)
    var staged: Dictionary = source.duplicate(false)
    for domain in OWNED:
        staged[domain] = source[domain].duplicate(true)
    for world in [oracle, staged]:
        world["faction_treasuries"]["f"] = 1010
        world["facilities"]["factory"]["credits"] = 185
        world["facilities"]["factory"]["dirty"] = true
        world["populations"]["colony"]["wealth"] = 55
        world["populations"]["colony"]["sentiment_dirty"] = true
        world["faction_finance_last_tick"] = 50
    assert(staged == oracle, "N129 owned wallet stage differs from full oracle")
    assert(source == frozen, "N129 stage mutated canonical source")
    staged["facilities"]["factory"]["stock"]["ore"] = 0
    staged["populations"]["colony"]["needs"]["water"] = 0
    assert(source == frozen, "N129 nested owned row escaped into source")
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["facilities"] = frozen["facilities"].duplicate(false)
    unsafe["facilities"]["factory"]["stock"]["ore"] = 999
    assert(frozen["facilities"]["factory"]["stock"]["ore"] == 999,
        "negative shallow-row alias was not reproduced")
    assert(source["facilities"]["factory"]["stock"]["ore"] == 12)
    quit(0)
