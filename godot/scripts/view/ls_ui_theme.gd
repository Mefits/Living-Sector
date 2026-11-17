extends RefCounted
## Shared Figma Make V1 design system for native Godot Control nodes.
## Theme variations are configured once per StrategyUI instance, not per frame.
## Existing local overrides stay authoritative until their components migrate.

const THEME_SOURCE: Theme = preload("res://ui/living_sector_theme.tres")

static func build() -> Theme:
    var ui_theme: Theme = THEME_SOURCE.duplicate(true) as Theme
    ui_theme.set_type_variation(&"LSPrimaryButton", &"Button")
    ui_theme.set_type_variation(&"LSNavButton", &"Button")
    ui_theme.set_type_variation(&"LSTabButton", &"Button")
    ui_theme.set_type_variation(&"LSWindowPanel", &"PanelContainer")
    ui_theme.set_type_variation(&"LSMutedLabel", &"Label")
    ui_theme.set_type_variation(&"LSMetricLabel", &"Label")

    ui_theme.set_color(&"font_color", &"LSPrimaryButton", Color("#53B5AC"))
    ui_theme.set_color(&"font_color", &"LSNavButton", Color("#748B92"))
    ui_theme.set_color(&"font_hover_color", &"LSNavButton", Color("#A6CFCB"))
    ui_theme.set_color(&"font_color", &"LSTabButton", Color("#748B92"))
    ui_theme.set_color(&"font_color", &"LSMutedLabel", Color("#748B92"))
    ui_theme.set_color(&"font_color", &"LSMetricLabel", Color("#D7DFDF"))
    ui_theme.set_font_size(&"font_size", &"LSNavButton", 8)
    ui_theme.set_font_size(&"font_size", &"LSTabButton", 10)
    ui_theme.set_font_size(&"font_size", &"LSMutedLabel", 9)
    ui_theme.set_font_size(&"font_size", &"LSMetricLabel", 17)
    return ui_theme
