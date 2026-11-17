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

static func section_panel() -> PanelContainer:
    var panel := PanelContainer.new()
    panel.theme_type_variation = &"LSSectionPanel"
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return panel
