extends Control
const QuickData = preload("res://scripts/view/colony_quick_projection.gd")
const ContextData = preload("res://scripts/view/colony_context_projection.gd")
const FacilityNames = preload("res://scripts/view/facility_labels_ru.gd")
const ShipPresence = preload("res://scripts/view/ship_body_projection.gd")
const FullWorkspaces = preload("res://scripts/view/strategy_workspaces.gd")
const FigmaIcons = preload("res://scripts/view/figma_strategy_icons.gd")
const LSTheme = preload("res://scripts/view/ls_ui_theme.gd")
const LSLayout = preload("res://scripts/view/ls_ui_layout.gd")
const LSComponents = preload("res://scripts/view/ls_ui_components.gd")
## Living Sector strategy HUD — Figma-inspired, read-only presentation.
## The game owns the map, authoritative economy, orders and clock.
## Never requests a new world_snapshot or invents per-tick trends.
const BG = Color("#09141C")
const BG2 = Color("#0D1B24")
const LINE = Color("#243942")
const TEAL = Color("#53B5AC")
const AMBER = Color("#C99B54")
# Figma shell block 1: all geometry uses the same logical pixel grid.
# Figma design baseline. The actual header height is derived from native
# Control minimum height, not the nominal baseline: FPS has two lines.
const TOP_H: float = 58.0
const FOOT_H: float = 24.0
const RAIL_W: float = 64.0
const OUT_W: float = 264.0
const COMPACT_OUT_W: float = 242.0
const GUTTER: float = 12.0
const TEXT = Color("#C4D0D3")
const MUTED = Color("#748B92")
# Figma V1 order: population → food → water → energy → advanced goods.
# Ore replaces the prototype's unsupported credit trend with real N39 stocks.
const METRICS: Array[Dictionary] = [
    {"key": "population", "label": "НАСЕЛЕНИЕ", "symbol": "●"},
    {"key": "food", "label": "ЕДА", "symbol": "◒"},
    {"key": "water", "label": "ВОДА", "symbol": "▽"},
    {"key": "energy_cells", "label": "ЭНЕРГИЯ", "symbol": "ϟ"},
    {"key": "metals", "label": "МЕТАЛЛЫ", "symbol": "⬡"},
    {"key": "ore", "label": "РУДА", "symbol": "◆"}
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
var _effective_top_h: float = TOP_H
var _rail: PanelContainer
var _rail_buttons: Dictionary = {}
var _rail_active: String = ""
var _tools_button: Button
var _tools_menu: PopupMenu
var _outliner_reopen: Button
var _outliner_close_button: Button
var _alerts_close_button: Button
var _footer_panel: PanelContainer
var _metric_boxes: Array[VBoxContainer] = []
var _brand_scope: Button
var _metric_nodes: Dictionary = {}
var _clock: Label
var _perf_readout: Label
var _perf_detail_text: String = ""
var _pause: Button
var _alert_button: Button
var _alert_count: Label
var _alerts_popover: PanelContainer
var _alerts_contents: VBoxContainer
var _alerts_signature: String = ""
var _footer_status: Label
var _outliner: PanelContainer
var _outliner_scope: Label
var _outliner_list: VBoxContainer
var _outliner_signature: String = ""
var _outliner_filter_mode: String = "all"
var _outliner_filter_buttons: Dictionary = {}
var _outliner_group_open: Dictionary = {
    "colonies":true, "bodies":false, "production":true,
    "stations":true, "fleet":true, "construction":true}

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
var _scale_button: Button
var _scale_caption: Label
var _scale_popup: PopupMenu
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
    box.anti_aliasing = false
    return box

func _label(value: String, size_px: int = 14, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", size_px)
    label.add_theme_color_override("font_color", color)
    label.clip_text = true
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label

func _button(value: String, callback: Callable, size_px: int = 12) -> Button:
    var button := Button.new()
    button.text = value
    button.add_theme_font_size_override("font_size", size_px)
    button.add_theme_color_override("font_color", TEXT)
    button.add_theme_color_override("font_hover_color", Color("#A4E8DE"))
    button.add_theme_stylebox_override("normal", _style(BG, LINE, 0, 0, 0, 1))
    button.add_theme_stylebox_override("hover", _style(Color("#132B34"), TEAL, 0, 0, 0, 2))
    button.add_theme_stylebox_override("pressed", _style(Color("#193B42"), TEAL, 0, 0, 0, 2))
    button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, TEAL))
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(callback)
    return button

func _panel() -> PanelContainer:
    var panel := PanelContainer.new()
    var frame: StyleBoxFlat = _style(BG, LINE)
    frame.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
    frame.shadow_size = 3
    panel.add_theme_stylebox_override("panel", frame)
    return panel

func attach(game: Control) -> void:
    _game = game

func _ready() -> void:
    # Base UI theme is shared; pre-existing per-control overrides stay intact.
    # New reusable components use named LS* theme variations.
    theme = LSTheme.build()
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_top()
    _build_alerts()
    _build_left()
    _build_outliner()
    _build_navigation()
    _build_window()
    _build_selection_card()
    _build_footer()
    resized.connect(_layout_window)
    set_process_unhandled_key_input(true)
    _layout_window()

