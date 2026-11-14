extends RefCounted
## Isolated physical economy fixture: the existing N73 recipe and N9 inventory
## rules, not full N39 production, payroll, market or N104 escrow.
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const CADENCE: int = 5
const HOLD_CAPACITY: int = 32

var markets: Array[Dictionary] = []
var facilities: Array[Dictionary] = []
var ships: Array[Dictionary] = []
var active: Array[bool] = []
var active_count: int = 0
var facilities_by_market: Dictionary = {}
var attempts: int = 0
var batches: int = 0
var arrivals: int = 0
var loaded_units: int = 0
var unloaded_units: int = 0
var errors: Array[String] = []

func initialize(facility_count: int, ship_count: int, seed: int) -> void:
    var count: int = maxi(3, int(ceil(float(facility_count) / 8.0)))
    facilities_by_market.clear()
    var recipes: Array[String] = [
        "smelt_metals", "process_ice", "crack_fuel", "refine_polymers",
        "assemble_components", "build_electronics", "forge_tools", "grow_food"
    ]
    for i in range(count):
        facilities_by_market[i] = []
        var variation: int = (i * 37 + seed * 13) % 11
        var market: Dictionary = {
            "ore": float(32 + variation), "ice": float(20 + variation),
            "gas": float(20 + variation), "fuel": 20.0, "metals": 12.0,
            "polymers": 6.0, "components": 9.0, "electronics": 1.0,
            "water": 18.0, "food": 7.0, "tools": 0.0
        }
        # Three deliberately asymmetric planet fixtures: Earthlike, volcanic, icy.
        # This changes initial stock only, NEVER the N73/N9 economic formulas.
        if i % 3 == 0:
            market["ore"] += 40.0
            market["food"] += 30.0
        elif i % 3 == 1:
            market["ore"] += 70.0
            market["gas"] += 25.0
            market["ice"] = 0.0
            market["food"] = 2.0
        else:
            market["ice"] += 65.0
            market["water"] += 25.0
            market["ore"] = 8.0
            market["food"] = 1.0
        markets.append(market)
    for i in range(facility_count):
        facilities.append({"market": i % count, "recipe": recipes[i % recipes.size()]})
        active.append(true)
        facilities_by_market[i % count].append(i)
    active_count = facility_count
    for i in range(ship_count):
        var start: int = i % count
        ships.append({
            "market": start, "target": (start + 1) % count,
            "cargo": {}, "arrival": -1, "departure": 1 + i % 3,
            "travel": 4 + i % 4
        })

func produce(facility_id: int) -> bool:
    attempts += 1
    var facility: Dictionary = facilities[facility_id]
    var stock: Dictionary = markets[int(facility["market"])]
    # Exactly the checked-in Rust-derived N73 fractional recipe transform.
    var output: Dictionary = Recipes.execute(str(facility["recipe"]), stock, 1.0, 1)
    if output.is_empty():
        return false
    batches += 1
    return true

func depart(ship_id: int, tick: int) -> int:
    var ship: Dictionary = ships[ship_id]
    if int(ship["arrival"]) != -1 or int(ship["departure"]) != tick:
        errors.append("invalid_depart_" + str(ship_id) + "/" + str(tick))
        return -1
    var cargo_kinds: Array[String] = [
        "ore", "ice", "metals", "water", "fuel",
        "polymers", "components", "food", "gas"
    ]
    var commodity: String = cargo_kinds[ship_id % cargo_kinds.size()]
    var warehouse: Dictionary = markets[int(ship["market"])]
    var quantity: int = mini(4, int(floor(float(warehouse.get(commodity, 0.0)))))
    if quantity > 0:
        if not Inventory.transfer_to_ship(
                warehouse, ship["cargo"], {commodity: quantity}, HOLD_CAPACITY):
            errors.append("rejected_load_" + str(ship_id))
            return -1
        loaded_units += quantity
    ship["arrival"] = tick + int(ship["travel"])
    ship["departure"] = -1
    return int(ship["arrival"])

func arrive(ship_id: int, tick: int) -> int:
    var ship: Dictionary = ships[ship_id]
    if int(ship["arrival"]) != tick:
        errors.append("invalid_arrival_" + str(ship_id) + "/" + str(tick))
        return -1
    var destination: int = int(ship["target"])
    var cargo: Dictionary = ship["cargo"]
    if not cargo.is_empty():
        var shipment: Dictionary = cargo.duplicate(true)
        var quantity: int = 0
        for slug in shipment:
            quantity += int(shipment[slug])
        if not Inventory.transfer(cargo, markets[destination], shipment):
            errors.append("rejected_unload_" + str(ship_id))
            return -1
        unloaded_units += quantity
    arrivals += 1
    ship["market"] = destination
    ship["target"] = (destination + 1) % markets.size()
    ship["arrival"] = -1
    ship["departure"] = tick + 3
    return destination

func sleep(facility_id: int) -> void:
    if active[facility_id]:
        active[facility_id] = false
        active_count -= 1

func wake_market(market_id: int) -> void:
    # Invalidation of a calculation cache, NOT a grant of goods or free work.
    for entry in facilities_by_market.get(market_id, []):
        var i: int = int(entry)
        if not active[i]:
            active[i] = true
            active_count += 1

func audit() -> String:
    if not errors.is_empty():
        return errors[0]
    for market in markets:
        var validation: String = Inventory.validate(market)
        if validation != "":
            return validation
    var in_transit: int = 0
    for ship in ships:
        var validation: String = Inventory.validate_ship_hold(ship["cargo"], HOLD_CAPACITY)
        if validation != "":
            return validation
        if int(ship["arrival"]) >= 0 and int(ship["departure"]) >= 0:
            return "ship_in_two_states"
        for commodity in ship["cargo"]:
            in_transit += int(ship["cargo"][commodity])
    if loaded_units != unloaded_units + in_transit:
        return "ship_cargo_conservation_failed"
    return ""

func state() -> Dictionary:
    var warehouse_state: Array = []
    var ship_state: Array = []
    for market in markets:
        warehouse_state.append(Inventory.canonical(market))
    for ship in ships:
        ship_state.append({
            "market": int(ship["market"]), "target": int(ship["target"]),
            "arrival": int(ship["arrival"]), "departure": int(ship["departure"]),
            "cargo": Inventory.canonical(ship["cargo"])
        })
    return {
        "markets": warehouse_state, "ships": ship_state,
        "batches": batches, "arrivals": arrivals,
        "loaded_units": loaded_units, "unloaded_units": unloaded_units
    }
