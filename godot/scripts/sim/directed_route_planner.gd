extends RefCounted
## N59: Rust world/pathfinder.rs parity: directed travel legs and paired gate legs.
## Pure planning; never moves ships, debits fuel, or charges gate fees.
const GATE_EDGE_WEIGHT := 5
const MAX_COST := 4294967295 # Rust u32 saturation

func plan(locations: Array, routes: Array, gate_pairs: Dictionary, origin: String, destination: String) -> Dictionary:
	var nodes: Dictionary = {}
	var adjacency: Dictionary = {}
	for value in locations:
		if not value is String or value.is_empty() or nodes.has(value):
			return _failure("invalid_location")
		nodes[value] = true
		adjacency[value] = []
	if not nodes.has(origin) or not nodes.has(destination):
		return _failure("unknown_endpoint")
	var seen_edges: Dictionary = {}
	for edge in routes:
		if not edge is Dictionary:
			return _failure("invalid_edge")
		if not edge.has("from") or not edge.has("to") or not edge.has("distance"):
			return _failure("invalid_edge")
		var a: Variant = edge["from"]
		var b: Variant = edge["to"]
		var weight: Variant = edge["distance"]
		if not a is String or not b is String or not nodes.has(a) or not nodes.has(b) or a == b:
			return _failure("invalid_edge")
		if not weight is int or weight <= 0 or weight > MAX_COST:
			return _failure("invalid_distance")
		var edge_key := str(a) + "\u0000" + str(b)
		if seen_edges.has(edge_key):
			return _failure("duplicate_edge")
		seen_edges[edge_key] = true
		adjacency[a].append({"to": b, "weight": weight, "distance": weight, "kind": "travel"})
	for gate in gate_pairs.keys():
		var paired: Variant = gate_pairs[gate]
		if not gate is String or not paired is String or not nodes.has(gate) or not nodes.has(paired) or gate == paired:
			return _failure("invalid_gate")
		if not gate_pairs.has(paired) or gate_pairs[paired] != gate:
			return _failure("unpaired_gate")
		adjacency[gate].append({"to": paired, "weight": GATE_EDGE_WEIGHT, "distance": 1, "kind": "gate"})
	if origin == destination:
		return {"ok": true, "legs": [], "cost": 0}
	for node in adjacency.keys():
		adjacency[node].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["to"] != b["to"]:
				return a["to"] < b["to"]
			return a["kind"] < b["kind"])
	var dist: Dictionary = {origin: 0}
	var prev: Dictionary = {}
	var settled: Dictionary = {}
	var heap: Array = []
	_push(heap, [0, origin])
	while not heap.is_empty():
		var item: Array = _pop(heap)
		var cost: int = item[0]
		var here: String = item[1]
		if settled.has(here) or cost != int(dist.get(here, MAX_COST)):
			continue
		settled[here] = true
		if here == destination:
			break
		for edge in adjacency[here]:
			var target: String = edge["to"]
			var next_cost: int = mini(MAX_COST, cost + int(edge["weight"]))
			if next_cost < int(dist.get(target, MAX_COST)):
				dist[target] = next_cost
				prev[target] = {"from": here, "to": target, "distance": edge["distance"], "kind": edge["kind"]}
				_push(heap, [next_cost, target])
	if not dist.has(destination):
		return _failure("unreachable")
	var legs: Array = []
	var cursor := destination
	while cursor != origin:
		if not prev.has(cursor):
			return _failure("broken_predecessor")
		var leg: Dictionary = prev[cursor]
		legs.push_front(leg.duplicate(true))
		cursor = leg["from"]
	return {"ok": true, "legs": legs, "cost": dist[destination]}

func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if not _less(heap[i], heap[parent]):
			break
		var tmp: Variant = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent

func _pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last: Variant = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var i := 0
	while true:
		var left := 2 * i + 1
		if left >= heap.size():
			break
		var right := left + 1
		var smallest := left
		if right < heap.size() and _less(heap[right], heap[left]):
			smallest = right
		if not _less(heap[smallest], heap[i]):
			break
		var tmp: Variant = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return first

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "legs": [], "cost": -1}
