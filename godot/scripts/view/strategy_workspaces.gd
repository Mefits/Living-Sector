extends VBoxContainer
## Living Sector — seven Figma Make management workspaces, native Godot.
## Visual blueprint: Living-Sector-Game-Interface (React WorkspaceShell).
## Every live quantity is read from the ALREADY DETACHED N39 frame.
## No World snapshot, simulation writes, fake contracts or invented AI scores.
signal navigate_requested(mode: String, tab: String, focus: String)
signal select_requested(kind: String, id: String)
signal back_requested()
signal close_requested()

const ShipPresence = preload("res://scripts/view/ship_body_projection.gd")
const FacilityNames = preload("res://scripts/view/facility_labels_ru.gd")
const FigmaIcons = preload("res://scripts/view/figma_strategy_icons.gd")
const BG = Color("#071019")
const SURFACE = Color("#0D1B24")
const DEEP = Color("#09141C")
const LINE = Color("#243942")
const TEAL = Color("#53B5AC")
const TEXT = Color("#C4D0D3")
const MUTED = Color("#748B92")
const AMBER = Color("#C99B54")
const BAD = Color("#CF856A")
const TABS: Dictionary = {
    "colony": ["Обзор", "Население", "Производство", "Запасы",
        "Строительство", "Логистика"],
    "facility": ["Процесс", "Работники", "Склад", "Поставщики"],
    "economy": ["Баланс", "Цепочки", "Дефициты", "Узкие места"],
    "construction": ["Проекты", "Материалы", "Поставщики", "Блокировки"],
    "fleet": ["Корабли", "Контракты", "Грузы", "Маршруты", "Стыковка", "Поставки"],
    "administration": ["Приоритеты ИИ", "План действий", "Обоснование", "Последствия"],
    "research": ["Прогресс", "Предпосылки", "Открытия"],
    "ship": ["Обзор", "Груз", "Маршрут"],
    "technical": ["Данные"]
}
const TITLES: Dictionary = {
    "colony": "КОЛОНИЯ", "facility": "ПРЕДПРИЯТИЕ",
    "economy": "ЭКОНОМИКА СЕКТОРА", "construction": "СТРОИТЕЛЬСТВО",
    "fleet": "ФЛОТ И ЛОГИСТИКА", "administration": "АВТОНОМНОЕ УПРАВЛЕНИЕ",
    "research": "ИССЛЕДОВАНИЯ", "ship": "КОРАБЛЬ",
    "technical": "ТЕХНИЧЕСКИЕ ДАННЫЕ"
}
var _mode: String = ""
var _tab: String = ""
var _world: Dictionary = {}
var _economy: Dictionary = {}
var _body: String = ""
var _facility: String = ""
var _ship: String = ""
var _focus: String = ""
var _tick: int = 0
var _debug_text: String = ""
var _header_title: Label
var _close_button: Button
var _back_button: Button
var _header_icon: TextureRect
var _scope: Label
var _focus_badge: Label
var _tabs: HBoxContainer
var _tabs_scroll: ScrollContainer
var _tabs_signature: String = ""
var _filter: LineEdit
var _updated: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _last_signature: String = ""
var _last_render_ms: int = -1
var _scroll_by_page: Dictionary = {}

func _box(fill: Color = SURFACE, outlined: bool = true) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = LINE
    if outlined:
        style.set_border_width_all(1)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 10
    style.content_margin_bottom = 10
    style.anti_aliasing = false
    return style

func _label(value: String, size_px: int = 14,
        tone: Color = TEXT) -> Label:
    var control := Label.new()
    control.text = value
    control.add_theme_font_size_override("font_size", size_px)
    control.add_theme_color_override("font_color", tone)
    control.clip_text = true
    control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return control

func _button(value: String, action: Callable = Callable(),
        prominent: bool = false) -> Button:
    var control := Button.new()
    control.text = value
    control.focus_mode = Control.FOCUS_NONE
    control.add_theme_font_size_override("font_size", 13)
    control.add_theme_color_override("font_color", TEAL if prominent else TEXT)
    control.add_theme_color_override("font_hover_color", TEAL)
    control.add_theme_stylebox_override("normal",
        _box(Color("#122631"), false))
    control.add_theme_stylebox_override("hover",
        _box(Color("#18343B"), true))
    control.add_theme_stylebox_override("pressed",
        _box(Color("#1F4248"), true))
    control.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, false))
    if action.is_valid():
        control.pressed.connect(action)
    else:
        control.disabled = true
    return control

func _hline() -> HSeparator:
    var rule := HSeparator.new()
    rule.add_theme_color_override("separator", LINE)
    return rule

func _clear(parent: Node) -> void:
    for child in parent.get_children():
        parent.remove_child(child)
        child.queue_free()

