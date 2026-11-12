extends RefCounted
## N100 — Rust strategy/planning/hybrid.rs: shared-budget policy and safe
## candidate arbitration. HTN/GOAP/Beam are external pure adapters.
## No plan is an order: native executor alone can dispatch.
const PLANNER_ID := "hybrid_utility_htn_goap_beam"

static func bounded_preferences(p: Dictionary) -> Dictionary:
	var out := {}
	for key in ["cost_weight", "speed_weight", "caution_weight"]:
		var v := float(p.get(key, 0.5 if key == "caution_weight" else 1.0))
		out[key] = clampf(v, 0.1, 8.0) if is_finite(v) else 1.0
	return out

static func split_budget(budget: Dictionary) -> Dictionary:
	var nodes := maxi(0, int(budget.get("max_nodes", 0)))
	var depth := maxi(0, int(budget.get("max_depth", 0)))
	if nodes < 3 or depth == 0:
		return {"error": "budget_exhausted"}
	var htn := maxi(1, nodes * 2 / 5)
	var goap := maxi(1, nodes * 2 / 5)
	return {"htn": {"max_nodes": htn, "max_depth": depth}, "goap": {"max_nodes": goap, "max_depth": depth}, "beam": {"max_nodes": nodes - htn - goap, "max_depth": depth}}

static func _safe_candidate(domain: Dictionary, actions: Array, result: Dictionary, budget: Dictionary) -> bool:
	if result.get("status") != "ready" or result.get("steps", []).size() > int(budget.get("max_depth", 0)):
		return false
	var state: Array = domain.get("initial", []).duplicate()
	var field := int(domain.get("goal_field", -1))
	if field < 0 or field >= state.size():
		return false
	var catalogue: Dictionary = {}
	for action in actions:
		if catalogue.has(str(action.get("action_id", ""))):
			return false
		catalogue[str(action.get("action_id", ""))] = action
	var native: Array = domain.get("actions", [])
	for step in result.get("steps", []):
		var action_id := str(step.get("action_id", ""))
		if not catalogue.has(action_id):
			return false
		var spec: Dictionary = catalogue[action_id]
		var found := false
		for operation in native:
			var index := int(operation.get("catalogue_index", -1))
			if index < 0 or index >= actions.size() or actions[index].get("action_id") != action_id:
				continue
			var valid := true
			for pre in operation.get("pre", []):
				var pos := int(pre[0])
				if pos < 0 or pos >= state.size() or int(state[pos]) < int(pre[1]):
					valid = false
					break
			if not valid:
				continue
			var after := state.duplicate()
			for delta in operation.get("delta", []):
				var pos := int(delta[0])
				if pos < 0 or pos >= state.size():
					valid = false
					break
				var value := int(after[pos]) + int(delta[1])
				if value < 0 or value > 2147483647:
					valid = false
					break
				after[pos] = value
			if valid:
				state = after
				found = true
				break
		if not found:
			return false
	return int(state[field]) >= int(domain.get("goal_amount", 0))

static func score(plan: Dictionary, actions: Array, preferences: Dictionary) -> float:
	var p := bounded_preferences(preferences)
	var payroll_risk := 0
	for step in plan.get("steps", []):
		for action in actions:
			if action.get("action_id") == step.get("action_id") and action.get("kind") == "produce":
				payroll_risk += 1
				break
	return p["cost_weight"] * float(plan.get("forecast_credits", 0)) / 1000.0 + p["speed_weight"] * float(plan.get("forecast_ticks", 0)) / 100.0 + p["caution_weight"] * (plan.get("steps", []).size() * 0.15 + payroll_risk)

static func select_candidates(domain: Dictionary, actions: Array, budget: Dictionary, preferences: Dictionary, htn: Dictionary, goap: Dictionary, beam: Dictionary = {}) -> Dictionary:
	## External planner adapters must use split_budget; candidates are replayed
	## against the SAME domain. Beam is eligible only after disagreement/failure.
	var split := split_budget(budget)
	if split.has("error"):
		return {"status": "budget_exhausted", "selected_source": "none"}
	var candidates: Array = []
	for item in [{"name": "htn_decomposition", "plan": htn, "limit": split["htn"]}, {"name": "telic_goap_fallback", "plan": goap, "limit": split["goap"]}]:
		if _safe_candidate(domain, actions, item["plan"], item["limit"]):
			candidates.append(item)
	var disagreement := candidates.size() == 2 and candidates[0]["plan"].get("steps") != candidates[1]["plan"].get("steps")
	if (disagreement or candidates.is_empty()) and not beam.is_empty() and _safe_candidate(domain, actions, beam, split["beam"]):
		candidates.append({"name": "control_beam_disagreement", "plan": beam, "limit": split["beam"]})
	if candidates.is_empty():
		return {"status": "no_plan", "selected_source": "none", "note": "Native Utility selected goal; forecast never implies native completion"}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := score(a["plan"], actions, preferences)
		var sb := score(b["plan"], actions, preferences)
		return str(a["name"]) < str(b["name"]) if is_equal_approx(sa, sb) else sa < sb)
	return {"status": "ready", "selected_source": candidates[0]["name"], "result": candidates[0]["plan"].duplicate(true), "note": "Native Utility selected goal; forecast never implies native completion"}
