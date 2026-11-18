extends RefCounted
## UI-only catalog; original Rust-port seed is unchanged.
const ConstructionCycle = preload("res://scripts/sim/construction/construction_cycle.gd")
const VISIBLE: Array = ["earth", "luna", "mars"]
const BUILDINGS: Array = [
 {"id":"administrative_center","name":"Административный центр","product":"food","base":0,"inputs":{},"ported":false},
 {"id":"mining_rig","name":"Добывающий комплекс","product":"ore","base":10,"inputs":{},"ported":true},
 {"id":"farm","name":"Ферма","product":"food","base":10,"inputs":{"water":3},"ported":true},
 {"id":"power_plant","name":"Энергостанция","product":"energy_cells","base":0,"inputs":{},"ported":false},
 {"id":"refinery","name":"Перерабатывающий комплекс","product":"metals","base":8,"inputs":{"ore":10,"fuel":1},"ported":true},
 {"id":"factory","name":"Фабрика","product":"components","base":5,"inputs":{"metals":3,"polymers":1},"ported":true},
 {"id":"spaceport","name":"Космопорт","product":"none","base":0,"inputs":{},"ported":false},
 {"id":"orbital_platform","name":"Орбитальная платформа","product":"none","base":0,"inputs":{},"ported":false},
 {"id":"shipyard","name":"Верфь (модуль)","product":"none","base":0,"inputs":{},"ported":false}
]
const LABELS: Dictionary = {"ore":"Руда","ice":"Лёд","gas":"Газ","rare_ore":"Редкая руда","crystal_ore":"Кристаллы","water":"Вода","food":"Еда","metals":"Металлы","components":"Компоненты","fuel":"Топливо","polymers":"Полимеры","energy_cells":"Энергия","none":"—"}
static func resource_label(id: String) -> String:
 return str(LABELS.get(id,id))
static func building_defaults() -> Dictionary:
 var result: Dictionary = {}
 for b in BUILDINGS:
  # The temporary construction test charges exactly 1 metal for EVERY
  # catalog entry. No paid labor, executor, or construction-shift formula.
  var row: Dictionary = {
   "metals": 1, "days": 45, "base": int(b["base"])
  }
  for ingredient in b["inputs"].keys():
   row["input_" + str(ingredient)] = int(b["inputs"][ingredient])
  result[str(b["id"])] = row
 return result

static func planet_defaults(world: Dictionary) -> Dictionary:
 var result: Dictionary = {}
 for b in world.get("bodies",[]):
  var id: String = str(b.get("id",""))
  if not VISIBLE.has(id):
   continue
  var row: Dictionary = (b.get("resources",{}) as Dictionary).duplicate(true)
  row["food"] = 1.0 if id=="earth" else 0.0
  for product in ["metals","components","energy_cells"]:
   if not row.has(product):
    row[product] = 1.0
  result[id] = row
 return result
static func calculated(b: Dictionary, settings: Dictionary, planets: Dictionary, body: String) -> float:
 var product: String = str(b["product"])
 if product=="none":
  return 0.0
 var base: float = float(settings.get(str(b["id"]),{}).get("base",0))
 var coefficient: float = float(planets.get(body,{}).get(product,1.0))
 return snappedf(base * coefficient, 0.01)
static func stock(world: Dictionary, body: String) -> int:
 for f in world.get("facilities",[]):
  if str(f.get("body","")) != body or str(f.get("type","")) != "station":
   continue
  for market in world.get("markets",[]):
   if str(market.get("facility_id","")) == str(f.get("location","")):
    return int(market.get("supply",{}).get("metals",0))
 return 0
static func colony(world: Dictionary, body: String) -> bool:
 for f in world.get("facilities",[]):
  if str(f.get("body","")) == body and str(f.get("type","")) == "station":
   return true
 return false
static func find_building(id: String) -> Dictionary:
 for item in BUILDINGS:
  if str(item["id"]) == id:
   return item
 return {}

static func built_or_pending(world: Dictionary,
        body: String, building_id: String) -> bool:
 for facility in world.get("facilities", []):
  if not (facility is Dictionary):
   continue
  if str(facility.get("body", "")) != body:
   continue
  if building_id == "administrative_center":
   if str(facility.get("type", "")) == "station" and (
      str(facility.get("location", "")) == body + "-colony"):
    return true
  if str(facility.get("construction_building_id", "")) == building_id:
   return true
  if str(facility.get("type", "")) == building_id:
   return true
 return false

static func available(b: Dictionary, settings: Dictionary,
        world: Dictionary, body: String) -> bool:
 var id: String = str(b.get("id", ""))
 if not VISIBLE.has(body) or id.is_empty() or not colony(world, body):
  return false
 if built_or_pending(world, body, id):
  return false
 var cost: int = int(settings.get(id, {}).get("metals", 1))
 return cost >= 1 and stock(world, body) >= cost

static func construction_days(building: Dictionary,
        settings: Dictionary) -> int:
 return maxi(1, int(settings.get(str(building.get("id", "")),
  {}).get("days", 45)))

## Legacy compatibility for old test scripts. No labor shifts are used.
static func minimum_construction_shifts(_building: Dictionary,
        _settings: Dictionary) -> int:
 return -1
