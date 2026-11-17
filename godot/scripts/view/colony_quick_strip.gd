extends HFlowContainer
## Small top-of-map instrument strip, NOT another game or planning panel.
## Only buttons are interactive: clicking opens a short real-data menu.
const QuickData = preload("res://scripts/view/colony_quick_projection.gd")
const ORDER: Array[String] = [
    "colony", "population", "food", "energy", "construction", "alerts"
]
const TITLES: Dictionary = {
    "colony": "Колония", "population": "Жители",
    "food": "Еда", "energy": "Энергия",
    "construction": "Стройки", "alerts": "Сигналы"
}
var _buttons: Dictionary = {}
var _menu: PopupMenu
var _data: Dictionary = {}

func _ready() -> void:
    add_theme_constant_override("h_separation", 4)
    add_theme_constant_override("v_separation", 2)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    visible = false
    for key in ORDER:
        var button: Button = Button.new()
        button.text = str(TITLES[key]) + " —"
        button.flat = true
        button.custom_minimum_size = Vector2(0, 27)
        button.add_theme_font_size_override("font_size", 11)
        button.focus_mode = Control.FOCUS_NONE
        button.pressed.connect(_open_menu.bind(key))
        add_child(button)
        _buttons[key] = button
    _menu = PopupMenu.new()
    add_child(_menu)

func show_colony(world: Dictionary, body_id: String,
        economy: Dictionary) -> void:
    var state: Dictionary = QuickData.project(world, body_id, economy)
    if state == _data:
        return
    _data = state
    visible = bool(state.get("visible", false))
    if not visible:
        if _menu != null:
            _menu.hide()
        return
    for key in ORDER:
        var button: Button = _buttons[key]
        var value: Variant = state.get(key, null)
        if key == "colony":
            button.text = str(state.get("name", "Колония")) + " ▾"
        elif value == null:
            button.text = str(TITLES[key]) + " —"
        elif value is float:
            button.text = str(TITLES[key]) + " " + ("%.0f" % float(value))
        else:
            button.text = str(TITLES[key]) + " " + str(value)
        var info: Array = state.get("details", {}).get(key, [])
        button.tooltip_text = "\n".join(PackedStringArray(info))
        if key == "alerts" and value != null and int(value) > 0:
            button.add_theme_color_override("font_color", Color("#e5ab90"))
        else:
            button.remove_theme_color_override("font_color")

func _open_menu(key: String) -> void:
    _menu.clear()
    var info: Array = _data.get("details", {}).get(key, [])
    for item in info:
        var index: int = _menu.get_item_count()
        _menu.add_item(str(item))
        _menu.set_item_disabled(index, true)
    if info.is_empty():
        _menu.add_item("Данные пока отсутствуют")
        _menu.set_item_disabled(0, true)
    var button: Button = _buttons[key]
    var pos: Vector2 = button.get_screen_position()
    _menu.popup(Rect2i(
        Vector2i(roundi(pos.x), roundi(pos.y + button.size.y + 2.0)),
        Vector2i(320, 0)))
