extends SceneTree
# N39 N135 funded contract posting: detached payer facility and escrow/board.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n135_owned_funded_contract.gd

func _initialize() -> void:
    var original: Dictionary = {
        "facilities": {
            "buyer": {"credits": 100, "reserves": {"ore": 3}},
            "other": {"credits": 80, "reserves": {"ore": 9}}},
        "escrow_balances": {"escrow:old": 11},
        "contract_board": {"contracts": {"old": {"status": "posted"}}},
        "ships": {"ship": {"cargo": {"ore": 7}}},
        "markets": {"planet": {"supply": {"ore": 99}}}}
    var next_board: Dictionary = {"contracts": {
        "old": {"status": "posted"}, "new": {"status": "posted"}}}
    var oracle: Dictionary = original.duplicate(true)
    oracle["contract_board"] = next_board.duplicate(true)
    oracle["escrow_balances"]["escrow:new"] = 25
    oracle["facilities"]["buyer"]["credits"] = 75

    var staged: Dictionary = original.duplicate()
    staged["contract_board"] = next_board.duplicate(true)
    staged["escrow_balances"] = original["escrow_balances"].duplicate(true)
    staged["escrow_balances"]["escrow:new"] = 25
    staged["facilities"] = original["facilities"].duplicate()
    staged["facilities"]["buyer"] = original["facilities"]["buyer"].duplicate(true)
    staged["facilities"]["buyer"]["credits"] = 75
    assert(staged == oracle, "N135 owned stage differs from full-copy oracle")
    assert(original["facilities"]["buyer"]["credits"] == 100)
    assert(not original["escrow_balances"].has("escrow:new"))
    assert(not original["contract_board"]["contracts"].has("new"))
    assert(original["facilities"]["other"]["reserves"]["ore"] == 9)

    # A rejected candidate must not change payer, board or escrow authority.
    var rejected: Dictionary = original.duplicate()
    rejected["facilities"] = original["facilities"].duplicate()
    rejected["facilities"]["buyer"] = original["facilities"]["buyer"].duplicate(true)
    rejected["facilities"]["buyer"]["credits"] = -100
    rejected["escrow_balances"] = original["escrow_balances"].duplicate(true)
    rejected["escrow_balances"]["escrow:new"] = -100
    assert(original["facilities"]["buyer"]["credits"] == 100)
    assert(not original["escrow_balances"].has("escrow:new"))

    # Negative: shallow facility-map copy alone leaks the payer row.
    var unsafe: Dictionary = original.duplicate()
    unsafe["facilities"] = original["facilities"].duplicate()
    unsafe["facilities"]["buyer"]["credits"] = -1
    assert(original["facilities"]["buyer"]["credits"] == -1,
        "negative fixture must expose the missing row detach")
    quit(0)
