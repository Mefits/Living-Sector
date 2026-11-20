extends RefCounted
## Sol Lab test-only construction model. Real stock is debited from the
## detached Rust Sol market. Sites live in the same map world as buildings.
## No second N39 simulation, no free facility, no paid labor or paid shifts.
const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const SurfaceSites = preload("res://scripts/view/sol_surface_sites.gd")

const Flight = preload("res://scripts/sol_local_flight.gd")

const VERSION: int = 7
const SHIP_METALS := 80
const SHIP_DAYS := 30
const EPSILON_NATIVE := 0.000001
const FREIGHT_CAPACITY := 10
const FREIGHT_ORDERS := {
 "luna": {"source": "earth", "destination": "luna", "resource": "metals", "amount": 10},
 "earth": {"source": "luna", "destination": "earth", "resource": "ore", "amount": 10}
}
const FREIGHT_RESOURCES := {"luna": ["metals", "food"], "earth": ["ore"]}
var world: Dictionary = {}
var settings: Dictionary = {}
var now_native: float = 0.0
var next_id: int = 1
var sites: Array = []
var expedition := preload("res://scripts/sol_lunar_expedition.gd").new()
var _freighter: Dictionary = {}
var _second: Dictionary = {}
# Latest completed Earth arrival per slot, for the local port view.
var _earth_arrivals: Dictionary = {}
var ship_order: Dictionary = {}
var _line_enabled := false
var _line_legs: Dictionary = {}
var initial_markets := 0
var initial_manifest: Dictionary
const CYCLE_DAYS := 30
const FOOD_PER_RESIDENT := 0.02
const EARTH_WATER_PER_CYCLE := 3
var planets: Dictionary = {}
var producers: Array = []
var meal_cycles: Dictionary = {}
var next_batch: float = INF
var batch_revision := 0

func setup(source_world: Dictionary, building_settings: Dictionary) -> void:
 world = source_world
 expedition.reset(world)
 _freighter = _starting_freighter()
 _second = {}
 _earth_arrivals.clear()
 ship_order = {}
 _line_enabled = false
 _line_legs = _default_line_legs()
 _ensure_earth_spaceport(world.get("facilities", []))
 SurfaceSites.reconcile(world.get("facilities", []))
 initial_markets = world.get("markets", []).size()
 initial_manifest = expedition.snapshot()
 settings = building_settings
 now_native = 0.0
 next_id = 1
 sites.clear()
 _index_producers()

func _starting_freighter() -> Dictionary:
 if world.get("system", {}).get("id") == "system-sol":
  return {"location": "earth"}
 return {}

static func _has_spaceport(facilities: Array, body: String) -> bool:
 for facility in facilities:
  if facility.get("body") == body and facility.get("location") == body + "-colony" and (
      facility.get("type") == "spaceport"):
   return true
 return false

static func _ensure_earth_spaceport(facilities: Array) -> void:
 if Model.built_or_pending({"facilities": facilities}, "earth", "spaceport"):
  return
 for facility in facilities:
  if facility.get("body") == "earth" and facility.get("location") == "earth-colony" and (
      facility.get("type") == "station"):
   var port: Dictionary = {"id": "facility-earth-spaceport",
    "name": "Космопорт", "type": "spaceport", "body": "earth",
    "location": "earth-colony", "tier": 1,
    "faction_id": facility.get("faction_id", "")}
   SurfaceSites.attach(port, SurfaceSites.get_site(
    "earth", "earth-port-01"))
   facilities.append(port)
   return

func freight_order(destination: String) -> Dictionary:
 return FREIGHT_ORDERS.get(destination, {}).duplicate()

func freight_block_reason(destination: String, food: bool = false) -> String:
 if _line_enabled:
  return "Для ручного рейса отключите линию"
 return _shipment_block_reason(_manual_order(destination, food))

func _manual_order(destination: String, food: bool) -> Dictionary:
 var shipment := freight_order(destination)
 if food:
  if destination != "luna":
   return {}
  shipment.resource = "food"
 return shipment

func _shipment_block_reason(shipment: Dictionary, reserve: float = 0.0, slot: int = 1) -> String:
 var ship := _second if slot == 2 else _freighter
 if shipment.is_empty() or ship.is_empty():
  return "Рейс недоступен"
 if ship.location == "transit":
  return "Грузовик в пути"
 if ship.location != shipment.source:
  return "Грузовик уже здесь"
 for body in [shipment.source, shipment.destination]:
  if not _has_spaceport(world.facilities, body):
   return "Нужен готовый космопорт (%s)" % Model.PLANET_NAMES[body]
  if _market_for(body).is_empty():
   return "Нужен склад колонии (%s)" % Model.PLANET_NAMES[body]
 if _colony_owner(shipment.source) != _colony_owner(shipment.destination):
  return "Склады должны принадлежать одной фракции"
 var available := float(_market_for(shipment.source).supply.get(shipment.resource, 0))
 var required: float = shipment.amount + reserve
 if available < required:
  return "На складе %s %s · требуется %s" % [
   Model.batch_amount(available), Model.batch_unit(shipment.resource), Model.batch_amount(required)]
 return ""

