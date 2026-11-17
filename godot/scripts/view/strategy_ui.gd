extends Control
const QuickData = preload("res://scripts/view/colony_quick_projection.gd")
const ContextData = preload("res://scripts/view/colony_context_projection.gd")
const FacilityNames = preload("res://scripts/view/facility_labels_ru.gd")
const ShipPresence = preload("res://scripts/view/ship_body_projection.gd")
const FullWorkspaces = preload("res://scripts/view/strategy_workspaces.gd")
const FigmaIcons = preload("res://scripts/view/figma_strategy_icons.gd")
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
var _fleet_diagnostics: Dictionary = {}
var _body: String = ""
var _facility: String = ""
var _ship: String = ""
var _mode: String = "sector"
var _window_mode: String = ""
var _tab: String = "Обзор"
var _top: PanelContainer
var _nav_panel: PanelContainer
var _nav_back: Button
var _nav_sector: Button
var _nav_path: Label
var _brand_box: VBoxContainer
var _time_area: VBoxContainer
var _metric_boxes: Array[VBoxContainer] = []
var _brand_scope: Button
var _metric_nodes: Dictionary = {}
var _clock: Label
var _perf_readout: Label
var _perf_detail_text: String = ""
var _pause: Button
var _outliner: PanelContainer
var _outliner_list: VBoxContainer
var _outliner_signature: String = ""
var _window: PanelContainer
var _workspace_ui
var _workspace_history: Array[Dictionary] = []
var _workspace_focus: String = ""
var _window_title: Label
var _window_text: RichTextLabel
var _window_tabs: HFlowContainer
var _window_cards: GridContainer
var _window_ship_links: HFlowContainer
var _ship_links_signature: String = ""
var _selection_card: PanelContainer
var _selection_title: Label
var _selection_summary: Label
var _tabs_signature: String = ""
var _cards_signature: String = ""
var _ui_scale_menu: OptionButton
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

func _label(value: String, size_px: int = 14, color: Color = TEXT) -> Label:
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
    _build_navigation()
    _build_window()
    _build_selection_card()
    resized.connect(_layout_window)
    set_process_unhandled_key_input(true)
    _layout_window()

func _build_top() -> void:
    _top = _panel()
    _top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _top.offset_bottom = 82
    _top.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_top)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 0)
    _top.add_child(row)
    var brand := VBoxContainer.new()
    _brand_box = brand
    brand.custom_minimum_size = Vector2(184, 0)
    brand.add_theme_constant_override("separation", 3)
    row.add_child(brand)
    brand.add_child(_label("LIVING SECTOR", 19, TEXT))
    _brand_scope = _button("СЕКТОР · ВСЕ РЫНКИ ▾", _toggle_scope, 11)
    _brand_scope.tooltip_text = "Общие запасы рынков всех фракций, НЕ баланс одной фракции"
    brand.add_child(_brand_scope)
    for item in METRICS:
        var box := VBoxContainer.new()
        _metric_boxes.append(box)
        box.custom_minimum_size = Vector2(121, 0)
        box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        box.add_theme_constant_override("separation", 4)
        row.add_child(box)
        box.add_child(_label(str(item["label"]), 12, MUTED))
        var large := _label(str(item["symbol"]) + " —", 20, TEXT)
        box.add_child(large)
        _metric_nodes[str(item["key"])] = large
    var time_area := VBoxContainer.new()
    _time_area = time_area
    time_area.custom_minimum_size = Vector2(210, 0)
    row.add_child(time_area)
    _perf_readout = _label("FPS — · SIM — · PING —", 12, TEAL)
    _perf_readout.tooltip_text = "Локальная симуляция: сетевой ping не применяется."
    time_area.add_child(_perf_readout)
    _clock = _label("ТИК — · ×1", 13, MUTED)
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
    rail.offset_top = 82
    rail.offset_right = 66
    rail.offset_bottom = -4
    add_child(rail)
    var rail_column := VBoxContainer.new()
    rail.add_child(rail_column)
    var menu_scroll := ScrollContainer.new()
    menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    rail_column.add_child(menu_scroll)
    var menu := VBoxContainer.new()
    menu.add_theme_constant_override("separation", 5)
    menu_scroll.add_child(menu)
    for entry in [
        {"text":"КОЛ", "tip":"Колонии [1]", "action":"colony", "icon":"colony"},
        {"text":"ЭКН", "tip":"Экономика [2]", "action":"economy", "icon":"economy"},
        {"text":"СТР", "tip":"Строительство [3]", "action":"construction", "icon":"construction"},
        {"text":"ИСС", "tip":"Исследования [4]", "action":"research", "icon":"research"},
        {"text":"ФЛТ", "tip":"Флот и логистика [5]", "action":"fleet", "icon":"fleet"},
        {"text":"УПР", "tip":"Автономное управление [6]", "action":"administration", "icon":"administration"},
        {"text":"ОБЪ", "tip":"Показать/скрыть список объектов", "action":"outliner"},
        {"text":"ДАН", "tip":"Подробные данные N39", "action":"technical"},
        {"text":"НАБ", "tip":"Наблюдение и диагностика", "action":"observer"},
        {"text":"КАР", "tip":"Сектор / система", "action":"map"},
        {"text":"ЦЕН", "tip":"Центрировать карту", "action":"center"},
        {"text":"СОХ", "tip":"Сохранить игру", "action":"save"},
        {"text":"ЗАГ", "tip":"Загрузить игру", "action":"load"}
    ]:
        var action: String = str(entry["action"])
        var btn := _button(str(entry["text"]), _activate.bind(action), 13)
        btn.tooltip_text = str(entry["tip"])
        if entry.has("icon"):
            btn.icon = FigmaIcons.texture(str(entry["icon"]), 21, TEAL)
            if btn.icon != null:
                btn.text = ""
                btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        btn.custom_minimum_size = Vector2(43, 43)
        menu.add_child(btn)
    _ui_scale_menu = OptionButton.new()
    _ui_scale_menu.tooltip_text = "Масштаб интерфейса: 100 / 115 / 125 / 140%"
    _ui_scale_menu.add_theme_font_size_override("font_size", 11)
    _ui_scale_menu.add_theme_color_override("font_color", TEXT)
    _ui_scale_menu.add_theme_stylebox_override("normal", _style(BG2))
    _ui_scale_menu.add_theme_stylebox_override("hover", _style(Color("#183239"), TEAL))
    _ui_scale_menu.add_theme_stylebox_override("pressed", _style(Color("#183239"), TEAL))
    _ui_scale_menu.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, TEAL))
    _ui_scale_menu.custom_minimum_size = Vector2(43, 33)
    for percent in [100, 115, 125, 140]:
        _ui_scale_menu.add_item("%d%%" % percent)
    _ui_scale_menu.select(2)
    _ui_scale_menu.item_selected.connect(_set_ui_scale)
    rail_column.add_child(_ui_scale_menu)

