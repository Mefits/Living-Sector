extends SceneTree
# N154 funded construction commission: six detached write registries.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n154_commission_owned_stage.gd

const OWNED: Array[String] = ["construction_sites", "construction_contracts",
    "faction_treasuries", "contract_board", "escrow_balances",
    "construction_receipts"]

func _initialize() -> void:
    var before: Dictionary = {
        "construction_sites": {"existing": {"labor": {"done": 2}}},
        "construction_contracts": {"old": "existing"},
        "faction_treasuries": {"f": 50000},
        "contract_board": {"contracts": {"old": {"status": "posted"}}},
        "escrow_balances": {"escrow:old": 10000},
        "construction_receipts": {"old": {"tick": 1}},
        "ships": {"ship": {"cargo": {"ore": 7}}},
        "markets": {"m": {"supply": {"ore": 15.0}}},
        "facilities": {"station": {"credits": 25}},
        "cargo_receipts": {"load": {"ore": 7}}}
    var frozen: Dictionary = before.duplicate(true)
    var oracle: Dictionary = before.duplicate(true)
    var stage: Dictionary = before.duplicate(false)
    for domain in OWNED:
        stage[domain] = before[domain].duplicate(true)
    for candidate in [oracle, stage]:
        candidate["construction_sites"]["new"] = {"labor": {"done": 0}}
        candidate["construction_contracts"]["construction:new:2"] = "new"
        candidate["faction_treasuries"]["f"] = 40000
        candidate["contract_board"]["contracts"]["construction:new:2"] = {
            "status": "posted", "receipt": {"amount": 10000}}
        candidate["escrow_balances"]["escrow:construction:new:2"] = 10000
        candidate["construction_receipts"]["native_site_commission:construction:new:2"] = {
            "tick": 2, "kind": "commission"}
    assert(stage == oracle, "N154 owned write differs from full World oracle")
    assert(before == frozen, "N154 rejected stage mutated authoritative World")
    stage["contract_board"]["contracts"]["construction:new:2"]["receipt"]["amount"] = 1
    stage["construction_sites"]["existing"]["labor"]["done"] = 99
    assert(before == frozen, "N154 nested stage mutation leaked into source")
    # Negative control: a shallow registry copy DOES alias nested contracts.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["contract_board"] = frozen["contract_board"].duplicate(false)
    unsafe["contract_board"]["contracts"]["old"]["status"] = "corrupted"
    assert(frozen["contract_board"]["contracts"]["old"]["status"] == "corrupted",
        "negative nested alias fixture did not reproduce the defect")
    assert(before["contract_board"]["contracts"]["old"]["status"] == "posted")
    assert(before["ships"] == {"ship": {"cargo": {"ore": 7}}})
    assert(before["markets"] == {"m": {"supply": {"ore": 15.0}}})
    quit(0)
