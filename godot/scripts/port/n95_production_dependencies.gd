extends RefCounted
## N95 — native strategy/production_dependencies.rs. Pure feasibility preview.
## Recipe catalogue is injected from native recipes (N73), in Rust declaration order.
## Dictionary recipe: {id, facility_type, inputs:{commodity:qty}, outputs:{commodity:qty}}
## Inventory is integer units; never writes to live markets.

const MAX_U32: int = 4294967295
const MAX_SAFE: int = 9223372036854775807

static func local_inputs_for_one_batch(product: String, facility_type: String, stock: Dictionary, recipes: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_missing: int = MAX_SAFE
	for rv in recipes:
		var r: Dictionary = rv
		if str(r.get("facility_type", "")) != facility_type or int(r.get("outputs", {}).get(product, 0)) <= 0:
			continue
		var gaps: Array = []
		var total := 0
		for commodity in r.get("inputs", {}):
			var required: int = int(r.inputs[commodity])
			var available: int = int(stock.get(commodity, 0))
			var missing: int = maxi(0, required - available)
			total += missing
			gaps.append({"commodity": commodity, "required": required, "available": available, "missing": missing})
		if best.is_empty() or total < best_missing or (total == best_missing and str(r.id) < str(best.recipe_id)):
			best_missing = total
			best = {"recipe_id": r.id, "facility_type": facility_type, "ready_for_one_batch": total == 0, "inputs": gaps}
	return best

static func ingredients(requested: Array, stock: Dictionary, recipes: Array) -> Dictionary:
	var inventory: Dictionary = stock.duplicate(true)
	var steps: Array = []
	for item in requested:
		var commodity: String = str(item[0])
		var amount: int = int(item[1])
		if amount < 0:
			return {"ok": false, "blocker": "arithmetic_overflow"}
		var result: Dictionary = _consume(commodity, amount, inventory, steps, [], recipes)
		if not result.ok:
			return result
	var leftover: Array = []
	var keys: Array = inventory.keys()
	keys.sort()
	for key in keys:
		leftover.append([key, inventory[key]])
	return {"ok": true, "requested": requested.duplicate(true), "steps": steps, "leftover_stock": leftover}

static func _consume(commodity: String, amount: int, inventory: Dictionary, steps: Array, active: Array, recipes: Array) -> Dictionary:
	if amount == 0:
		return {"ok": true}
	var have: int = int(inventory.get(commodity, 0))
	if have >= amount:
		inventory[commodity] = have - amount
		return {"ok": true}
	if active.has(commodity):
		return {"ok": false, "blocker": "cycle", "commodity": commodity}
	var blocker: Dictionary = {"ok": false, "blocker": "no_recipe_or_stock", "commodity": commodity, "missing_units": amount - have}
	for rv in recipes:
		var r: Dictionary = rv
		var output_per_batch: int = int(r.get("outputs", {}).get(commodity, 0))
		if output_per_batch <= 0:
			continue
		var missing: int = amount - have
		var batches: int = (missing - 1) / output_per_batch + 1
		if batches > MAX_U32:
			blocker = {"ok": false, "blocker": "arithmetic_overflow"}
			continue
		var attempt_stock: Dictionary = inventory.duplicate(true)
		var attempt_steps: Array = steps.duplicate(true)
		var path: Array = active.duplicate()
		path.append(commodity)
		var success := true
		for input in r.get("inputs", {}):
			var per_batch: int = int(r.inputs[input])
			if per_batch < 0 or (per_batch > 0 and batches > MAX_SAFE / per_batch):
				blocker = {"ok": false, "blocker": "arithmetic_overflow"}
				success = false
				break
			var outcome: Dictionary = _consume(str(input), per_batch * batches, attempt_stock, attempt_steps, path, recipes)
			if not outcome.ok:
				blocker = outcome
				success = false
				break
		if not success:
			continue
		for output in r.get("outputs", {}):
			var per_batch: int = int(r.outputs[output])
			var current: int = int(attempt_stock.get(output, 0))
			if per_batch < 0 or (per_batch > 0 and batches > (MAX_SAFE - current) / per_batch):
				blocker = {"ok": false, "blocker": "arithmetic_overflow"}
				success = false
				break
			attempt_stock[output] = current + per_batch * batches
		if not success or int(attempt_stock.get(commodity, 0)) < amount:
			continue
		attempt_stock[commodity] = int(attempt_stock[commodity]) - amount
		attempt_steps.append({"recipe_id": r.id, "facility_type": r.facility_type, "batches": batches})
		inventory.clear()
		inventory.merge(attempt_stock, true)
		steps.clear()
		steps.append_array(attempt_steps)
		return {"ok": true}
	return blocker
