extends RefCounted
## N100 — frozen Rust strategy/planning/hybrid.rs, pure HybridPlanner::decide/plan.
## N155 alone owns NativeDomain, HTN, Telic GOAP and structural validation;
## N99 alone owns Control Beam. N121 alone can request native execution.
## Do not consider a Ready forecast a production, trade or contract receipt.
const PLANNER_ID := "hybrid_utility_htn_goap_beam"
const NOTE := "Native Utility selected goal; forecast never implies native completion"
const I64_MAX := 9223372036854775807
const U32_MAX := 4294967295
const DOMAIN_PATH := "res://scripts/sim/phase1/n155_native_domain.gd"
const VALIDATOR_PATH := "res://scripts/sim/phase1/n155_planning_validation.gd"
const HTN_PATH := "res://scripts/sim/phase1/n155_htn_methods.gd"
const GOAP_PATH := "res://scripts/sim/phase1/n155_telic_goap_shadow.gd"
const BEAM_PATH := "res://scripts/sim/phase1/n99_control_beam.gd"

static func bounded_preferences(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in ["cost_weight", "speed_weight", "caution_weight"]:
		var fallback: float = 0.5 if key == "caution_weight" else 1.0
		var value: float = float(p.get(key, fallback))
		out[key] = clampf(value, 0.1, 8.0) if is_finite(value) else 1.0
	return out

static func split_budget(budget: Dictionary) -> Dictionary:
	var nodes: int = clampi(int(budget.get("max_nodes", 0)), 0, U32_MAX)
	var depth: int = maxi(0, int(budget.get("max_depth", 0)))
	if nodes < 3 or depth == 0:
		return {"error":"insufficient shared planning budget"}
	# Rust: floor(2/5), floor(2/5), remainder; never three full budgets.
	var htn: int = maxi(1, int(nodes * 2 / 5))
	var goap: int = maxi(1, int(nodes * 2 / 5))
	return {"htn":{"max_nodes":htn,"max_depth":depth},
		"goap":{"max_nodes":goap,"max_depth":depth},
		"beam":{"max_nodes":nodes-htn-goap,"max_depth":depth}}

static func _status(value: Variant) -> String:
	match str(value).to_lower():
		"ready": return "Ready"
		"budgetexhausted", "budget_exhausted": return "BudgetExhausted"
		"invalidsnapshot", "invalid_snapshot": return "InvalidSnapshot"
		_: return "NoPlan"

static func _rejected(goal: Dictionary, status: String, nodes: int, why: String) -> Dictionary:
	return {"status":status,"goal_id":str(goal.get("goal_id","")),
		"planner_id":PLANNER_ID,"steps":[],"forecast_credits":0,
		"forecast_ticks":0,"nodes_expanded":nodes,"explanation":why,
		"native_dispatch_authorized":false}

static func _trace() -> Dictionary:
	return {"htn_status":"NoPlan","goap_status":"NoPlan",
		"goap_full_status":null,"beam_status":null,
		"goap_role":"not_invoked","beam_reason":"not_invoked",
		"selected_source":"none","nodes_htn":0,"nodes_goap":0,
		"nodes_beam":0,"note":NOTE,"rejected_candidates":[]}

static func _adapter(provided: Dictionary, key: String, path: String) -> Variant:
	if provided.has(key):
		return provided[key]
	# Each component is in its own Draft PR in Phase 1. Fail closed until
	# Phase 2 mounts the exact existing scripts into one project.
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func _invoke(component: Variant, method: String, arguments: Array) -> Variant:
	if component is Callable:
		return component.callv(arguments)
	if component is Object:
		return component.callv(method, arguments)
	return null

static func _normalise(raw: Variant, goal: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		return _rejected(goal,"InvalidSnapshot",0,"planner adapter returned no plan")
	var plan: Dictionary = raw.duplicate(true)
	plan["status"] = _status(plan.get("status","NoPlan"))
	# N99 control_beam.gd omits goal_id; the invocation binds its request.
	if not plan.has("goal_id"):
		plan["goal_id"] = str(goal.get("goal_id",""))
	if not plan.has("explanation"):
		plan["explanation"] = "Read-only native search projection; no dispatch"
	plan["native_dispatch_authorized"] = false
	return plan

static func _domain(snapshot: Dictionary, goal: Dictionary,
		actions: Array, domain_tool: Variant) -> Dictionary:
	var projected: Variant = _invoke(domain_tool,"domain_from_native",[snapshot,goal,actions])
	if projected is Dictionary:
		return projected
	return {"ok":false,"error":"N155 native domain unavailable"}

static func _carrier_assignment(snapshot: Dictionary, actions: Array,
		steps: Array) -> Dictionary:
	## Extra fail-closed guard: N155 NativeDomain conserves the TOTAL number
	## of departures per source, but an action's capacity check is existential.
	## Two 8-unit deliveries must not reuse one 8-unit ship alongside a
	## second 1-unit ship. Match every departure to one distinct real carrier.
	var required: Dictionary = {}
	for step in steps:
		var spec: Dictionary = {}
		for action in actions:
			if str(action.get("action_id","")) == str(step.get("action_id","")):
				spec = action
				break
		if str(spec.get("kind","")).to_lower() != "deliver":
			continue
		var source: String = str(spec.get("source_id",""))
		if source.is_empty():
			return {"ok":false,"reason":"missing_delivery_source"}
		if not required.has(source):
			required[source] = []
		required[source].append(int(spec.get("units",0)))
	if required.is_empty():
		return {"ok":true,"reason":""}
	var committed: Dictionary = {}
	for contract in snapshot.get("active_commitments",[]):
		if contract.get("assigned_ship_id",null) != null:
			committed[str(contract["assigned_ship_id"])] = true
	var ships: Array = snapshot.get("ships",[])
	var identities: Dictionary = {}
	for ship in ships:
		var id: String = str(ship.get("ship_id",""))
		if id.is_empty() or identities.has(id):
			return {"ok":false,"reason":"missing_or_duplicate_ship_id"}
		identities[id] = true
	for source in required.keys():
		var usable: Array = []
		for ship in ships:
			var fuel: float = float(ship.get("fuel",0.0))
			if str(ship.get("location_id","")) == str(source) and not bool(ship.get("in_transit",false)) and not committed.has(str(ship.get("ship_id",""))) and is_finite(fuel) and fuel > 0.0 and int(ship.get("free_cargo",0)) > 0:
				usable.append({"id":str(ship.get("ship_id","")),
					"space":int(ship.get("free_cargo",0))})
		usable.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if int(a["space"]) != int(b["space"]):
				return int(a["space"]) < int(b["space"])
			return str(a["id"]) < str(b["id"]))
		var needs: Array = required[source].duplicate()
		needs.sort()
		needs.reverse()
		for amount in needs:
			var selected: int = -1
			for i in range(usable.size()):
				if int(usable[i]["space"]) >= int(amount):
					selected = i
					break
			if selected < 0:
				return {"ok":false,"reason":"distinct_real_carrier_capacity_exhausted:"+str(source)}
			usable.remove_at(selected)
	return {"ok":true,"reason":""}

static func _safe_candidate(domain: Dictionary, snapshot: Dictionary, goal: Dictionary,
		actions: Array, result: Dictionary, budget: Dictionary,
		domain_tool: Variant, validator_tool: Variant) -> Dictionary:
	## Mirrors hybrid.rs::safe_candidate: BOTH mod.rs::validate_plan and
	## htn_adapter.rs::NativeAction.apply over one conserved stock/cash state.
	## Never skip either validation for a supposedly successful candidate.
	if _status(result.get("status","NoPlan")) != "Ready":
		return {"ok":false,"reason":"not_ready"}
	if not bool(domain.get("ok",false)):
		return {"ok":false,"reason":"invalid_native_domain:"+str(domain.get("error",""))}
	var verdict: Variant = _invoke(validator_tool,"validate_plan",
		[snapshot,goal,actions,result,budget])
	if not (verdict is Dictionary) or not bool(verdict.get("ok",false)):
		return {"ok":false,"reason":"native_plan_validation:"+str(
			verdict.get("error","adapter_unavailable") if verdict is Dictionary else "adapter_unavailable")}
	var state: Array = domain.get("initial",[]).duplicate()
	var field: int = int(domain.get("goal_field",-1))
	if field < 0 or field >= state.size():
		return {"ok":false,"reason":"missing_goal_field"}
	for step in result.get("steps",[]):
		var target_id: String = str(step.get("action_id",""))
		var catalogue_index: int = -1
		for index in range(actions.size()):
			if str(actions[index].get("action_id","")) == target_id:
				catalogue_index = index
				break
		if catalogue_index < 0:
			return {"ok":false,"reason":"unknown_native_action:"+target_id}
		var operation: Dictionary = {}
		for candidate in domain.get("actions",[]):
			if int(candidate.get("catalogue_index",-1)) == catalogue_index:
				operation = candidate
				break
		if operation.is_empty():
			return {"ok":false,"reason":"action_has_no_native_effect:"+target_id}
		var after: Variant = _invoke(domain_tool,"apply",[state,operation])
		if not (after is Array) or after.is_empty():
			return {"ok":false,"reason":"stock_cash_ship_or_recipe_precondition:"+target_id}
		state = after
	if int(state[field]) < int(domain.get("goal_amount",0)):
		return {"ok":false,"reason":"goal_not_reached_by_real_actions"}
	var ship_check: Dictionary = _carrier_assignment(snapshot,actions,result.get("steps",[]))
	if not bool(ship_check["ok"]):
		return ship_check
	return {"ok":true,"reason":""}

static func score(plan: Dictionary, actions: Array, preferences: Dictionary) -> float:
	# Pure preferences supplied by existing Genesis Director; no new
	# psychology model and never a license to ignore native preconditions.
	var p: Dictionary = bounded_preferences(preferences)
	var payroll_risk: int = 0
	for step in plan.get("steps",[]):
		for action in actions:
			if str(action.get("action_id","")) == str(step.get("action_id","")) and str(action.get("kind","")).to_lower() == "produce":
				payroll_risk += 1
				break
	return float(p["cost_weight"]) * float(plan.get("forecast_credits",0)) / 1000.0 + float(p["speed_weight"]) * float(plan.get("forecast_ticks",0)) / 100.0 + float(p["caution_weight"]) * (float(plan.get("steps",[]).size()) * 0.15 + float(payroll_risk))

static func _rank(source: String) -> int:
	match source:
		"htn_plus_telic_goap": return 0
		"htn_decomposition": return 1
		"telic_goap_direct": return 2
		"telic_goap_fallback": return 3
		"selective_beam": return 4
		_: return 5

static func _better(a: Dictionary, b: Dictionary, actions: Array, preferences: Dictionary) -> bool:
	var sa: float = score(a["plan"],actions,preferences)
	var sb: float = score(b["plan"],actions,preferences)
	if sa != sb:
		return sa < sb
	return _rank(str(a["source"])) < _rank(str(b["source"]))

static func _add_candidate(alternatives: Array, rejects: Array, source: String,
		domain: Dictionary, snapshot: Dictionary, goal: Dictionary, actions: Array,
		result: Dictionary, budget: Dictionary, domain_tool: Variant,
		validator_tool: Variant) -> bool:
	var check: Dictionary = _safe_candidate(domain,snapshot,goal,actions,result,
		budget,domain_tool,validator_tool)
	if not bool(check["ok"]):
		rejects.append({"source":source,"reason":check["reason"],
			"planner_status":result.get("status","NoPlan")})
		return false
	alternatives.append({"source":source,"plan":result.duplicate(true)})
	return true

static func _ingredient_goal(snapshot: Dictionary, goal: Dictionary,
		actions: Array, htn: Dictionary) -> Dictionary:
	if htn.get("steps",[]).is_empty():
		return {}
	var tail: Dictionary = htn["steps"][-1]
	var recipe: Dictionary = {}
	for action in actions:
		if str(action.get("action_id","")) == str(tail.get("action_id","")):
			recipe = action
			break
	if str(recipe.get("kind","")).to_lower() != "produce" or recipe.get("inputs",[]).size() != 1 or str(recipe.get("destination_id","")) != str(goal.get("destination_id","")):
		return {}
	var produces_target: bool = false
	for output in recipe.get("outputs",[]):
		if output.size() >= 2 and str(output[0]) == str(goal.get("commodity","")):
			produces_target = true
			break
	if not produces_target:
		return {}
	var item: Array = recipe["inputs"][0]
	if item.size() != 2:
		return {}
	var ingredient: String = str(item[0])
	var required: int = int(item[1])
	# Exactly Rust's first owned destination market, not a sum of markets.
	for market in snapshot.get("owned_markets",[]):
		if str(market.get("location_id","")) == str(goal.get("destination_id","")):
			var present: float = float(market.get("stock",{}).get(ingredient,0.0))
			if not is_finite(present) or present < 0.0 or present >= float(required):
				return {}
			return {"goal_id":"%s:ingredient:%s" % [goal.get("goal_id",""),ingredient],
				"destination_id":str(goal.get("destination_id","")),
				"commodity":ingredient,"target_units":required,
				"priority":goal.get("priority",0)}
	return {}

static func compose_ingredient_route(snapshot: Dictionary, goal: Dictionary,
		actions: Array, htn: Dictionary, goap: Dictionary,
		domain_tool: Variant, validator_tool: Variant) -> Dictionary:
	## hybrid.rs: ONLY one-input last-step Produce is recomposed. Complex
	## trees retain their entire trusted HTN route; do not hallucinate one.
	if _status(htn.get("status","")) != "Ready" or _status(goap.get("status","")) != "Ready" or htn.get("steps",[]).is_empty():
		return {"ok":false,"reason":"decomposition_not_ready"}
	var tail: Dictionary = htn["steps"][-1]
	var recipe: Dictionary = {}
	for action in actions:
		if str(action.get("action_id","")) == str(tail.get("action_id","")):
			recipe = action
			break
	if str(recipe.get("kind","")).to_lower() != "produce" or recipe.get("inputs",[]).size() != 1 or str(recipe.get("destination_id","")) != str(goal.get("destination_id","")):
		return {"ok":false,"reason":"not_single_ingredient_recipe"}
	var has_output: bool = false
	for pair in recipe.get("outputs",[]):
		if pair.size() == 2 and str(pair[0]) == str(goal.get("commodity","")):
			has_output = true
	if not has_output:
		return {"ok":false,"reason":"recipe_does_not_make_goal_good"}
	var steps: Array = []
	var credits: int = 0
	var ticks: int = 0
	var proposals: Array = goap.get("steps",[]).duplicate(true)
	proposals.append(tail)
	for step in proposals:
		var spec: Dictionary = {}
		for action in actions:
			if str(action.get("action_id","")) == str(step.get("action_id","")):
				spec = action
				break
		if spec.is_empty():
			return {"ok":false,"reason":"unknown_composed_action"}
		var cost: int = int(spec.get("cost_credits",-1))
		var duration: int = int(spec.get("expected_ticks",-1))
		if cost < 0 or duration < 0 or cost > I64_MAX-credits or duration > I64_MAX-ticks:
			return {"ok":false,"reason":"composed_forecast_overflow"}
		credits += cost
		ticks += duration
		var step_id: String = "hybrid-s%d" % (steps.size()+1)
		var dependency: Array = [] if steps.is_empty() else [str(steps[-1]["step_id"])]
		steps.append({"step_id":step_id,"action_id":str(spec.get("action_id","")),
			"depends_on":dependency,
			"expected_condition":str(step.get("expected_condition",""))})
	var expanded: int = int(htn.get("nodes_expanded",0)) + int(goap.get("nodes_expanded",0))
	var combined: Dictionary = {"status":"Ready","goal_id":str(goal.get("goal_id","")),
		"planner_id":PLANNER_ID,"steps":steps,"forecast_credits":credits,
		"forecast_ticks":ticks,"nodes_expanded":expanded,
		"explanation":"HTN recipe milestone with GOAP ingredient-acquisition subplan",
		"native_dispatch_authorized":false}
	var replay_budget: Dictionary = {"max_nodes":maxi(1,expanded),"max_depth":12}
	var domain: Dictionary = _domain(snapshot,goal,actions,domain_tool)
	var checked: Dictionary = _safe_candidate(domain,snapshot,goal,actions,combined,
		replay_budget,domain_tool,validator_tool)
	if not bool(checked["ok"]):
		return {"ok":false,"reason":"composed_replay:"+str(checked["reason"])}
	return {"ok":true,"result":combined}

static func select_candidates(domain: Dictionary, actions: Array, budget: Dictionary,
		preferences: Dictionary, htn: Dictionary, goap: Dictionary,
		beam: Dictionary = {}, snapshot: Dictionary = {}, goal: Dictionary = {},
		validator_tool: Variant = null, domain_tool: Variant = null) -> Dictionary:
	## Compatibility for old N100 callers. A domain alone cannot validate
	## goal binding, forecasts and treasury: demand N155 validator + snapshot.
	if snapshot.is_empty() or goal.is_empty() or validator_tool == null or domain_tool == null:
		return {"status":"InvalidSnapshot","selected_source":"none",
			"reason":"requires original snapshot, goal and shared N155 validator"}
	var split: Dictionary = split_budget(budget)
	if split.has("error"):
		return {"status":"BudgetExhausted","selected_source":"none"}
	var candidates: Array = []
	var rejects: Array = []
	_add_candidate(candidates,rejects,"htn_decomposition",domain,snapshot,goal,
		actions,_normalise(htn,goal),split["htn"],domain_tool,validator_tool)
	_add_candidate(candidates,rejects,"telic_goap_fallback",domain,snapshot,goal,
		actions,_normalise(goap,goal),split["goap"],domain_tool,validator_tool)
	var disagreement: bool = _disagree(candidates)
	if (disagreement or candidates.is_empty()) and not beam.is_empty():
		_add_candidate(candidates,rejects,"selective_beam",domain,snapshot,goal,
			actions,_normalise(beam,goal),split["beam"],domain_tool,validator_tool)
	if candidates.is_empty():
		return {"status":"NoPlan","selected_source":"none","rejected_candidates":rejects}
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return _better(a,b,actions,preferences))
	return {"status":"Ready","selected_source":candidates[0]["source"],
		"result":candidates[0]["plan"].duplicate(true),"note":NOTE,
		"native_dispatch_authorized":false,"rejected_candidates":rejects}

