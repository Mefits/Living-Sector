extends RefCounted
## Small native Control factories. Geometry and color come from LSTheme,
## never from per-window StyleBox construction.
## Callers retain ownership of events and real N39 values.

static func action_button(text: String, action: Callable = Callable(),
        prominent: bool = false) -> Button:
    var button := Button.new()
    button.text = text
    button.theme_type_variation = (
        &"LSPrimaryButton" if prominent else &"LSSecondaryButton")
    button.focus_mode = Control.FOCUS_NONE
    if action.is_valid():
        button.pressed.connect(action)
    else:
        button.disabled = true
    return button

static func tab(text: String, active: bool, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.theme_type_variation = &"LSActiveTabButton" if active else &"LSTabButton"
    button.focus_mode = Control.FOCUS_NONE
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
            weight = [0.35, 1.5, 0.8, 1.5][i]
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
        button.focus_mode = Control.FOCUS_NONE
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
    label.clip_text = true
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.tooltip_text = value
    return label

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
