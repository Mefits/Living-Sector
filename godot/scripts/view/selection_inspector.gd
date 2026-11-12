extends RefCounted
## N49 read-only system selection snapshot. Does not own or mutate WorldModel.
## Seed IDs and orbit angles are native; distances are not light-years.

const MAX_ENTITIES: int = 100000

func inspect(world_model: RefCounted, system_id: String, tick: int) -> Dictionary:
    if world_model == null or not world_model.is_loaded() or system_id.is_empty() or tick < 0:
        return {"ok": false, "error": "invalid_selection"}
    var world: Dictionary = world_model.system_by_id(system_id)
    if world.is_empty():
        return {"ok": false, "error": "unknown_system"}
    var system_value: Variant = world.get("system", null)
    if not (system_value is Dictionary) or str(system_value.get("id", "")) != system_id:
        return {"ok": false, "error": "system_identity_mismatch"}
    var coords: Variant = system_value.get("universe_offset", null)
    if not (coords is Array) or coords.size() != 2:
        return {"ok": false, "error": "invalid_coordinates"}
    for component in coords:
        if not (component is float or component is int) or not is_finite(float(component)):
            return {"ok": false, "error": "invalid_coordinates"}
    var kinds: Array[String] = ["bodies", "facilities", "ships", "markets", "populations", "travel_routes"]
    var counts: Dictionary = {}
    var entities: Dictionary = {}
    var errors: Array[String] = []
    for kind in kinds:
        var values: Variant = world.get(kind, [])
        if not (values is Array) or values.size() > MAX_ENTITIES:
            return {"ok": false, "error": "invalid_collection", "collection": kind}
        counts[kind] = values.size()
        var records: Array[Dictionary] = []
        var seen: Dictionary = {}
        for value in values:
            if not (value is Dictionary):
                return {"ok": false, "error": "invalid_entity", "collection": kind}
            var identity: String = str(value.get("id", ""))
            # Routes can be source-keyed rather than ID-keyed; preserve native endpoints.
            if kind == "travel_routes":
                identity = str(value.get("from", "")) + " -> " + str(value.get("to", ""))
            if identity.is_empty() or (kind != "travel_routes" and seen.has(identity)):
                errors.append(kind + ": missing_or_duplicate_identity")
                continue
            seen[identity] = true
            var record: Dictionary = {"id": identity}
            if kind == "bodies":
                var angle: Variant = value.get("current_angle", null)
                var period: Variant = value.get("orbit_period", null)
                if not (angle is float or angle is int) or not (period is float or period is int):
                    errors.append("body: invalid_orbit " + identity)
                    continue
                if not is_finite(float(angle)) or float(angle) < 0.0 or float(angle) >= 360.0 or not is_finite(float(period)) or float(period) <= 0.0:
                    errors.append("body: invalid_orbit " + identity)
                    continue
                record["angle"] = float(angle)
                record["period"] = float(period)
            records.append(record)
        records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
        entities[kind] = records
    errors.sort()
    return {
        "ok": errors.is_empty(),
        "error": "" if errors.is_empty() else "entity_integrity",
        "errors": errors,
        "system_id": system_id,
        "system_name": str(system_value.get("name", "")),
        "tick": tick,
        "native_universe_offset": coords.duplicate(true),
        "units": "native_universe_offset_not_light_years",
        "counts": counts,
        "entities": entities
    }

func describe(snapshot: Dictionary) -> String:
    if not snapshot.get("ok", false):
        return "Диагностика выбора: " + str(snapshot.get("error", "unknown"))
    var counts: Dictionary = snapshot["counts"]
    return "Диагностика P1 · тик %d · %d тел · %d станций · %d кораблей (seed, не движение)" % [
        int(snapshot["tick"]), int(counts["bodies"]), int(counts["facilities"]), int(counts["ships"])
    ]
