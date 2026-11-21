extends Control

const Runtime = preload("res://scripts/sector_runtime.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const ShipArt = preload("res://sol_lab/earth_port/ship_art.gd")
const SAVE := "user://sol_sector_v1.json"
const GOLD := Color("#efb96e")
const BLUE := Color("#97bcca")

var sim = Runtime.new()
var system_id := ""
var colony_id := ""
var ship_id := ""
var halted := false
var panel: VBoxContainer
var summary: Label
var day_label: Label

func _ready() -> void:
 sim.setup(JSON.parse_string(FileAccess.get_file_as_string("res://data/sector_start.json")))
 colony_id = sim.focus
 mouse_filter = MOUSE_FILTER_STOP
 var bar := HBoxContainer.new()
 bar.position = Vector2(22, 16)
 add_child(bar)
 _button(bar, "Sol Lab", func(): hide())
 _button(bar, "К звёздам", func(): system_id = "")
 _button(bar, "Пауза / ход", func(): halted = not halted)
 _button(bar, "Сохранить", _save)
 _button(bar, "Загрузить", _load)
 day_label = Label.new()
 bar.add_child(day_label)
 var dock := PanelContainer.new()
 add_child(dock)
 dock.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
 dock.offset_left = -338
 dock.offset_right = -16
 dock.offset_top = 68
 dock.offset_bottom = -16
 var margin := MarginContainer.new()
 for side in ["top", "left", "right", "bottom"]:
  margin.add_theme_constant_override("margin_" + side, 14)
 dock.add_child(margin)
 panel = VBoxContainer.new()
 panel.add_theme_constant_override("separation", 9)
 margin.add_child(panel)
 _card()

func _button(parent: Node, title: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = title
 parent.add_child(button)
 button.pressed.connect(callback)
 return button

func _label() -> Label:
 var label := Label.new()
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 panel.add_child(label)
 return label

func _card() -> void:
 for item in panel.get_children():
  panel.remove_child(item)
  item.queue_free()
 summary = _label()

func _address(id: String) -> String:
 var planet: Dictionary = sim.planets[id]
 return sim.systems[planet.system].name + " / " + planet.name

func _select_ship(id: String) -> void:
 ship_id = id
 _card()
 _button(panel, "Закрыть карточку", func(): ship_id = ""; _card())

func _process(delta: float) -> void:
 if not halted:
  sim.advance(sim.day + delta)
 day_label.text = "    День %.1f%s" % [sim.day, " · пауза" if halted else ""]
 if not ship_id.is_empty():
  var ship: Dictionary = sim.ships[ship_id]
  summary.text = "%s\n%s" % [ship.name, ship.owner]
  if ship.has("flight"):
   var flight: Dictionary = ship.flight
   if ship.has("reserved"):
    var job: Dictionary = ship.reserved
    summary.text += "\n\nЛетит порожняком за грузом\nЗарезервировано: %s · %s\nДля колонии %s" % [
     Model.resource_label(job.resource), Model.batch_amount(job.amount), _address(job.target)]
   elif flight.amount > 0:
    summary.text += "\n\nВезёт груз: %s · %s" % [
     Model.resource_label(flight.resource), Model.batch_amount(flight.amount)]
   summary.text += "\n\n%s → %s\nПрибытие в день %.1f" % [
    _address(flight.source), _address(flight.target), flight.arrival]
  else:
   summary.text += "\n\nЖдёт назначения у причала\n" + _address(ship.port)
 elif not colony_id.is_empty():
  var colony: Dictionary = sim.planets[colony_id].colony
  var recipe := Model.find_building(colony.industry)
  summary.text = "%s\n%s\n\nСклад\n" % [_address(colony_id), colony.owner]
  for resource in colony.stock:
   summary.text += "%s  %.1f\n" % [Model.resource_label(resource), colony.stock[resource]]
  summary.text += "\n" + recipe.name
  for resource in recipe.get("inputs", {}):
   var needed: float = recipe.inputs[resource] - colony.stock.get(resource, 0)
   if needed > 0:
    summary.text += "\n%s · нужно %s\n%s" % [Model.resource_label(resource),
     Model.batch_amount(needed), sim.input_status(colony_id, resource)]
  if colony.has("last"):
   summary.text += "\nВыпуск %.1f · день %.1f" % [colony.last.amount, colony.last.day]

 else:
  summary.text = "Сектор\nВыберите звезду или корабль."
 queue_redraw()

func _map_size() -> Vector2:
 return Vector2(maxf(300, size.x - 355), size.y)

func _star(id: String) -> Vector2:
 return Vector2(26, 64) + sim.star_position(id) / 100.0 * (_map_size() - Vector2(52, 102))

func _planet(id: String) -> Vector2:
 var index: int = sim.systems[system_id].planets.find(sim.planets[id])
 return Vector2(_map_size().x * (0.48 + index * 0.24), size.y * 0.48 + index * 78)

func _gate() -> Vector2:
 return Vector2(_map_size().x - 58, size.y * 0.23)

func _ship_position(ship: Dictionary) -> Vector2:
 if not ship.has("flight"):
  if sim.planets[ship.port].system != system_id:
   return Vector2.INF
  return _planet(ship.port) + Vector2(28, -22)
 var f: Dictionary = ship.flight
 var a: String = sim.planets[f.source].system
 var b: String = sim.planets[f.target].system
 if system_id.is_empty():
  var cruise := maxf(0.001, f.arrival - f.start - 2 * sim.approach)
  return _star(a).lerp(_star(b), clampf((sim.day - f.start - sim.approach) / cruise, 0, 1))
 if a == b and a == system_id:
  return (_planet(f.source) + Vector2(28,-22)).lerp(_planet(f.target) + Vector2(28,-22),
   clampf((sim.day - f.start) / (f.arrival - f.start), 0, 1))
 if a == system_id and sim.day < f.start + sim.approach:
  return (_planet(f.source) + Vector2(28,-22)).lerp(_gate(), (sim.day - f.start) / sim.approach)
 if b == system_id and sim.day >= f.arrival - sim.approach:
  return _gate().lerp(_planet(f.target) + Vector2(28,-22), 1.0 - (f.arrival - sim.day) / sim.approach)
 return Vector2.INF

func _heading(ship: Dictionary) -> float:
 if not ship.has("flight"):
  return 0.0
 var order: Dictionary = ship.flight
 var origin: String = sim.planets[order.source].system
 var target: String = sim.planets[order.target].system
 if system_id.is_empty():
  return _star(origin).angle_to_point(_star(target))
 if origin == target:
  return _planet(order.source).angle_to_point(_planet(order.target))
 if system_id == origin:
  return (_planet(order.source) + Vector2(28, -22)).angle_to_point(_gate())
 return _gate().angle_to_point(_planet(order.target) + Vector2(28, -22))

func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1521"))
 var font := ThemeDB.fallback_font
 var bounds := _map_size()
 for i in 150:
  var p := Vector2(fmod(i * 141.37, bounds.x), 55 + fmod(i * 67.267, maxf(1, bounds.y - 55)))
  draw_circle(p, 0.8, Color("#354654"))
 if system_id.is_empty():
  draw_string(font, Vector2(26, 80), "СЕКТОР   /   %d СИСТЕМ" % sim.systems.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, BLUE)
  for ship in sim.ships.values():
   if ship.has("flight"):
    var f: Dictionary = ship.flight
    draw_dashed_line(_star(sim.planets[f.source].system), _star(sim.planets[f.target].system), GOLD, 1.5, 7.0)
  for id in sim.systems:
   var point := _star(id)
   var populated: bool = sim.systems[id].planets.any(func(planet): return planet.has("colony"))
   draw_circle(point, 12, Color("#32414d") if populated else Color("#23303b"))
   draw_circle(point, 5, GOLD if populated else BLUE)
   draw_string(font, point + Vector2(17, 5), sim.systems[id].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
 else:
  draw_string(font, Vector2(26, 80), sim.systems[system_id].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, BLUE)
  var star := Vector2(bounds.x * 0.2, size.y * 0.48)
  draw_circle(star, 34, GOLD)
  for planet in sim.systems[system_id].planets:
   var point := _planet(planet.id)
   draw_arc(star, star.distance_to(point), -0.85, 0.8, 48, Color("#2a3d4f"), 1, true)
   draw_circle(point, 23, Color(planet.color))
   draw_string(font, point + Vector2(-23, 52), planet.name)
   if planet.has("colony"):
    draw_rect(Rect2(point + Vector2(22, -28), Vector2(12, 12)), BLUE, false, 2)
  draw_string(font, _gate() + Vector2(-95, -9), "Межзвёздный выход", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BLUE)
 for ship in sim.ships.values():
  var point := _ship_position(ship)
  if not point.is_finite():
   continue
  draw_circle(point, 16, Color("#192c3b"))
  ShipArt.paint(self, point, _heading(ship), 24.0 / ShipArt.EMPTY.get_height(),
   Color.WHITE, false, ship.get("flight", {}).get("amount", 0) > 0)
  if ship.id == ship_id:
   draw_arc(point, 17, 0, TAU, 32, GOLD, 2, true)
  draw_string(font, point + Vector2(18,-12), ship.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)

func _gui_input(event: InputEvent) -> void:
 if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
  return
 var click: Vector2 = event.position
 for ship in sim.ships.values():
  if system_id.is_empty() and sim.systems.keys().any(func(id): return _star(id).distance_to(click) < 8):
   break
  if _ship_position(ship).distance_to(click) < 17:
   _select_ship(ship.id)
   return
 if system_id.is_empty():
  for id in sim.systems:
   if _star(id).distance_to(click) < 20:
    system_id = id
    colony_id = ""
    ship_id = ""
    for planet in sim.systems[id].planets:
     if planet.has("colony"):
      colony_id = planet.id
      break
    _card()
    return
 else:
  for planet in sim.systems[system_id].planets:
   if _planet(planet.id).distance_to(click) < 27 and planet.has("colony"):
    colony_id = planet.id
    ship_id = ""
    _card()
    return

func _save() -> void:
 var file := FileAccess.open(SAVE, FileAccess.WRITE)
 if file != null:
  file.store_string(JSON.stringify({"sim":sim.snapshot(), "system":system_id,
   "colony":colony_id, "ship":ship_id, "paused":halted}))

func _load() -> void:
 if not FileAccess.file_exists(SAVE):
  return
 var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
 if not saved is Dictionary or not saved.has("sim"):
  return
 sim.restore(saved.sim)
 system_id = saved.system
 colony_id = saved.colony
 halted = saved.paused
 ship_id = ""
 if saved.ship.is_empty():
  _card()
 else:
  _select_ship(saved.ship)
