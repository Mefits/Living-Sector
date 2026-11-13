extends RefCounted
## P2 N158: ONLY authoritative frozen Galaxy 0.6.7 JSON -> N39 paid
## production projection. No fabricated world, wallets, market price or
## resource. This adapter DOES NOT simulate ships, population consumption
## or faction AI (those remain separate Phase2 integrations).
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const FleetBootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const ShipRoster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const DirectorProfile = preload("res://scripts/sim/phase1/n155_director_native_observation.gd")

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
    var source_treasuries: Dictionary = {}
    var source_directors: Dictionary = {}
    for f in seed["factions"]:
        if not (f is Dictionary) or not _id(f.get("id", null)):
            return _fail("invalid_seed_faction")
        if factions.has(f["id"]):
            return _fail("duplicate_faction")
        factions[f["id"]] = true
        if not _whole_json_int(f.get("treasury", null)):
            return _fail("source_faction_treasury_not_grounded")
        var faction_id: String = str(f["id"])
        var personality: Dictionary = f.get("personality", {})
        if not (f.get("personality") is Dictionary):
            return _fail("missing_native_faction_personality")
        var profile: Dictionary = DirectorProfile.profile_from_personality(personality)
        if profile.is_empty():
            return _fail("source_director_personality_invalid")
        source_treasuries[faction_id] = int(f["treasury"])
        # Native N155 initial Director research fields, NOT synthetic tech.
        source_directors[faction_id] = {
            "technologies": [], "research": null, "progress": 0,
            "research_required": 0, "last_research_tick": null,
            "last_shift": null, "history": [], "crisis": false,
            "profile": profile
        }
    var projected: Dictionary = {
        "facilities": {}, "markets": {}, "populations": {}, "bodies": {},
        "research": {}, "research_directors": source_directors,
        "research_receipts": {}, "faction_treasuries": source_treasuries,
        "location_tiers": {}, "ships": {},
        "ship_next_token": 1, "dock_receipts": {}, "cargo_receipts": {},
        "contract_board": {"version": 1, "contracts": {}, "receipt_claims": {}},
        "escrow_balances": {},
        "station_executing": false
    }
    for faction in factions:
        projected["research"][faction] = []
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
            if not _whole_json_int(fac.get("credits", null)):
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
        if not (market.get("prices") is Dictionary) or not (market.get("supply") is Dictionary) or not (market.get("demand") is Dictionary):
            return _fail("missing_source_market_components")
        if not _id(market.get("id", null)):
            return _fail("source_market_missing_id")
        # Rust sim_db/seeder.rs writes spread=0.10 and price_elasticity
        # from the real seed, falling back to 0.02. Initial MarketFlow,
        # MarketOrders and MarketHistory are source-default empty.
        var elasticity: float = float(market.get("price_elasticity", 0.02))
        if not is_finite(elasticity) or elasticity < 0.0:
            return _fail("invalid_source_market_elasticity")
        projected["markets"][owner_location] = {
            "id": str(market["id"]),
            "location": owner_location,
            "owner": owner_id,
            "supply": market["supply"].duplicate(true),
            "prices": market["prices"].duplicate(true),
            "demand": market["demand"].duplicate(true),
            "elasticity": elasticity,
            "spread": 0.10,
            "seed_demand": market["demand"].duplicate(true),
            "consumption_window": {},
            "orders": {"pending_buys": [], "pending_sells": [],
                "reserved": {}, "order_expiry_ticks": 50 * 32},
            "history": {"shortage_ticks": {}, "trend_samples": [],
                "spawned_at_tick": null, "last_tick": 0},
            "limits": {}
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
        if not _whole_json_int(fac.get("docking_capacity", null)):
            return _fail("missing_native_docking_capacity")
        projected["facilities"][id] = {
            "type": kind,
            "faction": str(fac["faction_id"]),
            "location": location,
            "body_id": str(fac["body"]),
            "credits": int(fac["credits"]),
            "crew_count": int(NATIVE_CREW_BY_TYPE.get(kind, 6)),
            "docking_capacity": int(fac.get("docking_capacity", 0)),
            "morale": INITIAL_MORALE,
            "level": 1, "xp": 0, "abandoned": false,
            # Preserve only the ORIGINAL frozen seed's private service
            # reserves; never alias market stock as facility-owned Tools.
            "reserves": fac.get("reserves", {}).duplicate(true),
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
        if not _whole_json_int(pop.get("population_count", null)) or not _whole_json_int(pop.get("total_wealth", null)):
            return _fail("population_missing_real_counts")
        projected["populations"][pid] = {
            "faction": str(pop["faction_id"]),
            "location": location,
            "count": int(pop["population_count"]),
            "wealth": int(pop["total_wealth"]),
            # Rust sim_db migration 001 defaults for fields not present
            # in actual Galaxy JSON, no fabricated demographic changes.
            "id": pid,
            "label": label,
            "demographic": str(pop.get("demographic", "workers")),
            "employed_fraction": 0.85,
            "food_satisfaction": int(pop.get("food_satisfaction", 50)),
            "safety_satisfaction": 50,
            "entertainment_satisfaction": 50,
            "overall_sentiment": 50,
            "unrest": 0,
            "migration_pressure": 0.0,
            "spending_rate": 0.02,
            "growth_rate": 0.001,
            "production_commodity": pop.get("production_commodity", null),
            "production_amount": float(pop.get("production_amount", 0.0)),
            "consumption": pop.get("consumption", {}).duplicate(true)
        }
    # N46 reproduces the original Rust seeder: 24 stable source-array
    # ordinals, full class-specific tanks, empty cargo and real source
    # ship credits. Ship wallets enter the SAME N9 ledger at initial import.
    var new_fleet: Dictionary = FleetBootstrap.build_new_game(seed)
    if not bool(new_fleet.get("ok", false)) or int(new_fleet.get("ship_count", 0)) != 24:
        return _fail("native_ship_bootstrap_rejected:" +
            str(new_fleet.get("error", "unexpected_fleet_count")))
    var fleet: RefCounted = new_fleet["fleet"]
    var fleet_roster = ShipRoster.new()
    if not fleet_roster.load_seed(seed):
        return _fail("invalid_frozen_ship_roster")
    for ship in fleet.snapshot():
        var id: String = str(ship.get("id", ""))
        if projected["ships"].has(id) or not new_fleet["credit_sources"].has(id):
            return _fail("duplicate_or_unfunded_native_ship")
        var row: Dictionary = ship.duplicate(true)
        row["credits"] = int(new_fleet["credit_sources"][id])
        row["name"] = str(fleet_roster.metadata(id).get("name", id))
        # Rust modules::CATALOG Comms derived stat. The frozen 24-ship
        # source contains only comms_t2 overrides; default is comms_t1.
        # N104 acceptance must reserve its actual 5% top-up, not use 0.
        var native_ship: Dictionary = fleet_roster.registry.get_entity("ship", id).get("value", {})
        var raw_fit: Dictionary = native_ship.get("fitting", {})
        var comms_slug: String = str(raw_fit.get("comms", "comms_t1"))
        if comms_slug not in ["comms_t1", "comms_t2"]:
            return _fail("unsupported_native_comms_fitting")
        row["comms_bonus"] = 0.05 if comms_slug == "comms_t2" else 0.0
        # N21 frozen seeder: initial docked_at is NULL for ALL ships.
        row["docked_at"] = ""
        projected["ships"][id] = row
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
        "bodies": projected["bodies"].size(),
        "ships": projected["ships"].size()
    }}

## NativeData JSON parser represents whole-number JSON data as float in
## some Godot versions. Accept exact whole values only, never silently
## truncate or round financial accounts or population quantities.
static func _whole_json_int(value: Variant) -> bool:
    if not (value is int or value is float):
        return false
    var as_number: float = float(value)
    return is_finite(as_number) and as_number >= 0.0 and as_number <= 9007199254740991.0 and as_number == float(int(as_number))

static func _id(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