func _build_outliner() -> void:
    _outliner = _panel()
    _outliner.anchor_left = 1.0
    _outliner.anchor_right = 1.0
    _outliner.anchor_bottom = 1.0
    _outliner.offset_left = -272
    _outliner.offset_right = -8
    _outliner.offset_top = 92
    _outliner.offset_bottom = -12
    add_child(_outliner)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 7)
    _outliner.add_child(col)
    var head := HBoxContainer.new()
    col.add_child(head)
    var caption := _label("ОБЪЕКТЫ СИСТЕМЫ", 15)
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

## Persistent map breadcrumb. The former legacy "К сектору" button was
## hidden by the Figma shell, which made leaving another system undiscoverable.
## Keep this readable at 100–140% without reserving half of the map.
func _build_navigation() -> void:
    _nav_panel = _panel()
    _nav_panel.offset_left = 78
    _nav_panel.offset_right = 470
    _nav_panel.offset_top = 89
    _nav_panel.offset_bottom = 133
    add_child(_nav_panel)
    var controls := HBoxContainer.new()
    controls.add_theme_constant_override("separation", 5)
    _nav_panel.add_child(controls)
    _nav_back = _button("← К СЕКТОРУ", _navigate_back, 13)
    _nav_back.tooltip_text = "Вернуться на карту сектора (Esc)"
    controls.add_child(_nav_back)
    _nav_sector = _button("← СЕКТОР", _navigate_sector, 12)
    _nav_sector.tooltip_text = "Сразу вернуться на карту сектора"
    _nav_sector.visible = false
    controls.add_child(_nav_sector)
    _nav_path = _label("СЕКТОР", 12, MUTED)
    _nav_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    controls.add_child(_nav_path)

func _navigate_back() -> void:
    if _game == null:
        return
    if bool(_game.get("_in_system")):
        _game.call("_return_to_sector")
    else:
        _game.call("_open_selected_system")
    _update_navigation()

func _navigate_sector() -> void:
    if _game != null:
        _game.call("_go_to_sector")
    _update_navigation()

func _update_navigation() -> void:
    if _nav_back == null or _game == null:
        return
    var in_system: bool = bool(_game.get("_in_system"))
    var focused: bool = false
    if in_system:
        var view: Variant = _game.get("_system_view")
        if view != null and view.has_method("is_body_focused"):
            focused = bool(view.call("is_body_focused"))
    if not in_system:
        _nav_back.text = "ОТКРЫТЬ СИСТЕМУ ›"
        _nav_back.tooltip_text = "Открыть выбранную систему из карты сектора"
        _nav_sector.visible = false
        _nav_path.text = "СЕКТОР"
    else:
        _nav_back.text = "← К СИСТЕМЕ" if focused else "← К СЕКТОРУ"
        _nav_back.tooltip_text = ("Вернуться от планеты к орбитальной карте"
            if focused else "Вернуться к карте сектора")
        _nav_sector.visible = focused
        var name: String = str(_world.get("system", {}).get("name", "СИСТЕМА"))
        _nav_path.text = name
        _nav_panel.tooltip_text = "Esc — назад; навигация не перезапускает симуляцию"

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
    _window_title = _label("Колония", 22)
    _window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_window_title)
    header.add_child(_button("×", _close_window, 18))
    _window_tabs = HFlowContainer.new()
    _window_tabs.add_theme_constant_override("h_separation", 5)
    _window_tabs.add_theme_constant_override("v_separation", 5)
    col.add_child(_window_tabs)
    _window_cards = GridContainer.new()
    _window_cards.columns = 2
    _window_cards.add_theme_constant_override("h_separation", 8)
    _window_cards.add_theme_constant_override("v_separation", 8)
    _window_cards.visible = false
    col.add_child(_window_cards)
    _window_ship_links = HFlowContainer.new()
    _window_ship_links.add_theme_constant_override("h_separation", 5)
    _window_ship_links.add_theme_constant_override("v_separation", 5)
    _window_ship_links.visible = false
    col.add_child(_window_ship_links)
    _window_text = RichTextLabel.new()
    _window_text.bbcode_enabled = false
    _window_text.scroll_active = true
    _window_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _window_text.add_theme_font_size_override("normal_font_size", 16)
    _window_text.add_theme_color_override("default_color", TEXT)
    col.add_child(_window_text)
    # The old debug window is kept as noninteractive fallback only;
    # the active management UI is the complete Figma Make WorkspaceShell.
    col.visible = false
    _workspace_ui = FullWorkspaces.new()
    _workspace_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _workspace_ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _workspace_ui.navigate_requested.connect(_route_workspace)
    _workspace_ui.select_requested.connect(_select_from_workspace)
    _workspace_ui.back_requested.connect(_workspace_back)
    _workspace_ui.close_requested.connect(_close_window)
    _window.add_child(_workspace_ui)

func _build_selection_card() -> void:
    _selection_card = _panel()
    _selection_card.visible = false
    _selection_card.anchor_top = 1.0
    _selection_card.anchor_bottom = 1.0
    _selection_card.offset_left = 80
    _selection_card.offset_right = 406
    _selection_card.offset_top = -205
    _selection_card.offset_bottom = -20
    add_child(_selection_card)
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 7)
    _selection_card.add_child(body)
    var header := HBoxContainer.new()
    body.add_child(header)
    _selection_title = _label("ВЫБРАННЫЙ ОБЪЕКТ", 17, TEAL)
    _selection_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_selection_title)
    header.add_child(_button("×", _dismiss_selection_card, 15))
    _selection_summary = _label("—", 14, TEXT)
    _selection_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _selection_summary.custom_minimum_size = Vector2(0, 48)
    body.add_child(_selection_summary)
    body.add_child(_button("ПОДРОБНЕЕ  ›", _open_selection_details, 14))

