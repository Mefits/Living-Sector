extends RefCounted
## N104 frozen Rust sim_server/engine/transactions.rs::embark
## and sim_core/strategy/colony.rs::SETTLERS.
## Moves REAL people and proportional household wealth to persisted
## ContractFunding.embarked without inventing an aggregate population.
## On failure the original snapshot is unchanged. The destination
## arrival and payment are part of the separate delivery commit below.
const Quote = preload("res://scripts/port/n104_contract_quote.gd")
const PASSENGER_SEATS = {
    "colonizer": 50, "courier": 20, "freighter": 10,
    "hauler": 5, "tanker": 0, "miner": 0
}
const COLONY_SETTLERS: int = 10
const MAX_SAFE_FLOAT_INT: int = 9007199254740991

static func embark(world: Dictionary, ship_id: String,
        contract_id: String, tick: int) -> Dictionary:
    if tick < 0 or ship_id.is_empty() or contract_id.is_empty():
        return _bad("invalid_embark_context")
    if not (world.get("contracts", null) is Dictionary)             or not (world.get("ships", null) is Dictionary):
        return _bad("missing_world")
    var source_contract: Variant = world["contracts"].get(contract_id, null)
    var source_ship: Variant = world["ships"].get(ship_id, null)
    if not (source_contract is Dictionary) or not (source_ship is Dictionary):
        return _bad("missing_contract_or_ship")
    var contract: Dictionary = source_contract
    var ship: Dictionary = source_ship
    var funding: Variant = contract.get("funding", null)
    if (str(contract.get("contract_type", "")) != "passenger"
            or str(contract.get("status", "")) != "accepted"
            or str(contract.get("fulfiller_id", "")) != ship_id
            or str(ship.get("active_contract_id", "")) != contract_id
            or not (funding is Dictionary)
            or funding.get("agreed_payment", null) == null
            or funding.get("embarked", null) != null):
        return _bad("inactive_passenger_contract")
    var ship_class: String = str(ship.get("class", ""))
    var qty: Variant = contract.get("quantity", null)
    if typeof(qty) != TYPE_INT or not PASSENGER_SEATS.has(ship_class)             or int(qty) <= 0 or int(qty) > int(PASSENGER_SEATS[ship_class]):
        return _bad("insufficient_passenger_capacity")
    var source: String = str(contract.get("source_location", ""))
    var location_check: Dictionary = _dock_and_controller(world, ship_id, source)
    if not bool(location_check.get("ok", false)):
        return location_check
    var faction_value: Variant = contract.get("faction_id", null)
    var faction: String = str(ship.get("faction_id", ""))         if faction_value == null else str(faction_value)
    var retained: int = COLONY_SETTLERS         if str(contract.get("mission_category", "")) == "strategy.colony.v1" else 0
    var populations: Variant = world.get("populations", null)
    if not (populations is Dictionary):
        return _bad("missing_populations")
    var household_ids: Array = populations.keys()
    household_ids.sort()
    var chosen: String = ""
    var moved_wealth: int = 0
    for id in household_ids:
        var p: Variant = populations[id]
        if not (p is Dictionary):
            continue
        if str(p.get("facility_location", "")) != source                 or str(p.get("faction_id", "")) != faction:
            continue
        var people: Variant = p.get("population_count", null)
        var wealth: Variant = p.get("total_wealth", null)
        if typeof(people) != TYPE_INT or typeof(wealth) != TYPE_INT:
            continue
        if int(people) < int(qty) + retained or int(wealth) < 0:
            continue
        # Rust uses i128 numerator then truncating integer division.
        # Godot only has signed int64; require exact double representable
        # product instead of silently inventing savings on overflow.
        if int(wealth) > MAX_SAFE_FLOAT_INT:
            return _bad("wealth_requires_i128_adapter")
        var float_product: float = float(wealth) * float(qty)
        if float_product > float(MAX_SAFE_FLOAT_INT):
            return _bad("wealth_requires_i128_adapter")
        # Both operands and product are exact integers within the guard.
        # Godot int/int truncates exactly as the source Rust positive i128.
        var product: int = int(wealth) * int(qty)
        chosen = str(id)
        moved_wealth = int(product / int(people))
        break
    if chosen.is_empty():
        return _bad("insufficient_settlers")
    var staged: Dictionary = world.duplicate(true)
    var selected: Dictionary = staged["populations"][chosen]
    var updated: Dictionary = staged["contracts"][contract_id]
    updated["status"] = "picked_up"
    updated["funding"]["embarked"] = {
        "origin_population": chosen, "wealth": moved_wealth
    }
    selected["population_count"] = int(selected["population_count"]) - int(qty)
    selected["total_wealth"] = int(selected["total_wealth"]) - moved_wealth
    if selected.get("sentiment", null) is Dictionary:
        selected["sentiment"]["dirty"] = true
    var event: Dictionary = {
        "kind": "passengers_embarked", "contract_id": contract_id,
        "ship_id": ship_id, "source": source,
        "origin_population": chosen, "head_count": int(qty),
        "wealth": moved_wealth, "tick": tick
    }
    return {"ok": true, "world": staged, "events": [event],
        "quantity": float(qty), "payment": 0}

## Clone of engine/transactions.rs::dock and controller. Source facility
## identity, actual dock occupancy, controller and treaty are mandatory.
static func _dock_and_controller(world: Dictionary, ship_id: String,
        location: String) -> Dictionary:
    if location.is_empty() or not (world.get("ships", null) is Dictionary):
        return _bad("wrong_location")
    var ship: Variant = world["ships"].get(ship_id, null)
    if not (ship is Dictionary) or str(ship.get("location", "")) != location:
        return _bad("wrong_location")
    if not (ship.get("transit", null) is Dictionary)             or not (ship["transit"] as Dictionary).is_empty():
        return _bad("wrong_location")
    var facility_id: Variant = ship.get("docked_at", null)
    if not (facility_id is String):
        return _bad("not_docked")
    var facilities: Variant = world.get("facilities", null)
    if not (facilities is Dictionary)             or not (facilities.get(facility_id, null) is Dictionary):
        return _bad("missing_dock")
    var station: Dictionary = facilities[facility_id]
    if (str(station.get("location", "")) != location
            or not (station.get("docked_ships", null) is Array)
            or not (station["docked_ships"] as Array).has(ship_id)
            or bool(station.get("abandoned", false))):
        return _bad("invalid_dock")
    var relations: Variant = world.get("relations", null)
    if not (relations is Dictionary):
        return _bad("missing_relations")
    var from_faction: String = str(ship.get("faction_id", ""))
    var at_facility: Dictionary = Quote.commerce_allowed(
        relations, from_faction, str(station.get("faction_id", "")))
    if not bool(at_facility.get("ok", false)) or not bool(at_facility.get("allowed", false)):
        return _bad("embargo")
    var market_controllers: Variant = world.get("market_controllers", null)
    if not (market_controllers is Dictionary):
        return _bad("missing_market_controllers")
    var controller: String = str(market_controllers.get(location, ""))
    var at_market: Dictionary = Quote.commerce_allowed(
        relations, from_faction, controller)
    if not bool(at_market.get("ok", false)) or not bool(at_market.get("allowed", false)):
        return _bad("embargo")
    return {"ok": true, "facility_id": str(facility_id)}

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