func _ready() -> void:
    add_theme_constant_override("separation", 0)
    mouse_filter = Control.MOUSE_FILTER_STOP
    # Figma Make WorkspaceShell: 49px title / 37px tabs / 35px toolbar.
    # No Godot default margins grow the management window vertically.
    var header_bg := PanelContainer.new()
    var header_style := _box(Color("#152C35"), false)
    header_style.border_width_bottom = 1
    header_style.border_color = Color("#35515A")
    header_style.set_content_margin_all(0)
    header_bg.add_theme_stylebox_override("panel", header_style)
    add_child(header_bg)
    var header := HBoxContainer.new()
    header.custom_minimum_size.y = 49
    header.add_theme_constant_override("separation", 0)
    header_bg.add_child(header)
    _back_button = _button("‹", func() -> void: back_requested.emit())
    _back_button.custom_minimum_size = Vector2(42, 49)
    _back_button.add_theme_font_size_override("font_size", 24)
    _back_button.tooltip_text = "Назад к предыдущему окну"
    _back_button.disabled = true
    header.add_child(_back_button)
    var icon_frame := PanelContainer.new()
    icon_frame.custom_minimum_size = Vector2(31, 31)
    icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var icon_style := _box(Color("#0B2029"))
    icon_style.border_color = Color("#33555B")
    icon_style.set_content_margin_all(5)
    icon_frame.add_theme_stylebox_override("panel", icon_style)
    header.add_child(icon_frame)
    _header_icon = TextureRect.new()
    _header_icon.custom_minimum_size = Vector2(19, 19)
    _header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _header_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    _header_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_frame.add_child(_header_icon)
    var titles := VBoxContainer.new()
    titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    titles.add_theme_constant_override("separation", 2)
    var title_margin := MarginContainer.new()
    title_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title_margin.add_theme_constant_override("margin_left", 9)
    title_margin.add_theme_constant_override("margin_right", 6)
    header.add_child(title_margin)
    title_margin.add_child(titles)
    _scope = _label("СЕКТОР / ОБЗОР", 9, Color("#627E83"))
    _header_title = _label("КОЛОНИЯ", 14, Color("#D2DDDD"))
    titles.add_child(_scope)
    titles.add_child(_header_title)
    _focus_badge = _label("", 9, AMBER)
    _focus_badge.visible = false
    _focus_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var tag_style := _box(Color("#201B14"), false)
    tag_style.border_color = Color("#594A31")
    tag_style.set_border_width_all(1)
    tag_style.set_content_margin_all(5)
    _focus_badge.add_theme_stylebox_override("normal", tag_style)
    header.add_child(_focus_badge)
    _close_button = _button("✕", func() -> void: close_requested.emit())
    _close_button.custom_minimum_size = Vector2(42, 49)
    _close_button.tooltip_text = "Закрыть окно"
    _close_button.mouse_filter = Control.MOUSE_FILTER_STOP
    header.add_child(_close_button)

    # Figma uses one horizontal tab strip. HFlowContainer previously wrapped
    # six Fleet tabs onto a second row and moved all content down.
    _tabs_scroll = ScrollContainer.new()
    _tabs_scroll.custom_minimum_size.y = 37
    _tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    _tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tabs_scroll.add_theme_stylebox_override("panel", _box(Color("#09151D"), false))
    add_child(_tabs_scroll)
    _tabs = HBoxContainer.new()
    _tabs.add_theme_constant_override("separation", 0)
    _tabs_scroll.add_child(_tabs)

    var toolbar_bg := PanelContainer.new()
    var toolbar_style := _box(Color("#0A161D"), false)
    toolbar_style.border_width_bottom = 1
    toolbar_style.border_color = Color("#1E343B")
    toolbar_style.content_margin_left = 8
    toolbar_style.content_margin_right = 8
    toolbar_style.content_margin_top = 3
    toolbar_style.content_margin_bottom = 3
    toolbar_bg.add_theme_stylebox_override("panel", toolbar_style)
    add_child(toolbar_bg)
    var toolbar := HBoxContainer.new()
    toolbar.custom_minimum_size.y = 29
    toolbar.add_theme_constant_override("separation", 8)
    toolbar_bg.add_child(toolbar)
    var search_box := PanelContainer.new()
    search_box.custom_minimum_size.x = 0
    search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var search_style := _box(Color("#071218"), false)
    search_style.set_border_width_all(1)
    search_style.border_color = Color("#273E45")
    search_style.content_margin_left = 7
    search_style.content_margin_right = 5
    search_style.content_margin_top = 2
    search_style.content_margin_bottom = 2
    search_box.add_theme_stylebox_override("panel", search_style)
    toolbar.add_child(search_box)
    var search_row := HBoxContainer.new()
    search_row.add_theme_constant_override("separation", 5)
    search_box.add_child(search_row)
    var search_icon := TextureRect.new()
    search_icon.custom_minimum_size = Vector2(16, 16)
    search_icon.texture = FigmaIcons.texture("search", 14, MUTED)
    search_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    search_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    search_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    search_row.add_child(search_icon)
    _filter = LineEdit.new()
    _filter.placeholder_text = "Фильтр по объектам и статусам"
    _filter.custom_minimum_size.x = 0
    _filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _filter.add_theme_font_size_override("font_size", 10)
    _filter.add_theme_color_override("font_color", TEXT)
    _filter.add_theme_color_override("font_placeholder_color", MUTED)
    var transparent_style := _box(Color.TRANSPARENT, false)
    transparent_style.set_content_margin_all(0)
    _filter.add_theme_stylebox_override("normal", transparent_style)
    _filter.add_theme_stylebox_override("focus", transparent_style)
    _filter.text_changed.connect(func(_value: String) -> void:
        _last_signature = ""
        _render())
    search_row.add_child(_filter)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toolbar.add_child(spacer)
    _updated = _label("ЦИКЛ — · N39", 10, Color("#58747B"))
    _updated.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    toolbar.add_child(_updated)
    # Under high UI scaling the available workspace can be narrower than the
    # Figma desktop mock. Keep the search usable instead of clipping its text.
    resized.connect(_fit_toolbar)
    _fit_toolbar()
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_scroll)
    var page_padding := MarginContainer.new()
    page_padding.add_theme_constant_override("margin_left", 9)
    page_padding.add_theme_constant_override("margin_top", 9)
    page_padding.add_theme_constant_override("margin_right", 9)
    page_padding.add_theme_constant_override("margin_bottom", 9)
    page_padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.add_child(page_padding)
    _content = VBoxContainer.new()
    _content.add_theme_constant_override("separation", 8)
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_padding.add_child(_content)

func _fit_toolbar() -> void:
    if _updated == null:
        return
    # The tick remains visible in the global HUD on compact windows.
    # Removing this secondary label preserves space for the live filter.
    _updated.visible = size.x >= 500.0


func set_can_go_back(can_go_back: bool) -> void:
    if _back_button != null:
        _back_button.disabled = not can_go_back

func tabs_for(mode: String) -> Array:
    return TABS.get(mode, ["Данные"])

func show_state(mode: String, tab: String, world: Dictionary,
        economy: Dictionary, body: String, facility: String,
        ship: String, tick: int, focus: String = "",
        debug_text: String = "") -> void:
    var prior_mode: String = _mode
    var prior_tab: String = _tab
    var prior_body: String = _body
    var prior_facility: String = _facility
    var prior_ship: String = _ship
    _mode = mode
    _tab = tab if tab in tabs_for(mode) else str(tabs_for(mode)[0])
    _world = world
    _economy = economy
    _body = body
    _facility = facility
    _ship = ship
    _tick = tick
    _focus = focus
    _debug_text = debug_text
    var changed: bool = (prior_mode != mode or prior_tab != _tab or
        prior_body != body or prior_facility != facility or prior_ship != ship)
    if changed:
        _last_signature = ""
        if _scroll != null:
            var old_page: String = "%s|%s|%s|%s|%s" % [
                prior_mode, prior_tab, prior_body, prior_facility, prior_ship]
            _scroll_by_page[old_page] = _scroll.scroll_vertical
        if _filter != null and not _filter.text.is_empty():
            _filter.clear()
    var signature: String = "%s|%s|%s|%s|%s|%s|%d" % [
        _mode, _tab, _body, _facility, _ship, _focus, tick]
    if signature == _last_signature:
        return
    # Rendering a window is not a paid game phase. At a stable selection
    # rebuild at most every 0.8 seconds even if N158 advances rapidly.
    var now: int = Time.get_ticks_msec()
    if not changed and _last_render_ms >= 0 and now - _last_render_ms < 800:
        return
    _last_render_ms = now
    _last_signature = signature
    _render()
    if changed and _scroll != null:
        var page_key: String = "%s|%s|%s|%s|%s" % [
            _mode, _tab, _body, _facility, _ship]
        var restore: int = int(_scroll_by_page.get(page_key, 0))
        # Scroll ranges only settle after controls lay out.
        call_deferred("_restore_workspace_scroll", page_key, restore)

func _restore_workspace_scroll(page_key: String, offset: int) -> void:
    if _scroll == null:
        return
    var current: String = "%s|%s|%s|%s|%s" % [
        _mode, _tab, _body, _facility, _ship]
    if current != page_key:
        return
    _scroll.scroll_vertical = offset

