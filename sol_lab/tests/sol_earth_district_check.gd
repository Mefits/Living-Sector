extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/sol_building_model.gd")
const Sites = preload("res://scripts/view/sol_surface_sites.gd")

func _initialize() -> void:
 call_deferred("run")

func click(view: Control, point: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = point
 event.pressed = true
 view._gui_input(event)

func plot_click(view: Control, site: String) -> void:
 click(view, view._origin + (view._plots[site] as Rect2).get_center() * view._scale)

func check(condition: bool, message: String) -> void:
 if not condition:
  push_error(message)
  quit(1)
  assert(condition, message)

func run() -> void:
 var game = MAIN.instantiate()
 root.add_child(game)
 await process_frame
 game.paused = true
 var map = game.native_view
 var district = game.district
 var stock: Control = game.colony_stock_panel
 check(map.focus_body("earth"), "Earth exists on the ordinary globe")
 map._zoom = map._focus_zoom_target
 for step in range(6):
  if district.visible:
   break
  var wheel := InputEventMouseButton.new()
  wheel.button_index = MOUSE_BUTTON_WHEEL_UP
  wheel.pressed = true
  wheel.position = map.size * 0.5
  map._gui_input(wheel)
 check(district.visible and not map.visible, "Approaching the focused Earth opens the district")
 check(stock.get_parent() == game.colony_panel.dock_layout, "Stock is visible in the district")
 check(district._facilities.has("earth-ac-01") and district._facilities.has("earth-farm-01"),
  "The initial AC and farm occupy the correct plots")
 for building in Model.BUILDINGS:
  var kind: String = building["id"]
  for entry in Sites.entries("earth", kind):
   check((entry.kind == "ground") == district.PLOTS.has(entry.id),
    "Each ground site is mapped and each orbital site stays outside the district")
 for left in district.PLOTS:
  for right in district.PLOTS:
   if left != right:
    check(not (district.PLOTS[left] as Rect2).intersects(district.PLOTS[right]),
     "Plot footprints must not overlap")

 game._open_build()
 var browser = game.browser
 var initial: float = Model.stock(game.world, "earth")
 browser.build_controls["refinery"].button.pressed.emit()
 await process_frame
 check(stock.get_parent() == browser.dock_layout and stock.is_visible_in_tree(),
  "Same inventory remains above the catalog")
 check(browser.get_global_rect().end.x <= 1367 and browser.scroll.size.y > 210,
  "1366 by 768 leaves the catalog usable with the warehouse open")
 plot_click(district, "earth-ac-01")
 check(browser.placement_confirm.disabled and browser.placement_caption.text.begins_with("Участок занят"),
  "Occupied plot gives the specific rejection")
 plot_click(district, "earth-farm-02")
 check(browser.placement_confirm.disabled and browser.placement_caption.text.begins_with("Непригодная"),
  "Incompatible ground cannot be selected")
 plot_click(district, "earth-industry-01")
 check(not browser.placement_confirm.disabled and Model.stock(game.world, "earth") == initial,
  "Preview gives no debit")
 browser.placement_confirm.pressed.emit()
 check(Model.stock(game.world, "earth") == initial - 1 and game.construction.sites.size() == 1,
  "Confirmation spends metal once and reserves the site")
 game._save_game()
 game._load_game()
 check(district._facilities["earth-industry-01"].type == "construction_site",
  "Loading a pending project preserves its plot")
 browser.cancel_requested.emit(game.construction.sites[0].id)
 check(not district._facilities.has("earth-industry-01") and Model.stock(game.world, "earth") == initial,
  "Cancellation releases the plot and refunds it")

 var chosen := {
  "refinery": "earth-industry-01", "factory": "earth-industry-02",
  "power_plant": "earth-industry-03", "mining_rig": "earth-mine-02",
  "spaceport": "earth-port-01", "farm": "earth-farm-02"}
 for kind in chosen:
  if district._facilities.has(chosen[kind]):
   continue
  browser.build_controls[kind].button.pressed.emit()
  plot_click(district, chosen[kind])
  browser.placement_confirm.pressed.emit()
  check(district._facilities.get(chosen[kind], {}).get("type") == "construction_site",
   "Catalog placement reserved " + kind)
 var deadline: float = game.construction.sites.back().finish_native
 game.native_time = deadline
 game._advance_construction()
 game._update_native_map()
 game._save_game()
 game._load_game()
 for kind in chosen:
  check(district._facilities.get(chosen[kind], {}).get("type") == kind,
   "Finished facility keeps its confirmed plot across save and load: " + kind)
 game._close_browser()
 plot_click(district, "earth-industry-01")
 check(game.colony_panel.selected_facility == district._facilities["earth-industry-01"].id,
  "Clicking a completed facility opens the real facility details")
 district.return_requested.emit()
 check(map.visible and not district.visible and map.is_body_focused(),
  "Return restores the Earth globe")
 game._open_district()
 plot_click(district, "earth-industry-01")
 print("SOL_EARTH_DISTRICT_PASS")
 if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
  await create_timer(1.0).timeout
  await RenderingServer.frame_post_draw
  var frame := root.get_texture().get_image()
  check(frame.get_size() == Vector2i(1366, 768), "Capture is at the requested game resolution")
  check(frame.save_png("user://Living-Sector-Earth-District.png") == OK, "Capture saved")
  await create_timer(2.0).timeout
 quit()
