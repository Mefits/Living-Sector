extends RefCounted
## N81: pure native ai/planner.rs Dijkstra; emits ShipAction-shaped intents, never applies them.
const ORIGIN := "Origin"
const SOURCE := "Source"
const DEST := "Dest"
const SHIPYARD := "Shipyard"

static func initial(at: String = ORIGIN, fuel_bucket: int = 10) -> Dictionary:
	return {"at": at, "docked": false, "fuel_bucket": clampi(fuel_bucket, 0, 10),
		"cargo_loaded": false, "delivered": false, "sold": false,
		"retrofitted": false, "rested": false}

static func fuel_fraction_to_bucket(value: float) -> int:
	if not is_finite(value) or value <= 0.0:
		return 0
	return clampi(int(floor(value * 10.0 + 0.5)), 0, 10)

static func catalog(kind: String) -> Array:
	var actions: Array = ["Dock", "Refuel"]
	match kind:
		"delivery": actions.append_array(["Buy", "DeliverCargo", "Refit"])
		"trade": actions.append_array(["Buy", "SellAll", "Refit"])
		"passenger": actions.append_array(["EmbarkPassengers", "DeliverPassengers"])
		"retrofit": actions.append("Refit")
		"crew_mission": actions.append_array(["Rest", "DeliverPassengers"])
		"rest_crew": actions.append("Rest")
		_: return []
	actions.append("Undock")
	actions.append("Travel:Origin")
	if kind in ["delivery", "trade", "passenger"]:
		actions.append("Travel:Source")
	if kind != "retrofit":
		actions.append("Travel:Dest")
	if kind in ["delivery", "trade", "retrofit"]:
		actions.append("Travel:Shipyard")
	return actions

static func _real_location(role: String, map: Dictionary) -> String:
	return str(map.get(role.to_lower(), ""))

static func _edge_cost(a: String, b: String, map: Dictionary) -> int:
	if a == b:
		return 0
	var pair: Array = [a.to_lower(), b.to_lower()]
	pair.sort()
	return int(map.get("cost_" + pair[0] + "_to_" + pair[1], map.get("cost_" + pair[1] + "_to_" + pair[0], 0)))

static func _apply(state: Dictionary, op: String, map: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var at: String = state.at
	var docked: bool = state.docked
	var intent: Dictionary = {"type": op}
	var cost := 1
	if op.begins_with("Travel:"):
		var to := op.substr(7)
		if docked or at == to:
			return {}
		var src := _real_location(at, map)
		var dst := _real_location(to, map)
		if src.is_empty() or dst.is_empty():
			return {}
		cost = _edge_cost(at, to, map)
		if src != dst and cost <= 0:
			return {}
		if state.fuel_bucket < cost:
			return {}
		next.at = to
		next.fuel_bucket -= cost
		intent = {"type": "Travel", "destination": dst}
	elif op == "Dock":
		if docked:
			return {}
		next.docked = true
		intent.type = "DockAtShipyard" if at == SHIPYARD else "Dock"
	elif op == "Undock":
		if not docked:
			return {}
		next.docked = false
	elif op == "Refuel":
		if not docked or state.fuel_bucket >= 10:
			return {}
		next.fuel_bucket = 10
	elif op == "Buy":
		if not docked or at != SOURCE or state.cargo_loaded:
			return {}
		next.cargo_loaded = true
		intent = {"type": "Buy", "commodity": map.get("commodity", ""), "qty": int(map.get("quantity", 0))}
	elif op == "SellAll":
		if not docked or at != DEST or not state.cargo_loaded:
			return {}
		next.cargo_loaded = false
		next.sold = true
	elif op == "DeliverCargo":
		if not docked or at != DEST or not state.cargo_loaded or str(map.get("contract_id", "")).is_empty():
			return {}
		next.cargo_loaded = false
		next.delivered = true
		intent.contract_id = map.contract_id
	elif op == "Rest":
		if not docked or state.rested:
			return {}
		next.rested = true
	elif op == "EmbarkPassengers":
		if not docked or at != SOURCE or state.cargo_loaded or int(map.get("quantity", 0)) == 0:
			return {}
		next.cargo_loaded = true
		intent.contract_id = map.get("contract_id", "")
	elif op == "DeliverPassengers":
		if not docked or at != DEST or state.delivered or str(map.get("contract_id", "")).is_empty():
			return {}
		if int(map.get("quantity", 0)) > 0 and not state.cargo_loaded:
			return {}
		next.delivered = true
		intent = {"type": "DeliverCargo", "contract_id": map.contract_id}
	elif op == "Refit":
		if not docked or at != SHIPYARD or state.retrofitted or not map.has("refit_slot") or not map.has("refit_slug"):
			return {}
		next.retrofitted = true
		intent = {"type": "Refit", "slot": map.refit_slot, "slug": map.refit_slug}
	else:
		return {}
	return {"state": next, "action": intent, "cost": cost}

static func _key(s: Dictionary) -> String:
	return JSON.stringify([s.at, s.docked, s.fuel_bucket, s.cargo_loaded, s.delivered, s.sold, s.retrofitted, s.rested])

static func _goal(s: Dictionary, kind: String, min_fuel: int) -> bool:
	match kind:
		"delivery": return s.delivered and s.fuel_bucket >= min_fuel
		"trade": return s.sold and s.fuel_bucket >= min_fuel
		"passenger": return s.delivered and s.fuel_bucket >= min_fuel
		"retrofit": return s.retrofitted and s.fuel_bucket >= min_fuel
		"crew_mission": return s.delivered and s.rested and s.fuel_bucket >= min_fuel
		"rest_crew": return s.rested and not s.docked and s.at == DEST and s.fuel_bucket >= min_fuel
	return false

static func plan(start: Dictionary, kind: String, map: Dictionary, max_depth: int = 16, min_fuel: int = 0) -> Dictionary:
	var ops := catalog(kind)
	if ops.is_empty() or max_depth < 0:
		return {}
	var frontier: Array = [{"state": start.duplicate(true), "actions": [], "cost": 0, "order": 0}]
	var best: Dictionary = {_key(start): 0}
	var order := 0
	while not frontier.is_empty():
		# Stable insertion-order tie-break: Rust heap compares cost only.
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.cost < b.cost if a.cost != b.cost else a.order < b.order)
		var entry: Dictionary = frontier.pop_front()
		var state: Dictionary = entry.state
		if _goal(state, kind, min_fuel):
			return {"actions": entry.actions, "final_state": state, "cost": entry.cost}
		if entry.cost > int(best.get(_key(state), 2147483647)) or entry.actions.size() >= max_depth:
			continue
		for op in ops:
			var applied := _apply(state, op, map)
			if applied.is_empty():
				continue
			var next: Dictionary = applied.state
			var new_cost: int = entry.cost + int(applied.cost)
			var key := _key(next)
			if new_cost >= int(best.get(key, 2147483647)):
				continue
			best[key] = new_cost
			var actions: Array = entry.actions.duplicate()
			actions.append(applied.action)
			order += 1
			frontier.append({"state": next, "actions": actions, "cost": new_cost, "order": order})
	return {}
