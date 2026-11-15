extends RefCounted
## N155 Phase 1; frozen strategy/planning/native_catalogue.rs::catalogue,
## projectable_stock, promote_industry_output_goal, pinned_producer_recipe,
## comparison_case, projected_native_target, native_candidate and shadow data.
## Pure owned-market projection. No ship dispatch, actual recipes, inventory,
## payroll, escrow or NativeExecution side effects.
const PROBE_UNITS := 10
const MAX_SHADOW_NODES := 350
const MAX_SHADOW_DEPTH := 12
const PROJECTED_DELIVERY_TICKS := 120
const RECIPE_INTERVAL_BASE := 5
const SUBSIDY_BASE_PAYMENT := 800
const I32_MAX := 2147483647
const I64_MAX := 9223372036854775807
const GOODS := ["ore","ice","gas","rare_ore","crystal_ore","metals","fuel","polymers","water","alloys","components","electronics","quantum_cores","tools","food","medical","luxury"]
const BASE_PRICE := {"ore":15.0,"ice":10.0,"gas":20.0,"rare_ore":75.0,"crystal_ore":140.0,
	"metals":45.0,"fuel":25.0,"polymers":40.0,"water":12.0,"alloys":145.0,
	"components":80.0,"electronics":120.0,"quantum_cores":320.0,"tools":90.0,
	"food":18.0,"medical":100.0,"luxury":150.0}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

static func _pair_input_valid(pairs: Array) -> bool:
	if pairs.is_empty():
		return false
	for pair in pairs:
		if not (pair is Array) or pair.size() < 2 or str(pair[0]).is_empty() or int(pair[1]) <= 0:
			return false
	return true

static func _projectable_stock(market: Dictionary, commodity: String) -> int:
	var stock: Dictionary = market.get("stock", {})
	var raw: float = float(stock.get(commodity, 0.0))
	if not is_finite(raw) or raw < 0.0 or raw > float(I32_MAX):
		return -1
	return int(floor(raw))

static func _markets_at(markets: Array, location: String) -> Array:
	var result: Array = []
	for market in markets:
		if str(market.get("location_id", "")) == location:
			result.append(market)
	return result

static func _has_facility(facilities: Array, id: String, location: String, kind: String = "") -> bool:
	for f in facilities:
		if str(f.get("facility_id", "")) == id and str(f.get("location_id", "")) == location:
			if kind.is_empty() or kind == str(f.get("facility_type", "")):
				return true
	return false

static func _kind(action: Dictionary) -> String:
	return str(action.get("kind", "")).to_lower()

static func _sorted_action_catalogue(actions: Array) -> Array:
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("action_id", "")) < str(b.get("action_id", "")))
	var unique: Array = []
	var prev: String = ""
	for a in actions:
		if prev != str(a.get("action_id", "")):
			unique.append(a)
			prev = str(a.get("action_id", ""))
	return unique

