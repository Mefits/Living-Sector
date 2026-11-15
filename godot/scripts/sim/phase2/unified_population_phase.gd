extends RefCounted
## P2 single-World N151 adapter. Pure plan only: no wallet/stock mutation.
## N39.apply_population_phase is the EXCLUSIVE economic commit authority.
const NativePop = preload("res://scripts/sim/phase1/n151_native_population_tick.gd")
const NativeMigration = preload("res://scripts/sim/phase1/n151_native_population_migration.gd")
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
        if not (source["populations"][pid] is Dictionary):
            return {"ok": false, "reason": "invalid_population_row"}
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
        if not _valid_nonnegative_integer(pop["count"]) or not _valid_nonnegative_integer(pop["wealth"]):
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
        if not (source["facilities"][fid] is Dictionary):
            return {"ok": false, "reason": "invalid_facility_row"}
        var facility: Dictionary = source["facilities"][fid]
        if str(fid).is_empty() or not facility.has("credits") or not _valid_nonnegative_integer(facility["credits"]):
            return {"ok": false, "reason": "invalid_market_seller_account"}
        facility_views[fid] = {
            "id": str(fid),
            "credits": int(facility["credits"])
        }
    var market_locations: Array = source["markets"].keys()
    market_locations.sort()
    for location in market_locations:
        if not (source["markets"][location] is Dictionary):
            return {"ok": false, "reason": "invalid_market_row"}
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

## JSON restore may supply integral floats; reject fractional, NaN, negative,
## and values outside the exact JSON integer range before paid ledger admission.
static func _valid_nonnegative_integer(value: Variant) -> bool:
    if not (value is int or value is float):
        return false
    var number: float = float(value)
    return is_finite(number) and number >= 0.0 and number <= 9007199254740991.0 and float(int(number)) == number

## Frozen agents/population.rs::run_population_migration — one abstract
## demographic transfer on 200*mult tick only. Distinct from N147 physical
## passenger contracts; no ship or new colony is created by this phase.
## The N39 owner ALWAYS recomputes this candidate from its own World.
static func migration_proposal(source: Dictionary, tick: int,
        multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1 or multiplier > 10000:
        return {"ok": false, "reason": "invalid_native_migration_clock"}
    if tick % (NativePop.MIGRATION_CHECK_INTERVAL_BASE * multiplier) != 0:
        return {"ok": true, "due": false, "moved": 0}
    for field in ["populations", "facilities", "markets"]:
        if not (source.get(field) is Dictionary):
            return {"ok": false, "reason": "missing_native_migration_" + field}
    var population_ids: Array = source["populations"].keys()
    population_ids.sort() # stable canonical world order across N38 restore
    var projected: Array = []
    for id in population_ids:
        var p: Variant = source["populations"][id]
        if not (p is Dictionary) or str(p.get("id", "")) != str(id):
            return {"ok": false, "reason": "invalid_population_migration_identity"}
        var pop: Dictionary = p
        var location: String = str(pop.get("location", ""))
        var dock: bool = false
        for fac in source["facilities"].values():
            if fac is Dictionary and str(fac.get("location", "")) == location and str(fac.get("type", "")) == "construction_dock":
                dock = true
                break
        projected.append({
            "id": str(id), "label": str(pop.get("label", id)),
            "facility_location": location,
            "population_count": int(pop.get("count", -1)),
            "total_wealth": int(pop.get("wealth", -1)),
            "migration_pressure": pop.get("migration_pressure", -1.0),
            "overall_sentiment": int(pop.get("overall_sentiment", 50)),
            "is_dock": dock})
    var source_next: Dictionary = NativeMigration.migrate(projected, tick)
    if not source_next.get("ok", false):
        return source_next
    var moved: int = int(source_next.get("moved", 0))
    if moved == 0:
        return {"ok": true, "due": true, "moved": 0, "events": []}
    var events: Array = source_next.get("events", [])
    if events.size() != 1 or not (events[0] is Dictionary):
        return {"ok": false, "reason": "missing_native_migration_event"}
    var event: Dictionary = events[0]
    var from: String = str(event.get("source_id", ""))
    var to: String = str(event.get("destination_id", ""))
    if from == to or not source["populations"].has(from) or not source["populations"].has(to):
        return {"ok": false, "reason": "invalid_native_migration_endpoints"}
    return {"ok": true, "due": true, "moved": moved,
        "wealth": int(source_next.get("wealth_transferred", -1)),
        "from": from, "to": to, "event": event.duplicate(true),
        "after": source_next["populations"].duplicate(true)}
