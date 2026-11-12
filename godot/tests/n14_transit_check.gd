extends SceneTree
const NativeData = preload("res://scripts/native_data.gd")
const Registry = preload("res://scripts/sim/world_registry.gd")
const Ships = preload("res://scripts/sim/ship_state.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

func _initialize() -> void:
	var seed: Dictionary = NativeData.load_current_world()
	var registry = Registry.new()
	if seed.has("error") or not registry.load_seed(seed):
		_fail("seed")
		return
	var state = Ships.new()
	if not state.add_ship("test-freighter", "freighter", "faction-1", "system-sol"):
		_fail("ship")
		return
	state.ships["test-freighter"]["location"] = "earth-station"
	var graph = registry.graph()
	var positions := {"earth-station": Vector2(0, 0), "lane-epsilon": Vector2(0.1, 0)}
	var transit = Transit.new()
	if transit.depart(state, graph, "test-freighter", "pirate-outpost", positions, 0, 1.0):
		_fail("accepted nonadjacent leg")
		return
	if not transit.depart(state, graph, "test-freighter", "lane-epsilon", positions, 0, 1.0):
		_fail("departure")
		return
	var token := int(state.ships["test-freighter"]["transit"]["token"])
	if not transit.arrival_token_valid(state, "test-freighter", token):
		_fail("token")
		return
	var fuel_before := float(state.ships["test-freighter"]["fuel"])
	if transit.advance(state, "test-freighter", positions, 1, 1.0) != "moving":
		_fail("first tick")
		return
	var snapshot := JSON.stringify(state.snapshot())
	if transit.advance(state, "test-freighter", positions, 1, 1.0) != "duplicate" or JSON.stringify(state.snapshot()) != snapshot:
		_fail("duplicate moved ship")
		return
	if absf(float(state.ships["test-freighter"]["fuel"]) - (fuel_before - 0.05)) > 0.00001:
		_fail("native fuel formula")
		return
	var restored = Ships.new()
	if not restored.restore(state.snapshot()):
		_fail("snapshot")
		return
	if transit.advance(restored, "test-freighter", positions, 2, 1.0) != "arrived":
		_fail("arrival")
		return
	if str(restored.ships["test-freighter"]["location"]) != "lane-epsilon" or transit.arrival_token_valid(restored, "test-freighter", token):
		_fail("arrival state")
		return
	if not transit.depart(restored, graph, "test-freighter", "lane-tau", {"lane-epsilon": Vector2.ZERO, "lane-tau": Vector2(10, 0)}, 3, 1.0):
		_fail("second leg")
		return
	var old_token := int(restored.ships["test-freighter"]["transit"]["token"])
	if not transit.cancel(restored, "test-freighter") or transit.arrival_token_valid(restored, "test-freighter", old_token):
		_fail("cancel token")
		return
	print("N14_TRANSIT_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error("N14_TRANSIT_FAIL " + message)
	quit(1)
