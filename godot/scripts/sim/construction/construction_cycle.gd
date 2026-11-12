extends RefCounted
## N17: native ConstructionSite material delivery + paid local labor.
## Rust: agents/construction.rs, construction/labor.rs, facility/workforce.rs.
## Self-contained domain slice. Caller owns physical cargo, wallets and worker
## reservations; no SceneTree Nodes and no facility is spawned by an intent.

const DEFAULT_MATERIALS: int = 600
const DEFAULT_LABOR: int = 150
const MAX_SHIFT_WORKERS: int = 10
const WAGE_PER_WORKER: int = 1
const MAX_SAFE_CREDITS: int = 9000000000000000

var sites: Dictionary = {}
var facilities: Dictionary = {}
var receipts: Dictionary = {}

func create_site(id: String, faction: String, location: String, body: String, commodity: String, facility_type: String, required: int = DEFAULT_MATERIALS, labor_required: int = DEFAULT_LABOR) -> bool:
    if id.is_empty() or faction.is_empty() or location.is_empty() or body.is_empty() or commodity.is_empty() or facility_type.is_empty():
        return false
    if required <= 0 or labor_required <= 0 or sites.has(id) or facilities.has(id):
        return false
    for existing in sites.values():
        if not bool(existing.get("completed", false)) and existing.get("location") == location and existing.get("commodity") == commodity:
            return false # Rust site_exists_for: no duplicate demand for commodity/location
    sites[id] = {"id": id, "faction": faction, "location": location, "body": body,
        "commodity": commodity, "facility_type": facility_type,
        "required": required, "delivered": 0, "labor_required": labor_required,
        "labor_completed": 0, "last_shift_tick": -1, "last_executor": "",
        "completed": false, "blocked_reason": ""}
    return true

func remaining(id: String) -> int:
    if not sites.has(id):
        return -1
    var site: Dictionary = sites[id]
    return maxi(0, int(site["required"]) - int(site["delivered"]))

## A verified physical delivery receipt consumes cargo at the same location.
## Caller must supply the actual ship inventory dictionary, not an estimated supply.
## Exact receipt IDs survive save/load; failures do not debit cargo.
func deliver(id: String, receipt_id: String, ship: Dictionary, quantity: int) -> String:
    if not sites.has(id):
        return "missing_site"
    if receipt_id.is_empty():
        return "invalid_receipt"
    if receipts.has(receipt_id):
        return "duplicate_receipt"
    var site: Dictionary = sites[id]
    if bool(site["completed"]):
        return "completed_site"
    if quantity <= 0 or quantity > remaining(id):
        return "invalid_quantity"
    if ship.get("faction") != site["faction"] or ship.get("location") != site["location"] or bool(ship.get("in_transit", true)):
        return "ship_not_present"
    var cargo: Dictionary = ship.get("cargo", {})
    var commodity: String = site["commodity"]
    if int(cargo.get(commodity, 0)) < quantity:
        return "insufficient_cargo"
    cargo[commodity] = int(cargo[commodity]) - quantity
    ship["cargo"] = cargo
    site["delivered"] = int(site["delivered"]) + quantity
    site["blocked_reason"] = ""
    receipts[receipt_id] = {"site": id, "commodity": commodity, "quantity": quantity, "kind": "delivery"}
    return "ok"

