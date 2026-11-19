extends PanelContainer
## Fixed-header colony control; stock/list/detail are views of one real world.
signal build_requested
signal line_requested
signal facility_requested(facility_id: String)

const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Glyph = preload("res://scripts/view/colony_building_glyph.gd")
const Stock = preload("res://scripts/view/colony_stock_panel.gd")

var heading: Label
var population: Label
var summary: Label
var metal: Label
var food_status: Label
var details: Label
var message: Label
var stock_panel: PanelContainer
var colonize_button: Button
var freight_button: Button
var line_holder: VBoxContainer
var built_list: VBoxContainer
var detail_title: Label
var detail_description: Label
var overview: VBoxContainer
var stock_view: VBoxContainer
var scroll: ScrollContainer
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
 metal = _label(layout, "", 15, Color("#e6d59d"))
 food_status = _label(layout, "", 13, Color("#bfd0d9"))
 food_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

 var navigation := HBoxContainer.new()
 navigation.add_theme_constant_override("separation", 5)
 layout.add_child(navigation)
 _button(navigation, "Строить", func(): build_requested.emit())
 _button(navigation, "Склад", func(): _switch_page("stock"))
 _button(navigation, "Построено", func(): _switch_page("overview"))
 _button(navigation, "Линия", func(): line_requested.emit())

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
 detail_title = _label(overview, "", 16, Color("#f0dfae"))
 detail_description = _label(overview, "", 13, Color("#bfd0d9"))
 detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 built_list = VBoxContainer.new()
 built_list.add_theme_constant_override("separation", 3)
 overview.add_child(built_list)
 stock_view = VBoxContainer.new()
 content.add_child(stock_view)
 stock_panel = Stock.new()
 stock_view.add_child(stock_panel)
 stock_view.hide()

 message = _label(layout, "", 12, Color("#e5cb92"))
 message.clip_text = true
 message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 colonize_button = _button(layout, "Колонизировать Луну", func(): pass)
 freight_button = _button(layout, "Грузовик", func(): pass)
 line_holder = VBoxContainer.new()
 line_holder.add_theme_constant_override("separation", 3)
 layout.add_child(line_holder)
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
 stock_view.visible = page == "stock"
 scroll.scroll_vertical = 0

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
        now_native: float) -> void:
 if body_id != next_body:
  selected_facility = ""
  _switch_page("overview")
 body_id = next_body
 heading.text = name_ru
 population.text = "%d жителей" % residents if bool(warehouse.get("present", false)) else "Без колонии"
 var supply: Dictionary = warehouse.get("supply", {})
 metal.text = ("Металл на складе: %s" %
  Model.batch_amount(float(supply.get("metals", 0)))) if bool(
  warehouse.get("present", false)) else "Нет местного склада"
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
   var pick := _button(row, str(item.get("name", kind)),
    _pick.bind(facility_id))
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
 for facility in built_facilities:
  if str(facility.get("id", "")) != selected_facility:
   continue
  var kind: String = _kind(facility)
  var item: Dictionary = Model.find_building(kind)
  var purpose: String = _purpose(kind, item)
  var state: String = "Построено · готово"
  if kind in ["mining_rig", "refinery", "farm"]:
   var produced: String = str(facility.get("production_status", ""))
   state = produced if not produced.is_empty() else "Ожидание первой партии (30 дней)"
  elif kind in ["factory", "power_plant"]:
   state = "Цикл производства не подключён в Sol Lab"
  detail_title.text = str(facility.get("name", kind))
  detail_description.text = "%s\nСостояние: %s" % [purpose, state]
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
