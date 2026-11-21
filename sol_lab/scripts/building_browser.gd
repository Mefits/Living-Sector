extends ColorRect
## Docked Sol Lab catalog. Never covers the system map. Owns no simulation.
signal apply_requested
signal reset_requested
signal values_changed
signal close_requested
signal build_requested(body_id: String, building_id: String)
signal placement_confirmed(body_id: String, building_id: String, site_id: String)
signal placement_cancelled
signal cancel_requested(site_id: String)
signal stock_requested
signal save_game_requested
signal load_game_requested
signal new_game_requested

const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Economy = preload("res://scripts/sol_construction_runtime.gd")
const Glyph = preload("res://scripts/view/colony_building_glyph.gd")
const Icons = preload("res://scripts/view/sol_icon_atlas.gd")
var dock_layout: VBoxContainer

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
## Keep nine catalog cards alive while inventory and build availability change.
var build_controls: Dictionary = {}
var output_labels: Dictionary = {}
var time_labels: Dictionary = {}
var scroll: ScrollContainer
var colony_line: Label
var build_detail: Label
var placement_panel: VBoxContainer
var placement_caption: Label
var placement_building_id: String = ""
var placement_chosen_id: String = ""
var placement_options: Array = []

func _ready() -> void:
 color = Color("#101e2d")
 mouse_filter = Control.MOUSE_FILTER_STOP
 var margins := MarginContainer.new()
 add_child(margins)
 margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
  margins.add_theme_constant_override(key, 12)
 var layout := VBoxContainer.new()
 dock_layout = layout
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
 _button(navigation, "Колония", func(): close_requested.emit())
 _button(navigation, "Строительство", _navigate.bind("build"))
 _button(navigation, "Склад", func(): stock_requested.emit())
 var stock_bar := HBoxContainer.new()
 stock_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 stock_bar.add_theme_constant_override("separation", 5)
 layout.add_child(stock_bar)
 var stock_icon: TextureRect = Icons.make_icon("metals", false, 20)
 if stock_icon != null:
  stock_bar.add_child(stock_icon)
 colony_line = _label(stock_bar, "", 14, Color("#e1d1a4"))
 colony_line.custom_minimum_size = Vector2(190, 24)
 colony_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
 colony_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 colony_line.autowrap_mode = TextServer.AUTOWRAP_OFF
 colony_line.clip_text = true
 colony_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

 tabs = HBoxContainer.new()
 tabs.add_theme_constant_override("separation", 4)
 layout.add_child(tabs)

 scroll = ScrollContainer.new()
 # This dock does not have a horizontal-scrolling catalog: fill its width.
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
 var residents: int = 0
 for value in world.get("populations", []):
  if str(value.get("facility_id", "")) == body_id + "-colony":
   residents += int(value.get("population_count", 0))
 var warehouse_present: bool = Model.colony(world, body_id)
 set_colony_summary(str(Model.PLANET_NAMES.get(body_id, body_id)),
  residents, {"present": warehouse_present,
   "supply": {"metals": Model.stock(world, body_id)}})
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
  refresh_build_availability()
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

