extends SceneTree
## Fast UI-only integration checks; no ticking, mutation or full World cloning.
const StrategyUI = preload("res://scripts/view/strategy_ui.gd")
const Main = preload("res://scripts/main.gd")
const Roads = preload("res://scripts/view/colony_roads_projection.gd")
const Context = preload("res://scripts/view/colony_context_projection.gd")
const Quick = preload("res://scripts/view/colony_quick_projection.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "system": {"id":"system-sol", "name":"Sol"},
        "bodies": [{"id":"earth", "name":"Earth"},
            {"id":"mars", "name":"Mars"}],
        "facilities": [
            {"id":"mine", "type":"mining_rig", "body":"earth",
                "location":"earth-station", "faction_id":"alpha"},
            {"id":"farm", "type":"farm", "body":"earth",
                "location":"earth-station", "faction_id":"alpha"},
            {"id":"other", "type":"farm", "body":"mars",
                "location":"mars-market", "faction_id":"beta"}
        ]
    }
    var economy: Dictionary = {
        "markets": {
            "earth-station": {"supply": {
                "ore":41, "food":85, "energy_cells":3}},
            "mars-market": {"supply": {
                "ore":9, "food":20, "water":12}}},
        "populations": {
            "e": {"location":"earth-station", "count":150},
            "m": {"location":"mars-market", "count":20}},
        "facilities": {
            "mine": {"condition":0.95, "credits":100,
                "assigned_workers":8,
                "work_shift":{"tick":11, "wages":16}},
            "farm": {"condition":0.70, "credits":25,
                "assigned_workers":4}},
        "ships": {},
        "construction_sites": {
            "yard": {"location":"earth-station", "completed":false},
            "finished": {"location":"mars-market", "completed":true}}
    }
    var ui: Control = StrategyUI.new()
    ui.set("_world", world)
    ui.set("_economy", economy)
    ui.set("_mode", "sector")
    var totals: Dictionary = ui.call("_quantities")
    assert(int(totals["values"]["ore"]) == 50)
    assert(int(totals["values"]["food"]) == 105)
    assert(int(totals["values"]["population"]) == 170)
    assert(not totals["present"].has("metals"))
    ui.set("_body", "earth")
    ui.set("_mode", "colony")
    var earth: Dictionary = ui.call("_quantities")
    assert(int(earth["values"]["ore"]) == 41)
    assert(int(earth["values"]["population"]) == 150)
    assert(not earth["present"].has("water")) # unknown is not zero
    var quick: Dictionary = Quick.project(world, "earth", economy)
    assert(int(quick["construction"]) == 1)
    assert(int(quick["alerts"]) == 1)
    assert(Context.build(world, "earth", "", "", economy)["cards"].size() == 4)
    assert(ui.call("_stocks_text", true).contains("ore"))
    assert(ui.call("_construction_text", "earth").contains("yard"))
    assert(not ui.call("_construction_text", "earth").contains("finished"))
    ui.set("_body", "")
    ui.set("_facility", "mine")
    assert(ui.call("_effective_body") == "earth")
    assert(ui.call("_quantities")["values"]["ore"] == 41.0)
    assert(ui.call("_tabs_for_mode") is Array)
    var main: Control = Main.new()
    assert(main.has_method("_change_ui_scale"))
    assert(Roads.RECENT_PAID_TICKS == 12)
    ui.free()
    main.free()
    print("SYSTEMBALANCE_FIGMA_HUD_MERGE_PASS")
    quit()
