extends ColorRect
## Docked Sol Lab catalog. Never covers the system map. Owns no simulation.
signal apply_requested
signal reset_requested
signal values_changed
signal close_requested
signal build_requested(body_id: String, building_id: String)
signal save_game_requested
signal load_game_requested
signal new_game_requested

const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
var world: Dictionary = {}
var active_sites: Array = []
var now_native: float = 0.0
var queue_panel: VBoxContainer
## Reuse live nodes; only create/destroy them when queue membership changes.
var queue_rows: Dictionary = {}
var queue_membership: Array[String] = []
var queue_mounted: bool = false
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
 var game_controls := HBoxContainer.new()
 layout.add_child(game_controls)
 _button(game_controls, "Новая", func(): new_game_requested.emit())
 _button(game_controls, "Сохр.", func(): save_game_requested.emit())
 _button(game_controls, "Загруз.", func(): load_game_requested.emit())

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

func set_construction_state(source_world: Dictionary,
        pending_sites: Array, current_native: float) -> void:
 world = source_world
 # The construction controller owns the site rows. The dock reads them and
 # never mutates them, so no expensive deep copy is required per refresh.
 active_sites = pending_sites
 now_native = current_native
 if visible and page == "build" and queue_panel != null:
  _refresh_queue()

func show_order_result(result: Dictionary) -> void:
 var message: String = str(result.get("reason", ""))
 if bool(result.get("ok", false)):
  _navigate("build")
  message = "Стройка начата: списано %d металла · %d дней." % [
   int(result.get("spent", 0)), int(result.get("days", 0))]
 feedback.text = message

func select_planet(new_id: String) -> void:
 if new_id == body_id:
  return
 if not Model.VISIBLE.has(new_id):
  return
 body_id = new_id
 _navigate(page)

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
 queue_panel = null
 queue_rows.clear()
 queue_membership.clear()
 queue_mounted = false
 grid = null
 scroll.scroll_vertical = 0
 feedback.text = "Тест строительства: расходы и сроки действуют, производство N39 пока нет."
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
  _button(footer, "Сохранить баланс", func(): apply_requested.emit())
  _button(footer, "Сброс", func(): reset_requested.emit())

func _cards(editable: bool) -> void:
 _label(cards_root, "Тестовый баланс: 1 металл на здание · время в игровых днях." +
  " Производство пока не запускается.", 14, Color("#a3b9c7"))
 if not editable:
  queue_panel = VBoxContainer.new()
  cards_root.add_child(queue_panel)
  _refresh_queue()
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
   _spin(stack, "Дней", float(row.get("days", 45)),
    _edit_building.bind(id, "days"), 1, 100000)
   for resource in building.get("inputs", {}).keys():
    var key: String = "input_" + str(resource)
    _spin(stack, "Расход " + Model.resource_label(str(resource)),
     float(row.get(key, 0)), _edit_building.bind(id, key), 1, 100000)
   if str(building["product"]) != "none":
    _spin(stack, "Базовый выпуск", float(row.get("base", 0)),
     _edit_building.bind(id, "base"), 1, 100000)
  else:
   _label(stack, "Стоимость: %d металл." % int(
    row.get("metals", 1)), 14)
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
   _label(stack, "Производство ещё не подключено", 12,
    Color("#889eae"))
  if not editable:
   var action := _button(stack,
    "Заказать" if available else "Недоступно",
    _request_build.bind(id))
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
    385.0 if page == "admin_buildings" else 235.0)

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
 var days: int = Model.construction_days(building, config["buildings"])
 return "Строительство: %d дней" % days

func _number(value: float) -> String:
 if is_equal_approx(value, roundf(value)):
  return str(int(roundf(value)))
 return "%.2f" % value

func _request_build(building_id: String) -> void:
 build_requested.emit(body_id, building_id)

func _refresh_queue() -> void:
 if queue_panel == null or not is_instance_valid(queue_panel):
  return
 var relevant: Array = []
 var current_ids: Array[String] = []
 for entry in active_sites:
  if not (entry is Dictionary) or str(entry.get("body", "")) != body_id:
   continue
  relevant.append(entry)
  current_ids.append(str(entry.get("id", "")))
 # Original SystemBalance keeps long-lived controls and changes only their
 # values. Creating/queue_free'ing a VBox, Label and ProgressBar every 0.5s
 # caused a speed-independent recurring CPU/allocator spike in Sol Lab.
 if not queue_mounted or current_ids != queue_membership:
  queue_mounted = true
  queue_membership = current_ids
  queue_rows.clear()
  _clear(queue_panel)
  if relevant.is_empty():
   _label(queue_panel, "Очередь строительства пуста", 14,
    Color("#a4bdcc"))
  else:
   for entry in relevant:
    var site_id: String = str(entry.get("id", ""))
    var panel := VBoxContainer.new()
    panel.add_theme_constant_override("separation", 2)
    queue_panel.add_child(panel)
    var line := _label(panel, "", 14, Color("#eed6a1"))
    var bar := ProgressBar.new()
    bar.custom_minimum_size = Vector2(0, 15)
    bar.show_percentage = true
    bar.min_value = 0.0
    bar.max_value = 100.0
    panel.add_child(bar)
    queue_rows[site_id] = {"line": line, "bar": bar}
 # Every 0.5 seconds update just values, not the Godot scene tree.
 for entry in relevant:
  var site_id: String = str(entry.get("id", ""))
  var controls: Dictionary = queue_rows.get(site_id, {})
  if controls.is_empty():
   continue
  var begin: float = float(entry.get("start_native", now_native))
  var finish: float = float(entry.get("finish_native", begin))
  var completion: float = 1.0
  if finish > begin:
   completion = clampf((now_native - begin) / (finish - begin), 0.0, 1.0)
  var left: int = Calendar.days_remaining(now_native, finish)
  var next_text: String = "%s · осталось %d дн." % [
   str(entry.get("name", "Стройплощадка")), left]
  var line: Label = controls["line"]
  var bar: ProgressBar = controls["bar"]
  if line.text != next_text:
   line.text = next_text
  var next_percent: float = completion * 100.0
  if absf(bar.value - next_percent) > 0.05:
   bar.value = next_percent

func _spin(parent: Node, caption: String, value: float, changed: Callable,
        step_value: float, maximum: float) -> void:
 var row := HBoxContainer.new()
 row.add_theme_constant_override("separation", 4)
 parent.add_child(row)
 var name := _label(row, caption, 13)
 name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var field := SpinBox.new()
 field.min_value = 1.0 if caption in ["Металлы", "Дней"] else 0.0
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
