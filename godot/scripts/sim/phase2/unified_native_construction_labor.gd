extends RefCounted
## N141 native construction paid WorkShift adapter. No secondary World,
## wallet, personnel, free engineer, or construction-progress shortcut.
const Labor = preload("res://scripts/sim/phase1/n141_construction_paid_labor.gd")
const Materialize = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _active_construction(tree: Dictionary) -> String:
    if not NativeBt.validate(tree):
        return ""
    var cursor: Dictionary = tree
    for _i in range(32):
        var kind: String = str(cursor.get("kind", ""))
        if kind == "action":
            var action: Dictionary = cursor.get("action", {})
            if str(action.get("kind", "")) != "Construct":
                return ""
            return str(action.get("site_id", ""))
        if kind == "sequence":
            var children: Array = cursor.get("children", [])
            var index: int = int(cursor.get("index", 0))
            if index < 0 or index >= children.size():
                return ""
            cursor = children[index]
        elif kind == "selector":
            var children: Array = cursor.get("children", [])
            if children.is_empty():
                return ""
            cursor = children[0]
        else:
            return ""
    return ""

static func executor(world: Dictionary, site: Dictionary) -> String:
    var ids: Array = world.get("ships", {}).keys()
    ids.sort()
    for id in ids:
        var ship: Dictionary = world["ships"][id]
        var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
        if not spec.get("crew_roles", []).has("engineer"):
            continue
        if str(ship.get("faction_id", "")) != str(site.get("faction_id", "")):
            continue
        if str(ship.get("current_goal", "")) != "construct" or not (ship.get("current_bt") is Dictionary):
            continue
        if _active_construction(ship["current_bt"]) != str(site.get("id", "")):
            continue
        var station_order: Variant = site.get("labor", {}).get("station_order", null)
        if station_order is Dictionary:
            var assigned: String = str(station_order.get("executor_id", ""))
            if not assigned.is_empty() and assigned != str(id):
                continue
        if str(ship.get("location", "")) != str(site.get("location_name", "")) or not ship.get("transit", {}).is_empty():
            continue
        var dock_id: String = str(ship.get("docked_at", ""))
        if dock_id.is_empty() or not world["facilities"].has(dock_id):
            continue
        var dock: Dictionary = world["facilities"][dock_id]
        if bool(dock.get("abandoned", false)) or str(dock.get("location", "")) != str(site.get("location_name", "")):
            continue
        return str(id)
    return ""

static func _native_shift(shift: Dictionary) -> Dictionary:
    var workers: Array = []
    var by_id: Dictionary = shift.get("workers", {})
    if by_id is Dictionary:
        var ids: Array = by_id.keys()
        ids.sort()
        for id in ids:
            workers.append([str(id), int(by_id[id])])
    elif by_id is Array:
        workers = by_id.duplicate(true)
    return {"tick": int(shift.get("tick", -1)), "workers": workers}

static func paid_shift(world: Dictionary, site_id: String,
        tick: int, multiplier: int) -> Dictionary:
    if not Materialize.labor_tick_due(tick, multiplier):
        return {"ok": false, "reason": "not_native_construction_work_tick"}
    if not world.get("construction_sites", {}).has(site_id):
        return {"ok": false, "reason": "native_construction_site_missing"}
    var site: Dictionary = world["construction_sites"][site_id]
    if bool(site.get("completed", false)):
        return {"ok": false, "reason": "native_construction_site_completed"}
    if int(site.get("progress_delivered", 0)) < int(site.get("progress_required", 0)):
        return {"ok": false, "reason": "native_material_delivery_pending"}
    var builder_id: String = executor(world, site)
    if builder_id.is_empty():
        return {"ok": false, "reason": "no_physically_present_active_n84_engineer"}
    var faction_id: String = str(site["faction_id"])
    if not world.get("faction_treasuries", {}).has(faction_id):
        return {"ok": false, "reason": "missing_n9_construction_treasury"}
    var households: Array = []
    var ids: Array = world["populations"].keys()
    ids.sort()
    for pid in ids:
        var p: Dictionary = world["populations"][pid]
        households.append({"id": str(pid),
            "faction_id": str(p["faction"]),
            "facility_location": str(p["location"]),
            "population_count": int(p["count"]),
            "total_wealth": int(p["wealth"]),
            "employed_fraction": float(p.get("employed_fraction", 0.0))})
    var facility_shifts: Array = []
    for id in world["facilities"]:
        var shift: Dictionary = world["facilities"][id].get("work_shift", {})
        if not shift.is_empty() and int(shift.get("tick", -1)) == tick:
            facility_shifts.append(_native_shift(shift))
    var commander_shifts: Array = []
    for fid in world.get("research_directors", {}):
        var shift = world["research_directors"][fid].get("last_shift", null)
        if shift is Dictionary and int(shift.get("tick", -1)) == tick:
            commander_shifts.append(_native_shift(shift))
    var construction_shifts: Array = []
    for sid in world["construction_sites"]:
        var shift = world["construction_sites"][sid].get("labor", {}).get("last_shift", null)
        if shift is Dictionary and int(shift.get("tick", -1)) == tick:
            construction_shifts.append(_native_shift(shift))
    var state: Dictionary = {"site": site.duplicate(true),
        "faction": {"id": faction_id, "treasury": int(world["faction_treasuries"][faction_id])},
        "households": households, "facility_shifts": facility_shifts,
        "construction_shifts": construction_shifts, "commander_shifts": commander_shifts}
    var result: Dictionary = Labor.work(state, tick, builder_id)
    if not result.get("ok", false):
        return {"ok": false, "reason": str(result.get("reason", "native_paid_labor_denied"))}
    result["site_id"] = site_id
    result["faction_id"] = faction_id
    result["executor_id"] = builder_id
    return result
