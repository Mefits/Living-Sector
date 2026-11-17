extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_system_balance_colony_roads_check.gd
const Roads = preload("res://scripts/view/colony_roads_projection.gd")
const Assets = preload("res://scripts/sim/phase2/sol_physical_assets_projection.gd")
const Labels = preload("res://scripts/view/facility_labels_ru.gd")
const View = preload("res://scripts/star_system_view.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
    var source: Dictionary = {"system": {"id": "system-sol"}, "facilities": [
        {"id": "st", "name": "Station", "type": "station", "body": "earth",
            "location": "earth-station", "faction_id": "a"},
        {"id": "mine", "name": "Mine", "type": "mining_rig", "body": "earth",
            "location": "earth-station", "faction_id": "a"},
        {"id": "ref", "name": "Refinery", "type": "refinery", "body": "earth",
            "location": "earth-station", "faction_id": "a"},
        {"id": "factory", "name": "Factory", "type": "factory", "body": "earth",
            "location": "earth-station", "faction_id": "a"},
        {"id": "farm", "name": "Farm", "type": "farm", "body": "earth",
            "location": "earth-station", "faction_id": "a"}
    ]}
    # Localized UI text is separated from immutable native names/IDs.
    assert(Labels.display_name(source["facilities"][1]) == "Добывающий комплекс")
    assert(Labels.display_name(source["facilities"][2]) == "Перерабатывающий комплекс")
    assert(Labels.display_name(source["facilities"][3]) == "Фабрика" or
        Labels.display_name(source["facilities"][3]) == "Промышленный комплекс")
    assert(Labels.type_name("station") == "Орбитальная станция")
    assert(Labels.type_name("custom_unknown") == "custom_unknown")
    var assets: Dictionary = Assets.build(source)
    assert(assets.get("surface", []).size() == 4)
    assert(assets.get("orbital", []).size() == 1)
    var world: Dictionary = {"facilities": {
        "mine": {"work_shift": {"tick": 100, "wages": 60,
            "workers": {"earth": 16}}, "assigned_workers": 16},
        "ref": {"work_shift": {"tick": 100, "wages": 50,
            "workers": {"earth": 9}}, "assigned_workers": 9},
        "factory": {"work_shift": {"tick": 70, "wages": 30,
            "workers": {"earth": 5}}, "assigned_workers": 5},
        "farm": {"assigned_workers": 12}
    }}
    var statuses: Dictionary = {}
    for asset in assets["surface"]:
        statuses[str(asset["id"])] = Assets.live_status(asset, world["facilities"])
    assert(int(statuses["mine"]["shift_workers"]) == 16)
    assert(int(statuses["factory"]["shift_workers"]) == 5)
    var roads: Dictionary = Roads.build(assets["surface"], statuses, 100)
    assert(roads["sites"].size() == 5)
    assert(roads["links"].size() == 6) # four hub roads + mining→refinery + refinery→factory
    var moving: int = 0
    for link in roads["links"]:
        if int(link["particles"]) > 0:
            moving += 1
        assert(int(link["particles"]) <= Roads.MAX_PARTICLES_PER_LINK)
    assert(moving == 3) # mine, refinery, their relation; idle/stale stay idle
    assert(roads == Roads.build(assets["surface"], statuses, 100))
    var stopped: Dictionary = Roads.build(assets["surface"], statuses, 160)
    for link in stopped["links"]:
        assert(int(link["particles"]) == 0)
    var empty: Dictionary = Roads.build([], {}, 100)
    assert(empty["links"].is_empty())
    assert(empty["sites"].size() == 1)
    var view: Control = View.new()
    assert(view.has_method("set_live_facilities"))
    view.free()
    var main: Control = Main.new()
    assert(main != null)
    main.free()
    print("SYSTEM_BALANCE_COLONY_ROADS_PASS")
    quit()
