extends ColorRect
## Docked Sol Lab catalog. Never covers the system map. Owns no simulation.
signal apply_requested
signal reset_requested
signal values_changed
signal close_requested

const Model = preload("res://scripts/sol_building_model.gd")
var world: Dictionary = {}
var config: Dictionary = {}
var body_id: String = "earth"
var page: String = "build"
var dock_width: float = 780.0
var title: Label
var tabs: HBoxContainer
var cards_root: VBoxContainer
var feedback: Label
var footer: HBoxContainer
var grid: GridContainer
var card_nodes: Array = []
var output_labels: Dictionary = {}
var time_labels: Dictionary = {}
var scroll: ScrollContainer

func _ready() -> void:
 color = Color("#101e2d")
 mouse_filter = Control.MOUSE_FILTER_STOP
 var margins := MarginContainer.new()
 add_child(margins)
 margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
  margins.add_theme_constant_override(key, 12)
 var layout := VBoxContainer.new()
 layout.add_theme_constant_override("separation", 9)
 margins.add_child(layout)

 var top := HBoxContainer.new()
 layout.add_child(top)
 title = _label(top, "", 21, Color("#edd291"))
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _button(top, "Закрыть", func(): close_requested.emit())

 var navigation := HBoxContainer.new()
 navigation.add_theme_constant_override("separation", 6)
 layout.add_child(navigation)
 _button(navigation, "Строительство", _navigate.bind("build"))
 _button(navigation, "Админ-панель", _navigate.bind("admin_buildings"))

 tabs = HBoxContainer.new()
 tabs.add_theme_constant_override("separation", 4)
 layout.add_child(tabs)

 scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 layout.add_child(scroll)
 cards_root = VBoxContainer.new()
 cards_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 cards_root.add_theme_constant_override("separation", 10)
 scroll.add_child(cards_root)

 feedback = _label(layout, "", 14, Color("#a6bdca"))
 footer = HBoxContainer.new()
 footer.add_theme_constant_override("separation", 7)
 layout.add_child(footer)

func configure(source_world: Dictionary, settings: Dictionary,
        selected_id: String, admin: bool) -> void:
 world = source_world
 config = settings
 body_id = selected_id
 _navigate("admin_buildings" if admin else "build")
 show()

func set_dock_width(value: float) -> void:
 dock_width = maxf(260.0, value)
 _fit_cards()

func _button(parent: Node, caption: String, action: Callable) -> Button:
 var b := Button.new()
 b.text = caption
 b.custom_minimum_size = Vector2(88, 38)
 parent.add_child(b)
 b.pressed.connect(action)
 return b

func _label(parent: Node, value: String, font_size: int = 16,
        tone: Color = Color("#dce8ee")) -> Label:
 var l := Label.new()
 l.text = value
 l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 l.add_theme_font_size_override("font_size", font_size)
 l.add_theme_color_override("font_color", tone)
 l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(l)
 return l

func _clear(parent: Node) -> void:
 for child in parent.get_children():
  parent.remove_child(child)
  child.queue_free()

func _navigate(target: String) -> void:
 page = target
 _clear(tabs)
 _clear(cards_root)
 _clear(footer)
 card_nodes.clear()
 output_labels.clear()
 time_labels.clear()
 grid = null
 scroll.scroll_vertical = 0
 feedback.text = "Sol Lab: N39/N154 ещё не подключены. Заказы не создаются."
 var planet_name: String = ("Земля" if body_id == "earth"
  else ("Луна" if body_id == "luna" else "Марс"))
 if page == "build":
  title.text = "СТРОИТЕЛЬСТВО · " + planet_name
  _cards(false)
 elif page == "admin_buildings":
  title.text = "АДМИН · ЗДАНИЯ"
  _button(tabs, "Планета · " + planet_name, _navigate.bind("admin_planet"))
  _button(tabs, "Потребности", _navigate.bind("admin_needs"))
  _cards(true)
 elif page == "admin_planet":
  title.text = "АДМИН · " + planet_name.to_upper()
  _button(tabs, "Здания", _navigate.bind("admin_buildings"))
  _button(tabs, "Потребности", _navigate.bind("admin_needs"))
  _planet()
 elif page == "admin_needs":
  title.text = "АДМИН · ПОТРЕБНОСТИ"
  _button(tabs, "Здания", _navigate.bind("admin_buildings"))
  _button(tabs, "Планета", _navigate.bind("admin_planet"))
  _needs()
 if page.begins_with("admin"):
  _button(footer, "Сохранить + рестарт", func(): apply_requested.emit())
  _button(footer, "Сброс", func(): reset_requested.emit())