func depart_freighter(destination: String, food: bool = false) -> bool:
 if not freight_block_reason(destination, food).is_empty():
  return false
 _launch_freighter(_manual_order(destination, food))
 return true

## A manual flight is configured once, independently of scheduled legs.
## The old one-button APIs below remain for legacy test/save compatibility.
func manual_freight_reason(destination: String,
        resource: String, amount: int, slot: int = 1) -> String:
 if slot not in [1, 2]:
  return "Грузовик недоступен"
 if slot == 1 and _line_enabled:
  return "Сначала отключите регулярную линию"
 if not FREIGHT_ORDERS.has(destination) or (
     resource not in FREIGHT_RESOURCES.get(destination, [])):
  return "Недопустимый маршрут или груз"
 if amount < 0 or amount > FREIGHT_CAPACITY or (
     amount == 0 and destination != "earth"):
  return "Количество должно быть от 1 до %d" % FREIGHT_CAPACITY
 var shipment: Dictionary = freight_order(destination)
 shipment["resource"] = resource
 shipment["amount"] = amount
 return _shipment_block_reason(shipment, 0, slot)

func depart_manual_freight(destination: String,
        resource: String, amount: int, slot: int = 1) -> bool:
 if not manual_freight_reason(destination, resource, amount, slot).is_empty():
  return false
 var shipment: Dictionary = freight_order(destination)
 shipment["resource"] = resource
 shipment["amount"] = amount
 _launch_freighter(shipment, slot)
 return true


func return_order() -> Dictionary:
 var shipment := freight_order("earth")
 var available := float(_market_for("luna").get("supply", {}).get("ore", 0))
 shipment.amount = clampi(floori(available), 0, FREIGHT_CAPACITY)
 return shipment

func return_freighter() -> bool:
 var shipment := return_order()
 if not _shipment_block_reason(shipment).is_empty():
  return false
 _line_enabled = false
 _launch_freighter(shipment)
 return true

func _launch_freighter(shipment: Dictionary, slot: int = 1) -> void:
 var stock: Dictionary = _market_for(shipment.source).supply
 if shipment.amount > 0:
  stock[shipment.resource] = float(stock[shipment.resource]) - shipment.amount
 var path := Flight.make(world, "freight", shipment.source, now_native)
 var flight := {"location": "transit", "order": shipment, "trajectory": path,
  "departure": now_native, "arrival": path.arrival}
 if slot == 2:
  _second = flight
 else:
  _freighter = flight

static func _default_line_legs() -> Dictionary:
 var legs := {}
 for destination in FREIGHT_ORDERS:
  var order: Dictionary = FREIGHT_ORDERS[destination]
  legs[destination] = {"resource": order.resource, "amount": order.amount, "reserve": 0.0}
 return legs

func freight_line() -> Dictionary:
 return {"enabled": _line_enabled, "legs": _line_legs.duplicate(true)}

func set_freight_line_enabled(enabled: bool) -> void:
 _line_enabled = enabled and not _freighter.is_empty()

func configure_freight_line(legs: Dictionary) -> bool:
 if not _valid_line_legs(legs):
  return false
 for destination in FREIGHT_ORDERS:
  var leg: Dictionary = legs[destination]
  _line_legs[destination] = {"resource": leg.resource, "amount": int(leg.amount),
   "reserve": float(leg.reserve)}
 return true

static func _valid_line_legs(legs: Variant) -> bool:
 if not legs is Dictionary or legs.size() != FREIGHT_ORDERS.size():
  return false
 for destination in FREIGHT_ORDERS:
  var leg: Variant = legs.get(destination)
  if not leg is Dictionary or not _valid_cargo(leg, destination):
   return false
  if not _whole_number(leg.get("reserve")) or leg.reserve < 0:
   return false
 return true

static func _valid_cargo(cargo: Dictionary, destination: String) -> bool:
 var amount: Variant = cargo.get("amount")
 return cargo.get("resource") in FREIGHT_RESOURCES.get(destination, []) and (
  _whole_number(amount) and amount >= 1 and amount <= FREIGHT_CAPACITY)

static func _whole_number(value: Variant) -> bool:
 return (value is float or value is int) and is_finite(value) and floorf(value) == value

func _next_line_order() -> Dictionary:
 var destination := "earth" if _freighter.location == "luna" else "luna"
 var shipment := freight_order(destination)
 var leg: Dictionary = _line_legs[destination]
 shipment.resource = leg.resource
 shipment.amount = leg.amount
 return shipment

func freight_line_wait() -> String:
 if not _line_enabled or _freighter.location == "transit":
  return ""
 var shipment := _next_line_order()
 var reason := _shipment_block_reason(shipment, _line_legs[shipment.destination].reserve)
 if reason.is_empty():
  return ""
 return "Ждёт (%s) · %s" % [Model.PLANET_NAMES[shipment.source], reason]

