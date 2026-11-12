extends RefCounted
## N135 frozen native strategy/orders.rs dispatch. All state transitions are STAGED.
## Input uses authoritative plain snapshots (see N135 bridge), output must be atomically
## committed with the ContractBoard and world by the future Phase-2 exclusive owner.
const Core = preload("res://scripts/sim/n135_station_orders_core.gd")
const BASE_VELOCITY := 0.05
const SENSOR_INTERSTELLAR := 2.0
const BASE_PRICES := {"ore":15.0,"ice":10.0,"gas":20.0,"rare_ore":75.0,"crystal_ore":140.0,"metals":45.0,"fuel":25.0,"polymers":40.0,"water":12.0,"alloys":145.0,"components":80.0,"electronics":120.0,"quantum_cores":320.0,"tools":90.0,"food":18.0,"medical":100.0,"luxury":150.0}
const MAX_I64 := 9223372036854775807

static func _treaty(relations: Dictionary, from_id: String, to_id: String) -> String:
	if from_id == "" or to_id == "" or from_id == to_id:
		return "Neutral"
	var record = relations.get(from_id, {})
	if record is Dictionary:
		return str(record.get(to_id, "Neutral"))
	return "Neutral"

static func _commerce(relations: Dictionary, from_id: String, owner: String) -> bool:
	return _treaty(relations, from_id, owner) not in ["Hostile", "War"]

static func _payment_multiplier(relations: Dictionary, from_id: String, requestor: String) -> float:
	var treaty := _treaty(relations, from_id, requestor)
	if treaty == "TradePact":
		return 1.10
	if treaty == "Allied":
		return 1.15
	return 1.0

static func _market_buy_multiplier(relations: Dictionary, faction: String, reputation: int, owner: String) -> float:
	var rep := 50 if owner == "" else (100 if owner == faction and faction != "" else clampi(reputation, 0, 100))
	var base: float = clampf(1.0 + (50.0 - float(rep)) * 0.005, 0.75, 1.25)
	if _treaty(relations, faction, owner) in ["Hostile", "War"] and base > 1.0:
		return 1.0 + (base - 1.0) * 2.0
	return base

static func _market(snapshot: Dictionary, location: String) -> Dictionary:
	var markets: Dictionary = snapshot.get("markets", {})
	var market = markets.get(location)
	return market if market is Dictionary else {}

static func _price(market: Dictionary, commodity: String) -> float:
	var prices: Dictionary = market.get("prices", {})
	return float(prices.get(commodity, BASE_PRICES.get(commodity, NAN)))

static func _stock(market: Dictionary, commodity: String) -> float:
	var supply: Dictionary = market.get("supply", {})
	return float(supply.get(commodity, 0.0))

static func _has_stock(market: Dictionary, commodity: String, quantity: int) -> bool:
	var stock := _stock(market, commodity)
	return is_finite(stock) and stock >= float(quantity) and quantity > 0

static func _purchase_cost(snapshot: Dictionary, ship: Dictionary, source: String, commodity: String, quantity: int) -> int:
	var market := _market(snapshot, source)
	if market.is_empty() or quantity <= 0:
		return -1
	var price := _price(market, commodity)
	if not is_finite(price) or price <= 0.0:
		return -1
	var owner := str(snapshot.get("owners", {}).get(source, ""))
	var rep := int(ship.get("reputation", {}).get(owner, 0))
	var multiplier := _market_buy_multiplier(snapshot.get("relations", {}), str(ship.get("faction", "")), rep, owner)
	var cost := ceil(float(price * multiplier) * float(quantity))
	return -1 if not is_finite(cost) or cost >= float(MAX_I64) else int(cost)

static func _acceptance_payment(snapshot: Dictionary, contract: Dictionary, ship: Dictionary) -> int:
	var fixed := Core.fixed_strategy_reward(contract)
	if fixed >= 0:
		return fixed
	var payment: int = int(contract.get("payment", -1))
	if payment < 0:
		return -1
	var comms: float = float(ship.get("comms_bonus", 0.0))
	var treaty := _payment_multiplier(snapshot.get("relations", {}), str(ship.get("faction", "")), str(contract.get("faction_id", "")))
	var reward := round(float(payment) * (1.0 + comms) * treaty)
	return -1 if not is_finite(reward) or reward < 0.0 or reward >= float(MAX_I64) else int(reward)

