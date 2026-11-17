extends Control
## Living Sector strategy HUD — Figma-inspired, read-only presentation.
## The game owns the map, authoritative economy, orders and clock.
## Never requests a new world_snapshot or invents per-tick trends.
const BG = Color("#0B171E")
const BG2 = Color("#10212A")
const LINE = Color("#31505A")
const TEAL = Color("#53B5AC")
const AMBER = Color("#C99B54")
const TEXT = Color("#D3DDDD")
const MUTED = Color("#81999F")
const METRICS: Array[Dictionary] = [
    {"key": "population", "label": "НАСЕЛЕНИЕ", "symbol": "●"},
    {"key": "food", "label": "ЕДА", "symbol": "◒"},
    {"key": "ore", "label": "РУДА", "symbol": "◆"},
    {"key": "metals", "label": "МЕТАЛЛЫ", "symbol": "⬡"},
    {"key": "energy_cells", "label": "ЭНЕРГОЯЧЕЙКИ", "symbol": "ϟ"},
    {"key": "water", "label": "ВОДА", "symbol": "▽"}
]
var _game: Control
var _world: Dictionary = {}
var _economy: Dictionary = {}
var _body: String = ""
var _facility: String = ""
var _ship: String = ""
var _mode: String = "sector"
var _window_mode: String = ""
var _tab: String = "Обзор"
var _top: PanelContainer
var _brand_scope: Button
var _metric_nodes: Dictionary = {}
var _clock: Label
var _pause: Button
var _outliner: PanelContainer
var _outliner_list: VBoxContainer
var _outliner_signature: String = ""
var _window: PanelContainer
var _window_title: Label
var _window_text: RichTextLabel
var _window_tabs: HBoxContainer
var _status_text: String = ""
var _diagnostic_text: String = ""
var _selected_name: String = ""
var _tick: int = -1
var _paused: bool = false
var _speed: float = 1.0
var _show_outliner: bool = true

func _style(color: Color, border: Color = LINE, left: int = 1,
        top: int = 1, right: int = 1, bottom: int = 1) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = border
    box.border_width_left = left
    box.border_width_top = top
    box.border_width_right = right
    box.border_width_bottom = bottom
    box.content_margin_left = 8
    box.content_margin_right = 8
    box.content_margin_top = 6
    box.content_margin_bottom = 6
    return box

func _label(value: String, size_px: int = 13, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", size_px)
    label.add_theme_color_override("font_color", color)
    label.clip_text = true
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    return label

func _button(value: String, callback: Callable, size_px: int = 12) -> Button:
    var button := Button.new()
    button.text = value
    button.add_theme_font_size_override("font_size", size_px)
    button.add_theme_color_override("font_color", TEXT)
    button.add_theme_color_override("font_hover_color", Color("#A4E8DE"))
    button.add_theme_stylebox_override("normal", _style(BG))
    button.add_theme_stylebox_override("hover", _style(Color("#183239"), TEAL))
    button.add_theme_stylebox_override("pressed", _style(Color("#183239"), TEAL))
    button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, TEAL))
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(callback)
    return button

func _panel() -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _style(BG))
    return panel

func attach(game: Control) -> void:
    _game = game

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_top()
    _build_left()
    _build_outliner()
    _build_window()
    resized.connect(_layout_window)
    set_process_unhandled_key_input(true)
    _layout_window()