func _render() -> void:
    if _content == null:
        return
    var section_name: String = str(TITLES.get(_mode, _mode))
    _header_title.text = ( _body_name() if _mode == "colony" else (
        _facility_name() if _mode == "facility" else (
        _ship_name() if _mode == "ship" else section_name)))
    if _header_icon != null:
        _header_icon.texture = FigmaIcons.texture(
            "colony" if _mode == "colony" else (
            "facility" if _mode == "facility" else (
            "fleet" if _mode == "ship" else _mode)), 24, TEAL)
    var location: String = str(_world.get("system", {}).get("name", "Сектор"))
    if _mode == "colony":
        location += " / " + _body_name()
    elif _mode == "facility":
        location += " / " + _facility_name()
    elif _mode == "ship":
        location += " / " + _ship_name()
    _scope.text = "СЕКТОР " + str(
        _world.get("system", {}).get("name", "—")).to_upper() + (
        "   /   " + section_name)
    _updated.text = "ОБНОВЛЕНО: ТИК %d · N39" % _tick
    _focus_badge.visible = not _focus.is_empty()
    _focus_badge.text = "ФОКУС: " + _focus
    _focus_badge.tooltip_text = _focus
    var tab_signature: String = _mode + "|" + _tab
    if tab_signature != _tabs_signature:
        _tabs_signature = tab_signature
        _clear(_tabs)
        for name in tabs_for(_mode):
            var tab_name: String = str(name)
            var active: bool = tab_name == _tab
            var tab_btn: Button = _tab_button(tab_name, active)
            _tabs.add_child(tab_btn)
            if active:
                # Resolve by current mode/tab when the frame is laid out,
                # never hold a soon-to-be freed Button in a deferred call.
                call_deferred("_reveal_active_tab", _mode, _tab)
    _clear(_content)
    match _mode:
        "colony": _colony()
        "facility": _facility_workspace()
        "economy": _economy_workspace()
        "construction": _construction_workspace()
        "fleet": _fleet_workspace()
        "administration": _administration_workspace()
        "research": _research_workspace()
        "ship": _ship_workspace()
        "technical": _technical_workspace()
        _: _empty("Этот раздел пока не подключён.")

func _reveal_active_tab(mode: String, tab: String) -> void:
    if mode != _mode or tab != _tab or _tabs_scroll == null:
        return
    for child in _tabs.get_children():
        if child is Button and child.text == tab:
            _tabs_scroll.ensure_control_visible(child)
            return

func _tab_button(name: String, active: bool) -> Button:
    var btn := _button(name, func() -> void:
        navigate_requested.emit(_mode, name, _focus), active)
    btn.add_theme_font_size_override("font_size", 10)
    var normal := _box(Color("#11242C") if active else Color("#09151D"), false)
    normal.border_color = TEAL if active else LINE
    normal.border_width_bottom = 2 if active else 1
    normal.content_margin_left = 13
    normal.content_margin_right = 13
    normal.content_margin_top = 8
    normal.content_margin_bottom = 8
    btn.add_theme_stylebox_override("normal", normal)
    var hover := _box(Color("#102129"), false)
    hover.border_color = TEAL
    hover.border_width_bottom = 2
    hover.content_margin_left = 13
    hover.content_margin_right = 13
    hover.content_margin_top = 8
    hover.content_margin_bottom = 8
    btn.add_theme_stylebox_override("hover", hover)
    btn.custom_minimum_size.y = 36
    btn.add_theme_color_override("font_color",
        Color("#A6D8D3") if active else Color("#668087"))
    btn.tooltip_text = name
    return btn

# Every workspace uses the same Figma section header (31px) and body
# padding. The optional host supports the two-column colony overview.
func _section(title: String, detail: String = "", host: Node = null) -> VBoxContainer:
    var card := PanelContainer.new()
    var style := _box(Color("#0B1921"))
    style.border_color = Color("#263E45")
    style.set_content_margin_all(0)
    card.add_theme_stylebox_override("panel", style)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if host is HFlowContainer:
        card.custom_minimum_size.x = 300
    if host == null:
        _content.add_child(card)
    else:
        host.add_child(card)
    var shell := VBoxContainer.new()
    shell.add_theme_constant_override("separation", 0)
    card.add_child(shell)
    var title_bg := PanelContainer.new()
    var title_style := _box(Color("#0D1E26"), false)
    title_style.border_color = Color("#22383F")
    title_style.border_width_bottom = 1
    title_style.content_margin_left = 9
    title_style.content_margin_right = 9
    title_style.content_margin_top = 0
    title_style.content_margin_bottom = 0
    title_bg.add_theme_stylebox_override("panel", title_style)
    shell.add_child(title_bg)
    var heading_row := HBoxContainer.new()
    heading_row.custom_minimum_size.y = 31
    heading_row.add_theme_constant_override("separation", 7)
    title_bg.add_child(heading_row)
    var heading := _label(title, 11, Color("#B9C8C9"))
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    heading_row.add_child(heading)
    if not detail.is_empty():
        var right_detail := _label(detail, 9, MUTED)
        right_detail.size_flags_horizontal = Control.SIZE_SHRINK_END
        right_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        right_detail.tooltip_text = detail
        heading_row.add_child(right_detail)
    var padding := MarginContainer.new()
    padding.add_theme_constant_override("margin_left", 9)
    padding.add_theme_constant_override("margin_right", 9)
    padding.add_theme_constant_override("margin_top", 7)
    padding.add_theme_constant_override("margin_bottom", 9)
    shell.add_child(padding)
    var inside := VBoxContainer.new()
    inside.add_theme_constant_override("separation", 6)
    padding.add_child(inside)
    return inside

func _note(parent: Node, value: String, tone: Color = MUTED) -> void:
    var control := _label(value, 13, tone)
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(control)

func _pair(parent: Node, name: String, value: String,
        tone: Color = TEXT) -> void:
    if not _match(name + " " + value):
        return
    var row_bg := PanelContainer.new()
    var row_style := _box(Color("#0B1B24"), false)
    row_style.border_width_top = 1
    row_style.border_color = Color("#1D3138")
    row_style.content_margin_left = 7
    row_style.content_margin_right = 7
    row_style.content_margin_top = 3
    row_style.content_margin_bottom = 3
    row_bg.add_theme_stylebox_override("panel", row_style)
    parent.add_child(row_bg)
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 23
    row.add_theme_constant_override("separation", 12)
    row_bg.add_child(row)
    var key := _label(name, 11, MUTED)
    key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(key)
    var answer := _label(value, 12, tone)
    answer.tooltip_text = value
    answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(answer)

func _metric_strip(parent: Node, pairs: Array) -> void:
    # Figma uses a 4-up metric strip; HFlow wraps to two columns on
    # narrow window sizes without hiding real N39 values.
    var flow := HFlowContainer.new()
    flow.add_theme_constant_override("h_separation", 0)
    flow.add_theme_constant_override("v_separation", 4)
    parent.add_child(flow)
    for item in pairs:
        if not (item is Dictionary):
            continue
        var tile := PanelContainer.new()
        var tile_style := _box(Color("#0D1F27"), false)
        tile_style.border_width_right = 1
        tile_style.border_color = Color("#20373F")
        tile_style.content_margin_left = 10
        tile_style.content_margin_right = 9
        tile_style.content_margin_top = 6
        tile_style.content_margin_bottom = 6
        tile.add_theme_stylebox_override("panel", tile_style)
        tile.custom_minimum_size = Vector2(138, 59)
        tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        flow.add_child(tile)
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 3)
        tile.add_child(col)
        col.add_child(_label(str(item.get("label", "—")).to_upper(), 9, MUTED))
        col.add_child(_label(str(item.get("value", "—")), 17, Color("#D5E0E0")))
        if item.has("note") and not str(item["note"]).is_empty():
            col.add_child(_label(str(item["note"]), 9, TEAL))

