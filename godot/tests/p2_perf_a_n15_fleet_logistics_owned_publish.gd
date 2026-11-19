extends SceneTree
# N39 apply_fleet_logistics validated publish ownership regression.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n15_fleet_logistics_owned_publish.gd

func _initialize() -> void:
    var original: Dictionary = {
        "ships": {"s": {"cargo": {"ore": 2}, "docked_at": "dock"}},
        "markets": {"planet": {"supply": {"ore": 10}}},
        "dock_receipts": {"old": {"action": "dock"}},
        "cargo_receipts": {},
        "contract_board": {"contracts": {"c": {"status": "posted"}}},
        "facilities": {"dock": {"workers": [1, 2]}}}
    var proposal: Dictionary = original.duplicate(true)
    proposal["ships"]["s"]["cargo"]["ore"] = 5
    proposal["markets"]["planet"]["supply"]["ore"] = 7
    proposal["cargo_receipts"]["new"] = {"action": "load", "quantities": {"ore": 3}}
    var oracle: Dictionary = proposal.duplicate(true)
    var committed: Dictionary = original.duplicate(false)
    for domain in ["ships", "markets", "dock_receipts", "cargo_receipts"]:
        committed[domain] = proposal[domain].duplicate(true)
    assert(committed == oracle, "N15 owned publish must match full deep-copy oracle")
    assert(original["ships"]["s"]["cargo"]["ore"] == 2)
    assert(original["markets"]["planet"]["supply"]["ore"] == 10)
    assert(not original["cargo_receipts"].has("new"))
    # Caller may mutate or reuse its proposal after commit.
    proposal["ships"]["s"]["cargo"]["ore"] = -9
    proposal["markets"]["planet"]["supply"]["ore"] = -9
    proposal["cargo_receipts"]["new"]["quantities"]["ore"] = -9
    assert(committed["ships"]["s"]["cargo"]["ore"] == 5)
    assert(committed["markets"]["planet"]["supply"]["ore"] == 7)
    assert(committed["cargo_receipts"]["new"]["quantities"]["ore"] == 3)
    # Unchanged domains are taken from authority, not from caller-owned proposal.
    proposal["contract_board"]["contracts"]["c"]["status"] = "tampered"
    assert(committed["contract_board"]["contracts"]["c"]["status"] == "posted")
    # Negative regression: shallow copying the proposed writable domain aliases caller.
    var unsafe: Dictionary = original.duplicate(false)
    unsafe["ships"] = proposal["ships"].duplicate(false)
    unsafe["ships"]["s"]["cargo"]["ore"] = -100
    assert(proposal["ships"]["s"]["cargo"]["ore"] == -100,
        "negative fixture must demonstrate mutable ship alias")
    quit(0)
