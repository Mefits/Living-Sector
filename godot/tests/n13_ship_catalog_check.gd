extends SceneTree
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const State = preload("res://scripts/sim/ship_state.gd")

func _initialize() -> void:
	var ok := run_checks()
	print("N13 ship catalog: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func run_checks() -> bool:
	if not Catalog.validate_catalog():
		return false
	var expected := {"colonizer": [500, 250.0, 6, "medium"], "courier": [50, 80.0, 2, "small"], "freighter": [500, 100.0, 5, "medium"], "hauler": [2000, 200.0, 8, "huge"], "tanker": [1500, 300.0, 6, "large"], "miner": [200, 120.0, 3, "small"]}
	for key in expected:
		var spec := Catalog.spec(key)
		var row: Array = expected[key]
		if int(spec["cargo_capacity"]) != row[0] or float(spec["fuel_capacity"]) != row[1] or (spec["crew_roles"] as Array).size() != row[2] or spec["default_size"] != row[3]:
			return false
	if Catalog.size_tier("massive") != 6 or Catalog.size_tier("giant") != 0:
		return false
	if absf(Catalog.effective_speed("hauler") - 0.48) > 0.00001:
		return false
	var state = State.new()
	if not state.add_ship("ship-1", "freighter", "faction-1", "sol"):
		return false
	if state.add_ship("ship-1", "freighter", "faction-1", "sol"):
		return false
	if state.add_ship("ship-2", "invented", "faction-1", "sol"):
		return false
	if state.cargo_free("ship-1") != 500 or state.can_hold("ship-1", {"ore": 501}):
		return false
	if not state.can_hold("ship-1", {"ore": 300, "water": 200}):
		return false
	if state.set_fuel_from_authoritative_result("ship-1", 101.0):
		return false
	if not state.set_fuel_from_authoritative_result("ship-1", 75.0):
		return false
	var snap := state.snapshot()
	var restored = State.new()
	if not restored.restore(snap) or restored.snapshot() != snap:
		return false
	var broken := snap.duplicate(true)
	broken[0]["cargo"] = {"ore": 501}
	if restored.restore(broken) or restored.snapshot() != snap:
		return false
	return true
