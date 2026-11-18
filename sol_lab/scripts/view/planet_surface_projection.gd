extends RefCounted
## Deterministic, read-only 2D planet presentation for ANY system/body.
## The output uses normalized globe coordinates; no RNG global state, N39
## state, SceneTree node, simulation tick or file per planet.
## A procedural generator only needs to provide a unique body id, biome and
## optionally surface_seed / physical_radius_km. Save/load reproduces the view.

static func _hash_key(key: String) -> int:
    var h: int = 2166136261
    for i in range(key.length()):
        h = ((h ^ key.unicode_at(i)) * 16777619) & 0x7fffffff
    return h

static func _sample(seed: int, salt: int) -> float:
    var h: int = (seed + salt * 1103515245) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return float(h) / 2147483647.0

static func seed_for(body: Dictionary, system_id: String) -> int:
    var raw: Variant = body.get("surface_seed", null)
    if raw is int:
        return int(raw) & 0x7fffffff
    return _hash_key(system_id + ":" + str(body.get("id", "")))

static func build(body: Dictionary, system_id: String) -> Dictionary:
    var seed: int = seed_for(body, system_id)
    var biome: String = str(body.get("biome", "lifeless"))
    var regions: Array[Dictionary] = []
    var details: Array[Dictionary] = []
    var palettes: Dictionary = {
        "terrestrial": ["#789c7d", "#9bb38a", "#658967"],
        "desert": ["#baa17c", "#c9ad84", "#937759"],
        "molten": ["#9e5949", "#ca7455", "#713c3c"],
        "ice": ["#b7d0de", "#8faec6", "#d5e0e8"],
        "lifeless": ["#8e9eaf", "#a5b2be", "#627689"],
        "asteroid": ["#8994a2", "#76818e", "#b4bac1"]
    }
    var land_colors: Array = palettes.get(biome,
        palettes["lifeless"])
    if biome != "gas_giant":
        var count: int = 2 + int(floor(_sample(seed, 1) * 2.99))
        for k in range(count):
            var angle: float = _sample(seed, 10 + k * 5) * TAU
            var distance: float = 0.08 + 0.31 * _sample(
                seed, 11 + k * 5)
            var region_center := Vector2(
                cos(angle), sin(angle)) * distance
            var rx: float = 0.25 + 0.18 * _sample(seed, 12 + k * 5)
            var ry: float = 0.21 + 0.17 * _sample(seed, 13 + k * 5)
            var vertices := PackedVector2Array()
            var segments: int = 10
            for n in range(segments):
                var a: float = TAU * float(n) / float(segments)
                var irregular: float = (0.74 +
                    0.37 * _sample(seed, 100 + k * 16 + n))
                var point: Vector2 = region_center + Vector2(
                    cos(a) * rx, sin(a) * ry) * irregular
                if point.length() > 0.91:
                    point = point.normalized() * 0.91
                vertices.append(point)
            regions.append({
                "points": vertices, "center": region_center,
                "color": str(land_colors[k % land_colors.size()])
            })
        if biome == "terrestrial":
            details.append({
                "kind": "lake",
                "pos": regions[0]["center"] + Vector2(0.05, 0.06),
                "radius": 0.09 + 0.04 * _sample(seed, 220)
            })
        elif biome in ["ice", "lifeless", "asteroid"]:
            for j in range(3):
                var a: float = _sample(seed, 230 + j * 3) * TAU
                var d: float = 0.12 + 0.54 * _sample(
                    seed, 231 + j * 3)
                details.append({
                    "kind": "crater",
                    "pos": Vector2(cos(a), sin(a)) * d,
                    "radius": 0.04 + 0.09 * _sample(
                        seed, 232 + j * 3)
                })
    else:
        for j in range(5):
            details.append({
                "kind": "band",
                "y": -0.67 + float(j) * 0.33 +
                    (_sample(seed, 260 + j) - 0.5) * 0.09
            })
    var hub_site := Vector2(-0.30, -0.22)
    if not regions.is_empty():
        hub_site = regions[0]["center"]
    return {
        "seed": seed, "biome": biome, "regions": regions,
        "details": details, "hub_site": hub_site
    }

static func site_for(profile: Dictionary, facility_id: String) -> Vector2:
    var regions: Array = profile.get("regions", [])
    var seed: int = _hash_key(facility_id)
    if regions.is_empty():
        var theta: float = _sample(seed, 0) * TAU
        return Vector2(cos(theta), sin(theta)) * (
            0.25 + _sample(seed, 1) * 0.30)
    var which: int = seed % regions.size()
    var center: Vector2 = regions[which]["center"]
    var angle: float = _sample(seed, 2) * TAU
    var distance: float = 0.03 + 0.11 * _sample(seed, 3)
    var pos: Vector2 = center + Vector2(cos(angle),
        sin(angle)) * distance
    return pos.limit_length(0.86)
