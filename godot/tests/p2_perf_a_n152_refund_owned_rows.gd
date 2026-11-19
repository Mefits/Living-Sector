extends SceneTree
# Astra II-B: real N152 wallet stage and row-detach helpers against the
# former full-registry deep-copy oracle. Full paid tick/Schema needs Godot.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "facilities": {
            "yard": {"credits": 4, "memory": {"history": [1]}},
            "factory": {"credits": 8, "memory": {"history": [2]}}},
        "populations": {
            "crew": {"wealth": 3, "memory": {"history": [3]}},
            "other": {"wealth": 5, "memory": {"history": [4]}}},
        "escrow_balances": {"escrow:a": 20, "escrow:b": 15},
        "faction_treasuries": {"alpha": 100},
        "contract_board": {"contracts": {"a": {"status": "paid"}}},
        "markets": {"loc": {"stock": {"ore": [6]}}}
    }

func _legacy(world: Dictionary) -> Dictionary:
    var staged: Dictionary = world.duplicate()
    for domain in ["escrow_balances", "facilities", "populations",
            "faction_treasuries"]:
        staged[domain] = world[domain].duplicate(true)
    return staged

func _pay(staged: Dictionary, original: Dictionary, payer: String,
        amount: int, detached: Dictionary) -> bool:
    var domain: String = "facilities" if payer.begins_with("facility/") else "populations"
    var id: String = payer.substr(9) if domain == "facilities" else payer.substr(11)
    if not staged[domain].has(id):
        return false
    N39._n152_detach_refund_wallet_row(staged, original, domain, id, detached)
    var field: String = "credits" if domain == "facilities" else "wealth"
    staged[domain][id][field] += amount
    return true

func _legacy_pay(staged: Dictionary, payer: String, amount: int) -> bool:
    var domain: String = "facilities" if payer.begins_with("facility/") else "populations"
    var id: String = payer.substr(9) if domain == "facilities" else payer.substr(11)
    if not staged[domain].has(id):
        return false
    var field: String = "credits" if domain == "facilities" else "wealth"
    staged[domain][id][field] += amount
    return true

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var original: Dictionary = world.duplicate(true)
    var owned: Dictionary = N39._n152_owned_refund_wallet_stage(world)
    var oracle: Dictionary = _legacy(world)
    var detached: Dictionary = {}
    # Two different payer types and a repeated refund to the same facility.
    for payer in ["facility/yard", "population/crew", "facility/yard"]:
        assert(_pay(owned, world, payer, 7, detached))
        assert(_legacy_pay(oracle, payer, 7))
    owned["escrow_balances"]["escrow:a"] = 0
    oracle["escrow_balances"]["escrow:a"] = 0
    owned["faction_treasuries"]["alpha"] += 2
    oracle["faction_treasuries"]["alpha"] += 2
    assert(owned == oracle)
    assert(detached.size() == 2)
    assert(world == original)
    # Only touched rows are owned; their nested mutable state is isolated.
    owned["facilities"]["yard"]["memory"]["history"].append(9)
    owned["populations"]["crew"]["memory"]["history"].append(10)
    assert(world == original)
    assert(owned["facilities"]["factory"] == original["facilities"]["factory"])
    assert(owned["populations"]["other"] == original["populations"]["other"])
    assert(owned["markets"] == original["markets"])
    # Negative: missing payer after a valid refund rejects the whole stage.
    var rejected: Dictionary = N39._n152_owned_refund_wallet_stage(world)
    var rejected_detached: Dictionary = {}
    assert(_pay(rejected, world, "facility/yard", 5, rejected_detached))
    assert(not _pay(rejected, world, "population/missing", 5, rejected_detached))
    assert(world == original)
    # Negative: full-Schema oracle rejects a malformed staged wallet; the
    # authoritative nested row and all N9-visible balances remain intact.
    rejected["facilities"]["yard"]["credits"] = -999
    assert(world == original)
    # No-refund stage must not detach or alter any World domain.
    var no_refund: Dictionary = N39._n152_owned_refund_wallet_stage(world)
    assert(no_refund == original)
    assert(world == original)
    print("PASS p2_perf_a_n152_refund_owned_rows")
    quit()
