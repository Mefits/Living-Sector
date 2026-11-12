extends SceneTree
const Ships = preload("res://scripts/sim/ship_state.gd")
const Gate = preload("res://scripts/sim/ships/docked_cargo_gate.gd")
## Registry fixture has exactly the N21 public dictionary shape.
class DockFixture:
	extends RefCounted
	var ships: Dictionary = {}
	var facilities: Dictionary = {}
	var occupants: Dictionary = {}

func _initialize() -> void:
	var ships := Ships.new()
	assert(ships.add_ship("freight-1", "freighter", "faction-1", "system-1"))
	ships.ships["freight-1"]["location"] = "station-1"
	var dock := DockFixture.new()
	dock.facilities["bay-1"] = {"location": "station-1", "capacity": 2, "type": "station"}
	dock.ships["freight-1"] = {"location": "station-1", "in_transit": false, "docked_at": ""}
	dock.occupants["bay-1"] = []
	var gate := Gate.new()
	assert(gate.configure(dock, ships))
	var warehouse := {"ore": 600.0}
	assert(gate.register_warehouse("bay-1", warehouse))
	assert(not gate.transfer("freight-1", "bay-1", {"ore": 50}, "t0", "load", 1)["ok"])
	dock.ships["freight-1"]["docked_at"] = "bay-1"
	dock.occupants["bay-1"].append("freight-1")
	assert(gate.transfer("freight-1", "bay-1", {"ore": 100}, "t1", "load", 2)["ok"])
	assert(warehouse["ore"] == 500.0 and ships.cargo_used("freight-1") == 100)
	assert(not gate.transfer("freight-1", "bay-1", {"ore": 100}, "t1", "load", 3)["ok"])
	assert(warehouse["ore"] == 500.0)
	dock.ships["freight-1"]["in_transit"] = true
	assert(not gate.transfer("freight-1", "bay-1", {"ore": 10}, "t2", "unload", 4)["ok"])
	dock.ships["freight-1"]["in_transit"] = false
	dock.occupants["bay-1"].clear()
	assert(not gate.transfer("freight-1", "bay-1", {"ore": 10}, "t3", "unload", 4)["ok"])
	dock.occupants["bay-1"].append("freight-1")
	assert(gate.transfer("freight-1", "bay-1", {"ore": 40}, "t4", "unload", 5)["ok"])
	assert(warehouse["ore"] == 540.0 and ships.cargo_used("freight-1") == 60)
	var saved := gate.snapshot()
	var restored := Gate.new()
	assert(restored.configure(dock, ships))
	assert(restored.register_warehouse("bay-1", warehouse))
	assert(restored.restore(saved))
	assert(not restored.transfer("freight-1", "bay-1", {"ore": 1}, "t4", "load", 6)["ok"])
	assert(warehouse["ore"] + ships.cargo_used("freight-1") == 600.0)
	print("N29_DOCKED_CARGO_OK")
	quit(0)
