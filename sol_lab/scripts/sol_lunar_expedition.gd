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
var colonies: Dictionary = {}
var _world: Dictionary = {}

func reset(world: Dictionary) -> void:
 _world = world
 settlers = {}
 colonies = {}
 ship = {}
 if world.get("system", {}).get("id", "") == "system-sol":
  prepare_ship()

func prepare_ship() -> void:
 ship = {"id":"sol-colonizer-%d" % (colonies.size() + 1), "location":"earth-colony",
  "population":PASSENGERS, "metals":METALS, "food":STARTER_FOOD}

func depart(now: float, target := "luna", extra_food := 0) -> bool:
 if ship.get("location", "") != "earth-colony" or target not in TARGETS or colonies.has(target) or extra_food < 0:
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
 var population := {"label":"Residents " + port, "facility_id":port,
  "demographic":"workers", "population_count":ship.population, "faction_id":owner}
 colonies[target] = population
 if settlers.is_empty():
  settlers = population
 world.populations.append(population)
 ship = {}
 return true

func snapshot() -> Dictionary:
 var saved := ship.duplicate()
 saved.erase("trajectory")
 return {"ship":saved, "settlers":settlers.duplicate(), "colonies":colonies.duplicate(true)}

func saved_colonies(data: Dictionary) -> Dictionary:
 if data.get("colonies") is Dictionary:
  return data.colonies
 var prior: Dictionary = data.get("settlers", {})
 if prior.is_empty():
  return {}
 return {str(prior.get("facility_id", "")).trim_suffix("-colony"): prior}

func validate(data: Variant, worlds: Array, now: float) -> bool:
 if not data is Dictionary or not data.get("ship") is Dictionary or not data.get("settlers") is Dictionary:
  return false
 var records := saved_colonies(data)
 if records.size() != worlds.size():
  return false
 for body in worlds:
  var population: Variant = records.get(body, {})
  if not population is Dictionary or population.get("facility_id") != body + "-colony" or population.get("population_count") != PASSENGERS:
   return false
 if not records.is_empty():
  var first := str(data.settlers.get("facility_id", "")).trim_suffix("-colony")
  if records.get(first) != data.settlers:
   return false
 elif not data.settlers.is_empty():
  return false
 var saved: Dictionary = data.ship
 if saved.is_empty():
  return not worlds.is_empty() or _world.get("system", {}).get("id") != "system-sol"
 if worlds.size() == TARGETS.size() or saved.get("population") != PASSENGERS or saved.get("metals") != METALS:
  return false
 if saved.get("location") == "earth-colony":
  return true
 var target: String = saved.get("target", "luna")
 return saved.get("location") == "transit" and target in TARGETS and target not in worlds and Flight.valid_times(saved, now)

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
 colonies = saved_colonies(data).duplicate(true)
 for population in colonies.values():
  residents.append(population)
