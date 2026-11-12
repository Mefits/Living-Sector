extends RefCounted
## Frozen strategy/planning/mod.rs::validate_plan (260..304), same snapshot,
## goal, catalogue and budget across HTN/Telic/Beam; NO world apply.
const MAX_I64 := 9223372036854775807

static func validate_plan(snapshot: Dictionary, goal: Dictionary, actions: Array,
		plan: Dictionary, budget: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", 0)) != 1 or str(snapshot.get("faction_id", "")).is_empty():
		return {"ok":false,"error":"WrongSchema"}
	if str(plan.get("goal_id", "")) != str(goal.get("goal_id", "")):
		return {"ok":false,"error":"MismatchedGoal"}
	var nodes: int = int(plan.get("nodes_expanded", 0))
	if int(budget.get("max_nodes", 0)) == 0 or nodes > int(budget.get("max_nodes", 0)):
		return {"ok":false,"error":"NodesExceeded"}
	var steps: Array = plan.get("steps", [])
	if steps.size() > int(budget.get("max_depth", 0)):
		return {"ok":false,"error":"DepthExceeded"}
	var forecast_credits: int = int(plan.get("forecast_credits", -1))
	if forecast_credits < 0:
		return {"ok":false,"error":"InvalidCost"}
	var status: String = str(plan.get("status", "")).to_lower()
	if status != "ready":
		return {"ok":steps.is_empty(),"error":"" if steps.is_empty() else "InvalidPlanStatus"}
	if steps.is_empty():
		return {"ok":false,"error":"InvalidPlanStatus"}
	var catalogue: Dictionary = {}
	for action in actions:
		var id: String = str(action.get("action_id", ""))
		if id.is_empty() or int(action.get("cost_credits", -1)) < 0 or catalogue.has(id):
			return {"ok":false,"error":"DuplicateAction"}
		catalogue[id] = action
	var seen: Dictionary = {}
	var spent: int = 0
	var duration: int = 0
	for step in steps:
		var step_id: String = str(step.get("step_id", ""))
		if step_id.is_empty() or seen.has(step_id):
			return {"ok":false,"error":"DuplicateStep"}
		seen[step_id] = true
		for dep in step.get("depends_on", []):
			if not seen.has(str(dep)) or str(dep) == step_id:
				return {"ok":false,"error":"InvalidDependency"}
		var id: String = str(step.get("action_id", ""))
		if not catalogue.has(id):
			return {"ok":false,"error":"UnknownAction"}
		var action: Dictionary = catalogue[id]
		var cost: int = int(action.get("cost_credits", 0))
		var ticks: int = int(action.get("expected_ticks", 0))
		if cost < 0 or spent > MAX_I64 - cost:
			return {"ok":false,"error":"InvalidCost"}
		if ticks < 0 or duration > MAX_I64 - ticks:
			return {"ok":false,"error":"InvalidForecast"}
		spent += cost
		duration += ticks
	if spent != forecast_credits or duration != int(plan.get("forecast_ticks", -1)):
		return {"ok":false,"error":"InvalidForecast"}
	var treasury: int = int(snapshot.get("treasury_credits", 0))
	var reserve: int = int(snapshot.get("treasury_floor_credits", 0))
	if spent > maxi(0, treasury - reserve):
		return {"ok":false,"error":"SpendExceedsTreasury"}
	return {"ok":true,"error":""}

static func can_request_native_dispatch(snapshot: Dictionary, goal: Dictionary, actions: Array,
		plan: Dictionary, budget: Dictionary) -> bool:
	# Pure validation alone is NEVER sufficient. Requires real N121
	# authoritative receipt + native HTN/Telic upstream validation.
	return validate_plan(snapshot,goal,actions,plan,budget).get("ok",false) 		and plan.get("upstream_htn_verified", false) == true 		and plan.get("native_dispatch_authorized", false) == true
