extends RefCounted
## Frozen Rust strategy/planning/htn_adapter.rs::MethodSearch::expand.
## N93 partial BFS is NOT a substitute for this native Require/Prepare/Apply
## decomposition. The Rust htn 0.2.1 upstream crate final verification still
## requires Phase2 executable parity and remains an explicit dispatch blocker.
const Domain = preload("res://scripts/sim/phase1/n155_native_domain.gd")
const I64_MAX := 9223372036854775807

static func _result(goal: Dictionary, status: String, nodes: int, reason: String) -> Dictionary:
	return {"status":status,"goal_id":str(goal.get("goal_id", "")),
		"planner_id":"htn_0_2_1_shadow", "steps":[], "forecast_credits":0,
		"forecast_ticks":0,"nodes_expanded":nodes,"explanation":reason,
		"upstream_htn_verified":false, "native_dispatch_authorized":false}

static func _require(field: int, amount: int) -> Dictionary:
	return {"kind":"require","field":field,"min":amount}

static func _prepare(action: int) -> Dictionary:
	return {"kind":"prepare","action":action}

static func _apply(action: int, field: int, amount: int) -> Dictionary:
	return {"kind":"apply","action":action,"field":field,"min":amount}

static func _missing_preconditions(action: Dictionary, state: Array) -> int:
	var count: int = 0
	for condition in action.get("pre", []):
		if int(state[int(condition[0])]) < int(condition[1]):
			count += 1
	return count

static func _expand(ctx: Dictionary, state: Array, todo: Array, path: Array) -> Dictionary:
	# Work is a LIFO stack exactly as Rust's Vec<Work>::pop().
	if todo.is_empty():
		return {"found":true, "path":path, "state":state}
	if int(ctx["left"]) <= 0:
		return {"found":false}
	if todo.size() > 100:
		ctx["depth_truncated"] = true
		return {"found":false}
	ctx["left"] = int(ctx["left"]) - 1
	var pending: Array = todo.duplicate(true)
	var work: Dictionary = pending.pop_back()
	var kind: String = str(work.get("kind", ""))
	match kind:
		"require":
			var field: int = int(work["field"])
			var minimum: int = int(work["min"])
			if int(state[field]) >= minimum:
				return _expand(ctx, state, pending, path)
			if path.size() >= int(ctx["max_depth"]):
				ctx["depth_truncated"] = true
				return {"found":false}
			for item in pending:
				if str(item.get("kind", "")) == "apply" and int(item.get("field", -1)) == field and int(item.get("min", -1)) == minimum:
					return {"found":false}
			var producers: Array = []
			var native_actions: Array = ctx["domain"]["actions"]
			for i in range(native_actions.size()):
				var action: Dictionary = native_actions[i]
				var effect: int = Domain.action_effect(action, field)
				if effect > 0:
					producers.append({"index":i,"missing":_missing_preconditions(action,state),
						"effect":effect,"catalogue_index":int(action["catalogue_index"])})
			# Rust sort_by_key: (missing prerequisite count,
			# fields.len() - positive effect, catalogue_index).
			producers.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
				if a["missing"] != b["missing"]: return int(a["missing"]) < int(b["missing"])
				if a["effect"] != b["effect"]: return int(a["effect"]) > int(b["effect"])
				return int(a["catalogue_index"]) < int(b["catalogue_index"]))
			for p in producers:
				var branch: Array = pending.duplicate(true)
				branch.append(_require(field, minimum))
				branch.append(_apply(int(p["index"]), field, minimum))
				branch.append(_prepare(int(p["index"])))
				var found: Dictionary = _expand(ctx,state,branch,path)
				if found.get("found", false):
					return found
			return {"found":false}
		"prepare":
			var index: int = int(work["action"])
			var action: Dictionary = ctx["domain"]["actions"][index]
			for requirement in action.get("pre", []):
				var field: int = int(requirement[0])
				var amount: int = int(requirement[1])
				if int(state[field]) < amount:
					if path.size() >= int(ctx["max_depth"]):
						ctx["depth_truncated"] = true
						return {"found":false}
					var key: String = JSON.stringify([state,pending,int(ctx["max_depth"])-path.size()])
					if ctx["seen"].has(key):
						return {"found":false}
					ctx["seen"][key] = true
					pending.append(_prepare(index))
					pending.append(_require(field,amount))
					return _expand(ctx,state,pending,path)
			return _expand(ctx,state,pending,path)
		"apply":
			var index: int = int(work["action"])
			var target_field: int = int(work["field"])
			var minimum: int = int(work["min"])
			if int(state[target_field]) >= minimum:
				return _expand(ctx,state,pending,path)
			if path.size() >= int(ctx["max_depth"]):
				ctx["depth_truncated"] = true
				return {"found":false}
			var action: Dictionary = ctx["domain"]["actions"][index]
			if Domain.action_effect(action,target_field) <= 0:
				return {"found":false}
			# Mirrors original primitive_task condition/effect check here,
			# but cannot assert htn crate verification has actually run.
			var next: Array = Domain.apply(state,action)
			if next.is_empty():
				return {"found":false}
			var next_path: Array = path.duplicate()
			next_path.append(index)
			return _expand(ctx,next,pending,next_path)
	return {"found":false}

