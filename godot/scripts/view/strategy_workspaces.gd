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
const BG = Color("#0B171E")
const SURFACE = Color("#10212A")
const DEEP = Color("#0D1C23")
const LINE = Color("#31505A")
const TEAL = Color("#53B5AC")
const TEXT = Color("#D3DDDD")
const MUTED = Color("#81999F")
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
var _header_icon: TextureRect
var _scope: Label
var _tabs: HFlowContainer
var _filter: LineEdit
var _updated: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _last_signature: String = ""
var _last_render_ms: int = -1

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
    return style

func _label(value: String, size_px: int = 14,
        tone: Color = TEXT) -> Label:
    var control := Label.new()
    control.text = value
    control.add_theme_font_size_override("font_size", size_px)
    control.add_theme_color_override("font_color", tone)
    control.clip_text = true
    control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    return control

func _button(value: String, action: Callable = Callable(),
        prominent: bool = false) -> Button:
    var control := Button.new()
    control.text = value
    control.focus_mode = Control.FOCUS_NONE
    control.add_theme_font_size_override("font_size", 13)
    control.add_theme_color_override("font_color", TEAL if prominent else TEXT)
    control.add_theme_color_override("font_hover_color", TEAL)
    control.add_theme_stylebox_override("normal", _box(SURFACE, true))
    control.add_theme_stylebox_override("hover", _box(Color("#18343B"), true))
    control.add_theme_stylebox_override("pressed", _box(Color("#1F4248"), true))
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
    var header := HBoxContainer.new()
    header.custom_minimum_size.y = 53
    header.add_theme_constant_override("separation", 7)
    add_child(header)
    header.add_child(_button("‹", func() -> void: back_requested.emit()))
    _header_icon = TextureRect.new()
    _header_icon.custom_minimum_size = Vector2(28, 28)
    _header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _header_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    header.add_child(_header_icon)
    var titles := VBoxContainer.new()
    titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(titles)
    _scope = _label("СЕКТОР / ОБЗОР", 11, MUTED)
    _header_title = _label("УПРАВЛЕНИЕ", 20, TEXT)
    titles.add_child(_scope)
    titles.add_child(_header_title)
    header.add_child(_button("✕", func() -> void: close_requested.emit()))
    add_child(_hline())
    _tabs = HFlowContainer.new()
    _tabs.add_theme_constant_override("h_separation", 4)
    _tabs.add_theme_constant_override("v_separation", 4)
    add_child(_tabs)
    add_child(_hline())
    var toolbar := HBoxContainer.new()
    toolbar.custom_minimum_size.y = 49
    add_child(toolbar)
    _filter = LineEdit.new()
    _filter.placeholder_text = "Поиск в этом разделе…"
    _filter.custom_minimum_size.x = 210
    _filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _filter.add_theme_font_size_override("font_size", 13)
    _filter.add_theme_color_override("font_color", TEXT)
    _filter.add_theme_color_override("font_placeholder_color", MUTED)
    _filter.add_theme_stylebox_override("normal", _box(DEEP))
    _filter.add_theme_stylebox_override("focus", _box(DEEP))
    _filter.text_changed.connect(func(_value: String) -> void:
        _last_signature = ""
        _render())
    toolbar.add_child(_filter)
    _updated = _label("ТИК —", 12, MUTED)
    toolbar.add_child(_updated)
    add_child(_hline())
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_scroll)
    _content = VBoxContainer.new()
    _content.add_theme_constant_override("separation", 9)
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.add_child(_content)

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

func _render() -> void:
    if _content == null:
        return
    _header_title.text = str(TITLES.get(_mode, _mode))
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
    _scope.text = "СЕКТОР / " + location.to_upper()
    _updated.text = "ТИК %d · N39" % _tick
    _clear(_tabs)
    for name in tabs_for(_mode):
        var tab_name: String = str(name)
        var active: bool = tab_name == _tab
        _tabs.add_child(_button(tab_name, func() -> void:
            navigate_requested.emit(_mode, tab_name, _focus), active))
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

func _section(title: String, detail: String = "") -> VBoxContainer:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", _box(SURFACE))
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _content.add_child(card)
    var inside := VBoxContainer.new()
    inside.add_theme_constant_override("separation", 7)
    card.add_child(inside)
    var header := HBoxContainer.new()
    inside.add_child(header)
    var heading := _label(title, 16, TEXT)
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(heading)
    if not detail.is_empty():
        header.add_child(_label(detail, 11, MUTED))
    inside.add_child(_hline())
    return inside

func _note(parent: Node, value: String, tone: Color = MUTED) -> void:
    var control := _label(value, 13, tone)
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(control)

func _pair(parent: Node, name: String, value: String,
        tone: Color = TEXT) -> void:
    if not _match(name + " " + value):
        return
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    parent.add_child(row)
    var key := _label(name, 13, MUTED)
    key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(key)
    row.add_child(_label(value, 14, tone))

