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
const LSComponents = preload("res://scripts/view/ls_ui_components.gd")
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
    "colony": ["Сводка"],
    "facility": ["Процесс и снабжение", "Труд и склад"],
    "economy": ["Рынок и цепочки", "Дефициты и узкие места"],
    "construction": ["Проекты и снабжение"],
    "fleet": ["Рейсы и контракты", "Грузы и стыковка"],
    "administration": ["Цели и задачи", "Объяснения"],
    "research": ["Текущая программа"],
    "ship": ["Обзор", "Груз", "Маршрут"],
    "technical": ["Данные"]
}

## Old navigation links from other windows, persisted UI history and tests
## resolve to the same compact Figma Make screens. This is UI-only routing;
## no N39 state, contracts or simulation defaults are fabricated.
static func canonical_tab(mode: String, requested: String) -> String:
    var aliases: Dictionary = {
        "colony": {
            "Обзор": "Сводка", "Население": "Сводка",
            "Производство": "Сводка", "Запасы": "Сводка",
            "Строительство": "Сводка", "Логистика": "Сводка",
            "overview": "Сводка"
        },
        "facility": {
            "Процесс": "Процесс и снабжение",
            "Поставщики": "Процесс и снабжение",
            "Работники": "Труд и склад", "Склад": "Труд и склад",
            "process": "Процесс и снабжение",
            "workers": "Труд и склад"
        },
        "economy": {
            "Баланс": "Рынок и цепочки",
            "Цепочки": "Рынок и цепочки",
            "Дефициты": "Дефициты и узкие места",
            "Узкие места": "Дефициты и узкие места",
            "chains": "Рынок и цепочки",
            "deficits": "Дефициты и узкие места"
        },
        "construction": {
            "Проекты": "Проекты и снабжение",
            "Материалы": "Проекты и снабжение",
            "Поставщики": "Проекты и снабжение",
            "Блокировки": "Проекты и снабжение",
            "projects": "Проекты и снабжение"
        },
        "fleet": {
            "Корабли": "Рейсы и контракты",
            "Контракты": "Рейсы и контракты",
            "Маршруты": "Рейсы и контракты",
            "Поставки": "Рейсы и контракты",
            "Грузы": "Грузы и стыковка",
            "Стыковка": "Грузы и стыковка",
            "ships": "Рейсы и контракты",
            "cargo": "Грузы и стыковка"
        },
        "administration": {
            "Приоритеты ИИ": "Цели и задачи",
            "План действий": "Цели и задачи",
            "Обоснование": "Объяснения",
            "Последствия": "Объяснения",
            "priorities": "Цели и задачи",
            "reasoning": "Объяснения"
        },
        "research": {
            "Прогресс": "Текущая программа",
            "Предпосылки": "Текущая программа",
            "Открытия": "Текущая программа",
            "progress": "Текущая программа"
        }
    }
    var available: Array = TABS.get(mode, ["Данные"])
    var options: Dictionary = aliases.get(mode, {})
    var resolved: String = str(options.get(requested, requested))
    return resolved if resolved in available else str(available[0])

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
var _filter_clear: Button
var _updated: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _last_signature: String = ""
var _last_render_ms: int = -1
var _scroll_by_page: Dictionary = {}
# Reflow controls already built for the active page without re-reading N39.
var _metric_grids: Array[GridContainer] = []
var _colony_grids: Array[GridContainer] = []

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
    # One Theme-backed button for every workspace action; callers continue
    # to own their real N39 navigation / input callbacks.
    return LSComponents.action_button(value, action, prominent)

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
    var header_bg: PanelContainer = LSComponents.chrome_panel(&"LSWorkspaceHeader")
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
    var icon_frame: PanelContainer = LSComponents.chrome_panel(&"LSWindowIconFrame")
    icon_frame.custom_minimum_size = Vector2(31, 31)
    icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
    _scope = _label("СЕКТОР / ОБЗОР", 7, Color("#627E83"))
    _header_title = _label("КОЛОНИЯ", 13, Color("#D2DDDD"))
    titles.add_child(_scope)
    titles.add_child(_header_title)
    _focus_badge = _label("", 7, AMBER)
    _focus_badge.visible = false
    _focus_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _focus_badge.theme_type_variation = &"LSFocusBadge"
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
    _tabs_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
    _tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tabs_scroll.theme_type_variation = &"LSWorkspaceTabsScroller"
    add_child(_tabs_scroll)
    _tabs = HBoxContainer.new()
    _tabs.add_theme_constant_override("separation", 0)
    _tabs_scroll.add_child(_tabs)

    var toolbar_bg: PanelContainer = LSComponents.chrome_panel(&"LSWorkspaceToolbar")
    add_child(toolbar_bg)
    var toolbar := HBoxContainer.new()
    toolbar.custom_minimum_size.y = 29
    toolbar.add_theme_constant_override("separation", 8)
    toolbar_bg.add_child(toolbar)
    var search_box: PanelContainer = LSComponents.chrome_panel(&"LSSearchFrame")
    search_box.custom_minimum_size.x = 0
    search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
    _filter.theme_type_variation = &"LSFilterLineEdit"
    _filter.text_changed.connect(func(_value: String) -> void:
        _last_signature = ""
        _filter_clear.visible = not _filter.text.is_empty()
        _render())
    search_row.add_child(_filter)
    _filter_clear = _button("×", func() -> void: _filter.clear())
    _filter_clear.custom_minimum_size = Vector2(21, 21)
    _filter_clear.add_theme_font_size_override("font_size", 15)
    _filter_clear.tooltip_text = "Очистить поиск"
    _filter_clear.visible = false
    search_row.add_child(_filter_clear)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toolbar.add_child(spacer)
    _updated = _label("ЦИКЛ — · N39", 7, Color("#58747B"))
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
    # Desktop keeps cycle metadata and focus; laptop leaves more room
    # for search and avoids titlebar collisions under Windows UI scaling.
    _updated.visible = size.x >= 500.0
    if _focus_badge != null:
        # Long source IDs belong in the tooltip, not across the close button.
        _focus_badge.visible = not _focus.is_empty() and size.x >= 670.0
    if _filter != null:
        _filter.placeholder_text = (
            "Поиск" if size.x < 350.0 else "Фильтр по объектам и статусам")
    _refresh_responsive_columns()

