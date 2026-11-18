extends SceneTree
const Model = preload("res://scripts/sol_building_model.gd")
const Browser = preload("res://scripts/building_browser.gd")
const Lab = preload("res://scripts/main.gd")

func _initialize() -> void:
 var settings: Dictionary = Model.building_defaults()
 var original: Dictionary = Model.BUILDINGS[2] # farm, original 150 paid labor
 var okay: bool = Model.construction_days(original, settings) == 45
 settings["farm"]["days"] = 60
 okay = okay and Model.construction_days(original, settings) == 60
 settings["farm"]["days"] = 30
 okay = okay and Model.construction_days(original, settings) == 30
 okay = okay and Model.construction_days(Model.BUILDINGS[3], settings) == 45
 # Create actual UI nodes so parser and UI methods are exercised.
 var ui := Lab.new()
 ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 ui.size = Vector2(1366, 768)
 get_root().add_child(ui)
 ui.size = Vector2(1366, 768)
 ui._layout_right_side()
 okay = okay and ui.sidebar != null and ui.browser != null
 okay = okay and not ui.browser.visible
 if okay:
  ui._open_build()
  okay = okay and ui.browser.visible and not ui.sidebar.visible
  okay = okay and ui.browser.page == "build"
  var map_end: float = ui.native_view.offset_right
  okay = okay and map_end < -400.0
  okay = okay and is_equal_approx(ui.browser.offset_left, map_end)
  okay = okay and ui.browser.grid != null
  okay = okay and ui.browser.grid.columns == 3
  ui.browser._navigate("admin_buildings")
  okay = okay and ui.browser.grid != null
  okay = okay and ui.browser.grid.columns == 3
  ui._close_browser()
  okay = okay and ui.sidebar.visible and not ui.browser.visible
 ui.queue_free()
 if okay:
  print("SOL_DOCK_TIMING_PASS")
  quit(0)
 else:
  push_error("SOL_DOCK_TIMING_FAIL")
  quit(1)
