extends SceneTree
const Gate = preload("res://scripts/sim/n74_cargo_capacity.gd")
func _initialize() -> void:
	assert(Gate.inspect({"ore": 40}, 100, "water", 60).ok)
	assert(Gate.inspect({"ore": 40}, 100, "water", 61).reason == "insufficient_capacity")
	assert(Gate.inspect({"ore": -1}, 100, "water", 1).reason == "invalid_hold")
	assert(Gate.inspect({"ore": 4294967295}, 4294967295, "ore", 1).reason == "insufficient_capacity")
	assert(Gate.unload({"ore": 40}, "ore", 41).reason == "insufficient_cargo")
	assert(Gate.unload({"ore": 40}, "ore", 40).remaining == 0)
	quit(0)