static func catalogue(snapshot: Dictionary, destination: String, goal_commodity: Variant = null) -> Dictionary:
	## Rust BTreeMap location counts; only unique physical market owned by
	## a matching facility can be projected (including source locations).
	var original: Array = snapshot.get("owned_markets", [])
	var facilities: Array = snapshot.get("facilities", [])
	var recipes: Array = snapshot.get("recipes", [])
	var ships: Array = snapshot.get("ships", [])
	var commitments: Array = snapshot.get("active_commitments", [])
	var counts: Dictionary = {}
	for market in original:
		var loc: String = str(market.get("location_id", ""))
		counts[loc] = int(counts.get(loc, 0)) + 1
	if not counts.has(destination):
		return _fail("destination_has_no_owned_market")
	if int(counts[destination]) != 1:
		return _fail("ambiguous_destination_markets")
	var projected: Dictionary = snapshot.duplicate(true)
	var owned: Array = []
	for m in original:
		var loc: String = str(m.get("location_id", ""))
		if int(counts.get(loc, 0)) == 1 and not str(m.get("market_id", "")).is_empty() and not str(m.get("facility_id", "")).is_empty() and not loc.is_empty():
			if _has_facility(facilities, str(m["facility_id"]), loc):
				owned.append(m.duplicate(true))
	owned.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["location_id"]) == str(b["location_id"]):
			return str(a["market_id"]) < str(b["market_id"])
		return str(a["location_id"]) < str(b["location_id"]))
	projected["owned_markets"] = owned
	var targets: Array = _markets_at(owned, destination)
	if targets.is_empty():
		return _fail("destination_market_owner_missing_or_wrong_location")
	var target_market_id: String = str(targets[0]["market_id"])
	# Posted or Accepted contracts reserve source stock only in this preview;
	# picked-up goods are already absent from the real native stock.
	for commitment in commitments:
		var status: String = str(commitment.get("status", "")).to_lower()
		var source: String = str(commitment.get("source", ""))
		var quantity: int = int(commitment.get("quantity", 0))
		if quantity <= 0 or not (status in ["posted","accepted"]) or source == destination:
			continue
		for market in owned:
			if str(market["location_id"]) != source:
				continue
			var item: String = str(commitment.get("commodity", ""))
			var stock: Dictionary = market.get("stock", {})
			var value: float = float(stock.get(item, 0.0))
			if is_finite(value) and value >= 0.0:
				stock[item] = maxf(0.0, value - float(quantity))
			break
	var actions: Array = []
	var producible: Dictionary = {}
	# Native action pins a producer ID, while its storage belongs to the
	# distinct, uniquely owned market at the SAME location.
	for market in owned:
		var loc: String = str(market["location_id"])
		for producer in facilities:
			if str(producer.get("location_id", "")) != loc:
				continue
			for recipe in recipes:
				if str(recipe.get("facility_type", "")) != str(producer.get("facility_type", "")):
					continue
				var inputs: Array = recipe.get("inputs", [])
				var outputs: Array = recipe.get("outputs", [])
				if not _pair_input_valid(inputs) or not _pair_input_valid(outputs):
					continue
				var first: Array = outputs[0]
				actions.append({"action_id": "htn-preview:produce:%s:%s:%s" % [
					market.get("market_id", ""), producer.get("facility_id", ""), recipe.get("recipe_id", "")],
					"kind": "produce", "source_id": str(producer.get("facility_id", "")),
					"destination_id": loc, "commodity": str(first[0]), "units": int(first[1]),
					"cost_credits": 0, "expected_ticks": RECIPE_INTERVAL_BASE,
					"inputs": inputs.duplicate(true), "outputs": outputs.duplicate(true),
					"required_facility_type": str(recipe.get("facility_type", ""))})
				for output in outputs:
					var key: String = loc + "|" + str(output[0])
					producible[key] = maxi(int(producible.get(key, 0)), int(output[1]))
	var assigned: Dictionary = {}
	var incoming: Dictionary = {}
	for c in commitments:
		var ship_id: String = str(c.get("assigned_ship_id", ""))
		if not ship_id.is_empty():
			assigned[ship_id] = true
		if int(c.get("quantity", 0)) > 0:
			incoming[str(c.get("destination", "")) + "|" + str(c.get("commodity", ""))] = true
	for source_market in owned:
		var source: String = str(source_market.get("location_id", ""))
		var capacity: int = 0
		for ship in ships:
			var fuel: float = float(ship.get("fuel", 0.0))
			if ship.get("location_id") == source and not bool(ship.get("in_transit", false)) and not assigned.has(str(ship.get("ship_id", ""))) and is_finite(fuel) and fuel > 0.0:
				capacity = maxi(capacity, int(ship.get("free_cargo", 0)))
		if capacity == 0:
			continue
		for dest_market in owned:
			var dest: String = str(dest_market.get("location_id", ""))
			if source == dest:
				continue
			for commodity in GOODS:
				if incoming.has(dest + "|" + commodity):
					continue
				var stock: int = _projectable_stock(source_market, commodity)
				if stock < 0:
					continue
				var possible: int = int(producible.get(source + "|" + commodity, 0))
				var available: int = maxi(stock, mini(I32_MAX, possible * 3))
				var max_lot: int = mini(20, mini(capacity, available))
				if max_lot <= 0:
					continue
				var lots: Dictionary = {max_lot: true, mini(max_lot, PROBE_UNITS): true}
				if possible > 0:
					lots[mini(max_lot, possible)] = true
				for producer in facilities:
					if str(producer.get("location_id", "")) != dest:
						continue
					for recipe in recipes:
						if str(recipe.get("facility_type", "")) != str(producer.get("facility_type", "")):
							continue
						for input_pair in recipe.get("inputs", []):
							if str(input_pair[0]) == commodity and int(input_pair[1]) > 0 and int(input_pair[1]) <= max_lot:
								lots[int(input_pair[1])] = true
				var observed: Dictionary = source_market.get("prices", {})
				var price: float = float(observed.get(commodity, BASE_PRICE[commodity]))
				if not is_finite(price) or price <= 0.0 or price > 3.402823466e38:
					continue
				var ordered_lots: Array = lots.keys()
				ordered_lots.sort()
				for units in ordered_lots:
					var n: int = int(units)
					if n == 0:
						continue
					var estimate: float = ceil(price * float(n))
					if not is_finite(estimate) or estimate >= float(I64_MAX - SUBSIDY_BASE_PAYMENT * 2):
						continue
					var cost: int = int(estimate) + 2 * SUBSIDY_BASE_PAYMENT
					actions.append({"action_id":"htn-preview:deliver:%s:%s:%s:%d" % [
						source_market.get("market_id", ""), dest_market.get("market_id", ""), commodity, n],
						"kind":"deliver", "source_id": source, "destination_id": dest,
						"commodity": commodity, "units": n, "cost_credits": cost,
						"expected_ticks":PROJECTED_DELIVERY_TICKS, "inputs":[], "outputs":[],
						"required_facility_type":null})
	# Backward relevance closure: from the final stock objective through all
	# recipe ingredients and incoming deliveries, to a fixed point.
	if goal_commodity != null:
		var needed: Dictionary = {destination + "|" + str(goal_commodity): true}
		var changed: bool = true
		while changed:
			changed = false
			for action in actions:
				var place: String = str(action["destination_id"])
				if _kind(action) == "produce":
					var relevant: bool = false
					for output in action.get("outputs", []):
						if needed.has(place + "|" + str(output[0])):
							relevant = true
							break
					if relevant:
						for input_pair in action.get("inputs", []):
							var key: String = place + "|" + str(input_pair[0])
							if not needed.has(key):
								needed[key] = true
								changed = true
				elif _kind(action) == "deliver" and needed.has(place + "|" + str(action.get("commodity", ""))):
					var key: String = str(action.get("source_id", "")) + "|" + str(action.get("commodity", ""))
					if not needed.has(key):
						needed[key] = true
						changed = true
		var relevant_actions: Array = []
		for action in actions:
			var place: String = str(action.get("destination_id", ""))
			var relevant: bool = _kind(action) == "deliver" and needed.has(place + "|" + str(action.get("commodity", "")))
			if _kind(action) == "produce":
				for output in action.get("outputs", []):
					if needed.has(place + "|" + str(output[0])):
						relevant = true
						break
			if relevant:
				relevant_actions.append(action)
		actions = relevant_actions
	return {"ok":true, "projected":projected, "actions":_sorted_action_catalogue(actions),
		"market_id":target_market_id}

