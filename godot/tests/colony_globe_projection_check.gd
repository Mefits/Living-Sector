extends SceneTree
## Quick headless checks:
## godot --headless --path godot --script res://tests/colony_globe_projection_check.gd
const Globe = preload("res://scripts/view/colony_globe_projection.gd")
const GlobeView = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    # Preloading the actual system view catches transitive GDScript parse errors.
    var visual: Control = GlobeView.new()
    assert(visual != null)
    visual.free()
    var seed: Array = [
        {"id": "s", "name": "Earth orbital station"},
        {"id": "m", "name": "Earth mine"},
        {"id": "r", "name": "Earth refinery"},
        {"id": "x", "name": "Mars farm"}
    ]
    var world: Dictionary = {"facilities": {
        "s": {"type": "station", "body_id": "earth", "location": "earth-station"},
        "m": {"type": "mining_rig", "body_id": "earth", "location": "earth-station",
            "work_shift": {"tick": 100, "workers": {"pop-earth": 16}}},
        "r": {"type": "refinery", "body_id": "earth", "location": "earth-station",
            "work_shift": {"tick": 100, "workers": {"pop-earth": 9}}},
        "x": {"type": "farm", "body_id": "mars", "location": "mars-station",
            "work_shift": {"tick": 100, "workers": {"pop-mars": 7}}}
    }}
    var view: Dictionary = Globe.build("earth", seed, world, 100)
    assert(view["nodes"].size() == 2)
    assert(view["orbit"].size() == 1)
    assert(str(view["hub_id"]) == "s")
    assert(view["links"].size() == 3) # 2 hub roads + one recipe relation
    assert(int(view["nodes"][0]["activity"]) > 0)
    assert(view == Globe.build("earth", seed, world, 100)) # stable on refresh
    var stale: Dictionary = Globe.build("earth", seed, world, 200)
    assert(int(stale["nodes"][0]["activity"]) == 0)
    assert(int(stale["nodes"][1]["activity"]) == 0)
    var mars: Dictionary = Globe.build("mars", seed, world, 100)
    assert(mars["nodes"].size() == 1)
    assert(mars["orbit"].is_empty())
    var absent: Dictionary = Globe.build("jupiter", seed, world, 100)
    assert(absent["nodes"].is_empty() and absent["orbit"].is_empty())
    print("COLONY_GLOBE_PROJECTION_PASS")
    quit()
