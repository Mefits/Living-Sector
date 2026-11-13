extends RefCounted
## N39 / Rust Galaxy 0.6.7 physical production snapshot.
## This is a read/validate boundary, NOT another world/ledger implementation.
## The caller must supply real market, facility, population and body snapshots.
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")

static func validate(state: Dictionary) -> String:
    for key in ["facilities", "markets", "populations", "bodies"]:
        if not (state.get(key) is Dictionary):
            return "missing_" + key
    if state["facilities"].is_empty() or state["markets"].is_empty():
        return "empty_world"
    if state.has("research") and not (state["research"] is Dictionary):
        return "invalid_research"
    if state.has("location_tiers") and not (state["location_tiers"] is Dictionary):
        return "invalid_location_tiers"
    if state.has("station_executing") and typeof(state["station_executing"]) != TYPE_BOOL:
        return "invalid_station_phase"
    for id in state["facilities"]:
        if not _id(id) or not (state["facilities"][id] is Dictionary):
            return "invalid_facility"
        var fac: Dictionary = state["facilities"][id]
        for key in ["type", "faction", "location", "body_id"]:
            if not _id(fac.get(key, null)):
                return "invalid_facility_" + key
        for key in ["crew_count", "level", "xp", "credits"]:
            if typeof(fac.get(key, null)) != TYPE_INT or int(fac[key]) < 0:
                return "invalid_facility_" + key
        if int(fac["level"]) < 1 or int(fac["level"]) > 10 or int(fac["crew_count"]) > 65535:
            return "invalid_facility_level_or_crew"
        if typeof(fac.get("abandoned", null)) != TYPE_BOOL:
            return "invalid_abandoned"
        # Fuel/Tools reserves belong to this facility, never to a market.
        # Older checkpoints may omit this optional source component; their
        # actual owned inventory is then empty, NOT borrowed market stock.
        var owned: Variant = fac.get("reserves", {})
        if not (owned is Dictionary) or Inventory.validate(owned) != "":
            return "invalid_facility_owned_reserves"
        if fac.has("condition") and (not _fraction(fac["condition"]) or float(fac["condition"]) > 1.0):
            return "invalid_facility_condition"
        if fac.has("abandon_counter") and (typeof(fac["abandon_counter"]) != TYPE_INT or int(fac["abandon_counter"]) < 0 or int(fac["abandon_counter"]) > 4294967295):
            return "invalid_facility_abandon_counter"
        var morale: Variant = fac.get("morale", null)
        if not _fraction(morale) or float(morale) > 100.0:
            return "invalid_morale"
        for key in ["fitting_output_mult"]:
            if fac.has(key) and (not _fraction(fac[key]) or float(fac[key]) <= 0.0):
                return "invalid_fitting"
        if fac.has("fitting_batches_bonus") and (typeof(fac["fitting_batches_bonus"]) != TYPE_INT or int(fac["fitting_batches_bonus"]) < 0):
            return "invalid_fitting_batches"
        if fac.has("assigned_workers") and (typeof(fac["assigned_workers"]) != TYPE_INT or int(fac["assigned_workers"]) < 0):
            return "invalid_station_assignment"
        if fac.has("lod_divisor") and (typeof(fac["lod_divisor"]) != TYPE_INT or int(fac["lod_divisor"]) < 1):
            return "invalid_lod_divisor"
        if fac.has("lod_next_tick") and (typeof(fac["lod_next_tick"]) != TYPE_INT or int(fac["lod_next_tick"]) < 0):
            return "invalid_lod_cursor"
        if fac.has("work_shift"):
            var shift: Variant = fac["work_shift"]
            if not (shift is Dictionary):
                return "invalid_work_shift"
            if not shift.is_empty():
                if typeof(shift.get("tick", null)) != TYPE_INT or int(shift["tick"]) < 0 or not (shift.get("workers") is Dictionary):
                    return "invalid_work_shift"
                for pid in shift["workers"]:
                    if not _id(pid) or typeof(shift["workers"][pid]) != TYPE_INT or int(shift["workers"][pid]) <= 0:
                        return "invalid_work_shift_workers"
        if not state["markets"].has(str(fac["location"])):
            return "missing_facility_market"
    for location in state["markets"]:
        if not _id(location) or not (state["markets"][location] is Dictionary):
            return "invalid_market"
        var market: Dictionary = state["markets"][location]
        if not _id(market.get("owner", null)) or not state["facilities"].has(market["owner"]):
            return "missing_market_owner"
        var owner: Dictionary = state["facilities"][market["owner"]]
        if str(owner["location"]) != str(location):
            return "remote_market_owner"
        if not (market.get("supply") is Dictionary) or not (market.get("prices") is Dictionary):
            return "invalid_market_data"
        var limits: Variant = market.get("limits", {})
        if not (limits is Dictionary) or Inventory.validate(market["supply"], limits) != "":
            return "invalid_market_inventory"
        for commodity in market["prices"]:
            if not Inventory.valid_amount(market["prices"][commodity]):
                return "invalid_market_price"
    for id in state["populations"]:
        if not _id(id) or not (state["populations"][id] is Dictionary):
            return "invalid_population"
        var pop: Dictionary = state["populations"][id]
        if not _id(pop.get("faction", null)) or not _id(pop.get("location", null)):
            return "invalid_population_identity"
        if typeof(pop.get("count", null)) != TYPE_INT or int(pop["count"]) < 0:
            return "invalid_population_count"
        if typeof(pop.get("wealth", null)) != TYPE_INT or int(pop["wealth"]) < 0:
            return "invalid_household_balance"
        if pop.has("employed_fraction") and (not _fraction(pop["employed_fraction"]) or float(pop["employed_fraction"]) > 1.0):
            return "invalid_employment"
    for id in state["bodies"]:
        if not _id(id) or not (state["bodies"][id] is Dictionary):
            return "invalid_body"
        var body: Dictionary = state["bodies"][id]
        if not (body.get("resources") is Dictionary) or Inventory.validate(body["resources"]) != "":
            return "invalid_body_resources"
    if state.has("research"):
        for faction in state["research"]:
            if not _id(faction) or not (state["research"][faction] is Array):
                return "invalid_technologies"
            for tech in state["research"][faction]:
                if not _id(tech):
                    return "invalid_technology"
    if state.has("location_tiers"):
        for faction in state["location_tiers"]:
            if not _id(faction) or not (state["location_tiers"][faction] is Dictionary):
                return "invalid_tiers"
            for location in state["location_tiers"][faction]:
                var tier: Variant = state["location_tiers"][faction][location]
                if not _id(location) or typeof(tier) != TYPE_INT or int(tier) < 1 or int(tier) > 4:
                    return "invalid_tier"
    if Recipes.validate() != "":
        return "native_recipes_unavailable"
    return ""

static func accounts(state: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for id in state["facilities"]:
        result[facility_account(str(id))] = int(state["facilities"][id]["credits"])
    for id in state["populations"]:
        result[household_account(str(id))] = int(state["populations"][id]["wealth"])
    return result

static func facility_account(id: String) -> String:
    return "facility/" + id

static func household_account(id: String) -> String:
    return "population/" + id

static func has_tech(state: Dictionary, faction: String, tech: String) -> bool:
    var researched: Variant = state.get("research", {}).get(faction, [])
    return researched is Array and researched.has(tech)

static func tier_at(state: Dictionary, faction: String, location: String) -> int:
    var tiers: Variant = state.get("location_tiers", {}).get(faction, {})
    return int(tiers.get(location, 1)) if tiers is Dictionary else 1

static func _id(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _fraction(value: Variant) -> bool:
    return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)) and float(value) >= 0.0
