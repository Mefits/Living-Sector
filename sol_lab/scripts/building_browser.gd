extends ColorRect
## Sol Lab build/admin surface. Config is shared with the owning scene.
signal apply_requested
signal reset_requested
const Model = preload("res://scripts/sol_building_model.gd")
var world: Dictionary = {}
var config: Dictionary = {}
var body_id: String = "earth"
var page: String = "build"
var title: Label
var tabs: HBoxContainer
var contents: VBoxContainer
var feedback: Label

func _ready() -> void:
 color = Color(0.01,0.025,0.043,0.90)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var centered := CenterContainer.new()
 add_child(centered)
 centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var panel := PanelContainer.new()
 panel.custom_minimum_size = Vector2(1040,650)
 centered.add_child(panel)
 var layout := VBoxContainer.new()
 panel.add_child(layout)
 var header := HBoxContainer.new()
 layout.add_child(header)
 title = _label(header,"",23,Color("#edd291"))
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _button(header,"Закрыть",hide)
 tabs = HBoxContainer.new()
 layout.add_child(tabs)
 var scroll := ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.custom_minimum_size = Vector2(1000,515)
 layout.add_child(scroll)
 contents = VBoxContainer.new()
 contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 scroll.add_child(contents)
 feedback = _label(layout,"",15,Color("#a5bdcb"))

func configure(source_world: Dictionary, settings: Dictionary,
        selected_id: String, admin: bool) -> void:
 world = source_world
 config = settings
 body_id = selected_id
 _navigate("admin_buildings" if admin else "build")
 show()

func _button(parent: Node, caption: String, callback: Callable) -> Button:
 var b := Button.new()
 b.text = caption
 b.custom_minimum_size = Vector2(98,41)
 parent.add_child(b)
 b.pressed.connect(callback)
 return b

func _label(parent: Node, value: String, font_size: int = 16,
        tone: Color = Color("#dce8ee")) -> Label:
 var l := Label.new()
 l.text = value
 l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 l.add_theme_font_size_override("font_size",font_size)
 l.add_theme_color_override("font_color",tone)
 parent.add_child(l)
 return l

func _clear(parent: Node) -> void:
 for child in parent.get_children():
  child.queue_free()

func _navigate(target: String) -> void:
 page = target
 _clear(tabs)
 _clear(contents)
 feedback.text = "Интерфейсный этап: N39/N154 ещё не подключены, строительство не выполняется."
 var label: String = "Земля" if body_id=="earth" else ("Луна" if body_id=="luna" else "Марс")
 if page=="build":
  title.text = "СТРОИТЕЛЬСТВО · "+label
  _button(tabs,"Админ · здания",_navigate.bind("admin_buildings"))
  _cards(false)
 elif page=="admin_buildings":
  title.text = "АДМИН · ЗДАНИЯ"
  _button(tabs,"Строительство",_navigate.bind("build"))
  _button(tabs,"Планета · "+label,_navigate.bind("admin_planet"))
  _button(tabs,"Потребности",_navigate.bind("admin_needs"))
  _cards(true)
 elif page=="admin_planet":
  title.text = "АДМИН · ПЛАНЕТА "+label.to_upper()
  _button(tabs,"Здания",_navigate.bind("admin_buildings"))
  _button(tabs,"Потребности",_navigate.bind("admin_needs"))
  _planet()
 else:
  title.text = "АДМИН · ПОТРЕБНОСТИ"
  _button(tabs,"Здания",_navigate.bind("admin_buildings"))
  _button(tabs,"Планета",_navigate.bind("admin_planet"))
  _needs()
 if page!="build":
  var bar := HBoxContainer.new()
  contents.add_child(bar)
  _button(bar,"Сохранить и перезапустить",func(): apply_requested.emit())
  _button(bar,"Сбросить",func(): reset_requested.emit())