static func _disagree(alternatives: Array) -> bool:
	if alternatives.is_empty():
		return false
	var first: Array = []
	for step in alternatives[0]["plan"].get("steps",[]):
		first.append(str(step.get("action_id","")))
	for i in range(1,alternatives.size()):
		var other: Array = []
		for step in alternatives[i]["plan"].get("steps",[]):
			other.append(str(step.get("action_id","")))
		if first != other:
			return true
	return false

static func decide(snapshot: Dictionary, goal: Dictionary, actions: Array,
		budget: Dictionary, preferences: Dictionary = {},
		interfaces: Dictionary = {}) -> Dictionary:
	var trace: Dictionary = _trace()
	var split: Dictionary = split_budget(budget)
	if split.has("error"):
		return {"result":_rejected(goal,"BudgetExhausted",0,str(split["error"])),"roles":trace}
	var domain_tool: Variant = _adapter(interfaces,"domain",DOMAIN_PATH)
	var validator_tool: Variant = _adapter(interfaces,"validator",VALIDATOR_PATH)
	var htn_tool: Variant = _adapter(interfaces,"htn",HTN_PATH)
	var goap_tool: Variant = _adapter(interfaces,"goap",GOAP_PATH)
	var beam_tool: Variant = _adapter(interfaces,"beam",BEAM_PATH)
	if domain_tool == null or validator_tool == null or htn_tool == null or goap_tool == null or beam_tool == null:
		return {"result":_rejected(goal,"InvalidSnapshot",0,
			"Missing existing N155/N99 adapters in Phase1 isolated PR; no substitute plans"),
			"roles":trace}
	var native_domain: Dictionary = _domain(snapshot,goal,actions,domain_tool)
	if not bool(native_domain.get("ok",false)):
		return {"result":_rejected(goal,"InvalidSnapshot",0,
			"Native stock/ship/cash domain rejected: "+str(native_domain.get("error",""))),
			"roles":trace}
	var alternatives: Array = []
	var rejects: Array = trace["rejected_candidates"]
	var htn: Dictionary = _normalise(_invoke(htn_tool,"plan",
		[snapshot,goal,actions,split["htn"]]),goal)
	trace["nodes_htn"] = int(htn.get("nodes_expanded",0))
	trace["htn_status"] = htn["status"]
	var htn_ok: bool = _add_candidate(alternatives,rejects,"htn_decomposition",
		native_domain,snapshot,goal,actions,htn,split["htn"],domain_tool,validator_tool)
	var ingredient: Dictionary = _ingredient_goal(snapshot,goal,actions,htn) if htn_ok else {}
	trace["goap_role"] = "htn_ingredient_subgoal_and_full_goal" if not ingredient.is_empty() else "full_goal_alternative"
	var goap_goal: Dictionary = ingredient if not ingredient.is_empty() else goal
	var goap_nodes: int = int(split["goap"]["max_nodes"])
	var ingredient_nodes: int = maxi(1,int(goap_nodes / 2)) if not ingredient.is_empty() else goap_nodes
	var partial_budget: Dictionary = {"max_nodes":ingredient_nodes,
		"max_depth":int(split["goap"]["max_depth"])}
	var goap: Dictionary = _normalise(_invoke(goap_tool,"plan",
		[snapshot,goap_goal,actions,partial_budget]),goap_goal)
	trace["nodes_goap"] = int(goap.get("nodes_expanded",0))
	trace["goap_status"] = goap["status"]
	var goap_domain: Dictionary = _domain(snapshot,goap_goal,actions,domain_tool)
	var goap_check: Dictionary = _safe_candidate(goap_domain,snapshot,goap_goal,
		actions,goap,partial_budget,domain_tool,validator_tool)
	if bool(goap_check["ok"]):
		if not ingredient.is_empty():
			var composed: Dictionary = compose_ingredient_route(snapshot,goal,actions,
				htn,goap,domain_tool,validator_tool)
			if bool(composed.get("ok",false)):
				var candidate: Dictionary = composed["result"]
				if candidate.get("steps",[]).size() <= int(budget.get("max_depth",0)) and int(candidate.get("nodes_expanded",0)) <= int(budget.get("max_nodes",0)):
					_add_candidate(alternatives,rejects,"htn_plus_telic_goap",
						native_domain,snapshot,goal,actions,candidate,
						budget,domain_tool,validator_tool)
				else:
					rejects.append({"source":"htn_plus_telic_goap",
						"reason":"combined_depth_or_nodes_exceeded"})
			else:
				rejects.append({"source":"htn_plus_telic_goap",
					"reason":composed.get("reason","composition_rejected")})
		else:
			_add_candidate(alternatives,rejects,"telic_goap_fallback",
				native_domain,snapshot,goal,actions,goap,partial_budget,
				domain_tool,validator_tool)
	else:
		rejects.append({"source":"telic_ingredient" if not ingredient.is_empty() else "telic_goap_fallback",
			"reason":goap_check["reason"],"planner_status":goap["status"]})
	if not ingredient.is_empty() and goap_nodes > ingredient_nodes:
		var full_budget: Dictionary = {"max_nodes":goap_nodes-ingredient_nodes,
			"max_depth":int(split["goap"]["max_depth"])}
		var full: Dictionary = _normalise(_invoke(goap_tool,"plan",
			[snapshot,goal,actions,full_budget]),goal)
		trace["nodes_goap"] = int(trace["nodes_goap"]) + int(full.get("nodes_expanded",0))
		trace["goap_full_status"] = full["status"]
		_add_candidate(alternatives,rejects,"telic_goap_direct",
			native_domain,snapshot,goal,actions,full,full_budget,
			domain_tool,validator_tool)
	var need_beam: bool = alternatives.is_empty() or _disagree(alternatives)
	if need_beam and int(split["beam"]["max_nodes"]) > 0:
		trace["beam_reason"] = "no_valid_structural_plan" if alternatives.is_empty() else "candidate_paths_disagree"
		# Existing N99 Beam accepts projected domain, catalogue and budget,
		# unlike N155 HTN/GOAP which accept snapshot, goal and catalogue.
		var beam: Dictionary = _normalise(_invoke(beam_tool,"plan",
			[native_domain,actions,split["beam"]]),goal)
		trace["nodes_beam"] = int(beam.get("nodes_expanded",0))
		trace["beam_status"] = beam["status"]
		_add_candidate(alternatives,rejects,"selective_beam",
			native_domain,snapshot,goal,actions,beam,split["beam"],
			domain_tool,validator_tool)
	var used: int = int(trace["nodes_htn"]) + int(trace["nodes_goap"]) + int(trace["nodes_beam"])
	if used > int(budget.get("max_nodes",0)) or used < 0:
		return {"result":_rejected(goal,"BudgetExhausted",used,
			"Planner adapters exceeded one shared search budget"),"roles":trace}
	if alternatives.is_empty():
		var status: String = "NoPlan"
		for state in [trace["htn_status"],trace["goap_status"],
			trace["goap_full_status"],trace["beam_status"]]:
			if state == "BudgetExhausted":
				status = "BudgetExhausted"
				break
			if state == "InvalidSnapshot":
				status = "InvalidSnapshot"
		return {"result":_rejected(goal,status,used,
			"No valid HTN / GOAP / selective Beam path within shared budget"),
			"roles":trace}
	alternatives.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return _better(a,b,actions,preferences))
	var selected: Dictionary = alternatives[0]
	var plan: Dictionary = selected["plan"].duplicate(true)
	trace["selected_source"] = selected["source"]
	plan["nodes_expanded"] = used
	plan["planner_id"] = PLANNER_ID
	plan["native_dispatch_authorized"] = false
	plan["explanation"] = "Utility goal; HTN=%s; GOAP=%s (%s)/full=%s; Beam=%s; selected=%s; forecast only" % [
		trace["htn_status"],trace["goap_role"],trace["goap_status"],
		trace["goap_full_status"],trace["beam_reason"],selected["source"]]
	return {"result":plan,"roles":trace}

static func plan(snapshot: Dictionary, goal: Dictionary, actions: Array,
		budget: Dictionary, preferences: Dictionary = {},
		interfaces: Dictionary = {}) -> Dictionary:
	return decide(snapshot,goal,actions,budget,preferences,interfaces)["result"]
