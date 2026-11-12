extends RefCounted
## Frozen Rust ship/behavior.rs: GOAP request builders, BT expansion,
## rest congestion, retrofit yard choice, exploration and recovery.
## N81 owns GOAP operator/catalog execution, N84 owns BT ticking, N59 owns
## real directed routing, N88/N90 own leaves and N97/N104 own physical apply.
## A request is NOT a successful plan until the N81 planner returns actions.
const DOCK_ARRIVE_DWELL_SECS := 2
const DOCK_DEPART_DWELL_SECS := 2
const DOCK_SATURATION_THRESHOLD := 1.2
const CONTRACT_ACCEPT_QUEUE_MULTIPLIER := 3.0
const RETROFIT_CREDIT_RESERVE := 12000
const EXPLORE_CHECK_BOARD_SECONDS := 5
const SLOT_ORDER := ["engine", "cargo", "sensors", "reactor", "comms"]

static func _action(name: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = args.duplicate(true)
	result["kind"] = name
	return result

static func _clamp_bucket_cost(distance: float, same_location: bool, valid_route: bool) -> int:
	if same_location:
		return 0
	if not valid_route:
		return 1
	return mini(10, maxi(1, int(ceil(distance / 50.0))))

static func fuel_bucket_cost(from: String, to: String, route_legs: Dictionary) -> int:
	# Rust find_route(None) -> cost=1, not zero or an unreachable error.
	if from == to:
		return 0
	var key: String = from + "|" + to
	if not route_legs.has(key):
		return 1
	var distance: float = 0.0
	for leg in route_legs[key]:
		distance += maxf(1.0, float(leg.get("distance", 0.0)))
	return _clamp_bucket_cost(distance, false, true)

static func fuel_fraction_to_bucket(fraction: float) -> int:
	# ai/planner.rs::fuel_fraction_to_bucket, round positive ties up.
	if fraction <= 0.0:
		return 0
	return mini(10, maxi(0, int(floor(fraction * 10.0 + 0.5))))

static func plan_request(kind: String, args: Dictionary, route_legs: Dictionary) -> Dictionary:
	## Exact Rust GOAP call domain; run it using existing N81 planner/catalog.
	## The caller must supply source-derived bucket from N81, never -1.
	var origin: String = str(args.get("current", ""))
	var source: String = str(args.get("source", origin))
	var destination: String = str(args.get("destination", origin))
	var commodity: String = str(args.get("commodity", "Food"))
	var quantity: int = int(args.get("quantity", 0))
	var contract_id: String = str(args.get("contract_id", ""))
	var fuel_bucket: int = int(args.get("fuel_bucket", -1))
	if origin.is_empty() or source.is_empty() or destination.is_empty() or fuel_bucket < 0 or fuel_bucket > 10 or quantity < 0:
		return {}
	var catalogs: Dictionary = {
		"delivery": "delivery_catalog", "delivery_retrofit": "delivery_catalog",
		"trade_run": "trade_run_catalog", "trade_run_retrofit": "trade_run_catalog",
		"passenger": "passenger_catalog", "courier": "passenger_catalog",
		"crew_mission": "crew_mission_catalog", "rest_crew": "rest_crew_catalog",
		"retrofit": "retrofit_catalog", "resume_delivery": "delivery_catalog",
		"resume_passenger": "passenger_catalog", "resume_crew_mission": "crew_mission_catalog"
	}
	if not catalogs.has(kind):
		return {}
	var map: Dictionary = {
		"origin": origin, "source": source, "dest": destination,
		"commodity": commodity, "quantity": quantity, "contract_id": contract_id,
		"cost_origin_to_source": fuel_bucket_cost(origin, source, route_legs),
		"cost_source_to_dest": fuel_bucket_cost(source, destination, route_legs),
		"cost_origin_to_dest": fuel_bucket_cost(origin, destination, route_legs)
	}
	var goal: Dictionary = {"fuel_bucket_min": 2}
	var depth: int = 20
	match kind:
		"delivery", "resume_delivery":
			goal["delivered"] = true
		"delivery_retrofit":
			goal["delivered"] = true
			goal["retrofitted"] = true
			depth = 28
		"trade_run":
			goal["sold"] = true
		"trade_run_retrofit":
			goal["sold"] = true
			goal["retrofitted"] = true
			depth = 28
		"passenger", "courier", "resume_passenger":
			goal["delivered"] = true
			depth = 16
		"crew_mission", "resume_crew_mission":
			goal["delivered"] = true
			goal["rested"] = true
		"rest_crew":
			goal["rested"] = true
			goal["not_docked"] = true
			goal["at"] = "Dest"
			depth = 16
		"retrofit":
			goal["retrofitted"] = true
			depth = 16
	if kind == "rest_crew":
		# Rust source/dest are placeholders for the rest-only catalog.
		map["source"] = origin
		map["cost_origin_to_source"] = 0
		map["cost_source_to_dest"] = 0
	if kind == "retrofit":
		map["source"] = origin
		map["dest"] = origin
		map["cost_origin_to_source"] = 0
		map["cost_source_to_dest"] = 0
		map["cost_origin_to_dest"] = 0
	if kind in ["delivery_retrofit", "trade_run_retrofit", "retrofit"]:
		var rp: Dictionary = args.get("retrofit", {})
		if rp.is_empty() or str(rp.get("shipyard_location", "")).is_empty() or str(rp.get("slug", "")).is_empty():
			return {}
		var yard: String = str(rp["shipyard_location"])
		map["shipyard"] = yard
		map["refit_slot"] = rp.get("slot", "")
		map["refit_slug"] = rp.get("slug", "")
		map["cost_origin_to_shipyard"] = fuel_bucket_cost(origin, yard, route_legs)
		map["cost_source_to_shipyard"] = fuel_bucket_cost(source, yard, route_legs) if kind != "retrofit" else 0
		map["cost_shipyard_to_dest"] = fuel_bucket_cost(yard, destination, route_legs) if kind != "retrofit" else 0
	if kind == "trade_run" or kind == "trade_run_retrofit":
		map["contract_id"] = ""
		map["quantity"] = 50
	if kind.begins_with("resume_"):
		# Recovered contract state is derived from actual cargo and board.
		# Rust goal drops fuel>=2 for resume and uses initial dock status.
		goal.erase("fuel_bucket_min")
		var resume_status: Dictionary = args.get("resume", {})
		map["quantity"] = int(resume_status.get("remaining_quantity", quantity))
	var initial: Dictionary = {"at": "Origin", "fuel_bucket": fuel_bucket}
	if kind.begins_with("resume_"):
		if origin == destination:
			initial["at"] = "Dest"
		elif origin == source:
			initial["at"] = "Source"
		initial["docked"] = bool(args.get("docked", false))
		initial["cargo_loaded"] = bool(args.get("cargo_loaded", false))
	return {"catalog": catalogs[kind], "initial": initial, "goal": goal,
		"loc_map": map, "max_depth": depth, "kind": kind}

static func resume_contract_request(current: String, docked: bool, cargo: Dictionary, fuel_bucket: int, contract: Dictionary, routes: Dictionary) -> Dictionary:
	var contract_id: String = str(contract.get("id", ""))
	var kind: String = str(contract.get("contract_type", ""))
	var quantity: int = int(contract.get("quantity", 0))
	var commodity: String = str(contract.get("commodity", ""))
	var have: int = int(cargo.get(commodity, 0))
	if current.is_empty() or contract_id.is_empty() or quantity < 0:
		return {}
	if kind == "Courier" and have < quantity:
		# No physical courier pickup mechanism: never synthesize cargo.
		return {}
	var crew: bool = kind == "CrewMission"
	var passenger: bool = kind == "Passenger"
	var physical: bool = not passenger and not crew
	var initial_loaded: bool = have >= quantity if physical else str(contract.get("status", "")) == "PickedUp"
	var request_kind: String = "resume_crew_mission" if crew else ("resume_passenger" if passenger else "resume_delivery")
	var args: Dictionary = {
		"current": current, "source": contract.get("source_location", ""),
		"destination": contract.get("destination_location", ""),
		"commodity": commodity, "quantity": quantity if passenger else (0 if crew else maxi(0, quantity - have)),
		"contract_id": contract_id, "fuel_bucket": fuel_bucket, "docked": docked,
		"cargo_loaded": initial_loaded, "resume": {"remaining_quantity": quantity if passenger else (0 if crew else maxi(0, quantity - have))}
	}
	var spec: Dictionary = plan_request(request_kind, args, routes)
	if spec.is_empty():
		return {}
	if crew:
		spec["goal"].erase("fuel_bucket_min")
	return spec

static func route_actions(from: String, to: String, route_legs: Dictionary) -> Array:
	if from == to:
		return []
	var key: String = from + "|" + to
	var out: Array = []
	if not route_legs.has(key):
		# Source route_actions falls back to direct Travel on no path.
		return [_action("Travel", {"destination": to})]
	for leg in route_legs[key]:
		if str(leg.get("kind", "")).to_lower() in ["gate", "gatejump"]:
			out.append(_action("GateJump", {"src_gate": str(leg.get("from", "")), "dest_gate": str(leg.get("to", ""))}))
		else:
			out.append(_action("Travel", {"destination": str(leg.get("to", ""))}))
	return out

static func compile_plan_to_bt_actions(plan_actions: Array, loc_map: Dictionary, route_legs: Dictionary, is_resume: bool = false) -> Array:
	## N81 supplies actual action sequence. This function only expands it
	## to the source's leaf sequence for N84; it never runs a leaf.
	var out: Array = []
	var contract_id: String = str(loc_map.get("contract_id", ""))
	if not contract_id.is_empty() and not is_resume:
		out.append(_action("AcceptContract", {"contract_id": contract_id}))
	var current: String = str(loc_map.get("origin", ""))
	for raw in plan_actions:
		if not (raw is Dictionary):
			continue
		var kind: String = str(raw.get("kind", ""))
		match kind:
			"Travel":
				var to: String = str(raw.get("destination", ""))
				out.append_array(route_actions(current, to, route_legs))
				current = to
			"Dock", "DockAtShipyard":
				out.append(raw.duplicate(true))
				out.append(_action("DockDwell", {"seconds": DOCK_ARRIVE_DWELL_SECS}))
			"Undock":
				out.append(_action("DockDwell", {"seconds": DOCK_DEPART_DWELL_SECS}))
				out.append(_action("Undock"))
			_:
				out.append(raw.duplicate(true))
	# Rust resume removes the first Accept if it appears, not a later
	# Accept. A second acceptance is NEVER inserted by the wrapper.
	if is_resume and not out.is_empty() and str(out[0].get("kind", "")) == "AcceptContract":
		out.remove_at(0)
	return out

static func location_saturated(record: Dictionary) -> bool:
	var cap: int = int(record.get("capacity", 0))
	return cap <= 0 or (float(record.get("docked", 0)) + float(record.get("queued", 0))) / float(cap) >= DOCK_SATURATION_THRESHOLD

static func contract_destination_saturated(location: String, congestion: Dictionary) -> bool:
	if not congestion.has(location):
		return false
	var record: Dictionary = congestion[location]
	var cap: int = int(record.get("capacity", 0))
	return cap > 0 and float(record.get("queued", 0)) >= CONTRACT_ACCEPT_QUEUE_MULTIPLIER * float(cap)

static func any_rest_destination_viable(current: String, congestion: Dictionary, systems: Dictionary) -> bool:
	if congestion.has(current) and not location_saturated(congestion[current]):
		return true
	if not systems.has(current):
		return false
	for location in congestion.keys():
		if systems.get(location) == systems[current] and not location_saturated(congestion[location]):
			return true
	return false

static func pick_rest_destination(current: String, congestion: Dictionary, systems: Dictionary) -> String:
	if congestion.has(current):
		var here: Dictionary = congestion[current]
		if int(here.get("capacity", 0)) > 0 and int(here.get("docked", 0)) < int(here["capacity"]):
			return current
	var current_saturation: float = INF
	if congestion.has(current):
		var here2: Dictionary = congestion[current]
		current_saturation = (float(here2.get("docked", 0)) + float(here2.get("queued", 0))) / float(maxi(1, int(here2.get("capacity", 0))))
	var best: String = ""
	var best_saturation: float = INF
	for location in congestion.keys():
		var value: Dictionary = congestion[location]
		if location_saturated(value):
			continue
		if systems.has(current) and systems.get(location) != systems[current]:
			continue
		var saturation: float = (float(value.get("docked", 0)) + float(value.get("queued", 0))) / float(value["capacity"])
		if saturation < best_saturation:
			best = str(location)
			best_saturation = saturation
	return best if best_saturation < current_saturation else current

static func select_retrofit(fitting: Dictionary, inventory: Array, ship_credits: int, ship_location: String, ship_system: String, module_catalog: Dictionary, recipe_catalog: Dictionary) -> Dictionary:
	# Caller only invokes if N101 progression.retrofit_points > 0.
	if ship_credits < RETROFIT_CREDIT_RESERVE:
		return {}
	for slot in SLOT_ORDER:
		var slug: String = str(fitting.get(slot, ""))
		var current_def: Dictionary = module_catalog.get(slug, {})
		var tier: int = int(current_def.get("tier", 1))
		if tier >= 3:
			continue
		var next_slug: String = slot + "_t" + str(tier + 1)
		if not module_catalog.has(next_slug) or not recipe_catalog.has(next_slug):
			continue
		var price: int = int(recipe_catalog[next_slug].get("base_cost_credits", -1))
		if price < 0 or ship_credits - price < RETROFIT_CREDIT_RESERVE:
			continue
		var closest: Dictionary = {}
		var closest_rank: int = 3
		for yard in inventory:
			var stock: Dictionary = yard.get("stock", {})
			if int(stock.get(next_slug, 0)) <= 0:
				continue
			var where: String = str(yard.get("location", ""))
			var rank: int = 0 if where == ship_location else (1 if not ship_system.is_empty() and str(yard.get("system", "")) == ship_system else 2)
			if rank < closest_rank:
				closest_rank = rank
				closest = yard
		if not closest.is_empty():
			return {"shipyard_location": closest["location"], "slot": slot, "slug": next_slug, "cost": price}
	return {}

static func same_system_station(current: String, registry_order: Array, systems: Dictionary) -> String:
	if not systems.has(current):
		return ""
	for location in registry_order:
		var name: String = str(location.get("name", ""))
		var loc_type: String = str(location.get("loc_type", ""))
		if name == current or loc_type == "mining_site" or name.contains("gate"):
			continue
		if systems.get(name) == systems[current]:
			return name
	return ""

static func explore_plan(current: String, recent_systems: Array, gate_pairs_in_order: Array, systems: Dictionary, registry_order: Array, routes: Dictionary) -> Array:
	if not systems.has(current):
		return []
	var choices: Array = []
	var preferred: Array = []
	for pair in gate_pairs_in_order:
		var origin: String = str(pair.get("source", ""))
		var destination: String = str(pair.get("destination", ""))
		if systems.get(origin) != systems[current] or not systems.has(destination):
			continue
		var item: Dictionary = {"source": origin, "destination": destination}
		choices.append(item)
		if not recent_systems.has(systems[destination]):
			preferred.append(item)
	var choice: Dictionary = preferred[0] if not preferred.is_empty() else (choices[0] if not choices.is_empty() else {})
	if choice.is_empty():
		return []
	var gate: String = str(choice["destination"])
	var station: String = same_system_station(gate, registry_order, systems)
	if station.is_empty():
		station = gate
	var out: Array = route_actions(current, str(choice["source"]), routes)
	out.append(_action("GateJump", {"src_gate": choice["source"], "dest_gate": gate}))
	out.append_array(route_actions(gate, station, routes))
	out.append(_action("Dock"))
	out.append(_action("DockDwell", {"seconds": EXPLORE_CHECK_BOARD_SECONDS}))
	out.append(_action("Undock"))
	return out

static func idle_seek_station(current: String, docked: bool, loc_type: String, registry_order: Array, systems: Dictionary, routes: Dictionary) -> Array:
	if docked or not (loc_type == "mining_site" or loc_type == "gate" or loc_type == ""):
		return []
	var station: String = same_system_station(current, registry_order, systems)
	if station.is_empty():
		return []
	var out: Array = route_actions(current, station, routes)
	out.append(_action("Dock"))
	out.append(_action("DockDwell", {"seconds": EXPLORE_CHECK_BOARD_SECONDS}))
	out.append(_action("Undock"))
	return out

static func contract_candidate_request(current: String, candidate: Dictionary, fuel_bucket: int, routes: Dictionary) -> Dictionary:
	## Kind routing of behavior.rs::try_plan_contract after choosing the
	## highest own-strategy/fill-adjusted offer. Does not call N81 itself.
	if candidate.is_empty():
		return {}
	var kind: String = str(candidate.get("kind", ""))
	var source: String = str(candidate.get("source", ""))
	var dest: String = str(candidate.get("destination", ""))
	var id: String = str(candidate.get("id", ""))
	var commodity: String = str(candidate.get("commodity", ""))
	var qty: int = int(candidate.get("quantity", 0))
	var request_kind: String = "delivery"
	var request_source: String = source
	var request_dest: String = dest
	var request_quantity: int = qty
	match kind:
		"CrewMission":
			request_kind = "crew_mission"
			request_source = current
			request_dest = source
			request_quantity = 0
			commodity = "Food"
		"Passenger":
			request_kind = "passenger"
			commodity = "Food"
		"Courier":
			request_kind = "courier"
			request_quantity = 0
			commodity = "Food"
		_:
			request_kind = "delivery"
	return plan_request(request_kind, {
		"current": current, "source": request_source,
		"destination": request_dest, "commodity": commodity,
		"quantity": request_quantity, "contract_id": id,
		"fuel_bucket": fuel_bucket
	}, routes)

static func trade_candidate_request(current: String, trade: Dictionary, fuel_bucket: int, routes: Dictionary) -> Dictionary:
	## N83 supplies the actually accepted fresh + solvent best trade.
	## This does not duplicate N83 route price/learning calculations.
	if trade.is_empty():
		return {}
	return plan_request("trade_run", {
		"current": current, "source": str(trade.get("buy_loc", "")),
		"destination": str(trade.get("sell_loc", "")),
		"commodity": str(trade.get("commodity", "")), "quantity": 50,
		"fuel_bucket": fuel_bucket
	}, routes)

static func bt_result_after_goap(request: Dictionary, expanded_actions: Array, route_legs: Dictionary) -> Array:
	## Called only after N81 found a plan; an empty/failed search must
	## yield a one-tick Idle BT exactly as Rust build_* wrappers do.
	if request.is_empty() or expanded_actions.is_empty():
		return [_action("Idle")]
	return compile_plan_to_bt_actions(expanded_actions, request.get("loc_map", {}),
		route_legs, str(request.get("kind", "")).begins_with("resume_"))
