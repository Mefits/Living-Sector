extends SceneTree
const Model = preload("res://scripts/sol_building_model.gd")
func _initialize() -> void:
 var seed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sol.json"))
 if not (seed is Dictionary):
  push_error("SOL_LAB_MODEL_FAIL: missing Sol")
  quit(1)
  return
 var planets: Dictionary = Model.planet_defaults(seed)
 var buildings: Dictionary = Model.building_defaults()
 var mine: Dictionary = Model.BUILDINGS[1]
 var valid: bool = Model.VISIBLE == ["earth","luna","mars"]
 valid = valid and planets.size()==3
 valid = valid and absf(Model.calculated(mine,buildings,planets,"earth")-6.5)<0.001
 valid = valid and absf(Model.calculated(mine,buildings,planets,"luna")-3.0)<0.001
 var earth: Dictionary = planets["earth"]
 earth["ore"] = 0.4
 planets["earth"] = earth
 valid = valid and absf(Model.calculated(mine,buildings,planets,"earth")-4.0)<0.001
 valid = valid and Model.stock(seed,"earth")==1000
 valid = valid and Model.available(Model.BUILDINGS[2],buildings,seed,"earth")
 valid = valid and not Model.available(Model.BUILDINGS[2],buildings,seed,"mars")
 if valid:
  print("SOL_LAB_MODEL_PASS")
  quit(0)
 else:
  push_error("SOL_LAB_MODEL_FAIL")
  quit(1)
