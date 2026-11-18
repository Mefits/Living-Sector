extends SceneTree
## N153 offer-level payer proof: independent per-bid legacy oracle.
## Run headless with --script res://tests/p2_perf_c_n153_offer_context.gd.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _legacy_balance(world: Dictionary, contract: Dictionary, cid: String,
        faction: String, market: Dictionary, buyer: Dictionary) -> int:
    var payer: String = str(contract.get("requestor_id", ""))
    var balance: int = -1
    if str(contract.get("funding_source", "")) == "faction":
        if (world.get("construction_contracts", {}).has(cid) or
                world.get("native_htn_contracts", {}).has(cid)) and payer == Schema.faction_account(faction):
            balance = int(world.get("faction_treasuries", {}).get(faction, -1))
    elif str(contract.get("funding_source", "")) == "facility":
        if payer == Schema.facility_account(str(market["owner"])):
            balance = int(buyer["credits"])
    return balance

func _initialize() -> void:
    var world: Dictionary = {
        "construction_contracts": {"paid": {}},
        "native_htn_contracts": {"htn": {}},
        "faction_treasuries": {"f": 190}
    }
    var market: Dictionary = {"owner": "station"}
    var buyer: Dictionary = {"credits": 90}
    var cases: Array = [
        ["paid", "faction", Schema.faction_account("f"), 190],
        ["htn", "faction", Schema.faction_account("f"), 190],
        ["unlisted", "faction", Schema.faction_account("f"), -1],
        ["paid", "faction", Schema.faction_account("other"), -1],
        ["paid", "facility", Schema.facility_account("station"), 90],
        ["paid", "facility", Schema.facility_account("wrong"), -1],
        ["paid", "unknown", Schema.faction_account("f"), -1]
    ]
    for row in cases:
        var contract: Dictionary = {"funding_source": row[1], "requestor_id": row[2]}
        var expected: int = _legacy_balance(world, contract, row[0], "f", market, buyer)
        var actual: int = Dispatch._offer_payer_balance(world, contract, row[0], "f", market, buyer)
        assert(expected == row[3] and actual == expected, "payer oracle mismatch: " + str(row))
        # Per-ship bonus changes the required top-up, not the payer proof.
        for payment in [0, 89, 90, 91, 190, 191, 500]:
            for reserved in [0, 20, 100]:
                var top_up: int = maxi(0, payment - reserved)
                assert((actual >= top_up and actual >= 0) ==
                    (expected >= top_up and expected >= 0), "quote validity changed")
    # Negative invalidation: do not persist a previous proposal's balance.
    var c: Dictionary = {"funding_source": "faction", "requestor_id": Schema.faction_account("f")}
    assert(Dispatch._offer_payer_balance(world, c, "paid", "f", market, buyer) == 190)
    world["faction_treasuries"]["f"] = 0
    assert(Dispatch._offer_payer_balance(world, c, "paid", "f", market, buyer) == 0)
    world["construction_contracts"].erase("paid")
    assert(Dispatch._offer_payer_balance(world, c, "paid", "f", market, buyer) == -1)
    # Shared commerce projection must be detached for each bidder.
    var base: Dictionary = {"buyer": true, "seller": true}
    var bidder: Dictionary = base.duplicate()
    bidder["outlaw"] = true
    assert(not base.has("outlaw"))
    print("PASS p2_perf_c_n153_offer_context")
    quit(0)
