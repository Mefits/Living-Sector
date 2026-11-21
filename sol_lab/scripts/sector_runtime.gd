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

func _launch(ship: Dictionary, job: Dictionary) -> void:
 var flight := job.duplicate()
 flight.start = day
 flight.arrival = day + duration(flight.source, flight.target, ship)
 ship.flight = flight

func _load(ship: Dictionary, job: Dictionary) -> void:
 planets[job.source].colony.stock[job.resource] -= job.amount
 _launch(ship, job)

func _commitment(ship: Dictionary) -> Dictionary:
 return ship.get("reserved", ship.get("flight", {}))

func available(source: String, resource: String) -> float:
 var colony: Dictionary = planets[source].colony
 var own: Dictionary = Model.find_building(colony.industry).get("inputs", {})
 var surplus: float = colony.stock.get(resource, 0) - own.get(resource, 0)
 for ship in ships.values():
  var reserved: Dictionary = ship.get("reserved", {})
  if reserved.get("source") == source and reserved.get("resource") == resource:
   surplus -= reserved.amount
 return maxf(0.0, surplus)

func incoming(target: String, resource: String) -> float:
 var amount := 0.0
 for ship in ships.values():
  var job := _commitment(ship)
  if job.get("target") == target and job.get("resource") == resource:
   amount += job.amount
 return amount

func _sources(target: String, resource: String) -> Array:
 var sources := []
 var owner: String = planets[target].colony.owner
 for source in planets:
  var colony: Dictionary = planets[source].get("colony", {})
  if source != target and colony.get("owner") == owner and available(source, resource) > 0:
   sources.append(source)
 return sources

func input_status(target: String, resource: String) -> String:
 var pending := incoming(target, resource)
 if pending > 0:
  for ship in ships.values():
   var flight: Dictionary = ship.get("flight", {})
   if flight.get("resource") == resource and flight.get("target") == target and flight.amount > 0:
    return "груз в пути · %s" % Model.batch_amount(pending)
  return "транспорт летит за грузом · %s" % Model.batch_amount(pending)
 if _sources(target, resource).is_empty():
  return "нет доступного запаса"
 return "ожидает свободный транспорт"

func _best_job() -> Dictionary:
 var best := {}
 var finish := INF
 for target in planets:
  var colony: Dictionary = planets[target].get("colony", {})
  if colony.is_empty():
   continue
  var inputs: Dictionary = Model.find_building(colony.industry).get("inputs", {})
  for resource in inputs:
   var need: float = inputs[resource] - colony.stock.get(resource, 0) - incoming(target, resource)
   if need <= 0:
    continue
   for source in _sources(target, resource):
    var amount := minf(available(source, resource), need)
    for ship in ships.values():
     if ship.has("flight") or ship.owner != colony.owner or ship.capacity <= 0:
      continue
     var travel := duration(source, target, ship)
     if ship.port != source:
      travel += duration(ship.port, source, ship)
     if travel < finish:
      finish = travel
      best = {"ship":ship.id, "source":source, "target":target,
       "resource":resource, "amount":minf(amount, ship.capacity)}
 return best

func _assign() -> void:
 while true:
  var job := _best_job()
  if job.is_empty():
   return
  var ship: Dictionary = ships[job.ship]
  job.erase("ship")
  if ship.port == job.source:
   _load(ship, job)
  else:
   ship.reserved = job
   _launch(ship, {"source":ship.port, "target":job.source, "resource":"", "amount":0})

func advance(until: float) -> void:
 _assign()
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
  day = event
  for ship in ships.values():
   if ship.has("flight") and ship.flight.arrival <= event:
    var order: Dictionary = ship.flight
    var stock: Dictionary = planets[order.target].colony.stock
    if order.amount > 0:
     stock[order.resource] = stock.get(order.resource, 0) + order.amount
    ship.port = order.target
    ship.erase("flight")
    if ship.has("reserved"):
     var job: Dictionary = ship.reserved
     ship.erase("reserved")
     _load(ship, job)
  for planet in planets.values():
   if planet.has("colony") and planet.colony.next <= event:
    _produce(planet.colony, event)
    planet.colony.next += cycle
  _assign()
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