func _dismiss_selection_card() -> void:
    _selection_card.hide()

func _open_selection_details() -> void:
    _window_mode = ("ship" if not _ship.is_empty() else (
        "facility" if not _facility.is_empty() else "colony"))
    _tab = "Обзор" if _window_mode != "facility" else "Процесс"
    _workspace_history.clear()
    _workspace_focus = ""
    _window.visible = true
    _update_selection_card()
    _update_window()

func _update_selection_card() -> void:
    if _selection_card == null:
        return
    var has_selection: bool = not (_body.is_empty() and
        _facility.is_empty() and _ship.is_empty())
    _selection_card.visible = has_selection and not _window.visible
    if not has_selection:
        return
    var projection: Dictionary = ContextData.build(_world, _effective_body(),
        _facility, _ship, _economy)
    _selection_title.text = str(projection.get("title", "Объект"))
    var summary: Array[String] = []
    for card in projection.get("cards", []):
        if card is Dictionary and summary.size() < 3:
            summary.append("%s: %s" % [
                str(card.get("label", "")), str(card.get("value", "—"))])
    _selection_summary.text = "  ·  ".join(summary) if not summary.is_empty() else (
        str(projection.get("subtitle", "Данные отсутствуют")))
    if _ship.is_empty() and _facility.is_empty() and not _body.is_empty():
        var visiting: Array[Dictionary] = ShipPresence.ships_at_body(
            _world, _economy, _body)
        _selection_summary.text += "\nСуда в локациях тела: %d" % visiting.size()
        if not visiting.is_empty():
            _selection_summary.text += " · " + str(visiting[0]["name"])

func _layout_window() -> void:
    if _brand_box != null:
        var compact: bool = size.x < 1150.0
        _brand_box.custom_minimum_size.x = 148.0 if compact else 184.0
        for box in _metric_boxes:
            box.custom_minimum_size.x = 105.0 if compact else 121.0
        if _time_area != null:
            _time_area.custom_minimum_size.x = 170.0 if compact else 210.0
    if _window == null:
        return
    _window.offset_left = 80
    # Figma management sheets are intentionally roomy but never permanent.
    # Leave the 265px right outliner visible at 1366x768 and on wider displays.
    _window.offset_right = minf(1040.0, maxf(550.0, size.x - 350.0))
    _window.offset_top = 142
    _window.offset_bottom = -40

## The already-existing UIFrameProfiler owns timing samples. Reuse its
## scalars; do not sample World, N158 or network from the HUD.
func update_performance(fps: int, sim_ms: float, ui_ms: float,
        worker: bool, details: String = "") -> void:
    if _perf_readout == null:
        return
    var sim_label: String = "SIM" if worker else "SIM p95"
    _perf_readout.text = ("FPS %d  ·  %s %.1fмс\n" +
        "UI p95 %.1fмс  ·  PING —") % [
        maxi(0, fps), sim_label, maxf(0.0, sim_ms), maxf(0.0, ui_ms)]
    _perf_readout.tooltip_text = (
        "PING —: игра исполняется локально, сетевого RTT нет.\n" +
        ("SIM: последний завершённый шаг фонового N158.\n"
            if worker else
            "SIM p95: advance_frame за последние 120 кадров.\n") +
        "UI p95: нагрузка интерфейса за окно профайлера.\n" +
        details)

func _set_ui_scale(index: int) -> void:
    if _game != null:
        _game.call("_change_ui_scale", index)

func _normal_speed() -> void:
    if _game != null:
        _game.call("_change_speed", 1)

func _fast_speed() -> void:
    if _game != null:
        _game.call("_change_speed", 5)

func _toggle_scope() -> void:
    if _effective_body().is_empty():
        _mode = "sector"
    else:
        _mode = "colony" if _mode == "sector" else "sector"
    _update_metrics()
    _brand_scope.text = ("КОЛОНИЯ · " + _body_name(_effective_body()).to_upper() + " ▾"
        if _mode == "colony" else "СЕКТОР · ВСЕ РЫНКИ ▾")
    _update_window()

func _toggle_outliner() -> void:
    _show_outliner = not _show_outliner
    _outliner.visible = _show_outliner

func _close_window() -> void:
    _window.visible = false
    _window_mode = ""
    _workspace_history.clear()
    _workspace_focus = ""
    _update_selection_card()

func _activate(kind: String) -> void:
    if kind in ["map", "center", "save", "load"]:
        if _game != null:
            match kind:
                "map":
                    # Same destination as the visible persistent breadcrumb.
                    if bool(_game.get("_in_system")):
                        _game.call("_go_to_sector")
                    else:
                        _game.call("_open_selected_system")
                "center":
                    _game.call("_reset_map")
                "save":
                    _game.call("_save_game")
                "load":
                    _game.call("_load_game")
        return
    if kind == "outliner":
        _toggle_outliner()
        return
    if kind == "observer":
        if _game != null:
            _game.call("_toggle_observer")
        return
    if kind == "colony" and _body.is_empty():
        for row in _world.get("facilities", []):
            if row is Dictionary and not str(row.get("body", "")).is_empty():
                _select_body(str(row["body"]))
                break
    _workspace_history.clear()
    _workspace_focus = ""
    _window_mode = kind
    _tab = str(FullWorkspaces.TABS.get(kind, ["Данные"])[0])
    _window.visible = true
    _update_window()
    _update_selection_card()

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
    _update_metrics()
    _brand_scope.text = "КОЛОНИЯ · " + _body_name(id).to_upper() + " ▾"
    # Selection is a compact contextual card. Larger management windows are
    # opened explicitly with "Подробнее", as in the Figma reference.
    _update_selection_card()
    _update_window()

func _select_facility(id: String) -> void:
    if _game == null:
        return
    if not bool(_game.get("_in_system")):
        _game.call("_open_selected_system")
    _game.call("_on_facility_selected", id)
    _mode = "colony" if not _effective_body().is_empty() else "sector"
    _update_selection_card()
    _update_window()

func _select_ship(id: String) -> void:
    if _game == null:
        return
    if not bool(_game.get("_in_system")):
        _game.call("_open_selected_system")
    _game.call("_on_ship_selected", id)
    _game.call("_reveal_selected_ship_on_map")
    _update_selection_card()
    _update_window()

