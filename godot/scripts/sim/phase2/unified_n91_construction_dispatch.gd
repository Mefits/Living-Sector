extends RefCounted
## N91 source construction-executor selection over ONE existing N39 World.
## A site must have REAL paid N104/N15 material delivery before any ship
## is reserved. No contractor ship or labor is fabricated by this selector.
const Executor = preload("res://scripts/ported/n91_construction_executor.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func propose(world: Dictionary, resolver: RefCounted,
        tick: int) -> Dictionary:
    if tick < 1 or resolver == null or not (world.get("construction_sites") is Dictionary) or not (world.get("ships") is Dictionary):
        return {"ok": false, "reason": "missing_real_n91_world"}
    var sites: Array = []
    var site_ids: Array = world["construction_sites"].keys()
    site_ids.sort()
    for id in site_ids:
        var site: Dictionary = world["construction_sites"][id]
        if not world.get("markets", {}).has(str(site.get("location_name", ""))):
            return {"ok": false, "reason": "n91_site_without_real_market"}
        sites.append({
            "id": str(id), "completed": bool(site.get("completed", false)),
            "remaining_material": maxi(0, int(site.get("progress_required", 0)) -
                int(site.get("progress_delivered", 0))),
            "labor_completed": int(site.get("labor", {}).get("completed", 0)),
            "labor_required": int(site.get("labor", {}).get("required", 0)),
            "station_order": site.get("labor", {}).get("station_order", {}),
            "location": str(site.get("location_name", "")),
            "faction": str(site.get("faction_id", ""))
        })
    var class_catalogue: Dictionary = Catalog.CLASSES
    var ship_rows: Array = []
    var ship_ids: Array = world["ships"].keys()
    ship_ids.sort()
    var systems: Dictionary = {}
    for site in sites:
        systems[site["location"]] = resolver.system_for_location(str(site["location"]))
    for id in ship_ids:
        var row: Dictionary = world["ships"][id]
        var current_bt: Variant = row.get("current_bt", null)
        ship_rows.append({
            "id": str(id), "class": str(row.get("class", "")),
            "faction": str(row.get("faction_id", "")),
            "location": str(row.get("location", "")),
            "current_goal": str(row.get("current_goal", "")),
            "bt": current_bt if current_bt is Dictionary else {},
            "loyalty": float(row.get("loyalty", 0.0))
        })
        systems[str(row.get("location", ""))] = resolver.system_for_location(str(row.get("location", "")))
    var offers: Array = Executor.offers(sites, ship_rows, class_catalogue, false)
    var assigned: Array = []
    var blocked: Array = []
    var claimed_sites: Dictionary = {}
    for ship_id in ship_ids:
        var ship: Dictionary = world["ships"][ship_id]
        var location: String = str(ship.get("location", ""))
        if not str(ship.get("active_contract_id", "")).is_empty() or not ship.get("transit", {}).is_empty():
            continue
        if str(ship.get("current_goal", "")) not in ["", "idle"]:
            continue
        if not ship.get("cargo", {}).is_empty():
            continue
        var view: Dictionary = {
            "id": str(ship_id), "class": str(ship["class"]),
            "faction": str(ship["faction_id"]), "location": location,
            "loyalty": float(ship.get("loyalty", 0.0))}
        var competing: float = maxf(0.0, float(ship.get("current_goal_score", 0.0)))
        # A physically local construction choice must not be starved
        # by an unimplemented remote N91 travel offer sorted before it.
        var local_offers: Array = offers.filter(func(offer: Dictionary) -> bool:
            return str(offer.get("location", "")) == location)
        var choice: Dictionary = Executor.choose(local_offers, view, systems,
            class_catalogue, competing, false)
        if choice.is_empty():
            continue
        var site_id: String = str(choice.get("site_id", ""))
        var site: Dictionary = world["construction_sites"].get(site_id, {})
        if site.is_empty() or claimed_sites.has(site_id):
            continue
        # Original N91 permits construction elsewhere in the local SYSTEM.
        # Unintegrated N91 GOAP travel is NOT assumed: first admit only
        # ships at the REAL paid site itself. No teleport or fake fuel.
        if location != str(site.get("location_name", "")):
            blocked.append({"ship_id": str(ship_id), "site_id": site_id,
                "reason": "n91_native_route_to_site_not_yet_integrated"})
            continue
        var station_id: String = str(world["markets"][location].get("owner", ""))
        if not world.get("facilities", {}).has(station_id):
            blocked.append({"ship_id": str(ship_id), "site_id": site_id,
                "reason": "n91_missing_real_dock"})
            continue
        var station: Dictionary = world["facilities"][station_id]
        if str(station.get("faction", "")) != str(ship.get("faction_id", "")) or int(station.get("docking_capacity", 0)) < 1:
            blocked.append({"ship_id": str(ship_id), "site_id": site_id,
                "reason": "n91_no_same_faction_dock"})
            continue
        var nodes: Array = [
            Bt.action({"kind": "ConstructionDock", "site_id": site_id}),
            Bt.action({"kind": "Construct", "site_id": site_id})]
        var plan: Dictionary = Bt.sequence(nodes)
        if not Bt.validate(plan):
            return {"ok": false, "reason": "n91_cannot_compile_native_n84_plan"}
        assigned.append({"ship_id": str(ship_id), "site_id": site_id,
            "bt": plan, "score": Executor.utility(float(view["loyalty"])),
            "source": "source_n91_utility_local_engineer"})
        claimed_sites[site_id] = true
        offers = offers.filter(func(offer: Dictionary) -> bool:
            return str(offer.get("site_id", "")) != site_id)
    return {"ok": true, "tick": tick, "assignments": assigned,
        "blocked": blocked, "status": "N91_ENGINEER_SOURCE_PROPOSAL"}