static func _distance(snapshot: Dictionary, source: String, destination: String) -> int:
	if source == destination and source != "":
		return 0
	var routes: Dictionary = snapshot.get("distances", {})
	var from_routes = routes.get(source)
	if not from_routes is Dictionary or not from_routes.has(destination):
		return -1
	var steps: int = int(from_routes[destination])
	return steps if steps >= 0 else -1

static func _route(snapshot: Dictionary, ship_location: String, source: String, destination: String) -> int:
	var to_source := _distance(snapshot, ship_location, source)
	var to_destination := _distance(snapshot, source, destination)
	return -1 if to_source < 0 or to_destination < 0 else min(2147483647, to_source + to_destination)

static func _reachable(snapshot: Dictionary, target: String, speed: float) -> bool:
	var locations: Dictionary = snapshot.get("locations", {})
	var place = locations.get(target)
	if not place is Dictionary:
		return false
	var orbit = snapshot.get("orbits", {}).get(place.get("body_id"))
	if not orbit is Dictionary:
		return false
	var period := float(orbit.get("orbit_period", 0.0))
	if period <= 0.0 or speed <= 0.0:
		return false
	return TAU * float(orbit.get("orbit_radius", 0.0)) / period < BASE_VELOCITY * speed

static func _sensors_allow(snapshot: Dictionary, ship: Dictionary, contract: Dictionary) -> bool:
	if float(ship.get("sensors", 1.0)) >= SENSOR_INTERSTELLAR:
		return true
	var locations: Dictionary = snapshot.get("locations", {})
	var here = locations.get(str(ship.get("location", "")))
	var src = locations.get(str(contract.get("source_location", "")))
	var dst = locations.get(str(contract.get("destination_location", "")))
	if not here is Dictionary or not src is Dictionary or not dst is Dictionary:
		return false
	var sys := str(here.get("system", ""))
	return sys != "" and sys == str(src.get("system", "")) and sys == str(dst.get("system", ""))

static func _carrier_free(ship: Dictionary) -> int:
	# The preflight snapshot must contain a real ShipCargo free() or its operands.
	if ship.has("cargo_free"):
		return maxi(0, int(ship["cargo_free"]))
	if ship.has("cargo_capacity") and ship.has("cargo_used"):
		return maxi(0, int(ship["cargo_capacity"]) - int(ship["cargo_used"]))
	return -1

static func _valid_ship(ship: Dictionary) -> bool:
	# Missing authoritative transaction/transit/cargo data MUST NOT imply that
	# a ship is idle, rich or empty. Required by Rust ShipIdentity/Position/Transit.
	for field in ["id", "faction", "class", "location", "credits", "fuel_fraction",
		"speed", "in_transit", "active_contract_id", "transaction_pending",
		"reputation", "sensors", "comms_bonus", "cargo_used"]:
		if not ship.has(field):
			return false
	return (ship.get("reputation") is Dictionary) and _carrier_free(ship) >= 0

static func _carrier_busy(ship: Dictionary, galaxy: bool) -> bool:
	return bool(ship.get("in_transit", false)) or str(ship.get("active_contract_id", "")) != "" \
		or bool(ship.get("transaction_pending", false)) or (not galaxy and int(ship.get("cargo_used", 0)) > 0)

static func _rank_better(candidate: Dictionary, existing: Dictionary) -> bool:
	if existing.is_empty():
		return true
	if bool(candidate.get("low_fuel", false)) != bool(existing.get("low_fuel", false)):
		return not bool(candidate.get("low_fuel", false))
	if int(candidate.get("distance", 0)) != int(existing.get("distance", 0)):
		return int(candidate.get("distance", 0)) < int(existing.get("distance", 0))
	return str(candidate.get("ship_id", "")) < str(existing.get("ship_id", ""))

