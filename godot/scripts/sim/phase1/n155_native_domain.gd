extends RefCounted
## Frozen strategy/planning/htn_adapter.rs::domain_from_native (95..237).
## Corrects N93's ungrounded string-delta BFS; no world mutations.
const Catalogue = preload("res://scripts/sim/phase1/n155_native_catalogue.gd")
const I32_MAX := 2147483647
const I32_MIN := -2147483648

static func _err(reason: String) -> Dictionary:
	return {"ok":false,"error":reason}

static func _key(loc: String, item: String) -> String:
	return str(loc.to_utf8_buffer().size()) + ":" + loc + ":" + item

static func _pair_sorted(pairs: Array) -> Array:
	var a: Array = pairs.duplicate(true)
	a.sort_custom(func(x: Array,y: Array) -> bool: return str(x[0]) < str(y[0]))
	return a

static func _catalogue_is_recipe(snapshot: Dictionary, spec: Dictionary) -> bool:
	var kind: String = str(spec.get("required_facility_type", ""))
	var location: String = str(spec.get("destination_id", ""))
	if kind.is_empty():
		return false
	var pinned: Variant = spec.get("source_id", null)
	var exists: bool = false
	for f in snapshot.get("facilities", []):
		if str(f.get("location_id", "")) == location and str(f.get("facility_type", "")) == kind:
			if pinned == null or str(pinned) == str(f.get("facility_id", "")):
				exists = true
				break
	if not exists:
		return false
	var inputs: Array = _pair_sorted(spec.get("inputs", []))
	var outputs: Array = _pair_sorted(spec.get("outputs", []))
	for recipe in snapshot.get("recipes", []):
		if str(recipe.get("facility_type", "")) == kind:
			if _pair_sorted(recipe.get("inputs", [])) == inputs and _pair_sorted(recipe.get("outputs", [])) == outputs:
				return true
	return false

static func _valid_i32(v: int) -> bool:
	return v >= I32_MIN and v <= I32_MAX

static func _set_delta(delta: Dictionary, field: int, amount: int) -> bool:
	var before: int = int(delta.get(field, 0))
	# Avoid signed overflow and Rust i32::checked_add/sub.
	if not _valid_i32(amount) or not _valid_i32(before + amount):
		return false
	delta[field] = before + amount
	return true