func _table(parent: Node, headings: Array, rows: Array,
        route: String = "", tab: String = "", kind: String = "") -> void:
    var columns: int = maxi(1, headings.size())
    # All rows must share one column grid. Individual auto-sized HBoxes
    # caused headings and values to drift, especially in Fleet/Economy.
    # Scroll horizontally on compact viewports rather than crop N39 data.
    var scroller := ScrollContainer.new()
    scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(scroller)
    var grid_body := VBoxContainer.new()
    grid_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid_body.custom_minimum_size.x = 178.0 + 118.0 * float(columns - 1)
    grid_body.add_theme_constant_override("separation", 0)
    scroller.add_child(grid_body)
    _table_row(grid_body, headings, columns, true, Callable())
    var shown: int = 0
    for item in rows:
        if not (item is Dictionary):
            continue
        var cells: Array = item.get("cells", [])
        if not _match(" ".join(PackedStringArray(cells.map(
                func(v): return str(v))))):
            continue
        var callback := Callable()
        if not kind.is_empty() and not str(item.get("id", "")).is_empty():
            var source_id: String = str(item["id"])
            callback = func() -> void:
                select_requested.emit(kind, source_id)
        elif not route.is_empty():
            callback = func() -> void:
                navigate_requested.emit(route, tab, str(item.get("id", "")))
        _table_row(grid_body, cells, columns, false, callback, shown)
        shown += 1
        if shown >= 60:
            _note(parent, "Показаны первые 60 записей. Используйте поиск.")
            break
    if shown == 0:
        _note(parent, "Нет подтверждённых записей для выбранного раздела.")

func _table_row(parent: Node, cells: Array, columns: int,
        heading: bool, callback: Callable, row_index: int = 0) -> void:
    var container: Control
    var fill: Color = Color("#08151C") if heading else (
        Color("#0D2029") if row_index % 2 == 0 else Color("#0B1B24"))
    if callback.is_valid():
        var btn := Button.new()
        btn.flat = true
        btn.focus_mode = Control.FOCUS_NONE
        btn.pressed.connect(callback)
        var normal := _box(fill, false)
        normal.border_width_bottom = 1
        normal.border_color = Color("#213943")
        normal.content_margin_left = 9
        normal.content_margin_right = 9
        normal.content_margin_top = 3 if heading else 6
        normal.content_margin_bottom = 3 if heading else 6
        btn.add_theme_stylebox_override("normal", normal)
        var hover := _box(Color("#1B3740"), false)
        hover.border_color = TEAL
        hover.border_width_bottom = 1
        btn.add_theme_stylebox_override("hover", hover)
        btn.add_theme_stylebox_override("pressed",
            _box(Color("#23505A"), true))
        parent.add_child(btn)
        container = btn
    else:
        var panel := PanelContainer.new()
        var cell_style := _box(fill, false)
        cell_style.border_width_bottom = 1
        cell_style.border_color = Color("#213943")
        cell_style.content_margin_left = 9
        cell_style.content_margin_right = 9
        cell_style.content_margin_top = 3 if heading else 6
        cell_style.content_margin_bottom = 3 if heading else 6
        panel.add_theme_stylebox_override("panel", cell_style)
        parent.add_child(panel)
        container = panel
    # Figma dense-head is 25px, data rows 34px; no vertical box drift.
    container.custom_minimum_size.y = 25 if heading else 34
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.custom_minimum_size.y = 15 if heading else 20
    row.add_theme_constant_override("separation", 7)
    container.add_child(row)
    for i in range(columns):
        var text_value: String = str(cells[i]) if i < cells.size() else "—"
        var tint: Color = MUTED if heading else TEXT
        if not heading and i > 0:
            var lower: String = text_value.to_lower()
            if lower.contains("нет ") or lower.contains("износ") or (
                    lower.contains("заброш") or lower.contains("блокир")):
                tint = BAD
            elif lower.contains("в пути") or lower.contains("строится"):
                tint = TEAL
            elif text_value == "—":
                tint = MUTED
        var cell := _label(text_value, 9 if heading else 12, tint)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # Identical minimums for header and every data row make the columns
        # line up while leaving room for long names and real N39 statuses.
        cell.custom_minimum_size.x = 150.0 if i == 0 else 90.0
        cell.size_flags_stretch_ratio = 1.5 if i == 0 else 1.0
        cell.tooltip_text = text_value
        row.add_child(cell)

func _link(parent: Node, label: String,
        mode: String, tab: String, focus: String = "") -> void:
    var action := _button(label, func() -> void:
        navigate_requested.emit(mode, tab, focus), true)
    action.alignment = HORIZONTAL_ALIGNMENT_LEFT
    action.custom_minimum_size.y = 29
    action.add_theme_font_size_override("font_size", 10)
    var normal := _box(Color("#0D1E26"), false)
    normal.border_width_top = 1
    normal.border_color = Color("#294049")
    normal.content_margin_left = 9
    normal.content_margin_right = 9
    normal.content_margin_top = 4
    normal.content_margin_bottom = 4
    action.add_theme_stylebox_override("normal", normal)
    var hover := _box(Color("#132D34"), false)
    hover.border_width_top = 1
    hover.border_color = TEAL
    hover.content_margin_left = 9
    hover.content_margin_right = 9
    hover.content_margin_top = 4
    hover.content_margin_bottom = 4
    action.add_theme_stylebox_override("hover", hover)
    action.tooltip_text = "Открыть раздел «%s» → %s" % [
        str(TITLES.get(mode, mode)), tab]
    parent.add_child(action)

func _issue_line(parent: Node, headline: String, description: String,
        on_open: Callable, critical: bool = true) -> void:
    # Figma .issue-line: native 47px clickable alert with icon, two lines
    # and a compact action on the right. Values come from N39 only.
    var button := Button.new()
    button.text = ""
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size.y = 49
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.tooltip_text = headline + "\n" + description
    var base := _box(Color("#201A14") if critical else Color("#0D2029"), false)
    base.border_width_top = 1
    base.border_color = Color("#59442D") if critical else Color("#20343B")
    base.set_content_margin_all(0)
    button.add_theme_stylebox_override("normal", base)
    var hover := _box(Color("#2B241A") if critical else Color("#173038"), false)
    hover.border_width_top = 1
    hover.border_color = AMBER if critical else TEAL
    hover.set_content_margin_all(0)
    button.add_theme_stylebox_override("hover", hover)
    if on_open.is_valid():
        button.pressed.connect(on_open)
    else:
        button.disabled = true
    parent.add_child(button)
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_theme_constant_override("separation", 8)
    button.add_child(row)
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 9
    row.offset_right = -9
    row.offset_top = 5
    row.offset_bottom = -5
    var icon := TextureRect.new()
    icon.custom_minimum_size = Vector2(18, 18)
    icon.texture = FigmaIcons.texture("alert" if critical else "facility",
        17, AMBER if critical else TEAL)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(icon)
    var labels := VBoxContainer.new()
    labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    labels.add_theme_constant_override("separation", 2)
    labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(labels)
    labels.add_child(_label(headline, 11, Color("#D4C4A7") if critical else TEXT))
    labels.add_child(_label(description, 9, MUTED))
    if on_open.is_valid():
        var go := _label("ОТКРЫТЬ  ›", 9, AMBER if critical else TEAL)
        go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(go)

func _empty(message: String) -> void:
    var block := _section("ДАННЫЕ НЕДОСТУПНЫ")
    _note(block, message)
    _note(block, "Демо-значения Figma намеренно не подставляются в живую экономику.")