static func _contract_carrier(snapshot: Dictionary, contract: Dictionary, source: String, facility: bool, used: Dictionary, ships: Array) -> Dictionary:
	var faction := str(contract.get("faction_id", ""))
	var source_owner := str(snapshot.get("owners", {}).get(source, ""))
	var target := str(contract.get("destination_location", ""))
	var dest_owner := str(snapshot.get("owners", {}).get(target, ""))
	var qty := int(contract.get("quantity", 0))
	var kind := str(contract.get("contract_type", ""))
	var market := _market(snapshot, source)
	var best: Dictionary = {}
	for ship in ships:
		var ship_id := str(ship.get("id", ""))
		if faction == "" or not _valid_ship(ship) or ship_id == "" or str(ship.get("faction", "")) != faction or used.has(ship_id) \
			or _carrier_busy(ship, bool(snapshot.get("galaxy", false))):
			continue
		if not _commerce(snapshot.get("relations", {}), faction, source_owner) \
			or not _commerce(snapshot.get("relations", {}), faction, dest_owner):
			continue
		if facility:
			if not _sensors_allow(snapshot, ship, contract):
				continue
			if int(ship.get("reputation", {}).get(faction, 0)) < int(contract.get("min_reputation", 0)):
				continue
		var route := _route(snapshot, str(ship.get("location", "")), source, target)
		if route < 0:
			continue
		if str(contract.get("mission_category", "")) == "strategy.colony.v1" \
			and not _reachable(snapshot, target, float(ship.get("speed", 0.0))):
			continue
		if kind == "Passenger":
			# The config-owned class capacity must be supplied, not guessed from cargo capacity.
			if not ship.has("passenger_capacity") or int(ship["passenger_capacity"]) < qty:
				continue
		else:
			if _carrier_free(ship) < qty or not _has_stock(market, str(contract.get("commodity", "")), qty):
				continue
			var purchase_cost := _purchase_cost(snapshot, ship, source, str(contract.get("commodity", "")), qty)
			var reward := int(contract.get("initial_payment", -1))
			if facility:
				reward = _acceptance_payment(snapshot, contract, ship)
				var topup := Core.top_up(contract, reward)
				if topup < 0 or topup > int(snapshot.get("facility_payers", {}).get(str(contract.get("requestor_id", "")), -1)):
					continue
			if purchase_cost < 0 or reward <= purchase_cost or int(ship.get("credits", -1)) < purchase_cost:
				continue
		var contender := {"ship_id": ship_id, "low_fuel": float(ship.get("fuel_fraction", 0.0)) < 0.25,
			"distance": route, "source": source}
		if _rank_better(contender, best):
			best = contender
	return best

static func _alternative(snapshot: Dictionary, contract: Dictionary, used: Dictionary, ships: Array) -> Dictionary:
	# Called only for an unaccepted Faction contract without a viable original carrier.
	if str(contract.get("contract_type", "")) == "Passenger":
		return {}
	var best: Dictionary = {}
	var faction := str(contract.get("faction_id", ""))
	var destination := str(contract.get("destination_location", ""))
	var original := str(contract.get("source_location", ""))
	var commodity := str(contract.get("commodity", ""))
	var quantity := int(contract.get("quantity", 0))
	var dest_owner := str(snapshot.get("owners", {}).get(destination, ""))
	var markets: Dictionary = snapshot.get("markets", {})
	var sources := markets.keys()
	sources.sort()
	for other_source in sources:
		var source: String = str(other_source)
		if source in [original, destination]:
			continue
		var market := _market(snapshot, source)
		var owner := str(snapshot.get("owners", {}).get(source, ""))
		if not _has_stock(market, commodity, quantity) or not _commerce(snapshot.get("relations", {}), faction, owner):
			continue
		for ship in ships:
			var ship_id := str(ship.get("id", ""))
			if not _valid_ship(ship) or str(ship.get("faction", "")) != faction or used.has(ship_id) or _carrier_busy(ship, bool(snapshot.get("galaxy", false))) \
				or _carrier_free(ship) < quantity or not _commerce(snapshot.get("relations", {}), faction, dest_owner):
				continue
			var route := _route(snapshot, str(ship.get("location", "")), source, destination)
			if route < 0 or (str(contract.get("mission_category", "")) == "strategy.colony.v1" \
				and not _reachable(snapshot, destination, float(ship.get("speed", 0.0)))):
				continue
			var cost := _purchase_cost(snapshot, ship, source, commodity, quantity)
			if cost < 0 or cost >= int(contract.get("initial_payment", -1)) or cost > int(ship.get("credits", -1)):
				continue
			var contender := {"ship_id": ship_id, "source": source, "distance": route, "cost": cost,
				"external": owner != faction}
			if best.is_empty() or _alternative_better(contender, best):
				best = contender
	return best

