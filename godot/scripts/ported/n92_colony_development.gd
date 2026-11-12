extends RefCounted
## Rust: strategy/colony_development.rs. Observations and intent only.
## Input is a read-only ECS projection. No free goods, settlers or contracts.

const MIN_LIFE_SUPPORT_STOCK := 20.0
const BUFFER_CYCLES := 80.0
const MAX_FORECAST_RESERVE := 180.0
const ELECTRONICS_TARGET := 10.0
const MAX_MIGRATION_PARTY := 20

static func reserve(demand: float, per_purchase: float) -> float:
	if not is_finite(demand) or demand < 0.0 or not is_finite(per_purchase) or per_purchase < 0.0:
		return -1.0
	return maxf(maxf(demand * 2.0, MIN_LIFE_SUPPORT_STOCK), minf(per_purchase * BUFFER_CYCLES, MAX_FORECAST_RESERVE))

static func _valid_stock(stock: Dictionary, commodity: String) -> float:
	var value := float(stock.get(commodity, 0.0))
	return value if is_finite(value) and value >= 0.0 else -1.0

static func observe(colonies: Array) -> Array:
	var result := []
	for colony in colonies:
		if not str(colony.get("location", "")).ends_with("-colony") or colony.get("station_type", "") != "station":
			continue
		var population := maxi(0, int(colony.get("population", 0)))
		var required := 0
		var kinds := []
		for facility in colony.get("facilities", []):
			var kind := str(facility.get("type", ""))
			kinds.append(kind)
			if kind in ["mining_rig", "refinery", "farm", "factory"]:
				required += int(facility.get("crew_count", 0))
		var available := population * 3 / 5
		var missing := maxi(0, required - available)
		var unique: bool = int(colony.get("market_count", 0)) == 1 and bool(colony.get("market_owned_by_station", false))
		var stock: Dictionary = colony.get("stock", {})
		var demand: Dictionary = colony.get("demand", {})
		var food_per := float(colony.get("food_per_purchase", 0.0))
		var water_per := float(colony.get("water_per_purchase", 0.0))
		var food := _valid_stock(stock, "food")
		var water := _valid_stock(stock, "water")
		var fuel := _valid_stock(stock, "fuel")
		var electronics := _valid_stock(stock, "electronics")
		var ft := reserve(float(demand.get("food", 0.0)), food_per)
		var wt := reserve(float(demand.get("water", 0.0)), water_per)
		var phase := "operational"
		var reason := "colony_life_support_and_industry_present"
		var next_commodity := ""
		if not unique:
			phase = "blocked"; reason = "ambiguous_or_missing_colony_market"
		elif minf(minf(food, water), minf(ft, wt)) < 0.0:
			phase = "blocked"; reason = "invalid_colony_life_support_stock"
		elif population == 0:
			phase = "awaiting_population"; reason = "no_resident_household"
		elif water < wt or food < ft:
			phase = "life_support"; reason = "colony_essential_reserve_below_target"
			next_commodity = "water" if water / wt <= food / ft else "food"
		elif not kinds.has("mining_rig"):
			phase = "building"; reason = "colony_needs_mining_rig"
		elif not kinds.has("refinery"):
			phase = "building"; reason = "colony_needs_refinery"
		elif not kinds.has("farm"):
			phase = "building"; reason = "colony_needs_farm"
		elif missing > 0:
			phase = "migration"
			reason = "passenger_contract_in_progress" if colony.get("pending_passenger_contract", "") != "" else "colony_needs_workers"
		elif not kinds.has("factory"):
			phase = "building"; reason = "colony_needs_factory"
		elif electronics < ELECTRONICS_TARGET:
			phase = "industrial_chain"; reason = "colony_needs_electronics"; next_commodity = "electronics"
		result.append({"faction_id":colony.get("faction_id", ""), "location":colony.get("location", ""),
			"population":population, "available_workers":available, "required_workers":required,
			"missing_workers":missing, "water":water, "food":food, "fuel":fuel, "electronics":electronics,
			"water_reserve_target":wt, "food_reserve_target":ft, "phase":phase,
			"reason":reason, "next_commodity":next_commodity,
			"market_unambiguous":unique, "pending_passenger_contract":colony.get("pending_passenger_contract", "")})
	result.sort_custom(func(a,b): return [a["faction_id"],a["location"]] < [b["faction_id"],b["location"]])
	return result

