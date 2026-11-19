extends RefCounted
## Visual-only lookup: Sol body IDs override the reusable biome atlas.

const SOL_FILES: Dictionary = {
    "mercury": "mercury", "venus": "venus", "earth": "earth",
    "luna": "moon", "mars": "mars", "jupiter": "jupiter",
    "saturn": "saturn", "uranus": "uranus", "neptune": "neptune"
}
const BIOME_FILES: Dictionary = {
    "earthlike": "earthlike", "terrestrial": "earthlike",
    "marslike": "marslike", "gas_giant": "gas_giant",
    "ice_world": "ice_world", "ice": "ice_world",
    "volcanic": "volcanic", "molten": "volcanic",
    "barren": "barren", "lifeless": "barren",
    "ocean_world": "ocean_world",
    "desert_world": "desert_world", "desert": "desert_world",
    "venuslike": "venuslike", "ice_giant": "ice_giant",
    "titanlike": "titanlike", "tidally_locked": "tidally_locked"
}
## Only three pilot visuals use vector-sourced raster exports.
## Existing planets retain their original raster art.
const VECTOR_PILOT_KEYS: Dictionary = {
    "sol/earth": true,
    "sol/saturn": true,
    "biomes/desert_world": true
}

static var _texture_cache: Dictionary = {}


static func sprite_key(body: Dictionary, system_id: String) -> String:
    var kind: String = str(body.get("type", ""))
    if kind in ["asteroid", "belt", "star"]:
        return ""
    var bid: String = str(body.get("id", ""))
    if system_id == "system-sol" and SOL_FILES.has(bid):
        return "sol/" + str(SOL_FILES[bid])
    var biome: String = str(body.get("visual_biome", ""))
    if biome.is_empty():
        biome = str(body.get("biome", ""))
    if BIOME_FILES.has(biome):
        return "biomes/" + str(BIOME_FILES[biome])
    return ""


static func texture_for(body: Dictionary, system_id: String,
        map_icon: bool = false) -> Texture2D:
    var key: String = sprite_key(body, system_id)
    if key.is_empty():
        return null
    var pieces: PackedStringArray = key.split("/")
    var folder: String = "map_icons" if map_icon else "planets"
    var path: String = "res://assets/planets/%s/%s/%s.png" % [
        pieces[0], folder, pieces[1]]
    # Prefer pre-rendered 32 px / 512 px exports, never rasterize SVG in-game.
    # Preserve the original sprite if the pilot export is missing.
    if VECTOR_PILOT_KEYS.has(key):
        var vector_path: String = "res://assets/planets/%s/%s/%s_vector.png" % [
            pieces[0], folder, pieces[1]]
        if ResourceLoader.exists(vector_path, "Texture2D"):
            path = vector_path
    if _texture_cache.has(path):
        return _texture_cache[path] as Texture2D
    var texture: Texture2D = null
    if ResourceLoader.exists(path, "Texture2D"):
        texture = ResourceLoader.load(path, "Texture2D") as Texture2D
    _texture_cache[path] = texture
    return texture
