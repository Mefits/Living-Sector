extends SceneTree
## II-C: compare owned and validated-borrowed N14 preflight. Only N140's
## detached result may reach motion; the public _load default stays owned.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const N140 = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _ship(id: String) -> Dictionary:
	var spec: Dictionary = Catalog.spec("miner")
	return {
		"id": id, "class": "miner", "faction_id": "f1",
		"system_id": "sys1", "size": str(spec["default_size"]),
		"cargo_capacity": int(spec["cargo_capacity"]),
		"cargo": {"ore": 1}, "fuel": float(spec["fuel_capacity"]),
		"fuel_capacity": float(spec["fuel_capacity"]),
		"crew_size": (spec["crew_roles"] as Array).size(),
		"crew_roles": (spec["crew_roles"] as Array).duplicate(),
		"location": "a", "transit": {},
		"memory": {"visited": ["a"]}, "current_bt": {"marker": [1, 2]}
	}

func _initialize() -> void:
	if Catalog.spec("miner").is_empty():
		_fail("Missing miner catalog")
		return
	var world: Dictionary = {"ships": {}, "ship_next_token": 1}
	for n in 24:
		var id: String = "ship_%03d" % n
		world["ships"][id] = _ship(id)
	var original: Dictionary = world.duplicate(true)
	var owned: Dictionary = ShipPhase._load(world)
	var borrowed: Dictionary = ShipPhase._load(world, false)
	if not owned.get("ok", false) or not borrowed.get("ok", false):
		_fail("Valid owned/borrowed restore rejected")
		return
	if owned["fleet"].ships != borrowed["fleet"].ships or (
			owned["transit"].next_token() != borrowed["transit"].next_token()):
		_fail("Owned/borrowed validation or token oracle mismatch")
		return
	# The borrowed roster is read-only and must be replaced by N140-owned
	# output before any motion/BT mutation. N140 must not alias World.
	var gate: Dictionary = N140.stage(world, {"a": Vector2.ZERO}, 1, 1)
	if not gate.get("ok", false):
		_fail("N140 detached gate rejected")
		return
	var id0: String = "ship_000"
	gate["ships"][id0]["cargo"]["ore"] = 77
	gate["ships"][id0]["memory"]["visited"].append("b")
	if world != original:
		_fail("N140 owned fleet aliases original World")
		return
	# Public _load() remains detached, including nested arrays and cargo.
	owned["fleet"].ships[id0]["cargo"]["ore"] = 88
	if world != original:
		_fail("Public owned restore regressed")
		return
	# Borrowed and owned preflights must reject the same malformed state.
	for kind in ["cargo", "fuel", "crew", "identity", "transit", "cursor"]:
		var bad: Dictionary = original.duplicate(true)
		var row: Dictionary = bad["ships"][id0]
		match kind:
			"cargo":
				row["cargo"]["ore"] = -1
			"fuel":
				row["fuel"] = -1.0
			"crew":
				row["crew_size"] = 999
			"identity":
				row["id"] = "other"
			"transit":
				row["transit"] = {"token": 3}
			"cursor":
				bad["ship_next_token"] = 0
		var old: Dictionary = ShipPhase._load(bad)
		var new: Dictionary = ShipPhase._load(bad, false)
		if old.get("ok", false) != new.get("ok", false) or (
				str(old.get("reason", "")) != str(new.get("reason", ""))):
			_fail("Negative oracle diverged: " + kind)
			return
		if old.get("ok", false):
			_fail("Invalid fixture accepted: " + kind)
			return
	# No-transit paid tick: unchanged fleet and original World stay intact.
	var result: Dictionary = ShipPhase.advance(world, {"a": Vector2.ZERO},
		1, 1.0, null)
	if not result.get("ok", false) or result.get("changed", true):
		_fail("Idle N14 paid tick changed or failed: " + str(result))
		return
	if world != original:
		_fail("Advance mutated source World")
		return
	print("PASS p2_perf_c_n14_borrowed_restore_oracle")
	quit(0)