func _build_top() -> void:
    # Figma Make .topbar: 58px chrome. No UI profiling data is discarded:
    # performance scalars are rendered in the 24px footer instead.
    _top = LSComponents.chrome_panel(&"LSHeaderPanel")
    _top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _top.offset_bottom = TOP_H
    _top.z_index = 100
    _top.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_top)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 0)
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _top.add_child(row)

    # 192px brand, icon and two-line name/scope.
    var brand := VBoxContainer.new()
    _brand_box = brand
    brand.custom_minimum_size.x = 192
    brand.add_theme_constant_override("separation", 0)
    row.add_child(brand)
    var brand_identity := HBoxContainer.new()
    brand_identity.size_flags_vertical = Control.SIZE_EXPAND_FILL
    brand_identity.add_theme_constant_override("separation", 10)
    brand.add_child(brand_identity)
    var emblem: PanelContainer = LSComponents.chrome_panel(&"LSBrandEmblem")
    emblem.custom_minimum_size = Vector2(34, 34)
    emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    brand_identity.add_child(emblem)
    var initials := _label("LS", 11, Color("#93D1CA"))
    initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    emblem.add_child(initials)
    var brand_text := VBoxContainer.new()
    brand_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    brand_text.alignment = BoxContainer.ALIGNMENT_CENTER
    brand_text.add_theme_constant_override("separation", 2)
    brand_identity.add_child(brand_text)
    var wordmark := _label("LIVING SECTOR", 12, Color("#E1E9E9"))
    brand_text.add_child(wordmark)
    _brand_scope = LSComponents.header_scope("СЕКТОР · ВСЕ РЫНКИ ▾", _toggle_scope)
    _brand_scope.tooltip_text = "Выбранная область рыночных запасов; не бюджет фракции"
    brand_text.add_child(_brand_scope)

    # Six actual N39 resources (not the Figma prototype's invented trends).
    # Each tile uses its own icon and name/value text styles from Theme.
    for item in METRICS:
        var resource_tile: PanelContainer = LSComponents.header_resource()
        resource_tile.tooltip_text = "Текущие подтверждённые запасы, без прогнозов."
        row.add_child(resource_tile)
        var resource_row := HBoxContainer.new()
        resource_row.alignment = BoxContainer.ALIGNMENT_CENTER
        resource_row.add_theme_constant_override("separation", 6)
        resource_tile.add_child(resource_row)
        var icon: Label = LSComponents.metric_text(
            str(item["symbol"]), &"LSHeaderResourceIcon")
        icon.custom_minimum_size.x = 25
        icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        resource_row.add_child(icon)
        var box := VBoxContainer.new()
        _metric_boxes.append(box)
        box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_theme_constant_override("separation", 2)
        resource_row.add_child(box)
        box.add_child(LSComponents.metric_text(
            str(item["label"]).to_upper(), &"LSHeaderResourceName"))
        var large: Label = LSComponents.metric_text("—", &"LSHeaderResourceValue")
        box.add_child(large)
        _metric_nodes[str(item["key"])] = large

    _alert_button = LSComponents.header_alert(_toggle_alerts)
    _alert_button.icon = FigmaIcons.texture("alert", 17, AMBER)
    _alert_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _alert_button.tooltip_text = "Журнал важных сигналов N39"
    row.add_child(_alert_button)
    _alert_count = _label("", 9, Color("#14150F"))
    _alert_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var badge_style := _style(AMBER, AMBER, 0, 0, 0, 0)
    badge_style.set_content_margin_all(0)
    _alert_count.add_theme_stylebox_override("normal", badge_style)
    _alert_count.position = Vector2(27, 8)
    _alert_count.size = Vector2(15, 15)
    _alert_count.visible = false
    _alert_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _alert_button.add_child(_alert_count)

    # Figma .date is 118px and sits between alerts and speed controls.
    # Living Sector exposes real ticks, not a fabricated calendar date.
    var time_area := VBoxContainer.new()
    _time_area = time_area
    time_area.custom_minimum_size.x = 118
    time_area.alignment = BoxContainer.ALIGNMENT_CENTER
    time_area.add_theme_constant_override("separation", 2)
    row.add_child(time_area)
    _clock = LSComponents.metric_text("ТИК — · ×1", &"LSHeaderClock")
    _clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    time_area.add_child(_clock)
    var cycle_caption := _label("АВТОНОМНЫЙ СЕКТОР", 7, Color("#668087"))
    cycle_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    time_area.add_child(cycle_caption)

    var controls := HBoxContainer.new()
    controls.add_theme_constant_override("separation", 0)
    row.add_child(controls)
    _pause = LSComponents.header_speed("⏸", func() -> void:
        if _game != null:
            _game.call("_toggle_pause"))
    _pause.tooltip_text = "Пауза / продолжить (настоящие часы N158)"
    controls.add_child(_pause)
    var slower := LSComponents.header_speed("×1", _normal_speed)
    slower.tooltip_text = "Нормальная скорость симуляции N158"
    controls.add_child(slower)
    var faster := LSComponents.header_speed("×16", _fast_speed)
    faster.tooltip_text = "Ускорение симуляции N158 до ×16"
    controls.add_child(faster)

func _build_alerts() -> void:
    _alerts_popover = LSComponents.chrome_panel(&"LSAlertsPopover")
    _alerts_popover.visible = false
    _alerts_popover.anchor_left = 1.0
    _alerts_popover.anchor_right = 1.0
    _alerts_popover.offset_left = -610
    _alerts_popover.offset_right = -282
    _alerts_popover.offset_top = TOP_H + 64
    _alerts_popover.offset_bottom = TOP_H + 380
    _alerts_popover.z_index = 80
    _alerts_popover.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_alerts_popover)
    var contents := VBoxContainer.new()
    contents.add_theme_constant_override("separation", 7)
    _alerts_popover.add_child(contents)
    var head := HBoxContainer.new()
    contents.add_child(head)
    var title := _label("СИГНАЛЫ СИМУЛЯЦИИ", 14, TEXT)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    _alerts_close_button = _button("×", _close_alerts, 16)
    _alerts_close_button.custom_minimum_size = Vector2(36, 32)
    _alerts_close_button.tooltip_text = "Закрыть сигналы"
    head.add_child(_alerts_close_button)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    contents.add_child(scroll)
    _alerts_contents = VBoxContainer.new()
    _alerts_contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_alerts_contents)

