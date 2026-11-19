extends RefCounted
## Visual-only lookup: Sol body IDs override the reusable biome atlas.
## Close-up vector pilot uses Godot 4.7 DPITexture with a bounded zoom-tier
## cache. The draw loop never rasterizes an SVG anew on each frame.

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
## Only these three visuals have editable SVG sources. Non-pilot planets
## and the 32px map icons keep their original/pre-exported PNGs.
const VECTOR_PILOT_KEYS: Dictionary = {
    "sol/earth": true,
    "sol/saturn": true,
    "biomes/desert_world": true
}
## Avoid 512px textures being blown up across an entire zoomed-in viewport.
## All resolutions are cached; no SVG is re-rasterized for individual frames.
const VECTOR_CACHE_LIMIT: int = 6

static var _texture_cache: Dictionary = {}
static var _vector_cache_keys: Array[String] = []


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


## Pure selection, expressed in physical screen pixels (including UI scale).
## Round up rather than enlarging raster pixels. Cap the large tier at 4096.
static func vector_resolution(display_diameter_px: float) -> int:
    if display_diameter_px <= 512.0:
        return 512
    if display_diameter_px <= 1024.0:
        return 1024
    if display_diameter_px <= 2048.0:
        return 2048
    return 4096


static func _vector_texture(key: String, display_diameter_px: float) -> Texture2D:
    var resolution: int = vector_resolution(display_diameter_px)
    var cached_key: String = "svg:%s:%d" % [key, resolution]
    if _texture_cache.has(cached_key):
        return _texture_cache[cached_key] as Texture2D

    var path: String = "res://assets/planets_svg/%s.svg" % key
    if not ResourceLoader.exists(path, "DPITexture"):
        return null
    var source: DPITexture = ResourceLoader.load(path, "DPITexture") as DPITexture
    if source == null:
        return null

    # Override actual raster size, not the Control transform. This allows
    # zoomed-in continents to retain SVG-defined edges at large magnifications.
    var scaled: DPITexture = source.duplicate() as DPITexture
    if scaled == null:
        return null
    scaled.set_size_override(Vector2i(resolution, resolution))

    _texture_cache[cached_key] = scaled
    _vector_cache_keys.append(cached_key)
    while _vector_cache_keys.size() > VECTOR_CACHE_LIMIT:
        var oldest: String = _vector_cache_keys.pop_front()
        _texture_cache.erase(oldest)
    return scaled


## Fourth parameter is the on-screen texture diameter in physical pixels.
## Default keeps old tests and other callers working without code changes.
static func texture_for(body: Dictionary, system_id: String,
        map_icon: bool = false, display_diameter_px: float = 0.0) -> Texture2D:
    var key: String = sprite_key(body, system_id)
    if key.is_empty():
        return null
    var pieces: PackedStringArray = key.split("/")
    var folder: String = "map_icons" if map_icon else "planets"

    if VECTOR_PILOT_KEYS.has(key) and not map_icon:
        var vector_texture: Texture2D = _vector_texture(
            key, display_diameter_px)
        if vector_texture != null:
            return vector_texture

    # Safe fallback if SVG import is unavailable, including exported builds.
    # Other 18 planet types are unchanged.
    var path: String = "res://assets/planets/%s/%s/%s.png" % [
        pieces[0], folder, pieces[1]]
    if VECTOR_PILOT_KEYS.has(key):
        var vector_png: String = "res://assets/planets/%s/%s/%s_vector.png" % [
            pieces[0], folder, pieces[1]]
        if ResourceLoader.exists(vector_png, "Texture2D"):
            path = vector_png
    if _texture_cache.has(path):
        return _texture_cache[path] as Texture2D
    var texture: Texture2D = null
    if ResourceLoader.exists(path, "Texture2D"):
        texture = ResourceLoader.load(path, "Texture2D") as Texture2D
    _texture_cache[path] = texture
    return texture
