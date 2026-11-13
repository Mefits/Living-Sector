extends RefCounted
## P2 N158: ONLY authoritative frozen Galaxy 0.6.7 JSON -> N39 paid
## production projection. No fabricated world, wallets, market price or
## resource. This adapter DOES NOT simulate ships, population consumption
## or faction AI (those remain separate Phase2 integrations).
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

const NATIVE_CREW_BY_TYPE: Dictionary = {
    "station": 20, "shipyard": 16, "refinery": 12, "factory": 12,
    "farm": 6, "mining_rig": 8, "outpost": 6,
    "gate": 0, "construction_dock": 0
}
const INITIAL_MORALE: float = 80.0

static func from_seed(seed: Dictionary) -> Dictionary:
    if not (seed.get("worlds") is Array) or not (seed.get("factions") is Array):
        return _fail("missing_real_galaxy_seed")
    var factions: Dictionary = {}
    for f in seed["factions"]:
        if not (f is Dictionary) or not _id(f.get("id", null)):
            return _fail("invalid_seed_faction")
        if factions.has(f["id"]):
            return _fail("duplicate_faction")
        factions[f["id"]] = true
    var projected: Dictionary = {
        "facilities": {}, "markets": {}, "populations": {}, "bodies": {},
        "research": {}, "location_tiers": {},
        "station_executing": false
    }
    var all_facilities: Dictionary = {}
    var source_markets: Array = []
    var source_populations: Array = []
    for solar_system in seed["worlds"]:
        if not (solar_system is Dictionary):
            return _fail("invalid_system")
        for body in solar_system.get("bodies", []):
            if not (body is Dictionary) or not _id(body.get("id", null)):
                return _fail("invalid_source_body")
            var bid: String = str(body["id"])
            if projected["bodies"].has(bid) or not (body.get("resources") is Dictionary):
                return _fail("duplicate_or_incomplete_body")
            projected["bodies"][bid] = {
                "resources": body["resources"].duplicate(true)
            }
        for fac in solar_system.get("facilities", []):
            if not (fac is Dictionary):
                return _fail("invalid_source_facility")
            var id: String = str(fac.get("id", ""))
            if id.is_empty() or all_facilities.has(id) or not factions.has(fac.get("faction_id", "")):
                return _fail("duplicate_or_foreign_facility")
            if not _id(fac.get("location", null)) or not _id(fac.get("body", null)):
                return _fail("facility_missing_source_location")
            if not projected["bodies"].has(str(fac["body"])):
                return _fail("facility_missing_actual_body")
            if typeof(fac.get("credits", null)) != TYPE_INT or int(fac["credits"]) < 0:
                return _fail("invalid_source_facility_credits")
            if not _id(fac.get("type", null)):
                return _fail("invalid_source_facility_type")
            all_facilities[id] = fac.duplicate(true)
        for market in solar_system.get("markets", []):
            if not (market is Dictionary):
                return _fail("invalid_source_market")
            source_markets.append(market.duplicate(true))
        for pop in solar_system.get("populations", []):
            if not (pop is Dictionary):
                return _fail("invalid_source_population")
            source_populations.append(pop.duplicate(true))
    # Native seed has market.facility_id = location (not facility's agent
    # ID). Source sim_db seeder resolves this to station facility DB owner.
    # Never guess from array order: accept exactly one local source station.
    var owners_by_location: Dictionary = {}
    for market in source_markets:
        var owner_location: String = str(market.get("facility_id", ""))
        if owner_location.is_empty() or owners_by_location.has(owner_location):
            return _fail("duplicate_or_missing_market_location")
        var candidates: Array[String] = []
        for id in all_facilities:
            var fac: Dictionary = all_facilities[id]
            if str(fac["location"]) == owner_location and str(fac["type"]) == "station":
                candidates.append(str(id))
        if candidates.size() != 1:
            return _fail("market_has_no_unique_source_station")
        var owner_id: String = candidates[0]
        owners_by_location[owner_location] = owner_id
        if not (market.get("prices") is Dictionary) or not (market.get("supply") is Dictionary):
            return _fail("missing_market_stock_or_prices")
        projected["markets"][owner_location] = {
            "owner": owner_id, "supply": market["supply"].duplicate(true),
            "prices": market["prices"].duplicate(true), "limits": {}
        }
    if owners_by_location.is_empty():
        return _fail("no_native_markets")
    # Only source facilities at actual source market locations are currently
    # runnable by N39. Other facilities stay in the frozen seed/UI and must
    # be joined by later Phase2 world owners (never silently funded).
    var skipped: Array = []
    for id in all_facilities:
        var fac: Dictionary = all_facilities[id]
        var location: String = str(fac["location"])
        if not owners_by_location.has(location):
            skipped.append(id)
            continue
        var kind: String = str(fac["type"])
        projected["facilities"][id] = {
            "type": kind,
            "faction": str(fac["faction_id"]),
            "location": location,
            "body_id": str(fac["body"]),
            "credits": int(fac["credits"]),
            "crew_count": int(NATIVE_CREW_BY_TYPE.get(kind, 6)),
            "morale": INITIAL_MORALE,
            "level": 1, "xp": 0, "abandoned": false,
            # Rust FacilityFitting default production_t1+automation_t1
            # has neutral output and zero batch bonus.
            "fitting_output_mult": 1.0,
            "fitting_batches_bonus": 0
        }
    for pop in source_populations:
        if not _id(pop.get("label", null)) or not _id(pop.get("faction_id", null)):
            return _fail("population_missing_identity")
        var label: String = str(pop["label"])
        var pid: String = "pop-" + label.to_lower().replace(" ", "-")
        var location: String = str(pop.get("facility_id", ""))
        if not owners_by_location.has(location) or projected["populations"].has(pid):
            return _fail("population_missing_home_market_or_duplicate")
        var owner: Dictionary = projected["facilities"][owners_by_location[location]]
        if str(pop["faction_id"]) != str(owner["faction"]):
            return _fail("population_faction_mismatch")
        if typeof(pop.get("population_count", null)) != TYPE_INT or typeof(pop.get("total_wealth", null)) != TYPE_INT:
            return _fail("population_missing_real_counts")
        projected["populations"][pid] = {
            "faction": str(pop["faction_id"]),
            "location": location,
            "count": int(pop["population_count"]),
            "wealth": int(pop["total_wealth"]),
            "employed_fraction": 0.0,
            # Native N39 uses only jobs/wallet. Consumption/satisfaction
            # remain dormant until N151 is integrated into SAME ledger.
            "food_satisfaction": int(pop.get("food_satisfaction", 70)),
            "consumption": pop.get("consumption", {}).duplicate(true)
        }
    var failure: String = Schema.validate(projected)
    if not failure.is_empty():
        return _fail("source_world_rejected:" + failure)
    skipped.sort()
    return {"ok": true, "world": projected, "stats": {
        "source_facilities": all_facilities.size(),
        "active_facilities": projected["facilities"].size(),
        "inactive_facilities": skipped,
        "markets": projected["markets"].size(),
        "populations": projected["populations"].size(),
        "bodies": projected["bodies"].size()
    }}

static func _id(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
