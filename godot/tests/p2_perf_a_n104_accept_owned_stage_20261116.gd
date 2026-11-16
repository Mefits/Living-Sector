extends SceneTree

# Negative regression for the N104 accept owned-domain stage.
# This tests staging isolation and the full-copy oracle's values, not a
# synthetic claim of paid N104 transaction parity.
func _initialize() -> void:
    var original: Dictionary = {
        "ships": {"s": {"current_bt": {"steps": [1]}}},
        "facilities": {"f": {"credits": 40, "nested": {"x": [1]}}},
        "escrow_balances": {"e": 12},
        "faction_treasuries": {"a": 30},
        "contract_board": {"c": {"status": "open"}},
        "markets": {"m": {"supply": {"ore": 10}}},
        "populations": {"p": {"wealth": 7}}
    }
    var before: Dictionary = original.duplicate(true)
    var full: Dictionary = original.duplicate(true)
    var owned: Dictionary = original.duplicate()
    for domain in ["escrow_balances", "faction_treasuries", "facilities", "ships"]:
        owned[domain] = original[domain].duplicate(true)
    owned["contract_board"] = {"c": {"status": "accepted"}}
    full["contract_board"] = {"c": {"status": "accepted"}}
    owned["ships"]["s"]["current_bt"]["steps"].append(2)
    full["ships"]["s"]["current_bt"]["steps"].append(2)
    owned["facilities"]["f"]["credits"] = 35
    full["facilities"]["f"]["credits"] = 35
    owned["escrow_balances"]["e"] = 17
    full["escrow_balances"]["e"] = 17
    owned["faction_treasuries"]["a"] = 25
    full["faction_treasuries"]["a"] = 25
    assert(owned == full, "owned write-set differs from deep-copy oracle")
    assert(original == before, "N104 staging mutated authoritative World")
    assert(not is_same(owned["ships"], original["ships"]), "ship alias escaped")
    assert(not is_same(owned["facilities"], original["facilities"]), "facility alias escaped")
    assert(not is_same(owned["escrow_balances"], original["escrow_balances"]), "escrow alias escaped")
    assert(not is_same(owned["faction_treasuries"], original["faction_treasuries"]), "treasury alias escaped")
    # Negative control: a shallow-only stage MUST mutate authoritative data.
    var unsafe: Dictionary = original.duplicate()
    unsafe["ships"]["s"]["current_bt"]["steps"].append(99)
    assert(original != before, "negative alias control did not expose unsafe stage")
    print("P2_PERF_A_N104_ACCEPT_OWNED_STAGE_PASS")
    quit(0)