func present(world: Dictionary, economy: Dictionary, body: String,
        facility: String, ship: String, tick: int, paused: bool,
        speed: float, status: String, diagnostics: String,
        fleet_diagnostics: Dictionary = {}) -> void:
    var selection_changed: bool = body != _body or facility != _facility or (
        ship != _ship)
    if selection_changed and _window != null and _window.visible and (
            _window_mode in ["colony", "facility", "ship"]):
        if not ship.is_empty():
            _window_mode = "ship"
        elif not facility.is_empty():
            _window_mode = "facility"
        elif not body.is_empty():
            _window_mode = "colony"
        else:
            _window_mode = ""
            _window.hide()
        _tab = "Обзор"
    _fleet_diagnostics = fleet_diagnostics
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
    if _mode == "colony" and _effective_body().is_empty():
        _mode = "sector"
    _clock.text = "ТИК %d  ·  ×%s" % [_tick, str(_speed)]
    _pause.text = "▶" if _paused else "⏸"
    _brand_scope.text = ("КОЛОНИЯ · " + _body_name(_effective_body()).to_upper() + " ▾"
        if _mode == "colony" else "СЕКТОР · ВСЕ РЫНКИ ▾")
    _brand_scope.tooltip_text = ("Запасы рынка выбранной колонии"
        if _mode == "colony" else
        "Сумма запасов всех рынков и населения ВСЕХ фракций; не активы игрока")
    _update_metrics()
    _update_outliner()
    _update_navigation()
    _update_window()
    _update_selection_card()

func _effective_body() -> String:
    if not _body.is_empty():
        return _body
    if not _facility.is_empty():
        for row in _world.get("facilities", []):
            if row is Dictionary and str(row.get("id", "")) == _facility:
                return str(row.get("body", ""))
    return ""

func _body_name(id: String) -> String:
    for row in _world.get("bodies", []):
        if row is Dictionary and str(row.get("id", "")) == id:
            var name: String = str(row.get("name", id))
            return str(QuickData.BODY_NAMES_RU.get(name, name))
    return id

func _scope_locations() -> Dictionary:
    var locations: Dictionary = {}
    if _mode == "sector":
        return locations
    for item in _world.get("facilities", []):
        if item is Dictionary and str(item.get("body", "")) == _effective_body():
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
        selected: bool = false, hint: String = "") -> void:
    var btn := _button(label, callback, 14)
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    if not hint.is_empty():
        btn.tooltip_text = hint
    if selected:
        btn.add_theme_color_override("font_color", TEAL)
        btn.add_theme_stylebox_override("normal", _style(BG2, TEAL))
    _outliner_list.add_child(btn)

func _group(title: String) -> void:
    _outliner_list.add_child(_label(title, 13, TEAL))

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
                var route: Variant = row.get("transit", {})
                var underway: bool = route is Dictionary and not route.is_empty()
                signature += ":" + str(id) + (
                    ":flight" if underway else (
                    ":docked" if not str(row.get("docked_at", "")).is_empty()
                    else ":idle"))
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
            _outliner_entry("◉ " + _body_name(id),
                _select_body.bind(id), id == _body)
    _group("СТАНЦИИ И ПРЕДПРИЯТИЯ")
    for facility in _world.get("facilities", []):
        if facility is Dictionary:
            var id: String = str(facility.get("id", ""))
            _outliner_entry("⌑ " + FacilityNames.display_name(facility),
                _select_facility.bind(id), id == _facility)
    var flying_here: int = 0
    if ships is Dictionary:
        for id in ships:
            var entry: Variant = ships[id]
            if entry is Dictionary and str(entry.get("system_id", "")) == str(
                    _world.get("system", {}).get("id", "")):
                var flight: Variant = entry.get("transit", {})
                if flight is Dictionary and not flight.is_empty():
                    flying_here += 1
    _group("КОРАБЛИ · В ПОЛЁТЕ %d" % flying_here)
    if ships is Dictionary:
        var n: int = 0
        for id in ships:
            var item: Variant = ships[id]
            if not (item is Dictionary) or str(item.get("system_id", "")) != str(
                    _world.get("system", {}).get("id", "")):
                continue
            var route: Variant = item.get("transit", {})
            var flying: bool = route is Dictionary and not route.is_empty()
            var docked: bool = not str(item.get("docked_at", "")).is_empty()
            var marker: String = "↗ " if flying else (
                "■ " if docked else "○ ")
            var hint: String = ("N14: %s → %s" % [
                str(route.get("from", "—")), str(route.get("to", "—"))]
                if flying else (
                "Пристыкован: " + str(item.get("docked_at", ""))
                if docked else "Без активного N14 рейса"))
            _outliner_entry(marker + str(item.get("name", id)),
                _select_ship.bind(str(id)), str(id) == _ship, hint)
            n += 1
            if n >= 16:
                _outliner_list.add_child(_label("Остальные корабли — в разделе «Флот»", 11, MUTED))
                break
    _outliner_list.add_child(_label("Источник: действующий World / N39", 10, MUTED))

## Cross-workspace navigation is a local UI history, not a second
## simulation or new modal window for every React route.
func _route_workspace(mode: String, tab: String, focus: String = "") -> void:
    if _window.visible and not _window_mode.is_empty() and (
            _window_mode != mode or _tab != tab or _workspace_focus != focus):
        _workspace_history.append({
            "mode":_window_mode, "tab":_tab, "focus":_workspace_focus,
            "body":_body, "facility":_facility, "ship":_ship})
        if _workspace_history.size() > 20:
            _workspace_history.pop_front()
    _window_mode = mode
    _tab = tab
    _workspace_focus = focus
    _window.show()
    _update_window()
    _update_selection_card()

func _select_from_workspace(kind: String, id: String) -> void:
    if id.is_empty():
        return
    if _window.visible and not _window_mode.is_empty():
        _workspace_history.append({
            "mode":_window_mode, "tab":_tab, "focus":_workspace_focus,
            "body":_body, "facility":_facility, "ship":_ship})
    match kind:
        "facility":
            _select_facility(id)
            _window_mode = "facility"
            _tab = "Процесс"
        "ship":
            _select_ship(id)
            _window_mode = "ship"
            _tab = "Обзор"
        "body":
            _select_body(id)
            _window_mode = "colony"
            _tab = "Обзор"
        _:
            return
    _workspace_focus = id
    _window.show()
    _update_window()