static func next_supply_goal(views: Array, contracts: Array, faction: String) -> Dictionary:
	var options := []
	for view in views:
		if view["faction_id"] != faction or not view["market_unambiguous"] or view["population"] <= 0:
			continue
		for commodity in ["water", "food"]:
			var current := float(view[commodity])
			var target := float(view[commodity + "_reserve_target"])
			if current < 0.0 or target <= 0.0 or current >= target or _outstanding(contracts, view["location"], commodity):
				continue
			options.append({"goal_id":"colony_life_support", "commodity":commodity, "destination":view["location"], "score":1500.0 + (1.0-current/target)*100.0})
		if view["fuel"] >= 0.0 and view["fuel"] < 20.0 and not _outstanding(contracts, view["location"], "fuel"):
			options.append({"goal_id":"colony_service_fuel", "commodity":"fuel", "destination":view["location"], "score":600.0})
		if view["phase"] == "industrial_chain" and view["missing_workers"] == 0 and not _outstanding(contracts, view["location"], "electronics"):
			options.append({"goal_id":"colony_electronics_chain", "commodity":"electronics", "destination":view["location"], "score":55.0})
	options.sort_custom(func(a,b):
		if a["score"] != b["score"]: return a["score"] > b["score"]
		if a["destination"] != b["destination"]: return a["destination"] < b["destination"]
		return a["commodity"] < b["commodity"])
	return options[0] if not options.is_empty() else {}

static func _outstanding(contracts: Array, location: String, commodity: String) -> bool:
	for contract in contracts:
		if contract.get("destination", "") == location and contract.get("commodity", "") == commodity and contract.get("type", "") != "passenger" and contract.get("outstanding", false):
			return true
	return false

static func migration_quantity(missing_workers: int) -> int:
	return clampi((missing_workers * 5 + 2) / 3, 1, MAX_MIGRATION_PARTY)

static func migration_intent(view: Dictionary, sources: Array, ships: Array, treasury: int, treasury_floor: int, payment_per_head: int, settler_reserve: int, reachable: Dictionary) -> Dictionary:
	if view.get("phase", "") != "migration" or int(view.get("missing_workers", 0)) <= 0 or view.get("pending_passenger_contract", "") != "":
		return {}
	if not view.get("market_unambiguous", false) or float(view.get("water", -1.0)) < float(view.get("water_reserve_target", 0.0)) or float(view.get("food", -1.0)) < float(view.get("food_reserve_target", 0.0)):
		return {}
	var quantity := migration_quantity(int(view["missing_workers"]))
	var payment := quantity * payment_per_head
	if treasury - treasury_floor < payment:
		return {}
	for source in sources:
		var origin := str(source.get("location", ""))
		if source.get("faction_id", "") != view["faction_id"] or origin == view["location"] or int(source.get("population", 0)) < quantity + settler_reserve:
			continue
		if not reachable.has(origin + "|" + str(view["location"])):
			continue
		for ship in ships:
			var ship_location := str(ship.get("location", ""))
			if ship.get("faction_id", "") == view["faction_id"] and int(ship.get("passenger_capacity", 0)) >= quantity and not ship.get("in_transit", false) and not ship.get("contract_active", false) and float(ship.get("fuel", 0.0)) > 0.0 and (ship_location == origin or reachable.has(ship_location + "|" + origin)):
				return {"source":origin, "destination":view["location"], "quantity":quantity, "payment":payment, "reason":"ready", "requires":"authoritative_prepaid_passenger_contract"}
	return {}
