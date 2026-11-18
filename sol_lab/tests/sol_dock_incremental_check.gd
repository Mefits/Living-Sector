extends SceneTree
## Regression: timed UI updates must preserve the exact same scene nodes.
const Browser = preload("res://scripts/building_browser.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Main = preload("res://scripts/main.gd")
const Start = preload("res://scripts/sol_start_scenario.gd")

func _initialize() -> void:
 var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
  "res://data/sol.json"))
 if not (parsed is Dictionary):
  push_error("SOL_DOCK_INCREMENTAL_FAIL: seed")
  quit(1)
  return
 var world: Dictionary = Start.apply(parsed)
 var settings: Dictionary = {
  "buildings": Model.building_defaults(),
  "planets": Model.planet_defaults(world),
  "needs": {"earth_food": 5, "earth_water": 3}
 }
 var browser = Browser.new()
 get_root().add_child(browser)
 browser.set_dock_width(780.0)
 browser.configure(world, settings, "earth", false)
 browser.set_construction_state(world, [], 0.0)
 var okay: bool = browser.queue_panel.get_child_count() == 1
 var empty_line: Node = browser.queue_panel.get_child(0)
 browser.set_construction_state(world, [], 1.0)
 okay = okay and browser.queue_panel.get_child_count() == 1
 okay = okay and browser.queue_panel.get_child(0) == empty_line
 var site: Dictionary = {
  "id": "site-1", "body": "earth", "name": "Ферма",
  "start_native": 0.0, "finish_native": 100.0
 }
 browser.set_construction_state(world, [site], 0.0)
 var controls: Dictionary = browser.queue_rows.get("site-1", {})
 okay = okay and browser.queue_panel.get_child_count() == 1
 okay = okay and not controls.is_empty()
 var original_label: Label = controls["line"]
 var original_bar: ProgressBar = controls["bar"]
 browser.set_construction_state(world, [site], 50.0)
 controls = browser.queue_rows["site-1"]
 okay = okay and controls["line"] == original_label
 okay = okay and controls["bar"] == original_bar
 okay = okay and is_equal_approx(original_bar.value, 50.0)
 browser.set_construction_state(world, [site], 80.0)
 okay = okay and browser.queue_rows["site-1"]["line"] == original_label
 okay = okay and browser.queue_rows["site-1"]["bar"] == original_bar
 okay = okay and is_equal_approx(original_bar.value, 80.0)
 browser.set_construction_state(world, [], 101.0)
 okay = okay and browser.queue_rows.is_empty()
 okay = okay and browser.queue_panel.get_child_count() == 1
 var main = Main.new()
 var root_snapshot: Dictionary = {"a": {"b": 4}}
 var shallow: Dictionary = root_snapshot.duplicate(false)
 shallow["x"] = 99
 okay = okay and not root_snapshot.has("x")
 main.free()
 browser.queue_free()
 if okay:
  print("SOL_DOCK_INCREMENTAL_PASS")
  quit(0)
 else:
  push_error("SOL_DOCK_INCREMENTAL_FAIL")
  quit(1)