func _dispatch_line() -> bool:
 if not _line_enabled or _freighter.location == "transit":
  return false
 var shipment := _next_line_order()
 if not _shipment_block_reason(shipment, _line_legs[shipment.destination].reserve).is_empty():
  return false
 _launch_freighter(shipment)
 return true

func freight_status(slot: int = 1) -> Dictionary:
 return (_second if slot == 2 else _freighter).duplicate(true)

## Read-only projection. Flight orders, not UI visibility, drive the port.
func earth_port_state() -> Dictionary:
 var bays := []
 for slot in [1, 2]:
  var ship := _second if slot == 2 else _freighter
  bays.append({
   "location": ship.get("location", ""),
   "order": ship.get("order", {}).duplicate(),
   "departure": ship.get("departure", 0.0),
   "arrival": ship.get("arrival", 0.0),
   "last_arrival": _earth_arrivals.get(slot, {}).duplicate(),
  })
 return {"time": now_native, "bays": bays}

func _land_freighter(slot: int) -> void:
 var ship := _second if slot == 2 else _freighter
 var shipment: Dictionary = ship.order
 var stock: Dictionary = _market_for(shipment.destination).supply
 if shipment.amount > 0:
  stock[shipment.resource] = float(stock.get(shipment.resource, 0)) + int(shipment.amount)
 if shipment.destination == "earth":
  _earth_arrivals[slot] = {"time": ship.arrival, "resource": shipment.resource,
   "amount": shipment.amount}
 ship.clear()
 ship.location = shipment.destination

func order_second_freighter(yard: String) -> bool:
 if not _second.is_empty() or not ship_order.is_empty():
  return false
 if not _earth_yard(world.facilities, yard):
  return false
 var stock: Dictionary = _market_for("earth").get("supply", {})
 if float(stock.get("metals", 0)) < SHIP_METALS:
  return false
 stock.metals = float(stock.metals) - SHIP_METALS
 ship_order = {"yard": yard, "start_native": now_native,
  "finish_native": now_native + Calendar.days_to_native(SHIP_DAYS)}
 return true

func cancel_second_freighter(yard: String) -> bool:
 if ship_order.get("yard") != yard:
  return false
 var stock: Dictionary = _market_for("earth").supply
 stock.metals = float(stock.metals) + SHIP_METALS
 ship_order = {}
 return true

func _earth_yard(facilities: Array, yard: String) -> bool:
 return facilities.any(func(f): return f.get("id") == yard and f.get("body") == "earth" and f.get("type") == "shipyard")

func _restore_flight(ship: Dictionary) -> Dictionary:
 var restored := ship.duplicate(true)
 if restored.has("order"):
  restored.order.amount = int(restored.order.amount)
  restored.trajectory = Flight.make(world, "freight", restored.order.source,
   restored.departure, restored.arrival)
 return restored

func _migrate_freighter(version: int, saved: Variant) -> Variant:
 if version == 1:
  return _starting_freighter()
 if version != 2 or not saved is Dictionary or saved.is_empty():
  return saved
 match saved.get("location"):
  "earth-colony", "luna-colony":
   if saved.get("metals") == 0:
    return {"location": "earth" if saved.location == "earth-colony" else "luna"}
  "transit":
   var shipment := freight_order("luna")
   if saved.get("metals") == shipment.amount:
    return {"location": "transit", "order": shipment,
     "departure": saved.get("departure"), "arrival": saved.get("arrival")}
 return null

func _valid_freighter(saved: Variant, facilities: Array, lunar: bool, time: float) -> bool:
 if not saved is Dictionary:
  return false
 if _starting_freighter().is_empty():
  return saved.is_empty()
 if saved.get("location") == "earth":
  return not saved.has("order")
 if not lunar or not _has_spaceport(facilities, "luna"):
  return false
 if saved.get("location") == "luna":
  return not saved.has("order")
 if saved.get("location") != "transit" or not _has_spaceport(facilities, "earth"):
  return false
 var shipment: Variant = saved.get("order")
 if not shipment is Dictionary:
  return false
 var expected: Dictionary = FREIGHT_ORDERS.get(shipment.get("destination"), {})
 var empty_return: bool = shipment.get("destination") == "earth" and (
  shipment.get("resource") == "ore" and shipment.get("amount") == 0)
 if expected.is_empty() or shipment.get("source") != expected.source or (
     not empty_return and not _valid_cargo(shipment, expected.destination)):
  return false
 return Flight.valid_times(saved, time)

func _market_for(body: String) -> Dictionary:
 var ac_location: String = ""
 for facility in world.get("facilities", []):
  if str(facility.get("body", "")) == body and (
      str(facility.get("type", "")) == "station") and (
      str(facility.get("location", "")) == body + "-colony"):
   ac_location = str(facility["location"])
   break
 if ac_location.is_empty():
  return {}
 for market in world.get("markets", []):
  if str(market.get("facility_id", "")) == ac_location:
   return market
 return {}

