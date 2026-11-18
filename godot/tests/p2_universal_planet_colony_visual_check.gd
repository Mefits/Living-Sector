extends SceneTree
## Read-only regression fixture for ANY system, not only the frozen Sol.
## Does not generate an authoritative N39 World or alter colonization rules.
const Surface = preload("res://scripts/view/planet_surface_projection.gd")
const Assets = preload("res://scripts/view/physical_assets_projection.gd")
const Roads = preload("res://scripts/view/colony_roads_projection.gd")
const View = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var a: Dictionary = {
        "id": "planet-a", "type": "planet", "biome": "terrestrial",
        "physical_radius_km": 4800.0, "current_angle": 20.0,
        "orbit_radius": 3.0, "orbit_period": 1000.0
    }
    var b: Dictionary = {
        "id": "planet-b", "type": "planet", "biome": "terrestrial",
        "current_angle": 90.0, "orbit_radius": 5.0,
        "orbit_period": 1400.0
    }
    var moon: Dictionary = {
        "id": "moon-a", "type": "moon", "biome": "ice",
        "parent_body_id": "planet-a",
        "satellite_orbit_radius_native": 0.004,
        "current_angle": 80.0, "orbit_radius": 3.02,
        "orbit_period": 90.0
    }
    var world: Dictionary = {
        "system": {"id": "procedural-42", "name": "Uncharted"},
        "bodies": [a, b, moon], "facilities": []
    }
    var frozen: Dictionary = world.duplicate(true)
    var terrain_a: Dictionary = Surface.build(a, "procedural-42")
    var again: Dictionary = Surface.build(a, "procedural-42")
    var terrain_b: Dictionary = Surface.build(b, "procedural-42")
    assert(terrain_a == again)
    assert(terrain_a["seed"] != terrain_b["seed"])
    assert(terrain_a["regions"].size() >= 2)
    assert(terrain_a["hub_site"] is Vector2)
    var dock: Dictionary = {
        "body_id": "planet-a", "location": "planet-a-colony",
        "name": "New Colony", "type": "construction_dock",
        "faction": "faction-one", "credits": 0
    }
    var lab: Dictionary = {
        "body_id": "planet-a", "location": "planet-a-colony",
        "name": "Laboratory", "type": "laboratory",
        "faction": "faction-one", "credits": 95,
        "work_shift": {"tick": 42, "workers": {"p": 6}}
    }
    var orbit: Dictionary = {
        "body_id": "planet-b", "location": "planet-b-port",
        "name": "Other Star Station", "type": "station",
        "faction": "faction-two"
    }
    var live: Dictionary = {
        "colony-one": dock, "new-lab": lab, "other-station": orbit,
        "wrong-system": {"body_id": "alien-planet",
            "type": "factory", "location": "alien-port"}
    }
    var assets: Dictionary = Assets.build(world, live)
    assert(not assets.has("error"))
    assert(assets["surface"].size() == 2)
    assert(assets["orbital"].size() == 1)
    assert(not assets["source_ids"].has("wrong-system"))
    var positions: Dictionary = {}
    var appearances: Dictionary = {}
    for facility in assets["surface"]:
        positions[str(facility["id"])] = facility["site"]
        appearances[str(facility["id"])] = facility["render_type"]
    assert(appearances["colony-one"] == "colony_construction_dock")
    assert(Surface.site_for(terrain_a, "new-lab") == positions["new-lab"])
    var established: Dictionary = live.duplicate(true)
    established["colony-one"]["type"] = "station"
    var next_assets: Dictionary = Assets.build(world, established)
    assert(next_assets["orbital"].size() == 1)
    var founded: Dictionary = {}
    for facility in next_assets["surface"]:
        founded[str(facility["id"])] = facility
    assert(founded.has("colony-one"))
    assert(founded["colony-one"]["render_type"] == "administrative_center")
    assert(founded["colony-one"]["site"] == positions["colony-one"])
    assert(founded["new-lab"]["site"] == positions["new-lab"])
    var roads: Dictionary = Roads.build(
        next_assets["surface"], {}, 42)
    assert(roads["sites"].size() == 3)
    assert(roads["has_ac"].has("planet-a"))
    assert(roads["links"].size() == 1)
    assert(str(roads["links"][0]["body"]) == "planet-a")
    var view: Control = View.new()
    root.add_child(view)
    view.size = Vector2(1100, 800)
    view.set_world(world)
    assert(str(view.call("_known_moon_parent", moon).get("id", "")) ==
        "planet-a")
    view.set_live_facilities(live, 41)
    var stage_one: Dictionary = view.get("_physical_assets")
    assert(stage_one["surface"].size() == 2)
    view.set_live_facilities(established, 42)
    var stage_two: Dictionary = view.get("_physical_assets")
    assert(stage_two["surface"].size() == 2)
    assert(stage_two["orbital"].size() == 1)
    assert(world == frozen)
    view.queue_free()
    print("UNIVERSAL_PLANET_COLONY_VISUAL_PASS")
    quit(0)
