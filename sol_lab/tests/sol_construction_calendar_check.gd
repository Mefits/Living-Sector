extends SceneTree
const Starter = preload("res://scripts/sol_start_scenario.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Building = preload("res://scripts/sol_construction_runtime.gd")
const Projection = preload("res://scripts/view/physical_assets_projection.gd")

func new_world() -> Dictionary:
 var file: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sol.json"))
 return Starter.apply(file) if file is Dictionary else {}

func _initialize() -> void:
 var good: bool = true
 var settings: Dictionary = Model.building_defaults()
 for item in Model.BUILDINGS:
  good = good and settings[item["id"]]["metals"] == 1
  good = good and settings[item["id"]]["days"] == 45
 var first = Building.new()
 first.setup(new_world(), settings)
 good = good and first.order("earth", "farm")["ok"]
 good = good and Model.stock(first.world, "earth") == 999
 good = good and not first.order("earth", "farm")["ok"]
 good = good and Model.stock(first.world, "earth") == 999
 good = good and not first.order("luna", "farm")["ok"]
 good = good and Projection.build(first.world)["surface"].size() == 2
 var raw_site: Dictionary = first.world["facilities"][1]
 good = good and str(raw_site.get("type", "")) == "construction_site"
 good = good and is_equal_approx(float(raw_site.get(
  "construction_start_native", -1)), 0.0)
 good = good and is_equal_approx(float(raw_site.get(
  "construction_finished_native", -1)),
  Calendar.days_to_native(45.0))
 var saved: Dictionary = first.snapshot()
 var second = Building.new()
 second.setup(new_world(), settings)
 good = good and second.restore(saved)
 good = good and Model.stock(second.world, "earth") == 999
 var duration: float = Calendar.days_to_native(45.0)
 good = good and is_equal_approx(duration, 700.0 * 45.0 / 365.0)
 good = good and second.advance_to(duration - 0.001).is_empty()
 good = good and second.sites.size() == 1
 good = good and second.advance_to(duration).size() == 1
 good = good and second.sites.is_empty()
 var completed: bool = false
 for f in second.world["facilities"]:
  if str(f.get("construction_building_id", "")) == "farm":
   completed = str(f.get("type", "")) == "farm"
 good = good and completed
 good = good and second.advance_to(duration + 10).is_empty()
 good = good and not second.order("earth", "farm")["ok"]
 good = good and Model.stock(second.world, "earth") == 999
 good = good and Calendar.calendar_text(0.0) == "Год 1 · день 001/365"
 good = good and Calendar.calendar_text(700.0) == "Год 2 · день 001/365"
 var bad: Dictionary = second.snapshot()
 bad["markets"][0]["supply"]["metals"] = -1
 good = good and not second.restore(bad)
 good = good and Model.stock(second.world, "earth") == 999
 if good:
  print("SOL_CONSTRUCTION_CALENDAR_PASS")
  quit(0)
 else:
  push_error("SOL_CONSTRUCTION_CALENDAR_FAIL")
  quit(1)
