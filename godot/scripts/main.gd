extends Control
## P0 = a real Godot scene reading actual native world/faction JSON.
## NOT a simulation rewrite yet; do not claim simulated cargo or AI output.

const NativeData = preload("res://scripts/native_data.gd")
const SystemMap = preload("res://scripts/system_map.gd")

var _details: RichTextLabel
var _status: Label

func _ready() -> void:
    var data: Dictionary = NativeData.load_current_world()
    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 8)
    add_child(root)

    var title := Label.new()
    title.text = "LIVING SECTOR  /  GODOT PORT P0"
    title.add_theme_font_size_override("font_size", 24)
    root.add_child(title)

    _status = Label.new()
    _status.text = "Чтение нативных данных — симуляция пока не перенесена"
    root.add_child(_status)

    var columns := HBoxContainer.new()
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_theme_constant_override("separation", 10)
    root.add_child(columns)

    var map_border := PanelContainer.new()
    map_border.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_border.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(map_border)

    var map: Control = SystemMap.new()
    map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map.custom_minimum_size = Vector2(430, 420)
    map_border.add_child(map)

    var side := PanelContainer.new()
    side.custom_minimum_size = Vector2(340, 0)
    columns.add_child(side)

    _details = RichTextLabel.new()
    _details.fit_content = false
    _details.scroll_active = true
    side.add_child(_details)

    if data.has("error"):
        _status.text = str(data["error"])
        _details.text = "Источником правды остаётся Rust Galaxy 0.6.7."
        return

    var worlds: Array = data.get("worlds", [])
    var factions: Array = data.get("factions", [])
    _status.text = "Нативные данные: %d систем · %d фракции. Только чтение." % [
        worlds.size(), factions.size()
    ]
    map.set_worlds(worlds)
    map.system_selected.connect(_select_world)
    if not worlds.is_empty():
        _select_world(worlds[0])

func _select_world(item: Dictionary) -> void:
    var system: Dictionary = item.get("system", {})
    var bodies: Array = item.get("bodies", [])
    var facilities: Array = item.get("facilities", [])
    var text_lines: Array[String] = []
    text_lines.append("СИСТЕМА: " + str(system.get("name", "—")))
    text_lines.append("ID: " + str(system.get("id", "—")))
    text_lines.append("Тип звезды: " + str(system.get("star_type", "—")))
    text_lines.append("Небесных тел: " + str(bodies.size()))
    text_lines.append("Исходных объектов: " + str(facilities.size()))
    text_lines.append("")
    text_lines.append("ТЕЛА")
    for body in bodies:
        text_lines.append(" • " + str(body.get("name", "—")) +
            "  [" + str(body.get("type", "—")) + "]")
    text_lines.append("")
    text_lines.append("Без вымышленных запасов, контрактов и тиков.")
    _details.text = "\n".join(text_lines)
