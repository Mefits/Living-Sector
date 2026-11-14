extends RefCounted
## N91 source construction-executor selection over ONE existing N39 World.
## A site must have REAL paid N104/N15 material delivery before any ship
## is reserved. No contractor ship or labor is fabricated by this selector.
const Executor = preload("res://scripts/ported/n91_construction_executor.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")

## Frozen 24-ship seed lacks per-ship Personality RNG. The same source
## class fallback as N153 is used, never a fabricated max loyalty value.
static func _loyalty(ship: Dictionary) -> float:
    var native: Dictionary = ship.get("personality", {})
    if not Personality.validate(native):
        native = Personality.for_class(str(ship.get("class", "")))
    return float(native.get("loyalty", 0.0))

static func _station_order(site: Dictionary) -> Dictionary:
    var order: Variant = site.get("labor", {}).get("station_order", null)
    return order if order is Dictionary else {}

## A fully funded N154 site is proved by physical N15 unload
## receipts + final paid N104 receipts, not an untrusted progress count.
## Refuse a hand-edited save that claims 600/600 materials without cargo.
static func physical_site_funded(world: Dictionary, money: Dictionary,
        site_id: String) -> bool:
    var site: Dictionary = world.get("construction_sites", {}).get(site_id, {})
    if site.is_empty() or not (money.get("receipts") is Dictionary):
        return false
    var delivered: int = 0
    var seen: Dictionary = {}
    for id in world.get("construction_receipts", {}):
        var row: Dictionary = world["construction_receipts"][id]
        if str(row.get("kind", "")) != "delivery" or str(row.get("site_id", "")) != site_id:
            continue
        var cargo_id: String = str(row.get("n15_receipt_id", ""))
        var money_id: String = str(row.get("n9_receipt_id", ""))
        var contract_id: String = str(row.get("contract_id", ""))
        var qty: int = int(row.get("quantity", 0))
        if qty <= 0 or seen.has(cargo_id) or cargo_id.is_empty() or money_id.is_empty():
            return false
        var cargo: Dictionary = world.get("cargo_receipts", {}).get(cargo_id, {})
        var contract: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(contract_id, {})
        if cargo.is_empty() or contract.is_empty() or not money["receipts"].has(money_id):
            return false
        if str(cargo.get("action", "")) != "unload" or str(cargo.get("location_id", "")) != str(site.get("location_name", "")):
            return false
        if int(cargo.get("quantities", {}).get(str(site.get("commodity", "")), -1)) != qty:
            return false
        if str(contract.get("status", "")) != "paid" or str(contract.get("commodity", "")) != str(site.get("commodity", "")):
            return false
        if str(contract.get("destination_location", "")) != str(site.get("location_name", "")) or int(contract.get("quantity", -1)) != qty:
            return false
        seen[cargo_id] = true
        delivered += qty
        if delivered > int(site.get("progress_required", 0)):
            return false
    return delivered == int(site.get("progress_delivered", -1))

static func propose(world: Dictionary, resolver: RefCounted,
        tick: int, money: Dictionary) -> Dictionary:
    if tick < 1 or resolver == null or not (world.get("construction_sites") is Dictionary) or not (world.get("ships") is Dictionary):
        return {"ok": false, "reason": "missing_real_n91_world"}
    var sites: Array = []
    var site_ids: Array = world["construction_sites"].keys()
    site_ids.sort()
    for id in site_ids:
        var site: Dictionary = world["construction_sites"][id]
        if not world.get("markets", {}).has(str(site.get("location_name", ""))):
            return {"ok": false, "reason": "n91_site_without_real_market"}
        if not physical_site_funded(world, money, str(id)):
            # N154 site may still be waiting for paid material; omit from
            # N91 offers rather than invent an engineer job.
            continue
        sites.append({
            "id": str(id), "completed": bool(site.get("completed", false)),
            "remaining_material": maxi(0, int(site.get("progress_required", 0)) -
                int(site.get("progress_delivered", 0))),
            "labor_completed": int(site.get("labor", {}).get("completed", 0)),
            "labor_required": int(site.get("labor", {}).get("required", 0)),
            # Source N154 has station_order=null until it is assigned.
            # Port N91.offers expects an object; represent NONE with {}.
            "station_order": _station_order(site),
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
            "loyalty": _loyalty(row)
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
            "loyalty": _loyalty(ship)}
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
