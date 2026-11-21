extends SceneTree

var frame_index := 0
var capture_folder := OS.get_environment("SOL_ROAD_FRAMES")

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
 await capture(12)
 check(map.focus_body("earth"), "Earth exists on the ordinary globe")
 await capture(22)
 if map._focus_zoom_target > 0:
  map._zoom = map._focus_zoom_target
 for step in range(6):
  if district.visible:
   break
  var wheel := InputEventMouseButton.new()
  wheel.button_index = MOUSE_BUTTON_WHEEL_UP
  wheel.pressed = true
  var earth: Dictionary = map._body_by_id("earth")
  wheel.position = map._district_footprint(map._body_position(earth, map._orbit_scale()), map._body_size(earth)).get_center()
  map._gui_input(wheel)
 await capture(12)
 check(district.visible and map.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Approaching the focused Earth opens the district")
 await create_timer(0.52).timeout
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
 check(browser.placement_confirm.disabled and browser.placement_caption.text.contains("Участок занят"),
  "Occupied plot gives the specific rejection")
 plot_click(district, "earth-farm-02")
 check(browser.placement_confirm.disabled and browser.placement_caption.text.contains("Непригодная"),
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
 await ore_chain(game)
 var plant: Dictionary = district._facilities["earth-industry-01"]
 check(plant.type == "refinery", "Selected refinery exists")
 if not plant.has("refinery_shipment"):
  advance(game, plant.next_batch_native)
  plant = district._facilities["earth-industry-01"]
 check(plant.has("refinery_shipment"), "Refinery ingredients leave the warehouse")
 var expected_output: float = plant.refinery_shipment.output
 var due_at_gate: float = plant.refinery_shipment.arrival
 var metal_before: float = game.construction.colony_inventory("earth").supply.metals
 game._save_game()
 game._load_game()
 advance(game, due_at_gate)
 check(is_equal_approx(game.construction.colony_inventory("earth").supply.metals,
  metal_before + expected_output), "In-flight refinery supply survives reload and credits one batch")
 await unload_in_district(game)
 print("SOL_EARTH_DISTRICT_PASS")
 if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
  await create_timer(1.0).timeout
  await RenderingServer.frame_post_draw
  var frame := root.get_texture().get_image()
  check(frame.get_size() == Vector2i(1366, 768), "Capture is at the requested game resolution")
  check(frame.save_png("user://Living-Sector-Earth-District-Live-Port.png") == OK, "Capture saved")
  await create_timer(2.0).timeout
 quit()

func advance(game: Control, until: float) -> void:
 game.native_time = until
 game._advance_construction()
 game._update_native_map()

func unload_in_district(game: Control) -> void:
 var sim = game.construction
 game._native_body_selected({"id": "luna"})
 game.colony_button.pressed.emit()
 game.expedition_dialog.confirmed.emit()
 game.expedition_dialog.hide()
 advance(game, sim.expedition.ship.arrival)
 game._open_build()
 for kind in ["mining_rig", "spaceport"]:
  game.browser.build_controls[kind].button.pressed.emit()
  var site: String = game.browser.placement_options[0].id
  game.native_view.choose_placement(site)
  game.browser.select_placement(site)
  game.browser.placement_confirm.pressed.emit()
 advance(game, sim.sites.back().finish_native)
 game._close_browser()
 game._open_manual_freight()
 for index in game.manual_resource.item_count:
  if game.manual_resource.get_item_metadata(index) == "ore":
   game.manual_resource.select(index)
 game.manual_amount.value = float(game.district._facilities.get("earth-mine-02", {}).get("last_batch_amount", 0))
 var outbound_amount: float = game.manual_amount.value
 var earth_before: float = sim.colony_inventory("earth").supply.ore
 var luna_before: float = sim.colony_inventory("luna").supply.get("ore", 0)
 check(not game.manual_freight_dialog.get_ok_button().disabled, "Outbound order is ready")
 game.manual_freight_dialog.get_ok_button().pressed.emit()
 game.manual_freight_dialog.hide()
 check(sim.freight_status().location == "loading", "Reserved ore is loading before takeoff")
 check(is_equal_approx(sim.colony_inventory("earth").supply.ore, earth_before - outbound_amount),
  "Reservation removes the batch from available inventory")
 game._save_game()
 game._load_game()
 check(sim.freight_status().location == "loading" and sim.freight_status().order.amount == outbound_amount,
  "Reload retains the reserved amount without a second debit")
 if not capture_folder.is_empty():
  game._open_district()
  var port_edge: Vector2 = game.district._origin + Vector2(900, 510) * game.district._scale
  var target_point: Vector2 = (port_edge - game.district._origin) / game.district._scale
  var turn := InputEventMouseButton.new()
  turn.pressed = true
  turn.position = port_edge
  turn.button_index = MOUSE_BUTTON_WHEEL_UP
  game.district._gui_input(turn)
  check(((port_edge - game.district._origin) / game.district._scale).distance_to(target_point) < 0.01,
   "Zoom keeps the port edge under the cursor")
  var start: float = sim.now_native
  var load_end: float = sim.freight_status().load_due
  for index in range(67):
   advance(game, lerpf(start, load_end - 0.01, index / 66.0))
   await capture()
 advance(game, sim.freight_status().load_due)
 await capture(12)
 check(sim.freight_status().location == "transit" and sim.freight_status().order.amount == outbound_amount,
  "After the loader finishes, the ship departs with the same amount")
 game._save_game()
 game._load_game()
 advance(game, sim.freight_status().arrival)
 check(is_equal_approx(sim.colony_inventory("luna").supply.ore, luna_before + outbound_amount),
  "Moon warehouse receives the precise cargo once")
 # Use mined ore from the real lunar production cycle.
 game._set_speed(16)
 for tick in range(500):
  if sim.colony_inventory("luna").supply.get("ore", 0) >= 3:
   break
  game._step()
 check(sim.colony_inventory("luna").supply.get("ore", 0) >= 3, "Lunar mine produced a shipment")
 game._open_manual_freight()
 game.manual_amount.value = 3
 check(not game.manual_freight_dialog.get_ok_button().disabled, "Return ore order is ready")
 game.manual_freight_dialog.get_ok_button().pressed.emit()
 game.manual_freight_dialog.hide()
 var eta: float = sim.freight_status().arrival
 game._open_district()
 var district = game.district
 var port = district._port
 check(is_instance_valid(port) and port.is_visible_in_tree() and port.position == Vector2(676, 449),
  "Completed Earth port mounts the live scene at the real main pad")
 advance(game, eta - 0.01)
 var stock_before: float = sim.colony_inventory("earth").supply.get("ore", 0)
 await process_frame
 await process_frame
 check(port._state.bays[0].order.get("amount") == 3, "Mounted port sees the inbound container")
 advance(game, eta)
 await process_frame
 await process_frame
 check(sim.colony_inventory("earth").supply.get("ore", 0) == stock_before + 3,
  "Touchdown credits the real Earth warehouse once")
 advance(game, eta + port.SERVICE * 0.72)
 await process_frame
 await process_frame
 check(port._state.bays[0].last_arrival.get("amount") == 3 and port._state.time > eta,
  "Mounted port has a live unload pose on its service road")
 check(sim.colony_inventory("earth").supply.get("ore", 0) == stock_before + 3,
  "The loader pose does not credit the warehouse a second time")
 plot_click(district, "earth-port-01")
 check(game.colony_panel.page == "logistics", "Port plot opens its normal controls")
 for destination in ["luna", "earth"]:
  game._open_manual_freight()
  game.manual_empty.button_pressed = true
  check(not game.manual_freight_dialog.get_ok_button().disabled, "Empty reposition is available")
  game.manual_freight_dialog.get_ok_button().pressed.emit()
  game.manual_freight_dialog.hide()
  game._save_game()
  game._load_game()
  var flight: Dictionary = sim.freight_status()
  check(flight.location == "transit" and flight.order.amount == 0, "Empty ship stays empty across reload")
  advance(game, flight.arrival)
  check(sim.freight_status().location == destination, "Empty ship reaches the requested port")
 check_supply_line(game)
 print("SOL_EARTH_DISTRICT_LIVE_UNLOAD_PASS")

func check_supply_line(game: Control) -> void:
 var sim = game.construction
 # Fixture: the reserve leaves exactly three units available on the Moon.
 var moon: Dictionary = sim._market_for("luna").supply
 sim._set_ship(2, {"location": "earth"})
 var legs := {"luna": {"resource": "food", "amount": 10, "reserve": 0, "policy": "empty"},
  "earth": {"resource": "ore", "amount": 10, "reserve": 2, "policy": "partial"}}
 check(sim.configure_freight_line(legs), "Partial return and empty outbound accepted")
 sim.set_freight_line_enabled(true)
 advance(game, sim.now_native + 0.01)
 check(sim.freight_status().order.amount == 0, "Outbound leg repositions empty")
 check(sim.depart_manual_freight("luna", "fuel", 1, 2), "Free ship accepts an independent fuel delivery")
 var outbound_eta: float = sim.freight_status().arrival
 advance(game, outbound_eta - 0.01)
 moon.ore = 5.0
 advance(game, outbound_eta)
 var back: Dictionary = sim.freight_status()
 check(back.order.amount == 3 and moon.ore == 2, "Partial shipment preserves two units of reserve")
 sim.set_freight_line_enabled(false)
 game._save_game()
 game._load_game()
 check(not sim.freight_line().enabled and sim.freight_line().legs.earth.policy == "partial",
  "Stopped line and partial policy survive reload")
 advance(game, back.arrival)
 check(sim.freight_status().location == "earth" and sim.freight_status(2).location == "luna",
  "Both ships finish their own orders and stay docked")

func ore_chain(game: Control) -> void:
 var sim = game.construction
 var mine: Dictionary = game.district._facilities["earth-mine-02"]
 var due: float = mine.next_batch_native
 # The refinery can consume ore during the same production cycle. Read
 # immediately after production to isolate the arrival from those receipts.
 advance(game, due)
 check(sim.ground_ore.size() == 1, "Mine generated one physical batch")
 var job: Dictionary = sim.ground_ore[0]
 var amount: float = job.amount
 var stored: float = sim.colony_inventory("earth").supply.ore
 check(job.pickup > due and job.due > job.pickup, "A visible batch waits before collection")
 if not capture_folder.is_empty():
  for index in range(38):
   advance(game, lerpf(due, lerpf(job.pickup, job.due, 0.5), index / 37.0))
   await capture()
 advance(game, lerpf(job.pickup, job.due, 0.5))
 game._save_game()
 game._close_district()
 game._load_game()
 game._open_district()
 check(sim.ground_ore.size() == 1 and sim.ground_ore[0].amount == amount,
  "Save/load preserves the exact road shipment")
 check(sim.colony_inventory("earth").supply.ore == stored, "Road goods are not yet spendable")
 if not capture_folder.is_empty():
  for index in range(38):
   advance(game, lerpf(sim.now_native, job.due - 0.005, 0.14))
   await capture()
 advance(game, job.due)
 check(is_equal_approx(sim.colony_inventory("earth").supply.ore, stored + amount),
  "Warehouse receives the fractional batch once at the gate")
 print("SOL_EARTH_ROAD_BATCH ", amount)

func capture(count := 1) -> void:
 if capture_folder.is_empty() or DisplayServer.get_name() == "headless":
  return
 for index in count:
  await process_frame
  await RenderingServer.frame_post_draw
  var frame := root.get_texture().get_image()
  check(frame.save_png(capture_folder.path_join("%04d.png" % frame_index)) == OK, "Video frame saved")
  frame_index += 1


