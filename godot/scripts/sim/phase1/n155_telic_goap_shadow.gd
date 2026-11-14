extends RefCounted
## strategy/planning/telic_goap.rs + forward_search.rs GOAP-mode ONLY.
## Telic 0.1.0's Boolean heuristics do not prove delivery or cash effects.
## Real exact stock/cash search is carried out on N155 NativeDomain.
## Unlike N99 Beam, this retains a global least-cost priority frontier.
const Domain = preload("res://scripts/sim/phase1/n155_native_domain.gd")
const MAX_I64 := 9223372036854775807

static func _no(goal: Dictionary,status: String,nodes: int,why: String) -> Dictionary:
	return {"status":status,"goal_id":str(goal.get("goal_id", "")),
		"planner_id":"telic_0_1_goap_guided","steps":[],"forecast_credits":0,
		"forecast_ticks":0,"nodes_expanded":nodes,"explanation":why,
		"telic_upstream_verified":false, "native_dispatch_authorized":false}

static func structural_facts(domain: Dictionary, catalogue: Array) -> Dictionary:
	## Frozen source upper bounds: ≤36 actions, ≤8 preconditions/action,
	## ≤96 facts. Output is input for external Telic, not a fake Telic plan.
	var actions: Array = domain.get("actions", [])
	if actions.is_empty() or actions.size() > 36:
		return {"usable":false,"facts":[],"definitions":[]}
	var facts: Dictionary = {}
	var goal_field: int = int(domain.get("goal_field", -1))
	var goal_amount: int = int(domain.get("goal_amount", -1))
	facts[goal_field * 4294967296 + goal_amount] = [goal_field,goal_amount]
	for action in actions:
		var pre: Array = action.get("pre", [])
		if pre.size() > 8:
			return {"usable":false,"facts":[],"definitions":[]}
		for requirement in pre:
			if int(requirement[1]) > 0:
				facts[int(requirement[0]) * 4294967296 + int(requirement[1])] = [int(requirement[0]),int(requirement[1])]
	if facts.size() > 96:
		return {"usable":false,"facts":[],"definitions":[]}
	var key_order: Array = facts.keys()
	key_order.sort()
	var all_facts: Array = []
	for key in key_order:
		all_facts.append(facts[key])
	var definitions: Array = []
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		var effects: Array = []
		for fact in all_facts:
			if Domain.action_effect(a,int(fact[0])) > 0:
				effects.append(fact)
		if effects.is_empty():
			continue
		var spec: Dictionary = catalogue[int(a.get("catalogue_index", -1))]
		var relative_cost: float = (
			float(mini(int(spec.get("expected_ticks", 0)),4294967295)) / 100.0
			+ float(mini(maxi(0, int(spec.get("cost_credits", 0))),100000)) / 1000.0
			+ 1.0)
		definitions.append({"native_action_index":i,"cost":relative_cost,
			"preconditions":a.get("pre", []).duplicate(true),"effects":effects})
	return {"usable":true,"facts":all_facts,"definitions":definitions,
		"goal_fact":[goal_field,goal_amount]}

static func _path_less(a: Array,b: Array) -> bool:
	var bound: int = mini(a.size(), b.size())
	for i in range(bound):
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return a.size() < b.size()

static func _less(a: Dictionary,b: Dictionary) -> bool:
	if int(a["rank"]) != int(b["rank"]):
		return int(a["rank"]) < int(b["rank"])
	return _path_less(a["path"],b["path"])

static func _score(ticks: int,credits: int) -> int:
	return ticks + int(maxi(0,credits) / 20)

static func _rank(domain: Dictionary,node: Dictionary,hint: Array) -> int:
	var bonus: int = 0
	var path: Array = node["path"]
	if not path.is_empty():
		var native_action: Dictionary = domain["actions"][int(path[-1])]
		var catalogue_index: int = int(native_action["catalogue_index"])
		for i in range(hint.size()):
			if int(hint[i]) == catalogue_index:
				bonus = maxi(0, 12-i)
				break
	# Native forward_search::rank(SearchMode::Goap): exact cost
	# dominates; structural hint is a minor tie-break only.
	return _score(int(node["ticks"]),int(node["credits"])) * 100 + 12 - bonus

