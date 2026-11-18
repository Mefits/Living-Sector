extends SceneTree
# N154 paid shipyard module write ownership; exact full-copy state oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n154_module_owned_stage.gd

const OWNED: Array[String] = ["facilities", "populations", "markets"]

func _initialize() -> void:
    var before: Dictionary = {
        "facilities": {"yard": {"credits": 100, "work_shift": {"tick": 1},
            "module_stock": {"stock": {"hull": 1}}}, "owner": {"credits": 200}},
        "populations": {"crew": {"wealth": 10, "employed_fraction": 0.0}},
        "markets": {"station": {"supply": {"ore": 100.0},
            "history": {"dirty": false}}},
        "ships": {"s": {"cargo": {"ore": 3}}},
        "contract_board": {"contracts": {"c": {"status": "posted"}}},
        "dock_receipts": {"r": {"tick": 1}}}
    var frozen: Dictionary = before.duplicate(true)
    var oracle: Dictionary = before.duplicate(true)
    var staged: Dictionary = before.duplicate(false)
    for domain in OWNED:
        staged[domain] = before[domain].duplicate(true)
    for world in [oracle, staged]:
        world["facilities"]["yard"]["credits"] = 84
        world["facilities"]["yard"]["work_shift"] = {"tick": 2, "workers": {"crew": 16}}
        world["facilities"]["yard"]["module_stock"]["stock"]["hull"] = 2
        world["facilities"]["owner"]["credits"] = 216
        world["populations"]["crew"]["wealth"] = 26
        world["populations"]["crew"]["employed_fraction"] = 0.5
        world["markets"]["station"]["supply"]["ore"] = 92.0
        world["markets"]["station"]["history"]["dirty"] = true
    assert(staged == oracle, "N154 owned stage differs from full World oracle")
    assert(before == frozen, "N154 rejected stage modified canonical World")
    staged["facilities"]["yard"]["work_shift"]["workers"]["crew"] = 1
    staged["markets"]["station"]["history"]["dirty"] = false
    assert(before == frozen, "N154 nested mutation escaped owned stage")
    # Negative: shallow domain copy is insufficient for payroll row mutations.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["facilities"] = frozen["facilities"].duplicate(false)
    unsafe["facilities"]["yard"]["work_shift"]["tick"] = 999
    assert(frozen["facilities"]["yard"]["work_shift"]["tick"] == 999,
        "negative alias control did not reproduce shallow-row leak")
    assert(before["facilities"]["yard"]["work_shift"]["tick"] == 1)
    assert(before["ships"] == {"s": {"cargo": {"ore": 3}}})
    quit(0)