func _close_alerts() -> void:
    if _alerts_popover == null:
        return
    _alerts_popover.hide()
    _update_selection_card()

func _toggle_alerts() -> void:
    if _alerts_popover == null:
        return
    if _alerts_popover.visible:
        _close_alerts()
        return
    # Popups and management workspaces are mutually exclusive.
    if _window != null and _window.visible:
        _close_window()
    _alerts_popover.show()
    _alerts_signature = ""
    _update_alerts()
    if _selection_card != null:
        _selection_card.hide()

func _update_alerts() -> void:
    if _alert_button == null:
        return
    var problems: Array[Dictionary] = []
    var display_names: Dictionary = {}
    for source in _world.get("facilities", []):
        if source is Dictionary:
            display_names[str(source.get("id", ""))] = FacilityNames.display_name(source)
    var live: Variant = _economy.get("facilities", {})
    if live is Dictionary:
        for id in live:
            var raw: Variant = live[id]
            if not (raw is Dictionary):
                continue
            var full_name: String = str(display_names.get(str(id), str(id)))
            var brief: String = full_name
            if brief.length() > 28:
                brief = brief.substr(0, 27) + "…"
            if bool(raw.get("abandoned", false)):
                problems.append({"id":str(id), "title":"Объект заброшен",
                    "full_name":full_name, "value":brief + " · заброшен"})
            elif raw.has("condition") and float(raw["condition"]) < 0.8:
                problems.append({"id":str(id), "title":"Износ предприятия",
                    "full_name":full_name,
                    "value":"%s · %.1f%%" % [
                        brief, float(raw["condition"]) * 100.0]})
    _alert_button.tooltip_text = "Сигналы N39: %d · открыть" % problems.size()
    _alert_button.text = ""
    if _alert_count != null:
        _alert_count.text = ("99+" if problems.size() > 99
            else str(problems.size()))
        _alert_count.visible = not problems.is_empty()
    if _alerts_contents == null or not _alerts_popover.visible:
        return
    var signature: String = JSON.stringify(problems)
    if signature == _alerts_signature:
        return
    _alerts_signature = signature
    for child in _alerts_contents.get_children():
        _alerts_contents.remove_child(child)
        child.queue_free()
    if problems.is_empty():
        _alerts_contents.add_child(_label(
            "Подтверждённых сигналов износа пока нет.", 13, MUTED))
    else:
        for issue in problems.slice(0, 12):
            var id: String = str(issue["id"])
            var action := _button("⚠ " + str(issue["value"]),
                func() -> void:
                    _toggle_alerts()
                    _select_from_workspace("facility", id), 12)
            action.tooltip_text = ("%s\n%s\nN39 ID: %s" % [
                str(issue["title"]), str(issue["full_name"]), id])
            action.alignment = HORIZONTAL_ALIGNMENT_LEFT
            action.clip_text = true
            action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            action.custom_minimum_size.y = 36
            _alerts_contents.add_child(action)
    var all := _button("ЭКОНОМИЧЕСКИЕ УЗКИЕ МЕСТА  ›",
        func() -> void:
            _toggle_alerts()
            _route_workspace("economy", "Узкие места"), 12)
    _alerts_contents.add_child(all)

func _build_footer() -> void:
    # Figma Make .statusbar: keep it 24px tall; FPS/SIM/UI have been moved
    # here from the old multi-line 82px top HUD without polling N39.
    var panel: PanelContainer = LSComponents.chrome_panel(&"LSFooterPanel")
    _footer_panel = panel
    panel.z_index = 10
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.anchor_left = 0.0
    panel.anchor_right = 1.0
    panel.offset_left = RAIL_W
    panel.offset_right = -OUT_W
    panel.offset_top = -FOOT_H
    panel.offset_bottom = 0
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(panel)
    var status_row := HBoxContainer.new()
    status_row.add_theme_constant_override("separation", 10)
    panel.add_child(status_row)
    _footer_status = _label("СЕКТОР · Наблюдение", 9, MUTED)
    _footer_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status_row.add_child(_footer_status)
    _perf_readout = LSComponents.metric_text(
        "FPS — · SIM — · UI —", &"LSFooterDiagnostic")
    _perf_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _perf_readout.size_flags_horizontal = Control.SIZE_SHRINK_END
    _perf_readout.tooltip_text = "Диагностика производительности профайлера UIFrame"
    status_row.add_child(_perf_readout)

# Native Godot Buttons include text in their minimum width even when
# clip_text=true. Put visible text in a mouse-ignored child to preserve
# the exact 64px Figma rail without sacrificing readable labels.
func _rail_utility_button(caption: String,
        action: Callable) -> Button:
    var btn: Button = LSComponents.action_button("", action)
    btn.theme_type_variation = &"LSNavUtilityButton"
    btn.custom_minimum_size = Vector2(48, 29)
    var text_label := _label(caption, 9, TEXT)
    text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    btn.add_child(text_label)
    text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return btn