func _match(value: String) -> bool:
    return _filter == null or _filter.text.strip_edges().is_empty() or (
        value.to_lower().contains(_filter.text.strip_edges().to_lower()))

func _body_id() -> String:
    if not _body.is_empty():
        return _body
    if not _facility.is_empty():
        for raw in _world.get("facilities", []):
            if raw is Dictionary and str(raw.get("id", "")) == _facility:
                return str(raw.get("body", ""))
    return ""

func _body_name() -> String:
    var id: String = _body_id()
    for raw in _world.get("bodies", []):
        if raw is Dictionary and str(raw.get("id", "")) == id:
            return str(raw.get("name", id))
    return id if not id.is_empty() else "Выберите планету"

func _facility_source() -> Dictionary:
    for raw in _world.get("facilities", []):
        if raw is Dictionary and str(raw.get("id", "")) == _facility:
            return raw
    return {}

func _facility_name() -> String:
    var f: Dictionary = _facility_source()
    return FacilityNames.display_name(f) if not f.is_empty() else "Выберите предприятие"

func _ship_source() -> Dictionary:
    var ships: Variant = _economy.get("ships", {})
    if ships is Dictionary and ships.get(_ship) is Dictionary:
        return ships[_ship]
    return {}

func _ship_name() -> String:
    return str(_ship_source().get("name", _ship))

func _locations(body_id: String) -> Dictionary:
    var result: Dictionary = {}
    for raw in _world.get("facilities", []):
        if raw is Dictionary and str(raw.get("body", "")) == body_id:
            result[str(raw.get("location", ""))] = true
    for raw in _world.get("nav_sites", []):
        if raw is Dictionary and str(raw.get("body", "")) == body_id:
            result[str(raw.get("name", ""))] = true
    return result

func _markets(body_id: String = "") -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var all: Variant = _economy.get("markets", {})
    if not (all is Dictionary):
        return result
    var locs: Dictionary = _locations(body_id)
    for key in all:
        if not body_id.is_empty() and not locs.has(str(key)):
            continue
        var market: Variant = all[key]
        if market is Dictionary:
            result.append({"location": str(key), "data": market})
    return result

func _stock_rows(body_id: String = "") -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    for market in _markets(body_id):
        var stock: Variant = market["data"].get("supply", {})
        if not (stock is Dictionary):
            continue
        for kind in stock:
            rows.append({"cells":[str(kind), str(stock[kind]),
                str(market["location"]), "—", "—"]})
    return rows

func _population(body_id: String) -> int:
    var total: int = 0
    var pops: Variant = _economy.get("populations", {})
    if not (pops is Dictionary):
        return -1
    var locs: Dictionary = _locations(body_id)
    for raw in pops.values():
        if raw is Dictionary and (body_id.is_empty() or
                locs.has(str(raw.get("location", "")))):
            total += int(raw.get("count", 0))
    return total

func _facility_rows(body_id: String = "") -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    var active: Variant = _economy.get("facilities", {})
    for raw in _world.get("facilities", []):
        if not (raw is Dictionary):
            continue
        var item: Dictionary = raw
        if not body_id.is_empty() and str(item.get("body", "")) != body_id:
            continue
        var id: String = str(item.get("id", ""))
        var live: Dictionary = (active.get(id, {})
            if active is Dictionary and active.get(id) is Dictionary else {})
        var count: String = str(live.get("assigned_workers", "—"))
        var condition: String = "—"
        var state: Variant = live.get("condition", null)
        if state is int or state is float:
            condition = "%.0f%%" % (float(state) * 100.0)
        rows.append({"id":id, "cells":[FacilityNames.display_name(item),
            FacilityNames.type_name(str(item.get("type", "—"))),
            count, condition, str(item.get("location", "—"))]})
    return rows

func _ship_rows() -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    var ships: Variant = _economy.get("ships", {})
    if not (ships is Dictionary):
        return rows
    for id in ships:
        var raw: Variant = ships[id]
        if not (raw is Dictionary):
            continue
        var ship: Dictionary = raw
        var route: Variant = ship.get("transit", {})
        var status: String = ("В ПУТИ" if route is Dictionary and
            not route.is_empty() else (
            "У ДОКА" if not str(ship.get("docked_at", "")).is_empty()
            else "БЕЗ РЕЙСА"))
        rows.append({"id":str(id), "cells":[str(ship.get("name", id)),
            str(ship.get("class", "—")), str(ship.get("current_goal", "—")),
            str(ship.get("cargo", {})), status]})
    return rows

func _construction_rows(body_id: String = "") -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    var sites: Variant = _economy.get("construction_sites", {})
    if not (sites is Dictionary):
        return rows
    var locations: Dictionary = _locations(body_id)
    for id in sites:
        var raw: Variant = sites[id]
        if not (raw is Dictionary):
            continue
        var row: Dictionary = raw
        var loc: String = str(row.get("location_name", row.get("location", "")))
        if not body_id.is_empty() and not locations.has(loc):
            continue
        rows.append({"id":str(id), "cells":[str(id), loc,
            str(row.get("progress", "—")),
            "Завершено" if bool(row.get("completed", false)) else "Строится",
            str(row.get("needed", row.get("requirements", "—")))]})
    return rows

func _colony() -> void:
    var body: String = _body_id()
    if body.is_empty():
        _empty("Выберите колонию в правом списке.")
        return
    match _tab:
        "Обзор":
            var overview := _section("СОСТОЯНИЕ КОЛОНИИ", _body_name())
            var facilities: Array[Dictionary] = _facility_rows(body)
            var ships: Array[Dictionary] = ShipPresence.ships_at_body(
                _world, _economy, body)
            var pops: int = _population(body)
            _metric_strip(overview, [
                {"label":"Население", "value":str(pops) if pops >= 0 else "—"},
                {"label":"Предприятия", "value":str(facilities.size())},
                {"label":"Корабли рядом", "value":str(ships.size())},
                {"label":"Стройки", "value":str(_construction_rows(body).size())}])
            var problem := _section("СОСТОЯНИЯ, ТРЕБУЮЩИЕ ВНИМАНИЯ")
            var problems: int = 0
            for raw in facilities:
                var id: String = str(raw["id"])
                var live: Variant = _economy.get("facilities", {}).get(id, {})
                if not (live is Dictionary):
                    continue
                var abandoned: bool = bool(live.get("abandoned", false))
                var worn: bool = (live.has("condition") and
                    float(live["condition"]) < 0.8)
                if not abandoned and not worn:
                    continue
                var title: String = str(raw["cells"][0])
                var status: String = ("Заброшено · подтверждено N39" if abandoned
                    else "Состояние %.0f%% · N39" % (
                        float(live["condition"]) * 100.0))
                _issue_line(problem, title, status,
                    func() -> void: select_requested.emit("facility", id))
                problems += 1
            if problems == 0:
                _note(problem,
                    "Подтверждённых сигналов износа нет. Остальные причины — в N39.")
            # Figma overview: two neighboring compact sections after the
            # full-width summary and alerts. HFlow stacks on small screens.
            var pair := HFlowContainer.new()
            pair.add_theme_constant_override("h_separation", 8)
            pair.add_theme_constant_override("v_separation", 8)
            _content.add_child(pair)
            var companies := _section("ПРЕДПРИЯТИЯ",
                "%d объектов" % facilities.size(), pair)
            var compact_facilities: Array[Dictionary] = []
            for entry in facilities:
                compact_facilities.append({"id":str(entry.get("id", "")),
                    "cells":[str(entry["cells"][0]),
                        str(entry["cells"][3])]})
            _table(companies, ["Объект", "Состояние"],
                compact_facilities, "", "", "facility")
            var next := _section("АВТОНОМНОЕ УПРАВЛЕНИЕ", "", pair)
            _note(next, "Приоритеты и решения — только при публикации данных ИИ.")
            _link(next, "ВСЕ РЕШЕНИЯ ›", "administration", "План действий")
        "Население":
            var panel := _section("НАСЕЛЕНИЕ И ТРУД")
            var lines: Array[Dictionary] = []
            var pops: Variant = _economy.get("populations", {})
            if pops is Dictionary:
                var local: Dictionary = _locations(body)
                for value in pops.values():
                    if value is Dictionary and local.has(str(value.get("location", ""))):
                        lines.append({"cells":[str(value.get("location", "—")),
                            str(value.get("count", "—")),
                            str(value.get("happiness", "—")),
                            str(value.get("growth", "—"))]})
            _table(panel, ["Локация","Жители","Довольство","Рост"], lines)
            var labor := _section("РАСПРЕДЕЛЕНИЕ РАБОТНИКОВ")
            _table(labor, ["Предприятие","Тип","Занято","Состояние","Локация"],
                _facility_rows(body), "", "", "facility")
        "Производство":
            _chain(body)
            var panel := _section("ПРЕДПРИЯТИЯ И СМЕНЫ")
            _table(panel, ["Объект","Тип","Работники","Состояние","Локация"],
                _facility_rows(body), "", "", "facility")
        "Запасы":
            var panel := _section("РЫНОЧНЫЕ ЗАПАСЫ", "Без выдуманных скоростей изменения")
            _table(panel, ["Товар","Количество","Рынок","Резерв","Тренд"],
                _stock_rows(body))
        "Строительство":
            _projects(body)
        "Логистика":
            _local_ships(body)

