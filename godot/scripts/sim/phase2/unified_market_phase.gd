extends RefCounted
## P2 unified: materialize N150 native Market tick onto SAME N39 market.
## This is a pure proposal; only production.apply_market_phase commits.
## No alternate stock, wallet, ContractBoard or invented market trades.
const Markets = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")

static func propose(physical_world: Dictionary, tick: int,
        tick_multiplier: int) -> Dictionary:
    if not (physical_world.get("markets") is Dictionary):
        return {"ok": false, "reason": "missing_authoritative_market"}
    var views: Dictionary = {}
    var owner_by_id: Dictionary = {}
    for location in physical_world["markets"]:
        var m: Dictionary = physical_world["markets"][location]
        for key in ["id", "supply", "prices", "demand", "elasticity",
                "spread", "seed_demand", "consumption_window", "orders", "history"]:
            if not m.has(key):
                return {"ok": false, "reason": "incomplete_native_market:" + str(key)}
        var id: String = str(m["id"])
        if id.is_empty() or views.has(id):
            return {"ok": false, "reason": "duplicate_native_market_id"}
        owner_by_id[id] = str(location)
        views[id] = {
            "id": id, "facility_location": str(location),
            "pricing": {
                "price_elasticity": float(m["elasticity"]),
                "spread": float(m["spread"]),
                "prices": m["prices"].duplicate(true),
                "supply": m["supply"].duplicate(true),
                "demand": m["demand"].duplicate(true)
            },
            "flow": {
                "seed_demand": m["seed_demand"].duplicate(true),
                "consumption_window": m["consumption_window"].duplicate(true)
            },
            "orders": m["orders"].duplicate(true),
            "history": m["history"].duplicate(true)
        }
    var computed: Dictionary = Markets.tick_markets(views, tick,
        tick_multiplier, Callable(Price, "recalculate"))
    if not computed.get("ok", false):
        return {"ok": false, "reason": str(computed.get("reason", "native_market_tick_rejected"))}
    var updates: Dictionary = {}
    var output: Dictionary = computed["markets"]
    for id in output:
        if not owner_by_id.has(id):
            return {"ok": false, "reason": "unregistered_native_market"}
        var location: String = str(owner_by_id[id])
        var result: Dictionary = output[id]
        var m: Dictionary = physical_world["markets"][location]
        if result["pricing"]["supply"] != m["supply"]:
            return {"ok": false, "reason": "market_tick_must_not_mint_stock"}
        updates[location] = {
            "id": id,
            "prices": result["pricing"]["prices"].duplicate(true),
            "demand": result["pricing"]["demand"].duplicate(true),
            "seed_demand": result["flow"]["seed_demand"].duplicate(true),
            "consumption_window": result["flow"]["consumption_window"].duplicate(true),
            "orders": result["orders"].duplicate(true),
            "history": result["history"].duplicate(true)
        }
    return {"ok": true, "tick": tick, "updates": updates,
        "market_count": updates.size(),
        "source": "N150 native full market tick + existing N131 price engine"}
