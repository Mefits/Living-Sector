extends RefCounted
## Frozen Rust: native/crates/sim_core/src/strategy/production_chain.rs
## Pure read-only inspector. Inputs are authoritative world snapshots, not commands.
## No stock, payroll, construction, contracts or recipe output are ever mutated.

const COMPLETE := "complete"
const ACTIVE := "active"
const QUEUED := "queued"
const BLOCKED := "blocked"

static func _stage(key: String, status: String, administrator: String, reason: String, actual: int = 0, required: int = 0, contract_id: Variant = null) -> Dictionary:
	var s := {"key": key, "status": status, "administrator": administrator, "reason": reason, "actual": actual, "required": required}
	if contract_id != null:
		s["contract_id"] = contract_id
	return s

## Equivalent to production_dependencies::local_inputs_for_one_batch.
## Recipe entries: {id, facility_type, inputs: {commodity: units}, outputs: {commodity: units}}.
## The lowest total missing input wins; stable recipe ID breaks ties.
static func local_inputs_for_one_batch(product: String, facility_type: String, stock: Dictionary, recipes: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_missing := 9223372036854775807
	for recipe_value in recipes:
		if not recipe_value is Dictionary:
			continue
		var recipe: Dictionary = recipe_value
		if str(recipe.get("facility_type", "")) != facility_type:
			continue
		var outputs: Dictionary = recipe.get("outputs", {})
		if int(outputs.get(product, 0)) <= 0:
			continue
		var gaps: Array = []
		var total_missing := 0
		var inputs: Dictionary = recipe.get("inputs", {})
		var keys: Array = inputs.keys()
		keys.sort()
		for commodity in keys:
			var required := maxi(0, int(inputs[commodity]))
			var available := maxi(0, int(stock.get(commodity, 0)))
			var missing := maxi(0, required - available)
			total_missing += missing
			gaps.append({"commodity": str(commodity), "required": required, "available": available, "missing": missing})
		var recipe_id := str(recipe.get("id", ""))
		if best.is_empty() or total_missing < best_missing or (total_missing == best_missing and recipe_id < str(best.get("recipe_id", ""))):
			best_missing = total_missing
			best = {"recipe_id": recipe_id, "facility_type": facility_type, "ready_for_one_batch": total_missing == 0, "inputs": gaps}
	return best

## Priority for a REAL installed co-located producer. One batch only;
## never recursively assumes a factory, resource or future production.
static func available_local_precursor(product: String, final_facility: String, stock: Dictionary, installed_types: Array, recipes: Array) -> Variant:
	var final_batch := local_inputs_for_one_batch(product, final_facility, stock, recipes)
	if final_batch.is_empty() or bool(final_batch.get("ready_for_one_batch", false)):
		return null
	var kinds := installed_types.duplicate()
	kinds.sort()
	var unique_kinds: Array = []
	for kind in kinds:
		if not unique_kinds.has(kind):
			unique_kinds.append(kind)
	for gap in final_batch["inputs"]:
		if int(gap["missing"]) <= 0:
			continue
		var missing_product := str(gap["commodity"])
		for kind in unique_kinds:
			if str(kind) == final_facility and missing_product == product:
				continue
			var candidate := local_inputs_for_one_batch(missing_product, str(kind), stock, recipes)
			if not candidate.is_empty() and bool(candidate["ready_for_one_batch"]):
				return missing_product
	return null

## Snapshot contract:
## goal {commodity,destination}; construction {status,reason,site_id,
## facility_type,contract_id,delivery_block_reason}; sites[] physical ConstructionSite
## records; producers[] FacilityIdentity/Location/Crew records; contracts[] native
## ContractBoard records; markets[] {location,supply}; recipes[] native recipes.
## All arrays are read-only. Missing authoritative data never becomes success.
static func inspect(faction: String, construction: Dictionary, sites: Array, producers: Array, contracts: Array, markets: Array, recipes: Array) -> Dictionary:
	var goal_value: Variant = construction.get("selected_goal")
	if not goal_value is Dictionary:
		return {}
	var goal: Dictionary = goal_value
	var product := str(goal.get("commodity", ""))
	var destination := str(goal.get("destination", ""))
	if product.is_empty() or destination.is_empty():
		return {}
	var kind := str(construction.get("facility_type", ""))
	if kind.is_empty():
		kind = _facility_for(product, recipes)
	var site: Dictionary = {}
	for entry in sites:
		if not entry is Dictionary:
			continue
		if str(entry.get("faction_id", "")) == faction and str(entry.get("location_name", "")) == destination and str(entry.get("facility_type", "")) == kind and not bool(entry.get("completed", false)):
			var site_filter: Variant = construction.get("site_id")
			if site_filter == null or str(site_filter) == str(entry.get("id", "")):
				site = entry
				break
	var producer: Dictionary = {}
	for entry in producers:
		if not entry is Dictionary:
			continue
		if str(entry.get("faction_id", "")) != faction or str(entry.get("location_name", "")) != destination or str(entry.get("facility_type", "")) != kind:
			continue
		if kind == "mining_rig" or not _recipe_ids(product, kind, recipes).is_empty():
			producer = entry
			break
	var built := not producer.is_empty()
	var contract: Dictionary = {}
	var contract_filter: Variant = construction.get("contract_id")
	if contract_filter != null:
		for entry in contracts:
			if entry is Dictionary and str(entry.get("id", "")) == str(contract_filter) and str(entry.get("requestor_id", "")) == faction and str(entry.get("destination_location", "")) == destination and str(entry.get("mission_category", "")) == "strategy.construction.v1":
				contract = entry
				break
	var local: Dictionary = {}
	var market_found := false
	for entry in markets:
		if entry is Dictionary and str(entry.get("location", entry.get("facility_location", ""))) == destination:
			market_found = true
			var supply: Dictionary = entry.get("supply", {})
			for commodity in supply:
				var value := float(supply[commodity])
				if is_finite(value) and value >= 0.0:
					local[commodity] = int(floor(value))
			break
	var inputs := local_inputs_for_one_batch(product, kind, local, recipes) if market_found else {}
	var receipt: Dictionary = {}
	if built:
		var shift: Dictionary = producer.get("work_shift", {})
		var ticks: Dictionary = shift.get("last_recipe_ticks", {})
		var outputs: Dictionary = shift.get("produced_outputs", {})
		for recipe_id in _recipe_ids(product, kind, recipes):
			var per_recipe: Dictionary = outputs.get(recipe_id, {})
			var units := float(per_recipe.get(product, 0.0))
			if ticks.has(recipe_id) and is_finite(units) and units > 0.0:
				var tick := int(ticks[recipe_id])
				if receipt.is_empty() or tick > int(receipt["tick"]):
					receipt = {"tick": tick, "units": units}
	var steps: Array = []
	var site_exists := not site.is_empty()
	var commissioning := COMPLETE if built or site_exists else (BLOCKED if str(construction.get("status", "")) == BLOCKED else (ACTIVE if str(construction.get("status", "")) == "commissioned" else QUEUED))
	var commission_reason := "native_producer_exists" if built else ("native_site_exists" if site_exists else str(construction.get("reason", "")))
	steps.append(_stage("commission", commissioning, "construction", commission_reason, int(built or site_exists), 1))
	var material_done := site_exists and int(site.get("progress_delivered", 0)) >= int(site.get("progress_required", 0))
	var cargo_status := COMPLETE if built or material_done else QUEUED
	var cargo_reason := "native_material_progress_satisfied" if cargo_status == COMPLETE else "native_site_not_created"
	if cargo_status != COMPLETE and site_exists:
		if not contract.is_empty():
			match str(contract.get("status", "")).to_lower():
				"posted":
					cargo_status = ACTIVE
					cargo_reason = "native_contract_unassigned" if contract.get("fulfiller_id") == null else "native_contract_assigned"
				"accepted", "pickedup", "picked_up":
					cargo_status = ACTIVE
					cargo_reason = "native_carrier_in_flight"
				"delivered":
					cargo_status = ACTIVE
					cargo_reason = "delivery_arrived_progress_unverified"
				_:
					cargo_reason = "awaiting_next_native_delivery"
		else:
			cargo_reason = "awaiting_native_delivery_contract"
	if cargo_status != COMPLETE and construction.get("delivery_block_reason") != null:
		cargo_reason = str(construction["delivery_block_reason"])
	steps.append(_stage("materials", cargo_status, "logistics", cargo_reason, int(site.get("progress_delivered", int(built))), int(site.get("progress_required", int(built))), contract.get("id")))
	var labor: Dictionary = site.get("labor", {})
	var labor_actual := int(labor.get("completed", int(built)))
	var labor_required := int(labor.get("required", int(built)))
	var labor_status := COMPLETE if built or (site_exists and labor_actual >= labor_required) else (QUEUED if not site_exists or cargo_status != COMPLETE else (BLOCKED if labor.get("blocked_reason") != null else ACTIVE))
	var labor_reason := str(labor.get("blocked_reason", "native_labor_blocked")) if labor_status == BLOCKED else ("native_paid_labor_complete" if labor_status == COMPLETE else ("awaiting_native_paid_worker_shifts" if labor_status == ACTIVE else "waiting_for_materials"))
	steps.append(_stage("labor", labor_status, "construction", labor_reason, labor_actual, labor_required))
	var input_status := QUEUED
	var input_reason := "producer_not_materialized"
	if built:
		if not inputs.is_empty():
			input_status = COMPLETE if bool(inputs["ready_for_one_batch"]) else BLOCKED
			input_reason = "local_inputs_for_one_batch_present" if input_status == COMPLETE else "local_recipe_input_shortage"
		elif not market_found:
			input_status = BLOCKED
			input_reason = "local_market_unavailable"
		else:
			input_status = COMPLETE
			input_reason = "native_extractor_no_recipe_inputs"
	steps.append(_stage("inputs", input_status, "logistics", input_reason))
	var work_status := COMPLETE if not receipt.is_empty() else (QUEUED if not built or input_status != COMPLETE else (BLOCKED if producer.get("work_blocked_reason") != null else ACTIVE))
	var work_reason := "real_native_recipe_output_receipt" if work_status == COMPLETE else (str(producer.get("work_blocked_reason", "native_workforce_blocked")) if work_status == BLOCKED else ("awaiting_actual_paid_production_shift" if work_status == ACTIVE else "waiting_for_producer_or_inputs"))
	steps.append(_stage("first_output", work_status, "station", work_reason, int(not receipt.is_empty()), 1))
	var next_stage := "complete"
	var next_administrator := "none"
	for step in steps:
		if str(step["status"]) != COMPLETE:
			next_stage = str(step["key"])
			next_administrator = str(step["administrator"])
			break
	return {"commodity": product, "destination": destination, "facility_type": kind, "next_stage": next_stage, "next_administrator": next_administrator, "steps": steps, "local_inputs": inputs if not inputs.is_empty() else null, "last_output_tick": receipt.get("tick"), "cumulative_produced_units": receipt.get("units")}

static func _recipe_ids(product: String, kind: String, recipes: Array) -> Array:
	var ids: Array = []
	for r in recipes:
		if r is Dictionary and str(r.get("facility_type", "")) == kind and int(r.get("outputs", {}).get(product, 0)) > 0:
			ids.append(str(r.get("id", "")))
	return ids

static func _facility_for(product: String, recipes: Array) -> String:
	for r in recipes:
		if r is Dictionary and int(r.get("outputs", {}).get(product, 0)) > 0:
			return str(r.get("facility_type", ""))
	if ["ore", "ice", "gas", "rare_ore", "crystal_ore"].has(product.to_lower()):
		return "mining_rig"
	return ""
