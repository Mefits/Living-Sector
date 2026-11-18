extends RefCounted
## N84 direct construction dock must match the historical ordered scan.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

static func _oracle(world: Dictionary, contract: Dictionary, location: String) -> Dictionary:
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if not market.is_empty():
        var owner: String = str(market.get("owner", ""))
        if world.get("facilities", {}).has(owner) and str(world["facilities"][owner].get("type", "")) == "station":
            return {"id": owner, "type": "station"}
    if str(contract.get("contract_type", "")) not in ["passenger", "construction"] or str(contract.get("mission_category", "")) != "strategy.colony.v1" or str(contract.get("destination_location", "")) != location:
        return {}
    for site_id in world.get("construction_sites", {}).keys():
        var site: Dictionary = world["construction_sites"][site_id]
        if str(site.get("location_name", "")) != location or str(site.get("faction_id", "")) != str(contract.get("faction_id", "")) or site.get("labor", {}) is not Dictionary or site.get("labor", {}).get("colony_source", null) == null or (str(contract.get("contract_type", "")) == "construction" and str(contract.get("colony_site_id", "")) != str(site_id)):
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
        var site_id: String = "site_" + str(i)
        world["construction_sites"][site_id] = {"location_name": "colony", "faction_id": "f1", "labor": {"colony_source": "paid"}}
    world["construction_receipts"]["n151_colony_dock:site_1999"] = {"kind": "colony_dock_prepared", "facility_id": "dock"}
    world["facilities"]["dock"] = {"type": "construction_dock", "location": "colony", "abandoned": false}
    var contract: Dictionary = {"contract_type": "construction", "mission_category": "strategy.colony.v1", "destination_location": "colony", "faction_id": "f1", "colony_site_id": "site_1999"}
    var before: Dictionary = world.duplicate(true)
    for variant in range(8):
        if variant == 1:
            contract["colony_site_id"] = "missing"
        elif variant == 2:
            contract["colony_site_id"] = "site_1999"
            world["facilities"]["dock"]["abandoned"] = true
        elif variant == 3:
            world["facilities"]["dock"]["abandoned"] = false
            contract["faction_id"] = "wrong"
        elif variant == 4:
            contract["faction_id"] = "f1"
            world["construction_receipts"]["n151_colony_dock:site_1999"]["kind"] = "unpaid"
        elif variant == 5:
            world["construction_receipts"]["n151_colony_dock:site_1999"]["kind"] = "colony_dock_prepared"
            world["markets"]["colony"] = {"owner": "station"}
            world["facilities"]["station"] = {"type": "station", "location": "colony"}
        elif variant == 6:
            world["markets"].clear()
            contract["contract_type"] = "passenger"
        elif variant == 7:
            contract["mission_category"] = "wrong"
        var actual: Dictionary = N84._real_contract_dock(world, contract, "colony")
        var expected: Dictionary = _oracle(world, contract, "colony")
        if actual != expected:
            return {"ok": false, "reason": "oracle_mismatch_" + str(variant), "actual": actual, "expected": expected}
    if before["construction_sites"] != world["construction_sites"]:
        return {"ok": false, "reason": "site_history_mutated"}
    return {"ok": true}
