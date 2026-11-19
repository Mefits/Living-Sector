extends RefCounted
## Imported icons from the supplied Living-Sector-Resource-Icons and
## Living-Sector-Building-Sprites archives. Three real-size 20/32/64 atlases
## keep small UI crisp and avoid separate texture loads per icon.
const COLUMNS: int = 5
const RESOURCE_IDS: Dictionary = {
 "metals": 0, "ore": 1, "water": 2, "food": 3, "fuel": 4,
 "ice": 5, "components": 6, "gas": 7, "polymers": 8,
 "electronics": 9, "tools": 10, "medical_supplies": 11,
 "medical": 11, "luxury": 12
}
const BUILDING_IDS: Dictionary = {
 "administrative_center": 13, "station": 13,
 "colony_construction_dock": 13,
 "mining_rig": 14, "mining_complex": 14,
 "farm": 15, "power_plant": 16,
 "refinery": 17, "processing_complex": 17,
 "factory": 18, "spaceport": 19
}
## Energy cells, orbital platforms and shipyards are NOT in the supplied ZIPs.
## Never silently substitute electronics for energy.
static var _atlas_cache: Dictionary = {}
static var _region_cache: Dictionary = {}

static func _px(request: int) -> int:
 if request <= 24:
  return 20
 if request <= 45:
  return 32
 return 64

static func _index(kind: String, building: bool) -> int:
 return int((BUILDING_IDS if building else RESOURCE_IDS).get(kind, -1))

static func _texture(px: int) -> Texture2D:
 if _atlas_cache.has(px):
  return _atlas_cache[px] as Texture2D
 var path: String = "res://assets/icons/sol_icons_%d.png" % px
 var texture: Texture2D = null
 if ResourceLoader.exists(path, "Texture2D"):
  texture = ResourceLoader.load(path, "Texture2D") as Texture2D
 _atlas_cache[px] = texture
 return texture

static func icon_texture(kind: String, building: bool = false,
        preferred_px: int = 20) -> Texture2D:
 var index: int = _index(kind, building)
 if index < 0:
  return null
 var px: int = _px(preferred_px)
 var key: String = "%s:%d:%d" % ["b" if building else "r", index, px]
 if _region_cache.has(key):
  return _region_cache[key] as Texture2D
 var atlas: Texture2D = _texture(px)
 if atlas == null:
  return null
 var region := AtlasTexture.new()
 region.atlas = atlas
 region.region = Rect2(Vector2((index % COLUMNS) * px,
  (index / COLUMNS) * px), Vector2(px, px))
 _region_cache[key] = region
 return region

static func make_icon(kind: String, building: bool = false,
        preferred_px: int = 20) -> TextureRect:
 var source: Texture2D = icon_texture(kind, building, preferred_px)
 if source == null:
  return null
 var node := TextureRect.new()
 node.texture = source
 node.custom_minimum_size = Vector2(preferred_px, preferred_px)
 node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 node.mouse_filter = Control.MOUSE_FILTER_IGNORE
 node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 return node

## Draws from one real atlas on the globe. Returns false for unchanged
## fallback vector glyphs, never replacing a missing sprite with another type.
static func paint(canvas: CanvasItem, kind: String,
        center: Vector2, diameter: float, alpha: float = 1.0) -> bool:
 var index: int = _index(kind, true)
 if index < 0:
  return false
 var px: int = _px(roundi(diameter))
 var atlas: Texture2D = _texture(px)
 if atlas == null:
  return false
 var rect: Rect2 = Rect2(center - Vector2.ONE * diameter * 0.5,
  Vector2.ONE * diameter)
 var src: Rect2 = Rect2(Vector2((index % COLUMNS) * px,
  (index / COLUMNS) * px), Vector2(px, px))
 canvas.draw_texture_rect_region(atlas, rect, src,
  Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
 return true
