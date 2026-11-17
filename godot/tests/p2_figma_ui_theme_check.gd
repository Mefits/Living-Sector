extends SceneTree
## Fast read-only Figma V1 Theme regression; no N39 world or paid ticks.
const LSTheme = preload("res://scripts/view/ls_ui_theme.gd")

func _initialize() -> void:
    var t: Theme = LSTheme.build()
    assert(t != null)
    assert(t.get_type_variation_base(&"LSPrimaryButton") == &"Button")
    assert(t.get_type_variation_base(&"LSNavButton") == &"Button")
    assert(t.get_type_variation_base(&"LSTabButton") == &"Button")
    assert(t.get_type_variation_base(&"LSWindowPanel") == &"PanelContainer")
    assert(t.get_type_variation_base(&"LSMutedLabel") == &"Label")
    assert(t.get_type_variation_base(&"LSMetricLabel") == &"Label")
    assert(t.has_stylebox(&"normal", &"Button"))
    assert(t.has_stylebox(&"panel", &"PanelContainer"))
    assert(t.get_font_size(&"font_size", &"LSTabButton") == 10)
    assert(t.get_font_size(&"font_size", &"LSNavButton") == 8)
    assert(t.get_color(&"font_color", &"LSPrimaryButton") == Color("#53B5AC"))
    print("FIGMA_V1_NATIVE_THEME_PASS")
    quit()
