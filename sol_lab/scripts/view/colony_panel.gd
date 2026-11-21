extends PanelContainer
## Fixed-header colony control; stock/list/detail are views of one real world.
signal build_requested
signal ship_requested(slot: int)
signal line_requested
signal facility_requested(facility_id: String)
signal supply_requested(resource: String, amount: float)

const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Glyph = preload("res://scripts/view/colony_building_glyph.gd")
const Stock = preload("res://scripts/view/colony_stock_panel.gd")
const Icons = preload("res://scripts/view/sol_icon_atlas.gd")

var dock_layout: VBoxContainer

var heading: Label
var population: Label
var summary: Label
var food_status: Label
var details: Label
var message: Label
var stock_panel: PanelContainer
var colonize_button: Button
var ship_rows: Array[Button] = []
var line_holder: VBoxContainer
var built_list: VBoxContainer
var detail_title: Label
var detail_description: Label
var detail_icon: Control
var supply_button: Button
var shortage_resource := ""
var shortage_amount := 0.0
var overview: VBoxContainer
var logistics_view: VBoxContainer
var logistics_title: Label
var logistics_status: Label
var scroll: ScrollContainer
var production_data: Dictionary = {}
var displayed_native: float = 0.0
var page: String = "overview"
var selected_facility: String = ""
var body_id: String = ""
var built_facilities: Array = []
var built_buttons: Dictionary = {}

func _ready() -> void:
 var style := StyleBoxFlat.new()
 style.bg_color = Color("#101c29")
 style.set_content_margin_all(12)
 add_theme_stylebox_override("panel", style)
 var layout := VBoxContainer.new()
 dock_layout = layout
 layout.add_theme_constant_override("separation", 7)
 add_child(layout)
 var header := HBoxContainer.new()
 layout.add_child(header)
 heading = _label(header, "Земля", 22, Color("#f0dfae"))
 heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 population = _label(header, "", 14, Color("#b8cad5"))
 population.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 summary = _label(layout, "", 13, Color("#a8c6d4"))
 summary.clip_text = true
 summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 # Long food/ration diagnostics must remain a wrapping full-width Label.
 # A nested HBox here can force a tall minimum panel on 1366x768.
 food_status = _label(layout, "", 13, Color("#bfd0d9"))
 food_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

 var navigation := HBoxContainer.new()
 navigation.add_theme_constant_override("separation", 5)
 layout.add_child(navigation)
 _button(navigation, "Строить", func(): build_requested.emit())
 _button(navigation, "Построено", func(): _switch_page("overview"))
 _button(navigation, "Логистика", func(): line_requested.emit())

 scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 layout.add_child(scroll)
 var content := VBoxContainer.new()
 content.add_theme_constant_override("separation", 8)
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 scroll.add_child(content)
 overview = VBoxContainer.new()
 overview.add_theme_constant_override("separation", 6)
 content.add_child(overview)
 _label(overview, "ПОСТРОЕНО", 14, Color("#d4bc84"))
 # The selected card comes before the potentially long, scrollable list.
 # _switch_page resets scroll to top on selection from list or globe.
 var building_detail_row := HBoxContainer.new()
 building_detail_row.add_theme_constant_override("separation", 6)
 overview.add_child(building_detail_row)
 detail_icon = Glyph.new()
 detail_icon.custom_minimum_size = Vector2(36, 36)
 detail_icon.hide()
 building_detail_row.add_child(detail_icon)
 detail_title = _label(building_detail_row, "", 16, Color("#f0dfae"))
 detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 detail_description = _label(overview, "", 13, Color("#bfd0d9"))
 detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 supply_button = _button(overview, "", func(): supply_requested.emit(shortage_resource, shortage_amount))
 supply_button.hide()
 built_list = VBoxContainer.new()
 built_list.add_theme_constant_override("separation", 3)
 overview.add_child(built_list)
 stock_panel = Stock.new()
 layout.add_child(stock_panel)
 layout.move_child(stock_panel, 1)
 logistics_view = VBoxContainer.new()
 logistics_view.add_theme_constant_override("separation", 10)
 content.add_child(logistics_view)
 logistics_title = _label(logistics_view, "ЛОГИСТИКА", 15,
  Color("#e4d0a0"))
 logistics_status = _label(logistics_view, "", 13,
  Color("#bfd2dc"))
 logistics_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 for slot in [1, 2]:
  var row := _button(logistics_view, "", ship_requested.emit.bind(slot))
  row.alignment = HORIZONTAL_ALIGNMENT_LEFT
  ship_rows.append(row)
 logistics_view.hide()

 message = _label(layout, "", 12, Color("#e5cb92"))
 message.clip_text = true
 message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 colonize_button = _button(layout, "Колонизировать Луну", func(): pass)
 line_holder = VBoxContainer.new()
 line_holder.add_theme_constant_override("separation", 3)
 logistics_view.add_child(line_holder)
 # Keep prior diagnostic text queryable; no large legacy data in layout.
 details = Label.new()
 details.hide()
 add_child(details)

