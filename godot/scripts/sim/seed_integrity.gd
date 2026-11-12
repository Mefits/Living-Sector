extends RefCounted
## Read-only preflight for the exact native Galaxy seed. Never repairs input.
## Reports stable codes rather than silently dropping malformed entities.
const REQUIRED_ARRAYS = ["bodies", "facilities", "ships", "populations", "markets", "travel_routes", "nav_sites"]
const EXPECTED_COUNTS = {"systems": 8, "factions": 3, "bodies": 47, "facilities": 15, "ships": 24, "markets": 3, "populations": 3}
const EXPECTED_SYSTEMS = ["system-alpha-centauri", "system-barnard", "system-epsilon-eridani", "system-lalande", "system-nadir", "system-sol", "system-tau-ceti", "system-vega"]
const EXPECTED_FACTIONS = ["terran-authority", "pirates", "ceti-freeholds"]

static func inspect(seed: Dictionary, enforce_reference_counts: bool = true) -> Dictionary:
    var errors: Array[String] = []
    var worlds: Variant = seed.get("worlds", null)
    var factions: Variant = seed.get("factions", null)
    if not (worlds is Array) or not (factions is Array):
        return {"ok": false, "errors": ["seed:missing_arrays"], "counts": {}}
    var ids: Dictionary = {"system": {}, "faction": {}, "body": {}, "facility": {}}
    var counts: Dictionary = {"systems": 0, "factions": 0, "bodies": 0, "facilities": 0, "ships": 0, "markets": 0, "populations": 0}
    for i in range(factions.size()):
        var f: Variant = factions[i]
        if not (f is Dictionary):
            errors.append("faction:%d:not_object" % i)
            continue
        _unique(ids["faction"], str(f.get("id", "")), "faction:%d" % i, errors)
        counts["factions"] += 1
    for wi in range(worlds.size()):
        var world: Variant = worlds[wi]
        if not (world is Dictionary):
            errors.append("world:%d:not_object" % wi)
            continue
        var system: Variant = world.get("system", null)
        if not (system is Dictionary):
            errors.append("world:%d:missing_system" % wi)
            continue
        var sid: String = str(system.get("id", ""))
        _unique(ids["system"], sid, "world:%d" % wi, errors)
        counts["systems"] += 1
        var offset: Variant = system.get("universe_offset", null)
        if not (offset is Array) or offset.size() != 2:
            errors.append("world:%d:bad_offset" % wi)
        elif not _finite_number(offset[0]) or not _finite_number(offset[1]):
            errors.append("world:%d:bad_offset" % wi)
        for field in REQUIRED_ARRAYS:
            if not (world.get(field, null) is Array):
                errors.append("world:%d:missing_%s" % [wi, field])
        for field in REQUIRED_ARRAYS:
            var values: Variant = world.get(field, null)
            if not (values is Array):
                continue
            if counts.has(field):
                counts[field] += values.size()
            elif field == "bodies":
                counts["bodies"] += values.size()
            elif field == "facilities":
                counts["facilities"] += values.size()
            for i in range(values.size()):
                var item: Variant = values[i]
                if not (item is Dictionary):
                    errors.append("world:%d:%s:%d:not_object" % [wi, field, i])
                    continue
                var where: String = "world:%d:%s:%d" % [wi, field, i]
                if field == "bodies" or field == "facilities":
                    _unique(ids["body"] if field == "bodies" else ids["facility"], str(item.get("id", "")), where, errors)
                if field == "bodies":
                    if not _finite_number(item.get("orbit_period", null)) or float(item.get("orbit_period", 0.0)) <= 0.0:
                        errors.append(where + ":bad_orbit_period")
                    if not _finite_number(item.get("current_angle", null)):
                        errors.append(where + ":bad_angle")
                    elif float(item["current_angle"]) < 0.0 or float(item["current_angle"]) >= 360.0:
                        errors.append(where + ":bad_angle")
                if field == "travel_routes":
                    if str(item.get("from", "")).is_empty() or str(item.get("to", "")).is_empty() or str(item.get("from", "")) == str(item.get("to", "")):
                        errors.append(where + ":bad_route")
                    if not _finite_number(item.get("distance", null)) or float(item.get("distance", 0.0)) <= 0.0:
                        errors.append(where + ":bad_distance")
    for wi in range(worlds.size()):
        var world: Variant = worlds[wi]
        if not (world is Dictionary):
            continue
        for field in ["facilities", "ships"]:
            var values: Variant = world.get(field, [])
            if not (values is Array):
                continue
            for i in range(values.size()):
                var item: Variant = values[i]
                if item is Dictionary and not ids["faction"].has(str(item.get("faction_id", ""))):
                    errors.append("world:%d:%s:%d:unknown_faction" % [wi, field, i])
    if enforce_reference_counts:
        for id in EXPECTED_SYSTEMS:
            if not ids["system"].has(id):
                errors.append("reference:missing_system:" + id)
        for id in EXPECTED_FACTIONS:
            if not ids["faction"].has(id):
                errors.append("reference:missing_faction:" + id)
        for field in EXPECTED_COUNTS:
            if counts[field] != EXPECTED_COUNTS[field]:
                errors.append("reference:count:%s:%d" % [field, counts[field]])
    errors.sort()
    return {"ok": errors.is_empty(), "errors": errors, "counts": counts}

static func _unique(seen: Dictionary, id: String, where: String, errors: Array[String]) -> void:
    if id.is_empty():
        errors.append(where + ":empty_id")
    elif seen.has(id):
        errors.append(where + ":duplicate_id:" + id)
    else:
        seen[id] = true

static func _finite_number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))