static func _replay(initial: Array, domain: Dictionary, path: Array) -> bool:
	var state: Array = initial.duplicate()
	for index in path:
		state = Domain.apply(state,domain["actions"][int(index)])
		if state.is_empty():
			return false
	return int(state[int(domain["goal_field"])]) >= int(domain["goal_amount"])

static func plan(snapshot: Dictionary, goal: Dictionary, catalogue: Array, budget: Dictionary = {}) -> Dictionary:
	# Phase2 MUST verify this returned candidate against upstream htn 0.2.1
	# and frozen planning/mod.rs::validate_plan BEFORE N121 execution.
	var max_nodes: int = int(budget.get("max_nodes", 2000))
	var max_depth: int = int(budget.get("max_depth", 12))
	if max_nodes <= 0 or max_depth <= 0:
		return _result(goal,"BudgetExhausted",0,"search budget is zero")
	var domain: Dictionary = Domain.domain_from_native(snapshot,goal,catalogue)
	if not domain.get("ok",false):
		return _result(goal,"InvalidSnapshot",0,"snapshot/goal cannot be projected safely")
	var field: int = int(domain["goal_field"])
	var amount: int = int(domain["goal_amount"])
	var initial: Array = domain["initial"]
	if int(initial[field]) >= amount:
		return _result(goal,"NoPlan",0,"goal already satisfied; no action required")
	var ctx: Dictionary = {"left":max_nodes,"max_depth":max_depth,
		"domain":domain,"seen":{},"depth_truncated":false}
	var found: Dictionary = _expand(ctx,initial,[_require(field,amount)],[])
	var expanded: int = max_nodes - int(ctx["left"])
	if not found.get("found", false):
		return _result(goal,"BudgetExhausted" if int(ctx["left"]) == 0 or ctx["depth_truncated"] else "NoPlan",
			expanded,"no valid decomposition found within budget; no native orders issued")
	var path: Array = found["path"]
	if not _replay(initial,domain,path):
		return _result(goal,"NoPlan",expanded,"projected HTN path rejected by ordered stock/cash replay")
	var total_cost: int = 0
	var total_ticks: int = 0
	var steps: Array = []
	for i in range(path.size()):
		var spec: Dictionary = catalogue[int(domain["actions"][int(path[i])]["catalogue_index"])]
		var cost: int = int(spec.get("cost_credits", 0))
		var duration: int = int(spec.get("expected_ticks", 0))
		if cost < 0 or duration < 0 or total_cost > I64_MAX-cost or total_ticks > I64_MAX-duration:
			return _result(goal,"InvalidSnapshot",expanded,"cost or duration overflow")
		total_cost += cost
		total_ticks += duration
		steps.append({"step_id":"htn-%03d" % (i+1), "action_id":str(spec.get("action_id", "")),
			"depends_on":[] if i == 0 else ["htn-%03d" % i],
			"expected_condition":"native_receipt_then_recheck_physical_stock"})
	return {"status":"Ready","goal_id":str(goal.get("goal_id", "")),
		"planner_id":"htn_0_2_1_shadow","steps":steps,"forecast_credits":total_cost,
		"forecast_ticks":total_ticks,"nodes_expanded":expanded,
		"explanation":"HTN-decomposed stock plan; upstream crate verification and native dispatch pending",
		"upstream_htn_verified":false,"native_dispatch_authorized":false}