func _label(parent: Node, value: String, font_size: int,
        color: Color) -> Label:
 var result := Label.new()
 result.text = value
 result.add_theme_font_size_override("font_size", font_size)
 result.add_theme_color_override("font_color", color)
 parent.add_child(result)
 return result

func _button(parent: Node, text_value: String, callback: Callable) -> Button:
 var result := Button.new()
 result.text = text_value
 result.custom_minimum_size.y = 32
 result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(result)
 result.pressed.connect(callback)
 return result

func _switch_page(next_page: String) -> void:
 page = next_page
 overview.visible = page == "overview"
 logistics_view.visible = page == "logistics"
 scroll.scroll_vertical = 0

func clear_facility_selection() -> void:
 selected_facility = ""
 _switch_page("overview")
 _show_selected_detail()

func select_overview() -> void:
 _switch_page("overview")

func open_logistics() -> void:
 _switch_page("logistics")

func show_food(food: Dictionary) -> void:
 food_status.visible = not food.is_empty()
 if food.is_empty():
  return
 var text := "Еда: %s · расход %s / 30 дн. · запас ≈ %d дн." % [
  Model.batch_amount(food.stock), Model.batch_amount(food.rate), food.days]
 if not food.covered:
  text += "\nДефицит еды в текущем цикле"
 if food.has("incoming"):
  text += "\nВ пути: +%d еды · %s" % [food.incoming, Calendar.calendar_text(food.arrival)]
 food_status.text = text

func show_colony(next_body: String, name_ru: String,
        residents: int, warehouse: Dictionary, constructed: Array,
        current_sites: Array, idle: String, line_status: String,
        now_native: float, production: Dictionary = {}) -> void:
 if body_id != next_body:
  selected_facility = ""
  _switch_page("overview")
 body_id = next_body
 displayed_native = now_native
 production_data = production
 heading.text = name_ru
 population.text = "%d жителей" % residents if bool(warehouse.get("present", false)) else "Без колонии"
 stock_panel.show_inventory(name_ru, warehouse)
 var site_line: String = "Строек нет"
 for site in current_sites:
  if str(site.get("body", "")) != body_id:
   continue
  var days_left: int = maxi(0, ceili((float(site.get("finish_native", 0.0)) -
   now_native) * 365.0 / 700.0))
  site_line = "%s · %d дн." % [str(site.get("name", "")), days_left]
  break
 summary.text = "%s  ·  %s  ·  %s" % [
  site_line, "Простой: " + idle if not idle.is_empty() else "Без простоев",
  line_status]
 summary.tooltip_text = summary.text
 _set_built(constructed)
 _show_selected_detail()

