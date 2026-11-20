extends SceneTree
## Lightweight seed-integrity regression: one stable ground AC, no legacy Earth
## enterprises or dangling location references. The starter farm is local.
const Start = preload("res://scripts/sol_start_scenario.gd")
const Assets = preload("res://scripts/view/physical_assets_projection.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Sites = preload("res://scripts/view/sol_surface_sites.gd")

func _initialize() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/sol.json"))
    if not (parsed is Dictionary):
        push_error("SOL_AC_START_FAIL: source seed")
        quit(1)
        return
    var original: Dictionary = parsed
    var start: Dictionary = Start.apply(original)
    var earth: Array = []
    for facility in start.get("facilities", []):
        if str(facility.get("body", "")) == "earth":
            earth.append(facility)
    var okay: bool = earth.size() == 2 and earth.all(func(f): return f.location == Start.AC_LOCATION)
    okay = okay and earth.any(func(f): return f.id == Start.AC_ID and f.type == "station")
    okay = okay and earth.any(func(f): return f.id == Start.EARTH_FARM_ID and f.type == "farm")
    var projected: Dictionary = Assets.build(start)
    var ground: Array = projected.get("surface", [])
    var orbitals: Array = projected.get("orbital", [])
    okay = okay and ground.size() == 2 and orbitals.is_empty()
    var expected: Array = Sites.get_site(
        "earth", "earth-ac-01")["at"]
    okay = okay and ground.any(func(asset): return (asset.render_type == "administrative_center"
        and asset.site == Vector2(float(expected[0]), float(expected[1]))))
    okay = okay and Model.stock(start, "earth") == Start.EARTH_STOCK.metals
    okay = okay and Model.colony(start, "earth")
    for field in ["markets", "populations", "ships", "travel_routes"]:
        for item in start.get(field, []):
            for key in ["facility_id", "location", "from", "to"]:
                okay = okay and str(item.get(key, "")) != Start.OLD_LOCATION
    okay = okay and original.get("facilities", []).size() == 5
    okay = okay and str(original.get("facilities", [])[0].get(
        "location", "")) == Start.OLD_LOCATION
    if okay:
        print("SOL_AC_START_PASS")
        quit(0)
    else:
        push_error("SOL_AC_START_FAIL")
        quit(1)
