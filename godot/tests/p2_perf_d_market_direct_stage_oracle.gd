extends SceneTree
## Astra II-C/D: exact N150 sorted batch oracle against direct owned staging.
const Adapter = preload("res://scripts/sim/phase2/unified_market_phase.gd")
const Native = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const Crisis = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

func _initialize() -> void:
    var failures: Array[String] = []
    for tick in [1, 16, 51, 100, 400]:
        for count in [0, 1, 3, 12]:
            _positive(tick, count, failures)
    _negative(failures)
    if not failures.is_empty():
        for failure in failures:
            push_error(failure)
        quit(1)
        return
    print("PASS p2_perf_d_market_direct_stage_oracle")
    quit(0)

func _market(id: String) -> Dictionary:
    return {"id": id, "owner": "facility-" + id,
        "supply": {"ore": 40.0}, "prices": {"ore": 10.0},
        "demand": {"ore": 2.0}, "elasticity": 0.1, "spread": 0.05,
        "seed_demand": {"ore": 2.0},
        "consumption_window": {"ore": [{"tick": 1, "qty": 3.0}]},
        "orders": {"pending_buys": [], "pending_sells": [],
            "reserved": {}, "order_expiry_ticks": 50},
        "history": {"shortage_ticks": {"ore": 199},
            "trend_samples": [], "spawned_at_tick": 0, "last_tick": 0}}

func _oracle(world: Dictionary, tick: int) -> Dictionary:
    var views: Dictionary = {}
    var owner_by_id: Dictionary = {}
    for location in world["markets"]:
        var m: Dictionary = world["markets"][location]
        var id: String = str(m["id"])
        if views.has(id):
            return {"ok": false, "reason": "duplicate_native_market_id"}
        owner_by_id[id] = location
        views[id] = {"id": id, "facility_location": location,
            "pricing": {"price_elasticity": m["elasticity"], "spread": m["spread"],
                "prices": m["prices"], "supply": m["supply"], "demand": m["demand"]},
            "flow": {"seed_demand": m["seed_demand"],
                "consumption_window": m["consumption_window"]},
            "orders": m["orders"], "history": m["history"]}
    var computed: Dictionary = Native.tick_markets(views, tick, 1,
        Callable(Price, "recalculate"))
    if not computed.get("ok", false):
        return computed
    var updates: Dictionary = {}
    var events: Array[Dictionary] = []
    for id in computed["markets"]:
        var result: Dictionary = computed["markets"][id]
        var location: String = owner_by_id[id]
        var crisis: Dictionary = Crisis.stage_market_history(
            id, location, result["history"], true)
        if not crisis.get("ok", false):
            return crisis
        events.append_array(crisis["events"])
        if result["pricing"]["supply"] != world["markets"][location]["supply"]:
            return {"ok": false, "reason": "market_tick_must_not_mint_stock"}
        updates[location] = {"id": id, "prices": result["pricing"]["prices"],
            "demand": result["pricing"]["demand"],
            "seed_demand": result["flow"]["seed_demand"],
            "consumption_window": result["flow"]["consumption_window"],
            "orders": result["orders"], "history": crisis["history"]}
    return {"ok": true, "updates": updates, "crisis_events": events}

func _positive(tick: int, count: int, failures: Array[String]) -> void:
    var world: Dictionary = {"markets": {}}
    for i in range(count):
        var id: String = "market-%03d" % (count - i)
        world["markets"]["location-%03d" % i] = _market(id)
    var original: Dictionary = world.duplicate(true)
    var expected: Dictionary = _oracle(world, tick)
    var actual: Dictionary = Adapter.propose(world, tick, 1)
    if actual.get("ok") != expected.get("ok") or (
            actual.get("ok", false) and (
            actual.get("updates") != expected.get("updates") or
            actual.get("crisis_events") != expected.get("crisis_events"))):
        failures.append("N150 oracle mismatch tick=%d count=%d" % [tick, count])
    if world != original:
        failures.append("adapter mutated authoritative World")
    if actual.get("ok", false) and count > 0:
        var location: String = world["markets"].keys()[0]
        actual["updates"][location]["prices"]["ore"] = 999.0
        if world != original:
            failures.append("output aliases source World")

func _negative(failures: Array[String]) -> void:
    var world: Dictionary = {"markets": {"a": _market("a"), "b": _market("b")}}
    world["markets"]["b"]["consumption_window"]["ore"] = [
        {"tick": 1, "qty": "bad"}]
    var before: Dictionary = world.duplicate(true)
    var actual: Dictionary = Adapter.propose(world, 400, 1)
    var expected: Dictionary = _oracle(world, 400)
    if actual.get("ok", true) or expected.get("ok", true) or (
            actual.get("reason") != expected.get("reason")):
        failures.append("later invalid market must reject atomically in sorted order")
    if world != before:
        failures.append("negative tick mutated source")
    world = {"markets": {"a": _market("duplicate"), "b": _market("duplicate")}}
    actual = Adapter.propose(world, 16, 1)
    if actual.get("ok", true) or actual.get("reason") != "duplicate_native_market_id":
        failures.append("duplicate market identity accepted")
