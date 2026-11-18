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
    # Figma Make 58px HUD vocabulary.
    ui_theme.set_type_variation(&"LSHeaderPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSHeaderResource", &"PanelContainer")
    ui_theme.set_type_variation(&"LSBrandEmblem", &"PanelContainer")
    ui_theme.set_type_variation(&"LSFooterPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSHeaderScope", &"Button")
    ui_theme.set_type_variation(&"LSHeaderAlert", &"Button")
    ui_theme.set_type_variation(&"LSHeaderSpeed", &"Button")
    ui_theme.set_type_variation(&"LSHeaderResourceName", &"Label")
    ui_theme.set_type_variation(&"LSHeaderResourceValue", &"Label")
    ui_theme.set_type_variation(&"LSHeaderResourceIcon", &"Label")
    ui_theme.set_type_variation(&"LSHeaderClock", &"Label")
    ui_theme.set_type_variation(&"LSFooterDiagnostic", &"Label")
    ui_theme.set_type_variation(&"LSRailPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSOutlinerPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSOutlinerHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSAlertsPopover", &"PanelContainer")
    ui_theme.set_type_variation(&"LSMapBreadcrumb", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSelectionPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSNavButtonSelected", &"LSNavButton")
    ui_theme.set_type_variation(&"LSNavUtilityButton", &"LSNavButton")
    ui_theme.set_type_variation(&"LSOutlinerItem", &"Button")
    ui_theme.set_type_variation(&"LSOutlinerSelectedItem", &"LSOutlinerItem")
    ui_theme.set_type_variation(&"LSOutlinerGroup", &"Button")
    ui_theme.set_type_variation(&"LSOutlinerGlyph", &"PanelContainer")
    ui_theme.set_type_variation(&"LSOutlinerSelectedGlyph", &"LSOutlinerGlyph")
    ui_theme.set_type_variation(&"LSOutlinerFilter", &"Button")
    ui_theme.set_type_variation(&"LSOutlinerFilterActive", &"LSOutlinerFilter")
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
    # Shared dense workspace primitives, used across all seven workspaces.
    ui_theme.set_type_variation(&"LSKeyValuePanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSKeyName", &"Label")
    ui_theme.set_type_variation(&"LSKeyAnswer", &"Label")
    ui_theme.set_type_variation(&"LSBodyNote", &"Label")
    ui_theme.set_type_variation(&"LSChainStage", &"Button")
    ui_theme.set_type_variation(&"LSProcessMaterial", &"PanelContainer")
    ui_theme.set_type_variation(&"LSProcessMachine", &"PanelContainer")
    ui_theme.set_type_variation(&"LSProcessHeading", &"Label")
    ui_theme.set_type_variation(&"LSProcessValue", &"Label")
    ui_theme.set_type_variation(&"LSConditionGood", &"ProgressBar")
    ui_theme.set_type_variation(&"LSConditionWorn", &"ProgressBar")
    ui_theme.set_type_variation(&"LSConditionCritical", &"ProgressBar")
    ui_theme.set_type_variation(&"LSWorkspaceHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSWorkspaceToolbar", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSearchFrame", &"PanelContainer")
    ui_theme.set_type_variation(&"LSSectionHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSWindowIconFrame", &"PanelContainer")
    ui_theme.set_type_variation(&"LSLinkButton", &"Button")
    ui_theme.set_type_variation(&"LSIssueButton", &"Button")
    ui_theme.set_type_variation(&"LSCriticalIssueButton", &"LSIssueButton")
    ui_theme.set_type_variation(&"LSRowHeader", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowPlainEven", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowPlainOdd", &"PanelContainer")
    ui_theme.set_type_variation(&"LSRowActionEven", &"Button")
    ui_theme.set_type_variation(&"LSRowActionOdd", &"Button")

    # Figma .topbar / .resource / .date / .time-controls / .statusbar.
    # The HTML linear gradient cannot be represented by a flat StyleBox.
    # Use its upper stop consistently until the final visual pass.
    var header := _flat(Color("#101D26"), Color("#31505A"),
        1, 0, 0)
    header.shadow_size = 5
    header.shadow_color = Color(0, 0, 0, 0.45)
    ui_theme.set_stylebox(&"panel", &"LSHeaderPanel", header)
    ui_theme.set_stylebox(&"panel", &"LSHeaderResource",
        _flat(Color.TRANSPARENT, Color("#1E333C"), 0, 11, 0, 0, 0, 1))
    ui_theme.set_stylebox(&"panel", &"LSBrandEmblem",
        _flat(Color("#102832"), Color("#568288"), 1, 0, 0, 1, 1, 1))
    ui_theme.set_stylebox(&"panel", &"LSFooterPanel",
        _flat(Color("#071018"), Color("#243942"), 0, 8, 0, 0, 1, 0))
    var clear := _flat(Color.TRANSPARENT, Color.TRANSPARENT)
    ui_theme.set_stylebox(&"normal", &"LSHeaderScope", clear)
    ui_theme.set_stylebox(&"hover", &"LSHeaderScope",
        _flat(Color("#142832"), Color.TRANSPARENT))
    ui_theme.set_stylebox(&"pressed", &"LSHeaderScope", clear)
    ui_theme.set_stylebox(&"focus", &"LSHeaderScope", clear)
    ui_theme.set_font_size(&"font_size", &"LSHeaderScope", 8)
    ui_theme.set_color(&"font_color", &"LSHeaderScope", Color("#668086"))
    ui_theme.set_color(&"font_hover_color", &"LSHeaderScope", Color("#93D1CA"))
    ui_theme.set_stylebox(&"normal", &"LSHeaderAlert",
        _flat(Color.TRANSPARENT, Color("#243942"), 0, 0, 0, 1, 0, 0))
    ui_theme.set_stylebox(&"hover", &"LSHeaderAlert",
        _flat(Color("#332718"), Color("#243942"), 0, 0, 0, 1, 0, 0))
    ui_theme.set_stylebox(&"pressed", &"LSHeaderAlert",
        _flat(Color("#332718"), Color("#C99B54"), 0, 0, 0, 1, 0, 0))
    ui_theme.set_color(&"font_color", &"LSHeaderAlert", Color("#C99B54"))
    for variation in [&"LSHeaderAlert", &"LSHeaderSpeed"]:
        ui_theme.set_stylebox(&"focus", variation, clear)
    ui_theme.set_stylebox(&"normal", &"LSHeaderSpeed",
        _flat(Color.TRANSPARENT, Color("#20343B"), 0, 0, 0, 0, 0, 1))
    ui_theme.set_stylebox(&"hover", &"LSHeaderSpeed",
        _flat(Color("#183239"), Color("#53B5AC"), 2, 0, 0, 0, 0, 1))
    ui_theme.set_stylebox(&"pressed", &"LSHeaderSpeed",
        _flat(Color("#183239"), Color("#53B5AC"), 2, 0, 0, 0, 0, 1))
    ui_theme.set_font_size(&"font_size", &"LSHeaderSpeed", 13)
    ui_theme.set_color(&"font_color", &"LSHeaderSpeed", Color("#729198"))
    ui_theme.set_color(&"font_hover_color", &"LSHeaderSpeed", Color("#9FDDD4"))
    ui_theme.set_color(&"font_color", &"LSHeaderResourceName", Color("#70878D"))
    ui_theme.set_font_size(&"font_size", &"LSHeaderResourceName", 8)
    ui_theme.set_color(&"font_color", &"LSHeaderResourceValue", Color("#D7DFDF"))
    ui_theme.set_font_size(&"font_size", &"LSHeaderResourceValue", 13)
    ui_theme.set_color(&"font_color", &"LSHeaderResourceIcon", Color("#79AAA9"))
    ui_theme.set_font_size(&"font_size", &"LSHeaderResourceIcon", 18)
    ui_theme.set_color(&"font_color", &"LSHeaderClock", Color("#C9D3D4"))
    ui_theme.set_font_size(&"font_size", &"LSHeaderClock", 10)
    ui_theme.set_color(&"font_color", &"LSFooterDiagnostic", Color("#53B5AC"))
    ui_theme.set_font_size(&"font_size", &"LSFooterDiagnostic", 9)

    # Figma Make left navigation (64px rail, 58px targets) and 264px outliner.
    var rail_box := _flat(Color("#08131C"), Color("#294049"),
        0, 4, 0, 0, 0, 1)
    rail_box.content_margin_top = 8
    rail_box.content_margin_bottom = 6
    ui_theme.set_stylebox(&"panel", &"LSRailPanel", rail_box)
    var outliner_box := _flat(Color("#09141C"), Color("#31505A"),
        1, 0, 0, 1, 1, 1)
    outliner_box.shadow_size = 8
    outliner_box.shadow_color = Color(0, 0, 0, 0.65)
    ui_theme.set_stylebox(&"panel", &"LSOutlinerPanel", outliner_box)
    ui_theme.set_stylebox(&"panel", &"LSOutlinerHeader",
        _flat(Color("#122832"), Color("#243942"), 1, 13, 0))
    ui_theme.set_stylebox(&"normal", &"LSNavButton",
        _flat(Color("#08131C"), Color("#243942"), 1))
    ui_theme.set_stylebox(&"hover", &"LSNavButton",
        _flat(Color("#12242C"), Color("#243942"), 1))
    ui_theme.set_stylebox(&"pressed", &"LSNavButton",
        _flat(Color("#153139"), Color("#53B5AC"), 1, 0, 0, 2))
    ui_theme.set_stylebox(&"normal", &"LSNavButtonSelected",
        _flat(Color("#153139"), Color("#53B5AC"), 1, 0, 0, 2))
    ui_theme.set_stylebox(&"hover", &"LSNavButtonSelected",
        _flat(Color("#1B3B40"), Color("#53B5AC"), 1, 0, 0, 2))
    ui_theme.set_stylebox(&"focus", &"LSNavButton",
        _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    ui_theme.set_stylebox(&"normal", &"LSNavUtilityButton",
        _flat(Color("#08131C"), Color("#243942"), 1))
    ui_theme.set_stylebox(&"hover", &"LSNavUtilityButton",
        _flat(Color("#12242C"), Color("#243942"), 1))

    # Existing map/navigation and selected-object interactions retain their
    # signals; only the visual definitions are shared here.
    var popup := _flat(Color("#09141C"), Color("#243942"),
        1, 8, 6, 1, 1, 1)
    popup.shadow_size = 3
    popup.shadow_color = Color(0, 0, 0, 0.30)
    ui_theme.set_stylebox(&"panel", &"LSAlertsPopover", popup)
    ui_theme.set_stylebox(&"panel", &"LSMapBreadcrumb",
        _flat(Color("#09141C"), Color("#243942"),
            1, 8, 6, 1, 1, 1))
    ui_theme.set_stylebox(&"panel", &"LSSelectionPanel",
        _flat(Color("#0C1C25"), Color("#53B5AC"),
            1, 8, 6, 2, 1, 1))

    # Figma .outline-item 42px, .group-head and selected state.
    # Outliner entries are reconstructed only when selection/data changes.
    ui_theme.set_stylebox(&"normal", &"LSOutlinerItem",
        _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    ui_theme.set_stylebox(&"hover", &"LSOutlinerItem",
        _flat(Color("#12272F"), Color.TRANSPARENT))
    ui_theme.set_stylebox(&"pressed", &"LSOutlinerItem",
        _flat(Color("#153038"), Color("#53B5AC"), 0, 0, 0, 2))
    ui_theme.set_stylebox(&"normal", &"LSOutlinerSelectedItem",
        _flat(Color("#153038"), Color("#53B5AC"), 0, 0, 0, 2))
    ui_theme.set_stylebox(&"hover", &"LSOutlinerSelectedItem",
        _flat(Color("#153038"), Color("#53B5AC"), 0, 0, 0, 2))
    ui_theme.set_stylebox(&"normal", &"LSOutlinerGroup",
        _flat(Color("#0B1A22"), Color("#243942"), 1, 8, 0))
    ui_theme.set_stylebox(&"hover", &"LSOutlinerGroup",
        _flat(Color("#11252D"), Color("#243942"), 1, 8, 0))
    ui_theme.set_stylebox(&"panel", &"LSOutlinerGlyph",
        _flat(Color("#10252C"), Color("#274A4C"), 1, 4, 4, 1, 1, 1))
    ui_theme.set_stylebox(&"panel", &"LSOutlinerSelectedGlyph",
        _flat(Color("#10252C"), Color("#53B5AC"), 1, 4, 4, 1, 1, 1))
    ui_theme.set_stylebox(&"normal", &"LSOutlinerFilter",
        _flat(Color("#09141C"), Color("#243942"), 1, 4, 4, 1, 1, 1))
    ui_theme.set_stylebox(&"hover", &"LSOutlinerFilter",
        _flat(Color("#132B34"), Color("#53B5AC"), 1, 4, 4, 1, 1, 1))
    ui_theme.set_stylebox(&"normal", &"LSOutlinerFilterActive",
        _flat(Color("#1D4147"), Color("#53B5AC"), 1, 4, 4, 1, 1, 1))
    for v in [&"LSOutlinerItem", &"LSOutlinerGroup", &"LSOutlinerFilter"]:
        ui_theme.set_stylebox(&"focus", v,
            _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    ui_theme.set_color(&"font_color", &"LSOutlinerFilter", Color("#748B92"))
    ui_theme.set_color(&"font_color", &"LSOutlinerFilterActive", Color("#53B5AC"))
    ui_theme.set_font_size(&"font_size", &"LSOutlinerFilter", 9)

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
    # Figma .metric-strip: transparent equal-width tiles with a right border.
    ui_theme.set_stylebox(&"panel", &"LSMetricPanel",
        _flat(Color.TRANSPARENT, Color("#1E333A"), 0, 10, 7, 0, 0, 1))
    ui_theme.set_color(&"font_color", &"LSMutedLabel", Color("#748B92"))
    ui_theme.set_font_size(&"font_size", &"LSMutedLabel", 9)
    ui_theme.set_color(&"font_color", &"LSMetricCaption", Color("#748B92"))
    ui_theme.set_font_size(&"font_size", &"LSMetricCaption", 7)
    ui_theme.set_color(&"font_color", &"LSMetricValue", Color("#D5E0E0"))
    ui_theme.set_font_size(&"font_size", &"LSMetricValue", 13)
    ui_theme.set_color(&"font_color", &"LSMetricNote", Color("#53B5AC"))
    ui_theme.set_font_size(&"font_size", &"LSMetricNote", 7)

    # .key-value rows: 29px, top rule, muted 8px labels, compact values.
    ui_theme.set_stylebox(&"panel", &"LSKeyValuePanel",
        _flat(Color.TRANSPARENT, Color("#1D3138"), 0, 9, 0, 0, 1, 0))
    ui_theme.set_color(&"font_color", &"LSKeyName", Color("#74888D"))
    ui_theme.set_font_size(&"font_size", &"LSKeyName", 8)
    ui_theme.set_color(&"font_color", &"LSKeyAnswer", Color("#B7C6C7"))
    ui_theme.set_font_size(&"font_size", &"LSKeyAnswer", 8)
    ui_theme.set_color(&"font_color", &"LSBodyNote", Color("#748B92"))
    ui_theme.set_font_size(&"font_size", &"LSBodyNote", 9)
    # .chain-flow and .material/.machine, with no simulated throughput.
    ui_theme.set_stylebox(&"normal", &"LSChainStage",
        _flat(Color("#0B1D24"), Color("#2A484E"), 1, 10, 10, 1, 1, 1))
    ui_theme.set_stylebox(&"hover", &"LSChainStage",
        _flat(Color("#122A31"), Color("#56817E"), 1, 10, 10, 1, 1, 1))
    ui_theme.set_stylebox(&"pressed", &"LSChainStage",
        _flat(Color("#122A31"), Color("#53B5AC"), 1, 10, 10, 1, 1, 1))
    ui_theme.set_stylebox(&"focus", &"LSChainStage",
        _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    var process_box := _flat(Color("#0B1B22"), Color("#29434A"),
        1, 10, 10, 1, 1, 1)
    ui_theme.set_stylebox(&"panel", &"LSProcessMaterial", process_box)
    ui_theme.set_stylebox(&"panel", &"LSProcessMachine", process_box)
    ui_theme.set_color(&"font_color", &"LSProcessHeading", Color("#5C777C"))
    ui_theme.set_font_size(&"font_size", &"LSProcessHeading", 7)
    ui_theme.set_color(&"font_color", &"LSProcessValue", Color("#B9C7C8"))
    ui_theme.set_font_size(&"font_size", &"LSProcessValue", 9)
    # Progress state uses published 0..1 N39 condition; no fake percentages.
    var meter_back := _flat(Color("#172D36"), Color.TRANSPARENT)
    for variation in [&"LSConditionGood", &"LSConditionWorn",
            &"LSConditionCritical"]:
        ui_theme.set_stylebox(&"background", variation, meter_back)
    ui_theme.set_stylebox(&"fill", &"LSConditionGood",
        _flat(Color("#53B5AC"), Color.TRANSPARENT))
    ui_theme.set_stylebox(&"fill", &"LSConditionWorn",
        _flat(Color("#C99B54"), Color.TRANSPARENT))
    ui_theme.set_stylebox(&"fill", &"LSConditionCritical",
        _flat(Color("#CF856A"), Color.TRANSPARENT))
    # Shared workspace chrome: original Figma Make V1 geometry.
    var workspace_header := _flat(Color("#152C35"), Color("#35515A"), 1)
    var workspace_toolbar := _flat(Color("#0A161D"), Color("#1E343B"), 1, 8, 3)
    var section_header := _flat(Color("#0D1E26"), Color("#22383F"), 1, 9, 0)
    var search_frame := _flat(Color("#071218"), Color("#273E45"),
        1, 7, 2, 1, 1, 1)
    search_frame.content_margin_right = 5
    var window_icon := _flat(Color("#0B2029"), Color("#33555B"),
        1, 5, 5, 1, 1, 1)
    var window_shell := _flat(Color("#09141C"), Color("#31505A"),
        1, 0, 0, 1, 1, 1)
    window_shell.shadow_size = 10
    window_shell.shadow_color = Color(0, 0, 0, 0.60)
    ui_theme.set_stylebox(&"panel", &"LSWindowPanel", window_shell)
    ui_theme.set_stylebox(&"panel", &"LSWorkspaceHeader", workspace_header)
    ui_theme.set_stylebox(&"panel", &"LSWorkspaceToolbar", workspace_toolbar)
    ui_theme.set_stylebox(&"panel", &"LSSearchFrame", search_frame)
    ui_theme.set_stylebox(&"panel", &"LSSectionHeader", section_header)
    ui_theme.set_stylebox(&"panel", &"LSWindowIconFrame", window_icon)

    # Native counterparts of section links and .issue-line in Figma Make.
    ui_theme.set_font_size(&"font_size", &"LSLinkButton", 10)
    ui_theme.set_color(&"font_color", &"LSLinkButton", Color("#53B5AC"))
    ui_theme.set_color(&"font_hover_color", &"LSLinkButton", Color("#53B5AC"))
    ui_theme.set_stylebox(&"normal", &"LSLinkButton",
        _flat(Color("#0D1E26"), Color("#294049"), 0, 9, 4, 0, 1, 0))
    ui_theme.set_stylebox(&"hover", &"LSLinkButton",
        _flat(Color("#132D34"), Color("#53B5AC"), 0, 9, 4, 0, 1, 0))
    ui_theme.set_stylebox(&"pressed", &"LSLinkButton",
        _flat(Color("#132D34"), Color("#53B5AC"), 0, 9, 4, 0, 1, 0))
    ui_theme.set_stylebox(&"focus", &"LSLinkButton",
        _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    ui_theme.set_stylebox(&"normal", &"LSIssueButton",
        _flat(Color.TRANSPARENT, Color("#20343B"), 0, 0, 0, 0, 1, 0))
    ui_theme.set_stylebox(&"hover", &"LSIssueButton",
        _flat(Color("#132830"), Color("#20343B"), 0, 0, 0, 0, 1, 0))
    ui_theme.set_stylebox(&"pressed", &"LSIssueButton",
        _flat(Color("#132830"), Color("#53B5AC"), 0, 0, 0, 0, 1, 0))
    ui_theme.set_stylebox(&"normal", &"LSCriticalIssueButton",
        _flat(Color("#1C1814"), Color("#20343B"), 0, 0, 0, 0, 1, 0))
    ui_theme.set_stylebox(&"hover", &"LSCriticalIssueButton",
        _flat(Color("#132830"), Color("#20343B"), 0, 0, 0, 0, 1, 0))
    ui_theme.set_stylebox(&"pressed", &"LSCriticalIssueButton",
        _flat(Color("#132830"), Color("#C99B54"), 0, 0, 0, 0, 1, 0))
    for variation in [&"LSIssueButton", &"LSCriticalIssueButton"]:
        ui_theme.set_stylebox(&"focus", variation,
            _flat(Color.TRANSPARENT, Color.TRANSPARENT))

    # Figma Make .dense-row: 34px transparent rows, 1px TOP border,
    # 8px typography, 25px header, and #142930 hover.
    # No invented zebra striping; the section background shows through.
    var table_edge := Color("#1C3138")
    var row_normal := _flat(Color.TRANSPARENT, table_edge,
        0, 9, 0, 0, 1, 0)
    var row_hover := _flat(Color("#142930"), table_edge,
        0, 9, 0, 0, 1, 0)
    var row_pressed := _flat(Color("#142930"), Color("#53B5AC"),
        0, 9, 0, 0, 1, 0)
    var header_row := _flat(Color("#08151C"), Color.TRANSPARENT,
        0, 9, 0)
    ui_theme.set_stylebox(&"panel", &"LSRowHeader", header_row)
    ui_theme.set_stylebox(&"panel", &"LSRowPlainEven", row_normal)
    ui_theme.set_stylebox(&"panel", &"LSRowPlainOdd", row_normal)
    for variation in [&"LSRowActionEven", &"LSRowActionOdd"]:
        ui_theme.set_stylebox(&"normal", variation, row_normal)
        ui_theme.set_stylebox(&"hover", variation, row_hover)
        ui_theme.set_stylebox(&"pressed", variation, row_pressed)
        ui_theme.set_stylebox(&"focus", variation,
            _flat(Color.TRANSPARENT, Color.TRANSPARENT))
    return ui_theme