func _build_top() -> void:
    _top = _panel()
    _top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _top.offset_bottom = 66
    _top.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_top)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 0)
    _top.add_child(row)
    var brand := VBoxContainer.new()
    brand.custom_minimum_size = Vector2(184, 0)
    brand.add_theme_constant_override("separation", 3)
    row.add_child(brand)
    brand.add_child(_label("L I V I N G  S E C T O R", 15, TEXT))
    _brand_scope = _button("СЕКТОР · ВСЕ РЫНКИ ▾", _toggle_scope, 11)
    _brand_scope.tooltip_text = "Общие запасы рынков всех фракций, НЕ баланс одной фракции"
    brand.add_child(_brand_scope)
    for item in METRICS:
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(121, 0)
        box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        box.add_theme_constant_override("separation", 4)
        row.add_child(box)
        box.add_child(_label(str(item["label"]), 10, MUTED))
        var large := _label(str(item["symbol"]) + " —", 16, TEXT)
        box.add_child(large)
        _metric_nodes[str(item["key"])] = large
    var time_area := VBoxContainer.new()
    time_area.custom_minimum_size = Vector2(158, 0)
    row.add_child(time_area)
    _clock = _label("ТИК — · ×1", 11, MUTED)
    time_area.add_child(_clock)
    var controls := HBoxContainer.new()
    time_area.add_child(controls)
    _pause = _button("⏸", func() -> void: _game.call("_toggle_pause"), 17)
    _pause.tooltip_text = "Пауза / продолжить (настоящие часы N158)"
    _pause.custom_minimum_size = Vector2(45, 0)
    controls.add_child(_pause)
    var slower := _button("×1", _normal_speed)
    slower.custom_minimum_size = Vector2(42, 0)
    controls.add_child(slower)
    var faster := _button("×16", _fast_speed)
    faster.custom_minimum_size = Vector2(46, 0)
    controls.add_child(faster)

func _build_left() -> void:
    var rail := _panel()
    rail.anchor_bottom = 1.0
    rail.offset_top = 66
    rail.offset_right = 66
    rail.offset_bottom = -4
    add_child(rail)
    var menu := VBoxContainer.new()
    menu.add_theme_constant_override("separation", 7)
    rail.add_child(menu)
    for entry in [
        {"text":"КОЛ", "tip":"Открыть колонию", "action":"colony"},
        {"text":"ЭКН", "tip":"Экономика рынков", "action":"economy"},
        {"text":"ФЛТ", "tip":"Корабли и груз", "action":"fleet"},
        {"text":"ОБЪ", "tip":"Показать/скрыть список объектов", "action":"outliner"},
        {"text":"ДАН", "tip":"Подробные данные N39", "action":"technical"}
    ]:
        var action: String = str(entry["action"])
        var btn := _button(str(entry["text"]), _activate.bind(action), 11)
        btn.tooltip_text = str(entry["tip"])
        btn.custom_minimum_size = Vector2(45, 49)
        menu.add_child(btn)

func _build_outliner() -> void:
    _outliner = _panel()
    _outliner.anchor_left = 1.0
    _outliner.anchor_right = 1.0
    _outliner.anchor_bottom = 1.0
    _outliner.offset_left = -272
    _outliner.offset_right = -8
    _outliner.offset_top = 76
    _outliner.offset_bottom = -12
    add_child(_outliner)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 7)
    _outliner.add_child(col)
    var head := HBoxContainer.new()
    col.add_child(head)
    var caption := _label("ОБЪЕКТЫ СИСТЕМЫ", 13)
    caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(caption)
    head.add_child(_button("×", _toggle_outliner, 15))
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(scroll)
    _outliner_list = VBoxContainer.new()
    _outliner_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _outliner_list.add_theme_constant_override("separation", 3)
    scroll.add_child(_outliner_list)

func _build_window() -> void:
    _window = _panel()
    _window.visible = false
    _window.anchor_bottom = 1.0
    add_child(_window)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    _window.add_child(col)
    var header := HBoxContainer.new()
    col.add_child(header)
    _window_title = _label("Колония", 19)
    _window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_window_title)
    header.add_child(_button("×", _close_window, 18))
    _window_tabs = HBoxContainer.new()
    _window_tabs.add_theme_constant_override("separation", 5)
    col.add_child(_window_tabs)
    _window_text = RichTextLabel.new()
    _window_text.bbcode_enabled = false
    _window_text.scroll_active = true
    _window_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _window_text.add_theme_font_size_override("normal_font_size", 14)
    _window_text.add_theme_color_override("default_color", TEXT)
    col.add_child(_window_text)

func _layout_window() -> void:
    if _window == null:
        return
    _window.offset_left = 80
    _window.offset_right = minf(760.0, maxf(515.0, size.x - 370.0))
    _window.offset_top = 91
    _window.offset_bottom = -40

func _normal_speed() -> void:
    if _game != null:
        _game.call("_change_speed", 1)

