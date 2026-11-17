extends RefCounted
## Sol physical asset presentation, stage 1. READ ONLY.
## All objects correspond to actual Rust/N39 source facilities.
## DO NOT split a shared "earth-station" economic location here:
## facilities need paid physical transfer contracts before that migration.
const SOL: String = "system-sol"
const ORBITAL_TYPES: Array[String] = ["station", "shipyard"]
const SURFACE_TYPES: Array[String] = [
    "mining_rig", "refinery", "farm", "factory",
    "laboratory", "research", "power_plant"
]
## Deterministic, deliberately SCHEMATIC land coordinates on existing
## stylized Earth. Not geographic latitude/longitude or a world colony.
const SURFACE_SITES: Array[Vector2] = [
    Vector2(-0.45, -0.36), Vector2(-0.24, -0.46),
    Vector2(0.41, 0.22), Vector2(0.54, 0.41),
    Vector2(-0.31, 0.09), Vector2(0.36, 0.43),
    Vector2(-0.53, 0.10), Vector2(0.22, 0.50)
]

static func build(world: Dictionary) -> Dictionary:
    if str(world.get("system", {}).get("id", "")) != SOL:
        return {"orbital": [], "surface": [], "source_ids": []}
    var orbital: Array = []
    var surface: Array = []
    var seen: Dictionary = {}
    var raw: Variant = world.get("facilities", [])
    if not (raw is Array):
        return {"error": "invalid_source_facilities"}
    for item in raw:
        if not (item is Dictionary):
            return {"error": "invalid_source_facility"}
        var id: String = str(item.get("id", ""))
        var kind: String = str(item.get("type", ""))
        var body: String = str(item.get("body", ""))
        var location: String = str(item.get("location", ""))
        if id.is_empty() or seen.has(id):
            return {"error": "duplicate_or_empty_facility_id"}
        seen[id] = true
        if not (kind in ORBITAL_TYPES or kind in SURFACE_TYPES):
            continue # Other legacy source types are not guessed.
        var item_type: String = ("orbital" if kind in ORBITAL_TYPES
            else "surface")
        var projected: Dictionary = {
            "id": id, "name": str(item.get("name", id)),
            "type": kind, "body": body, "location": location,
            "faction_id": str(item.get("faction_id", "")),
            "kind": item_type,
            "docking_capacity": int(item.get("docking_capacity", 0)),
            "services": item.get("services", []).duplicate(true),
            "shared_legacy_location": location == "earth-station"
        }
        if item_type == "orbital":
            orbital.append(projected)
        else:
            surface.append(projected)
    orbital.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    surface.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    var ordinal_by_body: Dictionary = {}
    for facility in surface:
        var bid: String = str(facility["body"])
        var ordinal: int = int(ordinal_by_body.get(bid, 0))
        ordinal_by_body[bid] = ordinal + 1
        facility["site"] = SURFACE_SITES[ordinal % SURFACE_SITES.size()]
    var ids: Array = seen.keys()
    ids.sort()
    return {"orbital": orbital, "surface": surface, "source_ids": ids}


static func live_status(facility: Dictionary,
        live_facilities: Dictionary) -> Dictionary:
    var id: String = str(facility.get("id", ""))
    if not live_facilities.has(id):
        return {"present": false}
    var row: Dictionary = live_facilities[id]
    var shift: Dictionary = row.get("work_shift", {})
    return {
        "present": true,
        "credits": int(row.get("credits", 0)),
        "workers": int(row.get("assigned_workers", 0)),
        "shift_tick": int(shift.get("tick", -1)),
        "shift_wages": int(shift.get("wages", 0)),
        "status": str(row.get("status", "")),
        "modules": int(row.get("modules", []).size()) if row.get(
            "modules", []) is Array else 0
    }
