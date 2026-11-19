extends SceneTree
## godot --headless --path sol_lab -s res://tests/sol_planet_vector_pilot_check.gd
## Verify embedded SVG sources, raster fallbacks and cached zoom tiers.
const Catalog = preload("res://scripts/view/planet_sprite_catalog.gd")
const VectorSources = preload("res://scripts/view/planet_svg_sources.gd")


func _initialize() -> void:
    var cases: Array[Dictionary] = [
        {"body": {"id": "earth", "type": "planet", "biome": "terrestrial"},
         "system": "system-sol", "key": "sol/earth"},
        {"body": {"id": "saturn", "type": "planet", "biome": "gas_giant"},
         "system": "system-sol", "key": "sol/saturn"},
        {"body": {"id": "other-1", "type": "planet", "biome": "desert"},
         "system": "system-other", "key": "biomes/desert_world"}
    ]
    var issues: Array[String] = []
    for item in cases:
        var body: Dictionary = item["body"]
        var system: String = str(item["system"])
        var svg_source: String = VectorSources.source_for(str(item["key"]))
        if not svg_source.contains("<svg") or not svg_source.contains("</svg>"):
            issues.append("Embedded SVG source missing: %s" % str(item["key"]))
        var far: Texture2D = Catalog.texture_for(body, system, true)
        var near: Texture2D = Catalog.texture_for(body, system, false, 480.0)
        if far == null or far.get_width() != 32:
            issues.append("Missing 32px icon: %s" % str(item["key"]))
        if near == null or near.get_width() != 512:
            issues.append("Missing 512px vector tier: %s" % str(item["key"]))
        if near != null and not (near is DPITexture):
            issues.append("Not using live SVG-backed DPITexture: %s" % str(
                item["key"]))
        elif near is DPITexture:
            # get_width() alone is misleading: set_size_override() can
            # report 512 while its underlying raster is only 256px.
            var actual_image: Image = near.get_image()
            if actual_image == null or actual_image.get_width() != 512:
                issues.append("SVG is stretched instead of rasterized at 512: %s"
                    % str(item["key"]))

    var earth: Dictionary = {
        "id": "earth", "type": "planet", "biome": "terrestrial"}
    for span in [400.0, 800.0, 1600.0, 2600.0]:
        var expected: int = Catalog.vector_resolution(span)
        var actual: Texture2D = Catalog.texture_for(
            earth, "system-sol", false, span)
        if actual == null or actual.get_width() != expected:
            issues.append("Wrong zoom tier at %s px: %d" % [span, expected])
        elif actual is DPITexture and span <= 800.0:
            # Check actual image pixels, not just Texture2D logical width.
            var pixels: Image = actual.get_image()
            if pixels == null or pixels.get_width() != expected:
                issues.append("Raster not regenerated at %s px: %d" % [
                    span, expected])
        var again: Texture2D = Catalog.texture_for(
            earth, "system-sol", false, span)
        if actual != again:
            issues.append("Not reusing cached SVG texture at %s px" % span)

    var moon: Texture2D = Catalog.texture_for(
        {"id": "luna", "type": "moon", "biome": "lifeless"},
        "system-sol", false, 2000.0)
    if moon == null or moon.get_width() != 256:
        issues.append("Nonpilot Moon PNG changed unexpectedly")
    for issue in issues:
        push_error(issue)
    if issues.is_empty():
        print("SOL_PLANET_VECTOR_PILOT_PASS: dynamic zoom SVG at 512/1024/2048/4096px")
    quit(0 if issues.is_empty() else 1)