func _market_stock_total(key: String, body_id: String = "") -> Dictionary:
    # Snapshot-only aggregation. Missing commodity != zero or shortage;
    # stock quantities do NOT represent throughput, flow or a tick forecast.
    var present: bool = false
    var amount: float = 0.0
    var markets: int = 0
    for market in _markets(body_id):
        var stock: Variant = market["data"].get("supply", {})
        if not (stock is Dictionary) or not stock.has(key):
            continue
        var raw: Variant = stock[key]
        if not (raw is int or raw is float):
            continue
        present = true
        markets += 1
        amount += float(raw)
    return {"known":present, "amount":amount, "markets":markets}

func _select_chain_stock(key: String) -> void:
    # The card is an actionable resource filter, not a fictitious trade order.
    # Filtering the real stock ledger below makes the clicked stage inspectable.
    if _filter != null:
        var names: Dictionary = {
            "ore":"РУДА", "metals":"МЕТАЛЛЫ",
            "components":"КОМПОНЕНТЫ", "electronics":"ЭЛЕКТРОНИКА"}
        _filter.text = str(names.get(key, key))
        _last_signature = ""
        _render()

func _chain(body_id: String = "") -> void:
    var group := _section("ПРОИЗВОДСТВЕННАЯ ЦЕПОЧКА",
        "N39 · запасы, не производительность")
    var flow := HFlowContainer.new()
    flow.add_theme_constant_override("h_separation", 8)
    flow.add_theme_constant_override("v_separation", 8)
    group.add_child(flow)
    var entries: Array[Dictionary] = [
        {"key":"ore", "label":"РУДА", "stage":"ДОБЫЧА"},
        {"key":"metals", "label":"МЕТАЛЛЫ", "stage":"ПЕРЕРАБОТКА"},
        {"key":"components", "label":"КОМПОНЕНТЫ", "stage":"ПРОИЗВОДСТВО"},
        {"key":"electronics", "label":"ЭЛЕКТРОНИКА", "stage":"СБОРКА"}
    ]
    var rows: Array[Dictionary] = []
    for i in range(entries.size()):
        var stage: Dictionary = entries[i]
        var key: String = str(stage["key"])
        var current: Dictionary = _market_stock_total(key, body_id)
        var stock_text: String = (
            "%d ед." % roundi(float(current["amount"]))
            if bool(current["known"]) else "—")
        rows.append({"cells":[str(stage["label"]), stock_text,
            str(current["markets"]) if bool(current["known"]) else "—"]})
        # Figma .chain-flow: separate clickable process cards and arrow
        # gutters. Stock text is real, there are no mock production rates.
        var button := Button.new()
        button.text = ""
        button.custom_minimum_size = Vector2(147, 103)
        button.focus_mode = Control.FOCUS_NONE
        button.tooltip_text = "Показать подтверждённые запасы: " + str(
            stage["label"])
        button.pressed.connect(_select_chain_stock.bind(key))
        var style := _box(Color("#0B1D24"), true)
        style.border_color = Color("#2A484E")
        style.set_content_margin_all(0)
        button.add_theme_stylebox_override("normal", style)
        var hover := _box(Color("#122A31"), true)
        hover.border_color = TEAL
        hover.set_content_margin_all(0)
        button.add_theme_stylebox_override("hover", hover)
        button.add_theme_stylebox_override("pressed", hover)
        flow.add_child(button)
        var content := VBoxContainer.new()
        content.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.add_theme_constant_override("separation", 5)
        button.add_child(content)
        content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        content.offset_left = 10
        content.offset_right = -8
        content.offset_top = 9
        content.offset_bottom = -7
        content.add_child(_label(str(stage["stage"]), 9, MUTED))
        var icon := TextureRect.new()
        icon.custom_minimum_size = Vector2(20, 20)
        icon.texture = FigmaIcons.texture("facility", 18, TEAL)
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.add_child(icon)
        content.add_child(_label(str(stage["label"]), 11, TEXT))
        content.add_child(_label("На рынках: " + stock_text, 10,
            TEAL if bool(current["known"]) else MUTED))
        if i < entries.size() - 1:
            var arrow := _label("→", 20, Color("#54777A"))
            arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            flow.add_child(arrow)
    _note(group,
        "Стрелки обозначают технологические этапы. Реальные объёмы " +
        "выпуска, потребность и рейсы сюда не домысливаются.")
    var stock_section := _section("ЗАПАСЫ ПО ЭТАПАМ",
        "Сумма по опубликованным рынкам")
    _table(stock_section, ["Ресурс", "В наличии", "Рынков"], rows)
    var flow2 := _section("ДОСТУПНЫЕ ПРЕДПРИЯТИЯ")
    _table(flow2, ["Объект","Тип","Работники","Состояние","Локация"],
        _facility_rows(body_id), "", "", "facility")
    _note(flow2, "Выпуск за смену появится только из настоящих записей N39.")