static func _alternative_better(a: Dictionary, b: Dictionary) -> bool:
	# Rust rank: (owner != faction, route, purchase_cost, source, ship).
	if bool(a["external"]) != bool(b["external"]):
		return not bool(a["external"])
	for key in ["distance", "cost"]:
		if int(a[key]) != int(b[key]):
			return int(a[key]) < int(b[key])
	if a["source"] != b["source"]:
		return str(a["source"]) < str(b["source"])
	return str(a["ship_id"]) < str(b["ship_id"])

static func _index(contracts: Array) -> Dictionary:
	var out := {}
	for i in range(contracts.size()):
		var cid := str(contracts[i].get("id", ""))
		if cid == "" or out.has(cid):
			return {} # No partial dispatch on corrupted board.
		out[cid] = i
	return out

static func _save_order(contracts: Array, index: int, order: Dictionary) -> void:
	var contract: Dictionary = contracts[index]
	var funding: Dictionary = contract.get("funding", {})
	funding["station_order"] = order
	contract["funding"] = funding
	contracts[index] = contract

static func _pending_sites(sites: Array) -> Array[int]:
	var indices: Array[int] = []
	for i in range(sites.size()):
		indices.append(i)
	indices.sort_custom(func(a, b): return str(sites[a].get("id", "")) < str(sites[b].get("id", "")))
	return indices

static func _save_site_order(sites: Array, index: int, order: Dictionary) -> void:
	var site: Dictionary = sites[index]
	var labor: Dictionary = site.get("labor", {})
	if labor.get("station_order") != order:
		labor["station_order"] = order
		site["labor"] = labor
		site["dirty"] = true
		sites[index] = site

static func _init_used(contracts: Array) -> Dictionary:
	var used := {}
	for c in contracts:
		if str(c.get("status", "")) in ["Accepted", "PickedUp", "Delivered"]:
			var id := str(c.get("fulfiller_id", ""))
			if id != "":
				used[id] = true
	return used

static func _maintenance_sites(snapshot: Dictionary, sites: Array, used: Dictionary, alive: Dictionary, tick: int, cooldown: int, lease: int) -> void:
	for index in _pending_sites(sites):
		var site: Dictionary = sites[index]
		var labor: Dictionary = site.get("labor", {})
		var order = labor.get("station_order")
		if not (order is Dictionary):
			continue
		var completed: bool = bool(site.get("completed", false)) \
			or int(labor.get("completed", 0)) >= int(labor.get("required", 0))
		var updated: Dictionary = order.duplicate(true)
		if completed:
			updated["state"] = "completed"
			updated["blocked_reason"] = ""
		else:
			var ship_id := str(updated.get("executor_id", ""))
			if ship_id != "":
				if not alive.has(ship_id):
					updated = Core.release(updated, "executor_missing", tick, cooldown)
				elif used.has(ship_id):
					updated = Core.release(updated, "executor_has_other_order", tick, cooldown)
				elif max(0, tick - maxi(int(labor.get("last_shift_tick", 0)), int(updated.get("assigned_tick", 0)))) >= lease:
					updated = Core.release(updated, "construction_progress_timeout", tick, cooldown)
				else:
					used[ship_id] = true
		_save_site_order(sites, index, updated)