func _metric_strip(parent: Node, pairs: Array) -> void:
    var flow := HFlowContainer.new()
    flow.add_theme_constant_override("h_separation", 6)
    flow.add_theme_constant_override("v_separation", 6)
    parent.add_child(flow)
    for item in pairs:
        if not (item is Dictionary):
            continue
        var tile := PanelContainer.new()
        tile.add_theme_stylebox_override("panel", _box(DEEP))
        tile.custom_minimum_size = Vector2(140, 69)
        flow.add_child(tile)
        var col := VBoxContainer.new()
        tile.add_child(col)
        col.add_child(_label(str(item.get("label", "—")), 11, MUTED))
        col.add_child(_label(str(item.get("value", "—")), 20, TEXT))

func _table(parent: Node, headings: Array, rows: Array,
        route: String = "", tab: String = "", kind: String = "") -> void:
    var columns: int = maxi(1, headings.size())
    _table_row(parent, headings, columns, true, Callable())
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
        _table_row(parent, cells, columns, false, callback)
        shown += 1
        if shown >= 60:
            _note(parent, "Показаны первые 60 записей. Используйте поиск.")
            break
    if shown == 0:
        _note(parent, "Нет подтверждённых записей для выбранного раздела.")

func _table_row(parent: Node, cells: Array, columns: int,
        heading: bool, callback: Callable) -> void:
    var container: Control
    if callback.is_valid():
        var btn := Button.new()
        btn.flat = true
        btn.focus_mode = Control.FOCUS_NONE
        btn.pressed.connect(callback)
        btn.add_theme_stylebox_override("normal", _box(DEEP))
        btn.add_theme_stylebox_override("hover", _box(Color("#1C3A43")))
        btn.add_theme_stylebox_override("pressed", _box(Color("#22505A")))
        parent.add_child(btn)
        container = btn
    else:
        var panel := PanelContainer.new()
        panel.add_theme_stylebox_override("panel", _box(DEEP))
        parent.add_child(panel)
        container = panel
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    container.add_child(row)
    for i in range(columns):
        var cell := _label(str(cells[i]) if i < cells.size() else "—",
            12 if heading else 13, TEAL if heading else TEXT)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        cell.size_flags_stretch_ratio = 1.5 if i == 0 else 1.0
        cell.tooltip_text = cell.text
        row.add_child(cell)

func _link(parent: Node, label: String,
        mode: String, tab: String, focus: String = "") -> void:
    parent.add_child(_button(label, func() -> void:
        navigate_requested.emit(mode, tab, focus), true))

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
        var condition: String = str(live.get("condition", "—"))
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
                if live is Dictionary and (bool(live.get("abandoned", false)) or (
                        live.has("condition") and float(live["condition"]) < 0.8)):
                    var title: String = str(raw["cells"][0])
                    problem.add_child(_button("⚠ " + title + " · повреждение/износ",
                        func() -> void: select_requested.emit("facility", id)))
                    problems += 1
            if problems == 0:
                _note(problem, "Подтверждённых сигналов износа нет. Остальные причины — в N39.")
            var companies := _section("ПРЕДПРИЯТИЯ", "Откройте строку")
            _table(companies, ["Предприятие","Тип","Работники","Состояние","Локация"],
                facilities, "", "", "facility")
            var next := _section("АВТОНОМНОЕ УПРАВЛЕНИЕ")
            _note(next, "Планы ИИ отображаются только при наличии настоящих событий планировщика.")
            _link(next, "ОТКРЫТЬ УПРАВЛЕНИЕ ›", "administration", "План действий")
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

func _chain(body_id: String = "") -> void:
    var group := _section("ПРОИЗВОДСТВЕННЫЕ ЦЕПОЧКИ", "Схема рецептов · не поток за тик")
    var flow := HFlowContainer.new()
    flow.add_theme_constant_override("h_separation", 8)
    flow.add_theme_constant_override("v_separation", 8)
    group.add_child(flow)
    for stage in ["РУДА", "→", "МЕТАЛЛЫ", "→", "КОМПОНЕНТЫ", "→", "ЭЛЕКТРОНИКА"]:
        if stage == "→":
            flow.add_child(_label(stage, 18, TEAL))
        else:
            var tile := PanelContainer.new()
            tile.add_theme_stylebox_override("panel", _box(DEEP))
            flow.add_child(tile)
            var col := VBoxContainer.new()
            tile.add_child(col)
            col.add_child(_label(stage, 14, TEXT))
            col.add_child(_label("Реальный баланс — в «Запасы»", 11, MUTED))
    var flow2 := _section("ДОСТУПНЫЕ ПРЕДПРИЯТИЯ")
    _table(flow2, ["Объект","Тип","Работники","Состояние","Локация"],
        _facility_rows(body_id), "", "", "facility")
    _note(flow2, "Сырьё и выпуск за смену появятся после привязки точных N39 рецептов.")

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
