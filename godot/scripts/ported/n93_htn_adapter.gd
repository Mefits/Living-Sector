extends RefCounted
## Rust: strategy/planning/htn_adapter.rs. Bounded hypothetical stock planning.
## No ECS writes; execution and upstream htn 0.2.1 verification remain external.

static func _invalid(goal: Dictionary, status: String, reason: String, nodes: int = 0) -> Dictionary:
	return {"status":status, "goal_id":goal.get("goal_id", ""), "planner_id":"htn_0_2_1_shadow",
		"steps":[], "forecast_credits":0, "forecast_ticks":0, "nodes_expanded":nodes, "explanation":reason}

static func plan(snapshot: Dictionary, goal: Dictionary, catalogue: Array, max_nodes: int = 12000, max_depth: int = 22) -> Dictionary:
	if max_nodes <= 0 or max_depth <= 0:
		return _invalid(goal, "BudgetExhausted", "search budget is zero")
	var markets: Array = snapshot.get("owned_markets", [])
	var locations := {}
	for market in markets:
		var location := str(market.get("location_id", ""))
		if location.is_empty() or locations.has(location):
			return _invalid(goal, "InvalidSnapshot", "ambiguous market location")
		locations[location] = market.get("stock", {}).duplicate(true)
	var destination := str(goal.get("destination_id", ""))
	var commodity := str(goal.get("commodity", ""))
	if not locations.has(destination) or commodity.is_empty():
		return _invalid(goal, "InvalidSnapshot", "missing goal market")
	var target := int(goal.get("target_units", 0))
	if target <= 0:
		return _invalid(goal, "InvalidSnapshot", "invalid goal quantity")
	var initial := {}
	for location in locations:
		for item in locations[location]:
			var amount := float(locations[location][item])
			if not is_finite(amount) or amount < 0.0:
				return _invalid(goal, "InvalidSnapshot", "invalid stock")
			initial[str(location) + "|" + str(item)] = int(floorf(amount))
	var spendable := int(snapshot.get("treasury_credits", 0)) - int(snapshot.get("treasury_floor_credits", 0))
	if spendable < 0:
		return _invalid(goal, "InvalidSnapshot", "treasury below floor")
	initial["$cash"] = spendable
	var goal_key := destination + "|" + commodity
	if int(initial.get(goal_key, 0)) >= target:
		return _invalid(goal, "NoPlan", "goal already satisfied")
	var recipes: Array = snapshot.get("recipes", [])
	var facilities: Array = snapshot.get("facilities", [])
	var ships: Array = snapshot.get("ships", [])
	var commitments: Array = snapshot.get("active_commitments", [])
	var committed := {}
	for c in commitments:
		committed[str(c.get("assigned_ship_id", ""))] = true
	var actions := []
	for spec in catalogue:
		var kind := str(spec.get("kind", ""))
		if kind != "Deliver" and kind != "Produce":
			continue
		var cost := int(spec.get("cost_credits", -1))
		if cost < 0 or cost > spendable or int(spec.get("units", 0)) <= 0:
			continue
		var place := str(spec.get("destination_id", ""))
		if not locations.has(place):
			continue
		var delta := {"$cash":-cost}
		if kind == "Deliver":
			var source := str(spec.get("source_id", ""))
			var item := str(spec.get("commodity", ""))
			var units := int(spec.get("units", 0))
			if source == place or not locations.has(source):
				continue
			var eligible := false
			for ship in ships:
				if ship.get("location_id", "") == source and not ship.get("in_transit", true) and not committed.has(str(ship.get("ship_id", ""))) and int(ship.get("free_cargo", 0)) >= units and float(ship.get("fuel", 0.0)) > 0.0:
					eligible = true
			if not eligible:
				continue
			delta[source + "|" + item] = -units
			delta[place + "|" + item] = units
			delta["$departure:" + source] = -1
		else:
			var recipe_found := false
			for recipe in recipes:
				if recipe.get("recipe_id", "") != spec.get("recipe_id", ""):
					continue
				for facility in facilities:
					if facility.get("location_id", "") == place and facility.get("facility_type", "") == recipe.get("facility_type", ""):
						recipe_found = true
			if not recipe_found:
				continue
			for input in spec.get("inputs", []):
				var key := place + "|" + str(input[0])
				delta[key] = int(delta.get(key, 0)) - int(input[1])
			for output in spec.get("outputs", []):
				var key := place + "|" + str(output[0])
				delta[key] = int(delta.get(key, 0)) + int(output[1])
		actions.append({"spec":spec, "delta":delta})
	for location in locations:
		var count := 0
		for ship in ships:
			if ship.get("location_id", "") == location and not ship.get("in_transit", true) and not committed.has(str(ship.get("ship_id", ""))) and int(ship.get("free_cargo", 0)) > 0 and float(ship.get("fuel", 0.0)) > 0.0:
				count += 1
		initial["$departure:" + str(location)] = count
	var frontier := [{"state":initial, "path":[], "cost":0, "ticks":0}]
	var seen := {}
	var nodes := 0
	while not frontier.is_empty() and nodes < max_nodes:
		var node: Dictionary = frontier.pop_back()
		var state: Dictionary = node["state"]
		var key := JSON.stringify(state)
		if seen.has(key):
			continue
		seen[key] = true
		nodes += 1
		if int(state.get(goal_key, 0)) >= target:
			var steps := []
			var path: Array = node["path"]
			for i in range(path.size()):
				var spec: Dictionary = path[i]
				steps.append({"step_id":"htn-%03d" % (i+1), "action_id":spec.get("action_id", ""),
					"depends_on":[] if i == 0 else ["htn-%03d" % i],
					"expected_condition":"native_receipt_then_recheck_physical_stock"})
			return {"status":"Ready", "goal_id":goal.get("goal_id", ""), "planner_id":"htn_0_2_1_shadow",
				"steps":steps, "forecast_credits":node["cost"], "forecast_ticks":node["ticks"],
				"nodes_expanded":nodes, "explanation":"hypothetical plan; upstream HTN verification and native dispatch required"}
		if node["path"].size() >= max_depth:
			continue
		for i in range(actions.size()-1, -1, -1):
			var action: Dictionary = actions[i]
			var delta: Dictionary = action["delta"]
			var valid := true
			var next := state.duplicate(true)
			for field in delta:
				var updated := int(next.get(field, 0)) + int(delta[field])
				if updated < 0:
					valid = false
					break
				next[field] = updated
			if not valid:
				continue
			var path: Array = node["path"].duplicate()
			path.append(action["spec"])
			frontier.append({"state":next, "path":path,
				"cost":int(node["cost"]) + int(action["spec"].get("cost_credits", 0)),
				"ticks":int(node["ticks"]) + int(action["spec"].get("expected_ticks", 0))})
	return _invalid(goal, "BudgetExhausted" if nodes >= max_nodes else "NoPlan", "no valid decomposition within budget", nodes)
