extends RefCounted
## Frozen Rust ship/mod.rs::observe_prices, tick_ships Pass 2:
## real N140-fired, stationary ships learn ONLY reachable original N39
## MarketPricing through fitted comms: T1 body, T2 system, T3 one
## *actual paired-gate* neighboring system. Never see omniscient prices.
## Pure ONE-World ship-memory staging, no price or credit writes.
const Modules = preload("res://scripts/port/n108_shipyard_module_catalog.gd")

static func default_memory() -> Dictionary:
    # Native ShipMemory::default: no knowledge, no visited routes,
    # no route performance or deferred contract IDs on creation.
    return {"price_knowledge": {}, "visited": [], "recent_systems": [],
        "route_performance": {}, "contract_rejections": {}}

static func _comms_tier(ship: Dictionary) -> int:
    var fit: Variant = ship.get("fitting", null)
    if not (fit is Dictionary) or not (fit.get("slots") is Dictionary):
        return 1 # Rust ship without known fitted module defaults to T1.
    var slug: String = str(fit["slots"].get("comms", ""))
    if not Modules.MODULES.has(slug) or str(Modules.MODULES[slug].get("slot", "")) != "comms":
        return 1
    match slug:
        "comms_t3":
            return 3
        "comms_t2":
            return 2
        _:
            return 1

static func _neighbors(world: Dictionary, resolver: RefCounted) -> Dictionary:
    # Original Rust gate_pairs_snapshot, NOT a synthetic graph edge.
    # Only existing reciprocal GateLink records permit cross-system
    # observation at comms T3. Native paid GateJump uses the same proof.
    var neighboring: Dictionary = {}
    var facilities: Dictionary = world.get("facilities", {})
    for fid in facilities:
        var facility: Variant = facilities[fid]
        if not (facility is Dictionary) or not (facility.get("gate_link") is Dictionary):
            continue
        var paired: String = str(facility["gate_link"].get("paired_gate_id", ""))
        if not facilities.has(paired) or not (facilities[paired] is Dictionary):
            continue
        var other: Dictionary = facilities[paired]
        if not (other.get("gate_link") is Dictionary) or str(other["gate_link"].get(
                "paired_gate_id", "")) != str(fid):
            continue
        var from_loc: String = str(facility.get("location", ""))
        var to_loc: String = str(other.get("location", ""))
        var from_system: String = resolver.system_for_location(from_loc)
        var to_system: String = resolver.system_for_location(to_loc)
        if from_system.is_empty() or to_system.is_empty() or from_system == to_system:
            continue
        if not neighboring.has(from_system):
            neighboring[from_system] = {}
        if not neighboring.has(to_system):
            neighboring[to_system] = {}
        neighboring[from_system][to_system] = true
        neighboring[to_system][from_system] = true
    return neighboring

static func stage(world: Dictionary, resolver: RefCounted, tick: int,
        fired: Dictionary) -> Dictionary:
    if tick < 1 or resolver == null or not resolver.has_method("body_for_location") or not resolver.has_method("system_for_location"):
        return {"ok": false, "reason": "n150_ship_prices_invalid_source_registry"}
    if not (world.get("ships") is Dictionary) or not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "n150_ship_prices_missing_original_world"}
    var ships: Dictionary = world["ships"].duplicate(true)
    var market_prices: Dictionary = {}
    var systems: Dictionary = {}
    var bodies: Dictionary = {}
    var markets: Dictionary = world["markets"]
    for loc in markets:
        var market: Variant = markets[loc]
        if not (market is Dictionary) or not (market.get("prices") is Dictionary):
            return {"ok": false, "reason": "n150_bad_actual_market_prices"}
        var prices: Dictionary = market["prices"]
        for commodity in prices:
            var price: Variant = prices[commodity]
            if not (commodity is String) or str(commodity).is_empty() or not (price is float or price is int) or not is_finite(float(price)) or float(price) < 0.0:
                return {"ok": false, "reason": "n150_invalid_native_market_commodity"}
        market_prices[str(loc)] = prices
        systems[str(loc)] = resolver.system_for_location(str(loc))
        bodies[str(loc)] = resolver.body_for_location(str(loc))
    var neighboring: Dictionary = _neighbors(world, resolver)
    var ids: Array = fired.keys()
    ids.sort()
    var observed: Array = []
    var changed: bool = false
    for sid in ids:
        if not ships.has(sid) or typeof(fired[sid]) != TYPE_INT or int(fired[sid]) < 1:
            return {"ok": false, "reason": "n150_foreign_lod_ship"}
        var ship: Dictionary = ships[sid]
        if not (ship.get("transit", null) is Dictionary):
            return {"ok": false, "reason": "n150_missing_physical_ship_position"}
        if not ship["transit"].is_empty():
            continue # Rust position.location_name=None in flight.
        var location: String = str(ship.get("location", ""))
        if location.is_empty():
            continue
        var current_memory: Variant = ship.get("memory", null)
        if current_memory == null:
            current_memory = default_memory() # genuine old P2 checkpoint.
        if not (current_memory is Dictionary) or not (current_memory.get("price_knowledge") is Dictionary):
            return {"ok": false, "reason": "n150_invalid_existing_ship_memory"}
        var memory: Dictionary = current_memory.duplicate(true)
        var knowledge: Dictionary = memory["price_knowledge"]
        var source_body: String = resolver.body_for_location(location)
        var source_system: String = resolver.system_for_location(location)
        var tier: int = _comms_tier(ship)
        var count: int = 0
        var market_ids: Array = market_prices.keys()
        market_ids.sort()
        for market_loc in market_ids:
            var permitted: bool = str(market_loc) == location
            if not permitted and not source_body.is_empty() and not bodies[market_loc].is_empty() and bodies[market_loc] == source_body:
                permitted = true
            if not permitted and tier >= 2 and not source_system.is_empty() and systems[market_loc] == source_system:
                permitted = true
            if not permitted and tier >= 3 and not source_system.is_empty() and neighboring.get(source_system, {}).has(systems[market_loc]):
                permitted = true
            if not permitted:
                continue
            var entry: Dictionary = knowledge.get(market_loc, {}).duplicate(true)
            for commodity in market_prices[market_loc]:
                entry[str(commodity)] = {"price": float(market_prices[market_loc][commodity]),
                    "tick": tick}
                count += 1
            knowledge[market_loc] = entry
        memory["price_knowledge"] = knowledge
        if memory != current_memory:
            ship["memory"] = memory
            changed = true
        observed.append({"ship_id": str(sid), "comms_tier": tier,
            "prices_observed": count, "tick": tick,
            "locations_known": knowledge.size()})
    return {"ok": true, "changed": changed, "ships": ships, "tick": tick,
        "observed": observed, "active_count": ids.size()}
