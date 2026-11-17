extends SceneTree
const QuickData = preload("res://scripts/view/colony_quick_projection.gd")
const Strip = preload("res://scripts/view/colony_quick_strip.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "system": {"id": "system-sol"},
        "bodies": [{"id": "earth", "name": "Earth"},
            {"id": "mars", "name": "Mars"}],
        "facilities": [
            {"id": "farm", "body": "earth", "location": "earth-station"},
            {"id": "refinery", "body": "earth", "location": "earth-station"},
            {"id": "other", "body": "mars", "location": "mars-station"}
        ]
    }
    var economy: Dictionary = {
        "populations": {
            "p1": {"location": "earth-station", "count": 130},
            "p2": {"location": "mars-station", "count": 20}},
        "markets": {
            "earth-station": {"supply": {"food": 410, "water": 200}},
            "mars-station": {"supply": {"food": 25, "energy_cells": 8}}},
        "facilities": {
            "farm": {"condition": 0.94, "abandoned": false},
            "refinery": {"condition": 0.65, "abandoned": false},
            "other": {"condition": 1.0, "abandoned": false}},
        "construction_sites": {
            "site-earth": {"location_name": "earth-station", "completed": false},
            "site-mars": {"location_name": "mars-station", "completed": false},
            "site-done": {"location_name": "earth-station", "completed": true}}
    }
    var earth: Dictionary = QuickData.project(world, "earth", economy)
    assert(bool(earth["visible"]))
    assert(str(earth["name"]) == "Земля")
    assert(int(earth["population"]) == 130)
    assert(is_equal_approx(float(earth["food"]), 410.0))
    assert(earth["energy"] == null) # No energy market data: never fake balance.
    assert(int(earth["construction"]) == 1)
    assert(int(earth["alerts"]) == 1) # One worn real N39 facility.
    assert(QuickData.project(world, "", economy) == earth)
    var mars: Dictionary = QuickData.project(world, "mars", economy)
    assert(int(mars["population"]) == 20)
    assert(int(mars["food"]) == 25)
    assert(int(mars["energy"]) == 8)
    assert(int(mars["construction"]) == 1)
    assert(int(mars["alerts"]) == 0)
    assert(not bool(QuickData.project(world, "luna", economy)["visible"]))
    var boot: Dictionary = QuickData.project(world, "earth", {})
    assert(bool(boot["visible"]) and not bool(boot["live"]))
    assert(boot["population"] == null)
    var strip: HFlowContainer = Strip.new()
    assert(strip.has_method("show_colony"))
    strip.free()
    var main: Control = Main.new()
    assert(main != null)
    main.free()
    print("COLONY_QUICK_STRIP_PASS")
    quit()
