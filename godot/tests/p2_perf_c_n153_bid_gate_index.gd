extends SceneTree
## Independent pre-index vs original per-offer N153 bidder rejection oracle.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")

func _oracle(ship: Dictionary, factions: Dictionary, seller: String,
        buyer: String, assigned: bool) -> Dictionary:
    var faction: String = str(ship.get("faction_id", ""))
    if not factions.has(faction) or assigned:
        return {"ok": false, "reason": "ship_faction_missing_or_already_assigned"}
    if str(factions[faction].get("type", "")) == "outlaw" and (faction != buyer or faction != seller):
        return {"ok": false, "reason": "outlaw_source_commerce_restricted"}
    var reputation: Dictionary = ship.get("faction_reputation", {})
    var posture: Dictionary = MarketRules.posture({}, faction, seller,
        int(reputation.get(seller, 0)))
    if not posture.get("ok", false):
        return {"ok": false, "reason": "source_reputation_posture_rejected"}
    return {"ok": true, "multiplier": float(posture["multiplier"])}

func _check(world: Dictionary, factions: Dictionary, offers: Array) -> void:
    var ids: Array = world["ships"].keys()
    ids.sort()
    var rows: Array = Dispatch._bidder_rows(world, ids, factions)
    var gate_cache: Dictionary = {}
    var posture_cache: Dictionary = {}
    var assigned: Dictionary = {}
    var old_reasons: Dictionary = {}
    var new_reasons: Dictionary = {}
    for offer in offers:
        var seller: String = str(offer["seller"])
        var buyer: String = str(offer["buyer"])
        for row in rows:
            var id: String = str(row["id"])
            var expected: Dictionary = _oracle(world["ships"][id], factions,
                seller, buyer, assigned.has(id))
            var actual: Dictionary = {"ok": false,
                "reason": "ship_faction_missing_or_already_assigned"}
            if not assigned.has(id):
                actual = Dispatch._seller_bidder_gate(row, seller, buyer,
                    posture_cache, gate_cache)
            assert(actual == expected)
            if not expected["ok"]:
                var reason: String = str(expected["reason"])
                old_reasons[reason] = int(old_reasons.get(reason, 0)) + 1
            if not actual["ok"]:
                var actual_reason: String = str(actual["reason"])
                new_reasons[actual_reason] = int(new_reasons.get(actual_reason, 0)) + 1
        # Mimic earlier offer's accepted winner: assignment must override a
        # previously cached reputation/outlaw result on later offers.
        if bool(offer.get("assign", false)):
            assigned[str(offer["ship"])] = true
    assert(new_reasons == old_reasons)
    assert(rows.size() == ids.size())
    for i in range(ids.size()):
        assert(str(rows[i]["id"]) == str(ids[i]))

func _initialize() -> void:
    var factions: Dictionary = {
        "a": {"type": "regular"}, "b": {"type": "regular"},
        "pirate": {"type": "outlaw"}}
    var world: Dictionary = {"ships": {}}
    for i in range(240):
        var id: String = "ship_%03d" % i
        var faction: String = ["a", "b", "pirate", "missing"][i % 4]
        world["ships"][id] = {"faction_id": faction,
            "faction_reputation": {"a": (i % 9 - 4) * 25,
                "b": (i % 7 - 3) * 30, "pirate": (i % 5 - 2) * 50}}
    var offers: Array = []
    for i in range(18):
        offers.append({"seller": ["a", "b", "pirate"][i % 3],
            "buyer": ["b", "a", "pirate"][i % 3],
            "assign": i % 2 == 0, "ship": "ship_%03d" % (i * 3)})
    _check(world, factions, offers)
    # Negative: a new propose must not reuse faction, ownership or reputation.
    world["ships"]["ship_000"]["faction_id"] = "pirate"
    world["ships"]["ship_001"]["faction_reputation"]["a"] = -999
    factions["b"]["type"] = "outlaw"
    _check(world, factions, offers)
    # Negative: no mutable alias in cached gate output may alter World rows.
    var rows: Array = Dispatch._bidder_rows(world, world["ships"].keys(), factions)
    var gate: Dictionary = Dispatch._seller_bidder_gate(rows[0], "a", "b", {}, {})
    gate["reason"] = "changed_by_test"
    assert(not world["ships"][str(rows[0]["id"])].has("reason"))
    print("PASS p2_perf_c_n153_bid_gate_index")
    quit(0)
