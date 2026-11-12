extends RefCounted
## N141: native agents/construction/labor.rs + workforce::occupied_workers.
## One pure, staged transaction. The Phase-2 caller must provide an authoritative
## world snapshot and a VERIFIED present() engineering ship, and atomically commit
## returned state with the same tick's facility/commander shift receipts.
const MAX_SHIFT_WORKERS: int = 10
const WAGE_PER_SHIFT: int = 1
const I64_MAX: int = 9223372036854775807

static func occupied_workers(tick: int, facility_shifts: Array, construction_shifts: Array, commander_shifts: Array) -> Dictionary:
	var occupied: Dictionary = {}
	for source in [facility_shifts, construction_shifts, commander_shifts]:
		for shift in source:
			if not (shift is Dictionary) or int(shift.get("tick", -1)) != tick:
				continue
			for worker in shift.get("workers", []):
				if worker is Array and worker.size() == 2:
					var worker_id: String = str(worker[0])
					var count: int = int(worker[1])
					if count > 0:
						occupied[worker_id] = int(occupied.get(worker_id, 0)) + count
	return occupied

static func _failed(reason: String, original: Dictionary, duplicate: bool = false) -> Dictionary:
	var state: Dictionary = original.duplicate(true)
	if not duplicate and state.has("site") and state["site"] is Dictionary:
		var site: Dictionary = state["site"]
		var labor: Dictionary = site.get("labor", {}).duplicate(true)
		labor["blocked_reason"] = reason
		site["labor"] = labor
		site["dirty"] = true
	return {"ok": false, "reason": reason, "workers": 0, "state": state}

## state:
## site: {completed,progress_delivered,progress_required,faction_id,location_name,
##        labor:{required,completed,last_shift,blocked_reason,last_executor}}
## faction: {id,treasury,dirty}; households: Array of
## {id,faction_id,facility_location,population_count,total_wealth,employed_fraction,dirty}
## facility_shifts/construction_shifts/commander_shifts: current durable receipts.
## executor_id: only from executor::present(world,site), NOT a proposed assignment.
static func work(state: Dictionary, tick: int, executor_id: String) -> Dictionary:
	if not state.has("site") or not state["site"] is Dictionary:
		return _failed("missing_site", state)
	var site: Dictionary = state["site"]
	if bool(site.get("completed", false)):
		return _failed("completed_site", state)
	if int(site.get("progress_required", 0)) > int(site.get("progress_delivered", 0)):
		return _failed("awaiting_materials", state)
	var labor: Dictionary = site.get("labor", {})
	var last: Variant = labor.get("last_shift", null)
	if last is Dictionary and int(last.get("tick", -1)) >= tick:
		return _failed("already_worked_this_tick", state, true)
	var needed: int = mini(maxi(0, int(labor.get("required", 150)) - int(labor.get("completed", 0))), MAX_SHIFT_WORKERS)
	if needed == 0:
		var unchanged: Dictionary = state.duplicate(true)
		unchanged["site"]["labor"]["blocked_reason"] = null
		unchanged["site"]["dirty"] = true
		return {"ok": true, "reason": "", "workers": 0, "state": unchanged}
	if not state.has("faction") or not state["faction"] is Dictionary or str(state["faction"].get("id", "")) != str(site.get("faction_id", "")):
		return _failed("missing_sponsor", state)
	var treasury: int = int(state["faction"].get("treasury", -1))
	if treasury < WAGE_PER_SHIFT:
		return _failed("insufficient_labor_budget", state)
	if executor_id.is_empty():
		return _failed("awaiting_construction_ship", state)
	var occupied: Dictionary = occupied_workers(tick, state.get("facility_shifts", []), state.get("construction_shifts", []), state.get("commander_shifts", []))
	var households: Array = state.get("households", [])
	var candidates: Array = []
	for index in range(households.size()):
		var h: Dictionary = households[index]
		if str(h.get("faction_id", "")) != str(site.get("faction_id", "")) or str(h.get("facility_location", "")) != str(site.get("location_name", "")):
			continue
		var population: int = int(h.get("population_count", 0))
		if population <= 0:
			continue
		# Rust i128 population * 3 / 5 (integer truncation).
		var capacity: int = (population / 5) * 3 + ((population % 5) * 3) / 5
		var available: int = maxi(0, capacity - int(occupied.get(str(h.get("id", "")), 0)))
		candidates.append({"id": str(h.get("id", "")), "index": index, "available": available})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var remaining: int = mini(needed, treasury / WAGE_PER_SHIFT)
	var assignments: Array = []
	for candidate in candidates:
		var count: int = mini(int(candidate["available"]), remaining)
		if count == 0:
			continue
		var household: Dictionary = households[int(candidate["index"])]
		var balance: int = int(household.get("total_wealth", 0))
		if balance < 0:
			return _failed("invalid_household_balance", state)
		if balance > I64_MAX - count * WAGE_PER_SHIFT:
			return _failed("household_credit_overflow", state)
		assignments.append({"id": candidate["id"], "index": candidate["index"], "count": count, "after": balance + count * WAGE_PER_SHIFT})
		remaining -= count
		if remaining == 0:
			break
	var workers: int = 0
	for a in assignments:
		workers += int(a["count"])
	if workers == 0:
		return _failed("insufficient_workers", state)
	var wages: int = workers * WAGE_PER_SHIFT
	var result: Dictionary = state.duplicate(true)
	result["faction"]["treasury"] = treasury - wages
	result["faction"]["dirty"] = true
	var receipt_workers: Array = []
	for a in assignments:
		var household: Dictionary = result["households"][int(a["index"])]
		household["total_wealth"] = int(a["after"])
		household["dirty"] = true
		receipt_workers.append([a["id"], a["count"]])
	var new_labor: Dictionary = result["site"].get("labor", {}).duplicate(true)
	new_labor["completed"] = int(new_labor.get("completed", 0)) + workers
	new_labor["last_executor"] = executor_id
	new_labor["last_shift"] = {"tick": tick, "workers": receipt_workers, "wages": wages,
		"input_payment": 0, "processing_fee": 0, "last_recipe_ticks": {}, "produced_outputs": {}}
	new_labor["blocked_reason"] = null
	result["site"]["labor"] = new_labor
	result["site"]["dirty"] = true
	# Rust refresh_employment() rebuilds ALL household fractions from receipts.
	# Include this new shift once; do not independently reserve it twice.
	var all_construction: Array = result.get("construction_shifts", []).duplicate(true)
	all_construction.append(new_labor["last_shift"])
	var refreshed: Dictionary = occupied_workers(tick, result.get("facility_shifts", []), all_construction, result.get("commander_shifts", []))
	for h in result.get("households", []):
		var population: int = int(h.get("population_count", 0))
		var denominator: float = maxf(float(population) * 0.6, 1.0)
		h["employed_fraction"] = clampf(float(refreshed.get(str(h.get("id", "")), 0)) / denominator, 0.0, 1.0)
		h["dirty"] = true
	return {"ok": true, "reason": "", "workers": workers, "state": result,
		"shift": new_labor["last_shift"], "treasury_delta": -wages, "household_credit_delta": wages}
