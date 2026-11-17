extends RefCounted
## Independent legacy full-scan oracle for the real N84 colony-dock leaf.
const AI = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

static func _legacy(world: Dictionary, contract: Dictionary, location: String) -> Dictionary:
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if not market.is_empty():
        var owner: String = str(market.get("owner", ""))
        if world.get("facilities", {}).has(owner) and str(world["facilities"][owner].get("type", "")) == "station":
            return {"id": owner, "type": "station"}
    if str(contract.get("contract_type", "")) not in ["passenger", "construction"] or str(contract.get("mission_category", "")) != "strategy.colony.v1" or str(contract.get("destination_location", "")) != location:
        return {}
    for site_id in world.get("construction_sites", {}):
        var site: Dictionary = world["construction_sites"][site_id]
        if str(site.get("location_name", "")) != location or str(site.get("faction_id", "")) != str(contract.get("faction_id", "")) or not (site.get("labor", {}) is Dictionary) or site.get("labor", {}).get("colony_source", null) == null or (str(contract.get("contract_type", "")) == "construction" and str(contract.get("colony_site_id", "")) != str(site_id)):
            continue
        var proof: Dictionary = world.get("construction_receipts", {}).get("n151_colony_dock:" + str(site_id), {})
        var fid: String = str(proof.get("facility_id", ""))
        var fac: Dictionary = world.get("facilities", {}).get(fid, {})
        if str(proof.get("kind", "")) == "colony_dock_prepared" and str(fac.get("type", "")) == "construction_dock" and str(fac.get("location", "")) == location and not bool(fac.get("abandoned", false)):
            return {"id": fid, "type": "construction_dock"}
    return {}

static func run() -> Dictionary:
    var world: Dictionary = {"markets": {}, "facilities": {}, "construction_sites": {}, "construction_receipts": {}}
    for i in range(2000):
        var sid: String = "site_%04d" % i
        var fid: String = "dock_%04d" % i
        world["construction_sites"][sid] = {"location_name": "colony", "faction_id": "alpha", "labor": {"colony_source": "real"}}
        world["construction_receipts"]["n151_colony_dock:" + sid] = {"kind": "colony_dock_prepared", "facility_id": fid}
        world["facilities"][fid] = {"type": "construction_dock", "location": "colony", "abandoned": false}
    var c: Dictionary = {"contract_type": "construction", "mission_category": "strategy.colony.v1", "destination_location": "colony", "faction_id": "alpha", "colony_site_id": "site_1999", "status": "picked_up", "payment": 400, "reserved": 400}
    var before: Dictionary = world.duplicate(true)
    for scenario in range(8):
        var original: Dictionary = _legacy(world, c, "colony")
        var optimized: Dictionary = AI._real_contract_dock(world, c, "colony")
        if original != optimized:
            return {"ok": false, "reason": "oracle_mismatch_" + str(scenario)}
        if world != before:
            return {"ok": false, "reason": "mutated_paid_world"}
        match scenario:
            0:
                world["construction_receipts"]["n151_colony_dock:site_1999"]["kind"] = "unpaid"
            1:
                world["construction_receipts"]["n151_colony_dock:site_1999"]["kind"] = "colony_dock_prepared"
                world["facilities"]["dock_1999"]["abandoned"] = true
            2:
                world["facilities"]["dock_1999"]["abandoned"] = false
                c["colony_site_id"] = "site_missing"
            3:
                c["colony_site_id"] = "site_1999"
                c["faction_id"] = "other"
            4:
                c["faction_id"] = "alpha"
                world["construction_sites"]["site_1999"]["location_name"] = "elsewhere"
            5:
                world["construction_sites"]["site_1999"]["location_name"] = "colony"
                c["contract_type"] = "passenger"
            6:
                c["contract_type"] = "construction"
                world["markets"]["colony"] = {"owner": "station"}
                world["facilities"]["station"] = {"type": "station", "location": "colony"}
        before = world.duplicate(true)
    return {"ok": true}
