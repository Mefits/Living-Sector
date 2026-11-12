extends RefCounted
## Frozen strategy/planning/baseline.rs + native_catalogue.rs::{
## native_candidate[_with_target], htn_native_shadow}, connected to N134 head.
## N113 is the ONLY strategic hysteresis owner; N100 owns hybrid.rs.
## All projections remain read-only, no economic action is dispatched.
const Native = preload("res://scripts/sim/phase1/n155_native_catalogue.gd")
const Htn = preload("res://scripts/sim/phase1/n155_htn_methods.gd")
const Validator = preload("res://scripts/sim/phase1/n155_planning_validation.gd")
const SUBSIDY_QUANTITY := 200
const CONSTRUCTION_QUANTITY := 200
const U32_MAX := 4294967295

static func goal_from_head(head: Dictionary) -> Dictionary:
	var p: Dictionary = head.get("problem", {}) if head.get("problem", null) is Dictionary else {}
	if p.is_empty():
		return {}
	var goal_id: String = "%s:%s:%s" % [p.get("goal_id", ""),p.get("destination", ""),p.get("commodity", "")]
	return {"goal_id":goal_id,"destination_id":str(p.get("destination", "")),
		"commodity":str(p.get("commodity", "")),
		"target_units":SUBSIDY_QUANTITY,
		"priority":mini(U32_MAX, maxi(0, int(float(p.get("score", 0.0)))))}

static func native_first_actions(head: Dictionary) -> Array:
	# Only ready, already validated alternatives. The first payment is
	# NOT the complete multi-step project cost (Rust baseline.rs::95-130).
	var p: Dictionary = head.get("problem", {}) if head.get("problem", null) is Dictionary else {}
	if p.is_empty(): return []
	var actions: Array = []
	for alternative in head.get("alternatives", []):
		if str(alternative.get("status", "")) != "ready" or int(alternative.get("first_payment", -1)) < 0:
			continue
		var action: String = str(alternative.get("action", ""))
		var kind: String = ""
		var item: Variant = null
		var units: int = 0
		match action:
			"deliver":
				if alternative.get("source", null) == null: continue
				kind = "deliver"
				item = p.get("commodity")
				units = SUBSIDY_QUANTITY
			"build":
				kind = "construct"
				item = alternative.get("material", null)
				units = CONSTRUCTION_QUANTITY
			_:
				continue
		var suffix: String = str(alternative.get("site_id",
			alternative.get("source","new")))
		if suffix.is_empty(): suffix = "new"
		actions.append({"action_id":"native:%s:%s:%s:%s" % [
			action,p.get("destination",""),p.get("commodity",""),suffix],
			"kind":kind,"source_id":alternative.get("source",null),
			"destination_id":str(p.get("destination","")), "commodity":item,
			"units":units,"cost_credits":int(alternative["first_payment"]),
			"expected_ticks":int(alternative.get("estimated_delay_ticks",0)),
			"inputs":[],"outputs":[],"required_facility_type":null})
	actions.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return str(a["action_id"]) < str(b["action_id"]))
	var unique: Array = []
	var previous: String = ""
	for a in actions:
		if a["action_id"] != previous:
			unique.append(a)
			previous = str(a["action_id"])
	return unique

static func baseline_plan(snapshot: Dictionary, goal: Dictionary, actions: Array,
		selected_id: String, budget: Dictionary) -> Dictionary:
	var selected: Dictionary = {}
	for action in actions:
		if str(action.get("action_id","")) == selected_id:
			selected = action
			break
	var status: String = "NoPlan"
	if int(budget.get("max_nodes",0)) == 0 or int(budget.get("max_depth",0)) == 0:
		status = "BudgetExhausted"
	elif not selected.is_empty():
		status = "Ready"
	var ready: bool = status == "Ready"
	return {"status":status,"goal_id":str(goal.get("goal_id","")),
		"planner_id":"genesis_baseline",
		"steps":[{"step_id":"native-first-step","action_id":selected["action_id"],
			"depends_on":[],"expected_condition":"await_native_execution_receipt"}] if ready else [],
		"forecast_credits":int(selected.get("cost_credits",0)) if ready else 0,
		"forecast_ticks":int(selected.get("expected_ticks",0)) if ready else 0,
		"nodes_expanded":1 if ready else 0,
		"explanation":"Legacy Genesis selection, read-only projection; no dispatch",
		"native_dispatch_authorized":false}

