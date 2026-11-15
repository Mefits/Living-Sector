extends RefCounted
## N147 — frozen sim_core/src/strategy/colony_development.rs migration_proposals().
## Pure read-only source-backed logic; consumes N92 ColonyView snapshots, N142
## physical-only registry lookup, native Cargo/ShipClass/faction identities.
## NO households, funds, contracts, passengers or fuel are created here.
const MAX_U32: int = 4294967295
const PASSENGER_PAYMENT_PER_HEAD: int = 80
const MAX_MIGRATION_PARTY: int = 20
const MIN_SOURCE_RESERVE: int = 10 # colony::SETTLERS (original source)
const FACTION_SUBSIDY_FLOOR: int = 5000

static func _err(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "plans": {}}

static func outstanding(c: Dictionary) -> bool:
	## super::outstanding: Paid/Expired are settled only when reserved
	## funding is no longer held. All other native statuses are pending.
	var status: String = str(c.get("status", ""))
	var reserved: int = int(c.get("reserved_credits", 0))
	return not (status in ["paid", "expired"]) or reserved > 0

static func outstanding_carrier_ids(contracts: Array) -> Dictionary:
	var assigned := {}
	for contract in contracts:
		if not (contract is Dictionary) or not outstanding(contract):
			continue
		var id = contract.get("fulfiller_id", null)
		if id is String and not str(id).is_empty():
			assigned[id] = true
	return assigned

static func physical_route_exists(physical: Dictionary, origin: String, destination: String) -> bool:
	## N142 WorldRegistry::shortest_distance(...) -> Some(u32), NOT
	## N59's cheaper gate-enabled PathfinderCtx. Adapter must evaluate
	## this lookup directly from verified native directed location graph.
	var row = physical.get(origin, null)
	if not (row is Dictionary) or not row.has(destination):
		return false
	var distance = row[destination]
	return typeof(distance) == TYPE_INT and int(distance) >= 0 and int(distance) <= MAX_U32

static func quantity_for_missing(missing: int) -> int:
	## Native ((missing_workers * 5 + 2) / 3).clamp(1, 20).
	if missing <= 0:
		return 1
	# Rust missing is a positive bounded i64; cap before multiplication to
	# preserve the exact saturated result without signed overflow.
	if missing >= 12:
		return MAX_MIGRATION_PARTY
	return clampi(int((missing * 5 + 2) / 3), 1, MAX_MIGRATION_PARTY)

static func _life_support_ok(c: Dictionary) -> bool:
	## Rust Option<f32>::zip on stock/target; no inferred free water/food.
	for commodity in ["water", "food"]:
		var current = c.get(commodity, null)
		var target = c.get(commodity + "_reserve_target", null)
		if not (typeof(current) in [TYPE_INT, TYPE_FLOAT] and typeof(target) in [TYPE_INT, TYPE_FLOAT]):
			return false
		if not is_finite(float(current)) or not is_finite(float(target)):
			return false
		if float(current) < float(target):
			return false
	return true

static func _valid_view(c: Dictionary) -> bool:
	if str(c.get("phase", "")) != "migration" or int(c.get("missing_workers", 0)) <= 0:
		return false
	var pending = c.get("pending_passenger_contract", null)
	if pending != null and str(pending) != "":
		return false
	return bool(c.get("market_unambiguous", false)) and _life_support_ok(c)

static func _ship_idle_for_planning(ship: Dictionary, assigned: Dictionary) -> bool:
	## Native migration_proposals' ShipCargo/Economy/Fuel/Position/Transit ECS
	## projection. Caller must populate these from the real world/board,
	## never invent a passenger ship just because a view needs workers.
	if str(ship.get("id", "")).is_empty() or assigned.has(str(ship.get("id", ""))):
		return false
	var active = ship.get("active_contract_id", null)
	if active != null and str(active) != "":
		return false
	if bool(ship.get("in_transit", false)) or not bool(ship.get("has_native_cargo", false)):
		return false
	var fuel = ship.get("fuel", null)
	return typeof(fuel) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(fuel)) and float(fuel) > 0.0

