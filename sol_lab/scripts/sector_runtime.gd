extends RefCounted

const Model = preload("res://scripts/sol_building_model.gd")
var systems: Dictionary
var planets: Dictionary
var ships: Dictionary
var day := 0.0
var approach: float
var cycle: float
var focus: String

func setup(data: Dictionary) -> void:
 systems = {}
 planets = {}
 ships = {}
 day = 0
 approach = data.approach_days
 cycle = data.cycle_days
 focus = data.focus
 for system in data.systems:
  systems[system.id] = system.duplicate(true)
  for planet in systems[system.id].planets:
   planet.system = system.id
   planets[planet.id] = planet
   if planet.has("colony"):
    planet.colony.next = cycle
 for ship in data.ships:
  ships[ship.id] = ship.duplicate(true)

func star_position(id: String) -> Vector2:
 var xy: Array = systems[id].xy
 return Vector2(xy[0], xy[1])

func duration(source: String, target: String, ship: Dictionary) -> float:
 var distance := star_position(planets[source].system).distance_to(star_position(planets[target].system))
 return approach * 2.0 + distance / float(ship.speed)

func dispatch(id: String, source: String, target: String, resource: String, amount: float) -> bool:
 var ship: Dictionary = ships.get(id, {})
 if ship.is_empty() or ship.has("flight") or ship.port != source or source == target:
  return false
 var from: Dictionary = planets.get(source, {}).get("colony", {})
 var to: Dictionary = planets.get(target, {}).get("colony", {})
 if from.is_empty() or to.is_empty() or ship.owner != from.owner or ship.owner != to.owner:
  return false
 if not is_finite(amount) or amount <= 0 or amount > ship.capacity or amount > from.stock.get(resource, 0.0):
  return false
 from.stock[resource] -= amount
 ship.flight = {"source":source, "target":target, "resource":resource, "amount":amount,
  "start":day, "arrival":day + duration(source, target, ship)}
 return true

func advance(until: float) -> void:
 # Resolve arrivals and production chronologically, including when a frame skips events.
 while true:
  var event := INF
  for ship in ships.values():
   if ship.has("flight"):
    event = minf(event, ship.flight.arrival)
  for planet in planets.values():
   if planet.has("colony"):
    event = minf(event, planet.colony.next)
  if event > until:
   break
  for ship in ships.values():
   if ship.has("flight") and ship.flight.arrival <= event:
    var order: Dictionary = ship.flight
    var stock: Dictionary = planets[order.target].colony.stock
    stock[order.resource] = stock.get(order.resource, 0) + order.amount
    ship.port = order.target
    ship.erase("flight")
  for planet in planets.values():
   if planet.has("colony") and planet.colony.next <= event:
    _produce(planet.colony, event)
    planet.colony.next += cycle
 day = until

func _produce(colony: Dictionary, event: float) -> void:
 var recipe := Model.find_building(colony.industry)
 for resource in recipe.get("inputs", {}):
  if colony.stock.get(resource, 0) < recipe.inputs[resource]:
   return
 for resource in recipe.get("inputs", {}):
  colony.stock[resource] -= recipe.inputs[resource]
 var product: String = recipe.product
 colony.stock[product] = colony.stock.get(product, 0) + recipe.base
 colony.last = {"day":event, "amount":recipe.base, "resource":product}

func snapshot() -> Dictionary:
 return {"systems":systems.values(), "ships":ships.values(), "day":day}

func restore(saved: Dictionary) -> void:
 setup({"systems":saved.systems,"ships":saved.ships,"focus":focus,
  "approach_days":approach,"cycle_days":cycle})
 day = saved.day
 for system in saved.systems:
  for planet in system.planets:
   if planet.has("colony"):
    planets[planet.id].colony.next = planet.colony.next
