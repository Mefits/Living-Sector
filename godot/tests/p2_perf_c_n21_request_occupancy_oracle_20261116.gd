extends RefCounted
## Negative oracle for the request-local occupied-dock tally.
## Run with the existing Godot test harness; no fixture mutates World.

static func _naive(world: Dictionary, fid: String) -> int:
    var count: int = 0
    for ship in world.get("ships", {}).values():
        if str(ship.get("docked_at", "")) == fid:
            count += 1
    return count

static func _indexed(world: Dictionary) -> Dictionary:
    var occupancy: Dictionary = {}
    for ship in world["ships"].values():
        var dock_id: String = str(ship.get("docked_at", ""))
        if not dock_id.is_empty():
            occupancy[dock_id] = int(occupancy.get(dock_id, 0)) + 1
    return occupancy

static func run() -> Dictionary:
    var world: Dictionary = {"ships": {}}
    var docks: Array = ["alpha", "beta", "gamma", "stale"]
    for i in range(2000):
        var fid: String = docks[i % docks.size()]
        if i % 9 == 0:
            fid = ""
        world["ships"]["ship_%04d" % i] = {
            "docked_at": fid, "credits": 1000 + i,
            "cargo": {"ore": i % 7}}
    var baseline: Dictionary = world.duplicate(true)
    var indexed: Dictionary = _indexed(world)
    for fid in docks + ["missing", ""]:
        var cached: int = int(indexed.get(fid, 0))
        var oracle: int = _naive(world, fid) if not fid.is_empty() else 0
        if cached != oracle:
            return {"ok": false, "reason": "occupancy_parity_" + fid}
        for cap in [0, 1, 7, 500, 3000]:
            if (cached >= cap) != (oracle >= cap):
                return {"ok": false, "reason": "capacity_parity_" + fid}
            var cached_fee: int = roundi(50.0 * (1.0 + float(cached) / float(maxi(cap, 1))))
            var oracle_fee: int = roundi(50.0 * (1.0 + float(oracle) / float(maxi(cap, 1))))
            if cached_fee != oracle_fee:
                return {"ok": false, "reason": "fee_parity_" + fid}
    if world != baseline:
        return {"ok": false, "reason": "mutable_world_alias"}
    # Negative: a new request must rebuild occupancy after an intervening dock.
    world["ships"]["ship_0000"]["docked_at"] = "beta"
    var refreshed: Dictionary = _indexed(world)
    if int(refreshed.get("beta", 0)) != _naive(world, "beta"):
        return {"ok": false, "reason": "stale_occupancy"}
    if int(indexed.get("beta", 0)) == int(refreshed.get("beta", 0)):
        return {"ok": false, "reason": "not_invocation_local"}
    return {"ok": true}