static func pinned_producer_recipe(snapshot: Dictionary, action: Dictionary) -> Dictionary:
	if _kind(action) != "produce":
		return {}
	var id: String = str(action.get("source_id", ""))
	var loc: String = str(action.get("destination_id", ""))
	var kind: String = str(action.get("required_facility_type", ""))
	if id.is_empty() or not _has_facility(snapshot.get("facilities", []), id, loc, kind):
		return {}
	var markets: Array = _markets_at(snapshot.get("owned_markets", []), loc)
	if markets.size() != 1 or not _has_facility(snapshot.get("facilities", []), str(markets[0].get("facility_id", "")), loc):
		return {}
	var producer: Dictionary = {}
	for f in snapshot.get("facilities", []):
		if str(f.get("facility_id", "")) == id:
			producer = f
			break
	for recipe in snapshot.get("recipes", []):
		if str(recipe.get("facility_type", "")) != str(producer.get("facility_type", "")):
			continue
		if recipe.get("inputs", []) != action.get("inputs", []) or recipe.get("outputs", []) != action.get("outputs", []):
			continue
		var output: Array = recipe.get("outputs", [])
		if output.is_empty() or action.get("commodity") != output[0][0] or int(action.get("units", 0)) != int(output[0][1]):
			continue
		if str(action.get("action_id", "")) != "htn-preview:produce:%s:%s:%s" % [markets[0].get("market_id", ""), id, recipe.get("recipe_id", "")]:
			continue
		return {"facility_id":id, "recipe_id":str(recipe.get("recipe_id", ""))}
	return {}