func _local_ships(body_id: String) -> void:
    var rows: Array[Dictionary] = []
    for item in ShipPresence.ships_at_body(_world, _economy, body_id):
        rows.append({"id":str(item["id"]),
            "cells":[str(item["name"]), str(item["class"]),
                str(item["goal"]), str(item["location"]), str(item["status"])]})
    var panel := _section("КОРАБЛИ В ЛОКАЦИЯХ ПЛАНЕТЫ", "Посадка не предполагается")
    _table(panel, ["Корабль","Класс","Задача","Локация","Стыковка"],
        rows, "", "", "ship")
    var tip := _section("ФИЗИЧЕСКОЕ ДВИЖЕНИЕ")
    _note(tip, "Корабли в N14 transit не считаются уже прибывшими.")
    _link(tip, "ОТКРЫТЬ ВЕСЬ ФЛОТ ›", "fleet", "Корабли")

func _condition_bar(parent: Node, value: Variant) -> void:
    if not (value is int or value is float):
        return
    var level: float = float(value)
    if not is_finite(level) or level < 0.0 or level > 1.0:
        return
    var tint: Color = TEAL if level >= 0.8 else (
        AMBER if level >= 0.5 else BAD)
    var meter := ProgressBar.new()
    meter.min_value = 0.0
    meter.max_value = 1.0
    meter.value = level
    meter.show_percentage = false
    meter.custom_minimum_size.y = 9
    var back := _box(Color("#172D36"), false)
    back.set_content_margin_all(0)
    meter.add_theme_stylebox_override("background", back)
    var fill := _box(tint, false)
    fill.set_content_margin_all(0)
    meter.add_theme_stylebox_override("fill", fill)
    meter.tooltip_text = "N39: состояние %.1f%%" % (level * 100.0)
    parent.add_child(meter)

func _facility_workspace() -> void:
    var source: Dictionary = _facility_source()
    if source.is_empty():
        _empty("Выберите предприятие на карте или в аутлайнере.")
        return
    var all: Variant = _economy.get("facilities", {})
    var live: Dictionary = (all.get(_facility, {})
        if all is Dictionary and all.get(_facility) is Dictionary else {})
    match _tab:
        "Процесс":
            var section := _section("ПРОИЗВОДСТВЕННЫЙ ЦИКЛ", _facility_name())
            var flow := HFlowContainer.new()
            section.add_child(flow)
            for stage in ["ВХОДНЫЕ РЕСУРСЫ", "  →  ", "ПРЕДПРИЯТИЕ", "  →  ", "ПРОДУКЦИЯ"]:
                var tone: Color = TEAL if stage.contains("→") else TEXT
                flow.add_child(_label(stage, 14, tone))
            _pair(section, "Назначенные работники",
                str(live.get("assigned_workers", "—")))
            _pair(section, "Состояние объекта", str(live.get("condition", "—")))
            _condition_bar(section, live.get("condition", null))
            _pair(section, "Последняя оплаченная смена",
                str(live.get("work_shift", {}).get("tick", "—")))
            _note(section, "Точные входы, выпуск и причина простоя — только при наличии записи N39.")
            _link(section, "СКЛАД ОБЪЕКТА ›", "facility", "Склад", _facility)
        "Работники":
            var section := _section("РАБОТНИКИ И ОПЛАТА")
            _pair(section, "Назначено", str(live.get("assigned_workers", "—")))
            var shift: Variant = live.get("work_shift", {})
            if shift is Dictionary:
                _pair(section, "Тик последней смены", str(shift.get("tick", "—")))
                _pair(section, "Оплачено", str(shift.get("wages", "—")))
                _pair(section, "Работников в смене", str(shift.get("workers", "—")))
            _pair(section, "Износ / состояние", str(live.get("condition", "—")))
        "Склад":
            var section := _section("СКЛАД ПРЕДПРИЯТИЯ")
            var mod: Variant = live.get("module_stock", {})
            var stock: Variant = mod.get("stock", {}) if mod is Dictionary else {}
            var rows: Array[Dictionary] = []
            if stock is Dictionary:
                for key in stock:
                    rows.append({"cells":[str(key), str(stock[key]), "—", "—"]})
            _table(section, ["Товар","В наличии","Вход","Выход"], rows)
        "Поставщики":
            var section := _section("ПОСТАВЩИКИ И КОНТРАКТЫ")
            _pair(section, "Локация", str(source.get("location", "—")))
            _pair(section, "Фракция", str(source.get("faction_id", "—")))
            _note(section, "Не создаём обещанные поставки. Действительные контракты показаны во флоте.")
            _link(section, "ПОСМОТРЕТЬ КОНТРАКТЫ ›", "fleet", "Контракты")

func _economy_workspace() -> void:
    match _tab:
        "Баланс":
            var section := _section("БАЛАНС РЫНКОВ", "Все фракции, не кошелёк игрока")
            var rows: Array[Dictionary] = []
            for market in _markets():
                var stock: Variant = market["data"].get("supply", {})
                rows.append({"cells":[str(market["location"]),
                    str(stock.size()) if stock is Dictionary else "—",
                    str(market["data"].get("credits", "—")), "—"]})
            _table(section, ["Рынок","Товаров","Кредиты","Тренд"], rows)
            var links := _section("ПРОИЗВОДСТВЕННЫЕ ОБЪЕКТЫ")
            _table(links, ["Предприятие","Тип","Работники","Состояние","Локация"],
                _facility_rows(), "", "", "facility")
        "Цепочки":
            _chain()
            var link := _section("ПЕРЕХОДЫ")
            _link(link, "КОНТРАКТЫ И ДОСТАВКИ ›", "fleet", "Контракты")
        "Дефициты", "Узкие места":
            var section := _section(_tab.to_upper(), "Подтверждённые состояния N39")
            var rows: Array[Dictionary] = []
            var all: Variant = _economy.get("facilities", {})
            if all is Dictionary:
                for id in all:
                    var live: Variant = all[id]
                    if not (live is Dictionary):
                        continue
                    if bool(live.get("abandoned", false)) or (
                            live.has("condition") and float(live["condition"]) < 0.8):
                        rows.append({"id":str(id), "cells":[str(id),
                            "Заброшено" if bool(live.get("abandoned", false)) else "Износ",
                            str(live.get("condition", "—")), "—"]})
            _table(section, ["Объект","Сигнал","Состояние","Причина"], rows,
                "", "", "facility")
            _note(section, "Отсутствие опубликованных показателей спроса — не нулевой дефицит.")

func _projects(body_id: String = "") -> void:
    var section := _section("ФИЗИЧЕСКИЕ СТРОЙПЛОЩАДКИ",
        "Реальные записи construction_sites")
    _table(section, ["Проект","Локация","Прогресс","Статус","Материалы"],
        _construction_rows(body_id), "construction", "Материалы")
    _note(section, "Планы ИИ без созданной площадки здесь не считаются стройкой.")

func _construction_workspace() -> void:
    match _tab:
        "Проекты":
            _projects()
        "Материалы":
            var section := _section("МАТЕРИАЛЫ ПРОЕКТОВ")
            _table(section, ["Проект","Локация","Прогресс","Статус","Потребность"],
                _construction_rows())
            _link(section, "РЫНКИ И ДОСТУПНОСТЬ ›", "economy", "Баланс")
        "Поставщики":
            var section := _section("ПОСТАВЩИКИ СТРОИТЕЛЬСТВА")
            _note(section, "Подтверждённые рынки доступны ниже. Поставки не считаются обещанными без N39 контракта.")
            _table(section, ["Товар","В наличии","Рынок","Резерв","Тренд"],
                _stock_rows())
            _link(section, "КОНТРАКТЫ ›", "fleet", "Контракты")
        "Блокировки":
            var section := _section("ЗАДЕРЖАННЫЕ ПРОЕКТЫ")
            var rows: Array[Dictionary] = []
            var sites: Variant = _economy.get("construction_sites", {})
            if sites is Dictionary:
                for id in sites:
                    var raw: Variant = sites[id]
                    if raw is Dictionary and str(raw.get("blocked_reason", "")).length() > 0:
                        rows.append({"cells":[str(id),
                            str(raw.get("blocked_reason", "—")), "—"]})
            _table(section, ["Проект","Причина блокировки","Срок"], rows)