func set_colony_summary(name_ru: String, residents: int,
        inventory: Dictionary) -> void:
 var supply: Dictionary = inventory.get("supply", {})
 var state: String = ("%s · %d жителей · металл %s" % [
  name_ru, residents,
  Model.batch_amount(float(supply.get("metals", 0)))]) if bool(
  inventory.get("present", false)) else name_ru + " · нет колонии"
 if colony_line != null:
  colony_line.text = state
  colony_line.tooltip_text = state

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
 if not placement_building_id.is_empty():
  placement_cancelled.emit()
 page = target
 _clear(tabs)
 _clear(cards_root)
 _clear(footer)
 card_nodes.clear()
 build_controls.clear()
 output_labels.clear()
 time_labels.clear()
 queue_panel = null
 queue_rows.clear()
 queue_membership.clear()
 queue_mounted = false
 build_detail = null
 grid = null
 placement_panel = null
 placement_caption = null
 placement_building_id = ""
 placement_chosen_id = ""
 placement_options.clear()
 scroll.scroll_vertical = 0
 feedback.text = ""
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
 if not editable:
  queue_panel = VBoxContainer.new()
  cards_root.add_child(queue_panel)
  _refresh_queue()
  placement_panel = VBoxContainer.new()
  placement_panel.add_theme_constant_override("separation", 5)
  cards_root.add_child(placement_panel)
  placement_caption = _label(placement_panel, "", 13, Color("#e2d5ae"))
  placement_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  var actions := HBoxContainer.new()
  placement_panel.add_child(actions)
  _button(actions, "Отмена · бесплатно", func(): placement_cancelled.emit())
  placement_panel.hide()

 grid = GridContainer.new()
 grid.columns = 3 if editable else 1
 grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 grid.add_theme_constant_override("h_separation", 7)
 grid.add_theme_constant_override("v_separation", 5)
 cards_root.add_child(grid)
 var buildings: Dictionary = config.get("buildings", {})
 for building in Model.BUILDINGS:
  var id: String = str(building["id"])
  var row: Dictionary = buildings.get(id, {})
  var available: bool = Model.available(building, buildings, world, body_id)
  var existing: bool = Model.built_or_pending(world, body_id, id)
  var card := PanelContainer.new()
  var style := StyleBoxFlat.new()
  style.bg_color = Color("#1a3040") if available or editable else Color("#111c29")
  style.border_color = Color("#3d6374") if available or editable else Color("#27394b")
  style.set_border_width_all(1)
  style.set_content_margin_all(6)
  card.add_theme_stylebox_override("panel", style)
  grid.add_child(card)
  card_nodes.append(card)
  if editable:
   var stack := VBoxContainer.new()
   stack.add_theme_constant_override("separation", 5)
   card.add_child(stack)
   var name_label: Label = _label(stack, str(building["name"]), 16)
   _spin(stack, "Металлы", float(row.get("metals", 0)),
    _edit_building.bind(id, "metals"), 1, 100000, "metals")
   _spin(stack, "Дней", float(row.get("days", 45)),
    _edit_building.bind(id, "days"), 1, 100000)
   for resource in building.get("inputs", {}).keys():
    var key: String = "input_" + str(resource)
    _spin(stack, "Расход " + Model.resource_label(str(resource)),
     float(row.get(key, 0)), _edit_building.bind(id, key), 1, 100000,
     str(resource))
   if str(building["product"]) != "none":
    _spin(stack, "Базовый выпуск", float(row.get("base", 0)),
     _edit_building.bind(id, "base"), 1, 100000)
   output_labels[id] = _label(stack, _production(building), 15)
   time_labels[id] = _label(stack, _construction_time(building), 13)
  else:
   card.visible = not existing
   var stack := VBoxContainer.new()
   stack.add_theme_constant_override("separation", 3)
   card.add_child(stack)
   var top := HBoxContainer.new()
   top.add_theme_constant_override("separation", 5)
   stack.add_child(top)
   var symbol := Glyph.new()
   symbol.kind = id
   symbol.custom_minimum_size = Vector2(30, 30)
   top.add_child(symbol)
   var label: Label = _label(top, str(building["name"]), 14,
    Color("#e7f0f4") if available else Color("#8da3b2"))
   label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   label.custom_minimum_size.y = 32
   var action := _button(top, "Выбрать место" if available else "Нет места / металла",
    _request_build.bind(id))
   action.custom_minimum_size = Vector2(111, 32)
   action.add_theme_font_size_override("font_size", 12)
   action.disabled = not available
   var purpose: Label = _label(stack, _purpose(id), 12,
    Color("#abc7d3"))
   purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   var meta := HBoxContainer.new()
   meta.add_theme_constant_override("separation", 4)
   stack.add_child(meta)
   var metal_icon: TextureRect = Icons.make_icon("metals", false, 20)
   if metal_icon != null:
    meta.add_child(metal_icon)
   _label(meta, "Цена: %d металл · %d дн." % [
    int(row.get("metals", 1)),
    Model.construction_days(building, buildings)], 13,
    Color("#d5bb8c"))
   var expand := _button(meta, "Подробнее", _toggle_build_details.bind(id))
   expand.custom_minimum_size = Vector2(104, 28)
   expand.add_theme_font_size_override("font_size", 11)
   var local_details: Label = _label(stack, "", 12, Color("#afc8d4"))
   local_details.hide()
   build_controls[id] = {
    "card": card, "title": label, "button": action,
    "details": local_details, "available": available, "hidden": existing
   }
 _fit_cards()

static func _purpose(id: String) -> String:
 match id:
  "administrative_center": return "Управляет колонией и складом"
  "mining_rig": return "Добывает руду"
  "farm": return "Выращивает продовольствие"
  "power_plant": return "Производство энергии (заготовка)"
  "refinery": return "Перерабатывает руду в металл"
  "factory": return "Изготавливает компоненты"
  "spaceport": return "Принимает и отправляет грузовые корабли"
  "orbital_platform": return "Обеспечивает орбитальную инфраструктуру"
  "shipyard": return "Строительство кораблей (заготовка)"
 return "Здание колонии"


func _toggle_build_details(building_id: String) -> void:
 var controls: Dictionary = build_controls.get(building_id, {})
 if controls.is_empty():
  return
 var local_details: Label = controls["details"]
 if local_details.visible:
  local_details.hide()
  return
 var item: Dictionary = Model.find_building(building_id)
 var inputs: Array[String] = []
 for resource in item.get("inputs", {}).keys():
  var amount: int = int(config["buildings"][building_id].get(
   "input_" + str(resource), item["inputs"][resource]))
  inputs.append("%d %s" % [amount, Model.batch_unit(str(resource))])
 var output: String = _production(item) if str(item.get(
  "product", "")) != "none" else "Сервисное здание"
 local_details.text = "%s\nРасход: %s" % [
  output, ", ".join(inputs) if not inputs.is_empty() else "нет"]
 local_details.show()