## One shared colony logistics surface for map-clicked ports and the
## "Линия" quick entry. Buttons below remain the original game commands.
func show_logistics(line: Dictionary, freight: Dictionary,
        waiting_reason: String = "", second: Dictionary = {}) -> void:
 var destination_names: Dictionary = Model.PLANET_NAMES
 var enabled: bool = bool(line.get("enabled", false))
 logistics_title.text = "КОСМОПОРТ · " + str(
  destination_names.get(body_id, body_id)) if _selected_kind() == "spaceport" else (
  "ЛОГИСТИКА · " + str(destination_names.get(body_id, body_id)))
 var sentences: PackedStringArray = PackedStringArray()
 sentences.append("Регулярная линия: " + (
  "включена" if enabled else "отключена"))
 var legs: Dictionary = line.get("legs", {})
 for destination in ["luna", "earth"]:
  var leg: Dictionary = legs.get(destination, {})
  var origin: String = "earth" if destination == "luna" else "luna"
  if leg.get("policy") == "empty":
   sentences.append("%s → %s · пустой рейс" % [destination_names[origin], destination_names[destination]])
   continue
  sentences.append("%s → %s: %d %s · резерв %s" % [
   destination_names.get(origin, origin),
   destination_names.get(destination, destination),
   int(leg.get("amount", 0)),
   Model.resource_label(str(leg.get("resource", ""))),
   Model.batch_amount(float(leg.get("reserve", 0)))])
  if leg.get("policy") == "partial":
   sentences[-1] += " · брать доступное"
 for index in ship_rows.size():
  var ship := freight if index == 0 else second
  var row := ship_rows[index]
  row.visible = not ship.is_empty()
  if ship.is_empty():
   continue
  var assigned := index == 0 and enabled
  var active: bool = ship.location in ["loading", "transit"]
  var status: String = destination_names.get(ship.location, "")
  if active:
   var cargo: Dictionary = ship.order
   var payload := "пустой" if cargo.amount == 0 else "%s %s" % [
    Model.batch_amount(cargo.amount), Model.batch_unit(cargo.resource)]
   status = "%s → %s · %s" % ["Погрузка" if ship.location == "loading" else "В пути",
    destination_names[cargo.destination], payload]
  row.text = "Грузовик %d · %s\n%s" % [index + 1, status,
   "Регулярная линия" if assigned else ("После рейса остановится" if active else "Свободен · назначить рейс")]
  row.disabled = active and not assigned
 if enabled and not waiting_reason.is_empty():
  sentences.append(waiting_reason)
 logistics_status.text = "\n".join(sentences)


func _selected_kind() -> String:
 for facility in built_facilities:
  if str(facility.get("id", "")) == selected_facility:
   return _kind(facility)
 return ""


func _set_built(items: Array) -> void:
 built_facilities = items
 var keys: Array[String] = []
 for item in items:
  keys.append(str(item.get("id", "")) + ":" +
   str(item.get("name", "")) + ":" + str(item.get("type", "")))
 var existing: Array[String] = []
 for item in built_buttons:
  existing.append(str(item))
 var desired: Array[String] = []
 for item in items:
  desired.append(str(item.get("id", "")))
 var totals: Dictionary = {}
 for item in items:
  var kind: String = _kind(item)
  totals[kind] = int(totals.get(kind, 0)) + 1
 var ordinal: Dictionary = {}
 if desired != existing or built_buttons.is_empty():
  for child in built_list.get_children():
   built_list.remove_child(child)
   child.queue_free()
  built_buttons.clear()
  if items.is_empty():
   _label(built_list, "Построек нет", 13, Color("#92aebc"))
  for item in items:
   var facility_id: String = str(item.get("id", ""))
   var kind: String = _kind(item)
   var row := HBoxContainer.new()
   row.add_theme_constant_override("separation", 6)
   built_list.add_child(row)
   var symbol := Glyph.new()
   symbol.kind = kind
   symbol.tint = Color("#c1d6dc")
   row.add_child(symbol)
   ordinal[kind] = int(ordinal.get(kind, 0)) + 1
   var readable: String = str(item.get("name", kind))
   if int(totals.get(kind, 0)) > 1:
    readable += " · №%d" % int(ordinal[kind])
   if kind == "shipyard":
    readable += " · заказ корабля"
   var pick := _button(row, readable, _pick.bind(facility_id))
   pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
   built_buttons[facility_id] = pick
 if not selected_facility.is_empty() and not desired.has(selected_facility):
  selected_facility = ""

func _kind(facility: Dictionary) -> String:
 if str(facility.get("type", "")) == "station" and (
     str(facility.get("location", "")) ==
     str(facility.get("body", "")) + "-colony"):
  return "administrative_center"
 return str(facility.get("type", ""))

func _pick(facility_id: String) -> void:
 select_facility(facility_id)
 facility_requested.emit(facility_id)

func select_facility(facility_id: String) -> void:
 selected_facility = facility_id
 _switch_page("overview")
 _show_selected_detail()

