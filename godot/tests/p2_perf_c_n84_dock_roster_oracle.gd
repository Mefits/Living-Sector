extends SceneTree
## N84 paid-tick dock observation oracle. Run with Godot --headless -s.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

func _oracle_ticks(world: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for receipt in world.get("dock_receipts", {}).values():
        if str(receipt.get("action", "")) != "dock":
            continue
        var sid: String = str(receipt.get("ship_id", ""))
        result[sid] = maxi(int(result.get(sid, -1)),
            int(receipt.get("tick", -1)))
    return result

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("N84 dock oracle: " + message)
    return condition

func _initialize() -> void:
    var ok: bool = true
    var receipts: Dictionary = {}
    for i in range(2000):
        receipts["receipt_%04d" % i] = {
            "action": "dock" if i % 3 != 0 else "undock",
            "ship_id": "ship_%03d" % (i % 70),
            "tick": i / 2
        }
    receipts["collision"] = {"action": "dock", "ship_id": "_ready", "tick": 7777}
    receipts["gate_collision"] = {"action": "dock",
        "ship_id": "_n84_gate_roster", "tick": 8888}
    receipts["negative"] = {"action": "dock", "ship_id": "negative", "tick": -1}
    var world: Dictionary = {"dock_receipts": receipts}
    var scratch: Dictionary = {"_ready": true, "_n84_gate_roster": {"x": []}}
    var oracle: Dictionary = _oracle_ticks(world)
    for n in range(40):
        var indexed: Dictionary = N84._latest_dock_ticks(world, scratch)
        ok = _check(indexed == oracle, "cached latest receipt differs from legacy") and ok
        ok = _check(int(indexed.get("_ready", -1)) == 7777,
            "real ship ID collided with scratch sentinel") and ok
        ok = _check(int(indexed.get("_n84_gate_roster", -1)) == 8888,
            "real ship ID collided with gate scratch") and ok
    ok = _check(not scratch.has("ship_001"),
        "index leaked ship IDs into shared scratch") and ok
    # A new paid proposal must see newly appended receipts.
    receipts["newer"] = {"action": "dock", "ship_id": "_ready", "tick": 9999}
    ok = _check(N84._latest_dock_ticks(world, {}) == _oracle_ticks(world),
        "new proposal failed to invalidate receipt index") and ok
    ok = _check(int(N84._latest_dock_ticks(world, {}).get("missing", -1)) == -1,
        "missing dock time should remain unverified") and ok

    var facility: Dictionary = {"type": "station", "location": "Earth"}
    var dock_world: Dictionary = {
        "markets": {"Earth": {"owner": "station_A"}},
        "facilities": {"station_A": facility},
        "construction_sites": {}, "construction_receipts": {}
    }
    var contract: Dictionary = {"contract_type": "passenger",
        "mission_category": "strategy.colony.v1",
        "destination_location": "Earth", "faction_id": "f"}
    var station_scratch: Dictionary = {}
    var first: Dictionary = N84._real_contract_dock(dock_world, contract,
        "Earth", station_scratch)
    ok = _check(first == {"id": "station_A", "type": "station"},
        "station priority changed") and ok
    dock_world["facilities"]["station_A"]["type"] = "shipyard"
    ok = _check(N84._real_contract_dock(dock_world, contract,
        "Earth", station_scratch).is_empty(),
        "stale cached candidate bypassed live facility validation") and ok
    dock_world["markets"]["Earth"]["owner"] = "station_B"
    dock_world["facilities"]["station_B"] = {"type": "station", "location": "Earth"}
    ok = _check(N84._real_contract_dock(dock_world, contract,
        "Earth", {}).get("id", "") == "station_B",
        "new proposal did not see changed market owner") and ok
    quit(0 if ok else 1)