func _build_left() -> void:
    # Figma Make .leftnav: width 64px, rows 58px, icon + Russian caption
    # + numeric keyboard hint. Physical readability comes from UI scaling.
    # Native 64px Figma left rail; shared Theme owns gradient fallback,
    # border and padding instead of a private StyleBox per scene.
    _rail = LSComponents.chrome_panel(&"LSRailPanel")
    _rail.anchor_bottom = 1.0
    _rail.offset_top = TOP_H
    _rail.offset_right = RAIL_W
    _rail.offset_bottom = -FOOT_H
    _rail.z_index = 22
    _rail.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_rail)
    var column := VBoxContainer.new()
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 3)
    _rail.add_child(column)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.mouse_filter = Control.MOUSE_FILTER_STOP
    column.add_child(scroll)
    var menu := VBoxContainer.new()
    menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    menu.add_theme_constant_override("separation", 0)
    scroll.add_child(menu)
    for spec in [
        {"name":"Колонии", "action":"colony", "icon":"colony", "key":"1"},
        {"name":"Экономика", "action":"economy", "icon":"economy", "key":"2"},
        {"name":"Строительство", "action":"construction", "icon":"construction", "key":"3"},
        {"name":"Исследования", "action":"research", "icon":"research", "key":"4"},
        {"name":"Флоты", "action":"fleet", "icon":"fleet", "key":"5"},
        {"name":"Управление", "action":"administration", "icon":"administration", "key":"6"}
    ]:
        var action: String = str(spec["action"])
        var btn: Button = LSComponents.action_button(
            "", _activate.bind(action))
        btn.theme_type_variation = &"LSNavButton"
        btn.custom_minimum_size = Vector2(48, 58)
        btn.tooltip_text = str(spec["name"]) + " [" + str(spec["key"]) + "]"
        menu.add_child(btn)
        _rail_buttons[action] = btn
        var content := VBoxContainer.new()
        content.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.alignment = BoxContainer.ALIGNMENT_CENTER
        content.add_theme_constant_override("separation", 2)
        btn.add_child(content)
        content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var glyph := TextureRect.new()
        glyph.texture = FigmaIcons.texture(str(spec["icon"]), 19, TEAL)
        glyph.custom_minimum_size = Vector2(19, 19)
        glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
        glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.add_child(glyph)
        var name: String = str(spec["name"])
        var caption := _label(name, 8, TEXT)
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.tooltip_text = btn.tooltip_text
        content.add_child(caption)
        var hotkey := _label(str(spec["key"]), 8, Color("#526B73"))
        hotkey.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
        hotkey.offset_left = -13
        hotkey.offset_right = -3
        hotkey.offset_top = 2
        hotkey.offset_bottom = 14
        btn.add_child(hotkey)

    var bottom := VBoxContainer.new()
    bottom.add_theme_constant_override("separation", 2)
    column.add_child(bottom)
    var objects := _rail_utility_button("Список", _toggle_outliner)
    objects.tooltip_text = "Показать или скрыть правый аутлайнер"
    bottom.add_child(objects)
    _tools_button = _rail_utility_button("⋯ Меню", _show_nav_tools)
    _tools_button.tooltip_text = "Журнал, карта, сохранение и загрузка"
    bottom.add_child(_tools_button)
    # OptionButton inside a 64px PanelContainer forced its minimum width
    # to 98px. Keep the compatibility picker for tests, but render a
    # compact scale button and a native popup outside layout sizing.
    _ui_scale_menu = OptionButton.new()
    _ui_scale_menu.visible = false
    for percent in [125, 140, 160, 180, 200]:
        _ui_scale_menu.add_item("%d%%" % percent)
    _ui_scale_menu.select(clampi(int(_game.get("_ui_scale_index"))
        if _game != null else 2, 0, _ui_scale_menu.item_count - 1))
    _ui_scale_menu.item_selected.connect(_set_ui_scale)
    add_child(_ui_scale_menu)
    _scale_button = _rail_utility_button(
        _ui_scale_menu.get_item_text(_ui_scale_menu.selected),
        _show_scale_choices)
    _scale_caption = _scale_button.get_child(0) as Label
    _scale_button.tooltip_text = "Выбор размера интерфейса (125–200%)"
    bottom.add_child(_scale_button)
    _scale_popup = PopupMenu.new()
    for i in range(_ui_scale_menu.item_count):
        _scale_popup.add_radio_check_item(
            _ui_scale_menu.get_item_text(i), i)
        _scale_popup.set_item_checked(i, i == _ui_scale_menu.selected)
    _scale_popup.id_pressed.connect(_choose_scale)
    _rail.add_child(_scale_popup)
    _tools_menu = PopupMenu.new()
    for name in [
        "Аутлайнер", "Технические данные N39", "Наблюдение",
        "Сектор / система", "Центрировать", "Сохранить", "Загрузить"
    ]:
        _tools_menu.add_item(name)
    _tools_menu.id_pressed.connect(_on_tools_selected)
    _rail.add_child(_tools_menu)

func _show_scale_choices() -> void:
    if _scale_button == null or _scale_popup == null:
        return
    var origin: Vector2 = _scale_button.get_screen_transform().origin
    _scale_popup.position = Vector2i(origin + Vector2(RAIL_W + 4, -80))
    _scale_popup.popup()

func _choose_scale(index: int) -> void:
    if _ui_scale_menu == null or index < 0 or index >= _ui_scale_menu.item_count:
        return
    _ui_scale_menu.select(index)
    _set_ui_scale(index)

func _show_nav_tools() -> void:
    if _tools_button == null or _tools_menu == null:
        return
    var pos: Vector2 = _tools_button.get_screen_transform().origin
    _tools_menu.position = Vector2i(pos + Vector2(RAIL_W + 4, -70))
    _tools_menu.popup()

func _on_tools_selected(id: int) -> void:
    var actions: Array[String] = [
        "outliner", "technical", "observer", "map",
        "center", "save", "load"]
    if id >= 0 and id < actions.size():
        _activate(actions[id])

func _sync_rail_active() -> void:
    var current: String = _window_mode if _window != null and (
        _window.visible) else ""
    if current == _rail_active:
        return
    _rail_active = current
    for action in _rail_buttons:
        var btn: Button = _rail_buttons[action]
        var selected: bool = str(action) == current
        btn.theme_type_variation = (
            &"LSNavButtonSelected" if selected else &"LSNavButton")

