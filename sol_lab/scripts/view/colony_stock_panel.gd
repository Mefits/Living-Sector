extends PanelContainer
## Compact, read-only view of a real colony market (never a second inventory).
const Calendar = preload("res://scripts/sol_calendar.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Icons = preload("res://scripts/view/sol_icon_atlas.gd")
const ORDER: Array[String] = [
 "metals", "ore", "water", "food", "fuel", "energy_cells",
 "components", "ice", "gas", "polymers", "electronics", "tools",
 "medical", "luxury", "rare_ore", "crystal_ore"
]
const EXTRA_LABELS: Dictionary = {
 "electronics": "Электроника", "tools": "Инструменты",
 "medical": "Медтовары", "luxury": "Роскошь"
}
var heading: Label
var arrivals: VBoxContainer
var columns: HBoxContainer
var amount_labels: Dictionary = {}
var _visible_keys: Array[String] = []

func _init() -> void:
 visible = false
 var style := StyleBoxFlat.new()
 style.bg_color = Color("#192a35")
 style.border_color = Color("#3b5361")
 style.set_border_width_all(1)
 style.set_corner_radius_all(5)
 style.content_margin_left = 8.0
 style.content_margin_right = 8.0
 style.content_margin_top = 6.0
 style.content_margin_bottom = 7.0
 add_theme_stylebox_override("panel", style)
 var body := VBoxContainer.new()
 body.add_theme_constant_override("separation", 4)
 add_child(body)
 heading = Label.new()
 heading.add_theme_font_size_override("font_size", 15)
 heading.add_theme_color_override("font_color", Color("#b6dce5"))
 body.add_child(heading)
 columns = HBoxContainer.new()
 columns.add_theme_constant_override("separation", 12)
 var legend := Label.new()
 legend.text = "Доступно  /  изменение за 30 игр. дней"
 legend.add_theme_font_size_override("font_size", 12)
 body.add_child(legend)
 body.add_child(columns)
 arrivals = VBoxContainer.new()
 body.add_child(arrivals)

func show_inventory(planet: String, warehouse: Dictionary) -> void:
 visible = bool(warehouse.get("present", false))
 if not visible:
  return
 heading.text = "Склад колонии · " + planet
 _show_incoming(warehouse.get("incoming", []))
 var supply: Dictionary = warehouse.get("supply", {})
 var movement: Dictionary = warehouse.get("movement", {})
 var keys: Array[String] = []
 for resource in ORDER:
  if supply.has(resource):
   keys.append(resource)
 var extra: Array[String] = []
 for key in supply:
  var id: String = str(key)
  if not keys.has(id):
   extra.append(id)
 extra.sort()
 keys.append_array(extra)
 if keys == _visible_keys:
  # Keep the existing nodes when only amounts change.
  for resource in keys:
   var label: Label = amount_labels[resource]
   _display_amount(label, supply[resource], movement.get(resource, {}))
  return
 _visible_keys = keys
 for child in columns.get_children():
  columns.remove_child(child)
  child.queue_free()
 amount_labels.clear()
 if keys.is_empty():
  var empty := Label.new()
  empty.text = "Склад пуст"
  columns.add_child(empty)
  return
 var halves: Array[VBoxContainer] = []
 for index in range(2):
  var part := VBoxContainer.new()
  part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  part.add_theme_constant_override("separation", 1)
  columns.add_child(part)
  halves.append(part)
 for i in range(keys.size()):
  var resource: String = keys[i]
  var side: VBoxContainer = halves[i % 2]
  var line := HBoxContainer.new()
  line.add_theme_constant_override("separation", 3)
  side.add_child(line)
  var resource_icon: TextureRect = Icons.make_icon(resource, false, 20)
  if resource_icon != null:
   line.add_child(resource_icon)
  var resource_name := Label.new()
  resource_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  resource_name.text = str(EXTRA_LABELS.get(resource,
   Model.resource_label(resource)))
  resource_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  resource_name.add_theme_font_size_override("font_size", 13)
  resource_name.add_theme_color_override("font_color", Color("#c4d0d5"))
  line.add_child(resource_name)
  var amount := Label.new()
  _display_amount(amount, supply[resource], movement.get(resource, {}))
  amount.custom_minimum_size.x = 36.0
  amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
  amount.add_theme_font_size_override("font_size", 13)
  amount.add_theme_color_override("font_color", Color("#f0dfae"))
  line.add_child(amount)
  amount_labels[resource] = amount

func _display_amount(label: Label, value: float, row: Dictionary) -> void:
 var incoming: float = row.get("in", 0.0)
 var spent: float = row.get("out", 0.0)
 var balance := incoming - spent
 label.text = "%s / %s%s" % [Model.batch_amount(value),
  "+" if balance > 0 else "", Model.batch_amount(balance)]
 label.mouse_filter = Control.MOUSE_FILTER_STOP
 label.tooltip_text = "Доступно: %s
30 дней · приход: %s · расход: %s
В резерве: %s" % [
  Model.batch_amount(value), Model.batch_amount(incoming), Model.batch_amount(spent),
  Model.batch_amount(row.get("reserved", 0.0))]


func _show_incoming(incoming: Array) -> void:
 while arrivals.get_child_count() > incoming.size():
  var row := arrivals.get_child(-1)
  arrivals.remove_child(row)
  row.queue_free()
 for index in incoming.size():
  var shipment: Dictionary = incoming[index]
  if index == arrivals.get_child_count():
   var label := Label.new()
   label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   label.add_theme_font_size_override("font_size", 12)
   label.add_theme_color_override("font_color", Color("#a9dbed"))
   arrivals.add_child(label)
  arrivals.get_child(index).text = "%s: +%s %s · борт %d%s" % [
   "В пути" if is_finite(shipment.arrival) else "Погрузка",
   Model.batch_amount(shipment.amount), Model.batch_unit(shipment.resource), shipment.ship,
   " · " + Calendar.calendar_text(shipment.arrival) if is_finite(shipment.arrival) else ""]
