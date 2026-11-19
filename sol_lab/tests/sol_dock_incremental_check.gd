extends SceneTree
## Regression: timed UI updates must preserve the exact same scene nodes.
const Browser = preload("res://scripts/building_browser.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Main = preload("res://scripts/main.gd")
const Start = preload("res://scripts/sol_start_scenario.gd")
const Runtime = preload("res://scripts/sol_construction_runtime.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")

func _initialize() -> void:
 call_deferred("_run")

func _run() -> void:
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
 # Real order and completion must NOT rebuild the nine catalogue cards.
 var runtime = Runtime.new()
 runtime.setup(world, settings["buildings"])
 var existing: Dictionary = browser.build_controls["mining_rig"]
 var original_card: PanelContainer = existing["card"]
 var original_button: Button = existing["button"]
 var original_grid: GridContainer = browser.grid
 var placed: Dictionary = runtime.order("earth", "mining_rig")
 okay = okay and bool(placed.get("ok", false))
 var before_ms: int = Time.get_ticks_usec()
 browser.configure(world, settings, "earth", false)
 var full_rebuild_us: int = Time.get_ticks_usec() - before_ms
 # Explicitly rebuild once for a matched, same-scene comparison.
 existing = browser.build_controls["mining_rig"]
 original_card = existing["card"]
 original_button = existing["button"]
 original_grid = browser.grid
 var refresh_start: int = Time.get_ticks_usec()
 browser.refresh_build_availability()
 var refresh_us: int = Time.get_ticks_usec() - refresh_start
 okay = okay and browser.build_controls["mining_rig"]["card"] == original_card
 okay = okay and browser.build_controls["mining_rig"]["button"] == original_button
 okay = okay and browser.grid == original_grid
 okay = okay and original_button.disabled
 runtime.advance_to(Calendar.days_to_native(45.0))
 browser.refresh_build_availability()
 browser.set_construction_state(world, runtime.sites,
  Calendar.days_to_native(45.0))
 okay = okay and browser.build_controls["mining_rig"]["card"] == original_card
 okay = okay and original_button.disabled
 print("SOL_UI_REUSE_BENCH rebuild_ms=", float(full_rebuild_us) / 1000.0,
  " refresh_ms=", float(refresh_us) / 1000.0)
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
