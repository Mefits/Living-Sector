extends RefCounted
## P2 unified: materialize N150 native Market tick onto SAME N39 market.
## This is a pure proposal; only production.apply_market_phase commits.
## No alternate stock, wallet, ContractBoard or invented market trades.
const Markets = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const NativeCrisisWarnings = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

static func propose(physical_world: Dictionary, tick: int,
        tick_multiplier: int) -> Dictionary:
    if not (physical_world.get("markets") is Dictionary):
        return {"ok": false, "reason": "missing_authoritative_market"}
    # N150 tick_one_market validates and deep-copies each market before any mutation.
    # These DTO fields are borrowed read-only until that ownership boundary;
    # copying them here duplicates the entire market graph a second time.
    # No caller-owned reference may escape in updates (detached below).
    # Preflight all rows before any N150 tick; only retain scalar IDs.
    # Assemble each borrowed DTO immediately before its sorted execution.
    var owner_by_id: Dictionary = {}
    for location in physical_world["markets"]:
        if not (physical_world["markets"][location] is Dictionary):
            return {"ok": false, "reason": "invalid_authoritative_market_row"}
        var m: Dictionary = physical_world["markets"][location]
        for key in ["id", "supply", "prices", "demand", "elasticity",
                "spread", "seed_demand", "consumption_window", "orders", "history"]:
            if not m.has(key):
                return {"ok": false, "reason": "incomplete_native_market:" + str(key)}
        for field in ["supply", "prices", "demand", "seed_demand", "consumption_window", "orders", "history"]:
            if not (m[field] is Dictionary):
                return {"ok": false, "reason": "invalid_native_market_field:" + field}
        if not (m["elasticity"] is float or m["elasticity"] is int) or not (m["spread"] is float or m["spread"] is int):
            return {"ok": false, "reason": "invalid_native_market_pricing"}
        var id: String = str(m["id"])
        if id.is_empty() or owner_by_id.has(id):
            return {"ok": false, "reason": "duplicate_native_market_id"}
        owner_by_id[id] = str(location)

    # N150 validates every market in sorted identity order before crisis
    # staging. Preserve that failure precedence while avoiding the second
    # full-sized output registry: the owned results live in updates, then
    # are replaced in place with final N39 proposals after all ticks pass.
    var ids: Array = owner_by_id.keys()
    ids.sort()
    var updates: Dictionary = {}
    var crisis_events: Array[Dictionary] = []
    for id in ids:
        if not (id is String):
            return {"ok": false, "reason": "invalid_real_market_registry"}
        var location: String = str(owner_by_id[id])
        var m: Dictionary = physical_world["markets"][location]
        var input: Dictionary = {
            "id": id, "facility_location": str(location),
            "pricing": {
                "price_elasticity": float(m["elasticity"]),
                "spread": float(m["spread"]),
                "prices": m["prices"],
                "supply": m["supply"],
                "demand": m["demand"]
            },
            "flow": {
                "seed_demand": m["seed_demand"],
                "consumption_window": m["consumption_window"]
            },
            "orders": m["orders"],
            "history": m["history"]
        }
        if str(input.get("id", "")) != str(id):
            return {"ok": false, "reason": "market_identity_mismatch"}
        var changed: Dictionary = Markets.tick_one_market(input, tick,
            tick_multiplier, Callable(Price, "recalculate"))
        if not bool(changed.get("ok", false)):
            return {"ok": false, "reason": str(id) + ":" +
                str(changed.get("reason", ""))}
        updates[id] = changed["market"]
    for id in ids:
        var result: Dictionary = updates[id]
        var location: String = str(owner_by_id[id])
        if not (result.get("pricing") is Dictionary) or not (result.get("flow") is Dictionary):
            return {"ok": false, "reason": "invalid_native_market_result_sections"}
        for key in ["prices", "supply", "demand"]:
            if not (result["pricing"].get(key) is Dictionary):
                return {"ok": false, "reason": "invalid_native_market_result_pricing:" + key}
        for key in ["seed_demand", "consumption_window"]:
            if not (result["flow"].get(key) is Dictionary):
                return {"ok": false, "reason": "invalid_native_market_result_flow:" + key}
        for key in ["orders", "history"]:
            if not (result.get(key) is Dictionary):
                return {"ok": false, "reason": "invalid_native_market_result_field:" + key}
        # Original sim_server::scan_crisis_events follows the N150 market
        # phase; stage hysteresis in canonical MarketHistory before N39 Apply.
        var crisis: Dictionary = NativeCrisisWarnings.stage_market_history(
            str(id), location, result["history"], true)
        if not crisis.get("ok", false):
            return {"ok": false, "reason": "native_market_crisis_" + str(crisis.get("reason", "invalid"))}
        crisis_events.append_array(crisis["events"])
        var m: Dictionary = physical_world["markets"][location]
        if result["pricing"]["supply"] != m["supply"]:
            return {"ok": false, "reason": "market_tick_must_not_mint_stock"}
        updates[id] = {
            "id": id,
            # N150 tick_markets returns a freshly deep-owned market for every
            # identity. This proposal is the sole consumer of those markets;
            # re-duplicating growing orders/windows/history here costs another
            # complete traversal per paid tick. Crisis staging also returns a
            # detached history. None of these values alias physical_world.
            "prices": result["pricing"]["prices"],
            "demand": result["pricing"]["demand"],
            "seed_demand": result["flow"]["seed_demand"],
            "consumption_window": result["flow"]["consumption_window"],
            "orders": result["orders"],
            "history": crisis["history"]
        }
    var by_location: Dictionary = {}
    for id in ids:
        by_location[str(owner_by_id[id])] = updates[id]
    return {"ok": true, "tick": tick, "updates": by_location,
        "market_count": updates.size(),
        "crisis_events": crisis_events,
        "source": "N150 native full market tick + original Rust structural warning hysteresis + existing N131 price engine"}
