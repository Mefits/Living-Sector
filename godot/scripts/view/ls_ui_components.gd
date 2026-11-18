extends RefCounted
## Small native Control factories. Geometry and color come from LSTheme,
## never from per-window StyleBox construction.
## Callers retain ownership of events and real N39 values.

## HUD components are layout-only wrappers around N39 data. Neither style
## factory reads game state or allocates a per-tick snapshot.
static func header_resource() -> PanelContainer:
    var tile: PanelContainer = chrome_panel(&"LSHeaderResource")
    tile.custom_minimum_size.x = 104
    tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return tile

static func header_speed(text: String, action: Callable) -> Button:
    var button: Button = action_button(text, action)
    button.theme_type_variation = &"LSHeaderSpeed"
    button.custom_minimum_size.x = 31
    button.size_flags_vertical = Control.SIZE_EXPAND_FILL
    return button

static func header_alert(action: Callable) -> Button:
    var button: Button = action_button("", action)
    button.theme_type_variation = &"LSHeaderAlert"
    button.custom_minimum_size.x = 46
    button.size_flags_vertical = Control.SIZE_EXPAND_FILL
    return button

static func header_scope(text: String, action: Callable) -> Button:
    var button: Button = action_button(text, action)
    button.theme_type_variation = &"LSHeaderScope"
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.clip_text = true
    button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return button

static func action_button(text: String, action: Callable = Callable(),
        prominent: bool = false) -> Button:
    var button := Button.new()
    button.text = text
    button.theme_type_variation = (
        &"LSPrimaryButton" if prominent else &"LSSecondaryButton")
    button.focus_mode = Control.FOCUS_ALL
    if action.is_valid():
        button.pressed.connect(action)
    else:
        button.disabled = true
    return button

static func section_link(text: String, action: Callable) -> Button:
    var button: Button = action_button(text, action, true)
    button.theme_type_variation = &"LSLinkButton"
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.custom_minimum_size.y = 29
    return button

static func issue_button(critical: bool, action: Callable) -> Button:
    var button: Button = action_button("", action)
    button.theme_type_variation = (
        &"LSCriticalIssueButton" if critical else &"LSIssueButton")
    button.custom_minimum_size.y = 47
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return button

static func outliner_item(action: Callable, selected: bool) -> Button:
    var button: Button = action_button("", action)
    button.theme_type_variation = (
        &"LSOutlinerSelectedItem" if selected else &"LSOutlinerItem")
    button.custom_minimum_size.y = 42
    return button

static func outliner_group(action: Callable) -> Button:
    var button: Button = action_button("", action)
    button.theme_type_variation = &"LSOutlinerGroup"
    button.custom_minimum_size.y = 29
    return button

static func outliner_filter(text: String, action: Callable) -> Button:
    var button: Button = action_button(text, action)
    button.theme_type_variation = &"LSOutlinerFilter"
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return button

static func tab(text: String, active: bool, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.theme_type_variation = &"LSActiveTabButton" if active else &"LSTabButton"
    button.focus_mode = Control.FOCUS_ALL
    button.custom_minimum_size.y = 36
    button.tooltip_text = text
    button.pressed.connect(action)
    return button

## Stable per-table column widths and weights shared by header and every row.
## Five equally weighted columns follow Figma Make .dense-row.five. Four-column
## ID tables may use the .dense-row.four (0.35:1.5:0.8:1.5) layout; ordinary
## 4-column N39 tables retain a readable first column instead.
static func table_column_profile(headings: Array) -> Array[Vector2]:
    var profile: Array[Vector2] = []
    var count: int = maxi(1, headings.size())
    var id_heading: bool = not headings.is_empty() and (
        str(headings[0]).to_upper() in ["ID", "№"])
    for i in range(count):
        var min_width := 100.0
        var weight := 1.0
        if count == 5:
            min_width = 115.0
        elif count == 4 and id_heading:
            min_width = 55.0 if i == 0 else 110.0
            var four_column_weights: Array[float] = [0.35, 1.5, 0.8, 1.5]
            weight = four_column_weights[i]
        elif i == 0:
            min_width = 150.0
            weight = 1.5
        profile.append(Vector2(min_width, weight))
    return profile

static func table_row(heading: bool, odd: bool, action: Callable) -> Control:
    var row: Control
    if action.is_valid() and not heading:
        var button := Button.new()
        # Figma dense-row has visible hover/pressed decoration.
        button.flat = false
        button.focus_mode = Control.FOCUS_ALL
        button.theme_type_variation = (
            &"LSRowActionOdd" if odd else &"LSRowActionEven")
        button.pressed.connect(action)
        row = button
    else:
        var panel := PanelContainer.new()
        panel.theme_type_variation = (
            &"LSRowHeader" if heading else (
                &"LSRowPlainOdd" if odd else &"LSRowPlainEven"))
        row = panel
    row.custom_minimum_size.y = 25 if heading else 34
    return row

static func metric_text(value: String, role: StringName) -> Label:
    var label := Label.new()
    label.text = value
    label.theme_type_variation = role
    # Long N39 descriptions/AI reasons must wrap, never silently disappear.
    label.clip_text = not (role in [&"LSBodyNote", &"LSReasonValue"])
    if label.clip_text:
        label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.tooltip_text = value
    return label

static func key_value_panel() -> PanelContainer:
    var panel: PanelContainer = chrome_panel(&"LSKeyValuePanel")
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func process_card(machine: bool = false) -> PanelContainer:
    var panel: PanelContainer = chrome_panel(
        &"LSProcessMachine" if machine else &"LSProcessMaterial")
    panel.custom_minimum_size = Vector2(135, 100)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func chain_stage(action: Callable) -> Button:
    var button: Button = action_button("", action)
    button.theme_type_variation = &"LSChainStage"
    button.custom_minimum_size = Vector2(135, 108)
    return button

static func condition_bar(level: float) -> ProgressBar:
    var meter := ProgressBar.new()
    meter.theme_type_variation = (
        &"LSConditionGood" if level >= 0.8 else (
            &"LSConditionWorn" if level >= 0.5 else &"LSConditionCritical"))
    meter.min_value = 0.0
    meter.max_value = 1.0
    meter.value = clampf(level, 0.0, 1.0)
    meter.show_percentage = false
    meter.custom_minimum_size.y = 5
    return meter

static func reasoning_row(chosen: bool = false) -> PanelContainer:
    var panel: PanelContainer = chrome_panel(
        &"LSReasonChosen" if chosen else &"LSReasonRow")
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func research_card() -> PanelContainer:
    var panel: PanelContainer = chrome_panel(&"LSResearchCard")
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func research_progress(level: float) -> ProgressBar:
    var meter := ProgressBar.new()
    meter.theme_type_variation = &"LSResearchProgress"
    meter.min_value = 0.0
    meter.max_value = 1.0
    meter.value = clampf(level, 0.0, 1.0)
    meter.show_percentage = false
    meter.custom_minimum_size.y = 5
    return meter

static func route_card() -> PanelContainer:
    var panel: PanelContainer = chrome_panel(&"LSRouteCard")
    panel.custom_minimum_size = Vector2(170, 70)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func metric_panel() -> PanelContainer:
    var panel := PanelContainer.new()
    panel.theme_type_variation = &"LSMetricPanel"
    panel.custom_minimum_size = Vector2(138, 58)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel

static func chrome_panel(variation: StringName) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.theme_type_variation = variation
    return panel

static func section_panel() -> PanelContainer:
    var panel := PanelContainer.new()
    panel.theme_type_variation = &"LSSectionPanel"
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel
