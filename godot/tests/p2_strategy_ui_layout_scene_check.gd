extends SceneTree
## Exercise real Control tree, not only preload/parser or pure projections.
const UI = preload("res://scripts/view/strategy_ui.gd")
const ShipPresence = preload("res://scripts/view/ship_body_projection.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var host := Control.new()
    host.size = Vector2(1366, 768)
    get_root().add_child(host)
    var ui: Control = UI.new()
    host.add_child(ui)
    ui.size = host.size
    var world: Dictionary = {
        "system": {"id":"system-sol", "name":"Sol"},
        "bodies": [{"id":"earth", "name":"Earth"},
            {"id":"mars", "name":"Mars"}],
        "nav_sites": [{"name":"mine-near-earth", "body":"earth"}],
        "facilities": [{"id":"farm", "name":"Genesis Farm",
            "type":"farm", "location":"earth-station",
            "body":"earth", "faction_id":"alpha"}]}
    var economy: Dictionary = {
        "markets": {"earth-station": {
            "supply":{"food":120, "ore":55, "energy_cells":8}}},
        "populations": {"human":{"count":150,
            "location":"earth-station"}},
        "facilities": {"farm":{
            "condition":0.92, "assigned_workers":3,
            "work_shift":{"wages":6, "tick":20}}},
        "construction_sites":{"yard":{"completed":false,
            "location":"earth-station"}}, "ships":{
            "ship-a":{"name":"Test Freighter", "class":"freighter",
                "system_id":"system-sol",
                "faction_id":"alpha", "location":"earth-station",
                "current_goal":"idle", "transit":{}, "docked_at":"dock",
                "cargo":{}, "fuel":12, "fuel_capacity":20,
                "credits":100, "current_bt":null},
            "ship-b":{"name":"Ice Miner", "class":"miner",
                "system_id":"system-sol", "faction_id":"alpha",
                "location":"mine-near-earth","current_goal":"mine_ice",
                "transit":{}, "docked_at":"", "cargo":{},
                "current_bt":null},
            "ship-c":{"name":"In Flight", "class":"courier",
                "system_id":"system-sol", "faction_id":"alpha",
                "location":"earth-station","current_goal":"trade_run",
                "transit":{"from":"earth-station",
                    "to":"mine-near-earth"}, "docked_at":"",
                "cargo":{}, "current_bt":null}}
    }
    ui.call("present",world,economy,"earth","","",20,false,1.0,
        "running","details")
    assert(ui.get("_top") is PanelContainer)
    assert(ui.get("_window") is PanelContainer)
    assert(ui.get("_selection_card") is PanelContainer)
    assert((ui.get("_selection_card") as PanelContainer).visible)
    assert((ui.get("_brand_scope") as Button).text.contains("СЕКТОР"))
    ui.call("_toggle_scope")
    assert((ui.get("_brand_scope") as Button).text.contains("КОЛОНИЯ"))
    var local_ships: Array[Dictionary] = ShipPresence.ships_at_body(
        world, economy, "earth")
    assert(local_ships.size() == 2)
    assert(ShipPresence.ships_at_body(world, economy, "mars").is_empty())
    assert(ShipPresence.goal_name("mine_ice") == "Добыча льда")
    assert(str(local_ships[1]["status"]).contains("посадка не подтверждена"))
    assert((ui.get("_selection_summary") as Label).text.contains("Суда в локациях тела: 2"))
    ui.call("update_performance", 61, 193.2, 3.1, true, "Perf test")
    var readout: String = (ui.get("_perf_readout") as Label).text
    assert(readout.contains("FPS 61"))
    assert(readout.contains("PING —"))
    ui.call("_open_selection_details")
    assert((ui.get("_window") as PanelContainer).visible)
    var workspace: Control = ui.get("_workspace_ui")
    assert(workspace != null)
    assert(workspace.get("_mode") == "colony")
    assert(workspace.get("_tab") == "Обзор")
    assert((workspace.get("_content") as VBoxContainer).get_child_count() > 0)
    ui.call("_switch_tab", "Логистика")
    assert(workspace.get("_tab") == "Логистика")
    assert(_contains_text(workspace, "Test Freighter"))
    assert(_contains_text(workspace, "Ice Miner"))
    assert(_contains_text(workspace, "Добыча льда"))
    assert(not _contains_text(workspace, "In Flight"))
    ui.call("_switch_tab", "Строительство")
    assert(_contains_text(workspace, "yard"))
    # All seven Figma management workspaces must have their own real
    # tabbed native pages, even if N39 does not yet expose research.
    var destinations: Dictionary = {
        "colony":"Обзор", "facility":"Процесс",
        "economy":"Баланс", "construction":"Проекты",
        "fleet":"Корабли", "administration":"Приоритеты ИИ",
        "research":"Прогресс"
    }
    for mode in destinations:
        ui.call("_route_workspace", str(mode), str(destinations[mode]))
        assert(workspace.get("_mode") == mode)
        assert(workspace.get("_tab") == destinations[mode])
        assert((workspace.get("_content") as VBoxContainer).get_child_count() > 0)
        assert((workspace.get("_tabs") as HFlowContainer).get_child_count() >= 3)
    ui.call("_workspace_back")
    assert(workspace.get("_mode") == "administration")
    ui.call("_close_window")
    assert(not (ui.get("_window") as PanelContainer).visible)
    assert((ui.get("_selection_card") as PanelContainer).visible)
    # Figma skin smoke: real two-line outliner rows, dark section panels,
    # selected-tab underline and N39-backed condition bar must be native.
    ui.call("_route_workspace", "colony", "Обзор")
    assert(_contains_type(workspace, "PanelContainer"))
    assert(_contains_type(workspace, "HFlowContainer"))
    var colonized_title: String = str(workspace.get("_header_title").text)
    assert(colonized_title == "КОЛОНИЯ")
    ui.call("_close_window")
    ui.call("_toggle_outliner")
    assert(not (ui.get("_outliner") as PanelContainer).visible)
    ui.call("_toggle_outliner")
    assert((ui.get("_outliner") as PanelContainer).visible)
    # Regression: selecting a ship after Earth must never display Earth
    # debug text inside a ship's contextual management workspace.
    ui.call("_open_selection_details")
    ui.call("present",world,economy,"","","ship-a",21,false,1.0,
        "running","STALE EARTH TECHNICAL DETAILS",
        {"n153_blocked_this_tick":2,
            "n153_first_blocker":"no_real_route"})
    assert(ui.get("_window_mode") == "ship")
    ui.call("_switch_tab","Обзор")
    assert(workspace.get("_mode") == "ship")
    assert(_contains_text(workspace, "Test Freighter"))
    assert(not _contains_text(workspace, "STALE EARTH"))
    ui.call("_switch_tab","Маршрут")
    assert(_contains_text(workspace, "Нет активного физического N14 рейса."))
    assert(ui.call("_fleet_diagnostic_text").contains("пристыковано: 1"))
    assert(ui.call("_fleet_diagnostic_text").contains("В полёте: 1"))
    # BLOCK 1 / shell behavior: every close action must work, and a
    # collapsed outliner must have an immediately visible reopening tab.
    var manager_close: Button = workspace.get("_close_button")
    assert(manager_close != null and manager_close.mouse_filter == Control.MOUSE_FILTER_STOP)
    manager_close.pressed.emit()
    assert(not (ui.get("_window") as PanelContainer).visible)
    ui.call("_toggle_alerts")
    var alerts: PanelContainer = ui.get("_alerts_popover")
    assert(alerts.visible)
    assert(not (ui.get("_selection_card") as PanelContainer).visible)
    ui.call("present",world,economy,"earth","","",22,false,1.0,
        "running","details")
    assert(not (ui.get("_selection_card") as PanelContainer).visible)
    var alert_close: Button = ui.get("_alerts_close_button")
    assert(alert_close != null and alert_close.mouse_filter == Control.MOUSE_FILTER_STOP)
    alert_close.pressed.emit()
    assert(not alerts.visible)
    var outliner_close: Button = ui.get("_outliner_close_button")
    outliner_close.pressed.emit()
    assert(not (ui.get("_outliner") as PanelContainer).visible)
    assert((ui.get("_outliner_reopen") as Button).visible)
    (ui.get("_outliner_reopen") as Button).pressed.emit()
    assert((ui.get("_outliner") as PanelContainer).visible)
    assert(not (ui.get("_outliner_reopen") as Button).visible)
    var rail: PanelContainer = ui.get("_rail")
    assert(rail != null and absf(rail.size.x - 64.0) < 1.0)
    var scale_menu: OptionButton = ui.get("_ui_scale_menu")
    assert(scale_menu.item_count == 5)
    assert(scale_menu.get_item_text(0) == "125%")
    assert(scale_menu.get_item_text(3) == "180%")
    assert(scale_menu.get_item_text(4) == "200%")
    var buttons: Dictionary = ui.get("_rail_buttons")
    assert(buttons.size() == 6)
    for button in buttons.values():
        assert(button is Button)
        assert(button.get_child_count() > 0)
        assert((button.get_child(0) as VBoxContainer).get_child_count() == 2)
    # Verify the same non-overlapping Figma layout at 1366/140%,
    # 1366/125% and 1920/125% logical viewport sizes.
    for logical in [Vector2(976, 548), Vector2(1092, 614),
            Vector2(1536, 864)]:
        host.size = logical
        ui.size = logical
        ui.call("_layout_window")
        var panel: Rect2 = (ui.get("_window") as PanelContainer).get_rect()
        var list_rect: Rect2 = (ui.get("_outliner") as PanelContainer).get_rect()
        var breadcrumb: Rect2 = (ui.get("_nav_panel") as PanelContainer).get_rect()
        var popup: Rect2 = alerts.get_rect()
        var header: Rect2 = (ui.get("_top") as PanelContainer).get_rect()
        assert(panel.end.x <= list_rect.position.x)
        assert(panel.position.y >= breadcrumb.end.y)
        assert(popup.position.y >= breadcrumb.end.y)
        assert(popup.position.y >= header.end.y)
        assert(rail.size.x < panel.position.x)
    # At 200% on 1366×768, workspace wins over optional outliner
    # instead of taking the time-control area or the screen right edge.
    host.size = Vector2(683, 384)
    ui.size = host.size
    ui.call("_route_workspace", "fleet", "Корабли")
    ui.call("_layout_window")
    assert(not (ui.get("_outliner") as PanelContainer).visible)
    assert((ui.get("_outliner_reopen") as Button).visible)
    var big_scale_window: Rect2 = (ui.get("_window") as PanelContainer).get_rect()
    assert(big_scale_window.end.x <= 683.0)
    assert(big_scale_window.position.x >= rail.size.x)
    assert(big_scale_window.position.y >= (
        ui.get("_nav_panel") as PanelContainer).get_rect().end.y)
    ui.call("_close_window")
    assert((ui.get("_outliner") as PanelContainer).visible)
    host.queue_free()
    print("SYSTEMBALANCE_FIGMA_LAYOUT_SCENE_PASS")
    quit(0)


func _contains_text(root: Node, fragment: String) -> bool:
    if root is Label and root.text.contains(fragment):
        return true
    if root is Button and root.text.contains(fragment):
        return true
    if root is RichTextLabel and root.text.contains(fragment):
        return true
    for child in root.get_children():
        if _contains_text(child, fragment):
            return true
    return false


func _contains_type(root: Node, typename: String) -> bool:
    if root.get_class() == typename:
        return true
    for child in root.get_children():
        if _contains_type(child, typename):
            return true
    return false
