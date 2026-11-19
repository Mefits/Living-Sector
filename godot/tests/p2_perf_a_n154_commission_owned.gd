extends SceneTree
# Astra II-B: actual N154 staging helper against legacy deep-registry oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _world() -> Dictionary:
    return {
        "construction_sites": {
            "old": {"id": "old", "memory": {"nested": [1]}}},
        "construction_contracts": {"old-contract": "old"},
        "faction_treasuries": {"f": 40000, "other": 12000},
        "contract_board": {"contracts": {
            "old-contract": {"status": "delivered", "meta": {"tags": [2]}}}},
        "escrow_balances": {"escrow:old-contract": 0},
        "construction_receipts": {"old-receipt": {
            "meta": {"nested": [3]}}},
        "markets": {"m": {"history": {"nested": [4]}}}
    }

func _board() -> Dictionary:
    return {"contracts": {
        "old-contract": {"status": "delivered", "meta": {"tags": [2]}},
        "new-contract": {"status": "posted", "meta": {"tags": [8]}}}}

func _oracle(world: Dictionary, site: Dictionary,
        board: Dictionary) -> Dictionary:
    var staged: Dictionary = world.duplicate()
    for domain in ["construction_sites", "construction_contracts",
            "faction_treasuries", "contract_board", "escrow_balances",
            "construction_receipts"]:
        staged[domain] = world[domain].duplicate(true)
    staged["construction_sites"]["new"] = site.duplicate(true)
    staged["construction_contracts"]["new-contract"] = "new"
    staged["faction_treasuries"]["f"] = 30000
    staged["contract_board"] = board.duplicate(true)
    staged["escrow_balances"]["escrow:new-contract"] = 10000
    return staged

func _initialize() -> void:
    var world: Dictionary = _world()
    var original: Dictionary = world.duplicate(true)
    var site: Dictionary = {"id": "new", "memory": {"nested": [5]}}
    var board: Dictionary = _board()
    var staged: Dictionary = N39._n154_owned_commission_stage(
        world, "new", site, true, "new-contract", "f",
        "escrow:new-contract", 30000, 10000, board)
    var oracle: Dictionary = _oracle(world, site, board)
    assert(not staged.is_empty())
    assert(staged == oracle)
    # The actual caller appends the same receipt after the helper returns.
    var receipt: Dictionary = {"id": "native_site_commission:new-contract",
        "tick": 1, "kind": "commission", "meta": {"nested": [7]}}
    staged["construction_receipts"][receipt["id"]] = receipt.duplicate(true)
    oracle["construction_receipts"][receipt["id"]] = receipt.duplicate(true)
    assert(staged == oracle)
    assert(world == original)
    # New mutable rows and the entire candidate board are detached.
    staged["construction_sites"]["new"]["memory"]["nested"].append(99)
    staged["contract_board"]["contracts"]["new-contract"]["meta"]["tags"].append(99)
    board["contracts"]["new-contract"]["meta"]["tags"].append(88)
    assert(world == original)
    assert(site["memory"]["nested"] == [5])
    assert(staged["contract_board"]["contracts"]["new-contract"]["meta"]["tags"] == [8, 99])
    # Repeated valid commission with the existing site does not clone its row.
    var again_board: Dictionary = staged["contract_board"].duplicate(true)
    again_board["contracts"]["second-contract"] = {"status": "posted"}
    var existing: Dictionary = N39._n154_owned_commission_stage(
        staged, "old", staged["construction_sites"]["old"], false,
        "second-contract", "f", "escrow:second-contract", 25000, 5000,
        again_board)
    assert(not existing.is_empty())
    assert(existing["construction_sites"]["old"] == original["construction_sites"]["old"])
    assert(world == original)
    # Negative: duplicate IDs, malformed registries, stale site and absent
    # candidate board entry must reject without changing authoritative World.
    assert(N39._n154_owned_commission_stage(
        world, "old", site, true, "new-contract", "f",
        "escrow:new-contract", 30000, 10000, _board()).is_empty())
    assert(N39._n154_owned_commission_stage(
        world, "new", site, true, "old-contract", "f",
        "escrow:new-contract", 30000, 10000, _board()).is_empty())
    var bad: Dictionary = _world()
    bad["construction_receipts"] = []
    assert(N39._n154_owned_commission_stage(
        bad, "new", site, true, "new-contract", "f",
        "escrow:new-contract", 30000, 10000, _board()).is_empty())
    assert(N39._n154_owned_commission_stage(
        world, "old", {"id": "changed"}, false, "new-contract", "f",
        "escrow:new-contract", 30000, 10000, _board()).is_empty())
    assert(N39._n154_owned_commission_stage(
        world, "new", site, true, "new-contract", "f",
        "escrow:new-contract", 30000, 10000, {"contracts": {}}).is_empty())
    # Oracle/Schema failure at caller: no stage publication.
    var rejected: Dictionary = N39._n154_owned_commission_stage(
        world, "new", site, true, "new-contract", "f",
        "escrow:new-contract", -500, 10000, _board())
    assert(rejected["faction_treasuries"]["f"] < 0)
    assert(world == original)
    print("PASS p2_perf_a_n154_commission_owned")
    quit()