func refresh_build_availability() -> void:
 if not visible or page != "build":
  return
 var buildings: Dictionary = config.get("buildings", {})
 for building in Model.BUILDINGS:
  var id: String = str(building["id"])
  var controls: Dictionary = build_controls.get(id, {})
  if controls.is_empty():
   continue
  var existing: bool = Model.built_or_pending(world, body_id, id)
  var card: PanelContainer = controls["card"]
  card.visible = not existing
  var available: bool = Model.available(building, buildings, world, body_id)
  if available == bool(controls["available"]):
   continue
  controls["available"] = available
  var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
  style.bg_color = Color("#1a3040") if available else Color("#111c29")
  style.border_color = Color("#3d6374") if available else Color("#27394b")
  (controls["title"] as Label).add_theme_color_override("font_color",
   Color("#e7f0f4") if available else Color("#8da3b2"))
  var action: Button = controls["button"]
  action.text = "Выбрать место" if available else "Нет места / металла"
  action.disabled = not available
  build_controls[id] = controls

func _fit_cards() -> void:
 if grid == null or not is_instance_valid(grid):
  return
 if page != "admin_buildings":
  grid.columns = 1
  # ScrollContainer does not necessarily stretch nested VBox/Grid children.
  # Without explicit min widths it shrunk the entire building row to 150px,
  # wrapping full names one CHARACTER per line at 1366 and at 1920.
  var row_width: float = maxf(260.0, dock_width - 44.0)
  cards_root.custom_minimum_size.x = row_width
  grid.custom_minimum_size.x = row_width
  for card in card_nodes:
   if is_instance_valid(card):
    card.custom_minimum_size = Vector2(row_width, 0.0)
  return
 var columns: int = 3 if dock_width >= 690.0 else (
  2 if dock_width >= 475.0 else 1)
 grid.columns = columns
 var cell_width: float = floorf((dock_width - 32.0 -
  float(columns - 1) * 8.0) / float(columns))
 for card in card_nodes:
  if is_instance_valid(card):
   card.custom_minimum_size = Vector2(maxf(145.0, cell_width), 385.0)

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

func start_placement(building_id: String, candidates: Array, local := false) -> void:
 placement_building_id = building_id
 placement_chosen_id = ""
 placement_options = candidates.duplicate(true)
 if placement_panel == null:
  return
 placement_caption.text = _placement_summary() + "\nСвободно: %d\n" % candidates.size() + (
  "Клик по участку начинает стройку." if local else
  "Клик по подсвеченной площадке начинает стройку.")
 placement_panel.show()
 scroll.scroll_vertical = 0


func select_placement(site_id: String) -> void:
 if placement_panel == null or not placement_panel.visible:
  return
 for candidate in placement_options:
  if str(candidate.get("id", "")) != site_id:
   continue
  placement_chosen_id = site_id
  placement_confirmed.emit(body_id, placement_building_id, site_id)
  return


func _placement_summary() -> String:
 var buildings: Dictionary = config.get("buildings", {})
 var item := Model.find_building(placement_building_id)
 var row: Dictionary = buildings.get(placement_building_id, {})
 return "%s · %d металла · %d дн.\n%s" % [
  item.get("name", placement_building_id), int(row.get("metals", 1)),
  Model.construction_days(item, buildings), _purpose(placement_building_id)]

func reject_placement(reason: String) -> void:
 placement_chosen_id = ""
 if placement_panel != null and placement_panel.visible:
  placement_caption.text = _placement_summary() + "\n" + reason


func clear_placement() -> void:
 placement_building_id = ""
 placement_chosen_id = ""
 placement_options.clear()
 if placement_panel != null:
  placement_panel.hide()


func _request_build(building_id: String) -> void:
 build_requested.emit(body_id, building_id)

func _request_cancel(site_id: String) -> void:
 cancel_requested.emit(site_id)


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
    var cancel := _button(panel, "Отменить", _request_cancel.bind(site_id))
    cancel.custom_minimum_size = Vector2(0, 28)
    queue_rows[site_id] = {"line": line, "bar": bar, "cancel": cancel}
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
        step_value: float, maximum: float, resource_id: String = "") -> void:
 var row := HBoxContainer.new()
 row.add_theme_constant_override("separation", 4)
 parent.add_child(row)
 if not resource_id.is_empty():
  var resource_icon: TextureRect = Icons.make_icon(resource_id, false, 20)
  if resource_icon != null:
   row.add_child(resource_icon)
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
   float(values[key]), _edit_planet.bind(str(key)), 0.05, 10,
   str(key))

func _edit_planet(value: float, key: String) -> void:
 var values: Dictionary = config["planets"][body_id]
 values[key] = snappedf(value, 0.01)
 config["planets"][body_id] = values
 values_changed.emit()
 feedback.text = "Коэффициент обновлён; выработка пересчитается."

func _needs() -> void:
 _label(cards_root, "Еда: %s на 100 жителей за %d дней" % [
  Model.batch_amount(100 * Economy.FOOD_PER_RESIDENT), Economy.CYCLE_DAYS], 16)
 _label(cards_root, "Источник воды на Земле: +%d за %d дней" % [
  Economy.EARTH_WATER_PER_CYCLE, Economy.CYCLE_DAYS], 14)

