extends RefCounted
## C N84 passenger dock: original ordered full-site scan vs call-local roster.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

static func _legacy(world: Dictionary, contract: Dictionary, location: String) -> Dictionary:
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if not market.is_empty():
        var owner: String = str(market.get("owner", ""))
        if world.get("facilities", {}).has(owner) and str(world["facilities"][owner].get("type", "")) == "station":
            return {"id": owner, "type": "station"}
    if str(contract.get("contract_type", "")) not in ["passenger", "construction"] or str(contract.get("mission_category", "")) != "strategy.colony.v1" or str(contract.get("destination_location", "")) != location:
        return {}
    var ids: Array = world.get("construction_sites", {}).keys()
    if str(contract.get("contract_type", "")) == "construction":
        var site: String = str(contract.get("colony_site_id", ""))
        if not world.get("construction_sites", {}).has(site):
            return {}
        ids = [site]
    for id in ids:
        var row: Dictionary = world["construction_sites"][id]
        if str(row.get("location_name", "")) != location or str(row.get("faction_id", "")) != str(contract.get("faction_id", "")) or row.get("labor", {}) is not Dictionary or row.get("labor", {}).get("colony_source", null) == null or (str(contract.get("contract_type", "")) == "construction" and str(contract.get("colony_site_id", "")) != str(id)):
            continue
        var proof: Dictionary = world.get("construction_receipts", {}).get("n151_colony_dock:" + str(id), {})
        var fid: String = str(proof.get("facility_id", ""))
        var fac: Dictionary = world.get("facilities", {}).get(fid, {})
        if str(proof.get("kind", "")) == "colony_dock_prepared" and str(fac.get("type", "")) == "construction_dock" and str(fac.get("location", "")) == location and not bool(fac.get("abandoned", false)):
            return {"id": fid, "type": "construction_dock"}
    return {}

static func _equal(world: Dictionary, contract: Dictionary, location: String, scratch: Dictionary) -> bool:
    return N84._real_contract_dock(world, contract, location, scratch) == _legacy(world, contract, location)

static func run() -> Dictionary:
    var world: Dictionary = {"markets": {}, "facilities": {},
        "construction_sites": {}, "construction_receipts": {}}
    for i in range(2000):
        world["construction_sites"]["site_%04d" % i] = {
            "location_name": "L%d" % (i % 25),
            "faction_id": "f%d" % (i % 4),
            "labor": {"colony_source": "origin"}}
    var target: String = "site_0100"
    var alternative: String = "site_0200"
    for id in [target, alternative]:
        world["construction_sites"][id]["location_name"] = "A"
        world["construction_sites"][id]["faction_id"] = "F"
        world["construction_receipts"]["n151_colony_dock:" + id] = {
            "kind": "colony_dock_prepared", "facility_id": "dock_" + id}
        world["facilities"]["dock_" + id] = {
            "type": "construction_dock", "location": "A", "abandoned": false}
    var passenger: Dictionary = {"contract_type": "passenger",
        "mission_category": "strategy.colony.v1",
        "destination_location": "A", "faction_id": "F"}
    var scratch: Dictionary = {}
    var original: Dictionary = world.duplicate(true)
    for i in range(40):
        if not _equal(world, passenger, "A", scratch):
            return {"ok": false, "reason": "ordered_passenger_oracle"}
    if world != original:
        return {"ok": false, "reason": "world_alias_mutation"}
    # Receipt/facility validity must be read LIVE even when roster is cached.
    world["facilities"]["dock_" + target]["abandoned"] = true
    if not _equal(world, passenger, "A", scratch):
        return {"ok": false, "reason": "stale_abandoned_dock"}
    world["construction_receipts"]["n151_colony_dock:" + alternative]["kind"] = "invalid"
    if not _equal(world, passenger, "A", scratch):
        return {"ok": false, "reason": "stale_paid_dock_receipt"}
    world["construction_sites"][target]["labor"] = {}
    if not _equal(world, passenger, "A", scratch):
        return {"ok": false, "reason": "stale_labor"}
    # New proposal must rebuild after changed ownership/location.
    world["construction_sites"][target]["faction_id"] = "OTHER"
    if not _equal(world, passenger, "A", {}):
        return {"ok": false, "reason": "ownership_invalidation"}
    var construction: Dictionary = passenger.duplicate()
    construction["contract_type"] = "construction"
    construction["colony_site_id"] = alternative
    if not _equal(world, construction, "A", scratch):
        return {"ok": false, "reason": "direct_construction_oracle"}
    world["facilities"]["station"] = {"type": "station", "location": "A"}
    world["markets"]["A"] = {"owner": "station"}
    if not _equal(world, passenger, "A", scratch):
        return {"ok": false, "reason": "station_market_priority"}
    return {"ok": true}
