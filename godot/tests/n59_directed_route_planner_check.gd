extends SceneTree
const Planner = preload("res://scripts/sim/directed_route_planner.gd")
var failures := 0

func _initialize() -> void:
	var planner = Planner.new()
	var nodes := ["earth", "belt", "mars", "sol-gate", "ac-gate", "haven"]
	var edges := [
		{"from": "earth", "to": "mars", "distance": 300},
		{"from": "earth", "to": "belt", "distance": 100},
		{"from": "belt", "to": "mars", "distance": 80},
		{"from": "mars", "to": "sol-gate", "distance": 50},
		{"from": "ac-gate", "to": "haven", "distance": 40}
	]
	var gates := {"sol-gate": "ac-gate", "ac-gate": "sol-gate"}
	var result: Dictionary = planner.plan(nodes, edges, gates, "earth", "haven")
	_check(result["ok"] and result["cost"] == 275, "gate multi-hop weighted cost")
	if result["ok"]:
		_check(result["legs"].size() == 5, "five legs")
		_check(result["legs"][3]["kind"] == "gate" and result["legs"][3]["distance"] == 1, "gate nominal distance")
	_check(planner.plan(nodes, edges, gates, "earth", "earth")["legs"].is_empty(), "same location")
	_check(not planner.plan(nodes, edges, gates, "haven", "earth")["ok"], "directed graph no reverse")
	_check(not planner.plan(nodes, edges, {}, "earth", "haven")["ok"], "disconnected without gates")
	_check(not planner.plan(nodes, edges, {"sol-gate": "ac-gate"}, "earth", "haven")["ok"], "unpaired gate")
	var bad := edges.duplicate(true)
	bad.append(edges[0].duplicate())
	_check(not planner.plan(nodes, bad, gates, "earth", "haven")["ok"], "duplicate route")
	bad = edges.duplicate(true)
	bad[0]["distance"] = -1
	_check(not planner.plan(nodes, bad, gates, "earth", "haven")["ok"], "negative distance")
	var tie_edges := [{"from": "a", "to": "c", "distance": 1}, {"from": "a", "to": "b", "distance": 1},
		{"from": "b", "to": "d", "distance": 1}, {"from": "c", "to": "d", "distance": 1}]
	var tie: Dictionary = planner.plan(["a", "b", "c", "d"], tie_edges, {}, "a", "d")
	_check(tie["ok"] and tie["legs"][0]["to"] == "b", "stable tie resolution")
	print("N59 route planner: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, name: String) -> void:
	if not condition:
		failures += 1
		push_error("N59 FAIL: " + name)
