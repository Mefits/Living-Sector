extends RefCounted
## Scripted scenario contracts use the ordinary manifests and market mutations.
const Model = preload("res://scripts/sol_building_model.gd")
const Sites = preload("res://scripts/view/sol_surface_sites.gd")
const OWNER := "mars-expedition"
const LOT := 4
const PHASES := ["", "waiting", "ore_out", "metal_back", "charter_metal",
 "charter_ore", "building", "working", "metal_out", "fuel_back"]
var phase := ""

func start(sim) -> void:
 for body in ["luna", "mars"]:
  if sim.expedition.ship.is_empty():
   sim.expedition.prepare_ship()
  sim.expedition.ship.merge({"location": "transit", "target": body, "arrival": 0.0}, true)
  var owner: String = OWNER if body == "mars" else sim._colony_owner("earth")
  sim.expedition.land_if_due(sim.world, 0.0, owner)
  var port := {"id": "scenario-" + body + "-port", "name": "Космопорт",
   "type": "spaceport", "body": body, "location": body + "-colony", "faction_id": owner}
  Sites.attach(port, Sites.entries(body, "spaceport")[0])
  sim.world.facilities.append(port)
 var mine := {"id": "scenario-mars-mine", "name": "Добывающий комплекс",
  "type": "mining_rig", "body": "mars", "location": "mars-colony", "faction_id": OWNER}
 Sites.attach(mine, Sites.entries("mars", "mining_rig")[0])
 sim.world.facilities.append(mine)
 sim._market_for("luna").supply.food = 6
 sim._market_for("mars").supply.merge({"ore": 8, "metals": 0, "food": 100, "fuel": 4}, true)
 sim._second = {"location": "mars"}
 sim._index_producers()
 sim.configure_freight_line({
  "luna": {"resource": "food", "amount": 2, "reserve": 0, "policy": "full"},
  "earth": {"resource": "ore", "amount": 1, "reserve": 0, "policy": "empty"}})
 sim.set_freight_line_enabled(true)
 phase = "waiting"

func charter_reason(sim) -> String:
 if phase.is_empty():
  return "Сценарий не активен"
 if phase != "waiting":
  return "Обмен уже начат"
 if sim.freight_status().location != "earth":
  return "Дождитесь грузовика у Земли"
 if not _can_pay(sim, "metals", "ore", LOT):
  return "Для сделки нужны 4 металла Земли и 4 руды Марса"
 return ""

func charter(sim) -> bool:
 if phase.is_empty() or not charter_reason(sim).is_empty():
  return false
 sim.set_freight_line_enabled(false)
 sim._change_stock("mars", "ore", -LOT, sim.now_native)
 phase = "charter_metal"
 _fly(sim, "earth", "mars", "metals", LOT, 1)
 return true

func _can_pay(sim, earth_good: String, mars_good: String, amount: int) -> bool:
 return sim._market_for("earth").supply.get(earth_good, 0) >= amount and (
  sim._market_for("mars").supply.get(mars_good, 0) >= amount)

func _fly(sim, origin: String, target: String, resource: String, amount: int, slot: int) -> void:
 sim._launch_freighter({"source": origin, "destination": target, "resource": resource,
  "amount": amount}, slot)

func _prepaid(sim, origin: String, target: String, resource: String, slot: int) -> void:
 sim._takeoff({"source": origin, "destination": target, "resource": resource,
  "amount": LOT}, slot, sim.now_native)

func arrived(sim, slot: int, shipment: Dictionary) -> void:
 # Each return leg follows settlement of the previous physical delivery.
 match phase:
  "charter_metal":
   if slot == 1 and shipment.destination == "mars":
    phase = "charter_ore"
    _prepaid(sim, "mars", "earth", "ore", 1)
  "charter_ore":
   if slot == 1 and shipment.destination == "earth":
    phase = "working" if Model.built_or_pending(sim.world, "mars", "refinery") else "building"
    sim.set_freight_line_enabled(true)
  "ore_out", "metal_out":
   if slot == 2 and shipment.destination == "earth":
    var fuel := phase == "metal_out"
    phase = "fuel_back" if fuel else "metal_back"
    _prepaid(sim, "earth", "mars", "fuel" if fuel else "metals", 2)
  "metal_back", "fuel_back":
   if slot == 2 and shipment.destination == "mars":
    phase = "building" if phase == "metal_back" else "working"

func update(sim, notices: Array) -> void:
 if phase == "waiting" and sim._market_for("mars").supply.ore >= 10 and _can_pay(sim, "metals", "ore", LOT):
  sim._change_stock("earth", "metals", -LOT, sim.now_native)
  phase = "ore_out"
  _fly(sim, "mars", "earth", "ore", LOT, 2)
  notices.append("Марс: руда отправлена в обмен на металл")
 if phase in ["building", "charter_ore"] and not Model.built_or_pending(sim.world, "mars", "refinery"):
  if sim.order("mars", "refinery", "", true).ok:
   notices.append("Марс заложил переработчик")
 if phase in ["building", "working"] and sim.freight_status(2).location == "mars" and (
   sim.production_details(_refinery_id(sim)).get("last_present", false)) and (
   _can_pay(sim, "fuel", "metals", LOT)):
  sim._change_stock("earth", "fuel", -LOT, sim.now_native)
  phase = "metal_out"
  _fly(sim, "mars", "earth", "metals", LOT, 2)
  notices.append("Марс: металл отправлен в обмен на топливо")

func _refinery_id(sim) -> String:
 for building in sim.world.facilities:
  if building.body == "mars" and building.type == "refinery":
   return building.id
 return ""
