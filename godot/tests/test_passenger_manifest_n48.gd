extends SceneTree
const Manifest = preload("res://scripts/sim/passenger_manifest_n48.gd")

func _initialize() -> void:
	var m = Manifest.new()
	assert(m.configure({
		"origin": {"location": "Earth", "count": 6000, "sentiment": 60},
		"target": {"location": "Mars", "count": 1000, "sentiment": 70}
	}, {"ship": {"location": "Earth", "docked": true, "capacity": 50, "passengers": {}}}))
	assert(not m.embark("bad", "origin", "ship", "Mars"))
	assert(m.embark("board-1", "origin", "ship", "Earth"))
	assert(not m.embark("board-1", "origin", "ship", "Earth"))
	assert(not m.embark("board-2", "origin", "ship", "Earth"))
	assert(m.populations["origin"]["count"] == 5950)
	assert(not m.disembark("land-0", "origin", "ship", "target", "Mars", 50))
	var ship: Dictionary = m.ships["ship"]
	ship["location"] = "Mars"
	m.ships["ship"] = ship
	assert(m.disembark("land-1", "origin", "ship", "target", "Mars", 50))
	assert(not m.disembark("land-1", "origin", "ship", "target", "Mars", 50))
	assert(m.populations["target"]["count"] == 1050)
	assert(m.populations["origin"]["count"] + m.populations["target"]["count"] == 7000)
	var restored = Manifest.new()
	assert(restored.restore(m.snapshot()))
	assert(restored.snapshot() == m.snapshot())
	assert(not restored.restore({"populations": {}, "ships": {"bad": {"capacity": 0, "location": "X", "passengers": {"x": 1}}}, "receipts": {}}))
	assert(restored.snapshot() == m.snapshot())
	print("N48_PASS")
	quit()