func _refresh_responsive_columns() -> void:
    # Root workspace width, not a grid's own resized width, determines the
    # number of columns. This avoids resize-driven 4↔2 feedback loops.
    var available: float = maxf(0.0, size.x - 46.0)
    var metrics_columns: int = (
        4 if available >= 590.0 else (2 if available >= 300.0 else 1))
    for grid in _metric_grids:
        if is_instance_valid(grid) and grid.columns != metrics_columns:
            grid.columns = metrics_columns
    var pair_columns: int = 2 if available >= 620.0 else 1
    for grid in _colony_grids:
        if is_instance_valid(grid) and grid.columns != pair_columns:
            grid.columns = pair_columns


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
    _tab = canonical_tab(mode, tab)
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
    _header_title.tooltip_text = _header_title.text
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
    _focus_badge.text = "ФОКУС: " + _focus
    _focus_badge.tooltip_text = _focus
    _fit_toolbar()
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
    _metric_grids.clear()
    _colony_grids.clear()
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
    _refresh_responsive_columns()

func _reveal_active_tab(mode: String, tab: String) -> void:
    if mode != _mode or tab != _tab or _tabs_scroll == null:
        return
    for child in _tabs.get_children():
        if child is Button and child.text == tab:
            _tabs_scroll.ensure_control_visible(child)
            return

func _tab_button(name: String, active: bool) -> Button:
    # The same Theme-backed tab component is used in every workspace.
    # The route still carries the live mode/focus, not demo Figma values.
    return LSComponents.tab(name, active, func() -> void:
        navigate_requested.emit(_mode, name, _focus))

# Every workspace uses the same Figma section header (31px) and body
# padding. The optional host supports the two-column colony overview.
func _section(title: String, detail: String = "", host: Node = null) -> VBoxContainer:
    var card: PanelContainer = LSComponents.section_panel()
    if host is HFlowContainer:
        card.custom_minimum_size.x = 300
    elif host is GridContainer:
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if host == null:
        _content.add_child(card)
    else:
        host.add_child(card)
    var shell := VBoxContainer.new()
    shell.add_theme_constant_override("separation", 0)
    card.add_child(shell)
    var title_bg: PanelContainer = LSComponents.chrome_panel(&"LSSectionHeader")
    shell.add_child(title_bg)
    var heading_row := HBoxContainer.new()
    heading_row.custom_minimum_size.y = 31
    heading_row.add_theme_constant_override("separation", 7)
    title_bg.add_child(heading_row)
    var heading := _label(title, 9, Color("#B9C8C9"))
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    heading_row.add_child(heading)
    if not detail.is_empty():
        var right_detail := _label(detail, 7, MUTED)
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
    var control: Label = LSComponents.metric_text(value, &"LSBodyNote")
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    if tone != MUTED:
        control.add_theme_color_override("font_color", tone)
    parent.add_child(control)

func _pair(parent: Node, name: String, value: String,
        tone: Color = TEXT) -> void:
    if not _match(name + " " + value):
        return
    var row_bg: PanelContainer = LSComponents.key_value_panel()
    parent.add_child(row_bg)
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 29
    row.add_theme_constant_override("separation", 12)
    row_bg.add_child(row)
    var key: Label = LSComponents.metric_text(name, &"LSKeyName")
    key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(key)
    var answer: Label = LSComponents.metric_text(value, &"LSKeyAnswer")
    answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    answer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    answer.size_flags_horizontal = Control.SIZE_SHRINK_END
    if tone != TEXT:
        answer.add_theme_color_override("font_color", tone)
    row.add_child(answer)

