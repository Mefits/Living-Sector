extends RefCounted
## N111: strategy/options.rs read-only alternatives for a single native shortage.
## Caller supplies actual market, construction offers, assessments, and source quotes.
const HORIZON := 1200
const ACTIONS := ["deliver", "build", "wait"]

static func unmet(demand: float, stock: float, demand_window: int) -> float:
	if not is_finite(demand) or not is_finite(stock) or demand_window <= 0:
		return 0.0
	return max(0.0, max(0.0, demand) * float(HORIZON) / float(demand_window) - max(0.0, stock))

static func _wait(treasury: int) -> Dictionary:
	return {"action":"wait","source":"","status":"ready","reason":"reconsider_next_cycle",
		"first_payment":0,"total_commitment":0,"treasury_after":treasury,
		"estimated_delay_ticks":0,"shipment_count":0,"material":"",
		"site_id":"","source_stock":0.0,"first_purchase_cost":-1,
		"covered_units":0.0,"estimated_net_value":0.0}

static func _assess(option: Dictionary, reason: String, units: float, delay: int,
		other_cost: float, need: float, unit_value: float) -> void:
	option["reason"] = reason
	option["covered_units"] = min(max(0.0, units), need)
	if reason != "ready" or not is_finite(units) or not is_finite(other_cost) or not is_finite(unit_value):
		option["status"] = "blocked"
		option["estimated_net_value"] = null
		return
	var timing := float(max(0, HORIZON - delay)) / float(HORIZON)
	var net := float(option["covered_units"]) * unit_value * timing - float(option["total_commitment"]) - other_cost
	option["estimated_net_value"] = net
	option["reason"] = "no_projected_shortage_relief" if option["covered_units"] <= 0.0 else ("cost_exceeds_projected_relief" if net <= 0.0 else "positive_projected_relief")

static func compare_goal(goal: Dictionary, market: Dictionary, assessment: Dictionary,
		offer: Dictionary, treasury: int, multiplier: int, demand_window: int,
		shipment_time: int, delivery_reward: int, construction_payment: int,
		delivery_quantity: int) -> Dictionary:
	var commodity := str(goal.get("commodity",""))
	var demand: Dictionary = market.get("demand", {})
	var stock: Dictionary = market.get("supply", {})
	var price: Dictionary = market.get("prices", {})
	var unit_value := float(price.get(commodity, goal.get("base_price", 0.0)))
	if not is_finite(unit_value) or unit_value <= 0.0:
		unit_value = float(goal.get("base_price", 0.0))
	var need := unmet(float(demand.get(commodity,0.0)),float(stock.get(commodity,0.0)),demand_window)
	var delivery := _wait(treasury)
	delivery["action"] = "deliver"
	delivery["first_payment"] = delivery_reward
	delivery["total_commitment"] = delivery_reward
	delivery["treasury_after"] = treasury - delivery_reward
	delivery["estimated_delay_ticks"] = shipment_time * max(1,multiplier)
	delivery["shipment_count"] = 1
	delivery["material"] = commodity
	delivery["source"] = str(assessment.get("source",""))
	delivery["source_stock"] = float(assessment.get("source_stock",0.0))
	delivery["first_purchase_cost"] = int(assessment.get("first_purchase_cost",-1))
	_assess(delivery,str(assessment.get("reason","no_current_shortage")),
		float(delivery_quantity),shipment_time,0.0,need,unit_value)
	var build := _wait(treasury)
	build["action"] = "build"
	if offer.is_empty():
		_assess(build,"no_construction_proposal",0.0,0,0.0,need,unit_value)
	else:
		var shipments := max(0,int(offer.get("shipments",0)))
		var delay := shipments * shipment_time
		var commitment := int(offer.get("total_cost",0))
		build["first_payment"] = construction_payment
		build["total_commitment"] = commitment
		build["treasury_after"] = treasury - commitment
		build["estimated_delay_ticks"] = delay * max(1,multiplier)
		build["shipment_count"] = shipments
		build["material"] = str(offer.get("material",""))
		build["source"] = str(offer.get("source",""))
		build["site_id"] = str(offer.get("site_id",""))
		build["source_stock"] = float(offer.get("source_stock",0.0))
		build["first_purchase_cost"] = int(offer.get("first_purchase_cost",-1))
		# Forecast comes ONLY from native recipe execution over actual stock.
		# Unknown forecast blocks the option rather than inventing output.
		var remaining := max(0,int(offer.get("remaining",0)))
		var coverage := 0.0 if remaining == 0 else min(1.0,max(0.0,float(build["source_stock"])) / float(remaining))
		var ready := str(offer.get("reason","no_construction_proposal"))
		if not offer.has("native_output_units") or not offer.has("native_input_cost"):
			ready = "native_recipe_forecast_required"
		_assess(build,ready,float(offer.get("native_output_units",0.0))*coverage,
			delay,float(offer.get("native_input_cost",0.0))*coverage,need,unit_value)
	var alternatives := [delivery,build,_wait(treasury)]
	var selected := "wait"
	var best := 0.0
	var best_delay := 9223372036854775807
	for option in alternatives:
		if option["estimated_net_value"] == null:
			continue
		var value := float(option["estimated_net_value"])
		var delay := int(option["estimated_delay_ticks"])
		if value > best or (value > 0.0 and value == best and delay < best_delay):
			best = value
			best_delay = delay
			selected = str(option["action"])
	return {"goal":goal.duplicate(true),"alternatives":alternatives,"selected":selected}
	# No contract, money, stock, facility, or ship is changed.

static func compare_goals(goals: Array, markets: Dictionary, assessments: Dictionary,
		offers: Dictionary, treasury: int, multiplier: int, constants: Dictionary) -> Dictionary:
	var sorted := goals.duplicate(true)
	sorted.sort_custom(func(a,b):
		if float(a.get("score",0.0)) != float(b.get("score",0.0)):
			return float(a.get("score",0.0)) > float(b.get("score",0.0))
		if str(a.get("destination","")) != str(b.get("destination","")):
			return str(a.get("destination","")) < str(b.get("destination",""))
		return str(a.get("commodity","")) < str(b.get("commodity","")))
	var waiting := {}
	for goal in sorted:
		var key := str(goal.get("destination","")) + "|" + str(goal.get("commodity",""))
		var result := compare_goal(goal,markets.get(str(goal.get("destination","")),{}),
			assessments.get(key,{}),offers.get(key,{}),treasury,multiplier,
			int(constants.get("demand_window",0)),int(constants.get("shipment_time",0)),
			int(constants.get("delivery_reward",0)),int(constants.get("construction_payment",0)),
			int(constants.get("delivery_quantity",0)))
		if result["selected"] != "wait":
			return result
		if waiting.is_empty():
			waiting = result
	return waiting
