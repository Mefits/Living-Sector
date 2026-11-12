extends RefCounted
## Frozen Rust agents/ship/behavior.rs::try_plan_contract (1877..2223).
## Pure planner proposal. No ContractBoard, wallet, cargo, or escrow mutations.
## External read-only gates are populated by N152/N104/N135/N94/N150; fail closed
## if a required authoritative gate/quote is absent.
const CROSS_SYSTEM_SENSOR_RANGE_AU := 2.0
const CONTRACT_ACCEPT_QUEUE_MULTIPLIER := 3.0

static func median_known_price(price_knowledge: Dictionary, commodity: String) -> Variant:
	var values: Array[float] = []
	for market in price_knowledge.values():
		if not (market is Dictionary) or not market.has(commodity):
			continue
		var observation: Variant = market[commodity]
		var price: float = float(observation.get("price", -1.0)) if observation is Dictionary else -1.0
		if is_finite(price) and price >= 0.0:
			values.append(price)
	if values.is_empty():
		return null
	values.sort()
	# Rust picks prices[len/2], including the upper median for even sizes.
	return values[int(values.size() / 2)]

static func quote_source_price(memory: Dictionary, source: String, commodity: String) -> Variant:
	var price_map: Dictionary = memory.get("price_knowledge", {})
	if price_map.has(source) and price_map[source] is Dictionary:
		var observation: Variant = price_map[source].get(commodity)
		if observation is Dictionary and observation.has("price"):
			var source_price: float = float(observation["price"])
			if is_finite(source_price):
				return source_price
	return median_known_price(price_map, commodity)

static func contract_queue_saturated(location: String, congestion: Dictionary) -> bool:
	if not congestion.has(location):
		return false
	var load: Dictionary = congestion[location]
	var capacity: int = int(load.get("capacity", 0))
	if capacity <= 0:
		return false
	return float(load.get("queued", 0)) >= CONTRACT_ACCEPT_QUEUE_MULTIPLIER * float(capacity)

static func is_cross_system(ship_location: String, source: String, destination: String, system_by_location: Dictionary) -> bool:
	# Rust deliberately falls back to visible on incomplete system data.
	if not system_by_location.has(ship_location) or not system_by_location.has(source) or not system_by_location.has(destination):
		return false
	return system_by_location[ship_location] != system_by_location[source] or system_by_location[source] != system_by_location[destination]

static func estimate_gate_fees(pairs: Array, gate_pairs: Dictionary, cargo_estimate: int, flat_fee: int, per_cargo_fee: int) -> int:
	# Exact frozen ship/mod.rs heuristic, intentionally NOT real pathfinder fees.
	var total: int = 0
	for pair in pairs:
		var source: String = str(pair[0])
		var destination: String = str(pair[1])
		var either_gate: bool = gate_pairs.has(source) or gate_pairs.has(destination)
		var from_tag: String = source.split("-")[0] if gate_pairs.has(source) else "_other_"
		var to_tag: String = destination.split("-")[0] if gate_pairs.has(destination) else "_other_"
		if either_gate or (from_tag != to_tag and from_tag != "_other_" and to_tag != "_other_"):
			total += flat_fee + per_cargo_fee * cargo_estimate
	return total

static func _is_commerce_allowed(faction: String, commerce: Dictionary) -> bool:
	# The caller MUST obtain this from frozen FactionRelations and market owners.
	# Unknown is a rejected bid, rather than an invented peace treaty.
	return not faction.is_empty() and commerce.get(faction, false) == true

static func _goals_for_kind(kind: String) -> String:
	match kind:
		"CrewMission": return "do_crew_mission"
		"Passenger": return "fulfill_passenger_transport"
		"Courier": return "fulfill_courier"
		"Subsidy": return "fulfill_contract"
		"Construction": return "fulfill_construction"
		_: return "fulfill_delivery"

static func _rounded_nonnegative(v: float) -> int:
	# Rust f32 round() uses half-away-from-zero; effective profit is >=0.
	return int(floor(v + 0.5))