func _metric_strip(parent: Node, pairs: Array) -> void:
    # Exactly four Figma columns when space permits. On laptops/high DPI,
    # shrink to two/one rather than let 138px minimum tiles overflow.
    var grid := GridContainer.new()
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.columns = 1
    grid.add_theme_constant_override("h_separation", 0)
    grid.add_theme_constant_override("v_separation", 0)
    parent.add_child(grid)
    _metric_grids.append(grid)
    for item in pairs:
        if not (item is Dictionary):
            continue
        var tile: PanelContainer = LSComponents.metric_panel()
        grid.add_child(tile)
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 2)
        tile.add_child(col)
        col.add_child(LSComponents.metric_text(
            str(item.get("label", "—")).to_upper(), &"LSMetricCaption"))
        col.add_child(LSComponents.metric_text(
            str(item.get("value", "—")), &"LSMetricValue"))
        if item.has("note") and not str(item["note"]).is_empty():
            col.add_child(LSComponents.metric_text(
                str(item["note"]), &"LSMetricNote"))

func _table(parent: Node, headings: Array, rows: Array,
        route: String = "", tab: String = "", kind: String = "") -> void:
    var layout: Array[Vector2] = LSComponents.table_column_profile(headings)
    # All rows share the exact same minimum widths and stretch ratios.
    # Individual auto-sized HBoxes
    # caused headings and values to drift, especially in Fleet/Economy.
    # Scroll horizontally on compact viewports rather than crop N39 data.
    var scroller := ScrollContainer.new()
    scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    # Vertical wheel events can continue to the outer workspace scroller.
    # The table itself owns only horizontal overflow.
    scroller.mouse_filter = Control.MOUSE_FILTER_PASS
    scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(scroller)
    var grid_body := VBoxContainer.new()
    grid_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var grid_min_width := 18.0 + 7.0 * float(layout.size() - 1)
    for column in layout:
        grid_min_width += column.x
    grid_body.custom_minimum_size.x = grid_min_width
    grid_body.add_theme_constant_override("separation", 0)
    scroller.add_child(grid_body)
    _table_row(grid_body, headings, layout, true, Callable())
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
        _table_row(grid_body, cells, layout, false, callback, shown)
        shown += 1
        if shown >= 60:
            _note(parent, "Показаны первые 60 записей. Используйте поиск.")
            break
    if shown == 0:
        _note(parent, "Нет подтверждённых записей для выбранного раздела.")

func _table_row(parent: Node, cells: Array, layout: Array[Vector2],
        heading: bool, callback: Callable, row_index: int = 0) -> void:
    var container: Control = LSComponents.table_row(
        heading, row_index % 2 != 0, callback)
    parent.add_child(container)
    # Unified row geometry and states come from Theme variations.
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.custom_minimum_size.y = 15 if heading else 20
    row.add_theme_constant_override("separation", 7)
    container.add_child(row)
    # PanelContainer positions children within its Theme margins. A Button
    # is NOT a Container: its children need explicit full-width anchors.
    # Without this, clickable rows collapse to their minimum content width,
    # drifting away from the header at larger window sizes.
    if container is Button:
        row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        row.offset_left = 9
        row.offset_right = -9
    for i in range(layout.size()):
        var text_value: String = str(cells[i]) if i < cells.size() else "—"
        var tint: Color = Color("#536F75") if heading else Color("#809398")
        if not heading and i > 0:
            var lower: String = text_value.to_lower()
            if lower.contains("нет ") or lower.contains("износ") or (
                    lower.contains("заброш") or lower.contains("блокир")):
                tint = BAD
            elif lower.contains("в пути") or lower.contains("строится"):
                tint = TEAL
            elif text_value == "—":
                tint = MUTED
        var cell := _label(text_value, 7 if heading else 8, tint)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # Identical minimums for header and every data row make the columns
        # line up while leaving room for long names and real N39 statuses.
        cell.custom_minimum_size.x = layout[i].x
        cell.size_flags_stretch_ratio = layout[i].y
        cell.tooltip_text = text_value
        row.add_child(cell)

func _link(parent: Node, label: String,
        mode: String, tab: String, focus: String = "") -> void:
    var action := LSComponents.section_link(label, func() -> void:
        navigate_requested.emit(mode, tab, focus))
    action.tooltip_text = "Открыть раздел «%s» → %s" % [
        str(TITLES.get(mode, mode)), tab]
    parent.add_child(action)

