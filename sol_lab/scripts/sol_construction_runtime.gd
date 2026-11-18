extends RefCounted
## Sol Lab test-only construction model. Real stock is debited from the
## detached Rust Sol market. Sites live in the same map world as buildings.
## No second N39 simulation, no free facility, no paid labor or paid shifts.
const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")

const VERSION: int = 1
var world: Dictionary = {}
var settings: Dictionary = {}
var now_native: float = 0.0
var next_id: int = 1
var sites: Array = []
const CYCLE_DAYS := 30
var planets: Dictionary = {}
var producers: Array = []
var next_batch: float = INF
var batch_revision := 0

func setup(source_world: Dictionary, building_settings: Dictionary) -> void:
 world = source_world
 settings = building_settings
 now_native = 0.0
 next_id = 1
 sites.clear()
 _index_producers()

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

func order(body: String, building_id: String) -> Dictionary:
 var building: Dictionary = Model.find_building(building_id)
 if building.is_empty():
  return {"ok": false, "reason": "Неизвестное здание"}
 if not Model.colony(world, body):
  return {"ok": false, "reason": "Нет административного центра на планете"}
 if not Model.available(building, settings, world, body):
  if Model.built_or_pending(world, body, building_id):
   return {"ok": false, "reason": "Здание уже построено или строится"}
  return {"ok": false, "reason": "Недостаточно ресурсов или нет колонии"}
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
  "metals_spent": cost
 }
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
  "surface_site": Model.surface_site(building_id),
  "services": [],
  "docking_capacity": 0
 }
 # Commit once, after every validation: stock and the unique site appear
 # together. There is no synthetic material refund or repeat debit.
 supply["metals"] = float(supply["metals"]) - cost
 market["supply"] = supply
 world["facilities"].append(facility)
 sites.append(new_site)
 next_id += 1
 return {"ok": true, "id": id, "finish_native": finish,
  "days": duration_days, "spent": cost}

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
 var remaining: Array = []
 for site in sites:
  if now_native + 0.000001 < float(site["finish_native"]):
   remaining.append(site)
   continue
  if _finish(site):
   completed.append(str(site["name"]))
  else:
   # A missing construction site is not magically converted.
   remaining.append(site)
 sites = remaining
 _advance_production()
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
 return {
  "version": VERSION,
  "system_id": str(world.get("system", {}).get("id", "")),
  "native_time": now_native,
  "next_id": next_id,
  "sites": sites.duplicate(true),
  "facilities": (world.get("facilities", []) as Array).duplicate(true),
  "markets": (world.get("markets", []) as Array).duplicate(true)
 }

func restore(data: Dictionary) -> bool:
 if int(data.get("version", -1)) != VERSION or (
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
 if input_markets.size() != (world.get("markets", []) as Array).size():
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
  if f.has("next_batch_native"):
   var due: Variant = f.next_batch_native
   if not (due is float or due is int) or not is_finite(float(due)) or float(due) <= float(t):
    return false
  all_ids[id] = f
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
  site_ids[sid] = true
 for m in input_markets:
  if not (m is Dictionary) or not (m.get("supply", null) is Dictionary):
   return false
  if int(m["supply"].get("metals", -1)) < 0:
   return false
 # Commit all restored domains only after all checks pass.
 world["facilities"] = input_facilities.duplicate(true)
 world["markets"] = input_markets.duplicate(true)
 sites = input_sites.duplicate(true)
 now_native = float(t)
 _index_producers()
 next_id = int(seq)
 return true


func _index_producers() -> void:
 producers.clear()
 next_batch = INF
 for facility in world.get("facilities", []):
  _register_producer(facility, now_native)

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

func _advance_production() -> void:
 var interval := Calendar.days_to_native(CYCLE_DAYS)
 while now_native >= next_batch:
  var deadline := next_batch
  next_batch = INF
  for entry in producers:
   var facility: Dictionary = entry.facility
   var due := float(facility.next_batch_native)
   if due <= deadline:
    _run_batch(facility, entry.market.supply, entry.recipe)
    due += interval
    facility.next_batch_native = due
   next_batch = minf(next_batch, due)
  batch_revision += 1

func _run_batch(facility: Dictionary, supply: Dictionary, recipe: Dictionary) -> void:
 var row: Dictionary = settings.get(recipe.id, {})
 var output: float = Model.calculated(recipe, settings, planets, str(facility.body))
 if output <= 0:
  facility["production_status"] = "Простой: нулевая выработка"
  return
 # Check all ingredients before committing the complete batch.
 for key in recipe.inputs:
  var required: int = int(row.get("input_" + key, recipe.inputs[key]))
  var available: float = float(supply.get(key, 0))
  if available < required:
   facility["production_status"] = "Простой: не хватает %s (нужно %s, есть %s)" % [
    Model.batch_unit(key), Model.batch_amount(float(required)),
    Model.batch_amount(available)]
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