static func select_contract(context: Dictionary) -> Dictionary:
	## Required context:
	## offers = already filtered posted_for_ship(effective_reputation) from N152
	## assigned = N135 assigned Posted contract, or null
	## quotes[id] = {valid, quoted_payment, top_up, payer_balance,
	##               fixed_strategy_reward, source_purchase_cost} from N104/N94
	## commerce_allowed[owner] from N150, controllers[location] from N150
	## memory price_knowledge + contract_rejections[id] from N80,
	## gate flat/per_cargo fee from frozen facility constants.
	var offers: Array = context.get("offers", [])
	var assigned: Variant = context.get("assigned", null)
	var has_assignment: bool = assigned is Dictionary
	if has_assignment and str(assigned.get("status", "")) == "Posted":
		offers = [assigned]
	var ship_faction: String = str(context.get("ship_faction", ""))
	var ship_id: String = str(context.get("ship_id", ""))
	var ship_location: String = str(context.get("ship_location", ""))
	var controllers: Dictionary = context.get("controllers", {})
	var relations: Dictionary = context.get("commerce_allowed", {})
	var system_map: Dictionary = context.get("system_by_location", {})
	var congestion: Dictionary = context.get("dock_congestion", {})
	var sensor_range: float = float(context.get("sensor_range_au", 0.0))
	var cargo_capacity: int = int(context.get("cargo_capacity", 0))
	var credits: int = int(context.get("credits", 0))
	var quotes: Dictionary = context.get("quotes", {})
	var memory: Dictionary = context.get("memory", {})
	var rejections: Dictionary = memory.get("contract_rejections", {})
	var gate_pairs: Dictionary = context.get("gate_pairs", {})
	var default_flat: int = int(context.get("default_gate_fee_flat", 0))
	var default_per_cargo: int = int(context.get("default_gate_fee_per_cargo", 0))
	var current_tick: int = int(context.get("tick", 0))
	var best: Dictionary = {}
	for offer in offers:
		if not (offer is Dictionary):
			continue
		var cid: String = str(offer.get("id", ""))
		var source: String = str(offer.get("source_location", ""))
		var destination: String = str(offer.get("destination_location", ""))
		var kind: String = str(offer.get("contract_type", ""))
		var owner: String = str(offer.get("faction_id", ""))
		var quantity: int = int(offer.get("quantity", 0))
		if cid.is_empty() or source.is_empty() or destination.is_empty() or quantity < 0 or not quotes.has(cid):
			continue
		if has_assignment and str(assigned.get("id", "")) != cid:
			continue
		# N135 may_accept enforces member-assigned carrier/faction and leased ship.
		if offer.get("may_accept", false) != true:
			continue
		var quote: Dictionary = quotes[cid]
		if quote.get("valid", false) != true:
			continue
		var funding_key: String = str(quote.get("funding_key", ""))
		if rejections.has(cid):
			var rejected: Dictionary = rejections[cid]
			if str(rejected.get("key", "")) == funding_key and current_tick < int(rejected.get("until_tick", 0)):
				continue
		var top_up: int = int(quote.get("top_up", -1))
		var payment: int = int(quote.get("quoted_payment", -1))
		var payer_balance: Variant = quote.get("payer_balance", null)
		if top_up < 0 or payment <= 0 or (top_up > 0 and (payer_balance == null or int(payer_balance) < top_up)):
			continue
		if not owner.is_empty() and not _is_commerce_allowed(owner, relations):
			continue
		var source_owner: String = str(controllers.get(source, ""))
		var destination_owner: String = str(controllers.get(destination, ""))
		if not source_owner.is_empty() and not _is_commerce_allowed(source_owner, relations):
			continue
		if not destination_owner.is_empty() and not _is_commerce_allowed(destination_owner, relations):
			continue
		var fixed_reward: int = int(quote.get("fixed_strategy_reward", 0))
		var reserved: int = int(quote.get("reserved", -1))
		var own_strategy: bool = str(offer.get("requestor_id", "")) == ship_faction and fixed_reward > 0 and reserved >= fixed_reward
		# Assigned, already surveyed own-strategy orders bypass the sensor gate.
		if sensor_range < CROSS_SYSTEM_SENSOR_RANGE_AU and not (own_strategy and has_assignment):
			if is_cross_system(ship_location, source, destination, system_map):
				continue
		if contract_queue_saturated(source, congestion) or contract_queue_saturated(destination, congestion):
			continue
		var passenger: bool = kind == "Passenger"
		var courier: bool = kind == "Courier"
		var mission: bool = kind == "CrewMission"
		if not passenger and not mission and quantity > cargo_capacity:
			continue
		var buy_cost: int = 0
		if not (passenger or courier or mission):
			var source_price: Variant = quote_source_price(memory, source, str(offer.get("commodity", "")))
			if source_price == null:
				continue
			if quote.has("fixed_strategy_reward") and fixed_reward > 0:
				# N94 sourcing::purchase_cost is the one owner of treaty/rep multiplier.
				if not quote.has("source_purchase_cost") or int(quote["source_purchase_cost"]) < 0:
					continue
				buy_cost = int(quote["source_purchase_cost"])
			else:
				buy_cost = int(float(source_price) * float(quantity))
		var gate_fees: int = estimate_gate_fees([[ship_location, source], [source, destination]], gate_pairs, quantity, default_flat, default_per_cargo)
		var cost: int = buy_cost + gate_fees
		if cost >= payment or credits < cost:
			continue
		var profit: int = payment - cost
		var quality: float = 1.0
		if (kind == "Delivery" or kind == "Construction") and cargo_capacity > 0:
			quality = maxf(0.1, sqrt(clampf(float(quantity) / float(cargo_capacity), 0.0, 1.0)))
		var effective_profit: int = _rounded_nonnegative(float(profit) * quality)
		# Rust compares (own_strategy, effective_profit) lexicographically;
		# equal-ranked later entries replace earlier entries, by source.
		if not best.is_empty() and bool(best["own_strategy"]) == own_strategy and int(best["effective_profit"]) > effective_profit:
			continue
		if not best.is_empty() and bool(best["own_strategy"]) and not own_strategy:
			continue
		best = {
			"id": cid, "kind": kind, "goal_name": _goals_for_kind(kind),
			"profit": profit, "effective_profit": effective_profit,
			"own_strategy": own_strategy, "source": source,
			"destination": destination, "commodity": str(offer.get("commodity", "")),
			"quantity": quantity, "quoted_payment": payment, "estimated_cost": cost,
			"delivery_params": {
				"source": source, "destination": destination,
				"commodity": str(offer.get("commodity", "")),
				"quantity": quantity, "contract_id": cid
			} if kind in ["Delivery", "Subsidy", "Construction"] else null
		}
	return best