func _build_outliner() -> void:
    _outliner = LSComponents.chrome_panel(&"LSOutlinerPanel")
    _outliner.z_index = 25
    _outliner.mouse_filter = Control.MOUSE_FILTER_STOP
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
    var header_bg: PanelContainer = LSComponents.chrome_panel(
        &"LSOutlinerHeader")
    col.add_child(header_bg)
    var head := HBoxContainer.new()
    head.custom_minimum_size.y = 50
    head.add_theme_constant_override("separation", 5)
    header_bg.add_child(head)
    var header_titles := VBoxContainer.new()
    header_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header_titles.add_theme_constant_override("separation", 2)
    head.add_child(header_titles)
    _outliner_scope = _label("СЕКТОР", 9, Color("#608187"))
    header_titles.add_child(_outliner_scope)
    var caption := _label("Аутлайнер", 15, Color("#D3DDDD"))
    header_titles.add_child(caption)
    _outliner_close_button = _button("›", _toggle_outliner, 19)
    _outliner_close_button.custom_minimum_size = Vector2(36, 32)
    _outliner_close_button.tooltip_text = "Свернуть аутлайнер"
    head.add_child(_outliner_close_button)
    var filters := HBoxContainer.new()
    filters.add_theme_constant_override("separation", 3)
    col.add_child(filters)
    for entry in [
        {"mode":"all","text":"ВСЕ"},
        {"mode":"flight","text":"В ПУТИ"},
        {"mode":"docked","text":"У ДОКА"}]:
        var key: String = str(entry["mode"])
        var filter_btn: Button = LSComponents.outliner_filter(
            str(entry["text"]), _set_outliner_filter.bind(key))
        filters.add_child(filter_btn)
        _outliner_filter_buttons[key] = filter_btn
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(scroll)
    _outliner_list = VBoxContainer.new()
    _outliner_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _outliner_list.add_theme_constant_override("separation", 3)
    scroll.add_child(_outliner_list)
    _outliner_reopen = _button("‹  ОБЪЕКТЫ", _toggle_outliner, 11)
    _outliner_reopen.z_index = 28
    _outliner_reopen.tooltip_text = "Развернуть аутлайнер"
    _outliner_reopen.anchor_left = 1.0
    _outliner_reopen.anchor_right = 1.0
    _outliner_reopen.offset_left = -122
    _outliner_reopen.offset_right = -8
    _outliner_reopen.offset_top = TOP_H + 10
    _outliner_reopen.offset_bottom = TOP_H + 48
    _outliner_reopen.visible = false
    add_child(_outliner_reopen)

## Persistent map breadcrumb. The former legacy "К сектору" button was
## hidden by the Figma shell, which made leaving another system undiscoverable.
## Keep this readable at 100–140% without reserving half of the map.
func _build_navigation() -> void:
    _nav_panel = LSComponents.chrome_panel(&"LSMapBreadcrumb")
    _nav_panel.z_index = 35
    _nav_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _nav_panel.offset_left = RAIL_W + GUTTER
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
    # Full Figma workspace shell now shares the same Theme source
    # as inner panels. Zero inset avoids duplicate 8px page padding.
    _window = LSComponents.chrome_panel(&"LSWindowPanel")
    _window.z_index = 50
    _window.mouse_filter = Control.MOUSE_FILTER_STOP
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
    _selection_card = LSComponents.chrome_panel(&"LSSelectionPanel")
    _selection_card.z_index = 40
    _selection_card.mouse_filter = Control.MOUSE_FILTER_STOP
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
    if _alerts_popover != null:
        _alerts_popover.hide()
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
    _selection_card.visible = (has_selection and not _window.visible and
        (_alerts_popover == null or not _alerts_popover.visible))
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
    # Layout is derived from the post-scale logical viewport. No artificial
    # 640px minimum that can move Controls outside a small game window.
    var vw: float = maxf(1.0, size.x)
    var vh: float = maxf(1.0, size.y)
    if _brand_box != null:
        # Keep the clock/buttons visible first. Resource chips can be read
        # from Economy when the viewport is too narrow for all six.
        var count: int = (
            6 if vw >= 1220.0 else (
            5 if vw >= 1020.0 else (
            4 if vw >= 855.0 else (
            3 if vw >= 680.0 else (2 if vw >= 510.0 else 1)))))
        _brand_box.custom_minimum_size.x = (
            140.0 if vw < 845.0 else (
            168.0 if vw < 1160.0 else 192.0))
        for i in range(_metric_boxes.size()):
            var resource_tile: Control = _metric_boxes[i].get_parent().get_parent()
            resource_tile.visible = i < count
            resource_tile.custom_minimum_size.x = (
                82.0 if vw < 845.0 else (
                96.0 if vw < 1160.0 else 104.0))
        if _time_area != null:
            _time_area.custom_minimum_size.x = (
                104.0 if vw < 1160.0 else 118.0)
    var header_h: float = TOP_H
    if _top != null:
        header_h = maxf(TOP_H, _top.get_combined_minimum_size().y)
        _top.offset_bottom = header_h
    _effective_top_h = header_h
    var layout: Dictionary = LSLayout.calculate(
        Vector2(vw, vh), header_h,
        _window != null and _window.visible, _show_outliner)
    var left: float = float(layout["left"])
    var right: float = float(layout["right"])
    var out_w: float = float(layout["out_width"])
    var show_outliner: bool = bool(layout["show_outliner"])
    if _rail != null:
        _rail.offset_top = header_h
        _rail.offset_right = RAIL_W
        _rail.offset_bottom = -FOOT_H
    if _outliner != null:
        _outliner.visible = show_outliner
        _outliner.offset_left = -(out_w + 8.0)
        _outliner.offset_right = -8.0
        _outliner.offset_top = header_h + 9.0
        _outliner.offset_bottom = -(FOOT_H + 5.0)
    if _outliner_reopen != null:
        _outliner_reopen.visible = not show_outliner
        _outliner_reopen.offset_top = header_h + 10.0
        _outliner_reopen.offset_bottom = header_h + 48.0
    if _nav_panel != null:
        _nav_panel.offset_left = left
        _nav_panel.offset_right = float(layout["breadcrumb_right"])
        _nav_panel.offset_top = header_h + 10.0
        _nav_panel.offset_bottom = header_h + 53.0
    if _window != null:
        _window.offset_left = left
        _window.offset_right = float(layout["window_right"])
        _window.offset_top = float(layout["window_top"])
        _window.offset_bottom = float(layout["window_bottom"]) - vh
    if _selection_card != null:
        _selection_card.offset_left = float(layout["selection_left"])
        _selection_card.offset_right = float(layout["selection_right"])
        # Do not let the context card exceed the content height on high DPI.
        var selection_h: float = minf(
            185.0, maxf(70.0, vh - header_h - FOOT_H - 12.0))
        _selection_card.offset_top = -(FOOT_H + 10.0 + selection_h)
        _selection_card.offset_bottom = -(FOOT_H + 10.0)
    if _alerts_popover != null:
        _alerts_popover.offset_left = float(layout["alert_left"])
        _alerts_popover.offset_right = right - 5.0
        _alerts_popover.offset_top = header_h + 64.0
        _alerts_popover.offset_bottom = float(layout["alert_bottom"])
    if _footer_panel != null:
        _footer_panel.offset_left = RAIL_W
        _footer_panel.offset_right = (
            -(out_w + 8.0) if show_outliner else -8.0)
        _footer_panel.offset_top = -FOOT_H
        _footer_panel.offset_bottom = 0.0

