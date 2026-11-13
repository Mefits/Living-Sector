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
    var pop_ids: Array = source["populations"].keys()
    pop_ids.sort()
    for pid in pop_ids:
        var pop: Dictionary = source["populations"][pid]
        if str(pop.get("id", "")) != str(pid):
            return {"ok": false, "reason": "population_identity_mismatch"}
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
    for fid in source["facilities"]:
        facility_views[fid] = {
            "id": str(fid),
            "credits": int(source["facilities"][fid]["credits"])
        }
    for location in source["markets"]:
        var market: Dictionary = source["markets"][location]
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
