extends SceneTree
## Ordinary gameplay scene. SOL_SURFACE_FRAMES optionally records the same sequence.
const MAIN = preload("res://scenes/main.tscn")
const Roads = preload("res://scripts/view/sol_district_roads.gd")
const SITE := "earth-south-01"
var frames := OS.get_environment("SOL_SURFACE_FRAMES")
var frame_number := 0

func _initialize() -> void:
 call_deferred("run")

func verify(ok: bool, reason: String) -> void:
 if not ok:
  push_error(reason)
  quit(1)
  assert(ok, reason)

func wheel(view: Control, at: Vector2, up: bool) -> void:
 var event := InputEventMouseButton.new()
 event.position = at
 event.pressed = true
 event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
 view._gui_input(event)

func point_click(view: Control, at: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.position = at
 event.pressed = true
 event.button_index = MOUSE_BUTTON_LEFT
 view._gui_input(event)

func record() -> void:
 await process_frame
 if frames.is_empty() or DisplayServer.get_name() == "headless":
  return
 await RenderingServer.frame_post_draw
 verify(root.get_texture().get_image().save_png(
  frames.path_join("%04d.png" % frame_number)) == OK, "Frame saved")
 frame_number += 1

func hold(seconds: float) -> void:
 var elapsed := 0.0
 while elapsed < seconds:
  await record()
  elapsed += root.get_process_delta_time()

func cross_to_district(game: Control, local_point: Vector2) -> void:
 var globe = game.native_view
 var district = game.district
 var fraction := local_point / Roads.AREA
 for step in range(16):
  var projection: Rect2 = globe.earth_district_projection()
  var pointer: Vector2 = projection.position + projection.size * fraction
  if not globe.get_rect().has_point(pointer + globe.position):
   pointer = projection.get_center()
   fraction = Vector2(0.5, 0.5)
  wheel(globe, pointer, true)
  if district.visible:
   verify(is_equal_approx(district._scale, projection.size.x / Roads.AREA.x),
    "The district opens at exactly the size seen on the globe")
   for sample in range(5):
    verify((district._origin + Roads.AREA * fraction * district._scale).distance_to(pointer) < 0.1,
     "Zoom preserves the same local feature under the cursor")
    await hold(0.09)
   while district._scale < 0.65:
    wheel(district, pointer, true)
    await hold(0.25)
    verify((district._origin + Roads.AREA * fraction * district._scale).distance_to(pointer) < 0.15,
     "Every wheel step keeps its port or district point")
   return
  await hold(0.28)
 verify(false, "Wheel enters the district")

func cross_to_globe(game: Control, local_point: Vector2) -> void:
 var district = game.district
 var pointer: Vector2 = district._origin + local_point * district._scale
 var globe = game.native_view
 for step in range(16):
  wheel(district, pointer, false)
  await hold(0.25)
  if not district.visible:
   var projection: Rect2 = globe.earth_district_projection()
   verify((projection.position + projection.size * (local_point / Roads.AREA)).distance_to(pointer) < 1.5,
    "Globe still shows that surface point at the pointer")
   return
  verify((district._origin + local_point * district._scale).distance_to(pointer) < 0.15,
   "The same feature stays anchored on each outward wheel step")
 verify(false, "Returns input to the globe")

func test_roads() -> void:
 for id in ["earth-mine-01", SITE, "earth-south-02", "earth-east-04"]:
  var plot: Rect2 = Roads.PLOTS[id]
  var driveway := Roads.driveway(plot)
  var route := Roads.ore_route(plot)
  verify(route[0] == driveway[0] and route[1] == driveway[1] and route[-1] == Roads.GATE,
   "The vehicle follows the rendered driveway and reaches the warehouse gate: " + id)
  var segments: Array = Roads.streets(Roads.AREA)
  var port := Roads.port_access()
  segments.append([driveway[0], driveway[1]])
  for i in range(1, port.size()):
   segments.append([port[i - 1], port[i]])
  for i in range(1, route.size()):
   for step in range(11):
    var point := route[i - 1].lerp(route[i], step / 10.0)
    verify(segments.any(func(segment): return Geometry2D.get_closest_point_to_segment(
     point, segment[0], segment[1]).distance_to(point) < 0.1), "Route stays on a drawn street: " + id)
  route.reverse()
  verify(Roads.pose(route, 1.0).origin.distance_to(driveway[0]) < 0.01,
   "Unloaded truck returns to its own gate")

func run() -> void:
 test_roads()
 var game = MAIN.instantiate()
 root.add_child(game)
 await process_frame
 var globe = game.native_view
 var district = game.district
 game._set_speed(1)
 globe.focus_body("earth")
 await hold(0.60)
 await cross_to_district(game, Vector2(899, 512))
 await cross_to_globe(game, Vector2(899, 512))
 var blank: Vector2 = globe.earth_district_projection().get_center() + Vector2(100, 60)
 for step in range(4):
  wheel(globe, blank, true)
  await hold(0.08)
 verify(not district.visible, "Empty ground does not enter or recenter on the colony")
 globe.focus_body("earth")
 await hold(0.52)
 await cross_to_district(game, Vector2(1215, 654))
 await cross_to_globe(game, Vector2(1215, 654))
 game._open_district()
 game._open_build()
 game.browser.build_controls["mining_rig"].button.pressed.emit()
 var plot: Rect2 = Roads.PLOTS[SITE]
 var pointer: Vector2 = district._origin + plot.get_center() * district._scale
 var hover := InputEventMouseMotion.new()
 hover.position = pointer
 district._gui_input(hover)
 await hold(0.40)
 point_click(district, pointer)
 verify(not game.browser.placement_confirm.disabled and game.colony_stock_panel.is_visible_in_tree(),
  "The new site and warehouse are visible at the same time")
 await hold(0.38)
 game.browser.placement_confirm.pressed.emit()
 var deadline: float = game.construction.sites.back().finish_native
 game._close_browser()
 game._pause()
 game.native_time = deadline
 game._advance_construction()
 game._update_native_map()
 var mine: Dictionary = district._facilities[SITE]
 var cycle: float = mine.next_batch_native
 game.native_time = cycle
 game._advance_construction()
 game._update_native_map()
 point_click(district, pointer)
 var sim = game.construction
 var job: Dictionary = sim.ground_ore[0].duplicate()
 var stock: float = sim.colony_inventory("earth").supply.ore
 var paused_time: float = game.native_time
 await hold(0.18)
 verify(game.native_time == paused_time, "Pause holds production and road progress")
 game._pause()
 await hold(3.5)
 verify(game.speed == 1 and game.native_time > job.pickup and game.native_time < job.due,
  "The truck moves visibly through the gate at ×1")
 game._pause()
 game._save_game()
 await cross_to_globe(game, plot.get_center())
 game._native_body_selected({"id": "luna"})
 game._load_game()
 verify(sim.ground_ore.size() == 1 and sim.ground_ore[0] == job,
  "Reload keeps the road job and the destination")
 var tick: float = game.native_time
 game._set_speed(16)
 verify(game.speed == 16, "Speed ×16 selected")
 for step in range(110):
  if game.native_time >= job.due:
   break
  game._step()
 verify(game.native_time > tick and is_equal_approx(sim.colony_inventory("earth").supply.ore,
  stock + job.amount), "Offscreen delivery arrived once")
 game._step()
 verify(is_equal_approx(sim.colony_inventory("earth").supply.ore, stock + job.amount),
  "Next tick does not deliver again")
 game._open_district()
 verify(district._facilities[SITE].id == job.mine, "The mine remains on its confirmed site")
 var legacy: Dictionary = sim.snapshot()
 legacy.version = 7
 legacy.erase("stock_history")
 legacy.erase("ground_ore")
 verify(sim.restore(legacy), "Opens the previous save schema with an existing district")
 print("SOL_EARTH_SURFACE_JOURNEY_PASS")
 quit()