## The already-existing UIFrameProfiler owns timing samples. Reuse its
## scalars; do not sample World, N158 or network from the HUD.
func update_performance(fps: int, sim_ms: float, ui_ms: float,
        worker: bool, details: String = "") -> void:
    if _perf_readout == null:
        return
    var sim_label: String = "SIM" if worker else "SIM p95"
    _perf_readout.text = "FPS %d  ·  %s %.1fмс  ·  UI p95 %.1fмс" % [
        maxi(0, fps), sim_label, maxf(0.0, sim_ms), maxf(0.0, ui_ms)]
    _perf_readout.tooltip_text = (
        "PING —: игра исполняется локально, сетевого RTT нет.\n" +
        ("SIM: последний завершённый шаг фонового N158.\n"
            if worker else
            "SIM p95: advance_frame за последние 120 кадров.\n") +
        "UI p95: нагрузка интерфейса за окно профайлера.\n" +
        details)

func _set_ui_scale(index: int) -> void:
    if _ui_scale_menu != null and index >= 0 and index < _ui_scale_menu.item_count:
        _ui_scale_menu.select(index)
        if _scale_caption != null:
            _scale_caption.text = _ui_scale_menu.get_item_text(index)
        if _scale_popup != null:
            for i in range(_scale_popup.item_count):
                _scale_popup.set_item_checked(i, i == index)
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
    # When a narrow viewport hides the list behind a management panel,
    # clicking the reveal button closes that panel instead of toggling
    # the logical preference into the wrong state.
    if _show_outliner and _outliner != null and not _outliner.visible and (
            _window != null and _window.visible):
        _close_window()
        _layout_window()
        return
    _show_outliner = not _show_outliner
    _layout_window()

func _close_window() -> void:
    _window.visible = false
    _window_mode = ""
    _workspace_history.clear()
    _workspace_focus = ""
    _update_selection_card()
    _sync_rail_active()
    _layout_window()

func _activate(kind: String) -> void:
    if _alerts_popover != null and _alerts_popover.visible:
        _close_alerts()
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
    _sync_rail_active()
    _layout_window()

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
    if _footer_status != null:
        _footer_status.text = ("СЕКТОР / %s   ·   %s   ·   ТИК %d   ·   %s" % [
            str(_world.get("system", {}).get("name", "—")),
            "КАРТА СИСТЕМЫ" if _game != null and bool(
                _game.get("_in_system")) else "КАРТА СЕКТОРА",
            _tick, "ПАУЗА" if _paused else "НАБЛЮДЕНИЕ"])
    _pause.text = "▶" if _paused else "⏸"
    _brand_scope.text = ("КОЛОНИЯ · " + _body_name(_effective_body()).to_upper() + " ▾"
        if _mode == "colony" else "СЕКТОР · ВСЕ РЫНКИ ▾")
    _brand_scope.tooltip_text = ("Запасы рынка выбранной колонии"
        if _mode == "colony" else
        "Сумма запасов всех рынков и населения ВСЕХ фракций; не активы игрока")
    _update_metrics()
    _update_alerts()
    _update_outliner()
    _update_navigation()
    _update_window()
    _update_selection_card()
    _sync_rail_active()

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
        label.text = (
            str(roundi(float(values.get(key, 0.0)))) if present.has(key) else "—")
        label.tooltip_text = ("Население в выбранной области" if key == "population"
            else "Количество %s в рыночных запасах; это не добыча и не прогноз" % str(item["label"]))
        if not present.has(key):
            label.add_theme_color_override("font_color", MUTED)
        else:
            label.add_theme_color_override("font_color", TEXT)

