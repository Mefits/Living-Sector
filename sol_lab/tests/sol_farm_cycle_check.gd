extends SceneTree
## 30-day farm cycle, exact stock deltas, save/load deadline and ground slots.
const Starter = preload("res://scripts/sol_start_scenario.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Runtime = preload("res://scripts/sol_construction_runtime.gd")
const PhysicalAssets = preload("res://scripts/view/physical_assets_projection.gd")

func _runtime(settings: Dictionary) -> Variant:
 var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
  "res://data/sol.json"))
 var world: Dictionary = Starter.apply(parsed)
 var runtime = Runtime.new()
 runtime.planets = Model.planet_defaults(world)
 runtime.setup(world, settings)
 return runtime

func _stock(runtime: Variant) -> Dictionary:
 for market in runtime.world.get("markets", []):
  if str(market.get("facility_id", "")) == "earth-colony":
   return market["supply"]
 return {}

func _facility(runtime: Variant, kind: String) -> Dictionary:
 for row in runtime.world.get("facilities", []):
  if str(row.get("type", "")) == kind:
   return row
 return {}

func _sites(world: Dictionary) -> Dictionary:
 var result: Dictionary = {}
 for asset in PhysicalAssets.build(world).get("surface", []):
  result[str(asset["id"])] = asset["site"]
 return result

func _day(days: float) -> float:
 return Calendar.days_to_native(days)

func _initialize() -> void:
 var ok: bool = true
 var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(
  "res://data/balance_defaults.json"))
 var recipes: Dictionary = source.get("recipes", {}) if source is Dictionary else {}
 ok = ok and Model.building_defaults(recipes)["farm"]["input_water"] == int(
  recipes.get("farm_water_in", -1))
 ok = ok and Model.building_defaults(recipes)["farm"]["base"] == int(
  recipes.get("farm_food_out", -1))
 var defaults: Dictionary = Model.building_defaults()
 var runtime = _runtime(defaults)
 var stock: Dictionary = _stock(runtime)
 stock["water"] = 3.0
 stock["food"] = 0.0
 ok = ok and bool(runtime.order("earth", "farm").get("ok", false))
 ok = ok and runtime.advance_to(_day(45.0)).size() == 1
 var farm: Dictionary = _facility(runtime, "farm")
 ok = ok and is_equal_approx(float(farm.get("next_batch_native", -1.0)),
  _day(75.0))
 runtime.advance_to(_day(75.0) - 0.001)
 ok = ok and float(stock["water"]) == 3.0 and float(stock["food"]) == 0.0
 runtime.advance_to(_day(75.0))
 ok = ok and float(stock["water"]) == 0.0 and float(stock["food"]) == 10.0
 ok = ok and str(farm.get("production_status", "")) == "−3 воды, +10 еды"
 runtime.advance_to(_day(105.0))
 ok = ok and float(stock["food"]) == 10.0
 ok = ok and "не хватает воды" in str(farm.get("production_status", ""))
 ok = ok and is_equal_approx(float(farm["next_batch_native"]), _day(135.0))
 runtime.advance_to(_day(120.0))
 var checkpoint: Variant = JSON.parse_string(JSON.stringify(runtime.snapshot()))
 var restored = _runtime(defaults)
 ok = ok and restored.restore(checkpoint)
 var resumed: Dictionary = _facility(restored, "farm")
 var warehouse: Dictionary = _stock(restored)
 ok = ok and is_equal_approx(float(resumed.get("next_batch_native", -1.0)),
  _day(135.0))
 ok = ok and "не хватает воды" in str(resumed.get("production_status", ""))
 warehouse["water"] = 3.0
 restored.advance_to(_day(135.0) - 0.001)
 ok = ok and float(warehouse["food"]) == 10.0
 restored.advance_to(_day(135.0))
 ok = ok and float(warehouse["water"]) == 0.0
 ok = ok and float(warehouse["food"]) == 20.0
 ok = ok and str(resumed.get("production_status", "")) == "−3 воды, +10 еды"
 ok = ok and is_equal_approx(float(resumed["next_batch_native"]), _day(165.0))
 ok = ok and "Ферма: −3 воды, +10 еды" in restored.inventory_summary("earth")
 # Custom input/output values must apply to the real inventory.
 var tuned: Dictionary = Model.building_defaults({
  "farm_water_in": 4, "farm_food_out": 12})
 var custom = _runtime(tuned)
 var custom_stock: Dictionary = _stock(custom)
 custom_stock["water"] = 4.0
 custom_stock["food"] = 0.0
 ok = ok and bool(custom.order("earth", "farm").get("ok", false))
 custom.advance_to(_day(75.0))
 ok = ok and float(custom_stock["water"]) == 0.0
 ok = ok and float(custom_stock["food"]) == 12.0
 ok = ok and str(_facility(custom, "farm").get(
  "production_status", "")) == "−4 воды, +12 еды"
 # Distinct sites for AC, mine, refinery and farm, before and after build.
 var visual = _runtime(defaults)
 ok = ok and _sites(visual.world).has(Starter.AC_ID)
 for kind in ["mining_rig", "refinery", "farm"]:
  ok = ok and bool(visual.order("earth", kind).get("ok", false))
 var pending: Dictionary = _sites(visual.world)
 ok = ok and pending.size() == 4
 var positions: Array = pending.values()
 for i in range(positions.size()):
  for j in range(i + 1, positions.size()):
   ok = ok and positions[i].distance_to(positions[j]) >= 0.60
 visual.advance_to(_day(45.0))
 ok = ok and _sites(visual.world) == pending
 var saved_visual: Variant = JSON.parse_string(JSON.stringify(visual.snapshot()))
 var reloaded = _runtime(defaults)
 ok = ok and reloaded.restore(saved_visual)
 ok = ok and _sites(reloaded.world) == pending
 # A building without a fixed slot must still survive a checkpoint.
 var general = _runtime(defaults)
 ok = ok and bool(general.order("earth", "spaceport").get("ok", false))
 var general_save: Variant = JSON.parse_string(JSON.stringify(general.snapshot()))
 var general_reload = _runtime(defaults)
 ok = ok and general_reload.restore(general_save)
 if ok:
  print("SOL_FARM_CYCLE_PASS")
  quit(0)
 else:
  push_error("SOL_FARM_CYCLE_FAIL")
  quit(1)