## Native labor: max 10 per shift, available workers = floor(pop * 3/5)
## minus existing paid reservations at this tick. Faction pays households.
## 'executor' is a caller-verified active, docked engineering ship.
func work(id: String, tick: int, executor: Dictionary, sponsor: Dictionary, households: Array, occupied: Dictionary) -> String:
    if not sites.has(id):
        return "missing_site"
    var site: Dictionary = sites[id]
    if bool(site["completed"]):
        return _block(site, "completed_site")
    if remaining(id) != 0:
        return _block(site, "awaiting_materials")
    if tick < 0 or tick <= int(site["last_shift_tick"]):
        return "already_worked_this_tick"
    if executor.get("faction") != site["faction"] or executor.get("location") != site["location"] or not bool(executor.get("docked", false)) or bool(executor.get("in_transit", true)) or not bool(executor.get("engineer", false)) or executor.get("active_site") != id:
        return _block(site, "awaiting_construction_ship")
    if sponsor.get("faction") != site["faction"]:
        return _block(site, "missing_sponsor")
    var treasury: int = int(sponsor.get("credits", -1))
    if treasury < WAGE_PER_WORKER:
        return _block(site, "insufficient_labor_budget")
    var needed: int = mini(MAX_SHIFT_WORKERS, int(site["labor_required"]) - int(site["labor_completed"]))
    if needed <= 0:
        return "labor_complete"
    var available_budget: int = mini(needed, treasury / WAGE_PER_WORKER)
    var assignments: Array = []
    var ids: Dictionary = {}
    for household in households:
        if not household is Dictionary:
            return _block(site, "invalid_household")
        var hid: String = str(household.get("id", ""))
        if hid.is_empty() or ids.has(hid):
            return _block(site, "invalid_household")
        ids[hid] = true
        if household.get("faction") != site["faction"] or household.get("location") != site["location"]:
            continue
        var population: int = int(household.get("population", 0))
        var wealth: int = int(household.get("credits", -1))
        if population < 0 or wealth < 0:
            return _block(site, "invalid_household_balance")
        var count: int = mini(available_budget, maxi(0, population * 3 / 5 - int(occupied.get(hid, 0))))
        if count <= 0:
            continue
        if wealth > MAX_SAFE_CREDITS - count * WAGE_PER_WORKER:
            return _block(site, "household_credit_overflow")
        assignments.append({"household": household, "id": hid, "count": count})
        available_budget -= count
        if available_budget == 0:
            break
    var workers: int = 0
    for assignment in assignments:
        workers += int(assignment["count"])
    if workers == 0:
        return _block(site, "insufficient_workers")
    var wages: int = workers * WAGE_PER_WORKER
    sponsor["credits"] = treasury - wages
    for assignment in assignments:
        var household: Dictionary = assignment["household"]
        var count: int = int(assignment["count"])
        household["credits"] = int(household["credits"]) + count * WAGE_PER_WORKER
        occupied[assignment["id"]] = int(occupied.get(assignment["id"], 0)) + count
    site["labor_completed"] = int(site["labor_completed"]) + workers
    site["last_shift_tick"] = tick
    site["last_executor"] = str(executor.get("id", ""))
    site["blocked_reason"] = ""
    receipts["shift:%s:%d" % [id, tick]] = {"kind": "labor", "site": id, "tick": tick, "workers": workers, "wages": wages}
    return "ok"

## Materialization is a separate checkpoint operation, never an implied spawn.
func materialize(id: String) -> String:
    if not sites.has(id):
        return "missing_site"
    var site: Dictionary = sites[id]
    if bool(site["completed"]):
        return "completed_site"
    if remaining(id) != 0 or int(site["labor_completed"]) < int(site["labor_required"]):
        return _block(site, "requirements_incomplete")
    if facilities.has(id):
        return _block(site, "facility_id_conflict")
    facilities[id] = {"id": id, "faction": site["faction"], "location": site["location"],
        "body": site["body"], "facility_type": site["facility_type"], "source_site": id}
    site["completed"] = true
    site["blocked_reason"] = ""
    receipts["completion:%s" % id] = {"kind": "completion", "site": id}
    return "ok"

func _block(site: Dictionary, reason: String) -> String:
    site["blocked_reason"] = reason
    return reason

func snapshot() -> Dictionary:
    return {"version": 1, "sites": sites.duplicate(true), "facilities": facilities.duplicate(true), "receipts": receipts.duplicate(true)}

func restore(state: Dictionary) -> bool:
    if state.get("version") != 1 or not state.get("sites") is Dictionary or not state.get("facilities") is Dictionary or not state.get("receipts") is Dictionary:
        return false
    var restored_sites: Dictionary = state["sites"]
    var restored_facilities: Dictionary = state["facilities"]
    var restored_receipts: Dictionary = state["receipts"]
    for id in restored_sites:
        var site: Variant = restored_sites[id]
        if not site is Dictionary or site.get("id") != id:
            return false
        if int(site.get("required", 0)) <= 0 or int(site.get("labor_required", 0)) <= 0:
            return false
        if int(site.get("delivered", -1)) < 0 or int(site.get("delivered", -1)) > int(site["required"]):
            return false
        if int(site.get("labor_completed", -1)) < 0 or int(site.get("labor_completed", -1)) > int(site["labor_required"]):
            return false
        if bool(site.get("completed", false)) and (not restored_facilities.has(id) or int(site["delivered"]) != int(site["required"]) or int(site["labor_completed"]) != int(site["labor_required"])):
            return false
    sites = restored_sites.duplicate(true)
    facilities = restored_facilities.duplicate(true)
    receipts = restored_receipts.duplicate(true)
    return true
