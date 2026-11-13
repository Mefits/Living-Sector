extends RefCounted
## P2 single-World N151 adapter. Pure plan only: no wallet/stock mutation.
## N39.apply_population_phase is the EXCLUSIVE economic commit authority.
const NativePop = preload("res://scripts/sim/phase1/n151_native_population_tick.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")

static func propose(source: Dictionary, tick: int,
        tick_scale: float, multiplier: int) -> Dictionary:
    for key in ["populations", "markets", "facilities"]:
        if not (source.get(key) is Dictionary):
            return {"ok": false, "reason": "missing_native_world:" + key}
    var pops: Array = []
    var fired: Dictionary = {}
    var seen_population_ids: Dictionary = {}
    var pop_ids: Array = source["populations"].keys()
    pop_ids.sort()
    for pid in pop_ids:
        var pop: Dictionary = source["populations"][pid]
        if str(pop.get("id", "")) != str(pid) or str(pid).is_empty():
            return {"ok": false, "reason": "population_identity_mismatch"}
        if seen_population_ids.has(str(pid)):
            return {"ok": false, "reason": "duplicate_population_id"}
        seen_population_ids[str(pid)] = true
        for required in ["location", "count", "wealth", "consumption",
                "food_satisfaction", "safety_satisfaction",
                "entertainment_satisfaction", "overall_sentiment",
                "migration_pressure"]:
            if not pop.has(required):
                return {"ok": false, "reason": "missing_population_field:" + required}
        if not (pop["consumption"] is Dictionary):
            return {"ok": false, "reason": "invalid_population_consumption"}
        if int(pop["count"]) < 0 or int(pop["wealth"]) < 0:
            return {"ok": false, "reason": "negative_population_or_wealth"}
        var projected: Dictionary = pop.duplicate(true)
        projected["facility_location"] = str(pop["location"])
        projected["population_count"] = int(pop["count"])
        projected["total_wealth"] = int(pop["wealth"])
        pops.append(projected)
        # All real starter populations have AgentLod default divisor=1.
        # Later N140 must become the one selector for newly spawned pops.
        fired[pid] = 1
    var market_views: Dictionary = {}
    var facility_views: Dictionary = {}
    var facility_ids: Array = source["facilities"].keys()
    facility_ids.sort()
    for fid in facility_ids:
        var facility: Dictionary = source["facilities"][fid]
        if str(fid).is_empty() or not facility.has("credits") or int(facility["credits"]) < 0:
            return {"ok": false, "reason": "invalid_market_seller_account"}
        facility_views[fid] = {
            "id": str(fid),
            "credits": int(facility["credits"])
        }
    var market_locations: Array = source["markets"].keys()
    market_locations.sort()
    for location in market_locations:
        var market: Dictionary = source["markets"][location]
        for required in ["id", "owner", "supply", "prices", "consumption_window"]:
            if not market.has(required):
                return {"ok": false, "reason": "missing_market_field:" + required}
        if not facility_views.has(str(market["owner"])):
            return {"ok": false, "reason": "market_seller_missing_from_single_world"}
        for required in ["supply", "prices", "consumption_window"]:
            if not (market[required] is Dictionary):
                return {"ok": false, "reason": "invalid_market_field:" + required}
        market_views[location] = {
            "id": str(market["id"]),
            "facility_location": str(location),
            "owner_facility_id": str(market["owner"]),
            "supply": market["supply"].duplicate(true),
            "prices": market["prices"].duplicate(true),
            "consumption_window": market["consumption_window"].duplicate(true)
        }
    var base_prices: Dictionary = {}
    for slug in Catalog.ORDER:
        base_prices[slug] = Catalog.base_price(slug)
    var native_world: Dictionary = {
        "populations": pops,
        "markets": market_views,
        "facilities": facility_views,
        "fired": fired,
        "commodity_base_prices": base_prices
    }
    var result: Dictionary = NativePop.tick_populations(native_world,
        tick, tick_scale, multiplier)
    if not result.get("ok", false):
        return result
    return {"ok": true, "tick": tick, "native_result": result,
        "purchase_count": result["purchases"].size(),
        "source": "N151 source population phase single-N9 ledger commit"}
