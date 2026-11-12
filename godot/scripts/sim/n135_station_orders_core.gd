extends RefCounted
## N135: Rust strategy/orders.rs durable order contract and read-only views.
## No wallet, cargo, market or contract-board mutation. Dict schema is documented in the bridge.
const MAX_U32 := 4294967295
const MAX_I64 := 9223372036854775807
const PROJECT_TAGS := ["strategy.logistics.v1", "strategy.construction.v1", "strategy.colony.v1"]
const UNASSIGNED_AGE := 180

static func new_order(kind: String, identifier: String) -> Dictionary:
	return {"order_id": "station:%s:%s" % [kind, identifier], "executor_id": "",
		"state": "waiting", "blocked_reason": "", "attempt": 0,
		"assigned_tick": 0, "retry_after_tick": 0}

static func assign(order: Dictionary, ship_id: String, tick: int) -> Dictionary:
	var next := order.duplicate(true)
	next["executor_id"] = ship_id
	next["assigned_tick"] = max(0, tick)
	next["attempt"] = min(MAX_U32, max(0, int(order.get("attempt", 0))) + 1)
	next["state"] = "assigned"
	next["blocked_reason"] = ""
	return next

static func release(order: Dictionary, reason: String, tick: int, cooldown: int) -> Dictionary:
	var next := order.duplicate(true)
	next["executor_id"] = ""
	next["state"] = "blocked"
	next["blocked_reason"] = reason
	next["retry_after_tick"] = _saturating_tick(tick, cooldown)
	return next

static func _saturating_tick(tick: int, increment: int) -> int:
	var t: int = max(0, tick)
	var add: int = max(0, increment)
	return MAX_I64 if add > MAX_I64 - t else t + add

static func _funding(contract: Dictionary) -> Dictionary:
	var value = contract.get("funding")
	return value if value is Dictionary else {}

static func order_of(contract: Dictionary) -> Dictionary:
	var funding := _funding(contract)
	var order = funding.get("station_order")
	return order if order is Dictionary else {}

static func fixed_strategy_reward(contract: Dictionary) -> int:
	var funding := _funding(contract)
	if funding.get("source", "") == "Faction" and str(contract.get("mission_category", "")) in PROJECT_TAGS:
		return int(contract.get("initial_payment", -1))
	return -1

static func facility_relief(contract: Dictionary, tick: int) -> bool:
	var funding := _funding(contract)
	return str(contract.get("status", "")) == "Posted" and str(contract.get("contract_type", "")) == "Delivery" \
		and str(contract.get("faction_id", "")) != "" and funding.get("source", "") == "Facility" \
		and int(funding.get("reserved", 0)) > 0 \
		and max(0, tick - int(contract.get("posted_at_tick", tick))) >= UNASSIGNED_AGE

static func facility_order(contract: Dictionary) -> bool:
	var funding := _funding(contract)
	return str(contract.get("contract_type", "")) == "Delivery" and funding.get("source", "") == "Facility" \
		and funding.get("station_order") is Dictionary

static func top_up(contract: Dictionary, payment: int) -> int:
	var funding := _funding(contract)
	var reserved: int = int(funding.get("reserved", -1))
	if reserved < 0 or payment < 0:
		return -1
	var required: int = max(0, payment - reserved)
	if required > 0 and fixed_strategy_reward(contract) >= 0:
		return -1
	return required

static func funded_for_dispatch(contract: Dictionary, tick: int) -> bool:
	var funding := _funding(contract)
	if facility_order(contract) or facility_relief(contract, tick):
		return funding.get("source", "") == "Facility" and int(funding.get("reserved", 0)) > 0
	var reward := fixed_strategy_reward(contract)
	return reward >= 0 and top_up(contract, reward) == 0

static func may_accept(contract: Dictionary, ship: String, faction: String) -> bool:
	var order := order_of(contract)
	if order.is_empty():
		return true # Rust legacy public contract branch, not an order.
	var funding := _funding(contract)
	if funding.get("source", "") == "Facility" and str(order.get("executor_id", "")) == "":
		return true # A blocked facility order does not monopolize public contracts.
	return str(contract.get("faction_id", "")) == faction and str(order.get("executor_id", "")) == ship