func _issue_line(parent: Node, headline: String, description: String,
        on_open: Callable, critical: bool = true) -> void:
    # Figma .issue-line: native 47px clickable alert with icon, two lines
    # and a compact action on the right. Values come from N39 only.
    var button: Button = LSComponents.issue_button(critical, on_open)
    button.tooltip_text = headline + "\n" + description
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
        var source: Dictionary = _facility_source()
        if not source.is_empty():
            return str(source.get("body", ""))
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
    # A real N151 colony or later enterprise may exist only in N39.
    var active: Variant = _economy.get("facilities", {})
    if active is Dictionary and active.get(_facility) is Dictionary:
        var live: Dictionary = active[_facility]
        var bid: String = str(live.get(
            "body_id", live.get("body", "")))
        for body in _world.get("bodies", []):
            if body is Dictionary and str(body.get("id", "")) == bid:
                var source: Dictionary = live.duplicate(false)
                source["id"] = _facility
                source["body"] = bid
                source["faction_id"] = str(live.get(
                    "faction_id", live.get("faction", "")))
                return source
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
    var active: Variant = _economy.get("facilities", {})
    if active is Dictionary:
        for fid in active:
            var live: Variant = active[fid]
            if live is Dictionary and str(live.get("body_id",
                    live.get("body", ""))) == body_id:
                result[str(live.get("location", ""))] = true
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
    var seen: Dictionary = {}
    for raw in _world.get("facilities", []):
        if not (raw is Dictionary):
            continue
        var item: Dictionary = raw
        if not body_id.is_empty() and str(item.get("body", "")) != body_id:
            continue
        var id: String = str(item.get("id", ""))
        seen[id] = true
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
    # Keep live-created real N39 facilities in colony overview and tables.
    if active is Dictionary:
        var valid_bodies: Dictionary = {}
        for body in _world.get("bodies", []):
            if body is Dictionary:
                valid_bodies[str(body.get("id", ""))] = true
        for fid in active:
            var id: String = str(fid)
            if seen.has(id) or not (active[fid] is Dictionary):
                continue
            var live: Dictionary = active[fid]
            var bid: String = str(live.get("body_id",
                live.get("body", "")))
            if not valid_bodies.has(bid) or (
                    not body_id.is_empty() and bid != body_id):
                continue
            var kind: String = str(live.get("type", ""))
            if kind not in ["station", "shipyard", "construction_dock",
                    "mining_rig", "refinery", "farm", "factory",
                    "laboratory", "research", "power_plant"]:
                continue
            var condition: String = "—"
            var raw_condition: Variant = live.get("condition", null)
            if raw_condition is float or raw_condition is int:
                condition = "%.0f%%" % (float(raw_condition) * 100.0)
            rows.append({"id": id, "cells":[
                FacilityNames.display_name(live),
                FacilityNames.type_name(kind),
                str(live.get("assigned_workers", "—")), condition,
                str(live.get("location", "—"))]})
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
        "Сводка":
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
            # Figma .workspace-grid: two equal columns; collapse to one
            # below desktop space, without truncating real N39 table rows.
            var pair := GridContainer.new()
            pair.columns = 1
            pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            pair.add_theme_constant_override("h_separation", 8)
            pair.add_theme_constant_override("v_separation", 8)
            _content.add_child(pair)
            _colony_grids.append(pair)
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
            var resources := _section("КЛЮЧЕВЫЕ ЗАПАСЫ НА РЫНКАХ", "", pair)
            var stocks: Array[Dictionary] = []
            for commodity in ["food", "energy_cells", "metals", "ore"]:
                var stock: Dictionary = _market_stock_total(commodity, body)
                stocks.append({"cells": [str(commodity),
                    str(roundi(float(stock.get("amount", 0.0))))
                    if bool(stock.get("known", false)) else "—"]})
            _table(resources, ["Ресурс", "На рынке"], stocks)
            _link(resources, "ПОСМОТРЕТЬ ЭКОНОМИЧЕСКИЕ ЦЕПОЧКИ ›",
                "economy", "Рынок и цепочки")
            var projects := _section("СТРОЙКИ И МАТЕРИАЛЫ", "", pair)
            _table(projects, ["Проект", "Локация", "Прогресс",
                "Статус", "Материалы"], _construction_rows(body),
                "construction", "Проекты и снабжение")
            _link(projects, "ПРОВЕРИТЬ СТРОЙКИ И ПОСТАВКИ ›",
                "construction", "Проекты и снабжение")
            var local_fleet := _section("КОРАБЛИ И ЛОГИСТИКА", "", pair)
            _local_ships(body)
            _link(local_fleet, "РЕЙСЫ И КОНТРАКТЫ ›",
                "fleet", "Рейсы и контракты")
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
        var button: Button = LSComponents.chain_stage(
            _select_chain_stock.bind(key))
        button.tooltip_text = "Показать подтверждённые запасы: " + str(
            stage["label"])
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
        content.add_child(_label(str(stage["stage"]), 7, MUTED))
        var icon := TextureRect.new()
        icon.custom_minimum_size = Vector2(20, 20)
        icon.texture = FigmaIcons.texture("facility", 18, TEAL)
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.add_child(icon)
        content.add_child(_label(str(stage["label"]), 9, TEXT))
        content.add_child(_label("На рынках: " + stock_text, 8,
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
    var meter: ProgressBar = LSComponents.condition_bar(level)
    meter.tooltip_text = "N39: состояние %.1f%%" % (level * 100.0)
    parent.add_child(meter)

func _process_card(parent: Node, heading: String, value: String,
        note: String, machine: bool = false) -> void:
    # Figma .facility-process stage, grounded in published N39 work_shift.
    # An absent quantity stays "—"; it never becomes prototype's 4/12.
    var card: PanelContainer = LSComponents.process_card(machine)
    parent.add_child(card)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 6)
    card.add_child(content)
    var title: Label = LSComponents.metric_text(
        heading, &"LSProcessHeading")
    content.add_child(title)
    var amount: Label = LSComponents.metric_text(
        value, &"LSProcessValue")
    amount.custom_minimum_size.y = 25
    content.add_child(amount)
    var caption: Label = LSComponents.metric_text(
        note, &"LSBodyNote")
    content.add_child(caption)

func _reason_row(parent: Node, caption: String, value: String,
        chosen: bool = false) -> void:
    # Data is an original N39 decision/research field; no fabricated priority.
    var row_bg: PanelContainer = LSComponents.reasoning_row(chosen)
    parent.add_child(row_bg)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row_bg.add_child(row)
    var name: Label = LSComponents.metric_text(
        caption, &"LSReasonLabel")
    name.custom_minimum_size.x = 110
    row.add_child(name)
    var answer: Label = LSComponents.metric_text(
        value, &"LSReasonValue")
    answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    answer.tooltip_text = value
    row.add_child(answer)

func _research_entry(parent: Node, id: String, raw: Variant) -> void:
    var card: PanelContainer = LSComponents.research_card()
    parent.add_child(card)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 15)
    card.add_child(row)
    var icon := TextureRect.new()
    icon.texture = FigmaIcons.texture("research", 34, TEAL)
    icon.custom_minimum_size = Vector2(34, 34)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(icon)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 7)
    row.add_child(content)
    var title: String = str(raw.get("name", id)) if raw is Dictionary else id
    content.add_child(LSComponents.metric_text(title, &"LSResearchTitle"))
    if raw is Dictionary:
        # Only published absolute point totals can produce a real fraction.
        var points: Variant = raw.get("points", null)
        var required: Variant = raw.get("required_points", null)
        if (points is int or points is float) and (
                required is int or required is float) and float(required) > 0.0:
            var fraction: float = float(points) / float(required)
            var progress: ProgressBar = LSComponents.research_progress(fraction)
            progress.tooltip_text = "%s / %s N39" % [str(points), str(required)]
            content.add_child(progress)
            _note(content, "%s / %s очков N39" % [str(points), str(required)])
        for field in raw:
            if str(field) in ["name", "points", "required_points"]:
                continue
            _reason_row(content, str(field), str(raw[field]))
    else:
        _note(content, str(raw))

