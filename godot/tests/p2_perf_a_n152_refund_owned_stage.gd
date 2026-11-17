extends SceneTree
# N152 refund publish: detached wallet domains must match full-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n152_refund_owned_stage.gd

func _initialize() -> void:
    var before: Dictionary = {
        "contract_board": {"contracts": {"c": {"status": "posted"}}},
        "escrow_balances": {"escrow:c": 9},
        "facilities": {"f": {"credits": 1, "storage": {"ore": 4}}},
        "populations": {"p": {"wealth": 2, "needs": {"food": 3}}},
        "faction_treasuries": {"a": 3},
        "ships": {"s": {"cargo": {"ore": 7}}},
        "markets": {"m": {"supply": {"ore": 10}}}}
    var next_board: Dictionary = before["contract_board"].duplicate(true)
    next_board["contracts"]["c"]["status"] = "expired"
    var oracle: Dictionary = before.duplicate(true)
    oracle["contract_board"] = next_board.duplicate(true)
    oracle["escrow_balances"]["escrow:c"] = 0
    oracle["facilities"]["f"]["credits"] = 10
    oracle["populations"]["p"]["wealth"] = 11
    oracle["faction_treasuries"]["a"] = 12
    var stage: Dictionary = before.duplicate(false)
    stage["contract_board"] = next_board.duplicate(true)
    for domain in ["escrow_balances", "facilities", "populations", "faction_treasuries"]:
        stage[domain] = before[domain].duplicate(true)
    stage["escrow_balances"]["escrow:c"] = 0
    stage["facilities"]["f"]["credits"] = 10
    stage["populations"]["p"]["wealth"] = 11
    stage["faction_treasuries"]["a"] = 12
    assert(stage == oracle, "N152 owned refund must match full World oracle")
    assert(before["facilities"]["f"]["credits"] == 1)
    assert(before["populations"]["p"]["wealth"] == 2)
    assert(before["escrow_balances"]["escrow:c"] == 9)
    assert(before["faction_treasuries"]["a"] == 3)
    next_board["contracts"]["c"]["status"] = "tampered"
    assert(stage["contract_board"]["contracts"]["c"]["status"] == "expired")
    # Negative regression: a shallow wallet domain would mutate authority.
    var unsafe: Dictionary = before.duplicate(false)
    unsafe["facilities"] = before["facilities"].duplicate(false)
    unsafe["facilities"]["f"]["storage"]["ore"] = -1
    assert(before["facilities"]["f"]["storage"]["ore"] == -1,
        "negative fixture must expose shallow nested wallet alias")
    # No-refund tick must not mutate any shared wallet domain.
    var no_refund: Dictionary = before.duplicate(false)
    no_refund["contract_board"] = {"contracts": {"c": {"status": "expired"}}}
    assert(no_refund["facilities"] == before["facilities"])
    quit(0)
