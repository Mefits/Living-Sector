extends SceneTree
## godot --headless --path sol_lab -s res://tests/sol_planet_sprites_check.gd
const Sprites = preload("res://scripts/view/planet_sprite_catalog.gd")

func _initialize() -> void:
    var errors: Array[String] = []
    var sol_ids: Array[String] = [
        "mercury", "venus", "earth", "luna", "mars",
        "jupiter", "saturn", "uranus", "neptune"]
    for bid in sol_ids:
        _check({"id": bid, "type": "moon" if bid == "luna" else "planet",
            "biome": "lifeless"}, "system-sol", errors)
    var types: Array[String] = [
        "earthlike", "marslike", "gas_giant", "ice_world",
        "volcanic", "barren", "ocean_world", "desert_world",
        "venuslike", "ice_giant", "titanlike", "tidally_locked"]
    for type_name in types:
        _check({"id": "test", "type": "planet", "biome": "unknown",
            "visual_biome": type_name}, "other-system", errors)
    if Sprites.sprite_key({"id": "belt", "type": "belt",
            "biome": "asteroid"}, "system-sol") != "":
        errors.append("Asteroid belt must stay a schematic glyph")
    if Sprites.sprite_key({"id": "earth", "type": "planet",
            "biome": "terrestrial"}, "system-sol") != "sol/earth":
        errors.append("Sol body must override biome atlas")
    for issue in errors:
        push_error(issue)
    if errors.is_empty():
        print("SOL_PLANET_SPRITES_OK: 9 Sol bodies and 12 biome types with both textures")
    quit(0 if errors.is_empty() else 1)


func _check(body: Dictionary, system_id: String, errors: Array[String]) -> void:
    for use_icon in [false, true]:
        var texture: Texture2D = Sprites.texture_for(body, system_id, use_icon)
        var key: String = Sprites.sprite_key(body, system_id)
        if texture == null:
            errors.append("Texture missing: %s icon=%s" % [key, use_icon])
            continue
        # Three vector pilot bodies use a 512px normal-view tier, while
        # the remaining Sol/biome PNGs keep their original 256px dimensions.
        var pilot: bool = Sprites.VECTOR_PILOT_KEYS.has(key)
        var expected: int = 32 if use_icon else (512 if pilot else 256)
        if texture.get_width() != expected or texture.get_height() != expected:
            errors.append("Unexpected texture size: %s icon=%s" % [key, use_icon])