func _route_card(parent: Node, caption: String, value: String) -> void:
    var card: PanelContainer = LSComponents.route_card()
    parent.add_child(card)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 6)
    card.add_child(content)
    content.add_child(LSComponents.metric_text(
        caption.to_upper(), &"LSProcessHeading"))
    content.add_child(LSComponents.metric_text(
        value, &"LSProcessValue"))

func _project_state(parent: Node, id: String, raw: Dictionary) -> void:
    var blocked: bool = not str(raw.get("blocked_reason", "")).is_empty()
    var completed: bool = bool(raw.get("completed", false))
    var state: String = (
        "ЗАВЕРШЕНО" if completed else (
        "БЛОКИРОВКА" if blocked else "В РАБОТЕ"))
    var tone: Color = AMBER if blocked else TEAL
    var panel: PanelContainer = LSComponents.reasoning_row()
    parent.add_child(panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    panel.add_child(row)
    var label := LSComponents.metric_text(id, &"LSReasonLabel")
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    var badge := LSComponents.metric_text(state, &"LSReasonValue")
    badge.add_theme_color_override("font_color", tone)
    row.add_child(badge)
    var progress: Variant = raw.get("progress", null)
    if (progress is int or progress is float) and is_finite(float(progress)):
        var level: float = float(progress)
        if level >= 0.0 and level <= 1.0:
            var meter: ProgressBar = LSComponents.research_progress(level)
            meter.tooltip_text = "Прогресс стройки N39: %.1f%%" % (level * 100.0)
            parent.add_child(meter)
    if blocked:
        _note(parent, str(raw.get("blocked_reason", "")), AMBER)

func _planner_priority(parent: Node, caption: String, value: Variant) -> void:
    # The bar is only meaningful for normalized priority data in N39.
    var panel: PanelContainer = LSComponents.reasoning_row()
    parent.add_child(panel)
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", 10)
    panel.add_child(line)
    var label: Label = LSComponents.metric_text(caption, &"LSReasonLabel")
    label.custom_minimum_size.x = 190
    line.add_child(label)
    if (value is int or value is float) and is_finite(float(value)) and (
            float(value) >= 0.0 and float(value) <= 1.0):
        var bar: ProgressBar = LSComponents.research_progress(float(value))
        bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        line.add_child(bar)
        line.add_child(LSComponents.metric_text(
            "%.0f%%" % (float(value) * 100.0), &"LSReasonValue"))
    else:
        var raw_label: Label = LSComponents.metric_text(
            str(value), &"LSReasonValue")
        raw_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.add_child(raw_label)

func _facility_workspace() -> void:
    var source: Dictionary = _facility_source()
    if source.is_empty():
        _empty("Выберите предприятие на карте или в аутлайнере.")
        return
    var all: Variant = _economy.get("facilities", {})
    var live: Dictionary = (all.get(_facility, {})
        if all is Dictionary and all.get(_facility) is Dictionary else {})
    match _tab:
        "Процесс и снабжение":
            _facility_process_section(source, live)
            _facility_suppliers_section(source, live)
        "Труд и склад":
            _facility_workers_section(source, live)
            _facility_stock_section(source, live)

func _facility_process_section(source: Dictionary, live: Dictionary) -> void:
    var section := _section("ПРОИЗВОДСТВЕННЫЙ ЦИКЛ", _facility_name())
    var shift: Variant = live.get("work_shift", {})
    var input_value: String = (
        str(shift.get("inputs", "—")) if shift is Dictionary else "—")
    var output_value: String = (
        str(shift.get("outputs", "—")) if shift is Dictionary else "—")
    var last_tick: String = (
        str(shift.get("tick", "—")) if shift is Dictionary else "—")
    var flow := HFlowContainer.new()
    flow.add_theme_constant_override("h_separation", 9)
    flow.add_theme_constant_override("v_separation", 9)
    section.add_child(flow)
    _process_card(flow, "ВХОД · N39", input_value,
        "За последнюю смену")
    var arrow_in := _label("→", 16, TEAL)
    arrow_in.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    flow.add_child(arrow_in)
    _process_card(flow, "ПРЕДПРИЯТИЕ", _facility_name(),
        "Работники: " + str(live.get("assigned_workers", "—")), true)
    var arrow_out := _label("→", 16, TEAL)
    arrow_out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    flow.add_child(arrow_out)
    _process_card(flow, "ВЫХОД · N39", output_value,
        "Последняя смена: тик " + last_tick)
    _pair(section, "Назначенные работники",
        str(live.get("assigned_workers", "—")))
    _pair(section, "Состояние объекта", str(live.get("condition", "—")))
    _condition_bar(section, live.get("condition", null))
    _pair(section, "Последняя оплаченная смена", last_tick)
    _note(section, "Точные входы, выпуск и причина простоя — только при наличии записи N39.")
    _link(section, "СКЛАД ОБЪЕКТА ›", "facility", "Склад", _facility)

func _facility_workers_section(source: Dictionary, live: Dictionary) -> void:
    var section := _section("РАБОТНИКИ И ОПЛАТА")
    _pair(section, "Назначено", str(live.get("assigned_workers", "—")))
    var shift: Variant = live.get("work_shift", {})
    if shift is Dictionary:
        _pair(section, "Тик последней смены", str(shift.get("tick", "—")))
        _pair(section, "Оплачено", str(shift.get("wages", "—")))
        _pair(section, "Работников в смене", str(shift.get("workers", "—")))
    _pair(section, "Износ / состояние", str(live.get("condition", "—")))

func _facility_stock_section(source: Dictionary, live: Dictionary) -> void:
    var section := _section("СКЛАД ПРЕДПРИЯТИЯ")
    var mod: Variant = live.get("module_stock", {})
    var stock: Variant = mod.get("stock", {}) if mod is Dictionary else {}
    _metric_strip(section, [
        {"label":"Позиции склада", "value":(
            str(stock.size()) if stock is Dictionary else "—")},
        {"label":"Предприятие", "value":_facility_name()},
        {"label":"Локация", "value":str(source.get("location", "—"))},
        {"label":"Работники", "value":str(live.get("assigned_workers", "—"))}])
    var rows: Array[Dictionary] = []
    if stock is Dictionary:
        for key in stock:
            rows.append({"cells":[str(key), str(stock[key]), "—", "—"]})
    _table(section, ["Товар","В наличии","Вход","Выход"], rows)

func _facility_suppliers_section(source: Dictionary, live: Dictionary) -> void:
    var section := _section("ПОСТАВЩИКИ И КОНТРАКТЫ")
    _pair(section, "Локация", str(source.get("location", "—")))
    _pair(section, "Фракция", str(source.get("faction_id", "—")))
    _note(section, "Не создаём обещанные поставки. Действительные контракты показаны во флоте.")
    _link(section, "ПОСМОТРЕТЬ КОНТРАКТЫ ›", "fleet", "Контракты")

func _economy_workspace() -> void:
    match _tab:
        "Рынок и цепочки":
            var section := _section("БАЛАНС РЫНКОВ", "Все фракции, не кошелёк игрока")
            var rows: Array[Dictionary] = []
            var known_commodities: Dictionary = {}
            var total_credits: float = 0.0
            var credit_samples: int = 0
            var markets: Array[Dictionary] = _markets()
            for market in markets:
                var data: Dictionary = market["data"]
                var stock: Variant = data.get("supply", {})
                if stock is Dictionary:
                    for kind in stock:
                        known_commodities[str(kind)] = true
                var credits: Variant = data.get("credits", null)
                if credits is int or credits is float:
                    total_credits += float(credits)
                    credit_samples += 1
                rows.append({"cells":[str(market["location"]),
                    str(stock.size()) if stock is Dictionary else "—",
                    str(data.get("credits", "—")), "—"]})
            _metric_strip(section, [
                {"label":"Рынки N39", "value":str(markets.size())},
                {"label":"Виды товаров", "value":str(known_commodities.size())},
                {"label":"Кредиты рынков", "value":(
                    str(roundi(total_credits)) if credit_samples == markets.size() and credit_samples > 0 else "—")},
                {"label":"Предприятия", "value":str(_facility_rows().size())}])
            _table(section, ["Рынок","Товаров","Кредиты","Тренд"], rows)
            var links := _section("ПРОИЗВОДСТВЕННЫЕ ОБЪЕКТЫ")
            _table(links, ["Предприятие","Тип","Работники","Состояние","Локация"],
                _facility_rows(), "", "", "facility")
            _chain()
            var link := _section("ДОСТАВКИ И КОНТРАКТЫ")
            _link(link, "ДЕЙСТВИТЕЛЬНЫЕ ПЕРЕВОЗКИ ›", "fleet", "Рейсы и контракты")
        "Дефициты и узкие места":
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
    var visible_sites: Array[Dictionary] = _construction_rows(body_id)
    var all_sites: Variant = _economy.get("construction_sites", {})
    var completed: int = 0
    var blocked: int = 0
    for site in visible_sites:
        var id: String = str(site.get("id", ""))
        var raw: Variant = all_sites.get(id, {}) if all_sites is Dictionary else {}
        if raw is Dictionary:
            if bool(raw.get("completed", false)):
                completed += 1
            if not str(raw.get("blocked_reason", "")).is_empty():
                blocked += 1
    _metric_strip(section, [
        {"label":"Стройплощадки", "value":str(visible_sites.size())},
        {"label":"В работе", "value":str(maxi(0, visible_sites.size() - completed))},
        {"label":"Завершены", "value":str(completed)},
        {"label":"Блокировки", "value":str(blocked)}])
    _table(section, ["Проект","Локация","Прогресс","Статус","Материалы"],
        visible_sites, "construction", "Материалы")
    var milestones := _section("СОСТОЯНИЯ СТРОЙПЛОЩАДОК",
        "Шкала только если N39 публикует прогресс от 0 до 1")
    if all_sites is Dictionary:
        for site in visible_sites:
            var id: String = str(site.get("id", ""))
            var raw: Variant = all_sites.get(id, {})
            if raw is Dictionary:
                _project_state(milestones, id, raw)
    _note(section, "Планы ИИ без созданной площадки здесь не считаются стройкой.")

func _construction_workspace() -> void:
    if _tab != "Проекты и снабжение":
        return
    _projects()
    var markets := _section("ДОСТУПНЫЕ МАТЕРИАЛЫ НА РЫНКАХ",
        "Запас на рынке не равен подтверждённой поставке")
    _table(markets, ["Ресурс", "В наличии", "Рынок",
        "Резерв", "Тренд"], _stock_rows())
    _link(markets, "ПРОВЕРИТЬ РЕЙСЫ И КОНТРАКТЫ ›",
        "fleet", "Рейсы и контракты")
    var blocked := _section("ПРИЧИНЫ БЛОКИРОВОК")
    var rows: Array[Dictionary] = []
    var sites: Variant = _economy.get("construction_sites", {})
    if sites is Dictionary:
        for id in sites:
            var raw: Variant = sites[id]
            if raw is Dictionary and not str(
                    raw.get("blocked_reason", "")).is_empty():
                rows.append({"cells": [str(id),
                    str(raw.get("blocked_reason", "—"))]})
    _table(blocked, ["Проект", "Подтверждённая причина"], rows)
    _note(blocked, "Сроки и поставки не предсказываются без игровых данных.")

func _fleet_workspace() -> void:
    match _tab:
        "Рейсы и контракты":
            _fleet_ships_section()
            _fleet_routes_section()
            _fleet_contracts_section()
        "Грузы и стыковка":
            _fleet_cargo_section()
            _fleet_docks_section()
            _fleet_deliveries_section()

func _fleet_ships_section() -> void:
    var section := _section("КОРАБЛИ СЕКТОРА", "Выберите строку для карты")
    var ship_rows: Array[Dictionary] = _ship_rows()
    var flying: int = 0
    var docked: int = 0
    var carrying: int = 0
    var live_ships: Variant = _economy.get("ships", {})
    if live_ships is Dictionary:
        for raw in live_ships.values():
            if not (raw is Dictionary):
                continue
            var transit: Variant = raw.get("transit", {})
            if transit is Dictionary and not transit.is_empty():
                flying += 1
            if not str(raw.get("docked_at", "")).is_empty():
                docked += 1
            var cargo: Variant = raw.get("cargo", {})
            if cargo is Dictionary and not cargo.is_empty():
                carrying += 1
    _metric_strip(section, [
        {"label":"Корабли N39", "value":str(ship_rows.size())},
        {"label":"В пути N14", "value":str(flying)},
        {"label":"У дока", "value":str(docked)},
        {"label":"С грузом", "value":str(carrying)}])
    _table(section, ["Корабль","Класс","Задача","Груз","Статус"],
        ship_rows, "", "", "ship")

func _fleet_contracts_section() -> void:
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
    var statuses: Dictionary = {}
    for entry in rows:
        var cells: Array = entry["cells"]
        var name: String = str(cells[1])
        statuses[name] = int(statuses.get(name, 0)) + 1
    _metric_strip(section, [
        {"label":"Контракты N153", "value":str(rows.size())},
        {"label":"Разных статусов", "value":str(statuses.size())},
        {"label":"Срок исполнения", "value":"—"},
        {"label":"История рейсов", "value":"—"}])
    _table(section, ["ID","Состояние","Товар","Количество","Назначение"], rows)

func _fleet_cargo_section() -> void:
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

func _fleet_routes_section() -> void:
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

func _fleet_docks_section() -> void:
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

func _fleet_deliveries_section() -> void:
    var section := _section("ФАКТИЧЕСКИЕ ПЕРЕВОЗКИ")
    _note(section, "Нет прогноза «через 3 часа» без реального срока N14 transit.")
    _link(section, "ПОСМОТРЕТЬ РЕЙСЫ ›", "fleet", "Маршруты")
    _link(section, "ПОСМОТРЕТЬ КОНТРАКТЫ ›", "fleet", "Контракты")

func _administration_workspace() -> void:
    var section := _section(_tab.to_upper(), "Реальные решения автономных фракций")
    var reasons: Variant = _economy.get("autonomy_diagnostics", {})
    var actions: Variant = _economy.get("ai_actions", {})
    if _tab == "Цели и задачи":
        var has_priorities: bool = reasons is Dictionary and not reasons.is_empty()
        if has_priorities:
            for key in reasons:
                if str(key) == "consequences":
                    continue
                _planner_priority(section, str(key), reasons[key])
        else:
            _note(section,
                "Цели фракции пока не опубликованы симуляцией.")
        var tasks := _section("ОЧЕРЕДЬ ДЕЙСТВИЙ")
        if actions is Dictionary and not actions.is_empty():
            for id in actions:
                _reason_row(tasks, str(id), str(actions[id]))
        else:
            _note(tasks, "Список текущих решений ИИ пока недоступен.")
    else:
        var has_explanations: bool = false
        if reasons is Dictionary:
            for key in reasons:
                if str(key) == "consequences":
                    continue
                _reason_row(section, str(key), str(reasons[key]))
                has_explanations = true
            var consequences: Variant = reasons.get("consequences", {})
            if consequences is Dictionary and not consequences.is_empty():
                var consequences_box := _section("ПОДТВЕРЖДЁННЫЕ ПОСЛЕДСТВИЯ")
                for key in consequences:
                    _reason_row(consequences_box, str(key),
                        str(consequences[key]))
                has_explanations = true
        if not has_explanations:
            _note(section, "Объяснения и последствия ещё не опубликованы.")
    _link(section, "ЭКОНОМИЧЕСКИЕ УЗКИЕ МЕСТА ›",
        "economy", "Дефициты и узкие места")

func _research_workspace() -> void:
    var section := _section("ТЕКУЩАЯ НАУЧНАЯ ПРОГРАММА")
    var state: Variant = _economy.get("research", null)
    if state is Dictionary and not state.is_empty():
        for id in state:
            if str(id) in ["prerequisites", "unlocks"]:
                continue
            _research_entry(section, str(id), state[id])
        for key in ["prerequisites", "unlocks"]:
            var rows: Variant = state.get(key, null)
            if rows is Dictionary and not rows.is_empty():
                var sub := _section("ПРЕДПОСЫЛКИ" if key == "prerequisites"
                    else "ОТКРЫТИЯ")
                for id in rows:
                    _research_entry(sub, str(id), rows[id])
    else:
        var placeholder: PanelContainer = LSComponents.research_card()
        section.add_child(placeholder)
        var pending := VBoxContainer.new()
        pending.add_theme_constant_override("separation", 7)
        placeholder.add_child(pending)
        pending.add_child(LSComponents.metric_text(
            "ИССЛЕДОВАНИЕ · —", &"LSResearchTitle"))
        _note(pending, "N39 ещё не опубликовал исследование, очки и срок.")
        _note(pending, "Прототипные 72% и технология из макета не подставляются.")
    _note(section, "Открытия и условия показываются только после публикации игровых данных.")

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
            _metric_strip(section, [
                {"label":"Корабль", "value":_ship_name()},
                {"label":"Позиций груза", "value":(
                    str(cargo.size()) if cargo is Dictionary else "—")},
                {"label":"Контракт", "value":str(ship.get("active_contract_id", "—"))},
                {"label":"Док", "value":str(ship.get("docked_at", "—"))}])
            if cargo is Dictionary and not cargo.is_empty():
                for key in cargo:
                    _pair(section, str(key), str(cargo[key]))
            else:
                _note(section, "Подтверждённого груза нет.")
        "Маршрут":
            var transit: Variant = ship.get("transit", {})
            if transit is Dictionary and not transit.is_empty():
                var route_flow := HFlowContainer.new()
                route_flow.add_theme_constant_override("h_separation", 12)
                route_flow.add_theme_constant_override("v_separation", 9)
                section.add_child(route_flow)
                _route_card(route_flow, "Отправление · N14",
                    str(transit.get("from", "—")))
                var direction := _label("→", 16, TEAL)
                direction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                route_flow.add_child(direction)
                _route_card(route_flow, "Назначение · N14",
                    str(transit.get("to", "—")))
                for key in ["departure_tick", "arrival_tick"]:
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