func _workspace_back() -> void:
    if _workspace_history.is_empty():
        _close_window()
        return
    var record: Dictionary = _workspace_history.pop_back()
    _window_mode = str(record.get("mode", ""))
    _tab = str(record.get("tab", "Обзор"))
    _workspace_focus = str(record.get("focus", ""))
    # Selection in the actual game remains authoritative. History only
    # navigates presentation and never resurrects a stale N39 object.
    _update_window()

func _tabs_for_mode() -> Array[String]:
    match _window_mode:
        "colony":
            return ["Обзор", "Население", "Производство",
                "Запасы", "Строительство", "Логистика", "Данные"]
        "facility":
            return ["Обзор", "Производство", "Склад", "Данные"]
        "economy":
            return ["Запасы", "Производство", "Сигналы", "Данные"]
        "fleet":
            return ["Корабли", "Грузы", "Данные"]
        "ship":
            return ["Обзор", "Груз", "Данные"]
        _:
            return ["Данные"]

func _switch_tab(name: String) -> void:
    if _tab == name:
        return
    _tab = name
    _update_window()

func _render_cards(cards: Array) -> void:
    if _window_cards == null:
        return
    var signature: String = JSON.stringify(cards)
    if signature == _cards_signature:
        return
    _cards_signature = signature
    for child in _window_cards.get_children():
        _window_cards.remove_child(child)
        child.queue_free()
    _window_cards.visible = not cards.is_empty()
    for card in cards:
        if not (card is Dictionary):
            continue
        var panel := _panel()
        panel.add_theme_stylebox_override("panel", _style(BG2, LINE))
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _window_cards.add_child(panel)
        var content := VBoxContainer.new()
        content.add_theme_constant_override("separation", 3)
        panel.add_child(content)
        content.add_child(_label(str(card.get("label", "")), 13, MUTED))
        content.add_child(_label(str(card.get("value", "—")), 22, TEXT))
        var note: String = str(card.get("note", ""))
        if not note.is_empty():
            content.add_child(_label(note, 12, AMBER))

func _update_window() -> void:
    if _window == null or not _window.visible:
        return
    if _workspace_ui != null:
        _workspace_ui.show_state(_window_mode, _tab, _world, _economy,
            _effective_body(), _facility, _ship, _tick, _workspace_focus,
            _diagnostic_text)
        return
    var title: String = str({
        "colony":"КОЛОНИЯ", "economy":"ЭКОНОМИКА",
        "fleet":"ФЛОТ И ЛОГИСТИКА", "facility":"ПРЕДПРИЯТИЕ",
        "ship":"КОРАБЛЬ", "technical":"ТЕХНИЧЕСКИЕ ДАННЫЕ N39"
    }.get(_window_mode, "ОБЗОР"))
    var selected_body: String = _effective_body()
    if _window_mode == "colony" and not selected_body.is_empty():
        title += " · " + _body_name(selected_body)
    _window_title.text = title
    var tabs: Array[String] = _tabs_for_mode()
    if not _tab in tabs:
        _tab = tabs[0]
    var signature: String = _window_mode + "|" + _tab
    if signature != _tabs_signature:
        _tabs_signature = signature
        for child in _window_tabs.get_children():
            _window_tabs.remove_child(child)
            child.queue_free()
        for name in tabs:
            var btn := _button(name, _switch_tab.bind(name), 13)
            if name == _tab:
                btn.add_theme_stylebox_override("normal", _style(BG2, TEAL))
                btn.add_theme_color_override("font_color", TEAL)
            _window_tabs.add_child(btn)
    var lines: Array[String] = []
    var projection: Dictionary = {}
    var use_cards: bool = _tab == "Обзор" and _window_mode in [
        "colony", "facility", "ship"]
    if use_cards:
        projection = ContextData.build(_world, selected_body, _facility,
            _ship, _economy)
        _render_cards(projection.get("cards", []))
    else:
        _render_cards([])
    if _window_mode == "technical":
        lines.append(_diagnostic_text if not _diagnostic_text.is_empty()
            else _status_text)
    elif _tab == "Данные" and _window_mode == "ship":
        lines.append(_ship_diagnostic_text())
    elif _tab == "Данные" and _window_mode == "fleet":
        lines.append(_fleet_diagnostic_text())
    elif _tab == "Данные" and _window_mode == "facility":
        lines.append(_production_text())
    elif _tab == "Данные" and _window_mode == "colony":
        lines.append(_colony_diagnostic_text())
    elif _tab == "Данные" and _window_mode == "economy":
        lines.append(_stocks_text(false))
    elif _tab == "Данные":
        lines.append(_diagnostic_text if not _diagnostic_text.is_empty()
            else _status_text)
    elif _window_mode == "colony":
        lines.append(_colony_window_text(selected_body, projection))
    elif _window_mode == "facility":
        lines.append(_facility_window_text(projection))
    elif _window_mode == "ship":
        lines.append(_ship_window_text(projection))
    elif _window_mode == "fleet":
        lines.append(_fleet_diagnostic_text() + "\n\n" +
            _ships_text(false, _tab == "Грузы"))
    elif _window_mode == "economy":
        match _tab:
            "Производство":
                lines.append(_production_text())
            "Сигналы":
                lines.append(_facility_signals())
            _:
                lines.append(_stocks_text(false))
    else:
        lines.append("Информация недоступна")
    var new_text: String = "\n".join(lines)
    if _window_text.text != new_text:
        _window_text.text = new_text
    _update_ship_links(selected_body)

func _colony_diagnostic_text() -> String:
    var body_id: String = _effective_body()
    if body_id.is_empty():
        return "Выберите колонию."
    var lines: Array[String] = [
        _body_name(body_id).to_upper(),
        "ПОДТВЕРЖДЁННЫЕ ДАННЫЕ · N39", ""]
    for body in _world.get("bodies", []):
        if not (body is Dictionary) or str(body.get("id", "")) != body_id:
            continue
        lines.append("Тип: " + str(body.get("type", "—")))
        lines.append("Биом: " + str(body.get("biome", "—")))
        lines.append("Внешняя среда (исходные данные):")
        var properties: Variant = body.get("resources", {})
        if properties is Dictionary:
            for resource in properties:
                lines.append("  %s: %s" % [
                    str(resource), str(properties[resource])])
        break
    lines.append("")
    lines.append("ПОСТРОЕННЫЕ ОБЪЕКТЫ")
    var total: int = 0
    for facility in _world.get("facilities", []):
        if facility is Dictionary and str(facility.get("body", "")) == body_id:
            lines.append(" • " + FacilityNames.display_name(facility))
            total += 1
    if total == 0:
        lines.append(" • Подтверждённых объектов нет")
    lines.append("")
    lines.append("Рыночные запасы см. во вкладке «Запасы».")
    lines.append("Полный N39 отладочный дамп — кнопка «ДАН» слева.")
    return "\n".join(lines)