func _fast_speed() -> void:
    if _game != null:
        _game.call("_change_speed", 5)

func _toggle_scope() -> void:
    if _body.is_empty():
        _mode = "sector"
    else:
        _mode = "colony" if _mode == "sector" else "sector"
    _update_metrics()
    _update_window()

func _toggle_outliner() -> void:
    _show_outliner = not _show_outliner
    _outliner.visible = _show_outliner

func _close_window() -> void:
    _window.visible = false
    _window_mode = ""

func _activate(kind: String) -> void:
    if kind == "outliner":
        _toggle_outliner()
        return
    if kind == "colony" and _body.is_empty():
        for row in _world.get("facilities", []):
            if row is Dictionary and not str(row.get("body", "")).is_empty():
                _select_body(str(row["body"]))
                break
    _window_mode = kind
    _tab = "Обзор"
    _window.visible = true
    _update_window()

func _select_body(id: String) -> void:
    if _game == null:
        return
    if not bool(_game.get("_in_system")):
        _game.call("_open_selected_system")
    for item in _world.get("bodies", []):
        if item is Dictionary and str(item.get("id", "")) == id:
            _game.call("_on_body_selected", item)
            break
    _mode = "colony"

func _select_facility(id: String) -> void:
    if _game == null:
        return
    if not bool(_game.get("_in_system")):
        _game.call("_open_selected_system")
    _game.call("_on_facility_selected", id)
    _window_mode = "facility"
    _tab = "Обзор"
    _window.visible = true

func _select_ship(id: String) -> void:
    if _game == null:
        return
    if not bool(_game.get("_in_system")):
        _game.call("_open_selected_system")
    _game.call("_on_ship_selected", id)
    _window_mode = "ship"
    _tab = "Обзор"
    _window.visible = true

func present(world: Dictionary, economy: Dictionary, body: String,
        facility: String, ship: String, tick: int, paused: bool,
        speed: float, status: String, diagnostics: String) -> void:
    if not world.is_empty():
        _world = world
    if not economy.is_empty():
        _economy = economy
    _body = body
    _facility = facility
    _ship = ship
    _tick = tick
    _paused = paused
    _speed = speed
    _status_text = status
    _diagnostic_text = diagnostics
    if _mode == "colony" and _body.is_empty():
        _mode = "sector"
    _clock.text = "ТИК %d  ·  ×%s" % [_tick, str(_speed)]
    _pause.text = "▶" if _paused else "⏸"
    _brand_scope.text = ("КОЛОНИЯ · " + _body.to_upper() + " ▾"
        if _mode == "colony" else "СЕКТОР · ВСЕ РЫНКИ ▾")
    _brand_scope.tooltip_text = ("Запасы рынка выбранной колонии"
        if _mode == "colony" else
        "Сумма запасов всех рынков и населения ВСЕХ фракций; не активы игрока")
    _update_metrics()
    _update_outliner()
    _update_window()

func _scope_locations() -> Dictionary:
    var locations: Dictionary = {}
    if _mode == "sector":
        return locations
    for item in _world.get("facilities", []):
        if item is Dictionary and str(item.get("body", "")) == _body:
            locations[str(item.get("location", ""))] = true
    return locations

func _quantities() -> Dictionary:
    var values: Dictionary = {}
    var present: Dictionary = {}
    var locations: Dictionary = _scope_locations()
    var sector: bool = _mode == "sector"
    var markets: Variant = _economy.get("markets", null)
    if markets is Dictionary:
        for key in markets:
            if not sector and not locations.has(str(key)):
                continue
            var market: Variant = markets[key]
            if not (market is Dictionary):
                continue
            var supply: Variant = market.get("supply", null)
            if not (supply is Dictionary):
                continue
            for resource in ["food", "ore", "metals", "water", "energy_cells"]:
                if supply.has(resource):
                    values[resource] = float(values.get(resource, 0.0)) + float(supply[resource])
                    present[resource] = true
    var people: Variant = _economy.get("populations", null)
    if people is Dictionary:
        for entry in people.values():
            if not (entry is Dictionary):
                continue
            if not sector and not locations.has(str(entry.get("location", ""))):
                continue
            values["population"] = float(values.get("population", 0.0)) + float(entry.get("count", 0))
            present["population"] = true
    return {"values": values, "present": present}

