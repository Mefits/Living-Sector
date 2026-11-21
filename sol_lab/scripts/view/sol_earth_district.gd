extends Control
## Earth district presentation. Named site IDs remain the construction authority.
signal return_requested
signal zoom_out_requested(pointer: Vector2, fraction: Vector2)
signal projection_changed(projection: Rect2)
signal facility_selected(id: String)
signal site_selected(id: String)
signal selection_invalid(reason: String)
signal placement_cancelled

const Sites = preload("res://scripts/view/sol_surface_sites.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Art = preload("res://scripts/view/sol_earth_district_art.gd")
const SHIP_PATH = "res://assets/district/freighter.png"
const PORT_PATHS = ["res://earth_port/EarthPort.tscn",
 "res://sol_lab/earth_port/EarthPort.tscn"]
const AREA = Roads.AREA
const CLOSE_SCALE := 2.23
const EARTH = "earth"
const Roads = preload("res://scripts/view/sol_district_roads.gd")
const PLOTS = Roads.PLOTS
var _plots: Dictionary = {}
var _facilities: Dictionary = {}
var _kind := ""
var _chosen := ""
var _hover := ""
var _selected := ""
var _scale := 1.0
var _origin := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _world_size := AREA
var _port: Node2D
var _runtime: RefCounted
var _ship: Texture2D
var _layer := Node2D.new()
var _hint: Label
var _traffic := Node2D.new()
var _terrain := Node2D.new()
var _chrome: Array[Control] = []
var _wheel_tween: Tween
var _minimum_scale := 0.08
var _zoom_target := 1.0
var _drawn_plots: Dictionary = {}

func _ready() -> void:
 clip_contents = true
 _ship = load(SHIP_PATH) as Texture2D if ResourceLoader.exists(SHIP_PATH) else null
 if _ship == null:
  var image := Image.load_from_file(SHIP_PATH)
  if image != null and not image.is_empty():
   _ship = ImageTexture.create_from_image(image)
 add_child(_layer)
 _layer.add_child(_terrain)
 _terrain.draw.connect(_draw_district)
 var back := Button.new()
 back.text = "‹  Земля"
 back.position = Vector2(18, 14)
 back.pressed.connect(func(): return_requested.emit())
 add_child(back)
 var title := Label.new()
 title.text = "ЗЕМЛЯ  /  ПОСЕЛЕНИЕ"
 title.position = Vector2(118, 17)
 title.add_theme_font_size_override("font_size", 17)
 add_child(title)
 _hint = Label.new()
 _hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 _hint.offset_top = -35
 _hint.offset_left = 16
 _hint.add_theme_font_size_override("font_size", 15)
 add_child(_hint)
 _hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
 resized.connect(_redraw_layout)
 _chrome.assign([back, title, _hint])
 _set_hint()

func show_district(pointer := Vector2(-1, -1), projection := Rect2()) -> void:
 cancel_camera()
 _minimum_scale = projection.size.x / _world_size.x if projection.has_area() else 0.08
 _zoom = 1.0
 _pan = Vector2.ZERO
 if pointer.x >= 0 and projection.has_area():
  _zoom = _minimum_scale / _overview_scale()
  _pan = projection.position - _centered_origin(_minimum_scale)
 show()
 _zoom_target = _zoom
 _redraw_layout()
 if pointer.x >= 0 and projection.has_area():
  _zoom_at(pointer, true)

func camera_extent() -> Vector2:
 return _world_size

func cancel_camera() -> void:
 if _wheel_tween != null:
  _wheel_tween.kill()
  _wheel_tween = null

func _centered_origin(scale: float) -> Vector2:
 return (size - _world_size * scale) * 0.5 + Vector2(0, 6)

func _zoom_at(pointer: Vector2, inward: bool) -> void:
 var anchor := (pointer - _origin) / _scale
 var minimum := _minimum_scale / _overview_scale()
 if not inward and is_equal_approx(_zoom, minimum) and not is_placing():
  zoom_out_requested.emit(pointer, anchor / _world_size)
  return
 var previous := _zoom_target
 cancel_camera()
 _zoom_target = clampf(previous * (1.37 if inward else 1.0 / 1.37),
  minimum, CLOSE_SCALE / _overview_scale())
 _wheel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
 _wheel_tween.tween_method(func(value: float):
  _zoom = value
  var next_scale := _overview_scale() * value
  _pan = pointer - anchor * next_scale - _centered_origin(next_scale)
  _redraw_layout(), _zoom, _zoom_target, 0.23)

func _overview_scale() -> float:
 var available := size - Vector2(10, 78)
 return maxf(0.01, minf(available.x / _world_size.x, available.y / _world_size.y))

func bind_runtime(construction: RefCounted) -> void:
 _runtime = construction
 for path in PORT_PATHS:
  if not ResourceLoader.exists(path):
   continue
  var scene := load(path) as PackedScene
  if scene == null:
   continue
  var candidate := scene.instantiate()
  if not candidate is Node2D or not candidate.has_method("bind_runtime"):
   candidate.free()
   continue
  _port = candidate
  _port.position = Art.pad_anchor(PLOTS["earth-port-01"])
  _port.hide()
  _layer.add_child(_port)
  _port.call("bind_runtime", _runtime, EARTH)
  break
 _layer.add_child(_traffic)
 _traffic.draw.connect(_draw_ground_freight)

var _traffic_time := 0.0

func set_traffic_time(value: float) -> void:
 if value != _traffic_time:
  _traffic_time = value
  _traffic.queue_redraw()

func _draw_ground_freight() -> void:
 for site in _facilities:
  var mine: Dictionary = _facilities[site]
  if mine.has("refinery_return_end") and _traffic_time < float(mine.refinery_return_end) and _scale >= 0.58:
   var road := Roads.ore_route(_plots[site])
   var arrival := float(mine.refinery_return_start)
   var duration := float(mine.refinery_return_end) - arrival
   var loaded := _traffic_time < arrival
   var start_time := arrival
   if loaded:
    road.reverse()
    start_time -= duration
   Art.ground_cargo(_traffic, Roads.pose(road, (_traffic_time - start_time) / duration), true, _zoom, loaded)
  if mine.get("type") != "mining_rig" or not mine.has("truck_home"):
   continue
  var start := float(mine.truck_unloaded)
  var finish := float(mine.truck_home)
  if _traffic_time >= start and _traffic_time < finish and _scale >= 0.58:
   var route := Roads.ore_route(_plots[site])
   route.reverse()
   var progress := inverse_lerp(start, finish, _traffic_time)
   Art.ground_cargo(_traffic, Roads.pose(route, progress), true, _zoom, false)
 for job in _runtime.ground_ore:
  var plot := Roads.mine_plot(_facilities.values(), job.mine)
  var route := Roads.ore_route(plot)
  var moving: bool = _traffic_time >= job.pickup
  var pose := Roads.pose(route, inverse_lerp(job.pickup, job.due, _traffic_time))
  if moving and _scale < 0.58:
   continue
  Art.ground_cargo(_traffic, pose, moving, _zoom)

func _select_cargo(point: Vector2) -> bool:
 if _port != null and _port.visible and _port.has_method("cargo_at"):
  var cargo: Dictionary = _port.cargo_at(point - _port.position)
  if not cargo.is_empty():
   _set_hint("%s %s → %s" % [Model.batch_amount(cargo.amount),
    Model.batch_unit(cargo.resource), "Луна" if cargo.get("destination") == "luna" else "Земной склад"])
   return true
 for job in _runtime.ground_ore:
  var route := Roads.ore_route(Roads.mine_plot(_facilities.values(), job.mine))
  var pose := Roads.pose(route, inverse_lerp(job.pickup, job.due, _traffic_time))
  if pose.origin.distance_to(point) <= 13:
   _set_hint("%s %s → Земной склад · %s" % [
    Model.batch_amount(job.amount), Model.batch_unit(job.resource),
    "в пути" if _traffic_time >= job.pickup else "ждёт машину"])
   return true
 return false

func update_colony(facilities: Array) -> void:
 _plots = PLOTS.duplicate()
 _facilities.clear()
 var overflow := 0
 for facility in facilities:
  if facility.get("body", "") != EARTH:
   continue
  var kind: String = Sites.facility_kind(facility)
  if kind not in Art.GROUND:
   continue
  var site: String = str(facility.get("surface_site_id", ""))
  if not _plots.has(site) or _facilities.has(site):
   # Preserve legacy objects beyond the named-site catalogue.
   site = str(facility["id"])
   _plots[site] = Roads.overflow_plot(overflow)
   overflow += 1
  _facilities[site] = facility
 var extent := AREA + Vector2(0, ceili(float(overflow) / 6.0) * 112)
 if extent != _world_size:
  _world_size = extent
  _redraw_layout()
 if _port != null:
  var facility: Dictionary = _facilities.get("earth-port-01", {})
  _port.visible = facility.get("type", "") == "spaceport"
 var plots: Dictionary = {}
 for site in _facilities:
  var facility: Dictionary = _facilities[site]
  plots[site] = [facility.get("id"), facility.get("type"), Sites.facility_kind(facility)]
 if plots != _drawn_plots:
  _drawn_plots = plots
  _terrain.queue_redraw()

func start_placement(kind: String) -> void:
 _kind = kind
 _chosen = ""
 _hover = ""
 _set_hint()
 _terrain.queue_redraw()

func plot_name(site: String) -> String:
 if site == "earth-port-01":
  return "Портовый участок"
 var plot: Rect2 = PLOTS.get(site, Rect2())
 var zone := "Производственный двор"
 if plot.position.x >= 941:
  zone = "Восточный квартал"
 elif plot.position.y >= 799:
  zone = "Южный квартал"
 elif plot.position.y >= 400:
  zone = "Расширение" if plot.position.y >= 661 else "Южные поля"
 elif plot.position.x < 350:
  zone = "Горный участок"
 return "%s · %s" % [zone, site.get_slice("-", 2)]

func is_placing() -> bool:
 return not _kind.is_empty()

func stop_placement() -> void:
 start_placement("")

func select_facility(id: String) -> void:
 _selected = id
 _terrain.queue_redraw()

func _set_hint(reason := "") -> void:
 if _hint == null:
  return
 _hint.text = reason if not reason.is_empty() else (
  "Выберите участок · ЛКМ   /   Отмена · ПКМ" if not _kind.is_empty() else
  "Осмотр · ЛКМ   /   Масштаб · колесо   /   Перемещение · СКМ")

func _plot_at(point: Vector2) -> String:
 for key in _plots:
  if (_plots[key] as Rect2).has_point(point):
   return key
 return ""

func placement_reason(site: String) -> String:
 if _facilities.has(site):
  var kind := Sites.facility_kind(_facilities[site])
  return "Участок занят · %s" % Model.find_building(kind).get("name", kind)
 if site.is_empty() or _kind not in Sites.get_site(EARTH, site).get("types", []):
  return "Непригодная поверхность для этой постройки"
 return ""

func _gui_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion:
  if _drag:
   _pan += event.relative
  elif not _kind.is_empty():
   _hover = _plot_at((event.position - _origin) / _scale)
   _set_hint(placement_reason(_hover))
  if _drag or is_placing():
   _terrain.queue_redraw()
   _redraw_layout()
 if not event is InputEventMouseButton:
  return
 if event.button_index == MOUSE_BUTTON_MIDDLE:
  _drag = event.pressed
 elif event.pressed:
  match event.button_index:
   MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
    _zoom_at(event.position, event.button_index == MOUSE_BUTTON_WHEEL_UP)
    accept_event()
    return
   MOUSE_BUTTON_RIGHT:
    if _kind.is_empty():
     return_requested.emit()
    else:
     placement_cancelled.emit()
   MOUSE_BUTTON_LEFT:
    var site := _plot_at((event.position - _origin) / _scale)
    if not _kind.is_empty():
     var reason := placement_reason(site)
     _chosen = site if reason.is_empty() else ""
     _set_hint(reason)
     if reason.is_empty():
      site_selected.emit(site)
     else:
      selection_invalid.emit(reason)
    elif not _select_cargo((event.position - _origin) / _scale) and (
      _facilities.has(site) and _facilities[site].get("type") != "construction_site"):
     facility_selected.emit(str(_facilities[site]["id"]))
  _terrain.queue_redraw()
  _redraw_layout()
 accept_event()

func _redraw_layout() -> void:
 _scale = _overview_scale() * _zoom
 _origin = _centered_origin(_scale) + _pan
 _apply_projection()

func _apply_projection() -> void:
 _layer.position = _origin
 _layer.scale = Vector2.ONE * _scale
 _traffic.queue_redraw()
 projection_changed.emit(Rect2(_origin, _world_size * _scale))
 var detail := smoothstep(0.12, 0.28, _scale)
 for item in _chrome:
  item.modulate.a = detail

func plan_pins() -> Array:
 var pins: Array = []
 for site in _facilities:
  var plot: Rect2 = _plots[site]
  if _facilities[site].get("type") != "construction_site":
   pins.append({"id": _facilities[site].id, "position": plot.get_center(),
    "radius": minf(plot.size.x, plot.size.y) * 0.45})
 return pins

func _draw_district() -> void:
 paint_plan(_terrain, true)

func paint_plan(canvas: CanvasItem, local: bool) -> void:
 Art.terrain(canvas, _world_size, local)
 for site in _plots:
  var plot: Rect2 = _plots[site]
  var facility: Dictionary = _facilities.get(site, {})
  if not facility.is_empty() and plot != Roads.PORT:
   canvas.draw_polyline(Roads.driveway(plot), Color("#777a67"), 8.0, true)
  if facility.is_empty():
   if local and is_placing():
    Art.empty_plot(canvas, plot, site)
  else:
   var kind := Sites.facility_kind(facility)
   var pending: bool = facility.get("type") == "construction_site"
   if pending:
    Art.construction(canvas, plot, kind)
   elif site == "earth-port-01" and _port != null and _port.visible:
    if not local:
     var yard := _port.get_node_or_null("Yard") as Sprite2D
     if yard != null and yard.texture != null:
      canvas.draw_texture_rect(yard.texture, plot, false)
   else:
    var docked_ship: Texture2D
    if kind == "spaceport" and (_runtime.freight_status().get("location") == EARTH or
      _runtime.freight_status(2).get("location") == EARTH):
     docked_ship = _ship
    Art.building(canvas, plot, kind, docked_ship)
   if plot != Roads.PORT:
    Art.gate(canvas, Roads.driveway(plot), Color("#c6a873"))
   if local and not pending and str(facility.get("id", "")) == _selected:
    canvas.draw_rect(plot.grow(3), Color("#b6d8df"), false, 2)
  if local and not _kind.is_empty():
   var valid := placement_reason(site).is_empty()
   if valid or site == _hover:
    var color := Color("#b7d99b") if valid else Color("#e88b75")
    canvas.draw_rect(plot.grow(2), color, false, 2.5 if site == _chosen else 1.3)
   if valid and (site == _hover or site == _chosen):
    Art.preview(canvas, plot, _kind, null)
    canvas.draw_polyline(Roads.driveway(plot), Color("#b7d99b"), 6.0, true)
    Art.gate(canvas, Roads.driveway(plot), Color("#b7d99b"))