func _update_ship_links(body_id: String) -> void:
    if _window_ship_links == null:
        return
    var active: bool = (_window_mode == "colony" and not body_id.is_empty()
        and _tab in ["Обзор", "Логистика"])
    var items: Array[Dictionary] = []
    if active:
        items = ShipPresence.ships_at_body(_world, _economy, body_id)
    var signature: String = (_window_mode + "|" + _tab + "|" + body_id +
        "|" + JSON.stringify(items.map(func(row):
            return [row["id"], row["status"], row["goal"]])))
    if signature == _ship_links_signature:
        return
    _ship_links_signature = signature
    for child in _window_ship_links.get_children():
        _window_ship_links.remove_child(child)
        child.queue_free()
    _window_ship_links.visible = not items.is_empty()
    if items.is_empty():
        return
    _window_ship_links.add_child(_label("КОРАБЛИ У ТЕЛА · %d" % items.size(),
        12, TEAL))
    var limit: int = 8 if _tab == "Логистика" else 4
    for item in items.slice(0, limit):
        var btn := _button("➤ " + str(item["name"]), _select_ship.bind(
            str(item["id"])), 13)
        btn.tooltip_text = str(item["status"]) + "\n" + str(item["goal"])
        _window_ship_links.add_child(btn)

func _body_ship_text(body_id: String) -> String:
    var rows: Array[Dictionary] = ShipPresence.ships_at_body(
        _world, _economy, body_id)
    var lines: Array[String] = [
        "КОРАБЛИ В ЛОКАЦИЯХ ПЛАНЕТЫ: %d" % rows.size(),
        "Только подтверждённые локации N43/N39; посадка не предполагается.", ""]
    if rows.is_empty():
        lines.append("Судов в известных локациях этого тела сейчас нет.")
    for row in rows:
        lines.append("➤ %s · %s" % [str(row["name"]), str(row["class"])])
        lines.append("  %s" % str(row["status"]))
        lines.append("  Задача: %s  ·  локация: %s" % [
            str(row["goal"]), str(row["location"])])
        if not str(row["contract_id"]).is_empty():
            lines.append("  Контракт: " + str(row["contract_id"]))
        lines.append("")
    lines.append("Нажмите на имя корабля выше, чтобы перейти к нему.")
    lines.append("Корабли в полёте смотрите в «Флот» — они ещё не прибыли.")
    return "\n".join(lines)

func _colony_window_text(body_id: String,
        projection: Dictionary) -> String:
    if body_id.is_empty():
        return "Выберите существующую колонию в правом списке или на карте."
    var quick: Dictionary = QuickData.project(_world, body_id, _economy)
    if not bool(quick.get("visible", false)):
        return "На этом небесном теле нет подтверждённого поселения N39."
    match _tab:
        "Обзор":
            var lines: Array[String] = [
                str(projection.get("subtitle", "Обзор колонии"))]
            for item in projection.get("lines", []):
                lines.append(str(item))
            lines.append("")
            lines.append("Данные колонии — реальные рынки и население N39.")
            lines.append("Построек без фактических площадок не показываем.")
            lines.append("")
            lines.append("Суда в локациях планеты: %d" % ShipPresence.ships_at_body(
                _world, _economy, body_id).size())
            lines.append("Вкладка «Логистика» — задачи, стыковка и переход к кораблю.")
            return "\n".join(lines)
        "Население":
            return _population_text(body_id)
        "Производство":
            return _production_text()
        "Запасы":
            return _stocks_text(true)
        "Строительство":
            return _construction_text(body_id)
        "Логистика":
            return _body_ship_text(body_id)
    return "—"

func _population_text(body_id: String) -> String:
    var lines: Array[String] = ["НАСЕЛЕНИЕ · " + _body_name(body_id), ""]
    var locations: Dictionary = _locations_for_body(body_id)
    var population: Variant = _economy.get("populations", {})
    var matched: int = 0
    var total: int = 0
    if population is Dictionary:
        for item in population.values():
            if not (item is Dictionary) or not locations.has(
                    str(item.get("location", ""))):
                continue
            matched += 1
            var count: int = int(item.get("count", 0))
            total += count
            lines.append("%s · жители: %d" % [
                str(item.get("location", "—")), count])
    if matched > 0:
        lines.push_front("ВСЕГО ЖИТЕЛЕЙ: %d" % total)
    else:
        lines.append("Подтверждённое население в снимке отсутствует: —")
    return "\n".join(lines)

func _locations_for_body(body_id: String) -> Dictionary:
    var locations: Dictionary = {}
    for item in _world.get("facilities", []):
        if item is Dictionary and str(item.get("body", "")) == body_id:
            locations[str(item.get("location", ""))] = true
    return locations

func _stocks_text(colony_only: bool) -> String:
    var scope: String = "КОЛОНИЯ · " + _body_name(_effective_body())
    if not colony_only:
        scope = "ВСЕ РЫНКИ СЕКТОРА · ВСЕ ФРАКЦИИ"
    var lines: Array[String] = ["СКЛАДСКИЕ ЗАПАСЫ", scope,
        "Только подтверждённые товары markets.supply, не производство за тик.", ""]
    var markets: Variant = _economy.get("markets", {})
    var locations: Dictionary = _locations_for_body(_effective_body())
    var totals: Dictionary = {}
    if markets is Dictionary:
        for location in markets:
            if colony_only and not locations.has(str(location)):
                continue
            var market: Variant = markets[location]
            if not (market is Dictionary):
                continue
            var stock: Variant = market.get("supply", {})
            if not (stock is Dictionary):
                continue
            for commodity in stock:
                var key: String = str(commodity)
                totals[key] = float(totals.get(key, 0.0)) + float(
                    stock[commodity])
    var names: Array = totals.keys()
    names.sort()
    if names.is_empty():
        lines.append("Запасы в текущем снимке не представлены: —")
    else:
        for name in names:
            lines.append("%s  ·  %s ед." % [
                str(name), str(snappedf(float(totals[name]), 0.01))])
    return "\n".join(lines)

