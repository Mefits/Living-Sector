extends PanelContainer
## Compact, read-only view of a real colony market (never a second inventory).
const Model = preload("res://scripts/sol_building_model.gd")
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
var columns: HBoxContainer
var amount_labels: Dictionary = {}

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
 body.add_child(columns)

func show_inventory(planet: String, warehouse: Dictionary) -> void:
 visible = bool(warehouse.get("present", false))
 if not visible:
  return
 heading.text = "Склад колонии · " + planet
 for child in columns.get_children():
  columns.remove_child(child)
  child.queue_free()
 amount_labels.clear()
 var supply: Dictionary = warehouse.get("supply", {})
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
  var resource_name := Label.new()
  resource_name.text = str(EXTRA_LABELS.get(resource,
   Model.resource_label(resource)))
  resource_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  resource_name.add_theme_font_size_override("font_size", 13)
  resource_name.add_theme_color_override("font_color", Color("#c4d0d5"))
  line.add_child(resource_name)
  var amount := Label.new()
  amount.text = Model.batch_amount(float(supply[resource]))
  amount.custom_minimum_size.x = 36.0
  amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
  amount.add_theme_font_size_override("font_size", 13)
  amount.add_theme_color_override("font_color", Color("#f0dfae"))
  line.add_child(amount)
  amount_labels[resource] = amount