func _outliner_entry(label: String, callback: Callable,
        selected: bool = false, hint: String = "",
        technical_detail: String = "") -> void:
    var name: String = label
    var icon_key: String = "planet"
    var accent: Color = Color("#72979D")
    if label.begins_with("⌑ "):
        icon_key = "facility"
    elif label.begins_with("⬡ "):
        icon_key = "station"
    elif label.begins_with("▱ "):
        icon_key = "construction"
    elif label.begins_with("↗ ") or label.begins_with("■ ") or (
            label.begins_with("○ ")):
        icon_key = "ship"
        if label.begins_with("↗ "):
            accent = TEAL
        elif label.begins_with("■ "):
            accent = AMBER
    if label.length() >= 2 and label.substr(1, 1) == " ":
        name = label.substr(2)
    var row_button: Button = LSComponents.outliner_item(callback, selected)
    row_button.tooltip_text = (name + "\n" + hint +
        ("\n" + technical_detail if not technical_detail.is_empty() else "")
        if not hint.is_empty() else name)
    _outliner_list.add_child(row_button)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row_button.add_child(row)
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 7
    row.offset_right = -6
    var glyph_tile: PanelContainer = LSComponents.chrome_panel(
        &"LSOutlinerSelectedGlyph" if selected else &"LSOutlinerGlyph")
    glyph_tile.custom_minimum_size = Vector2(29, 29)
    glyph_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    glyph_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(glyph_tile)
    var mark := TextureRect.new()
    mark.custom_minimum_size = Vector2(17, 17)
    mark.texture = FigmaIcons.texture(icon_key, 17, TEAL if selected else accent)
    mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glyph_tile.add_child(mark)
    var text_column := VBoxContainer.new()
    text_column.add_theme_constant_override("separation", 2)
    text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(text_column)
    var primary := _label(name, 10, Color("#A5E1D9") if selected else TEXT)
    text_column.add_child(primary)
    if not hint.is_empty():
        var detail := _label(hint, 8, MUTED)
        text_column.add_child(detail)
    var state: String = ("В ПУТИ" if label.begins_with("↗ ") else (
        "ДОК" if label.begins_with("■ ") else ""))
    if not state.is_empty():
        var state_label := _label(state, 8, TEAL if state == "В ПУТИ" else AMBER)
        state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(state_label)

func _set_outliner_filter(mode: String) -> void:
    if _outliner_filter_mode == mode:
        return
    _outliner_filter_mode = mode
    _outliner_signature = ""
    _update_outliner()

func _toggle_outliner_group(key: String) -> void:
    _outliner_group_open[key] = not bool(_outliner_group_open.get(key, true))
    _outliner_signature = ""
    _update_outliner()

func _outliner_heading(key: String, title: String,
        total: int) -> bool:
    var open: bool = bool(_outliner_group_open.get(key, true))
    var icon: String = "⌄ " if open else "› "
    var btn: Button = LSComponents.outliner_group(
        _toggle_outliner_group.bind(key))
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _outliner_list.add_child(btn)
    var group_row := HBoxContainer.new()
    group_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    btn.add_child(group_row)
    group_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    group_row.offset_left = 6
    group_row.offset_right = -7
    var group_title := _label(icon + title.to_upper(), 10, TEAL)
    group_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    group_row.add_child(group_title)
    var group_count := _label(str(total), 10, MUTED)
    group_count.tooltip_text = "%d подтверждённых объектов" % total
    group_row.add_child(group_count)
    return open