func _construction_text(body_id: String) -> String:
    var lines: Array[String] = [
        "СТРОИТЕЛЬСТВО · " + _body_name(body_id), ""]
    var locations: Dictionary = _locations_for_body(body_id)
    var sites: Variant = _economy.get("construction_sites", null)
    if not (sites is Dictionary):
        lines.append("Данные о реальных стройплощадках пока недоступны.")
        return "\n".join(lines)
    var pending: int = 0
    for id in sites:
        var row: Variant = sites[id]
        if not (row is Dictionary) or bool(row.get("completed", false)):
            continue
        var location: String = str(row.get("location_name",
            row.get("location", "")))
        if not locations.has(location):
            continue
        pending += 1
        lines.append("◈ %s" % str(id))
        lines.append("    Локация: " + location)
        if row.has("progress"):
            lines.append("    Прогресс: " + str(row["progress"]))
        lines.append("")
    if pending == 0:
        lines.append("Активных физических стройплощадок: 0")
    lines.append("Намерения ИИ без реальной площадки не считаются стройкой.")
    return "\n".join(lines)

func _facility_window_text(projection: Dictionary) -> String:
    if _facility.is_empty():
        return "Выберите предприятие на карте или в списке объектов."
    var lines: Array[String] = []
    if _tab == "Склад":
        var live: Variant = _economy.get("facilities", {})
        if live is Dictionary and live.get(_facility) is Dictionary:
            var facility: Dictionary = live[_facility]
            var goods: Variant = facility.get("module_stock", {})
            if goods is Dictionary:
                var stock: Variant = goods.get("stock", {})
                if stock is Dictionary:
                    for commodity in stock:
                        lines.append("%s: %s ед." % [
                            str(commodity), str(stock[commodity])])
        if lines.is_empty():
            lines.append("Подтверждённых локальных запасов нет: —")
    elif _tab == "Производство":
        return _production_text()
    else:
        lines.append(str(projection.get("subtitle", "")))
        for item in projection.get("lines", []):
            lines.append(str(item))
    return "\n".join(lines)

func _ship_window_text(projection: Dictionary) -> String:
    if _ship.is_empty():
        return "Выберите корабль на карте или в списке."
    if _tab == "Груз":
        var fleet: Variant = _economy.get("ships", {})
        if fleet is Dictionary and fleet.get(_ship) is Dictionary:
            var vessel: Dictionary = fleet[_ship]
            var cargo: Variant = vessel.get("cargo", {})
            if cargo is Dictionary:
                var lines: Array[String] = ["ПОДТВЕРЖДЁННЫЙ ГРУЗ", ""]
                for kind in cargo:
                    lines.append("%s: %s ед." % [
                        str(kind), str(cargo[kind])])
                return "\n".join(lines)
        return "Нет доступных данных о грузе: —"
    var lines: Array[String] = [str(projection.get("subtitle", ""))]
    for item in projection.get("lines", []):
        lines.append(str(item))
    return "\n".join(lines)

func _fleet_diagnostic_text() -> String:
    var ships: Variant = _economy.get("ships", null)
    if not (ships is Dictionary):
        return "Снимок флота отсутствует —"
    var flying: int = 0
    var docked: int = 0
    var waiting: int = 0
    var active_contracts: int = 0
    var known_multiple_markets: int = 0
    var plans: int = 0
    var current: int = 0
    var current_system: String = str(_world.get("system", {}).get("id", ""))
    for id in ships:
        var item: Variant = ships[id]
        if not (item is Dictionary):
            continue
        var ship: Dictionary = item
        var transit: Variant = ship.get("transit", {})
        if transit is Dictionary and not transit.is_empty():
            flying += 1
        elif not str(ship.get("docked_at", "")).is_empty():
            docked += 1
        else:
            waiting += 1
        if not str(ship.get("active_contract_id", "")).is_empty():
            active_contracts += 1
        var memory: Variant = ship.get("memory", {})
        if memory is Dictionary and memory.get("price_knowledge", {}) is Dictionary:
            if (memory.get("price_knowledge", {}) as Dictionary).size() >= 2:
                known_multiple_markets += 1
        if ship.get("current_bt", null) is Dictionary and not (
                ship.get("current_bt", {}) as Dictionary).is_empty():
            plans += 1
        if str(ship.get("system_id", "")) == current_system:
            current += 1
    var lines: Array[String] = [
        "СОСТОЯНИЕ ФЛОТА · N39",
        "Всего: %d  ·  в этой системе: %d" % [ships.size(), current],
        "В полёте: %d  ·  пристыковано: %d  ·  без рейса: %d" % [
            flying, docked, waiting],
        "Контрактов на кораблях: %d  ·  активных планов BT: %d" % [
            active_contracts, plans],
        "Известно 2+ рынков (для N83): %d / %d кораблей" % [
            known_multiple_markets, ships.size()],
        ""]
    if not _fleet_diagnostics.is_empty():
        var due: int = int(_fleet_diagnostics.get("n140_ship_fired_this_tick",
            _fleet_diagnostics.get("n140_fired", -1)))
        if due >= 0:
            lines.append("N140: решение принято для %d кораблей в последнем тике" % due)
        var accepted: int = int(_fleet_diagnostics.get(
            "n153_accepted_this_tick",
            _fleet_diagnostics.get("n153_accepted", -1)))
        if accepted >= 0:
            lines.append("N153: контрактов принято за тик: %d" % accepted)
        if _fleet_diagnostics.has("n83_trade_plans_this_tick"):
            lines.append("N83: торговых планов за тик: %d" % int(
                _fleet_diagnostics["n83_trade_plans_this_tick"]))
        var launches: int = int(_fleet_diagnostics.get(
            "n153_departures_this_tick",
            (_fleet_diagnostics.get("n84_departures", []) as Array).size()))
        lines.append("N84 → N14: команд BeginTransit за тик: %d" % launches)
        var blocked: int = int(_fleet_diagnostics.get(
            "n153_blocked_this_tick",
            (_fleet_diagnostics.get("n153_blocked", []) as Array).size()))
        if blocked > 0:
            lines.append("N153: отклонено %d предложений" % blocked)
            var blocker: String = str(_fleet_diagnostics.get(
                "n153_first_blocker", ""))
            var reasons: Array = _fleet_diagnostics.get("n153_blocked", [])
            if blocker.is_empty() and not reasons.is_empty():
                if reasons[0] is Dictionary:
                    blocker = str(reasons[0].get("reason", ""))
            if not blocker.is_empty() and blocker != "—":
                lines.append("Первое препятствие: " + blocker)
    lines.append("")
    if known_multiple_markets == 0 and ships.size() > 0:
        lines.append("N83: ни один корабль пока не знает цены двух рынков.")
        lines.append("Без подтверждённых цен N83 не строит торговый маршрут.")
    if flying == 0:
        lines.append("СЕЙЧАС НИ ОДИН КОРАБЛЬ НЕ НАХОДИТСЯ В ПОЛЁТЕ.")
        lines.append("Это реальный статус transit, а не проблема анимации.")
        lines.append("Для движения нужен действительный приказ N84/N146.")
    else:
        lines.append("Физический N14 transit подтверждён у %d кораблей." % flying)
    lines.append("Показатели ИИ относятся к последнему тиковому шагу,")
    lines.append("а не ко всей истории игры.")
    return "\n".join(lines)

