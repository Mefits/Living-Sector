extends RefCounted
## Frozen Rust: native/crates/sim_core/src/agents/facility/workforce.rs
## Pure preflight and commit of paid shifts on caller-owned dictionaries.
## Caller must provide same-location same-faction facilities, population and durable receipts.
const WAGE_PER_SHIFT := 1

func occupied_workers(tick: int, receipts: Array) -> Dictionary:
	var used := {}
	for receipt in receipts:
		if int(receipt.get("tick", -1)) != tick:
			continue
		for assignment in receipt.get("workers", []):
			var id := String(assignment.get("population_id", ""))
			used[id] = int(used.get(id, 0)) + int(assignment.get("count", 0))
	return used

func plan_shift(producer: Dictionary, stock_owner: Dictionary, populations: Array, receipts: Array, tick: int, input_payment: Variant = null, assigned: bool = true) -> Dictionary:
	if int(producer.get("last_shift_tick", -1)) >= tick:
		return {"ok": false, "reason": "already_worked_this_tick"}
	if input_payment == null and not assigned:
		return {"ok": false, "reason": "station_workforce_not_assigned"}
	var required := int(producer.get("crew_count", 0))
	if required <= 0:
		return {"ok": false, "reason": "no_staffed_jobs"}
	if producer.get("faction_id") != stock_owner.get("faction_id") or producer.get("location_id") != stock_owner.get("location_id"):
		return {"ok": false, "reason": "foreign_workplace_stock"}
	var occupied := occupied_workers(tick, receipts)
	var people := populations.duplicate(true)
	people.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	var assignments := []
	var remaining := required
	for pop in people:
		if pop.get("faction_id") != producer.get("faction_id") or pop.get("location_id") != producer.get("location_id"):
			continue
		var available := maxi(0, int(int(pop.get("population_count", 0)) * 3 / 5) - int(occupied.get(pop.get("id"), 0)))
		var count := mini(remaining, available)
		if count <= 0:
			continue
		var wealth := int(pop.get("wealth", 0))
		if wealth < 0:
			return {"ok": false, "reason": "invalid_household_balance"}
		if wealth > 9223372036854775807 - count:
			return {"ok": false, "reason": "household_credit_overflow"}
		assignments.append({"population_id": pop.get("id"), "count": count, "wealth_after": wealth + count})
		remaining -= count
		if remaining == 0:
			break
	if remaining != 0:
		return {"ok": false, "reason": "insufficient_workers"}
	var wages := required * WAGE_PER_SHIFT
	var producer_cash := int(producer.get("credits", -1))
	var owner_cash := int(stock_owner.get("credits", -1))
	if producer_cash < 0 or owner_cash < 0:
		return {"ok": false, "reason": "invalid_cash_balance"}
	var distinct := producer.get("id") != stock_owner.get("id")
	var producer_after := producer_cash
	var owner_after := owner_cash
	var cost := 0
	var fee := 0
	if input_payment != null:
		cost = int(input_payment) if distinct else 0
		if int(input_payment) < 0:
			return {"ok": false, "reason": "invalid_input_payment"}
		if producer_cash < wages + cost:
			return {"ok": false, "reason": "insufficient_payroll_budget"}
		producer_after -= wages + cost
		owner_after += cost
	elif distinct:
		fee = int((wages + 9) / 10)
		if owner_cash < wages + fee:
			return {"ok": false, "reason": "insufficient_processing_budget"}
		producer_after += fee
		owner_after -= wages + fee
	else:
		if producer_cash < wages:
			return {"ok": false, "reason": "insufficient_payroll_budget"}
		producer_after -= wages
		owner_after = producer_after
	return {"ok": true, "tick": tick, "workers": assignments, "wages": wages, "input_payment": cost, "processing_fee": fee, "producer_before": producer_cash, "owner_before": owner_cash, "producer_after": producer_after, "owner_after": owner_after, "producer_id": producer.get("id"), "stock_owner_id": stock_owner.get("id")}

func commit_shift(plan: Dictionary, producer: Dictionary, owner: Dictionary, populations: Array) -> Dictionary:
	if not plan.get("ok", false):
		return {"ok": false, "reason": "invalid_plan"}
	if producer.get("id") != plan.get("producer_id") or owner.get("id") != plan.get("stock_owner_id") or int(producer.get("last_shift_tick", -1)) >= int(plan.tick):
		return {"ok": false, "reason": "stale_shift"}
	# Caller must serialize access to balances and validate snapshot versions.
	if int(producer.get("credits", -1)) != int(plan.producer_before) or int(owner.get("credits", -1)) != int(plan.owner_before):
		return {"ok": false, "reason": "stale_cash_snapshot"}
	for assignment in plan.workers:
		var found := false
		for pop in populations:
			if pop.get("id") == assignment.population_id:
				found = true
				if int(pop.get("wealth", -1)) != int(assignment.wealth_after) - int(assignment.count):
					return {"ok": false, "reason": "stale_population_snapshot"}
		if not found:
			return {"ok": false, "reason": "missing_population"}
	producer.credits = plan.producer_after
	if producer.get("id") != owner.get("id"):
		owner.credits = plan.owner_after
	producer.last_shift_tick = plan.tick
	for assignment in plan.workers:
		for pop in populations:
			if pop.get("id") == assignment.population_id:
				pop.wealth = assignment.wealth_after
				pop.employed_fraction = clampf(float(assignment.count) / maxf(1.0, float(pop.get("population_count", 0)) * 0.6), 0.0, 1.0)
	return {"ok": true, "tick": plan.tick, "workers": plan.workers.duplicate(true), "wages": plan.wages, "input_payment": plan.input_payment, "processing_fee": plan.processing_fee}