func _cards(editable: bool) -> void:
 _label(cards_root, "Базовая выработка (с коэффициентом планеты) · " +
  "время — не меньше нужного числа смен после доставки ресурсов.", 14,
  Color("#a3b9c7"))
 grid = GridContainer.new()
 grid.columns = 3
 grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 grid.add_theme_constant_override("h_separation", 8)
 grid.add_theme_constant_override("v_separation", 8)
 cards_root.add_child(grid)
 var buildings: Dictionary = config.get("buildings", {})
 for building in Model.BUILDINGS:
  var id: String = str(building["id"])
  var row: Dictionary = buildings.get(id, {})
  var available: bool = Model.available(building, buildings, world, body_id)
  var card := PanelContainer.new()
  var style := StyleBoxFlat.new()
  style.bg_color = Color("#1a3040") if available else Color("#111c29")
  style.border_color = Color("#3d6374") if available else Color("#27394b")
  style.set_border_width_all(1)
  style.set_content_margin_all(9)
  card.add_theme_stylebox_override("panel", style)
  grid.add_child(card)
  card_nodes.append(card)
  var stack := VBoxContainer.new()
  stack.add_theme_constant_override("separation", 5)
  card.add_child(stack)
  _label(stack, str(building["name"]), 17,
   Color("#e7f0f4") if available or editable else Color("#8da3b2"))
  if editable:
   _spin(stack, "Металлы", float(row.get("metals", 0)),
    _edit_building.bind(id, "metals"), 1, 100000)
   _spin(stack, "Труд", float(row.get("labor", 0)),
    _edit_building.bind(id, "labor"), 1, 100000)
   for resource in building.get("inputs", {}).keys():
    var key: String = "input_" + str(resource)
    _spin(stack, "Расход " + Model.resource_label(str(resource)),
     float(row.get(key, 0)), _edit_building.bind(id, key), 1, 100000)
   if str(building["product"]) != "none":
    _spin(stack, "Базовый выпуск", float(row.get("base", 0)),
     _edit_building.bind(id, "base"), 1, 100000)
  else:
   _label(stack, ("Стоимость: %d металла · %d труда" % [
    int(row.get("metals", 0)), int(row.get("labor", 0))])
    if bool(building["ported"]) else "Стоимость: не определена", 14)
   var inputs: Array[String] = []
   for resource in building.get("inputs", {}).keys():
    inputs.append("%d %s" % [
     int(row.get("input_" + str(resource), 0)),
     Model.resource_label(str(resource))])
   _label(stack, "Расход: " + (
    " + ".join(inputs) if not inputs.is_empty() else "—"), 13,
    Color("#a4bdcc"))
  output_labels[id] = _label(stack, _production(building), 16,
   Color("#85d79b"))
  time_labels[id] = _label(stack, _construction_time(building), 14,
   Color("#e0c18b"))
  var spacer := Control.new()
  spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
  stack.add_child(spacer)
  if not bool(building["ported"]):
   _label(stack, "Механика ещё не перенесена", 12,
    Color("#889eae"))
  if not editable:
   var action := _button(stack,
    "Заказать" if available else "Недоступно", _not_connected)
   action.disabled = not available
   if not available:
    card.modulate = Color(0.71, 0.74, 0.79, 1.0)
 _fit_cards()