static func domain_from_native(snapshot: Dictionary, goal: Dictionary, catalogue: Array) -> Dictionary:
	## Result matches Rust NativeDomain {fields,initial,goal_field,
	## goal_amount,actions} and pre/delta typed pairs. No paid shift.
	if int(snapshot.get("schema_version", 0)) != 1 or str(snapshot.get("faction_id", "")).is_empty() or str(goal.get("destination_id", "")).is_empty() or int(goal.get("target_units", 0)) <= 0:
		return _err("invalid_snapshot_or_goal")
	var floor_value: int = maxi(0, int(snapshot.get("treasury_floor_credits", 0)))
	var spendable: int = maxi(0, int(snapshot.get("treasury_credits", 0)) - floor_value)
	if spendable > I32_MAX:
		return _err("credits_out_of_i32_range")
	var target_amount: int = int(goal.get("target_units", 0))
	if target_amount > I32_MAX:
		return _err("goal_out_of_i32_range")
	var by_location: Dictionary = {}
	for m in snapshot.get("owned_markets", []):
		var loc: String = str(m.get("location_id", ""))
		if loc.is_empty() or by_location.has(loc):
			return _err("ambiguous_market_location")
		var stock: Dictionary = {}
		for item in Catalogue.GOODS:
			var amount: float = float(m.get("stock", {}).get(item, 0.0))
			if not is_finite(amount) or amount < 0.0 or floor(amount) > float(I32_MAX):
				return _err("invalid_stock")
			stock[item] = int(floor(amount))
		by_location[loc] = stock
	var destination: String = str(goal.get("destination_id", ""))
	if not by_location.has(destination):
		return _err("goal_market_not_owned_or_missing")
	var fields: Array = []
	var initial: Array = []
	var indices: Dictionary = {}
	var locs: Array = by_location.keys()
	locs.sort()
	for loc in locs:
		for item in Catalogue.GOODS:
			indices[_key(str(loc), item)] = fields.size()
			fields.append("market:%s:%s" % [str(loc.to_utf8_buffer().size()) + ":" + str(loc), item])
			initial.append(int(by_location[loc][item]))
	var cash_field: int = fields.size()
	fields.append("credits_spendable_after_treasury_floor")
	initial.append(spendable)
	var goal_field: int = int(indices[_key(destination, str(goal.get("commodity", "")))]) if indices.has(_key(destination, str(goal.get("commodity", "")))) else -1
	if goal_field < 0:
		return _err("unknown_goal_commodity")
	var committed: Dictionary = {}
	for c in snapshot.get("active_commitments", []):
		if c.get("assigned_ship_id", null) != null:
			committed[str(c["assigned_ship_id"])] = true
	var source_slots: Dictionary = {}
	for loc in locs:
		var eligible: int = 0
		for ship in snapshot.get("ships", []):
			var fuel: float = float(ship.get("fuel", 0.0))
			if ship.get("location_id", null) == loc and not bool(ship.get("in_transit", false)) and not committed.has(str(ship.get("ship_id", ""))) and int(ship.get("free_cargo", 0)) > 0 and is_finite(fuel) and fuel > 0.0:
				eligible += 1
		if eligible > I32_MAX:
			return _err("too_many_available_carriers")
		source_slots[loc] = fields.size()
		fields.append("available_departures:%s:%s" % [loc.to_utf8_buffer().size(), loc])
		initial.append(eligible)
	var actions: Array = []
	var seen: Dictionary = {}
	for catalogue_index in range(catalogue.size()):
		var spec: Dictionary = catalogue[catalogue_index]
		var action_id: String = str(spec.get("action_id", ""))
		var cost: int = int(spec.get("cost_credits", -1))
		var units: int = int(spec.get("units", 0))
		var loc: String = str(spec.get("destination_id", ""))
		if action_id.is_empty() or seen.has(action_id) or cost < 0 or units <= 0 or loc.is_empty():
			continue
		seen[action_id] = true
		if cost > I32_MAX or cost > spendable:
			continue
		var delta: Dictionary = {}
		var ok: bool = true
		var kind: String = str(spec.get("kind", "")).to_lower()
		match kind:
			"deliver":
				var source: String = str(spec.get("source_id", ""))
				var commodity: String = str(spec.get("commodity", ""))
				if source == loc or not indices.has(_key(source, commodity)) or not indices.has(_key(loc, commodity)) or units > I32_MAX:
					continue
				var carrier: bool = false
				for ship in snapshot.get("ships", []):
					var fuel: float = float(ship.get("fuel", 0.0))
					if ship.get("location_id", null) == source and not bool(ship.get("in_transit", false)) and not committed.has(str(ship.get("ship_id", ""))) and int(ship.get("free_cargo", 0)) >= units and is_finite(fuel) and fuel > 0.0:
						carrier = true
						break
				if not carrier or not source_slots.has(source):
					continue
				ok = _set_delta(delta, int(source_slots[source]), -1)
				ok = _set_delta(delta, int(indices[_key(source, commodity)]), -units) and ok
				ok = _set_delta(delta, int(indices[_key(loc, commodity)]), units) and ok
			"produce":
				if not _catalogue_is_recipe(snapshot, spec):
					continue
				for input_pair in spec.get("inputs", []):
					var key: String = _key(loc, str(input_pair[0]))
					var amount: int = int(input_pair[1])
					if amount <= 0 or amount > I32_MAX or not indices.has(key):
						ok = false
						break
					ok = _set_delta(delta, int(indices[key]), -amount) and ok
				if not ok: continue
				for output in spec.get("outputs", []):
					var key: String = _key(loc, str(output[0]))
					var amount: int = int(output[1])
					if amount <= 0 or amount > I32_MAX or not indices.has(key):
						ok = false
						break
					ok = _set_delta(delta, int(indices[key]), amount) and ok
			_:
				# No ungrounded Construct/Research/FoundColony stock effects.
				continue
		if not ok:
			continue
		var nonzero: bool = false
		for d in delta.values():
			if int(d) != 0:
				nonzero = true
		if not nonzero:
			continue
		if cost > 0 and not _set_delta(delta, cash_field, -cost):
			continue
		var keys: Array = delta.keys()
		keys.sort()
		var pre: Array = []
		var delta_pairs: Array = []
		for field in keys:
			var effect: int = int(delta[field])
			if effect < 0:
				pre.append([field, -effect])
			delta_pairs.append([field, effect])
		actions.append({"catalogue_index":catalogue_index, "pre":pre, "delta":delta_pairs})
	return {"ok":true,"fields":fields,"initial":initial,
		"goal_field":goal_field,"goal_amount":target_amount,"actions":actions}

static func action_effect(action: Dictionary, field: int) -> int:
	for delta in action.get("delta", []):
		if int(delta[0]) == field:
			return int(delta[1])
	return 0

static func apply(state: Array, action: Dictionary) -> Array:
	## Rust NativeAction::apply: preconditions precede effects, exact checked
	## i32 addition then reject negative stock/treasury/departure count.
	for req in action.get("pre", []):
		var f: int = int(req[0])
		if f < 0 or f >= state.size() or int(state[f]) < int(req[1]):
			return []
	var after: Array = state.duplicate()
	for effect in action.get("delta", []):
		var f: int = int(effect[0])
		if f < 0 or f >= after.size():
			return []
		var next: int = int(after[f]) + int(effect[1])
		if next < 0 or next > I32_MAX:
			return []
		after[f] = next
	return after
