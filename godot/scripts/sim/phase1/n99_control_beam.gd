extends RefCounted
## N99 — Rust planning/control_beam.rs + forward_search.rs beam mode.
## Domain is a validated Rust-native stock/cash projection supplied by HTN adapter.
## This module never dispatches, produces, pays, or alters the world.
const WIDTH := 16
const MAX_I32 := 2147483647

static func _apply(stock: Array, action: Dictionary) -> Array:
	var result := stock.duplicate()
	for requirement in action.get("pre", []):
		var field := int(requirement[0])
		if field < 0 or field >= result.size() or int(result[field]) < int(requirement[1]):
			return []
	for effect in action.get("delta", []):
		var field := int(effect[0])
		if field < 0 or field >= result.size():
			return []
		var value := int(result[field]) + int(effect[1])
		if value < 0 or value > MAX_I32:
			return []
		result[field] = value
	return result

static func _rank(stock: Array, goal_field: int, goal_amount: int, ticks: int, credits: int, depth: int) -> int:
	var shortage: int = maxi(0, goal_amount - int(stock[goal_field]))
	return shortage * 1000 + ticks + maxi(0, credits) / 20 + depth

static func plan(domain: Dictionary, catalogue: Array, budget: Dictionary) -> Dictionary:
	var max_nodes := int(budget.get("max_nodes", 0))
	var max_depth := int(budget.get("max_depth", 0))
	if max_nodes <= 0 or max_depth <= 0:
		return _result("budget_exhausted", [], 0, true)
	var initial: Array = domain.get("initial", [])
	var goal_field := int(domain.get("goal_field", -1))
	var goal_amount := int(domain.get("goal_amount", -1))
	if goal_field < 0 or goal_field >= initial.size() or goal_amount < 0:
		return _result("invalid_snapshot", [], 0, false)
	if int(initial[goal_field]) >= goal_amount:
		return _result("no_plan", [], 0, false)
	var actions: Array = domain.get("actions", [])
	var frontier: Array = [{"stock": initial.duplicate(), "path": [], "ticks": 0, "credits": 0, "rank": 0}]
	var best: Dictionary = {JSON.stringify(initial): 0}
	var expanded := 0
	var truncated := false
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["rank"] == b["rank"]:
				return str(a["path"]) < str(b["path"])
			return a["rank"] < b["rank"])
		var active := frontier
		frontier = []
		var next_level: Array = []
		for node in active:
			var stock: Array = node["stock"]
			if int(stock[goal_field]) >= goal_amount:
				return _result("ready", node["path"], expanded, false, catalogue, actions, node)
			if node["path"].size() >= max_depth:
				truncated = true
				continue
			if expanded >= max_nodes:
				return _result("budget_exhausted", [], expanded, true)
			expanded += 1
			for i in range(actions.size()):
				var native: Dictionary = actions[i]
				var idx := int(native.get("catalogue_index", -1))
				if idx < 0 or idx >= catalogue.size():
					return _result("invalid_snapshot", [], expanded, false)
				var successor := _apply(stock, native)
				if successor.is_empty():
					continue
				var spec: Dictionary = catalogue[idx]
				var ticks := int(node["ticks"]) + int(spec.get("expected_ticks", 0))
				var credits := int(node["credits"]) + int(spec.get("cost_credits", 0))
				if ticks < 0 or credits < 0:
					continue
				var cost := ticks + credits / 20
				var key := JSON.stringify(successor)
				if best.has(key) and int(best[key]) <= cost:
					continue
				best[key] = cost
				var path: Array = node["path"].duplicate()
				path.append(i)
				next_level.append({"stock": successor, "path": path, "ticks": ticks, "credits": credits, "rank": _rank(successor, goal_field, goal_amount, ticks, credits, path.size())})
		next_level.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["rank"] == b["rank"]:
				return str(a["path"]) < str(b["path"])
			return a["rank"] < b["rank"])
		if next_level.size() > WIDTH:
			truncated = true
			next_level.resize(WIDTH)
		frontier = next_level
	return _result("budget_exhausted" if truncated else "no_plan", [], expanded, truncated)

static func _result(status: String, path: Array, expanded: int, exhausted: bool, catalogue: Array = [], actions: Array = [], node: Dictionary = {}) -> Dictionary:
	var steps: Array = []
	for i in range(path.size()):
		var spec: Dictionary = catalogue[int(actions[int(path[i])]["catalogue_index"])]
		steps.append({"step_id": "search-%03d" % (i + 1), "action_id": spec["action_id"], "depends_on": [] if i == 0 else ["search-%03d" % i], "expected_condition": "native_receipt_then_recheck_physical_stock"})
	return {"status": status, "planner_id": "control_beam_native", "steps": steps, "nodes_expanded": expanded, "exhausted": exhausted, "forecast_credits": node.get("credits", 0), "forecast_ticks": node.get("ticks", 0)}
