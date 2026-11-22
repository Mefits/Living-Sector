extends SceneTree
# Astra II-C D: streamed DTO adapter against independent N150+crisis oracle.
const Adapter = preload("res://scripts/sim/phase2/unified_market_phase.gd")
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const Crisis = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

func _market(id: String) -> Dictionary:
    return {"id": id, "elasticity": 0.15, "spread": 0.1,
        "supply": {"ore": 100.0}, "prices": {"ore": 12.0},
        "demand": {"ore": 4.0}, "seed_demand": {"ore": 4.0},
        "consumption_window": {"ore": [{"tick": 1, "qty": 2.0}]},
        "orders": {"pending_buys": [], "pending_sells": [],
            "reserved": {}, "order_expiry_ticks": 50},
        "history": {"shortage_ticks": {"ore": 0},
            "trend_samples": [], "spawned_at_tick": 1, "last_tick": 1}}

func _oracle(world: Dictionary, tick: int, mult: int) -> Dictionary:
    var by_id: Dictionary = {}
    for location in world["markets"]:
        var m: Dictionary = world["markets"][location]
        by_id[str(m["id"])] = str(location)
    var ids: Array = by_id.keys()
    ids.sort()
    var updates: Dictionary = {}
    var events: Array[Dictionary] = []
    for id in ids:
        var location: String = by_id[id]
        var m: Dictionary = world["markets"][location]
        var input: Dictionary = {"id": id, "facility_location": location,
            "pricing": {"price_elasticity": float(m["elasticity"]),
                "spread": float(m["spread"]), "prices": m["prices"],
                "supply": m["supply"], "demand": m["demand"]},
            "flow": {"seed_demand": m["seed_demand"],
                "consumption_window": m["consumption_window"]},
            "orders": m["orders"], "history": m["history"]}
        var changed: Dictionary = N150.tick_one_market(
            input, tick, mult, Callable(Price, "recalculate"))
        if not changed.get("ok", false):
            return {"ok": false, "reason": str(id) + ":" + str(changed.get("reason", ""))}
        updates[id] = changed["market"]
    var output: Dictionary = {}
    for id in ids:
        var result: Dictionary = updates[id]
        var location: String = by_id[id]
        var crisis: Dictionary = Crisis.stage_market_history(id, location, result["history"], true)
        if not crisis.get("ok", false):
            return {"ok": false, "reason": "native_market_crisis_" + str(crisis.get("reason", "invalid"))}
        events.append_array(crisis["events"])
        if result["pricing"]["supply"] != world["markets"][location]["supply"]:
            return {"ok": false, "reason": "market_tick_must_not_mint_stock"}
        output[location] = {"id": id, "prices": result["pricing"]["prices"],
            "demand": result["pricing"]["demand"],
            "seed_demand": result["flow"]["seed_demand"],
            "consumption_window": result["flow"]["consumption_window"],
            "orders": result["orders"], "history": crisis["history"]}
    return {"ok": true, "tick": tick, "updates": output,
        "market_count": output.size(), "crisis_events": events,
        "source": "N150 native full market tick + original Rust structural warning hysteresis + existing N131 price engine"}

func _initialize() -> void:
    var checks: int = 0
    for count in [0, 1, 3, 12]:
        for tick in [2, 16, 64, 201]:
            var markets: Dictionary = {}
            for i in range(count):
                # Reverse insertion order, but sorted market ID is canonical.
                var n: int = count - i
                markets["location-" + str(n)] = _market("market-" + str(n))
            var world: Dictionary = {"markets": markets}
            var before: Dictionary = world.duplicate(true)
            var actual: Dictionary = Adapter.propose(world, tick, 1)
            var expected: Dictionary = _oracle(world, tick, 1)
            assert(actual == expected, "streamed N150 mismatch count=%d tick=%d" % [count, tick])
            assert(world == before, "proposal modified authoritative market")
            if count > 0 and actual.get("ok", false):
                actual["updates"]["location-1"]["prices"]["ore"] = 999.0
                assert(world == before, "mutable alias escaped market proposal")
            checks += 1
    var malformed: Dictionary = {"markets": {
        "z": _market("z"), "a": _market("a")}}
    malformed["markets"]["z"]["prices"] = []
    var invalid: Dictionary = Adapter.propose(malformed, 16, 1)
    assert(not invalid.get("ok", true))
    assert(invalid.get("reason", "") == "invalid_native_market_field:prices")
    malformed["markets"]["z"] = _market("a")
    invalid = Adapter.propose(malformed, 16, 1)
    assert(invalid.get("reason", "") == "duplicate_native_market_id")
    malformed["markets"]["z"] = _market("z")
    malformed["markets"]["z"]["orders"]["pending_buys"] = [{"agent_id": 42, "placed_at_tick": 1}]
    invalid = Adapter.propose(malformed, 16, 1)
    assert(not invalid.get("ok", true), "malformed order must fail")
    print("PASS p2_perf_d_market_streamed_input cases=", checks + 3)
    quit()
