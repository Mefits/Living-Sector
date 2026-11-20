extends RefCounted
## A single pre-equipped scenario ship. The landing consumes its manifest.
const Flight = preload("res://scripts/sol_local_flight.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const PORT := "luna-colony"
const PASSENGERS := 100
const METALS := 2
const STARTER_FOOD := 10
var ship: Dictionary = {}
var settlers: Dictionary = {}
var _world: Dictionary = {}

func reset(world: Dictionary) -> void:
 _world = world
 settlers = {}
 ship = {}
 if world.get("system", {}).get("id", "") == "system-sol":
  ship = {"id":"sol-colonizer-1", "location":"earth-colony",
   "population":PASSENGERS, "metals":METALS, "food":STARTER_FOOD}

func depart(now: float) -> bool:
 if ship.get("location", "") != "earth-colony":
  return false
 ship.location = "transit"
 ship["departure"] = now
 ship["trajectory"] = Flight.make(_world, "colonizer", "earth", now)
 ship["arrival"] = ship.trajectory.arrival
 return true

func land_if_due(world: Dictionary, now: float, owner: String) -> bool:
 if ship.get("location", "") != "transit" or now < float(ship.arrival):
  return false
 world.facilities.append({"id":"facility-luna-ac", "name":"Административный центр",
  "type":"station", "body":"luna", "location":PORT, "faction_id":owner,
  "surface_site":Model.surface_site("administrative_center"), "services":[], "docking_capacity":0})
 world.markets.append({"id":"market-luna-colony", "facility_id":PORT,
  "supply":{"metals":ship.metals, "food":ship.food}})
 settlers = {"label":"Residents luna-colony", "facility_id":PORT,
  "demographic":"workers", "population_count":ship.population, "faction_id":owner}
 world.populations.append(settlers)
 ship = {}
 return true

func snapshot() -> Dictionary:
 var saved := ship.duplicate()
 saved.erase("trajectory")
 return {"ship":saved, "settlers":settlers.duplicate()}

func validate(data: Variant, lunar_market: bool, now: float) -> bool:
 if not data is Dictionary or not data.get("ship") is Dictionary or not data.get("settlers") is Dictionary:
  return false
 var saved: Dictionary = data.ship
 if lunar_market:
  return saved.is_empty() and data.settlers.get("facility_id") == PORT and data.settlers.get("population_count") == PASSENGERS
 if saved.is_empty():
  return ship.is_empty() and settlers.is_empty() and data.settlers.is_empty()
 if not data.settlers.is_empty() or saved.get("population") != PASSENGERS or saved.get("metals") != METALS:
  return false
 if saved.get("location") == "earth-colony":
  return true
 if saved.get("location") != "transit":
  return false
 return Flight.valid_times(saved, now)

func restore(world: Dictionary, data: Dictionary) -> void:
 var residents: Array = world.get("populations", [])
 for i in range(residents.size()-1, -1, -1):
  if residents[i].get("facility_id") == PORT:
   residents.remove_at(i)
 ship = data.ship.duplicate()
 if ship.get("location") == "transit":
  ship.trajectory = Flight.make(world, "colonizer", "earth", ship.departure, ship.arrival)
 settlers = data.settlers.duplicate()
 if not settlers.is_empty():
  residents.append(settlers)
