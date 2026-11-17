extends RefCounted
## Native Control theme for Figma Make V1.
## A single Theme owns all reusable visual states. Existing UI overrides are
## migrated incrementally; the world and interaction routes are unchanged.
const THEME_SOURCE: Theme = preload("res://ui/living_sector_theme.tres")

static func _flat(bg: Color, edge: Color, bottom: int = 0,
        xpad: int = 0, ypad: int = 0, left: int = 0,
        top: int = 0, right: int = 0) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = edge
    box.border_width_bottom = bottom
    box.border_width_left = left
    box.border_width_top = top
    box.border_width_right = right
    box.content_margin_left = xpad
    box.content_margin_right = xpad
    box.content_margin_top = ypad
    box.content_margin_bottom = ypad
    box.anti_aliasing = false
    return box

static func build() -> Theme:
    var ui_theme: Theme = THEME_SOURCE.duplicate(true) as Theme
    ui_theme.set_type_variation(&"LSPrimaryButton", &"Button")
    ui_theme.set_type_variation(&"LSSecondaryButton", &"Button")
    ui_theme.set_type_variation(&"LSNavButton", &"Button")
    ui_theme.set_type_variation(&"LSTabButton", &"Button")
    ui_theme.set_type_variation(&"LSActiveTabButton", &"LSTabButton")
    ui_theme.set_type_variation(&"LSWindowPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSectionPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSMetricPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSMutedLabel", &"Label")
    ui_theme.set_type_variation(&"LSMetricCaption", &"Label")
    ui_theme.set_type_variation(&"LSMetricValue", &"Label")
    ui_theme.set_type_variation(&"LSMetricNote", &"Label")
    ui_theme.set_type_variation(&"LSWorkspaceHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSWorkspaceToolbar", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSearchFrame", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSectionHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSWindowIconFrame", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowPlainEven", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowPlainOdd", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowActionEven", &"Button")
    ui_theme.set_type_variation(&"LSRowActionOdd", &"Button")

    # Ordinary workspace actions, previously rebuilt via _box() per control.
    # Preserve the original 12×10px padding while moving style ownership
    # to Theme. Disabled buttons do not inherit interactive hover effects.
    var action_normal := _flat(Color("#122631"), Color.TRANSPARENT, 0, 12, 10)
    var action_hover := _flat(Color("#18343B"), Color("#243942"), 1, 12, 10, 1, 1, 1)
    var action_pressed := _flat(Color("#1F4248"), Color("#243942"), 1, 12, 10, 1, 1, 1)
    var action_focus := _flat(Color.TRANSPARENT, Color.TRANSPARENT)
    for variation in [&"LSPrimaryButton", &"LSSecondaryButton"]:
        ui_theme.set_font_size(&"font_size", variation, 13)
        ui_theme.set_color(&"font_hover_color", variation, Color("#53B5AC"))
        ui_theme.set_stylebox(&"normal", variation, action_normal)
        ui_theme.set_stylebox(&"hover", variation, action_hover)
        ui_theme.set_stylebox(&"pressed", variation, action_pressed)
        ui_theme.set_stylebox(&"focus", variation, action_focus)
    ui_theme.set_color(&"font_color", &"LSSecondaryButton", Color("#C4D0D3"))
    ui_theme.set_color(&"font_color", &"LSPrimaryButton", Color("#53B5AC"))
    ui_theme.set_color(&"font_color", &"LSNavButton", Color("#748B92"))
    ui_theme.set_color(&"font_hover_color", &"LSNavButton", Color("#A6CFCB"))
    ui_theme.set_font_size(&"font_size", &"LSNavButton", 8)

    # Figma .workspace-tabs: a flat 37px horizontal strip with 2px
    # underline for the selected tab, never a wrapped multi-row list.
    ui_theme.set_font_size(&"font_size", &"LSTabButton", 8)
    ui_theme.set_color(&"font_color", &"LSTabButton", Color("#668087"))
    ui_theme.set_color(&"font_hover_color", &"LSTabButton", Color("#A6D8D3"))
    ui_theme.set_stylebox(&"normal", &"LSTabButton",
        _flat(Color("#09151D"), Color("#243942"), 1, 13, 8))
    ui_theme.set_stylebox(&"hover", &"LSTabButton",
        _flat(Color("#102129"), Color("#53B5AC"), 2, 13, 8))
    ui_theme.set_stylebox(&"pressed", &"LSTabButton",
        _flat(Color("#11242C"), Color("#53B5AC"), 2, 13, 8))
    ui_theme.set_stylebox(&"focus", &"LSTabButton",
        _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    ui_theme.set_color(&"font_color", &"LSActiveTabButton", Color("#A6D8D3"))
    ui_theme.set_stylebox(&"normal", &"LSActiveTabButton",
        _flat(Color("#11242C"), Color("#53B5AC"), 2, 13, 8))

    # Distinct panel variants reuse the same shared style across pages.
    ui_theme.set_stylebox(&"panel", &"LSSectionPanel",
        _flat(Color("#0B1921"), Color("#263E45"), 1, 0, 0, 1, 1, 1))
    ui_theme.set_stylebox(&"panel", &"LSMetricPanel",
        _flat(Color("#0D1F27"), Color("#20373F"), 0, 10, 6, 0, 0, 1))
    ui_theme.set_color(&"font_color", &"LSMutedLabel", Color("#748B92"))
    ui_theme.set_font_size(&"font_size", &"LSMutedLabel", 9)
    ui_theme.set_color(&"font_color", &"LSMetricCaption", Color("#748B92"))
    ui_theme.set_font_size(&"font_size", &"LSMetricCaption", 7)
    ui_theme.set_color(&"font_color", &"LSMetricValue", Color("#D5E0E0"))
    ui_theme.set_font_size(&"font_size", &"LSMetricValue", 13)
    ui_theme.set_color(&"font_color", &"LSMetricNote", Color("#53B5AC"))
    ui_theme.set_font_size(&"font_size", &"LSMetricNote", 7)
    # Shared workspace chrome: original Figma Make V1 geometry.
    var workspace_header := _flat(Color("#152C35"), Color("#35515A"), 1)
    var workspace_toolbar := _flat(Color("#0A161D"), Color("#1E343B"), 1, 8, 3)
    var section_header := _flat(Color("#0D1E26"), Color("#22383F"), 1, 9, 0)
    var search_frame := _flat(Color("#071218"), Color("#273E45"),
        1, 7, 2, 1, 1, 1)
    search_frame.content_margin_right = 5
    var window_icon := _flat(Color("#0B2029"), Color("#33555B"),
        1, 5, 5, 1, 1, 1)
    ui_theme.set_stylebox(&"panel", &"LSWorkspaceHeader", workspace_header)
    ui_theme.set_stylebox(&"panel", &"LSWorkspaceToolbar", workspace_toolbar)
    ui_theme.set_stylebox(&"panel", &"LSSearchFrame", search_frame)
    ui_theme.set_stylebox(&"panel", &"LSSectionHeader", section_header)
    ui_theme.set_stylebox(&"panel", &"LSWindowIconFrame", window_icon)

    # One table row vocabulary for Economy, Fleet, Colonies and Projects.
    # Keep normal/hover/pressed padding identical to avoid shifting columns.
    var table_edge := Color("#213943")
    var row_hover_edge := Color("#53B5AC")
    var header_row := _flat(Color("#08151C"), table_edge, 1, 9, 3)
    var even_row := _flat(Color("#0D2029"), table_edge, 1, 9, 6)
    var odd_row := _flat(Color("#0B1B24"), table_edge, 1, 9, 6)
    ui_theme.set_stylebox(&"panel", &"LSRowHeader", header_row)
    ui_theme.set_stylebox(&"panel", &"LSRowPlainEven", even_row)
    ui_theme.set_stylebox(&"panel", &"LSRowPlainOdd", odd_row)
    for variation in [&"LSRowActionEven", &"LSRowActionOdd"]:
        var normal: StyleBoxFlat = even_row if variation == &"LSRowActionEven" else odd_row
        ui_theme.set_stylebox(&"normal", variation, normal)
        ui_theme.set_stylebox(&"hover", variation,
            _flat(Color("#1B3740"), row_hover_edge, 1, 9, 6))
        ui_theme.set_stylebox(&"pressed", variation,
            _flat(Color("#23505A"), row_hover_edge, 1, 9, 6))
        ui_theme.set_stylebox(&"focus", variation,
            _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    return ui_theme
