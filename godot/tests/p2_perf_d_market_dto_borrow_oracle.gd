extends SceneTree
## N150 DTO ownership regression: compare borrowed read-only input with the
## original eager-deep-copy bridge, including failures and caller isolation.
const Phase = preload("res://scripts/sim/phase2/unified_market_phase.gd")
const Native = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const Crisis = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

func _market(id: String) -> Dictionary:
    return {
        "id": id, "supply": {"ore": 4.0}, "prices": {"ore": 20.0},
        "demand": {"ore": 8.0}, "elasticity": 0.05, "spread": 0.1,
        "seed_demand": {"ore": 8.0},
        "consumption_window": {"ore": [{"tick": 0, "qty": 2.0, "meta": {"nested": [1, 2]}}]},
        "orders": {"pending_buys": [{"agent_id": "buyer", "placed_at_tick": 0, "meta": {"nested": [3]}}],
            "pending_sells": [], "reserved": {}, "order_expiry_ticks": 50},
        "history": {"shortage_ticks": {"ore": 199}, "trend_samples": [],
            "spawned_at_tick": 0, "last_tick": 0}
    }

func _legacy(world: Dictionary, tick: int, multiplier: int) -> Dictionary:
    var views: Dictionary = {}
    for location in world["markets"]:
        var m: Dictionary = world["markets"][location]
        views[m["id"]] = {
            "id": m["id"], "facility_location": str(location),
            "pricing": {"price_elasticity": float(m["elasticity"]),
                "spread": float(m["spread"]), "prices": m["prices"].duplicate(true),
                "supply": m["supply"].duplicate(true), "demand": m["demand"].duplicate(true)},
            "flow": {"seed_demand": m["seed_demand"].duplicate(true),
                "consumption_window": m["consumption_window"].duplicate(true)},
            "orders": m["orders"].duplicate(true), "history": m["history"].duplicate(true)
        }
    var computed: Dictionary = Native.tick_markets(views, tick, multiplier, Callable(Price, "recalculate"))
    if not computed.get("ok", false):
        return computed
    var updates: Dictionary = {}
    var events: Array[Dictionary] = []
    for id in computed["markets"]:
        var result: Dictionary = computed["markets"][id]
        var location: String = result["facility_location"]
        var crisis: Dictionary = Crisis.stage_market_history(id, location, result["history"])
        if not crisis.get("ok", false):
            return crisis
        events.append_array(crisis["events"])
        updates[location] = {
            "id": id, "prices": result["pricing"]["prices"].duplicate(true),
            "demand": result["pricing"]["demand"].duplicate(true),
            "seed_demand": result["flow"]["seed_demand"].duplicate(true),
            "consumption_window": result["flow"]["consumption_window"].duplicate(true),
            "orders": result["orders"].duplicate(true), "history": crisis["history"].duplicate(true)}
    return {"ok": true, "updates": updates, "crisis_events": events}

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error(message)
        return false
    return true

func _initialize() -> void:
    var ok: bool = true
    var world: Dictionary = {"markets": {"earth": _market("m-earth"), "mars": _market("m-mars")}}
    for tick in [0, 16, 32, 200, 201]:
        var original: Dictionary = world.duplicate(true)
        var expected: Dictionary = _legacy(world, tick, 1)
        var actual: Dictionary = Phase.propose(world, tick, 1)
        ok = _check(actual.get("ok", false) == expected.get("ok", false), "status differs at tick " + str(tick)) and ok
        ok = _check(actual.get("updates", {}) == expected.get("updates", {}), "market projection differs at tick " + str(tick)) and ok
        ok = _check(actual.get("crisis_events", []) == expected.get("crisis_events", []), "warning order differs at tick " + str(tick)) and ok
        ok = _check(world == original, "borrowed input mutated at tick " + str(tick)) and ok
        if actual.get("ok", false):
            actual["updates"]["earth"]["orders"]["pending_buys"][0]["meta"]["nested"].append(99)
            if not actual["updates"]["earth"]["consumption_window"]["ore"].is_empty():
                actual["updates"]["earth"]["consumption_window"]["ore"][0]["meta"]["nested"].append(99)
            ok = _check(world == original, "nested output aliases caller at tick " + str(tick)) and ok
    var invalid: Dictionary = world.duplicate(true)
    invalid["markets"]["earth"]["orders"]["pending_buys"][0]["placed_at_tick"] = "bad"
    var before: Dictionary = invalid.duplicate(true)
    var rejected: Dictionary = Phase.propose(invalid, 16, 1)
    var legacy_rejected: Dictionary = _legacy(invalid, 16, 1)
    ok = _check(not rejected.get("ok", false) and not legacy_rejected.get("ok", false), "invalid order accepted") and ok
    ok = _check(invalid == before, "failure mutated caller") and ok
    print("p2_perf_d_market_dto_borrow_oracle: ", "PASS" if ok else "FAIL")
    quit(0 if ok else 1)