func _colony_owner(body: String) -> String:
 for f in world.get("facilities", []):
  if str(f.get("body", "")) == body and (
      str(f.get("location", "")) == body + "-colony") and (
      str(f.get("type", "")) == "station"):
   return str(f.get("faction_id", ""))
 return ""

func order(body: String, building_id: String,
        requested_site_id: String = "") -> Dictionary:
 var building: Dictionary = Model.find_building(building_id)
 if building.is_empty():
  return {"ok": false, "reason": "Неизвестное здание"}
 if not Model.colony(world, body):
  return {"ok": false, "reason": "Нет административного центра на планете"}
 if not Model.available(building, settings, world, body):
  if Model.built_or_pending(world, body, building_id):
   return {"ok": false, "reason": "Здание уже построено или строится"}
  return {"ok": false, "reason": "Недостаточно ресурсов или нет колонии"}
 # Determine and reserve a FREE compatible place BEFORE touching stock.
 # A missing explicit site is supported for older tests and AI commands;
 # the human catalog ALWAYS supplies a confirmed named site ID.
 var chosen: Dictionary = {}
 if body in ["earth", "luna"]:
  var available_sites: Array = SurfaceSites.free_sites(body, building_id,
   world.get("facilities", []))
  if requested_site_id.is_empty():
   if not available_sites.is_empty():
    chosen = available_sites[0]
  else:
   chosen = SurfaceSites.reservable(body, building_id,
    requested_site_id, world.get("facilities", []))
  if chosen.is_empty():
   return {"ok": false, "reason": "Площадка занята или не подходит"}
 var market: Dictionary = _market_for(body)
 if market.is_empty():
  return {"ok": false, "reason": "Нет местного склада административного центра"}
 var cost: int = int(settings[building_id].get("metals", 1))
 var supply: Dictionary = market.get("supply", {})
 if cost < 1 or int(supply.get("metals", 0)) < cost:
  return {"ok": false, "reason": "Недостаточно металла на складе"}
 var duration_days: int = Model.construction_days(building, settings)
 var id: String = "sol-lab-build-%04d" % next_id
 var finish: float = now_native + Calendar.days_to_native(
  float(duration_days))
 var new_site: Dictionary = {
  "id": id,
  "body": body,
  "building_id": building_id,
  "name": str(building["name"]),
  "start_native": now_native,
  "finish_native": finish,
  "duration_days": duration_days,
  "metals_spent": cost,
  "paid_resources": {"metals": cost}
 }
 if not chosen.is_empty():
  new_site["surface_site_id"] = str(chosen["id"])
 var facility: Dictionary = {
  "id": id,
  "name": str(building["name"]) + " · строится",
  "type": "construction_site",
  "body": body,
  "location": body + "-colony",
  "faction_id": str(_colony_owner(body)),
  "construction_building_id": building_id,
  "construction_start_native": now_native,
  "construction_finished_native": finish,
  "services": [],
  "docking_capacity": 0
 }
 if not chosen.is_empty():
  SurfaceSites.attach(facility, chosen)
 else:
  # Legacy non-Sol systems retain their existing deterministic sites.
  var mapped_site: Array = Model.surface_site(building_id)
  if mapped_site.size() == 2:
   facility["surface_site"] = mapped_site
 # Commit once, after every validation: stock and the unique site appear
 # together. There is no synthetic material refund or repeat debit.
 supply["metals"] = float(supply["metals"]) - cost
 market["supply"] = supply
 world["facilities"].append(facility)
 sites.append(new_site)
 next_id += 1
 return {"ok": true, "id": id, "finish_native": finish,
  "days": duration_days, "spent": cost,
  "surface_site_id": str(chosen.get("id", ""))}

## Refund only the exact resources previously debited by a still-pending
## order. Atomic with removal of its construction_site, including on restore.
## Repeated cancel / completed order cannot refund a second time.
func cancel_order(site_id: String) -> Dictionary:
 var site_index: int = -1
 for index in range(sites.size()):
  if str(sites[index].get("id", "")) == site_id:
   site_index = index
   break
 if site_index < 0:
  return {"ok": false, "reason": "Заказ уже отменён или завершён"}
 var site: Dictionary = sites[site_index]
 var facility_index: int = -1
 var facilities: Array = world.get("facilities", [])
 for index in range(facilities.size()):
  if str(facilities[index].get("id", "")) == site_id and str(
      facilities[index].get("type", "")) == "construction_site":
   facility_index = index
   break
 if facility_index < 0:
  return {"ok": false, "reason": "Стройплощадка уже отсутствует"}
 var body: String = str(site.get("body", ""))
 if str(facilities[facility_index].get("body", "")) != body:
  return {"ok": false, "reason": "Несовпадение колонии и стройплощадки"}
 var market: Dictionary = _market_for(body)
 if market.is_empty():
  return {"ok": false, "reason": "Нет склада колонии для возврата"}
 var paid: Dictionary = {}
 if site.get("paid_resources") is Dictionary:
  paid = site["paid_resources"]
 elif site.has("metals_spent"):
  paid = {"metals": site["metals_spent"]}
 for resource in paid:
  var amount: Variant = paid[resource]
  if not (amount is int or amount is float) or not is_finite(
      float(amount)) or float(amount) < 0:
   return {"ok": false, "reason": "Неверная запись списанных материалов"}
 # Validated all receipt fields before any inventory mutation.
 var supply: Dictionary = market["supply"]
 for resource in paid:
  supply[str(resource)] = float(supply.get(resource, 0.0)) + float(
   paid[resource])
 facilities.remove_at(facility_index)
 sites.remove_at(site_index)
 return {"ok": true, "id": site_id, "body": body,
  "refunded": paid.duplicate(true)}


