extends RefCounted
## Frozen Rust: sim_core/agents/facility/mod.rs bundle_convoy_plans.
## Only proposes contracts; posting, escrow and stock movement belong to apply.
const MAX_DELIVERY_CONTRACT_QTY := 200
const I64_MAX := 9223372036854775807

static func bundle(plans: Array, credits_by_requestor: Dictionary) -> Dictionary:
	var groups := {}
	for plan in plans:
		if not (plan is Dictionary):
			return {"ok": false, "reason": "invalid_plan"}
		var destination := str(plan.get("destination", ""))
		var commodity := str(plan.get("commodity", ""))
		var requestor := str(plan.get("requestor_id", ""))
		var qty := int(plan.get("qty", -1))
		var payment := int(plan.get("payment", -1))
		if destination.is_empty() or commodity.is_empty() or requestor.is_empty() or qty <= 0 or payment < 0:
			return {"ok": false, "reason": "invalid_plan"}
		var key := JSON.stringify([destination, commodity])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(plan.duplicate(true))
	var output := []
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var group: Array = groups[key]
		if group.size() == 1:
			output.append(group[0])
			continue
		var total_qty := 0
		var total_payment := 0
		for p in group:
			total_qty = mini(MAX_DELIVERY_CONTRACT_QTY * 2, total_qty + int(p["qty"]))
			if int(p["payment"]) > I64_MAX - total_payment:
				return {"ok": false, "reason": "payment_overflow"}
			total_payment += int(p["payment"])
		var lead_index := -1
		var best_credits := -1
		for i in range(group.size()):
			var cash := int(credits_by_requestor.get(str(group[i]["requestor_id"]), 0))
			if cash >= total_payment and cash > best_credits:
				best_credits = cash
				lead_index = i
		if lead_index < 0:
			output.append_array(group)
			continue
		var lead: Dictionary = group[lead_index].duplicate(true)
		lead["qty"] = total_qty
		lead["payment"] = total_payment
		output.append(lead)
	return {"ok": true, "plans": output}