static func _ship_can_carry(ship: Dictionary, faction: String, quantity: int,
		source: String, physical: Dictionary, ship_classes: Dictionary) -> bool:
	if str(ship.get("faction_id", "")) != faction:
		return false
	var ship_class: String = str(ship.get("class", ""))
	var spec = ship_classes.get(ship_class, null)
	if not (spec is Dictionary) or typeof(spec.get("passenger_capacity")) != TYPE_INT:
		return false
	if int(spec["passenger_capacity"]) < quantity:
		return false
	var position = ship.get("location", null)
	if not position is String or str(position).is_empty():
		return false
	return str(position) == source or physical_route_exists(physical, str(position), source)

static func _read_cash(treasuries: Dictionary, faction: String) -> Dictionary:
	if not treasuries.has(faction) or typeof(treasuries[faction]) != TYPE_INT:
		return {"ok": false, "cash": 0}
	return {"ok": true, "cash": int(treasuries[faction])}

static func plan(views: Array, world: Dictionary) -> Dictionary:
	## Inputs: views from N92 observe(), native world projection:
	## {treasuries:Dictionary[id:int], stations:Array[{faction_id,location,facility_type}],
	##  households:Array[{faction_id,location,population_count}],
	##  ships:Array[{id,faction_id,class,location,has_native_cargo,
	##               active_contract_id,in_transit,fuel}],
	##  ship_classes:Dictionary[class -> {passenger_capacity:int}],
	##  contracts:Array native board snapshots,
	##  physical_distances:Dictionary[origin -> Dictionary[destination -> u32]]}
	##
	## Native ColonyView arrive sorted by faction then location; normalize that
	## view order here so exactly one BTreeMap entry per faction is stable.
	for key in ["treasuries", "stations", "households", "ships", "ship_classes", "contracts", "physical_distances"]:
		if not world.has(key):
			return _err("missing_native_world_projection:" + key)
	if not (world["treasuries"] is Dictionary and world["stations"] is Array and
			world["households"] is Array and world["ships"] is Array and
			world["ship_classes"] is Dictionary and world["contracts"] is Array and
			world["physical_distances"] is Dictionary):
		return _err("invalid_native_world_projection")
	var physical: Dictionary = world["physical_distances"]
	var assigned := outstanding_carrier_ids(world["contracts"])
	var sorted_views := views.duplicate(true)
	for c in sorted_views:
		if not c is Dictionary:
			return _err("malformed_colony_view")
	sorted_views.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.get("faction_id", "")) != str(b.get("faction_id", "")):
			return str(a.get("faction_id", "")) < str(b.get("faction_id", ""))
		return str(a.get("location", "")) < str(b.get("location", "")))
	var result := {}
	for view in sorted_views:
		if not _valid_view(view):
			continue
		var faction: String = str(view.get("faction_id", ""))
		var destination: String = str(view.get("location", ""))
		if faction.is_empty() or destination.is_empty() or result.has(faction):
			continue
		var quantity := quantity_for_missing(int(view["missing_workers"]))
		var payment := quantity * PASSENGER_PAYMENT_PER_HEAD
		var money := _read_cash(world["treasuries"], faction)
		if not bool(money["ok"]) or int(money["cash"]) - FACTION_SUBSIDY_FLOOR < payment:
			continue
		var sources: Array[String] = []
		for station in world["stations"]:
			if not station is Dictionary:
				continue
			var source: String = str(station.get("location", ""))
			if str(station.get("facility_type", "")) != "station" or 					str(station.get("faction_id", "")) != faction or 					source == destination or source.is_empty() or 					not physical_route_exists(physical, source, destination):
				continue
			var resident := false
			for pop in world["households"]:
				if not pop is Dictionary:
					continue
				if str(pop.get("faction_id", "")) == faction and 						str(pop.get("location", "")) == source and 						int(pop.get("population_count", -1)) >= quantity + MIN_SOURCE_RESERVE:
					resident = true
					break
			if resident and not sources.has(source):
				sources.append(source)
		sources.sort()
		for source in sources:
			var eligible := false
			for ship in world["ships"]:
				if not ship is Dictionary or not _ship_idle_for_planning(ship, assigned):
					continue
				if _ship_can_carry(ship, faction, quantity, source, physical, world["ship_classes"]):
					eligible = true
					break
			if eligible:
				result[faction] = {"source": source, "destination": destination,
					"quantity": quantity, "payment": payment, "reason": "ready"}
				break
	return {"ok": true, "reason": "", "plans": result}