func progress(site: Dictionary) -> float:
 var start: float = float(site.get("start_native", now_native))
 var end: float = float(site.get("finish_native", start))
 if end <= start:
  return 1.0
 return clampf((now_native - start) / (end - start), 0.0, 1.0)

func advance_to(new_native: float) -> Array:
 var completed: Array = []
 if not is_finite(new_native) or new_native < now_native:
  return completed
 now_native = new_native
 if expedition.ship.get("location", "") == "transit" and now_native >= float(expedition.ship.arrival):
  var landed_at := float(expedition.ship.arrival)
  if expedition.land_if_due(world, now_native, _colony_owner("earth")):
   _register_meals(world.facilities.back(), landed_at)
   completed.append("Колония на Луне основана")
 var remaining: Array = []
 for site in sites:
  if now_native + EPSILON_NATIVE < float(site["finish_native"]):
   remaining.append(site)
   continue
  if _finish(site):
   completed.append(str(site["name"]))
  else:
   # A missing construction site is not magically converted.
   remaining.append(site)
 sites = remaining
 if not ship_order.is_empty() and now_native + EPSILON_NATIVE >= float(ship_order.finish_native):
  ship_order = {}
  _second = {"location": "earth"}
  completed.append("Грузовик 2 готов")
 _advance_production(completed)
 if _dispatch_line():
  completed.append("Погрузка грузовика")
 return completed

func _finish(site: Dictionary) -> bool:
 var building_id: String = str(site["building_id"])
 var id: String = str(site["id"])
 for facility in world.get("facilities", []):
  if str(facility.get("id", "")) != id or (
      str(facility.get("type", "")) != "construction_site"):
   continue
  facility["type"] = building_id
  facility["name"] = str(site["name"])
  # Orbital placeholders are on the same physical world, but placed in
  # orbit only after completion, not as a second free building.
  if building_id in ["orbital_platform", "shipyard"]:
   facility["location"] = str(site["body"]) + "-orbit-" + id
  _register_producer(facility, float(site["finish_native"]))
  facility.erase("construction_start_native")
  facility.erase("construction_finished_native")
  return true
 return false

func snapshot() -> Dictionary:
 var saved_freighter := freight_status()
 saved_freighter.erase("trajectory")
 var saved_second := freight_status(2)
 saved_second.erase("trajectory")
 return {
  "version": VERSION,
  "expedition": expedition.snapshot(),
  "freighter": saved_freighter,
  "second_freighter": saved_second,
  "ship_order": ship_order.duplicate(),
  "freight_line": freight_line(),
  "system_id": str(world.get("system", {}).get("id", "")),
  "native_time": now_native,
  "next_id": next_id,
  "sites": sites.duplicate(true),
  "facilities": (world.get("facilities", []) as Array).duplicate(true),
  "markets": (world.get("markets", []) as Array).duplicate(true)
 }