static func _path_result(goal: Dictionary, catalogue: Array, domain: Dictionary,
		path: Array, nodes: int, reason: String) -> Dictionary:
	var cost: int = 0
	var ticks: int = 0
	var steps: Array = []
	for i in range(path.size()):
		var a: Dictionary = domain["actions"][int(path[i])]
		var spec: Dictionary = catalogue[int(a["catalogue_index"])]
		var value: int = int(spec.get("cost_credits", 0))
		var duration: int = int(spec.get("expected_ticks", 0))
		if value < 0 or duration < 0 or cost > MAX_I64 - value or ticks > MAX_I64 - duration:
			return _no(goal,"InvalidSnapshot",nodes,"forecast overflow")
		cost += value
		ticks += duration
		steps.append({"step_id":"search-%03d" % (i+1),
			"action_id":str(spec.get("action_id", "")),
			"depends_on":[] if i == 0 else ["search-%03d" % i],
			"expected_condition":"native_receipt_then_recheck_physical_stock"})
	return {"status":"Ready","goal_id":str(goal.get("goal_id", "")),
		"planner_id":"telic_0_1_goap_guided","steps":steps,
		"forecast_credits":cost,"forecast_ticks":ticks,
		"nodes_expanded":nodes,"explanation":reason,
		"telic_upstream_verified":false,"native_dispatch_authorized":false}

static func plan(snapshot: Dictionary, goal: Dictionary, catalogue: Array,
		budget: Dictionary, upstream_telic_hint: Array = []) -> Dictionary:
	var nodes_max: int = int(budget.get("max_nodes", 0))
	var depth_max: int = int(budget.get("max_depth", 0))
	if nodes_max <= 0 or depth_max <= 0:
		return _no(goal,"BudgetExhausted",0,"search budget is zero")
	if int(snapshot.get("schema_version", 0)) != 1:
		return _no(goal,"InvalidSnapshot",0,"unsupported snapshot schema")
	var domain: Dictionary = Domain.domain_from_native(snapshot,goal,catalogue)
	if not domain.get("ok",false):
		return _no(goal,"InvalidSnapshot",0,"native stock projection not safe; no orders issued")
	if int(domain["initial"][int(domain["goal_field"])]) >= int(domain["goal_amount"]):
		return _no(goal,"NoPlan",0,"goal already reached")
	# On Phase1, external Telic is not executed. The optional hint must
	# have been produced by the actual upstream Telic interface in Phase2,
	# otherwise use [] and do the original exact GOAP fallback.
	var hint: Array = []
	for h in upstream_telic_hint:
		if int(h) >= 0 and int(h) < catalogue.size():
			hint.append(int(h))
	var initial: Array = domain["initial"].duplicate()
	var frontier: Array = [{"stock":initial,"path":[],"ticks":0,"credits":0,"rank":0}]
	var best: Dictionary = {JSON.stringify(initial): 0}
	var nodes: int = 0
	var truncated: bool = false
	while not frontier.is_empty():
		frontier.sort_custom(_less)
		var node: Dictionary = frontier.pop_front()
		var stock: Array = node["stock"]
		if int(stock[int(domain["goal_field"])]) >= int(domain["goal_amount"]):
			return _path_result(goal,catalogue,domain,node["path"],nodes,
				"Exact stock search; Telic structural hint optional; native dispatch not implied")
		if node["path"].size() >= depth_max:
			truncated = true
			continue
		if nodes >= nodes_max:
			return _no(goal,"BudgetExhausted",nodes,"No exact feasible sequence within bounded GOAP search")
		nodes += 1
		var actions: Array = domain["actions"]
		for i in range(actions.size()):
			var new_stock: Array = Domain.apply(stock,actions[i])
			if new_stock.is_empty():
				continue
			var spec: Dictionary = catalogue[int(actions[i]["catalogue_index"])]
			var duration: int = int(spec.get("expected_ticks", 0))
			var payment: int = int(spec.get("cost_credits", 0))
			if duration < 0 or payment < 0 or int(node["ticks"]) > MAX_I64-duration or int(node["credits"]) > MAX_I64-payment:
				continue
			var next_ticks: int = int(node["ticks"]) + duration
			var next_cost: int = int(node["credits"]) + payment
			var cost_score: int = _score(next_ticks,next_cost)
			var key: String = JSON.stringify(new_stock)
			if best.has(key) and int(best[key]) <= cost_score:
				continue
			best[key] = cost_score
			var path: Array = node["path"].duplicate()
			path.append(i)
			var next: Dictionary = {"stock":new_stock,"path":path,"ticks":next_ticks,
				"credits":next_cost,"rank":0}
			next["rank"] = _rank(domain,next,hint)
			frontier.append(next)
	return _no(goal,"BudgetExhausted" if truncated else "NoPlan",nodes,
		"No exact feasible sequence within bounded GOAP search")
