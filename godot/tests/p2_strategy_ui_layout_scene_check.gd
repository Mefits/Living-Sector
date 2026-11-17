extends SceneTree
## Exercise real Control tree, not only preload/parser or pure projections.
const UI = preload("res://scripts/view/strategy_ui.gd")

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
                "faction_id":"alpha", "location":"earth-station",
                "current_goal":"idle", "transit":{}, "docked_at":"dock",
                "cargo":{}, "fuel":12, "fuel_capacity":20,
                "credits":100, "current_bt":null}}
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
    ui.call("_open_selection_details")
    assert((ui.get("_window") as PanelContainer).visible)
    assert((ui.get("_window_cards") as GridContainer).get_child_count() == 4)
    ui.call("_switch_tab","Строительство")
    assert((ui.get("_window_text") as RichTextLabel).text.contains("yard"))
    ui.call("_close_window")
    assert(not (ui.get("_window") as PanelContainer).visible)
    assert((ui.get("_selection_card") as PanelContainer).visible)
    ui.call("_toggle_outliner")
    assert(not (ui.get("_outliner") as PanelContainer).visible)
    ui.call("_toggle_outliner")
    assert((ui.get("_outliner") as PanelContainer).visible)
    # Regression: selecting a ship after Earth must not keep Earth's
    # diagnostic text under a misleading "КОРАБЛЬ" title.
    ui.call("_open_selection_details")
    ui.call("present",world,economy,"","","ship-a",21,false,1.0,
        "running","STALE EARTH TECHNICAL DETAILS",
        {"n153_blocked_this_tick":2,
            "n153_first_blocker":"no_real_route"})
    assert(ui.get("_window_mode") == "ship")
    ui.call("_switch_tab","Данные")
    var displayed: String = (ui.get("_window_text") as RichTextLabel).text
    assert(displayed.contains("Test Freighter"))
    assert(not displayed.contains("STALE EARTH"))
    assert(displayed.contains("нет активного рейса"))
    assert(ui.call("_fleet_diagnostic_text").contains("пристыковано: 1"))
    host.queue_free()
    print("SYSTEMBALANCE_FIGMA_LAYOUT_SCENE_PASS")
    quit(0)
