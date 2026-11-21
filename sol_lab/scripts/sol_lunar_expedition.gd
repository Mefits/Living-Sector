extends RefCounted
## A single pre-equipped scenario ship. The landing consumes its manifest.
const Flight = preload("res://scripts/sol_local_flight.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const SurfaceSites = preload("res://scripts/view/sol_surface_sites.gd")
const TARGETS := ["luna", "mars"]
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

func depart(now: float, target := "luna", extra_food := 0) -> bool:
 if ship.get("location", "") != "earth-colony" or target not in TARGETS or extra_food < 0:
  return false
 ship.location = "transit"
 ship["target"] = target
 ship.food += extra_food
 ship["departure"] = now
 ship["trajectory"] = Flight.make(_world, "colonizer", "earth", now, -1.0, target)
 ship["arrival"] = ship.trajectory.arrival
 return true

func land_if_due(world: Dictionary, now: float, owner: String) -> bool:
 if ship.get("location", "") != "transit" or now < float(ship.arrival):
  return false
 var target: String = ship.get("target", "luna")
 var port := target + "-colony"
 var ac: Dictionary = {"id":"facility-%s-ac" % target, "name":"Административный центр",
  "type":"station", "body":target, "location":port, "faction_id":owner,
  "services":[], "docking_capacity":0}
 SurfaceSites.attach(ac, SurfaceSites.get_site(target, target + "-ac-01"))
 world.facilities.append(ac)
 world.markets.append({"id":"market-" + port, "facility_id":port,
  "supply":{"metals":ship.metals, "food":ship.food}})
 settlers = {"label":"Residents " + port, "facility_id":port,
  "demographic":"workers", "population_count":ship.population, "faction_id":owner}
 world.populations.append(settlers)
 ship = {}
 return true

func snapshot() -> Dictionary:
 var saved := ship.duplicate()
 saved.erase("trajectory")
 return {"ship":saved, "settlers":settlers.duplicate()}

func validate(data: Variant, colony: String, now: float) -> bool:
 if not data is Dictionary or not data.get("ship") is Dictionary or not data.get("settlers") is Dictionary:
  return false
 var saved: Dictionary = data.ship
 if not colony.is_empty():
  return saved.is_empty() and data.settlers.get("facility_id") == colony + "-colony" and data.settlers.get("population_count") == PASSENGERS
 if saved.is_empty():
  return _world.get("system", {}).get("id") != "system-sol" and data.settlers.is_empty()
 if not data.settlers.is_empty() or saved.get("population") != PASSENGERS or saved.get("metals") != METALS:
  return false
 if saved.get("location") == "earth-colony":
  return true
 if saved.get("location") != "transit":
  return false
 return saved.get("target", "luna") in TARGETS and Flight.valid_times(saved, now)

func restore(world: Dictionary, data: Dictionary) -> void:
 var residents: Array = world.get("populations", [])
 for i in range(residents.size()-1, -1, -1):
  if residents[i].get("facility_id") in ["luna-colony", "mars-colony"]:
   residents.remove_at(i)
 ship = data.ship.duplicate()
 if ship.get("location") == "transit":
  ship["target"] = ship.get("target", "luna")
  ship.trajectory = Flight.make(world, "colonizer", "earth", ship.departure, ship.arrival, ship.target)
 settlers = data.settlers.duplicate()
 if not settlers.is_empty():
  residents.append(settlers)