func restore(data: Dictionary) -> bool:
 var version := int(data.get("version", -1))
 if version < 1 or version > VERSION or (
    str(data.get("system_id", "")) != str(world.get("system", {}).get(
    "id", ""))):
  return false
 var t: Variant = data.get("native_time", null)
 var seq: Variant = data.get("next_id", null)
 var input_sites: Variant = data.get("sites", null)
 var input_facilities: Variant = data.get("facilities", null)
 var input_markets: Variant = data.get("markets", null)
 if not (t is float or t is int) or not is_finite(float(t)):
  return false
 if not (seq is float or seq is int) or not is_finite(float(seq)):
  return false
 if float(t) < 0.0 or float(seq) != float(int(seq)) or int(seq) < 1:
  return false
 if not (input_sites is Array) or not (input_facilities is Array) or (
     not (input_markets is Array)):
  return false
 var lunar := false
 for item in input_markets:
  if item is Dictionary and item.get("facility_id") == expedition.PORT:
   lunar = true
 var manifest: Variant = data.get("expedition", initial_manifest)
 if not expedition.validate(manifest, lunar, float(t)):
  return false
 if version >= 5 and not manifest.ship.is_empty() and (
     manifest.ship.get("food") != expedition.STARTER_FOOD):
  return false
 if input_markets.size() != initial_markets + int(lunar):
  return false
 var all_ids: Dictionary = {}
 var site_ids: Dictionary = {}
 for f in input_facilities:
  if not (f is Dictionary) or str(f.get("id", "")).is_empty():
   return false
  var id: String = str(f["id"])
  if all_ids.has(id):
   return false
  if f.has("surface_site"):
   var saved_site: Variant = f["surface_site"]
   if not (saved_site is Array) or saved_site.size() != 2:
    return false
   if not ((saved_site[0] is int or saved_site[0] is float) and (
       saved_site[1] is int or saved_site[1] is float)):
    return false
   var position := Vector2(float(saved_site[0]), float(saved_site[1]))
   if not is_finite(position.x) or not is_finite(position.y) or (
       position.length() > 0.90):
    return false
  for key in ["next_batch_native", "next_meal_native"]:
   if f.has(key):
    var due: Variant = f[key]
    if not (due is float or due is int) or not is_finite(float(due)) or float(due) <= float(t):
     return false
  if f.has("next_meal_native") and not f.get("fed") is bool:
   return false
  all_ids[id] = f
 if all_ids.has("facility-luna-ac") != lunar:
  return false
 for site in input_sites:
  if not (site is Dictionary):
   return false
  var sid: String = str(site.get("id", ""))
  if sid.is_empty() or site_ids.has(sid) or not all_ids.has(sid):
   return false
  var node: Dictionary = all_ids[sid]
  if str(node.get("type", "")) != "construction_site" or (
      str(node.get("construction_building_id", "")) != str(
      site.get("building_id", ""))):
   return false
  if Model.find_building(str(site.get("building_id", ""))).is_empty():
   return false
  if not (site.get("finish_native", null) is float or (
      site.get("finish_native", null) is int)):
   return false
  if not is_finite(float(site["finish_native"])) or (
      float(site["finish_native"]) < float(t)):
   return false
  var paid: Variant = site.get("paid_resources",
   {"metals": site.get("metals_spent", 0)})
  if not (paid is Dictionary):
   return false
  for resource in paid:
   var amount: Variant = paid[resource]
   if not (amount is int or amount is float) or not is_finite(
       float(amount)) or float(amount) < 0:
    return false
  site_ids[sid] = true
 for m in input_markets:
  if not (m is Dictionary) or not (m.get("supply", null) is Dictionary):
   return false
  if int(m["supply"].get("metals", -1)) < 0:
   return false
 var restored_freighter: Variant = _migrate_freighter(version, data.get("freighter"))
 if not _valid_freighter(restored_freighter, input_facilities, lunar, float(t)):
  return false
 var restored_line: Variant = data.get("freight_line") if version >= 4 else (
  {"enabled": false, "legs": _default_line_legs()})
 if not restored_line is Dictionary or not restored_line.get("enabled") is bool or (
     not _valid_line_legs(restored_line.get("legs"))):
  return false
 var saved_second: Variant = data.get("second_freighter", {}) if version >= 7 else {}
 var saved_order: Variant = data.get("ship_order", {}) if version >= 7 else {}
 if not saved_second is Dictionary or not saved_order is Dictionary:
  return false
 if not saved_second.is_empty() and not _valid_freighter(saved_second, input_facilities, lunar, float(t)):
  return false
 if not saved_order.is_empty():
  var start: Variant = saved_order.get("start_native")
  var finish: Variant = saved_order.get("finish_native")
  if not saved_second.is_empty() or not _earth_yard(input_facilities, str(saved_order.get("yard", ""))):
   return false
  if not (start is int or start is float) or not (finish is int or finish is float):
   return false
  if start < 0 or start > t or finish <= t or not is_equal_approx(finish - start, Calendar.days_to_native(SHIP_DAYS)):
   return false
 # Commit all restored domains only after all checks pass.
 expedition.restore(world, manifest)
 if version < 5 and not expedition.ship.is_empty():
  expedition.ship.food = expedition.STARTER_FOOD
 world["facilities"] = input_facilities.duplicate(true)
 _ensure_earth_spaceport(world.facilities)
 SurfaceSites.reconcile(world["facilities"], input_sites)
 world["markets"] = input_markets.duplicate(true)
 if version < 5 and lunar:
  var supply: Dictionary = _market_for("luna").supply
  supply.food = float(supply.get("food", 0)) + expedition.STARTER_FOOD
 _freighter = _restore_flight(restored_freighter)
 _second = _restore_flight(saved_second)
 ship_order = saved_order.duplicate()
 configure_freight_line(restored_line.legs)
 set_freight_line_enabled(restored_line.enabled)
 sites = input_sites.duplicate(true)
 _earth_arrivals.clear()
 now_native = float(t)
 _index_producers()
 next_id = int(seq)
 return true


