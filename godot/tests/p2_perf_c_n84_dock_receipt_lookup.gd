extends SceneTree
## N84 DockDwell latest N21 receipt: optimized live-dock projection vs
## independent unfiltered original scan. Run with Godot --headless --script.
const Execution = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

func _oracle(world: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for receipt_id in world.get("dock_receipts", {}):
        var row: Dictionary = world["dock_receipts"][receipt_id]
        if str(row.get("action", "")) != "dock":
            continue
        var ship_id: String = str(row.get("ship_id", ""))
        result[ship_id] = maxi(int(result.get(ship_id, -1)), int(row.get("tick", -1)))
    return result

func _check(condition: bool, reason: String) -> void:
    if not condition:
        push_error(reason)
        quit(1)

func _initialize() -> void:
    var world: Dictionary = {
        "ships": {
            "A": {"id": "A", "docked_at": "station"},
            "B": {"id": "B", "docked_at": "warehouse"},
            "C": {"id": "C", "docked_at": "", "transit": {"token": 5}},
            "D": {"id": "D", "docked_at": ""}
        },
        "dock_receipts": {
            "r1": {"action": "dock", "ship_id": "A", "tick": 10},
            "r2": {"action": "undock", "ship_id": "A", "tick": 100},
            "r3": {"action": "dock", "ship_id": "B", "tick": 12},
            "r4": {"action": "dock", "ship_id": "A", "tick": 30},
            "r5": {"action": "dock", "ship_id": "C", "tick": 40},
            "r6": {"action": "dock", "ship_id": "removed", "tick": 50},
            "r7": {"action": "dock", "ship_id": "B", "tick": -1},
            "r8": {"action": "dock", "ship_id": "A", "tick": 29}
        }
    }
    var original: Dictionary = world.duplicate(true)
    var scratch: Dictionary = {}
    var optimized: Dictionary = Execution._latest_dock_ticks(world, scratch)
    var oracle: Dictionary = _oracle(world)
    _check(optimized.size() == 2, "historical undocked receipts retained")
    for id in ["A", "B"]:
        _check(int(optimized.get(id, -1)) == int(oracle.get(id, -1)),
            "latest receipt differs for docked ship " + id)
    _check(int(optimized["A"]) == 30 and int(optimized["B"]) == 12,
        "N21 max-tick/undock ordering changed")
    _check(world == original, "authoritative World mutated")
    # Within the same proposal the detached index must remain stable.
    world["dock_receipts"]["r9"] = {"action": "dock", "ship_id": "A", "tick": 99}
    _check(Execution._latest_dock_ticks(world, scratch) == optimized,
        "proposal-local cached view was unexpectedly rebuilt")
    # A fresh N84 proposal must invalidate the old index after N21 commit.
    var fresh: Dictionary = Execution._latest_dock_ticks(world, {})
    _check(int(fresh.get("A", -1)) == 99,
        "fresh paid-tick proposal used stale dock receipt")
    # Changing the physical dock roster between proposals also invalidates.
    world["ships"]["A"]["docked_at"] = ""
    world["ships"]["C"]["docked_at"] = "new_station"
    fresh = Execution._latest_dock_ticks(world, {})
    _check(not fresh.has("A") and int(fresh.get("C", -1)) == 40,
        "live dock ownership was not respected")
    # Empty roster: historical receipts must never grant a DockDwell.
    for id in world["ships"]:
        world["ships"][id]["docked_at"] = ""
    _check(Execution._latest_dock_ticks(world, {}).is_empty(),
        "undocked ship received historical dwell proof")
    print("PASS N84 dock receipt live projection / N21 oracle / invalidation")
    quit()