func _update_outliner() -> void:
    if _outliner_list == null or _world.is_empty():
        return
    var signature: String = str(_world.get("system", {}).get("id", "")) + (
        "|" + _body + "|" + _facility + "|" + _ship + "|" + _outliner_filter_mode +
        "|" + JSON.stringify(_outliner_group_open))
    for body in _world.get("bodies", []):
        if body is Dictionary:
            signature += ":" + str(body.get("id", ""))
    for facility in _world.get("facilities", []):
        if facility is Dictionary:
            signature += ":" + str(facility.get("id", ""))
    var ships: Variant = _economy.get("ships", {})
    if ships is Dictionary:
        for id in ships:
            var item: Variant = ships[id]
            if not (item is Dictionary) or str(item.get("system_id", "")) != str(
                    _world.get("system", {}).get("id", "")):
                continue
            var transit: Variant = item.get("transit", {})
            signature += ":" + str(id) + (
                ":flight" if transit is Dictionary and not transit.is_empty()
                else ":docked" if not str(item.get("docked_at", "")).is_empty()
                else ":idle")
    var construction: Variant = _economy.get("construction_sites", {})
    if construction is Dictionary:
        signature += ":build=" + str(construction.size())
    if signature == _outliner_signature:
        return
    _outliner_signature = signature
    if _outliner_scope != null:
        _outliner_scope.text = "СЕКТОР · " + str(
            _world.get("system", {}).get("name", "—")).to_upper()
    for key in _outliner_filter_buttons:
        var b: Button = _outliner_filter_buttons[key]
        b.theme_type_variation = (
            &"LSOutlinerFilterActive"
            if key == _outliner_filter_mode else &"LSOutlinerFilter")
    _clear_outliner_entries()
    var areas: Dictionary = {}
    var production: Array[Dictionary] = []
    var stations: Array[Dictionary] = []
    var local_locations: Dictionary = {}
    for raw in _world.get("facilities", []):
        if not (raw is Dictionary):
            continue
        var facility: Dictionary = raw
        var body_id: String = str(facility.get("body", ""))
        var loc: String = str(facility.get("location", ""))
        areas[body_id] = true
        local_locations[loc] = true
        if str(facility.get("type", "")) in ["station", "orbital_station"]:
            stations.append(facility)
        else:
            production.append(facility)
    var inhabited: Array[Dictionary] = []
    var other_bodies: Array[Dictionary] = []
    for raw in _world.get("bodies", []):
        if not (raw is Dictionary):
            continue
        if areas.has(str(raw.get("id", ""))):
            inhabited.append(raw)
        else:
            other_bodies.append(raw)
    if _outliner_filter_mode == "all":
        if _outliner_heading("colonies", "КОЛОНИИ", inhabited.size()):
            for item in inhabited:
                var id: String = str(item.get("id", ""))
                _outliner_entry("◉ " + _body_name(id),
                    _select_body.bind(id), id == _body,
                    "Планета/тело с подтверждёнными объектами N39")
        if _outliner_heading("production", "ПРОИЗВОДСТВО", production.size()):
            for item in production:
                var id: String = str(item.get("id", ""))
                _outliner_entry("⌑ " + FacilityNames.display_name(item),
                    _select_facility.bind(id), id == _facility,
                    str(item.get("location", "")))
        if _outliner_heading("stations", "СТАНЦИИ", stations.size()):
            for item in stations:
                var id: String = str(item.get("id", ""))
                _outliner_entry("⬡ " + FacilityNames.display_name(item),
                    _select_facility.bind(id), id == _facility,
                    str(item.get("location", "")))
    var fleet_rows: Array[Dictionary] = []
    var flying: int = 0
    if ships is Dictionary:
        for sid in ships:
            var raw: Variant = ships[sid]
            if not (raw is Dictionary) or str(raw.get("system_id", "")) != str(
                    _world.get("system", {}).get("id", "")):
                continue
            var transit: Variant = raw.get("transit", {})
            var inflight: bool = transit is Dictionary and not transit.is_empty()
            var docked: bool = not str(raw.get("docked_at", "")).is_empty()
            if inflight:
                flying += 1
            if _outliner_filter_mode == "flight" and not inflight:
                continue
            if _outliner_filter_mode == "docked" and not docked:
                continue
            fleet_rows.append({"id":str(sid), "data":raw,
                "inflight":inflight, "docked":docked})
    if _outliner_heading("fleet", "КОРАБЛИ · ЛЕТЯТ %d" % flying,
            fleet_rows.size()):
        for row in fleet_rows.slice(0, 24):
            var id: String = str(row["id"])
            var ship: Dictionary = row["data"]
            var in_flight: bool = bool(row["inflight"])
            var at_dock: bool = bool(row["docked"])
            var prefix: String = "↗ " if in_flight else (
                "■ " if at_dock else "○ ")
            var transit: Variant = ship.get("transit", {})
            # Figma row subtitle describes the ship state, never a truncated
            # internal facility-* ID. Full N39 dock/route IDs stay in tooltip.
            var hint: String = ("В полёте · " + ShipPresence.goal_name(
                str(ship.get("current_goal", ""))) if in_flight else (
                "Пристыкован" if at_dock else "Нет активного N14 рейса"))
            var raw_detail: String = ("N14: %s → %s" % [
                str(transit.get("from", "—")),
                str(transit.get("to", "—"))]
                if in_flight else ("Док N39: " + str(
                ship.get("docked_at", "")) if at_dock else "N14 transit: нет"))
            _outliner_entry(prefix + str(ship.get("name", id)),
                _select_ship.bind(id), id == _ship, hint, raw_detail)
    if _outliner_filter_mode == "all":
        var local_sites: Array[Dictionary] = []
        if construction is Dictionary:
            for id in construction:
                var raw: Variant = construction[id]
                if not (raw is Dictionary):
                    continue
                var loc: String = str(raw.get("location_name",
                    raw.get("location", "")))
                if not local_locations.has(loc) or bool(raw.get("completed", false)):
                    continue
                local_sites.append({"id":str(id), "location":loc})
        if _outliner_heading("construction", "СТРОИТЕЛЬСТВО",
                local_sites.size()):
            for site in local_sites:
                _outliner_entry("▱ " + str(site["id"]),
                    _route_workspace.bind("construction", "Проекты", str(site["id"])),
                    false, str(site["location"]))
        if _outliner_heading("bodies", "ДРУГИЕ ТЕЛА", other_bodies.size()):
            for body in other_bodies:
                var id: String = str(body.get("id", ""))
                _outliner_entry("◉ " + _body_name(id),
                    _select_body.bind(id), id == _body)
    _outliner_list.add_child(_label(
        "N39 / N43 · %s" % str(
        _world.get("system", {}).get("name", "—")), 11, MUTED))

func _clear_outliner_entries() -> void:
    for child in _outliner_list.get_children():
        _outliner_list.remove_child(child)
        child.queue_free()

## Navigation state shared by the seven Figma workspaces.
func _route_workspace(mode: String, tab: String, focus: String = "") -> void:
    if _alerts_popover != null:
        _alerts_popover.hide()
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
    _sync_rail_active()
    _layout_window()

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
        _workspace_ui.set_can_go_back(not _workspace_history.is_empty())
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
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    var key: int = event.keycode
    if key == KEY_ESCAPE:
        if _alerts_popover != null and _alerts_popover.visible:
            _close_alerts()
        elif _window != null and _window.visible:
            _workspace_back()
        elif _game != null and bool(_game.get("_in_system")):
            _game.call("_return_to_sector")
        else:
            return
        get_viewport().set_input_as_handled()
        return
    var focused: Control = get_viewport().gui_get_focus_owner()
    if focused is LineEdit or focused is TextEdit:
        return
    var actions: Dictionary = {
        KEY_1:"colony", KEY_2:"economy", KEY_3:"construction",
        KEY_4:"research", KEY_5:"fleet", KEY_6:"administration"}
    if actions.has(key):
        _activate(str(actions[key]))
        get_viewport().set_input_as_handled()