func _index_producers() -> void:
 producers.clear()
 meal_cycles.clear()
 next_batch = INF
 for facility in world.get("facilities", []):
  _register_producer(facility, now_native)
  _register_meals(facility, now_native)

func colony_population(body: String) -> int:
 var count := 0
 for group in world.get("populations", []):
  if group.get("facility_id") == body + "-colony":
   count += int(group.get("population_count", 0))
 return count

func _food_rate(body: String) -> float:
 return colony_population(body) * FOOD_PER_RESIDENT

func _register_meals(facility: Dictionary, start: float) -> void:
 var body: String = facility.get("body", "")
 if facility.get("type") != "station" or facility.get("location") != body + "-colony":
  return
 var supply: Dictionary = _market_for(body).get("supply", {})
 if supply.is_empty() or colony_population(body) <= 0:
  return
 facility.next_meal_native = facility.get("next_meal_native", start + Calendar.days_to_native(CYCLE_DAYS))
 facility.fed = facility.get("fed", true)
 meal_cycles[body] = {"facility": facility, "stock": supply}
 next_batch = minf(next_batch, facility.next_meal_native)

func _feed_colony(body: String, meal: Dictionary) -> void:
 var rate := _food_rate(body)
 var stock: Dictionary = meal.stock
 var available := float(stock.get("food", 0))
 meal.facility.fed = available + EPSILON_NATIVE >= rate
 stock.food = snappedf(maxf(0.0, available - rate), 0.01)
 # Local Earth water supply feeds the starter farm's existing recipe.
 if body == "earth":
  stock.water = float(stock.get("water", 0)) + EARTH_WATER_PER_CYCLE

func _register_producer(facility: Dictionary, start: float) -> void:
 var kind: String = str(facility.get("type", ""))
 if kind not in ["mining_rig", "refinery", "farm"]:
  return
 var body: String = str(facility.get("body", ""))
 var market := _market_for(body)
 if market.is_empty():
  return
 var due := float(facility.get("next_batch_native", start + Calendar.days_to_native(CYCLE_DAYS)))
 facility["next_batch_native"] = due
 producers.append({"facility": facility, "market": market, "recipe": Model.find_building(kind)})
 next_batch = minf(next_batch, due)

func _advance_production(completed: Array) -> void:
 var interval := Calendar.days_to_native(CYCLE_DAYS)
 while true:
  # Unload before a meal due at the same time, never before an earlier meal.
  var first_eta := float(_freighter.get("arrival", INF))
  var second_eta := float(_second.get("arrival", INF))
  var arrival := minf(first_eta, second_eta)
  if arrival <= now_native and arrival <= next_batch + EPSILON_NATIVE:
   var slot := 1 if first_eta <= second_eta else 2
   _land_freighter(slot)
   completed.append("Грузовик %d разгружен" % slot)
   continue
  if now_native + EPSILON_NATIVE < next_batch:
   return
  var deadline := next_batch
  next_batch = INF
  for body in meal_cycles:
   var meal: Dictionary = meal_cycles[body]
   var due := float(meal.facility.next_meal_native)
   if due <= deadline + EPSILON_NATIVE:
    _feed_colony(body, meal)
    due += interval
    meal.facility.next_meal_native = due
   next_batch = minf(next_batch, due)
  for entry in producers:
   var facility: Dictionary = entry.facility
   var due := float(facility.next_batch_native)
   if due <= deadline + EPSILON_NATIVE:
    _run_batch(facility, entry.market.supply, entry.recipe, due)
    due += interval
    facility.next_batch_native = due
   next_batch = minf(next_batch, due)
  batch_revision += 1

func _run_batch(facility: Dictionary, supply: Dictionary,
        recipe: Dictionary, attempt_time: float = -1.0) -> void:
 if attempt_time < 0.0:
  attempt_time = now_native
 facility["last_attempt_native"] = attempt_time
 if facility.body == "luna" and recipe.id == "mining_rig" and (
     not meal_cycles.get("luna", {}).get("facility", {}).get("fed", true)):
  facility.production_status = "Простой: поселенцам не хватает еды"
  facility["last_idle_reason"] = facility.production_status
  return
 var row: Dictionary = settings.get(recipe.id, {})
 var output: float = Model.calculated(recipe, settings, planets, str(facility.body))
 if output <= 0:
  facility["production_status"] = "Простой: нулевая выработка"
  facility["last_idle_reason"] = facility["production_status"]
  return
 # Check all ingredients before committing the complete batch.
 for key in recipe.inputs:
  var required: int = int(row.get("input_" + key, recipe.inputs[key]))
  var available: float = float(supply.get(key, 0))
  if available < required:
   facility["production_status"] = "Простой: не хватает %s (нужно %s, есть %s)" % [
    Model.batch_unit(key), Model.batch_amount(float(required)),
    Model.batch_amount(available)]
   facility["last_idle_reason"] = facility["production_status"]
   return
 var changes := PackedStringArray()
 for key in recipe.inputs:
  var consumed: int = int(row.get("input_" + key, recipe.inputs[key]))
  supply[key] = snappedf(float(supply.get(key, 0)) - consumed, 0.01)
  if consumed > 0:
   changes.append("−%s %s" % [
    Model.batch_amount(float(consumed)), Model.batch_unit(key)])
 supply[recipe.product] = snappedf(
  float(supply.get(recipe.product, 0)) + output, 0.01)
 changes.append("+%s %s" % [
  Model.batch_amount(output), Model.batch_unit(str(recipe.product))])
 facility["production_status"] = ", ".join(changes)
 # Authoritative completed batch receipt, separate from future predictions.
 facility["last_batch_native"] = attempt_time
 facility["last_batch_amount"] = output
 facility["last_batch_resource"] = str(recipe.product)
 facility["last_batch_changes"] = facility["production_status"]
 facility["last_idle_reason"] = ""

