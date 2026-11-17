extends SceneTree
## Fast, deterministic UI-only test. No full world tick or second N39 owner.
const Cards = preload("res://scripts/view/colony_context_cards.gd")
const Data = preload("res://scripts/view/colony_context_projection.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "system": {"id": "system-sol", "name": "Sol"},
        "bodies": [{"id": "earth", "name": "Earth"}],
        "facilities": [
            {"id": "farm", "type": "farm", "name": "Genesis Farm",
                "body": "earth", "location": "earth-station",
                "faction_id": "terran-authority"}]
    }
    var economy: Dictionary = {
        "markets": {"earth-station": {"supply": {"food": 120}}},
        "populations": {"p": {"location": "earth-station", "count": 50}},
        "facilities": {"farm": {"condition": 0.72,
            "assigned_workers": 6, "credits": 400,
            "work_shift": {"tick": 9, "wages": 60}}},
        "construction_sites": {}}
    var colony: Dictionary = Data.build(world, "earth", "", "", economy)
    assert(colony["title"] == "Земля")
    assert(colony["cards"].size() == 4)
    assert(colony["cards"][0]["value"] == "50")
    assert(colony["cards"][1]["value"] == "120 ед.")
    assert(colony["cards"][2]["value"] == "—") # no false power budget
    var farm: Dictionary = Data.build(world, "earth", "farm", "", economy)
    assert(farm["title"] == "Ферма")
    assert(farm["cards"][0]["value"] == "72%")
    assert(farm["cards"][1]["value"] == "6")
    assert(farm["cards"][2]["value"] == "60 CR")
    var shipless: Dictionary = Data.build(world, "", "", "ship-absent", economy)
    assert(shipless["title"] == "Корабль")
    var panel: ScrollContainer = Cards.new()
    get_root().add_child(panel)
    panel.show_projection(farm)
    assert((panel.get("_title") as Label).text == "Ферма")
    panel.show_projection(colony)
    assert((panel.get("_title") as Label).text == "Земля")
    panel.queue_free()
    var main: Control = Main.new()
    assert(main.has_method("_change_ui_scale"))
    main.free()
    print("COLONY_CONTEXT_CARDS_PASS")
    quit()