static func promote_industry_output_goal(snapshot: Dictionary, head_goal: Dictionary) -> Dictionary:
	if not str(head_goal.get("goal_id", "")).begins_with("supply_industry:"):
		return {}
	var result: Dictionary = catalogue(snapshot, str(head_goal.get("destination_id", "")), null)
	if not result.get("ok", false):
		return {}
	var target: Array = _markets_at(result["projected"]["owned_markets"], str(head_goal.get("destination_id", "")))
	if target.is_empty():
		return {}
	var choices: Array = []
	for a in result["actions"]:
		if _kind(a) != "produce" or str(a.get("destination_id", "")) != str(head_goal["destination_id"]):
			continue
		var uses_shortage: bool = false
		for input_pair in a.get("inputs", []):
			if str(input_pair[0]) == str(head_goal.get("commodity", "")) and int(input_pair[1]) > 0:
				uses_shortage = true
		if not uses_shortage or pinned_producer_recipe(result["projected"], a).is_empty():
			continue
		for output in a.get("outputs", []):
			var commodity: String = str(output[0])
			if commodity == str(head_goal.get("commodity", "")) or int(output[1]) == 0:
				continue
			var stock: float = float(target[0].get("stock", {}).get(commodity, 0.0))
			var demand: float = float(target[0].get("demand", {}).get(commodity, 0.0))
			if not is_finite(stock) or not is_finite(demand) or stock < 0.0 or demand <= stock:
				continue
			choices.append({"commodity":commodity,"essential":commodity in ["water","food"],"shortfall":demand-stock})
	choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a["essential"] != b["essential"]: return bool(a["essential"])
		if a["shortfall"] != b["shortfall"]: return float(a["shortfall"]) > float(b["shortfall"])
		return str(a["commodity"]) < str(b["commodity"]))
	if choices.is_empty():
		return {}
	var goal: Dictionary = head_goal.duplicate(true)
	goal["goal_id"] = str(head_goal["goal_id"]) + ":output:" + str(choices[0]["commodity"])
	goal["commodity"] = choices[0]["commodity"]
	goal["target_units"] = PROBE_UNITS
	return goal

static func projected_native_target(stock: int, fixed_target: Variant = null) -> Dictionary:
	if fixed_target != null:
		return {"ok":true,"target":int(fixed_target)} if int(fixed_target) > stock else _fail("native_goal_already_met")
	if stock > 4294967295 - PROBE_UNITS:
		return _fail("target_stock_overflow")
	return {"ok":true,"target":stock + PROBE_UNITS}

static func comparison_case(snapshot: Dictionary, goal: Dictionary) -> Dictionary:
	var result: Dictionary = catalogue(snapshot, str(goal.get("destination_id", "")), goal.get("commodity"))
	if not result.get("ok", false): return result
	var target: Array = _markets_at(result["projected"]["owned_markets"], str(goal.get("destination_id", "")))
	if target.is_empty(): return _fail("destination_market_not_projectable")
	var stock: int = _projectable_stock(target[0], str(goal.get("commodity", "")))
	if stock < 0: return _fail("invalid_destination_stock")
	var new_target: Dictionary = projected_native_target(stock)
	if not new_target.get("ok", false): return new_target
	var projected_goal: Dictionary = goal.duplicate(true)
	projected_goal["target_units"] = new_target["target"]
	result["goal"] = projected_goal
	return result

static func native_candidate_request(snapshot: Dictionary, goal: Dictionary, fixed_target: Variant = null) -> Dictionary:
	## A native candidate is not valid until N155 HTN search returns READY,
	## shared planning/mod.rs::validate_plan verifies it, and N121 receives
	## a fresh physical/funding receipt. No speculative funded order here.
	var result: Dictionary = catalogue(snapshot, str(goal.get("destination_id", "")), goal.get("commodity"))
	if not result.get("ok", false): return result
	var target: Array = _markets_at(result["projected"]["owned_markets"], str(goal.get("destination_id", "")))
	if target.is_empty(): return _fail("destination_market_not_projectable")
	var stock: int = _projectable_stock(target[0], str(goal.get("commodity", "")))
	if stock < 0: return _fail("invalid_destination_stock")
	var next_target: Dictionary = projected_native_target(stock, fixed_target)
	if not next_target.get("ok", false): return next_target
	var projected_goal: Dictionary = goal.duplicate(true)
	projected_goal["target_units"] = next_target["target"]
	result["goal"] = projected_goal
	result["budget"] = {"max_nodes":MAX_SHADOW_NODES,"max_depth":MAX_SHADOW_DEPTH}
	result["dispatchable_kinds"] = ["deliver","produce"]
	return result