static func _maintenance_contracts(contracts: Array, ids: Array[String], lookup: Dictionary, used: Dictionary, alive: Dictionary, tick: int, cooldown: int, lease: int) -> void:
	for id in ids:
		var index: int = lookup[id]
		var c: Dictionary = contracts[index]
		# Board owner guarantees funding for any native strategy/facility order.
		if not (c.get("funding") is Dictionary):
			continue
		var order := Core.order_of(c)
		if order.is_empty():
			order = Core.new_order("delivery", id)
		var status := str(c.get("status", ""))
		if status == "Paid":
			order["state"] = "completed"
			order["blocked_reason"] = ""
		elif status == "Expired":
			order["state"] = "cancelled"
			order["blocked_reason"] = "contract_expired"
		elif status in ["Accepted", "PickedUp", "Delivered"]:
			order["executor_id"] = str(c.get("fulfiller_id", ""))
			order["state"] = "executing"
			order["blocked_reason"] = ""
		elif status == "Posted":
			if not Core.funded_for_dispatch(c, tick):
				if str(order.get("executor_id", "")) != "" or tick >= int(order.get("retry_after_tick", 0)):
					order = Core.release(order, "invalid_order_escrow", tick, cooldown)
				_save_order(contracts, index, order)
				continue
			if str(order.get("blocked_reason", "")) == "invalid_order_escrow":
				order["retry_after_tick"] = tick
				order["blocked_reason"] = ""
			var current_ship := str(order.get("executor_id", ""))
			if current_ship != "":
				if not alive.has(current_ship):
					order = Core.release(order, "executor_missing", tick, cooldown)
				elif used.has(current_ship):
					order = Core.release(order, "executor_busy", tick, cooldown)
				elif str(order.get("state", "")) == "executing" \
					or max(0, tick - int(order.get("assigned_tick", 0))) >= lease:
					order = Core.release(order, "execution_released_or_accept_timeout", tick, cooldown)
				else:
					used[current_ship] = true
		_save_order(contracts, index, order)

static func _assign_contracts(snapshot: Dictionary, contracts: Array, ids: Array[String], lookup: Dictionary, ships: Array, used: Dictionary, tick: int, cooldown: int) -> void:
	for id in ids:
		var index: int = lookup[id]
		var c: Dictionary = contracts[index]
		var order := Core.order_of(c)
		if order.is_empty() or str(c.get("status", "")) != "Posted" \
			or str(order.get("executor_id", "")) != "" or tick < int(order.get("retry_after_tick", 0)) \
			or not Core.funded_for_dispatch(c, tick):
			continue
		var funding: Dictionary = c.get("funding", {})
		var facility: bool = funding.get("source", "") == "Facility"
		var source := str(c.get("source_location", ""))
		var candidate := _contract_carrier(snapshot, c, source, facility, used, ships)
		if candidate.is_empty() and not facility:
			candidate = _alternative(snapshot, c, used, ships)
		if not candidate.is_empty():
			var new_source := str(candidate.get("source", source))
			# Only unaccepted and escrowed offers may be re-sourced.
			c["source_location"] = new_source
			used[str(candidate["ship_id"])] = true
			_save_order(contracts, index, Core.assign(order, str(candidate["ship_id"]), tick))
		else:
			var reason := "no_viable_local_carrier"
			var market := _market(snapshot, source)
			if market.is_empty():
				reason = "source_market_missing"
			elif _stock(market, str(c.get("commodity", ""))) < float(c.get("quantity", 0)):
				reason = "source_stock_short"
			elif facility and not _has_sensor_ship(snapshot, c, ships):
				reason = "no_sensor_qualified_carrier"
			elif facility and not _has_idle_faction_ship(snapshot, c, ships, used):
				reason = "all_carriers_busy"
			_save_order(contracts, index, Core.release(order, reason, tick, cooldown))

static func _has_sensor_ship(snapshot: Dictionary, contract: Dictionary, ships: Array) -> bool:
	var faction := str(contract.get("faction_id", ""))
	for ship in ships:
		if str(ship.get("faction", "")) == faction and _sensors_allow(snapshot, ship, contract):
			return true
	return false

static func _has_idle_faction_ship(snapshot: Dictionary, contract: Dictionary, ships: Array, used: Dictionary) -> bool:
	var faction := str(contract.get("faction_id", ""))
	for ship in ships:
		if str(ship.get("faction", "")) == faction and not _carrier_busy(ship, bool(snapshot.get("galaxy", false))) \
			and not used.has(str(ship.get("id", ""))):
			return true
	return false

static func _assignment_quotes(snapshot: Dictionary, contracts: Array, tick: int) -> Array[Dictionary]:
	var quotes: Array[Dictionary] = []
	for c in contracts:
		if str(c.get("status", "")) not in ["Posted", "Accepted"]:
			continue
		var order := Core.order_of(c)
		var ship_id := str(order.get("executor_id", ""))
		if ship_id == "":
			continue
		var source := str(c.get("source_location", ""))
		var commodity := str(c.get("commodity", ""))
		var price := _price(_market(snapshot, source), commodity)
		if is_finite(price) and price > 0.0:
			quotes.append({"ship_id": ship_id, "source": source,
				"commodity": commodity, "price": price, "tick": tick})
	return quotes

