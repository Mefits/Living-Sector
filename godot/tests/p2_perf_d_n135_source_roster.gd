extends SceneTree
## Astra II-C D: N135 sorted source roster vs independent naive market scan.
const Phase = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {"markets": {}, "facilities": {}}
    for i in range(8):
        var loc: String = "loc%02d" % i
        var fid: String = "station%02d" % i
        world["facilities"][fid] = {"location": loc, "credits": 500,
            "faction": "f" + str(i % 2)}
        world["markets"][loc] = {"owner": fid, "supply": {"ore": 30.0},
            "prices": {"ore": 2.0}, "consumption_window": {}}
    # Two destinations compete for the same ordered suppliers.
    world["markets"]["loc06"]["supply"]["ore"] = 0.0
    world["markets"]["loc07"]["supply"]["ore"] = 0.0
    world["markets"]["loc06"]["consumption_window"] = {"ore": [{"tick": 1, "qty": 115.0}]}
    world["markets"]["loc07"]["consumption_window"] = {"ore": [{"tick": 1, "qty": 115.0}]}
    _oracle(world)
    # A moved owner invalidates a supplier on the next proposal.
    world["facilities"]["station01"]["location"] = "elsewhere"
    _oracle(world)
    world["facilities"]["station01"]["location"] = "loc01"
    world["markets"]["loc00"]["supply"]["ore"] = 4.0
    _oracle(world)
    # A missing owner is skipped as supplier, but rejected as destination.
    world["markets"]["loc02"]["owner"] = "missing"
    assert(not Phase.propose(world, 1).get("ok", true))
    world["markets"].erase("loc02")
    _oracle(world)
    # Bad supplier stock is checked only when actually visited by a deficit.
    world["markets"]["loc03"]["supply"]["ore"] = -1.0
    assert(Phase.propose(world, 1).get("reason", "") == "invalid_supplier_stock")
    world["markets"]["loc03"]["supply"]["ore"] = 30.0
    _oracle(world)
    # All indices are capture-local; no previous result can alter World.
    var before: Dictionary = world.duplicate(true)
    var result: Dictionary = Phase.propose(world, 1)
    result["proposals"].clear()
    assert(world == before)
    print("PASS p2_perf_d_n135_source_roster")
    quit(0)

func _oracle(world: Dictionary) -> void:
    var actual: Dictionary = Phase.propose(world, 1)
    assert(actual.get("ok", false))
    var expected: Array = _naive_proposals(world)
    assert(actual["proposals"] == expected)
    # Every funded proposal is only a forecast, never an N9 transaction.
    for row in actual["proposals"]:
        assert(row["status"] == "UNFUNDED_PROPOSAL")

func _naive_proposals(world: Dictionary) -> Array:
    var proposals: Array = []
    var reserved: Dictionary = {}
    var spent: Dictionary = {}
    var locations: Array = world["markets"].keys()
    locations.sort()
    for loc in locations:
        var market: Dictionary = world["markets"][loc]
        var owner_id: String = str(market["owner"])
        var owner: Dictionary = world["facilities"][owner_id]
        var commodities: Array = market["consumption_window"].keys()
        commodities.sort()
        for commodity in commodities:
            var consumed: float = 0.0
            for receipt in market["consumption_window"][commodity]:
                consumed += float(receipt["qty"])
            var stock: float = float(market["supply"].get(commodity, 0.0))
            if consumed <= stock or consumed <= 0.0:
                continue
            var remaining: int = int(ceil(consumed - stock))
            var price: float = float(market["prices"][commodity])
            # Deliberately reconstruct and sort the full registry per deficit,
            # as the original N135 did, rather than using Phase's roster.
            var sources: Array = world["markets"].keys()
            sources.sort()
            for source in sources:
                if remaining <= 0:
                    break
                if source == loc:
                    continue
                var supplier: Dictionary = world["markets"][source]
                var source_owner: String = str(supplier["owner"])
                if not world["facilities"].has(source_owner):
                    continue
                if str(world["facilities"][source_owner]["location"]) != str(source):
                    continue
                var key: String = str(source) + ":" + str(commodity)
                var available: int = maxi(0, int(floor(float(
                    supplier["supply"].get(commodity, 0.0)))) - int(reserved.get(key, 0)))
                var prior_spend: int = int(spent.get(owner_id, 0))
                var affordable: int = maxi(0, int(floor(float(
                    int(owner["credits"]) - prior_spend) / price)))
                var qty: int = mini(remaining, mini(available, affordable))
                if qty <= 0:
                    continue
                var cost: int = int(ceil(float(qty) * price))
                while qty > 0 and cost > int(owner["credits"]) - prior_spend:
                    qty -= 1
                    cost = int(ceil(float(qty) * price))
                if qty <= 0:
                    continue
                proposals.append({"id": "n135:need:%s:%s:%s" % [str(loc), str(commodity), str(source)],
                    "tick": 1, "station_id": owner_id, "location": str(loc),
                    "faction": str(owner["faction"]), "source_location": str(source),
                    "source_station_id": source_owner,
                    "source_available_stock": float(supplier["supply"].get(commodity, 0.0)),
                    "commodity": str(commodity), "quantity": qty,
                    "observed_consumption": consumed, "observed_stock": stock,
                    "estimated_cost": cost,
                    "reason": "observed_consumption_exceeds_physical_market_stock",
                    "status": "UNFUNDED_PROPOSAL"})
                reserved[key] = int(reserved.get(key, 0)) + qty
                spent[owner_id] = prior_spend + cost
                remaining -= qty
    return proposals