func _show_selected_detail() -> void:
 detail_title.hide()
 detail_description.hide()
 detail_icon.hide()
 supply_button.hide()
 for facility_id in built_buttons:
  var button: Button = built_buttons[facility_id]
  if not is_instance_valid(button):
   continue
  button.add_theme_color_override("font_color",
   Color("#f1d69d") if facility_id == selected_facility else
   Color("#c4d5df"))
 for facility in built_facilities:
  if str(facility.get("id", "")) != selected_facility:
   continue
  var kind: String = _kind(facility)
  var item: Dictionary = Model.find_building(kind)
  var purpose: String = _purpose(kind, item)
  var lines: PackedStringArray = PackedStringArray([purpose])
  if kind in ["mining_rig", "farm", "refinery"]:
   var data: Dictionary = production_data.get(selected_facility, {})
   if data.has("delivery"):
    lines.append(str(data.delivery))
   if bool(data.get("last_present", false)):
    lines.append("Фактическая последняя партия: +%s %s" % [
     Model.batch_amount(float(data.get("last_amount", 0))),
     Model.resource_label(str(data.get("last_resource", "")))])
    lines.append("Выпущено: " + Calendar.calendar_text(
     float(data.get("last_native", 0))))
    var changes: String = str(data.get("last_changes", ""))
    if not changes.is_empty():
     lines.append("Фактическая партия: " + changes)
   else:
    lines.append("Выпуска ещё не было")
   lines.append("Прогноз следующего выпуска: +%s %s" % [
    Model.batch_amount(float(data.get("forecast", 0))),
    Model.resource_label(str(data.get("product", "")))])
   var idle: String = str(data.get("idle_reason", ""))
   var missing: Dictionary = data.get("missing", {})
   if not missing.is_empty():
    for resource in missing:
     lines.append("%s: не хватает %s %s" % [
      "Простой" if idle.contains("не хватает") else "Следующая партия",
      Model.batch_amount(missing[resource]), Model.batch_unit(resource)])
    shortage_resource = str(missing.keys()[0])
    shortage_amount = float(missing[shortage_resource])
    if body_id in ["earth", "luna"]:
     supply_button.text = "Доставить: " + Model.resource_label(shortage_resource)
     supply_button.show()
   elif not idle.is_empty():
    lines.append(idle if not idle.contains("не хватает") else "Сырьё есть · ждёт следующего цикла")
   for shipment in data.get("incoming", []):
    lines.append("%s: +%s %s%s" % [shipment.mode,
     Model.batch_amount(shipment.amount), Model.batch_unit(shipment.resource),
     " · " + Calendar.calendar_text(shipment.arrival) if is_finite(shipment.arrival) else ""])
   var next_batch: float = float(data.get("next_native", INF))
   if is_finite(next_batch):
    lines.append("%s: %s · через %d дн." % [
     "Приём сырья" if str(data.get("delivery", "")).begins_with("Сырьё в пути") else (
      "Следующая попытка" if not idle.is_empty() or not missing.is_empty() else "Следующая партия"),
     Calendar.calendar_text(next_batch),
     Calendar.days_remaining(displayed_native, next_batch)])
   else:
    lines.append("Следующая партия: не запланирована")
  elif kind in ["factory", "power_plant"]:
   lines.append("Производственный цикл пока не подключён")
   lines.append("Фактической партии и срока следующего выпуска нет")
  elif kind == "spaceport":
   lines.append("Открыта логистика этой колонии")
  elif kind == "administrative_center":
   lines.append("Открыто управление строительством и очередью")
  else:
   lines.append("Построено · готово")
  detail_icon.kind = kind
  detail_icon.show()
  detail_icon.queue_redraw()
  detail_title.text = built_buttons[selected_facility].text
  detail_description.text = "\n".join(lines)
  detail_title.show()
  detail_description.show()
  break

func _purpose(kind: String, item: Dictionary) -> String:
 match kind:
  "administrative_center":
   return "Управление колонией и местным складом"
  "spaceport":
   return "Приём и отправка грузовых кораблей"
  "mining_rig":
   return "Добыча руды из местных месторождений"
  "refinery":
   return "Переработка руды в металл"
  "farm":
   return "Выращивание продовольствия"
  "power_plant":
   return "Производство энергии"
  "factory":
   return "Изготовление промышленных компонентов"
  "shipyard":
   return "Строительство кораблей"
  "orbital_platform":
   return "Орбитальная инфраструктура"
 return str(item.get("name", "Объект колонии"))


