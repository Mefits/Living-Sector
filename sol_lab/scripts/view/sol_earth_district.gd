extends Control
## Earth district presentation. Named site IDs remain the construction authority.
signal return_requested
signal zoom_out_requested(pointer: Vector2, fraction: Vector2)
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
const AREA = Vector2(980, 782)
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

func _ready() -> void:
 clip_contents = true
 _ship = load(SHIP_PATH) as Texture2D if ResourceLoader.exists(SHIP_PATH) else null
 if _ship == null:
  var image := Image.load_from_file(SHIP_PATH)
  if image != null and not image.is_empty():
   _ship = ImageTexture.create_from_image(image)
 add_child(_layer)
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
 _set_hint()

func show_district(pointer := Vector2(-1, -1), fraction := Vector2.ZERO) -> void:
 _zoom = 1.0
 _pan = Vector2.ZERO
 show()
 _redraw_layout()
 if pointer.x >= 0:
  _pan += pointer - (_origin + _world_size * fraction * _scale)
  _redraw_layout()

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

func _draw_ground_freight() -> void:
 for job in _runtime.ground_ore:
  var plot := Roads.mine_plot(_facilities.values(), job.mine)
  var route := Roads.ore_route(plot)
  var moving: bool = _runtime.now_native >= job.pickup
  var pose := Roads.pose(route, inverse_lerp(job.pickup, job.due, _runtime.now_native))
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
  var pose := Roads.pose(route, inverse_lerp(job.pickup, job.due, _runtime.now_native))
  if pose.origin.distance_to(point) <= 13:
   _set_hint("%s %s → Земной склад · %s" % [
    Model.batch_amount(job.amount), Model.batch_unit(job.resource),
    "в пути" if _runtime.now_native >= job.pickup else "ждёт машину"])
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
 _world_size = AREA + Vector2(0, ceili(float(overflow) / 6.0) * 112)
 if _port != null:
  var facility: Dictionary = _facilities.get("earth-port-01", {})
  _port.visible = facility.get("type", "") == "spaceport"
 _redraw_layout()

func start_placement(kind: String) -> void:
 _kind = kind
 _chosen = ""
 _hover = ""
 _set_hint()
 queue_redraw()

func plot_name(site: String) -> String:
 if site == "earth-port-01":
  return "Портовый участок"
 var plot: Rect2 = PLOTS.get(site, Rect2())
 var zone := "Производственный двор"
 if plot.position.y >= 400:
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
 queue_redraw()

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
   _redraw_layout()
 if not event is InputEventMouseButton:
  return
 if event.button_index == MOUSE_BUTTON_MIDDLE:
  _drag = event.pressed
 elif event.pressed:
  match event.button_index:
   MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
    var world_point: Vector2 = (event.position - _origin) / _scale
    if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and is_equal_approx(_zoom, 1.0) and not is_placing():
     zoom_out_requested.emit(event.position, (world_point / _world_size).clamp(Vector2.ZERO, Vector2.ONE))
     accept_event()
     return
    var old_zoom := _zoom
    _zoom = clampf(_zoom * (1.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else
     1.0 / 1.16), 1.0, 2.7)
    var ratio := _zoom / old_zoom
    var center := size * 0.5 + Vector2(0, 6)
    _pan = (event.position - center) * (1.0 - ratio) + _pan * ratio
    _hover = _plot_at(world_point)
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
  _redraw_layout()
 accept_event()

func _redraw_layout() -> void:
 var available := size - Vector2(10, 78)
 _scale = maxf(0.01, minf(available.x / _world_size.x,
  available.y / _world_size.y)) * _zoom
 var limit := (size * 0.48 + _world_size * _scale * 0.25)
 _pan = _pan.clamp(-limit, limit)
 _origin = (size - _world_size * _scale) * 0.5 + _pan + Vector2(0, 6)
 _layer.position = _origin
 _layer.scale = Vector2.ONE * _scale
 _traffic.queue_redraw()
 queue_redraw()

func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO, size), Color("#252f28"))
 draw_set_transform(_origin, 0.0, Vector2.ONE * _scale)
 Art.terrain(self, _world_size)
 for site in _plots:
  var plot: Rect2 = _plots[site]
  var facility: Dictionary = _facilities.get(site, {})
  if not facility.is_empty() and plot != Roads.PORT:
   draw_polyline(Roads.driveway(plot), Color("#777a67"), 8.0, true)
  if facility.is_empty():
   Art.empty_plot(self, plot, site)
  else:
   var kind := Sites.facility_kind(facility)
   var pending: bool = facility.get("type") == "construction_site"
   if pending:
    Art.construction(self, plot, kind)
   elif not (site == "earth-port-01" and _port != null and _port.visible):
    var docked_ship: Texture2D
    if kind == "spaceport" and (_runtime.freight_status().get("location") == EARTH or
      _runtime.freight_status(2).get("location") == EARTH):
     docked_ship = _ship
    Art.building(self, plot, kind, docked_ship)
   if not pending and str(facility.get("id", "")) == _selected:
    draw_rect(plot.grow(3), Color("#b6d8df"), false, 2)
  if not _kind.is_empty():
   var valid := placement_reason(site).is_empty()
   if valid or site == _hover:
    var color := Color("#b7d99b") if valid else Color("#e88b75")
    draw_rect(plot.grow(2), color, false, 2.5 if site == _chosen else 1.3)
   if valid and (site == _hover or site == _chosen):
    Art.preview(self, plot, _kind, null)
    draw_polyline(Roads.driveway(plot), Color("#b7d99b"), 6.0, true)