static func htn_native_shadow(snapshot: Dictionary, goal: Dictionary) -> Dictionary:
	var trace: Dictionary = {"mode":"read_only_real_genesis_snapshot",
		"status":"blocked","reason":"","market_id":null,
		"incremental_probe_units":Native.PROBE_UNITS,
		"snapshot_markets":snapshot.get("owned_markets",[]).size(),"usable_markets":0,
		"catalogue_size":0,"validation":"not_run","proposal":null,
		"dispatch_blockers":["native_route_and_fuel_unverified",
			"workforce_and_payroll_unverified","native_order_receipts_not_connected",
			"escrow_and_current_market_prices_require_recheck","upstream_htn_0_2_1_not_executed"]}
	var projection: Dictionary = Native.comparison_case(snapshot,goal)
	if not projection.get("ok",false):
		trace["reason"] = str(projection.get("error","invalid_catalogue"))
		return trace
	trace["usable_markets"] = projection["projected"].get("owned_markets",[]).size()
	trace["catalogue_size"] = projection["actions"].size()
	trace["market_id"] = projection.get("market_id")
	var candidate: Dictionary = Htn.plan(projection["projected"],projection["goal"],
		projection["actions"],{"max_nodes":Native.MAX_SHADOW_NODES,
			"max_depth":Native.MAX_SHADOW_DEPTH})
	var validated: Dictionary = Validator.validate_plan(
		projection["projected"],projection["goal"],projection["actions"],candidate,
		{"max_nodes":Native.MAX_SHADOW_NODES,"max_depth":Native.MAX_SHADOW_DEPTH})
	trace["validation"] = "valid_projected_plan" if candidate.get("status","") == "Ready" and validated.get("ok",false) else (
		"rejected:"+str(validated.get("error","")) if candidate.get("status","") == "Ready"
		else "not_applicable_no_ready_plan")
	match str(candidate.get("status","")):
		"Ready":
			trace["status"] = "projected_only_upstream_unverified" if validated.get("ok",false) else "rejected_by_shared_validator"
		"NoPlan": trace["status"] = "no_plan_with_available_owned_sources"
		"BudgetExhausted": trace["status"] = "bounded_search_exhausted"
		_: trace["status"] = "invalid_snapshot"
	trace["reason"] = "10-unit stock-increase probe; results are forecasts, never native dispatch"
	trace["proposal"] = candidate
	return trace

static func native_candidate_request(snapshot: Dictionary, goal: Dictionary,
		fixed_target: Variant = null) -> Dictionary:
	var proposal: Dictionary = Native.native_candidate_request(snapshot, goal, fixed_target)
	if not proposal.get("ok",false):
		return proposal
	var result: Dictionary = Htn.plan(proposal["projected"],proposal["goal"],
		proposal["actions"],proposal["budget"])
	var check: Dictionary = Validator.validate_plan(proposal["projected"],
		proposal["goal"],proposal["actions"],result,proposal["budget"])
	if str(result.get("status","")) != "Ready":
		var failed: String = "htn_no_ready_plan"
		if result.get("status","") == "BudgetExhausted": failed = "htn_search_budget_exhausted"
		elif result.get("status","") == "InvalidSnapshot": failed = "htn_invalid_snapshot"
		return {"ok":false,"error":failed,"proposal":result}
	if not check.get("ok",false):
		return {"ok":false,"error":"htn_invalid_plan","proposal":result}
	for step in result["steps"]:
		var found: bool = false
		for a in proposal["actions"]:
			if str(a.get("action_id","")) == str(step.get("action_id","")):
				found = str(a.get("kind","")).to_lower() in ["deliver","produce"]
				break
		if not found:
			return {"ok":false,"error":"htn_action_not_dispatchable","proposal":result}
	proposal["proposal"] = result
	proposal["source_projection_ready"] = true
	proposal["dispatch_ready"] = false
	proposal["remaining_gate"] = "upstream_htn_native_receipt_and_live_world_validation"
	return proposal

static func baseline_shadow(snapshot: Dictionary, head: Dictionary, tick: int,
		compare_enabled: bool = false) -> Dictionary:
	# Input is N134's actual HeadDecision. N155 never invents head choice.
	var trace: Dictionary = {"mode":"diagnostic_only","snapshot_tick":tick,
		"faction_id":str(snapshot.get("faction_id","")),
		"selected_native_action":str(head.get("selected_option","")),
		"catalogue_size":0,"goal_id":null,"status":"unavailable",
		"validation":"not_run","proposal":null,"htn":null,
		"planner_comparison":null}
	var goal: Dictionary = goal_from_head(head)
	if goal.is_empty():
		trace["status"] = "no_shortage_goal_for_native_choice"
		return trace
	trace["goal_id"] = goal["goal_id"]
	trace["htn"] = htn_native_shadow(snapshot,goal)
	var actions: Array = native_first_actions(head)
	trace["catalogue_size"] = actions.size()
	var selected: String = ""
	var selected_option: String = str(head.get("selected_option",""))
	for a in actions:
		if selected_option == str(a.get("kind","")) or (selected_option == "build" and str(a.get("kind","")) == "construct"):
			selected = str(a["action_id"])
			break
	var budget: Dictionary = {"max_nodes":2000,"max_depth":12}
	var plan: Dictionary = baseline_plan(snapshot,goal,actions,selected,budget)
	var check: Dictionary = Validator.validate_plan(snapshot,goal,actions,plan,budget)
	trace["proposal"] = plan
	trace["validation"] = "valid" if check.get("ok",false) else "rejected:"+str(check.get("error",""))
	if plan["status"] == "Ready":
		trace["status"] = "projected_first_step" if check.get("ok",false) else "blocked_by_validator"
	else:
		trace["status"] = "no_equivalent_first_step"
	# compare_enabled is a pure read-only instruction to N117, not a new
	# planner invocation. N100 Hybrid plugin remains with another owner.
	trace["comparison_requested"] = compare_enabled
	return trace
