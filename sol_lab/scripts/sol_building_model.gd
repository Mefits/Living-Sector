extends RefCounted
## UI-only catalog; original Rust-port seed is unchanged.
const SurfaceSites = preload("res://scripts/view/sol_surface_sites.gd")
const VISIBLE: Array = ["earth", "luna", "mars"]
const PLANET_NAMES := {"earth": "Земля", "luna": "Луна", "mars": "Марс"}
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
## Fixed separated preview slots on the visible Sol globe, no biome logic.
const SURFACE_SITES: Dictionary = {
 "administrative_center": [-0.46, -0.34],
 "mining_rig": [0.43, -0.34],
 "refinery": [-0.41, 0.34],
 "farm": [0.44, 0.33]
}
const BATCH_UNITS: Dictionary = {
 "ore":"руды", "water":"воды", "food":"еды", "metals":"металла",
 "fuel":"топлива", "components":"компонентов", "polymers":"полимеров",
 "energy_cells":"энергии"
}
static func surface_site(building_id: String) -> Array:
 return (SURFACE_SITES.get(building_id, []) as Array).duplicate()

## Identical enterprise types are separate facility IDs and globe anchors.
## The first preserves the established art location, subsequent sites use
## deterministic inboard offsets saved on the real facility at order time.
static func surface_site_instance(building_id: String, index: int) -> Array:
 var base: Array = surface_site(building_id)
 if base.size() != 2 or index <= 0:
  return base
 var origin := Vector2(float(base[0]), float(base[1]))
 for attempt in range(1, 56):
  var slot: int = index + attempt - 1
  var angle: float = float(slot) * 2.399963229728653
  var radius: float = 0.20 + 0.11 * float((slot / 7) % 3)
  var candidate: Vector2 = origin + Vector2(
   cos(angle), sin(angle)) * radius
  if candidate.length() <= 0.85 and candidate.distance_to(origin) >= 0.14:
   return [snappedf(candidate.x, 0.0001),
    snappedf(candidate.y, 0.0001)]
 return base

static func batch_unit(resource: String) -> String:
 return str(BATCH_UNITS.get(resource, resource))

static func batch_amount(value: float) -> String:
 var number: float = snappedf(value, 0.01)
 var whole: int = roundi(number)
 return str(whole) if is_equal_approx(number, float(whole)) else str(number)

const LABELS: Dictionary = {"ore":"Руда","ice":"Лёд","gas":"Газ","rare_ore":"Редкая руда","crystal_ore":"Кристаллы","water":"Вода","food":"Еда","metals":"Металлы","components":"Компоненты","fuel":"Топливо","polymers":"Полимеры","energy_cells":"Энергия","electronics":"Электроника","tools":"Инструменты","medical":"Медтовары","luxury":"Роскошь","none":"—"}
static func resource_label(id: String) -> String:
 return str(LABELS.get(id,id))
static func building_defaults(recipes: Dictionary = {}) -> Dictionary:
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
 # Shipped JSON recipes initialize the same editable building settings.
 var mapping: Dictionary = {
  "farm_water_in": ["farm", "input_water"],
  "farm_food_out": ["farm", "base"],
  "smelt_ore_in": ["refinery", "input_ore"],
  "smelt_fuel_in": ["refinery", "input_fuel"],
  "smelt_metals_out": ["refinery", "base"]
 }
 for key in mapping:
  var value: Variant = recipes.get(key, null)
  if (value is int or value is float) and is_finite(float(value)) and (
      float(value) >= 0.0 and float(value) <= 100000.0):
   var target: Array = mapping[key]
   result[target[0]][target[1]] = int(value)
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

## Infrastructure remains unique; enterprises can have multiple actual
## instances with independent production clocks and physical selection IDs.
const UNIQUE_BUILDINGS: Array[String] = [
 "administrative_center", "spaceport", "orbital_platform", "shipyard"]

static func built_or_pending(world: Dictionary,
        body: String, building_id: String) -> bool:
 if building_id not in UNIQUE_BUILDINGS:
  return false
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
 if cost < 1 or stock(world, body) < cost:
  return false
 if body in VISIBLE:
  return not SurfaceSites.free_sites(body, id, world.get(
   "facilities", [])).is_empty()
 return true

static func construction_days(building: Dictionary,
        settings: Dictionary) -> int:
 return maxi(1, int(settings.get(str(building.get("id", "")),
  {}).get("days", 45)))

## Legacy compatibility for old test scripts. No labor shifts are used.
static func minimum_construction_shifts(_building: Dictionary,
        _settings: Dictionary) -> int:
 return -1

