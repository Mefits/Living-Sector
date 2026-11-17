extends ScrollContainer
## Presentation-only card panel for the currently selected source entity.
## The full textual N39 inspector remains in its separate sibling tab.
const Data = preload("res://scripts/view/colony_context_projection.gd")
var _title: Label
var _subtitle: Label
var _cards: Array = []
var _notes: Array[Label] = []
var _previous: Dictionary = {}

func _ready() -> void:
    name = "Обзор"
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    var margins := MarginContainer.new()
    margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margins.add_theme_constant_override(side, 12)
    add_child(margins)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 10)
    margins.add_child(column)
    _title = Label.new()
    _title.add_theme_font_size_override("font_size", 22)
    _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_title)
    _subtitle = Label.new()
    _subtitle.add_theme_font_size_override("font_size", 14)
    _subtitle.add_theme_color_override("font_color", Color("#8daaba"))
    _subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_subtitle)
    var cards := GridContainer.new()
    cards.columns = 2
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cards.add_theme_constant_override("h_separation", 8)
    cards.add_theme_constant_override("v_separation", 8)
    column.add_child(cards)
    for i in range(4):
        var panel := PanelContainer.new()
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#182938")
        style.corner_radius_top_left = 5
        style.corner_radius_top_right = 5
        style.corner_radius_bottom_left = 5
        style.corner_radius_bottom_right = 5
        style.content_margin_left = 9
        style.content_margin_top = 9
        style.content_margin_right = 9
        style.content_margin_bottom = 9
        panel.add_theme_stylebox_override("panel", style)
        cards.add_child(panel)
        var inner := VBoxContainer.new()
        inner.add_theme_constant_override("separation", 3)
        panel.add_child(inner)
        var caption := Label.new()
        caption.add_theme_font_size_override("font_size", 13)
        caption.add_theme_color_override("font_color", Color("#95acba"))
        caption.clip_text = true
        inner.add_child(caption)
        var number := Label.new()
        number.add_theme_font_size_override("font_size", 19)
        number.clip_text = true
        number.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        inner.add_child(number)
        var note := Label.new()
        note.add_theme_font_size_override("font_size", 11)
        note.add_theme_color_override("font_color", Color("#7e9aa8"))
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        inner.add_child(note)
        _cards.append({"panel": panel, "caption": caption,
            "value": number, "note": note})
    var divider := HSeparator.new()
    column.add_child(divider)
    var details_heading := Label.new()
    details_heading.text = "Состояние и сведения"
    details_heading.add_theme_font_size_override("font_size", 16)
    column.add_child(details_heading)
    for i in range(6):
        var line := Label.new()
        line.add_theme_font_size_override("font_size", 14)
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.add_theme_color_override("font_color", Color("#c3d2db"))
        column.add_child(line)
        _notes.append(line)
    show_projection({"title": "Колония", "subtitle": "Выбери объект",
        "cards": [], "lines": []})

func show_selection(world: Dictionary, body_id: String,
        facility_id: String, ship_id: String, economy: Dictionary) -> void:
    show_projection(Data.build(world, body_id, facility_id,
        ship_id, economy))

func show_projection(value: Dictionary) -> void:
    if not is_node_ready() or value == _previous:
        return
    _previous = value
    _title.text = str(value.get("title", "Колония"))
    _subtitle.text = str(value.get("subtitle", ""))
    var data: Array = value.get("cards", [])
    for i in range(_cards.size()):
        var card: Dictionary = _cards[i]
        var has_data: bool = i < data.size()
        (card["panel"] as PanelContainer).visible = has_data
        if not has_data:
            continue
        var spec: Dictionary = data[i]
        (card["caption"] as Label).text = str(spec.get("label", ""))
        (card["value"] as Label).text = str(spec.get("value", "—"))
        (card["note"] as Label).text = str(spec.get("note", ""))
        (card["note"] as Label).visible = not str(spec.get(
            "note", "")).is_empty()
    var lines: Array = value.get("lines", [])
    for i in range(_notes.size()):
        var has_line: bool = i < lines.size()
        _notes[i].visible = has_line
        if has_line:
            _notes[i].text = str(lines[i])