static func assigned_contract(contracts: Array, ship: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for raw in contracts:
		var c: Dictionary = raw
		if str(c.get("status", "")) in ["Posted", "Accepted", "PickedUp"] \
			and str(order_of(c).get("executor_id", "")) == ship:
			candidates.append(c)
	candidates.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return candidates[0] if not candidates.is_empty() else {}

static func builder_assigned(sites: Array, ship: String) -> bool:
	for raw in sites:
		var site: Dictionary = raw
		var labor: Dictionary = site.get("labor", {})
		var order = labor.get("station_order")
		if not bool(site.get("completed", false)) \
			and int(labor.get("completed", 0)) < int(labor.get("required", 0)) \
			and order is Dictionary and str(order.get("executor_id", "")) == ship:
			return true
	return false

static func contract_ids(contracts: Array, tick: int, known_ships: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw in contracts:
		var c: Dictionary = raw
		if fixed_strategy_reward(c) < 0 and not facility_relief(c, tick) and not facility_order(c):
			continue
		if order_of(c).is_empty() and str(c.get("fulfiller_id", "")) != "":
			var valid := false
			for s in known_ships:
				if str(s.get("id", "")) == str(c.get("fulfiller_id", "")) and str(s.get("faction", "")) == str(c.get("faction_id", "")):
					valid = true
			if not valid:
				continue
		ids.append(str(c.get("id", "")))
	var lookup := {}
	for c in contracts:
		lookup[str(c.get("id", ""))] = c
	ids.sort_custom(func(a, b):
		var x: Dictionary = lookup.get(a, {})
		var y: Dictionary = lookup.get(b, {})
		var ap := _contract_priority(x)
		var bp := _contract_priority(y)
		return ap < bp if ap != bp else a < b
	)
	return ids

static func _contract_priority(contract: Dictionary) -> int:
	if str(contract.get("contract_type", "")) == "Passenger":
		return 1
	if str(contract.get("commodity", "")).to_lower() in ["food", "water"]:
		return 0
	return 2

static func _view_contract(contract: Dictionary) -> Dictionary:
	var order := order_of(contract)
	if order.is_empty():
		return {}
	var state := str(contract.get("status", ""))
	var view := order.duplicate(true)
	if state == "Paid":
		view["state"] = "completed"
		view["blocked_reason"] = ""
	elif state == "Expired":
		view["state"] = "cancelled"
		view["blocked_reason"] = "contract_expired"
	elif state in ["Accepted", "PickedUp", "Delivered"]:
		view["state"] = "executing"
	var passenger := str(contract.get("contract_type", "")) == "Passenger"
	view.merge({"faction_id": str(contract.get("faction_id", "")),
		"location": str(contract.get("destination_location", "")),
		"kind": "passenger" if passenger else "delivery",
		"target_id": str(contract.get("id", "")),
		"commodity": "" if passenger else str(contract.get("commodity", "")),
		"quantity": int(contract.get("quantity", 0)),
		"completed_quantity": int(contract.get("quantity", 0)) if state == "Paid" else 0}, true)
	return view

static func snapshot(contracts: Array, sites: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in contracts:
		var item := _view_contract(c)
		if not item.is_empty():
			out.append(item)
	for site in sites:
		var labor: Dictionary = site.get("labor", {})
		var order = labor.get("station_order")
		if not (order is Dictionary):
			continue
		var entry: Dictionary = order.duplicate(true)
		entry.merge({"faction_id": str(site.get("faction_id", "")),
			"location": str(site.get("location_name", "")),
			"kind": "construction", "target_id": str(site.get("id", "")),
			"commodity": "", "quantity": int(labor.get("required", 0)),
			"completed_quantity": int(labor.get("completed", 0))}, true)
		out.append(entry)
	out.sort_custom(func(a, b): return str(a.get("order_id", "")) < str(b.get("order_id", "")))
	return out