func _ship_diagnostic_text() -> String:
    var ships: Variant = _economy.get("ships", {})
    if not (ships is Dictionary) or not (
            ships.get(_ship) is Dictionary):
        return "Выбранного корабля нет в последнем N39 снимке."
    var vessel: Dictionary = ships[_ship]
    var lines: Array[String] = [
        str(vessel.get("name", _ship)),
        "ID: " + _ship,
        "Тип: " + str(vessel.get("class", "—")),
        "Фракция: " + str(vessel.get("faction_id", "—")),
        "Локация: " + str(vessel.get("location", "—")),
        "Текущая цель: " + str(vessel.get("current_goal", "—")),
        "Активный контракт: " + str(vessel.get("active_contract_id", "—")),
        "Док: " + str(vessel.get("docked_at", "—")),
        "Топливо: %s / %s" % [
            str(vessel.get("fuel", "—")),
            str(vessel.get("fuel_capacity", "—"))], ""]
    var transit: Variant = vessel.get("transit", {})
    if transit is Dictionary and not transit.is_empty():
        lines.append("ПОДТВЕРЖДЁННЫЙ N14 РЕЙС")
        lines.append("%s → %s" % [
            str(transit.get("from", "—")),
            str(transit.get("to", "—"))])
        lines.append("Отправление: тик " + str(
            transit.get("departure_tick", "—")))
        lines.append("Прибытие: тик " + str(
            transit.get("arrival_tick", "—")))
    else:
        lines.append("N14: нет активного рейса")
        lines.append("Наличие корабля не означает, что ИИ назначил полёт.")
    var memory: Variant = vessel.get("memory", {})
    if memory is Dictionary:
        var knowledge: Variant = memory.get("price_knowledge", {})
        if knowledge is Dictionary:
            lines.append("Цены известных рынков: %d" % knowledge.size())
            if knowledge.size() < 2:
                lines.append("N83: недостаточно данных для поиска торгового маршрута.")
    var bt: Variant = vessel.get("current_bt", null)
    lines.append("План N84: " + (
        "сохранён" if bt is Dictionary and not bt.is_empty()
        else "нет"))
    return "\n".join(lines)

func _ships_text(colony_only: bool, cargo_only: bool) -> String:
    var lines: Array[String] = [
        "КОРАБЛИ · ОДИН ЖИВОЙ СНИМОК N39", ""]
    var fleet: Variant = _economy.get("ships", null)
    if not (fleet is Dictionary):
        return "Флот в текущем снимке ещё недоступен: —"
    var count: int = 0
    var locations: Dictionary = _locations_for_body(_effective_body())
    for ship_id in fleet:
        var row: Variant = fleet[ship_id]
        if not (row is Dictionary):
            continue
        if colony_only and not locations.has(str(row.get("location", ""))):
            continue
        var name: String = str(row.get("name", ship_id))
        var cargo: Variant = row.get("cargo", {})
        if cargo_only:
            lines.append("%s · груз: %s" % [name, str(cargo)])
        else:
            lines.append("%s · %s" % [name,
                str(row.get("location", "—"))])
        count += 1
        if count >= 40:
            lines.append("Показаны первые 40 кораблей; остальное — в N39.")
            break
    if count == 0:
        lines.append("В этом представлении корабли не найдены.")
    if colony_only:
        lines.append("Список по текущей локации, не прогноз доставки.")
    return "\n".join(lines)

func _facility_signals() -> String:
    var lines: Array[String] = [
        "ПРОВЕРЕННЫЕ СИГНАЛЫ · ИЗНОС / ЗАБРОШЕННОСТЬ", ""]
    var live: Variant = _economy.get("facilities", {})
    var found: int = 0
    if live is Dictionary:
        for id in live:
            var row: Variant = live[id]
            if not (row is Dictionary):
                continue
            var abandoned: bool = bool(row.get("abandoned", false))
            var damaged: bool = row.has("condition") and (
                float(row["condition"]) < 0.8)
            if not abandoned and not damaged:
                continue
            found += 1
            lines.append("%s · %s" % [str(id),
                "Заброшено" if abandoned else "Износ"])
    if found == 0:
        lines.append("Сигналов по известным состояниям не обнаружено.")
    lines.append("")
    lines.append("Причины дефицита отдельно не вычисляются без N39 данных.")
    return "\n".join(lines)

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
        lines.append(FacilityNames.display_name(facility))
        lines.append("  Тип: %s · владелец: %s" % [
            FacilityNames.type_name(str(facility.get("type", "—"))),
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
    if not (event is InputEventKey) or not event.pressed or (
            event.echo or event.keycode != KEY_ESCAPE):
        return
    if _window != null and _window.visible:
        _close_window()
    elif _game != null and bool(_game.get("_in_system")):
        _game.call("_return_to_sector")
    else:
        return
    get_viewport().set_input_as_handled()
