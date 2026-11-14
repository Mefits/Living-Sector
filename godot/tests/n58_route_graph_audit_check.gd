extends SceneTree
const Graph = preload("res://scripts/sim/route_graph.gd")
const Audit = preload("res://scripts/sim/route_graph_audit.gd")
var failures: int = 0

func _initialize() -> void:
	var worlds: Array = [
		{"system": {"id": "sol"}, "facilities": [{"location": "a"}], "nav_sites": [{"name": "b"}],
			"travel_routes": [{"from": "a", "to": "b", "distance": 12.0}]},
		{"system": {"id": "alpha"}, "facilities": [], "nav_sites": [{"name": "c"}],
			"travel_routes": [{"from": "b", "to": "c", "distance": 8.0}]}
	]
	var graph = Graph.new()
	var auditor = Audit.new()
	_assert(graph.load_worlds(worlds), "valid graph load")
	var before: Dictionary = graph.snapshot()
	_assert(auditor.audit(worlds, graph)["ok"], "exact source graph")
	_assert(graph.snapshot() == before, "audit does not mutate graph")
	_assert(not graph.shortest_path("c", "a")["reachable"], "no reverse edges")
	var tampered: Array = worlds.duplicate(true)
	tampered[0]["travel_routes"][0]["distance"] = 13.0
	_assert(not auditor.audit(tampered, graph)["ok"], "weight mismatch")
	tampered = worlds.duplicate(true)
	tampered[0]["travel_routes"].append({"from": "a", "to": "b", "distance": 12.0})
	_assert(not auditor.audit(tampered, graph)["ok"], "duplicate source arc")
	tampered = worlds.duplicate(true)
	tampered[0]["travel_routes"][0]["distance"] = -1
	_assert(not auditor.audit(tampered, graph)["ok"], "negative weight")
	tampered = worlds.duplicate(true)
	tampered[1]["system"]["id"] = "sol"
	_assert(not auditor.audit(tampered, graph)["ok"], "duplicate system")
	tampered = worlds.duplicate(true)
	tampered[1]["travel_routes"].clear()
	_assert(not auditor.audit(tampered, graph)["ok"], "missing arc")
	_assert(graph.snapshot() == before, "failure does not mutate graph")
	if failures == 0:
		print("N58_ROUTE_GRAPH_AUDIT_PASS")
	quit(0 if failures == 0 else 1)

func _assert(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("N58 FAIL: " + label)
