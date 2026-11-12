extends SceneTree
const Ships = preload("res://scripts/sim/ship_state.gd")
const Cargo = preload("res://scripts/sim/ship_cargo_transfer.gd")

func _initialize() -> void:
	var ships := Ships.new()
	var cargo := Cargo.new()
	assert(ships.add_ship("freight-1", "freighter", "faction-1", "system-1"))
	ships.ships["freight-1"]["location"] = "station-1"
	var market := {"ore": 600.0, "food": 20.0}
	var first := cargo.move(ships, "freight-1", market, {"ore": 400}, "load-1", "load", "station-1", 10)
	assert(first.get("ok", false))
	assert(ships.cargo_used("freight-1") == 400)
	assert(market["ore"] == 200.0)
	var before := market.duplicate(true)
	assert(not cargo.move(ships, "freight-1", market, {"ore": 1}, "load-1", "load", "station-1", 10)["ok"])
	assert(market == before and ships.cargo_used("freight-1") == 400)
	assert(not cargo.move(ships, "freight-1", market, {"ore": 101}, "load-over", "load", "station-1", 11)["ok"])
	assert(not cargo.move(ships, "freight-1", market, {"food": 21}, "load-missing", "load", "station-1", 11)["ok"])
	assert(not cargo.move(ships, "freight-1", market, {"food": 1.5}, "load-fraction", "load", "station-1", 11)["ok"])
	assert(market == before and ships.cargo_used("freight-1") == 400)
	ships.ships["freight-1"]["location"] = ""
	assert(not cargo.move(ships, "freight-1", market, {"ore": 5}, "unload-flight", "unload", "station-1", 12)["ok"])
	ships.ships["freight-1"]["location"] = "station-2"
	assert(not cargo.move(ships, "freight-1", market, {"ore": 5}, "unload-wrong", "unload", "station-1", 12)["ok"])
	ships.ships["freight-1"]["location"] = "station-1"
	assert(cargo.move(ships, "freight-1", market, {"ore": 150}, "unload-1", "unload", "station-1", 13)["ok"])
	assert(ships.cargo_used("freight-1") == 250 and market["ore"] == 350.0)
	assert(ships.cargo_used("freight-1") + int(market["ore"]) == 600)
	var snapshot := cargo.snapshot()
	var restored := Cargo.new()
	assert(restored.restore(snapshot))
	assert(restored.snapshot() == snapshot)
	assert(not restored.move(ships, "freight-1", market, {"ore": 1}, "load-1", "load", "station-1", 14)["ok"])
	print("N15_CARGO_OK")
	quit(0)