static func run(snapshot: Dictionary) -> Dictionary:
	## Pure plan: no money/contract acceptance, facility stock, or movement committed here.
	var contracts: Array = snapshot.get("contracts", []).duplicate(true)
	var sites: Array = snapshot.get("sites", []).duplicate(true)
	var response := {"contracts": contracts, "sites": sites, "price_quotes": [],
		"error": "", "staged": false}
	if not bool(snapshot.get("executing", false)):
		return response # Rust Shadow mode: no orders created.
	var lookup := _index(contracts)
	if lookup.size() != contracts.size():
		response["error"] = "invalid_or_duplicate_contract_ids"
		return response
	var ships: Array = snapshot.get("ships", []).duplicate(true)
	ships.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	var alive := {}
	for ship in ships:
		var ship_id := str(ship.get("id", ""))
		if ship_id == "" or alive.has(ship_id):
			response["error"] = "invalid_or_duplicate_ship_ids"
			return response
		alive[ship_id] = true
	var tick: int = maxi(0, int(snapshot.get("tick", 0)))
	var multiplier: int = maxi(1, int(snapshot.get("multiplier", 1)))
	var cooldown: int = min(MAX_I64, 30 * multiplier)
	var lease: int = min(MAX_I64, 300 * multiplier)
	var used := _init_used(contracts)
	var ids := Core.contract_ids(contracts, tick, ships)
	_maintenance_sites(snapshot, sites, used, alive, tick, cooldown, lease)
	_maintenance_contracts(contracts, ids, lookup, used, alive, tick, cooldown, lease)
	_assign_contracts(snapshot, contracts, ids, lookup, ships, used, tick, cooldown)
	_assign_builders(snapshot, sites, ships, used, tick, cooldown)
	response["price_quotes"] = _assignment_quotes(snapshot, contracts, tick)
	response["staged"] = true
	return response

static func _assign_builders(snapshot: Dictionary, sites: Array, ships: Array, used: Dictionary, tick: int, cooldown: int) -> void:
	for index in _pending_sites(sites):
		var site: Dictionary = sites[index]
		var labor: Dictionary = site.get("labor", {})
		var required := int(labor.get("required", 0))
		if bool(site.get("completed", false)) or int(site.get("remaining", 1)) > 0 \
			or int(labor.get("completed", 0)) >= required:
			continue
		var order = labor.get("station_order")
		var active: Dictionary = order.duplicate(true) if order is Dictionary else Core.new_order("construction", str(site.get("id", "")))
		var site_loc := str(site.get("location_name", ""))
		if str(active.get("executor_id", "")) == "" and tick >= int(active.get("retry_after_tick", 0)):
			var best: Dictionary = {}
			for ship in ships:
				var ship_id := str(ship.get("id", ""))
				if not _valid_ship(ship) or str(ship.get("faction", "")) != str(site.get("faction_id", "")) or str(site.get("faction_id", "")) == "" \
					or _carrier_busy(ship, bool(snapshot.get("galaxy", false))) or used.has(ship_id) \
					or not ("engineer" in ship.get("crew_roles", [])):
					continue
				if str(labor.get("colony_source", "")) != "" and not _reachable(snapshot, site_loc, float(ship.get("speed", 0.0))):
					continue
				var distance := _distance(snapshot, str(ship.get("location", "")), site_loc)
				if distance < 0:
					continue
				var contender := {"ship_id": ship_id, "distance": distance}
				if best.is_empty() or distance < int(best.get("distance", 2147483647)) \
					or (distance == int(best.get("distance", 2147483647)) and ship_id < str(best.get("ship_id", ""))):
					best = contender
			if not best.is_empty():
				var ship_id := str(best.get("ship_id", ""))
				used[ship_id] = true
				active = Core.assign(active, ship_id, tick)
			else:
				active = Core.release(active, "no_viable_local_builder", tick, cooldown)
		var current := str(active.get("executor_id", ""))
		if current != "":
			if current == str(labor.get("last_executor", "")) and int(labor.get("last_shift_tick", -1)) >= int(active.get("assigned_tick", 0)):
				active["state"] = "executing"
			active["blocked_reason"] = str(labor.get("blocked_reason", ""))
		_save_site_order(sites, index, active)