## Read-only lookup by physical facility ID, never aggregated by recipe.
## Legacy free-form status cannot be mistaken for a confirmed last batch.
func production_details(facility_id: String) -> Dictionary:
 for raw in world.get("facilities", []):
  if str(raw.get("id", "")) != facility_id:
   continue
  var facility: Dictionary = raw
  var kind: String = str(facility.get("type", ""))
  var result: Dictionary = {"id": facility_id, "kind": kind,
   "supported": kind in ["mining_rig", "farm", "refinery"]}
  if not bool(result["supported"]):
   return result
  var recipe: Dictionary = Model.find_building(kind)
  result["product"] = str(recipe.get("product", "none"))
  result["forecast"] = Model.calculated(recipe, settings, planets,
   str(facility.get("body", "")))
  result["next_native"] = float(facility.get("next_batch_native", INF))
  result["idle_reason"] = str(facility.get("last_idle_reason", ""))
  if result["idle_reason"].is_empty() and str(facility.get(
      "production_status", "")).begins_with("Простой:"):
   result["idle_reason"] = str(facility["production_status"])
  result["last_present"] = facility.has("last_batch_native") and (
   facility.has("last_batch_amount")) and facility.has(
   "last_batch_resource")
  if bool(result["last_present"]):
   result["last_native"] = float(facility["last_batch_native"])
   result["last_amount"] = float(facility["last_batch_amount"])
   result["last_resource"] = str(facility["last_batch_resource"])
   result["last_changes"] = str(facility.get("last_batch_changes", ""))
  return result
 return {}


## Read-only snapshot from this planet's actual colony market. An
## uncolonized body has no stock panel, never an invented zero-warehouse.
func colony_inventory(body: String) -> Dictionary:
 var market: Dictionary = _market_for(body)
 if market.is_empty() or not (market.get("supply", null) is Dictionary):
  return {"present": false, "supply": {}}
 return {"present": true, "supply": (market["supply"] as Dictionary).duplicate()}

func colony_food(body: String) -> Dictionary:
 if not meal_cycles.has(body):
  return {}
 var meal: Dictionary = meal_cycles[body]
 var stock := float(meal.stock.get("food", 0))
 var rate := _food_rate(body)
 var food := {"stock": stock, "rate": rate, "covered": meal.facility.fed,
  "days": floori(stock * CYCLE_DAYS / rate)}
 for ship in [_freighter, _second]:
  var order: Dictionary = ship.get("order", {})
  if order.get("destination") == body and order.get("resource") == "food" and (
      float(ship.arrival) < float(food.get("arrival", INF))):
   food["incoming"] = order.amount
   food["arrival"] = ship.arrival
 return food

func production_summary(body: String) -> String:
 var lines := PackedStringArray()
 for entry in producers:
  if str(entry.facility.body) == body:
   lines.append("%s: %s" % [
    str(entry.recipe.name),
    str(entry.facility.get("production_status", "Ожидается первый выпуск"))])
 if lines.is_empty():
  return "Предприятия: нет"
 return "Предприятия · последняя партия (30 дней):\n" + "\n".join(lines)

func inventory_summary(body: String) -> String:
 var market: Dictionary = _market_for(body)
 if market.is_empty():
  return "Нет склада колонии"
 var stock: Dictionary = market.supply
 var lines := PackedStringArray([
  "Склад: руда %s · топливо %s · металл %s" % [
   Model.batch_amount(float(stock.get("ore", 0))),
   Model.batch_amount(float(stock.get("fuel", 0))),
   Model.batch_amount(float(stock.get("metals", 0)))],
  "Вода: %s · еда: %s" % [
   Model.batch_amount(float(stock.get("water", 0))),
   Model.batch_amount(float(stock.get("food", 0)))]
 ])
 var has_producers := false
 for entry in producers:
  if str(entry.facility.body) != body:
   continue
  if not has_producers:
   lines.append("Последняя партия (цикл 30 дней):")
   has_producers = true
  lines.append("%s: %s" % [
   str(entry.recipe.name),
   str(entry.facility.get("production_status", "Ожидается первый выпуск"))])
 return "\n".join(lines)

