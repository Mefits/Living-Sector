extends RefCounted
## UI-only catalog; original Rust-port seed is unchanged.
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
  var native: bool = bool(b["ported"])
  var row: Dictionary = {"metals":600 if native else 0,"labor":150 if native else 0,"base":int(b["base"])}
  for ingredient in b["inputs"].keys():
   row["input_"+str(ingredient)] = int(b["inputs"][ingredient])
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
static func available(b: Dictionary, settings: Dictionary, world: Dictionary, body: String) -> bool:
 return bool(b["ported"]) and colony(world,body) and stock(world,body) >= int(settings.get(str(b["id"]),{}).get("metals",0))
