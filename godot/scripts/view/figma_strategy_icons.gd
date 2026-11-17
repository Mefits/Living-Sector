extends RefCounted
## Exact SVG stroke geometry from the connected Living Sector Figma Make
## React Icon component, rasterized once per key/size as native Godot Texture2D.
## No stock emojis, no external Figma asset requests, no browser overlay.
const GEOMETRY: Dictionary = {
    "colony":"<circle cx='12' cy='12' r='8'/><path d='M4.5 14h15M7 7.5c2 1.5 3.2 4.2 3.2 8.5m6.8-8.2c-2.1 1.6-3.4 4.1-3.4 8.2'/>",
    "economy":"<path d='M4 18V9m5 9V5m5 13v-6m5 6V3'/><path d='m3 7 5-4 5 6 7-7'/>",
    "construction":"<path d='M4 20V8l8-5 8 5v12'/><path d='M2 20h20M8 20v-6h8v6M7 9h2m6 0h2'/>",
    "research":"<circle cx='10' cy='10' r='6'/><path d='m14.5 14.5 6 6M8 10h4m-2-2v4'/>",
    "fleet":"<path d='m12 3 8 15-8-3-8 3 8-15Z'/><path d='M12 8v7'/>",
    "administration":"<circle cx='8' cy='8' r='3'/><circle cx='17' cy='9' r='2.5'/><path d='M3 20c.6-4 2.3-6 5-6s4.4 2 5 6m0-4c1-2 2.4-3 4-3 2.2 0 3.5 1.7 4 5'/>",
    "alert":"<path d='M12 3 2.5 20h19L12 3Z'/><path d='M12 9v5m0 3v.1'/>",
    "planet":"<circle cx='12' cy='12' r='6'/><path d='M2 15c4 1 9 0 14-2s7-4 5-5'/>",
    "station":"<path d='M7 7h10v10H7zM3 12h4m10 0h4M12 3v4m0 10v4'/><circle cx='12' cy='12' r='2'/>",
    "ship":"<path d='m4 14 8-11 8 11-8 7-8-7Z'/><path d='m8 13 4-2 4 2M12 3v8'/>",
    "facility":"<path d='M3 21V9l6 3V8l6 4V5l6 4v12H3Z'/><path d='M7 17h2m3 0h2m3 0h2'/>",
    "close":"<path d='m6 6 12 12M18 6 6 18'/>",
    "chevron":"<path d='m8 10 4 4 4-4'/>",
    "pin":"<path d='M12 21s6-6.3 6-12a6 6 0 1 0-12 0c0 5.7 6 12 6 12Z'/><circle cx='12' cy='9' r='2'/>",
    "search":"<circle cx='10' cy='10' r='6'/><path d='m15 15 5 5'/>",
    "pause":"<path d='M9 5v14m6-14v14'/>",
    "play":"<path d='m8 5 11 7-11 7V5Z'/>",
    "fast":"<path d='m4 6 7 6-7 6V6Zm9 0 7 6-7 6V6Z'/>"
}
static var _textures: Dictionary = {}

static func texture(kind: String, pixels: int = 22,
        tint: Color = Color("#53B5AC")) -> Texture2D:
    var size: int = clampi(pixels, 12, 64)
    if not GEOMETRY.has(kind):
        return null
    var key: String = "%s|%d|%s" % [kind, size, tint.to_html()]
    if _textures.has(key):
        return _textures[key]
    var svg: String = ("<svg xmlns='http://www.w3.org/2000/svg' " +
        "width='%d' height='%d' viewBox='0 0 24 24' fill='none' " +
        "stroke='#%s' stroke-width='1.6' " +
        "stroke-linecap='round' stroke-linejoin='round'>%s</svg>") % [
            size, size, tint.to_html(false), str(GEOMETRY[kind])]
    var img := Image.new()
    var err: Error = img.load_svg_from_string(svg)
    if err != OK or img.is_empty():
        return null
    var tex: Texture2D = ImageTexture.create_from_image(img)
    _textures[key] = tex
    return tex
