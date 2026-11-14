extends RefCounted
## B3 N38 historical proof after Rust engine/colony.rs::establish
## despawns the original ConstructionSite. Read-only. The original
## N39 World is sole authority; no per-colony shadow state exists.
const CAPITAL: int = 20000
const METALS: int = 600
const LABOR: int = 150

static func validate_archived(world: Dictionary, id: String) -> String:
    if id.is_empty() or world.get("construction_sites", {}).has(id):
        return "b3_historical_colony_site_not_despawned"
    var receipts: Dictionary = world.get("construction_receipts", {})
    var proof_id: String = "n151_colony_dock:" + id
    var completion_id: String = "n151_colony_established:" + id
    var original: Dictionary = receipts.get(proof_id, {})
    var completed: Dictionary = receipts.get(completion_id, {})
    if original.is_empty() or completed.is_empty() or (
            str(original.get("kind", "")) != "colony_dock_prepared" or
            str(completed.get("kind", "")) != "colony_established" or
            str(original.get("id", "")) != proof_id or
            str(completed.get("id", "")) != completion_id or
            str(original.get("site_id", "")) != id or
            str(completed.get("site_id", "")) != id):
        return "b3_missing_original_completion_evidence"
    var fid: String = str(original.get("facility_id", ""))
    var pid: String = str(original.get("population_id", ""))
    var location: String = str(original.get("destination_location", ""))
    var faction: String = str(original.get("faction_id", ""))
    var body: String = str(original.get("body_id", ""))
    var fac: Dictionary = world.get("facilities", {}).get(fid, {})
    var home: Dictionary = world.get("populations", {}).get(pid, {})
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if fid.is_empty() or pid.is_empty() or location != body + "-colony" or (
            fac.is_empty() or home.is_empty() or market.is_empty() or
            str(fac.get("type", "")) != "station" or
            str(fac.get("location", "")) != location or
            str(fac.get("faction", "")) != faction or
            str(fac.get("body_id", "")) != body or
            str(fac.get("construction_source_site_id", "")) != id or
            str(home.get("colony_dock_id", "")) != fid or
            str(home.get("construction_source_site_id", "")) != id or
            str(home.get("faction", "")) != faction or
            str(home.get("location", "")) != location or
            str(market.get("owner", "")) != fid or
            str(market.get("id", "")) != "market-" + location or
            not (fac.get("services", []) is Array) or
            not (fac.get("services", []) as Array).has("market")):
        return "b3_finished_colony_not_original_dock_or_market"
    if str(completed.get("facility_id", "")) != fid or (
            str(completed.get("population_id", "")) != pid or
            str(completed.get("market_id", "")) != str(market["id"]) or
            str(completed.get("destination_location", "")) != location or
            str(completed.get("faction_id", "")) != faction or
            str(completed.get("body_id", "")) != body or
            int(completed.get("native_db_id", 0)) != int(original.get("native_db_id", 1)) or
            int(fac.get("native_db_id", 0)) != int(original.get("native_db_id", 1)) or
            int(home.get("native_db_id", 0)) != int(original.get("native_db_id", 1)) or
            int(completed.get("capital", -1)) != CAPITAL or
            int(completed.get("delivered_metals", -1)) != METALS or
            int(completed.get("paid_labor", -1)) != LABOR or
            int(completed.get("shipments", -1)) < 3 or
            int(completed.get("shifts", -1)) < 1 or
            int(completed.get("tick", -1)) < int(original.get("tick", 0)) or
            str(completed.get("n9_receipt_id", "")) !=
                "native_colony_establish:" + id + ":" + str(completed.get("tick", -1))):
        return "b3_forged_archived_colony_completion"
    # A historical N104 contract remains in the main Board but its
    # temporary N154 material-order index must be deleted, not replayed.
    for cid in world.get("construction_contracts", {}):
        if str(world["construction_contracts"][cid]) == id:
            return "b3_resurrected_completed_construction_order"
    var sums_goods: int = 0
    var sums_wages: int = 0
    var count_shipments: int = 0
    var count_shifts: int = 0
    for key in receipts:
        var r: Dictionary = receipts[key]
        if str(r.get("site_id", "")) != id:
            continue
        if str(r.get("kind", "")) == "delivery":
            var cid: String = str(r.get("contract_id", ""))
            var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
            var cargo_id: String = str(r.get("n15_receipt_id", ""))
            var unload: Dictionary = world.get("cargo_receipts", {}).get(cargo_id, {})
            var qty: int = int(r.get("quantity", 0))
            if qty < 1 or qty > 200 or str(c.get("status", "")) != "paid" or (
                    str(c.get("colony_site_id", "")) != id or
                    str(c.get("contract_type", "")) != "construction" or
                    str(c.get("mission_category", "")) != "strategy.colony.v1" or
                    str(unload.get("kind", "")) != "construction_site" or
                    str(unload.get("site_id", "")) != id or
                    str(unload.get("action", "")) != "unload" or
                    str(unload.get("location_id", "")) != location or
                    unload.get("quantities", {}) != {"metals": qty}):
                return "b3_archived_construction_missing_paid_physical_receipt"
            sums_goods += qty
            count_shipments += 1
        elif str(r.get("kind", "")) == "labor":
            var amount: int = int(r.get("wages", -1))
            if amount <= 0 or str(r.get("n9_receipt_id", "")) != str(key):
                return "b3_archived_n141_wage_history_missing"
            sums_wages += amount
            count_shifts += 1
    if sums_goods != METALS or sums_wages != LABOR or (
            count_shipments != int(completed.get("shipments", -1)) or
            count_shifts != int(completed.get("shifts", -1))):
        return "b3_original_600_150_history_not_conserved"
    return ""

static func validate_all(world: Dictionary) -> String:
    var receipts: Dictionary = world.get("construction_receipts", {})
    var completed_sites: Dictionary = {}
    for rid in receipts:
        var r: Dictionary = receipts[rid]
        if str(r.get("kind", "")) != "colony_established":
            continue
        var id: String = str(r.get("site_id", ""))
        if id.is_empty() or completed_sites.has(id) or (
                str(rid) != "n151_colony_established:" + id):
            return "b3_duplicate_or_invalid_historical_completion"
        completed_sites[id] = true
        var err: String = validate_archived(world, id)
        if not err.is_empty():
            return err
    for rid in receipts:
        var r: Dictionary = receipts[rid]
        if str(r.get("kind", "")) != "colony_dock_prepared":
            continue
        var site_id: String = str(r.get("site_id", ""))
        if not world.get("construction_sites", {}).has(site_id) and (
                not completed_sites.has(site_id)):
            return "b3_temporary_colony_dock_vanished_without_establish"
    return ""