func _update_metrics() -> void:
    if _metric_nodes.is_empty():
        return
    var projection: Dictionary = _quantities()
    var values: Dictionary = projection["values"]
    var present: Dictionary = projection["present"]
    for item in METRICS:
        var key: String = str(item["key"])
        var label: Label = _metric_nodes[key]
        label.text = str(item["symbol"]) + " " + (
            str(roundi(float(values.get(key, 0.0)))) if present.has(key) else "—")
        label.tooltip_text = ("Население в выбранной области" if key == "population"
            else "Количество %s в рыночных запасах; это не добыча и не прогноз" % str(item["label"]))
        if not present.has(key):
            label.add_theme_color_override("font_color", MUTED)
        else:
            label.add_theme_color_override("font_color", TEXT)

func _outliner_entry(label: String, callback: Callable,
        selected: bool = false) -> void:
    var btn := _button(label, callback, 12)
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    if selected:
        btn.add_theme_color_override("font_color", TEAL)
        btn.add_theme_stylebox_override("normal", _style(BG2, TEAL))
    _outliner_list.add_child(btn)

func _group(title: String) -> void:
    _outliner_list.add_child(_label(title, 11, TEAL))

func _update_outliner() -> void:
    if _outliner_list == null or _world.is_empty():
        return
    var signature: String = str(_world.get("system", {}).get("id", "")) + (
        "|" + _body + "|" + _facility + "|" + _ship)
    for body in _world.get("bodies", []):
        if body is Dictionary:
            signature += ":" + str(body.get("id", ""))
    for facility in _world.get("facilities", []):
        if facility is Dictionary:
            signature += ":" + str(facility.get("id", ""))
    var ships: Variant = _economy.get("ships", {})
    if ships is Dictionary:
        for id in ships:
            var row: Variant = ships[id]
            if row is Dictionary and str(row.get("system_id", "")) == str(
                    _world.get("system", {}).get("id", "")):
                signature += ":" + str(id)
    if signature == _outliner_signature:
        return
    _outliner_signature = signature
    for child in _outliner_list.get_children():
        _outliner_list.remove_child(child)
        child.queue_free()
    _group("ПЛАНЕТЫ И СПУТНИКИ")
    for body in _world.get("bodies", []):
        if body is Dictionary:
            var id: String = str(body.get("id", ""))
            _outliner_entry("◉ " + str(body.get("name", id)),
                _select_body.bind(id), id == _body)
    _group("СТАНЦИИ И ПРЕДПРИЯТИЯ")
    for facility in _world.get("facilities", []):
        if facility is Dictionary:
            var id: String = str(facility.get("id", ""))
            _outliner_entry("⌑ " + str(facility.get("name", id)),
                _select_facility.bind(id), id == _facility)
    _group("КОРАБЛИ В СИСТЕМЕ")
    if ships is Dictionary:
        var n: int = 0
        for id in ships:
            var item: Variant = ships[id]
            if not (item is Dictionary) or str(item.get("system_id", "")) != str(
                    _world.get("system", {}).get("id", "")):
                continue
            _outliner_entry("➤ " + str(item.get("name", id)),
                _select_ship.bind(str(id)), str(id) == _ship)
            n += 1
            if n >= 16:
                _outliner_list.add_child(_label("Остальные корабли — в разделе «Флот»", 11, MUTED))
                break
    _outliner_list.add_child(_label("Источник: действующий World / N39", 10, MUTED))

func _tabs_for_mode() -> Array[String]:
    if _window_mode in ["colony", "facility"]:
        return ["Обзор", "Производство", "Данные"]
    if _window_mode == "economy":
        return ["Запасы", "Производство", "Данные"]
    return ["Обзор", "Данные"]

func _switch_tab(name: String) -> void:
    _tab = name
    _update_window()