func _cards(editable: bool) -> void:
 _label(contents,"3 карточки в ряд. Выпуск: базовый (с коэффициентом выбранной планеты).",16)
 var grid := GridContainer.new()
 grid.columns = 3
 grid.add_theme_constant_override("h_separation",12)
 grid.add_theme_constant_override("v_separation",12)
 contents.add_child(grid)
 for building in Model.BUILDINGS:
  var id: String = str(building["id"])
  var row: Dictionary = config["buildings"][id]
  var available: bool = Model.available(building,config["buildings"],world,body_id)
  var card := PanelContainer.new()
  card.custom_minimum_size = Vector2(302,246 if not editable else 335)
  var style := StyleBoxFlat.new()
  style.bg_color = Color("#1b3040") if available else Color("#111c29")
  style.border_color = Color("#435d71") if available else Color("#2b3b4a")
  style.set_border_width_all(1)
  style.set_content_margin_all(12)
  card.add_theme_stylebox_override("panel",style)
  grid.add_child(card)
  var stack := VBoxContainer.new()
  card.add_child(stack)
  _label(stack,str(building["name"]),19)
  if editable:
   _spin(stack,"Металлы",float(row["metals"]),_edit_building.bind(id,"metals"),1,100000)
   _spin(stack,"Труд",float(row["labor"]),_edit_building.bind(id,"labor"),1,100000)
   for resource in building["inputs"].keys():
    var key: String = "input_"+str(resource)
    _spin(stack,"Расход "+Model.resource_label(str(resource)),float(row[key]),_edit_building.bind(id,key),1,100000)
   if str(building["product"])!="none":
    _spin(stack,"Базовый выпуск",float(row["base"]),_edit_building.bind(id,"base"),1,100000)
  else:
   _label(stack,"Стоимость: %d металла · %d труда" % [int(row["metals"]),int(row["labor"])],15)
   var needs: Array[String] = []
   for resource in building["inputs"].keys():
    needs.append("%d %s" % [int(row["input_"+str(resource)]),Model.resource_label(str(resource))])
   _label(stack,"Расход/цикл: "+(" + ".join(needs) if not needs.is_empty() else "—"),15)
  var output := _label(stack,_production(building),17,Color("#89d9a3"))
  if editable:
   output.name = "Output_"+id
  var spacer := Control.new()
  spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
  stack.add_child(spacer)
  if not bool(building["ported"]):
   _label(stack,"Механика пока не перенесена",14,Color("#8ea5b5"))
  if not editable:
   var button := _button(stack,"Заказать" if available else "Недоступно",_not_connected)
   button.disabled = not available
   if not available:
    card.modulate = Color(0.65,0.69,0.75,1.0)

func _production(building: Dictionary) -> String:
 var resource: String = str(building["product"])
 if resource=="none":
  return "Выработка: —"
 var value: float = float(config["buildings"][building["id"]]["base"])
 var result: float = Model.calculated(building,config["buildings"],config["planets"],body_id)
 return "%s: +%s (+%s)" % [Model.resource_label(resource),_number(value),_number(result)]

func _number(value: float) -> String:
 if is_equal_approx(value,roundf(value)):
  return str(int(roundf(value)))
 return "%.2f" % value

func _not_connected() -> void:
 feedback.text = "Заказ не создан: N39 ещё не подключён. Ресурсы не списаны."

func _spin(parent: Node, name: String, value: float, callback: Callable,
        step_value: float, upper: float) -> void:
 var row := HBoxContainer.new()
 parent.add_child(row)
 var caption := _label(row,name,15)
 caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var box := SpinBox.new()
 box.min_value = 0
 box.max_value = upper
 box.step = step_value
 box.rounded = step_value >= 1
 box.custom_minimum_size = Vector2(90,35)
 box.value = value
 row.add_child(box)
 box.value_changed.connect(callback)

func _edit_building(value: float, building_id: String, key: String) -> void:
 var row: Dictionary = config["buildings"][building_id]
 row[key] = int(roundf(value))
 config["buildings"][building_id] = row
 for building in Model.BUILDINGS:
  if str(building["id"])==building_id:
   # Update green calculated value without replacing the active SpinBox.
   for card in contents.get_children():
    if card is GridContainer:
     for panel in card.get_children():
      var output: Node = panel.find_child("Output_"+building_id,true,false)
      if output is Label:
       output.text = _production(building)
   break
 feedback.text = "Изменено. Сохраните и перезапустите."

func _planet() -> void:
 _label(contents,"Коэффициенты меняются только здесь. Итоговая выработка рассчитывается автоматически.",17)
 _label(contents,"Еда и промышленные коэффициенты — временные настройки превью.",14)
 var row: Dictionary = config["planets"][body_id]
 var keys: Array = row.keys()
 keys.sort()
 for key in keys:
  _spin(contents,Model.resource_label(str(key)),float(row[key]),_edit_planet.bind(str(key)),0.05,10)

func _edit_planet(value: float, key: String) -> void:
 var row: Dictionary = config["planets"][body_id]
 row[key] = snappedf(value,0.01)
 config["planets"][body_id] = row
 feedback.text = "Коэффициент изменён; проверьте новое число в карточке здания."

func _needs() -> void:
 _label(contents,"Потребности жителей Земли (пока без симуляции).",17)
 var needs: Dictionary = config["needs"]
 _spin(contents,"Еда",float(needs.get("earth_food",5)),_edit_need.bind("earth_food"),1,100000)
 _spin(contents,"Вода",float(needs.get("earth_water",3)),_edit_need.bind("earth_water"),1,100000)

func _edit_need(value: float, key: String) -> void:
 config["needs"][key] = int(roundf(value))
 feedback.text = "Изменено. Сохраните и перезапустите."