func _fleet_workspace() -> void:
    match _tab:
        "Корабли":
            var section := _section("КОРАБЛИ СЕКТОРА", "Выберите строку для карты")
            _table(section, ["Корабль","Класс","Задача","Груз","Статус"],
                _ship_rows(), "", "", "ship")
        "Контракты":
            var section := _section("ДЕЙСТВИТЕЛЬНЫЕ N153 КОНТРАКТЫ")
            var board: Variant = _economy.get("contract_board", {})
            var contracts: Variant = board.get("contracts", {}) if board is Dictionary else {}
            var rows: Array[Dictionary] = []
            if contracts is Dictionary:
                for id in contracts:
                    var item: Variant = contracts[id]
                    if item is Dictionary:
                        rows.append({"cells":[str(id), str(item.get("status", "—")),
                            str(item.get("commodity", "—")), str(item.get("quantity", "—")),
                            str(item.get("destination", "—"))]})
            _table(section, ["ID","Состояние","Товар","Количество","Назначение"], rows)
        "Грузы":
            var section := _section("ГРУЗОВЫЕ МАНИФЕСТЫ")
            var rows: Array[Dictionary] = []
            var ships: Variant = _economy.get("ships", {})
            if ships is Dictionary:
                for id in ships:
                    var item: Variant = ships[id]
                    if item is Dictionary:
                        var cargo: Variant = item.get("cargo", {})
                        if cargo is Dictionary and not cargo.is_empty():
                            rows.append({"id":str(id), "cells":[str(item.get("name", id)),
                                str(cargo), str(item.get("active_contract_id", "—"))]})
            _table(section, ["Корабль","Груз","Контракт"], rows, "", "", "ship")
        "Маршруты":
            var section := _section("ФИЗИЧЕСКИЕ N14 РЕЙСЫ")
            var rows: Array[Dictionary] = []
            var ships: Variant = _economy.get("ships", {})
            if ships is Dictionary:
                for id in ships:
                    var item: Variant = ships[id]
                    if item is Dictionary:
                        var transit: Variant = item.get("transit", {})
                        if transit is Dictionary and not transit.is_empty():
                            rows.append({"id":str(id), "cells":[str(item.get("name", id)),
                                str(transit.get("from", "—")), str(transit.get("to", "—")),
                                str(transit.get("arrival_tick", "—"))]})
            _table(section, ["Судно","Откуда","Куда","Прибытие (тик)"],
                rows, "", "", "ship")
        "Стыковка":
            var section := _section("СТЫКОВКА ПО N39")
            var rows: Array[Dictionary] = []
            var ships: Variant = _economy.get("ships", {})
            if ships is Dictionary:
                for id in ships:
                    var item: Variant = ships[id]
                    if item is Dictionary and not str(item.get("docked_at", "")).is_empty():
                        rows.append({"id":str(id), "cells":[str(item.get("name", id)),
                            str(item.get("docked_at", "")), str(item.get("location", "—"))]})
            _table(section, ["Корабль","Док","Локация"], rows, "", "", "ship")
        "Поставки":
            var section := _section("ФАКТИЧЕСКИЕ ПЕРЕВОЗКИ")
            _note(section, "Нет прогноза «через 3 часа» без реального срока N14 transit.")
            _link(section, "ПОСМОТРЕТЬ РЕЙСЫ ›", "fleet", "Маршруты")
            _link(section, "ПОСМОТРЕТЬ КОНТРАКТЫ ›", "fleet", "Контракты")

func _administration_workspace() -> void:
    var section := _section(_tab.to_upper(), "Решения автономной симуляции")
    var reasons: Variant = _economy.get("autonomy_diagnostics", {})
    var actions: Variant = _economy.get("ai_actions", {})
    if _tab in ["Приоритеты ИИ", "Обоснование"]:
        if reasons is Dictionary and not reasons.is_empty():
            for key in reasons:
                _pair(section, str(key), str(reasons[key]))
        else:
            _note(section, "ИИ выполняется, но человекочитаемые приоритеты/объяснения в N39 ещё не опубликованы.")
    elif _tab == "План действий":
        if actions is Dictionary and not actions.is_empty():
            for id in actions:
                _pair(section, str(id), str(actions[id]))
        else:
            _note(section, "Не опубликован список актуальных действий ИИ. Не выдумываем планы из макета.")
    else:
        _note(section, "Последствия решений будут связаны с реальной историей N39/кошельков/логистики.")
    _link(section, "ПРОВЕРИТЬ ЭКОНОМИЧЕСКИЕ УЗКИЕ МЕСТА ›", "economy", "Узкие места")

func _research_workspace() -> void:
    var section := _section(_tab.to_upper(), "Научная программа")
    var state: Variant = _economy.get("research", null)
    if state is Dictionary and not state.is_empty():
        for id in state:
            _pair(section, str(id), str(state[id]))
    else:
        _note(section, "Подтверждённых данных о прогрессе исследований в текущем N39 снимке нет.")
        _note(section, "Будущая технология и время открытия остаются «—», а не фиктивными 72%.")
    if _tab == "Открытия":
        _note(section, "Реальные разблокировки показываются только после события исследования.")

func _ship_workspace() -> void:
    var ship: Dictionary = _ship_source()
    if ship.is_empty():
        _empty("Выберите судно из списка объектов.")
        return
    var section := _section("СУДНО · " + _ship_name(), str(ship.get("class", "—")))
    match _tab:
        "Обзор":
            for key in ["faction_id","current_goal","location","system_id",
                    "docked_at","active_contract_id","fuel"]:
                _pair(section, str(key), str(ship.get(key, "—")))
            _link(section, "ФЛОТ И ЛОГИСТИКА ›", "fleet", "Корабли")
        "Груз":
            var cargo: Variant = ship.get("cargo", {})
            if cargo is Dictionary and not cargo.is_empty():
                for key in cargo:
                    _pair(section, str(key), str(cargo[key]))
            else:
                _note(section, "Подтверждённого груза нет.")
        "Маршрут":
            var transit: Variant = ship.get("transit", {})
            if transit is Dictionary and not transit.is_empty():
                for key in ["from","to","departure_tick","arrival_tick"]:
                    _pair(section, str(key), str(transit.get(key, "—")))
            else:
                _note(section, "Нет активного физического N14 рейса.")

func _technical_workspace() -> void:
    var section := _section("ДИАГНОСТИКА · ТОЛЬКО ДЛЯ РАЗРАБОТКИ")
    var raw := RichTextLabel.new()
    raw.bbcode_enabled = false
    raw.custom_minimum_size.y = 420
    raw.size_flags_vertical = Control.SIZE_EXPAND_FILL
    raw.add_theme_font_size_override("normal_font_size", 13)
    raw.text = _debug_text if not _debug_text.is_empty() else "Нет данных."
    section.add_child(raw)
