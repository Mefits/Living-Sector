extends RefCounted
## Rust strategy/long_term.rs: persistent native production objectives.
## All input observations are authoritative; this module issues no payments.
static func from_committed_view(view: Dictionary, tick: int, contract: Dictionary = {}) -> Dictionary:
	var goal: Dictionary = view.get("selected_goal", {})
	if goal.is_empty() or str(view.get("facility_type", "")).is_empty():
		return {}
	var site_id := str(view.get("site_id", ""))
	var contract_id := str(view.get("contract_id", ""))
	var paid_contract := not contract_id.is_empty() and str(contract.get("id", "")) == contract_id and str(contract.get("requestor_id", "")) == str(view.get("faction_id", "")) and str(contract.get("mission_category", "")) == "strategy.construction.v1" and int(contract.get("reserved", 0)) > 0 and str(contract.get("status", "")) != "expired"
	if site_id.is_empty() and not paid_contract:
		return {}
	return {"goal_id": str(goal.get("goal_id", "")), "commodity": goal.get("commodity"), "location": str(goal.get("destination", "")), "facility_type": str(view["facility_type"]), "created_tick": tick, "last_observed_tick": tick, "site_id": site_id, "contract_id": contract_id, "next_stage": "materials", "status": "active", "reason": "native_construction_committed", "verified_output_tick": null, "verified_output_units": null}

static func matches(objective: Dictionary, view: Dictionary) -> bool:
	var goal: Dictionary = view.get("selected_goal", {})
	return objective.get("commodity") == goal.get("commodity") and str(objective.get("location", "")) == str(goal.get("destination", "")) and str(objective.get("facility_type", "")) == str(view.get("facility_type", ""))

static func can_reoffer(objective: Dictionary, crisis: bool) -> bool:
	return str(objective.get("status", "")) != "completed" and not crisis and not str(objective.get("goal_id", "")).begins_with("player_")

## Chain is a fresh physical ECS/contract observation. Never accept pre-project output.
static func observe(objective: Dictionary, chain: Dictionary, tick: int, crisis: bool) -> Dictionary:
	var result: Dictionary = objective.duplicate(true)
	if str(result.get("status", "")) == "completed":
		return result
	result["last_observed_tick"] = tick
	result["next_stage"] = str(chain.get("next_stage", ""))
	var output_tick = chain.get("last_output_tick")
	if output_tick != null and int(output_tick) >= int(result.get("created_tick", 0)) and result["next_stage"] == "complete":
		result["verified_output_tick"] = int(output_tick)
		result["verified_output_units"] = chain.get("cumulative_produced_units")
		result["status"] = "completed"
		result["reason"] = "native_paid_output_confirmed"
	elif crisis:
		result["status"] = "paused"
		result["reason"] = "survival_override"
	else:
		var current: Dictionary = {}
		for step in chain.get("steps", []):
			if str(step.get("status", "")) != "complete":
				current = step
				break
		result["status"] = "blocked" if str(current.get("status", "")) == "blocked" else "active"
		result["reason"] = str(current.get("reason", "native_physical_plan_waiting")) if not current.is_empty() else "native_physical_plan_waiting"
	return result

## Reconcile a faction's remembered objective without replacing active commitments.
## Inputs: existing objectives, current construction views, verified contracts,
## active faction ids, crises and physical production-chain observations.
static func refresh(objectives: Dictionary, views: Dictionary, contracts: Dictionary, chains: Dictionary, factions: Array, crises: Dictionary, tick: int, execute_mode: bool) -> Dictionary:
	var next: Dictionary = objectives.duplicate(true)
	for faction in views.keys():
		var view: Dictionary = views[faction]
		var prior: Dictionary = next.get(faction, {})
		if not prior.is_empty() and str(prior.get("status", "")) != "completed":
			continue
		if not execute_mode and str(view.get("site_id", "")).is_empty():
			continue
		var candidate: Dictionary = view.duplicate(true)
		candidate["faction_id"] = faction
		var objective := from_committed_view(candidate, tick, contracts.get(str(view.get("contract_id", "")), {}))
		if not objective.is_empty():
			next[faction] = objective
	for faction in next.keys():
		if not factions.has(faction):
			next.erase(faction)
			continue
		var objective: Dictionary = next[faction]
		if str(objective.get("status", "")) == "completed":
			continue
		var chain: Dictionary = chains.get(faction, {})
		if chain.is_empty():
			continue
		next[faction] = observe(objective, chain, tick, bool(crises.get(faction, false)))
		var view: Dictionary = views.get(faction, {})
		if matches(objective, view):
			if not str(view.get("site_id", "")).is_empty():
				next[faction]["site_id"] = str(view["site_id"])
			if not str(view.get("contract_id", "")).is_empty():
				next[faction]["contract_id"] = str(view["contract_id"])
	return next
