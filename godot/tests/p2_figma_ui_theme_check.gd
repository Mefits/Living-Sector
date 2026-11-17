extends SceneTree
## Fast read-only Figma V1 Theme regression; no N39 world or paid ticks.
const LSTheme = preload("res://scripts/view/ls_ui_theme.gd")
const LSComponents = preload("res://scripts/view/ls_ui_components.gd")

func _initialize() -> void:
    var t: Theme = LSTheme.build()
    assert(t != null)
    assert(t.get_type_variation_base(&"LSPrimaryButton") == &"Button")
    assert(t.get_type_variation_base(&"LSSecondaryButton") == &"Button")
    assert(t.get_type_variation_base(&"LSNavButton") == &"Button")
    assert(t.get_type_variation_base(&"LSTabButton") == &"Button")
    assert(t.get_type_variation_base(&"LSWindowPanel") == &"PanelContainer")
    assert(t.get_type_variation_base(&"LSMutedLabel") == &"Label")
    assert(t.get_type_variation_base(&"LSMetricCaption") == &"Label")
    assert(t.get_type_variation_base(&"LSMetricValue") == &"Label")
    assert(t.get_type_variation_base(&"LSMetricNote") == &"Label")
    assert(t.get_type_variation_base(&"LSSectionPanel") == &"PanelContainer")
    assert(t.get_type_variation_base(&"LSMetricPanel") == &"PanelContainer")
    assert(t.get_type_variation_base(&"LSActiveTabButton") == &"LSTabButton")
    for chrome in [&"LSWorkspaceHeader", &"LSWorkspaceToolbar",
            &"LSSearchFrame", &"LSSectionHeader", &"LSWindowIconFrame",
            &"LSRowHeader", &"LSRowPlainEven", &"LSRowPlainOdd"]:
        assert(t.get_type_variation_base(chrome) == &"PanelContainer")
        assert(t.has_stylebox(&"panel", chrome))
    for variation in [&"LSRowActionEven", &"LSRowActionOdd"]:
        assert(t.get_type_variation_base(variation) == &"Button")
        assert(t.has_stylebox(&"normal", variation))
        assert(t.has_stylebox(&"hover", variation))
    assert(t.has_stylebox(&"normal", &"Button"))
    assert(t.has_stylebox(&"panel", &"PanelContainer"))
    assert(t.get_font_size(&"font_size", &"LSTabButton") == 8)
    assert(t.get_font_size(&"font_size", &"LSNavButton") == 8)
    assert(t.get_color(&"font_color", &"LSPrimaryButton") == Color("#53B5AC"))
    var root := Control.new()
    root.theme = t
    get_root().add_child(root)
    var actions: Array[String] = []
    var action_button: Button = LSComponents.action_button(
        "Подробнее", func() -> void: actions.append("clicked"), true)
    root.add_child(action_button)
    assert(action_button.theme_type_variation == &"LSPrimaryButton")
    action_button.pressed.emit()
    assert(actions == ["clicked"])
    var inactive: Button = LSComponents.action_button("—")
    root.add_child(inactive)
    assert(inactive.disabled)
    var tab: Button = LSComponents.tab("Обзор", true, func() -> void: pass)
    root.add_child(tab)
    assert(tab.theme_type_variation == &"LSActiveTabButton")
    assert(tab.get_theme_font_size(&"font_size") == 8)
    assert(tab.get_theme_stylebox(&"normal") is StyleBoxFlat)
    var panel: PanelContainer = LSComponents.metric_panel()
    root.add_child(panel)
    assert(panel.theme_type_variation == &"LSMetricPanel")
    assert(panel.get_theme_stylebox(&"panel") is StyleBoxFlat)
    var value_label: Label = LSComponents.metric_text("123", &"LSMetricValue")
    panel.add_child(value_label)
    assert(value_label.get_theme_font_size(&"font_size") == 13)
    var clicked: Array[String] = []
    var row_action: Button = LSComponents.table_row(
        false, true, func() -> void: clicked.append("row")) as Button
    root.add_child(row_action)
    assert(row_action.theme_type_variation == &"LSRowActionOdd")
    row_action.pressed.emit()
    assert(clicked == ["row"])
    var five_columns: Array[Vector2] = LSComponents.table_column_profile(
        ["Судно", "Класс", "Задача", "Груз", "Статус"])
    assert(five_columns.size() == 5)
    for column in five_columns:
        assert(column.x == 115.0 and column.y == 1.0)
    var four_columns: Array[Vector2] = LSComponents.table_column_profile(
        ["ID", "Объект", "Количество", "Статус"])
    assert(four_columns.size() == 4)
    assert(four_columns[0].x == 55.0)
    assert(is_equal_approx(four_columns[0].y, 0.35))
    var regular_columns: Array[Vector2] = LSComponents.table_column_profile(
        ["Локация", "Жители", "Состояние", "Рост"])
    assert(regular_columns[0].x == 150.0)
    var row_header: PanelContainer = LSComponents.table_row(
        true, false, Callable()) as PanelContainer
    root.add_child(row_header)
    assert(row_header.theme_type_variation == &"LSRowHeader")
    var workspace_header: PanelContainer = LSComponents.chrome_panel(&"LSWorkspaceHeader")
    root.add_child(workspace_header)
    assert(workspace_header.get_theme_stylebox(&"panel") is StyleBoxFlat)
    root.free()
    print("FIGMA_V1_NATIVE_THEME_PASS")
    quit()