func _update_window() -> void:
    if _window == null or not _window.visible:
        return
    var title: String = {
        "colony":"КОЛОНИЯ", "economy":"ЭКОНОМИКА СЕКТОРА",
        "fleet":"ФЛОТ И ЛОГИСТИКА", "facility":"ПРЕДПРИЯТИЕ",
        "ship":"КОРАБЛЬ", "technical":"ДАННЫЕ N39"
    }.get(_window_mode, "ОБЗОР")
    _window_title.text = title + ((" · " + _body) if _window_mode == "colony" else "")
    var tabs: Array[String] = _tabs_for_mode()
    for child in _window_tabs.get_children():
        _window_tabs.remove_child(child)
        child.queue_free()
    for name in tabs:
        var btn := _button(name, _switch_tab.bind(name))
        if name == _tab:
            btn.add_theme_stylebox_override("normal", _style(BG2, TEAL))
            btn.add_theme_color_override("font_color", TEAL)
        _window_tabs.add_child(btn)
    if _tab == "Данные" or _window_mode == "technical":
        _window_text.text = _diagnostic_text if not _diagnostic_text.is_empty() else _status_text
    elif _window_mode == "fleet" or _window_mode == "ship":
        var lines: Array[String] = ["РЕАЛЬНЫЕ КОРАБЛИ В СНИМКЕ"]
        var ships: Variant = _economy.get("ships", {})
        if ships is Dictionary:
            for id in ships:
                var ship: Variant = ships[id]
                if ship is Dictionary and (_window_mode == "fleet" or str(id) == _ship):
                    lines.append("%s · %s · груз: %s" % [
                        str(ship.get("name", id)),
                        str(ship.get("location", "—")),
                        str(ship.get("cargo", "—"))])
        _window_text.text = "\n\n".join(lines)
    elif _tab == "Производство":
        _window_text.text = _production_text()
    else:
        var projection: Dictionary = _quantities()
        var quantities: Dictionary = projection["values"]
        var present: Dictionary = projection["present"]
        var lines: Array[String] = [
            "ОБЛАСТЬ УЧЁТА: " + ("КОЛОНИЯ " + _body if _mode == "colony"
                else "ВСЕ РЫНКИ СЕКТОРА (все фракции)"),
            "", "ТЕКУЩИЕ ЗАПАСЫ"
        ]
        for item in METRICS:
            var key: String = str(item["key"])
            lines.append("%s: %s" % [str(item["label"]),
                str(roundi(float(quantities.get(key, 0.0))))
                if present.has(key) else "—"])
        lines.append("")
        lines.append("Показаны только подтверждённые рыночные запасы и население.")
        lines.append("Скорости производства и прогнозы здесь не выдумываются.")
        _window_text.text = "\n".join(lines)

func _production_text() -> String:
    var lines: Array[String] = ["ПРЕДПРИЯТИЯ · ЖИВОЙ СНИМОК N39", ""]
    var live: Variant = _economy.get("facilities", {})
    var found: bool = false
    for facility in _world.get("facilities", []):
        if not (facility is Dictionary):
            continue
        if _window_mode == "colony" and str(facility.get("body", "")) != _body:
            continue
        if _window_mode == "facility" and str(facility.get("id", "")) != _facility:
            continue
        found = true
        var id: String = str(facility.get("id", ""))
        lines.append(str(facility.get("name", id)))
        lines.append("  Тип: %s · владелец: %s" % [
            str(facility.get("type", "—")),
            str(facility.get("faction_id", "—"))])
        if live is Dictionary and live.get(id) is Dictionary:
            var row: Dictionary = live[id]
            var shift: Variant = row.get("work_shift", {})
            lines.append("  Работники: %s · состояние: %s" % [
                str(row.get("assigned_workers", "—")),
                str(row.get("condition", "—"))])
            if shift is Dictionary:
                lines.append("  Последняя смена: %s · зарплата: %s" % [
                    str(shift.get("tick", "—")), str(shift.get("wages", "—"))])
            var stock: Variant = row.get("module_stock", {}).get("stock", {})
            if stock is Dictionary:
                lines.append("  Склад: %s" % str(stock))
        else:
            lines.append("  Живое состояние недоступно")
        lines.append("")
    if not found:
        lines.append("Для выбранного объекта нет подтверждённых предприятий.")
    return "\n".join(lines)

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _close_window()
