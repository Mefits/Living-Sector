extends SceneTree
## Negative ownership regression: _load must validate via ShipState.restore
## and never return mutable aliases into authoritative World.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

func _initialize() -> void:
	var spec: Dictionary = Catalog.spec("miner")
	if spec.is_empty():
		push_error("Fixture requires a valid miner catalog class")
		quit(1)
		return
	var ship := {
		"id": "s1", "class": "miner", "faction_id": "f1",
		"system_id": "sys1", "size": str(spec["default_size"]),
		"cargo_capacity": int(spec["cargo_capacity"]),
		"cargo": {"ore": 1}, "fuel": float(spec["fuel_capacity"]),
		"fuel_capacity": float(spec["fuel_capacity"]),
		"crew_size": (spec["crew_roles"] as Array).size(),
		"crew_roles": (spec["crew_roles"] as Array).duplicate(),
		"location": "a", "transit": {},
	}
	var world := {"ships": {"s1": ship}, "ship_next_token": 1}
	var result: Dictionary = ShipPhase._load(world)
	if not result.get("ok", false):
		push_error("Valid fleet rejected: " + str(result))
		quit(1)
		return
	var detached: Dictionary = result["fleet"].ships["s1"]
	detached["cargo"]["ore"] = 999
	detached["crew_roles"].clear()
	detached["location"] = "b"
	if world["ships"]["s1"]["cargo"]["ore"] != 1 or (world["ships"]["s1"]["crew_roles"] as Array).is_empty() or world["ships"]["s1"]["location"] != "a":
		push_error("Mutable alias escaped validated fleet restore")
		quit(1)
		return
	var bad: Dictionary = world.duplicate(true)
	bad["ships"]["s1"]["cargo"]["ore"] = -1
	if ShipPhase._load(bad).get("ok", false):
		push_error("Negative cargo bypassed ShipState.restore validation")
		quit(1)
		return
	var bad_token: Dictionary = world.duplicate(true)
	bad_token["ships"]["s1"]["transit"] = {"token": 1}
	if ShipPhase._load(bad_token).get("ok", false):
		push_error("Stale token cursor accepted")
		quit(1)
		return
	print("PASS p2_perf_c_ship_restore_single_detach_oracle_20261117")
	quit(0)
