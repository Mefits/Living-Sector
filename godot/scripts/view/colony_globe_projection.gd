extends RefCounted
## UI-only colony projection over an already-detached N39 snapshot.
## Never changes physical facilities, markets, construction, N9 or clock.
## No invented deliveries: points signify recent paid work, not cargo receipts.

const MAX_SURFACE: int = 48
const MAX_ORBIT: int = 12
const MAX_LINKS: int = 24
const RECENT_SHIFT_TICKS: int = 12

static func _position_for_id(facility_id: String) -> Vector2:
    # Stable visual footprint on the schematic land areas of the globe.
    # This is NOT a saved physical building coordinate or a nine-slot grid.
    var h: int = absi(facility_id.hash())
    var angle: float = float(h % 6283) / 1000.0
    var dist: float = 0.06 + float(floori(float(h) / 6283.0) % 100) / 100.0 * 0.17
    var land_center: Vector2 = Vector2(-0.34, -0.34)
    if h % 3 == 0:
        land_center = Vector2(0.45, 0.39)
    return land_center + Vector2(cos(angle), sin(angle)) * dist

static func _shift_workers(facility: Dictionary, tick: int) -> int:
    var shift: Variant = facility.get("work_shift", {})
    if not (shift is Dictionary) or shift.is_empty():
        return 0
    var at: int = int(shift.get("tick", -100000))
    if at < tick - RECENT_SHIFT_TICKS or at > tick:
        return 0
    var workers: Variant = shift.get("workers", {})
    if not (workers is Dictionary):
        return 0
    var total: int = 0
    for count in workers.values():
        total += maxi(0, int(count))
    return total

static func build(body_id: String, seed_facilities: Array,
        economy: Dictionary, tick: int) -> Dictionary:
    if body_id.is_empty() or not (economy.get("facilities") is Dictionary):
        return {"nodes": [], "orbit": [], "links": [], "hub_id": ""}
    var names: Dictionary = {}
    for raw in seed_facilities:
        if raw is Dictionary:
            names[str(raw.get("id", ""))] = str(raw.get("name", ""))
    var live_facilities: Dictionary = economy["facilities"]
    var ids: Array = live_facilities.keys()
    ids.sort()
    var nodes: Array[Dictionary] = []
    var orbit: Array[Dictionary] = []
    for fid in ids:
        var fac: Variant = live_facilities[fid]
        if not (fac is Dictionary) or str(fac.get("body_id", "")) != body_id:
            continue
        var kind: String = str(fac.get("type", ""))
        var id: String = str(fid)
        var workers: int = _shift_workers(fac, tick)
        var abandoned: bool = bool(fac.get("abandoned", false))
        var activity: int = 0
        if not abandoned and workers > 0:
            activity = clampi(ceili(sqrt(float(workers)) * 2.0), 1, 9)
        var entry: Dictionary = {
            "id": id, "name": str(names.get(id, fac.get("name", id))),
            "type": kind, "location": str(fac.get("location", "")),
            "workers": workers, "activity": activity,
            "abandoned": abandoned, "pos": _position_for_id(id)
        }
        if kind in ["station", "shipyard", "gate", "construction_dock"]:
            if orbit.size() < MAX_ORBIT:
                orbit.append(entry)
        elif nodes.size() < MAX_SURFACE:
            nodes.append(entry)
    # The market's real station is a visual road-network anchor. An
    # independent administrative-centre building is NOT fabricated here.
    var hub_id: String = ""
    for entry in orbit:
        if str(entry["type"]) == "station":
            hub_id = str(entry["id"])
            break
    var links: Array[Dictionary] = []
    # Every on-surface facility connects to the schematic central node.
    for node in nodes:
        links.append({"a": "hub", "b": str(node["id"]),
            "activity": int(node["activity"]), "kind": "access"})
    # Display only plausible shared-market production chains. They are
    # visual relations, NOT confirmed facility-to-facility cargo transfers.
    for from_node in nodes:
        for to_node in nodes:
            if links.size() >= MAX_SURFACE + MAX_LINKS:
                break
            if from_node["id"] == to_node["id"] or (
                    str(from_node["location"]) != str(to_node["location"])):
                continue
            var from_type: String = str(from_node["type"])
            var to_type: String = str(to_node["type"])
            var connected: bool = (from_type == "mining_rig" and
                to_type == "refinery") or (from_type == "refinery" and
                to_type == "factory")
            if not connected:
                continue
            links.append({"a": str(from_node["id"]), "b": str(to_node["id"]),
                "activity": mini(int(from_node["activity"]), int(to_node["activity"])),
                "kind": "production"})
    return {"nodes": nodes, "orbit": orbit, "links": links, "hub_id": hub_id}