func _fit_cards() -> void:
 if grid == null or not is_instance_valid(grid):
  return
 var columns: int = 3 if dock_width >= 690.0 else (
  2 if dock_width >= 475.0 else 1)
 grid.columns = columns
 var cell_width: float = floorf((dock_width - 32.0 -
  float(columns - 1) * 8.0) / float(columns))
 for card in card_nodes:
  if is_instance_valid(card):
   card.custom_minimum_size = Vector2(maxf(145.0, cell_width),
    420.0 if page == "admin_buildings" else 235.0)

func _production(building: Dictionary) -> String:
 var resource: String = str(building["product"])
 if resource == "none":
  return "Выработка: —"
 var base: float = float(config["buildings"][building["id"]]["base"])
 var derived: float = Model.calculated(
  building, config["buildings"], config["planets"], body_id)
 return "%s: +%s (+%s)" % [
  Model.resource_label(resource), _number(base), _number(derived)]

func _construction_time(building: Dictionary) -> String:
 var minimum: int = Model.minimum_construction_shifts(
  building, config["buildings"])
 if minimum < 0:
  return "Строительство: не определено"
 return "Строительство: от %d смен" % minimum

func _number(value: float) -> String:
 if is_equal_approx(value, roundf(value)):
  return str(int(roundf(value)))
 return "%.2f" % value

func _not_connected() -> void:
 feedback.text = "Заказ не выполнен: N39/N154 не подключены. Ресурсы не списаны."

func _spin(parent: Node, caption: String, value: float, changed: Callable,
        step_value: float, maximum: float) -> void:
 var row := HBoxContainer.new()
 row.add_theme_constant_override("separation", 4)
 parent.add_child(row)
 var name := _label(row, caption, 13)
 name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var field := SpinBox.new()
 field.min_value = 0.0
 field.max_value = maximum
 field.step = step_value
 field.rounded = step_value >= 1.0
 field.custom_minimum_size = Vector2(78, 34)
 field.size_flags_horizontal = Control.SIZE_SHRINK_END
 field.value = value
 row.add_child(field)
 field.value_changed.connect(changed)

func _edit_building(value: float, id: String, key: String) -> void:
 var row: Dictionary = config["buildings"][id]
 row[key] = int(roundf(value))
 config["buildings"][id] = row
 for building in Model.BUILDINGS:
  if str(building["id"]) != id:
   continue
  if output_labels.has(id):
   var output: Label = output_labels[id]
   if is_instance_valid(output):
    output.text = _production(building)
  if time_labels.has(id):
   var timing: Label = time_labels[id]
   if is_instance_valid(timing):
    timing.text = _construction_time(building)
  break
 feedback.text = "Параметры изменены. Сохраните и перезапустите."

func _planet() -> void:
 _label(cards_root, "Коэффициенты этой планеты. " +
  "Значения в скобках пересчитываются автоматически.", 16)
 _label(cards_root, "Дополнительные коэффициенты еды и " +
  "промышленности — пока параметры превью.", 13)
 var values: Dictionary = config["planets"][body_id]
 var keys: Array = values.keys()
 keys.sort()
 for key in keys:
  _spin(cards_root, Model.resource_label(str(key)),
   float(values[key]), _edit_planet.bind(str(key)), 0.05, 10)

func _edit_planet(value: float, key: String) -> void:
 var values: Dictionary = config["planets"][body_id]
 values[key] = snappedf(value, 0.01)
 config["planets"][body_id] = values
 values_changed.emit()
 feedback.text = "Коэффициент обновлён; выработка пересчитается."

func _needs() -> void:
 _label(cards_root, "Потребности жителей Земли " +
  "(только настройки, симуляция ещё не подключена).", 16)
 var needs: Dictionary = config.get("needs", {})
 _spin(cards_root, "Еда", float(needs.get("earth_food", 5)),
  _edit_need.bind("earth_food"), 1, 100000)
 _spin(cards_root, "Вода", float(needs.get("earth_water", 3)),
  _edit_need.bind("earth_water"), 1, 100000)

func _edit_need(value: float, key: String) -> void:
 config["needs"][key] = int(roundf(value))
 feedback.text = "Изменено; сохраните настройки и перезапустите."
