extends SceneTree
## SVG pilot must resolve generated PNG textures, and all other planets stay unchanged.
const Catalog = preload("res://scripts/view/planet_sprite_catalog.gd")

func _initialize() -> void:
    var cases: Array[Dictionary] = [
        {"body": {"id": "earth", "type": "planet", "biome": "terrestrial"},
         "system": "system-sol"},
        {"body": {"id": "saturn", "type": "planet", "biome": "gas_giant"},
         "system": "system-sol"},
        {"body": {"id": "other-1", "type": "planet", "biome": "desert"},
         "system": "system-other"}
    ]
    var okay: bool = true
    for item in cases:
        var body: Dictionary = item["body"]
        var system: String = str(item["system"])
        var far: Texture2D = Catalog.texture_for(body, system, true)
        var near: Texture2D = Catalog.texture_for(body, system, false)
        okay = okay and far != null and near != null
        if far != null and near != null:
            okay = okay and far.get_width() == 32 and far.get_height() == 32
            okay = okay and near.get_width() == 512 and near.get_height() == 512
    var moon: Texture2D = Catalog.texture_for(
        {"id": "luna", "type": "moon", "biome": "lifeless"},
        "system-sol", false)
    okay = okay and moon != null
    if okay:
        print("SOL_PLANET_VECTOR_PILOT_PASS")
        quit(0)
    else:
        push_error("SOL_PLANET_VECTOR_PILOT_FAIL")
        quit(1)
