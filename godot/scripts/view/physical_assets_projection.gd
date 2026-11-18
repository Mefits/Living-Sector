extends RefCounted
## Common read-only presentation of REAL source/N39 facilities in any system.
## A newly completed N151 colony is the same station ID that previously was
## a construction_dock; no imaginary AC, market, or construction is minted.
const Surface = preload("res://scripts/view/planet_surface_projection.gd")
const ORBITAL_TYPES: Array[String] = ["station", "shipyard",
    "construction_dock"]
const SURFACE_TYPES: Array[String] = ["mining_rig", "refinery", "farm",
    "factory", "laboratory", "research", "power_plant"]

static func _asset(id: String, item: Dictionary) -> Dictionary:
    var bid: String = str(item.get("body_id",
        item.get("body", "")))
    var kind: String = str(item.get("type", ""))
    var location: String = str(item.get("location", ""))
    # N151's original dock/station on body-colony is a ground
    # administrative centre visually. The real N39 type stays unchanged.
    var colony: bool = (
        (kind in ORBITAL_TYPES) and
        location == bid + "-colony" and not bid.is_empty())
    return {
        "id": id, "name": str(item.get("name", id)),
        "type": kind, "body": bid, "location": location,
        "faction_id": str(item.get("faction_id",
            item.get("faction", ""))),
        "kind": "surface" if colony or kind in SURFACE_TYPES
            else "orbital",
        "render_type": (
            "colony_construction_dock" if colony and
            kind == "construction_dock" else
            "administrative_center" if colony else kind),
        "docking_capacity": int(item.get("docking_capacity", 0)),
        "services": (item.get("services", []) as Array).duplicate(true)
            if item.get("services", []) is Array else [],
        "shared_legacy_location": location == "earth-station"
    }

static func build(world: Dictionary,
        live_facilities: Dictionary = {}) -> Dictionary:
    var system_id: String = str(world.get("system", {}).get("id", ""))
    var bodies: Dictionary = {}
    var profiles: Dictionary = {}
    for value in world.get("bodies", []):
        if not (value is Dictionary):
            continue
        var bid: String = str(value.get("id", ""))
        if bid.is_empty() or bodies.has(bid):
            continue
        bodies[bid] = value
        profiles[bid] = Surface.build(value, system_id)
    var source: Variant = world.get("facilities", [])
    if not (source is Array):
        return {"error": "invalid_source_facilities"}
    var orbital: Array = []
    var surface: Array = []
    var seen: Dictionary = {}
    for value in source:
        if not (value is Dictionary):
            return {"error": "invalid_source_facility"}
        var id: String = str(value.get("id", ""))
        if id.is_empty() or seen.has(id):
            return {"error": "duplicate_or_empty_facility_id"}
        seen[id] = true
        var kind: String = str(value.get("type", ""))
        if not (kind in ORBITAL_TYPES or kind in SURFACE_TYPES):
            continue
        var asset: Dictionary = _asset(id, value)
        # Keep old seed-test compatibility if the fixture has no body list.
        if not bodies.is_empty() and not bodies.has(asset["body"]):
            continue
        if asset["kind"] == "orbital":
            orbital.append(asset)
        else:
            surface.append(asset)
    # Dynamic N39 rows contain body_id and are not inserted into the
    # frozen WorldModel. Include only verified bodies in this system.
    for fid in live_facilities:
        var id: String = str(fid)
        if id.is_empty() or seen.has(id):
            continue
        var candidate: Variant = live_facilities[fid]
        if not (candidate is Dictionary):
            continue
        var row: Dictionary = candidate
        var bid: String = str(row.get("body_id",
            row.get("body", "")))
        var kind: String = str(row.get("type", ""))
        if not bodies.has(bid) or not (
                kind in ORBITAL_TYPES or kind in SURFACE_TYPES):
            continue
        seen[id] = true
        var asset: Dictionary = _asset(id, row)
        if asset["kind"] == "orbital":
            orbital.append(asset)
        else:
            surface.append(asset)
    orbital.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    surface.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    for facility in surface:
        var bid: String = str(facility["body"])
        var profile: Dictionary = profiles.get(bid, {})
        if profile.is_empty():
            profile = Surface.build({"id": bid,
                "biome": "terrestrial"}, system_id)
            profiles[bid] = profile
        facility["site"] = Surface.site_for(
            profile, str(facility["id"]))
        facility["hub_site"] = profile["hub_site"]
    return {
        "orbital": orbital, "surface": surface, "profiles": profiles,
        "source_ids": seen.keys()
    }

static func live_status(facility: Dictionary,
        live_facilities: Dictionary) -> Dictionary:
    var id: String = str(facility.get("id", ""))
    if not live_facilities.has(id) or not (
            live_facilities[id] is Dictionary):
        return {"present": false}
    var row: Dictionary = live_facilities[id]
    var raw_shift: Variant = row.get("work_shift", {})
    var shift: Dictionary = raw_shift if raw_shift is Dictionary else {}
    var paid_workers: int = 0
    var roster: Variant = shift.get("workers", {})
    if roster is Dictionary:
        for quantity in roster.values():
            paid_workers += maxi(0, int(quantity))
    return {
        "present": true,
        "credits": int(row.get("credits", 0)),
        "workers": int(row.get("assigned_workers", 0)),
        "shift_tick": int(shift.get("tick", -1)),
        "shift_wages": int(shift.get("wages", 0)),
        "shift_workers": paid_workers,
        "status": str(row.get("status", "")),
        "modules": (row.get("modules", []) as Array).size()
            if row.get("modules", []) is Array else 0
    }
