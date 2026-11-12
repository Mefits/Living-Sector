extends RefCounted
## N144 / Rust strategy/colony.rs::proposals. Pure snapshot -> plans.
## Input keys: factions, ports, sites, bodies, people, ships, markets,
## locations, contracts, director_enabled, tech, distances.
## External paid contract commission belongs to N118; no stocks are changed.
const SETTLERS := 10
const DIRECTOR_SETTLERS := 50
const CONSTRUCTION_QUANTITY := 10 # Inject exact faction constants via rules.
const TAU_R := 6.283185307179586

static func _number(v: Variant, fallback: float = 0.0) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return fallback
	return float(v)

static func _has_pop(people: Array, faction: String, location: String, count: int) -> bool:
	for p in people:
		if p.get("faction_id", "") == faction and p.get("facility_location", "") == location and int(p.get("population_count", 0)) >= count:
			return true
	return false

static func _outstanding(contracts: Array, faction: String, destination: String) -> bool:
	for c in contracts:
		if c.get("requestor_id", "") == faction and c.get("destination_location", "") == destination and bool(c.get("outstanding", false)):
			return true
	return false

static func can_rendezvous(orbit: Dictionary, speed_modifier: float, base_velocity: float) -> bool:
	var period := float(orbit.get("orbit_period", 0.0))
	if period <= 0.0:
		return false
	return TAU_R * float(orbit.get("orbit_radius", 0.0)) / period < base_velocity * speed_modifier

static func _plan(destination: String, source: String, body: Dictionary, site_id: Variant, cost: int, quantity: int, passenger: bool, reason: String, score: float) -> Dictionary:
	return {"goal_id":"found_colony", "commodity":"Metals", "destination":destination,
		"shortage_ticks":0, "score":score, "source":source, "body":body,
		"site_id":site_id, "cost":cost, "quantity":quantity,
		"passenger":passenger, "reason":reason}

static func _better(a: Dictionary, b: Dictionary) -> bool:
	if b.is_empty():
		return true
	if (a.reason == "ready") != (b.reason == "ready"):
		return a.reason == "ready"
	if a.score != b.score:
		return a.score > b.score
	if a.destination != b.destination:
		return a.destination < b.destination
	return a.source < b.source

## Rules are explicit Rust constants (not invented defaults):
## construction_progress_required, construction_quantity, construction_base_payment,
## startup_capital, labor_required, wage_per_shift, subsidy_floor,
## ship_base_velocity. Quotes supplied by native sourcing.purchase_cost.
## distances is a nested physical WorldRegistry shortest_distance map (no gates).
static func proposals(snapshot: Dictionary, rules: Dictionary) -> Dictionary:
	var output := {}
	var factions: Array = snapshot.get("factions", [])
	var ports: Array = snapshot.get("ports", [])
	var sites: Array = snapshot.get("sites", [])
	var bodies: Array = snapshot.get("bodies", [])
	var people: Array = snapshot.get("people", [])
	var ships: Array = snapshot.get("ships", [])
	var markets: Array = snapshot.get("markets", [])
	var contracts: Array = snapshot.get("contracts", [])
	var locations: Dictionary = snapshot.get("locations", {})
	var distances: Dictionary = snapshot.get("distances", {})
	var tech: Dictionary = snapshot.get("tech", {})
	var director := bool(snapshot.get("director_enabled", false))
	var settlers := DIRECTOR_SETTLERS if director else SETTLERS
	var construction_qty := int(rules.get("construction_quantity", 0))
	var progress_required := int(rules.get("construction_progress_required", 0))
	var base_payment := int(rules.get("construction_base_payment", 0))
	var startup := int(rules.get("startup_capital", 0))
	var labor_required := int(rules.get("labor_required", 0))
	var wage := int(rules.get("wage_per_shift", 0))
	var floor := int(rules.get("subsidy_floor", 0))
	if construction_qty <= 0 or progress_required <= 0:
		return output
	var founding_cost := int(ceil(float(progress_required) / construction_qty)) * base_payment + startup + labor_required * wage + settlers * 80
	var occupied := {}
	for port in ports:
		occupied[str(port.get("body_id", ""))] = true
	for faction in factions:
		var fid := str(faction.get("id", ""))
		var treasury := int(faction.get("treasury", 0))
		var active: Dictionary = {}
		for site in sites:
			if site.get("faction_id", "") == fid and not site.get("completed", false) and site.get("colony_source") != null:
				if active.is_empty() or str(site.get("id", "")) < str(active.get("id", "")):
					active = site
		if not active.is_empty():
			var body := {}
			for b in bodies:
				if b.get("body_id", "") == active.get("body_id", ""):
					body = b
					break
			if body.is_empty():
				continue
			var source := str(active.get("colony_source", ""))
			var destination := str(active.get("location_name", ""))
			var passenger := not _has_pop(people, fid, destination, settlers)
			var quantity := settlers if passenger else mini(int(active.get("remaining", 0)), construction_qty)
			var cost := quantity * 80 if passenger else base_payment
			var reason := "ready"
			if _outstanding(contracts, fid, destination):
				reason = "colony_contract_in_progress"
			elif quantity == 0:
				reason = "awaiting_paid_labor"
			elif treasury - floor < cost + startup + maxi(0, int(active.get("labor_required", 0)) - int(active.get("labor_completed", 0))) * wage:
				reason = "insufficient_colony_budget"
			elif passenger and not _has_pop(people, fid, source, settlers * 2):
				reason = "insufficient_settlers"
			elif not passenger:
				var affordable := false
				for market in markets:
					if market.get("facility_location", "") == source and _number(market.get("metals_supply", 0)) >= quantity and bool(market.get("quote_valid", false)) and int(market.get("metals_quote", 0)) < cost:
						affordable = true
						break
				if not affordable:
					reason = "insufficient_affordable_metals"
			output[fid] = _plan(destination, source, body, active.get("id"), cost, quantity, passenger, reason, 0.0)
			continue
		var best := {}
		for body in bodies:
			if body.get("body_type", "") != "planet" or occupied.has(str(body.get("body_id", ""))):
				continue
			var pending := false
			for site in sites:
				if site.get("body_id", "") == body.get("body_id", "") and not site.get("completed", false):
					pending = true
					break
			if pending:
				continue
			var ore := _number(body.get("ore", 0.0))
			var ice := _number(body.get("ice", 0.0))
			var gas := _number(body.get("gas", 0.0))
			if ore <= 0.0 and ice <= 0.0 and gas <= 0.0:
				continue
			var destination := str(body.get("body_id", "")) + "-colony"
			var loc: Dictionary = locations.get(destination, {})
			if loc.get("loc_type", "") != "colony" or loc.get("celestial_body_id") != body.get("db_id"):
				continue
			for port in ports:
				if port.get("faction_id", "") != fid or port.get("facility_type", "") == "construction_dock":
					continue
				var source := str(port.get("location_name", ""))
				var distance_map: Dictionary = distances.get(source, {})
				if not distance_map.has(destination):
					continue
				var distance := int(distance_map[destination])
				var stock := {}
				for market in markets:
					if market.get("facility_id") == port.get("id"):
						stock = market
						break
				if stock.is_empty():
					continue
				var reason := "ready"
				if director and not tech.get(fid, {}).get("orbital_habitats", false):
					reason = "requires_orbital_habitats"
				elif director and distance > 100 and not tech.get(fid, {}).get("deep_navigation", false):
					reason = "requires_deep_navigation"
				elif treasury - floor < founding_cost:
					reason = "insufficient_colony_budget"
				elif not _has_pop(people, fid, source, settlers * 2):
					reason = "insufficient_settlers"
				elif not is_finite(_number(stock.get("metals_supply", -1.0), -1.0)) or _number(stock.get("metals_supply", -1.0), -1.0) < progress_required:
					reason = "insufficient_affordable_metals"
				else:
					var passenger := false
					var carrier := false
					var engineer := false
					for ship in ships:
						if ship.get("faction_id", "") != fid or _number(ship.get("fuel_fraction", 0.0)) <= 0.0:
							continue
						if not can_rendezvous(body, _number(ship.get("speed_modifier", 1.0)), _number(rules.get("ship_base_velocity", 0.0))):
							continue
						var ship_loc := str(ship.get("location_name", ""))
						if ship_loc != source and not (distances.get(ship_loc, {}) as Dictionary).has(source):
							continue
						passenger = passenger or int(ship.get("passenger_capacity", 0)) >= settlers
						carrier = carrier or (int(ship.get("cargo_capacity", 0)) >= construction_qty and bool(stock.get("quote_valid", false)) and int(stock.get("metals_quote", 0)) < base_payment and int(ship.get("credits", 0)) >= int(stock.get("metals_quote", 0)))
						engineer = engineer or bool(ship.get("builder_capable", false))
					if not passenger:
						reason = "no_passenger_transport"
					elif not carrier:
						reason = "no_viable_local_carrier"
					elif not engineer:
						reason = "no_viable_local_builder"
				var same_system := false
				for own in ports:
					if own.get("faction_id", "") != fid or own.get("facility_type", "") != "station":
						continue
					for home in bodies:
						if home.get("body_id") == own.get("body_id") and home.get("star_system_id") == body.get("star_system_id"):
							same_system = true
							break
				var gas_need := _number(stock.get("gas_supply", 0.0)) < 50.0
				var score := (0.1 + maxf(ore, maxf(ice, gas)) + gas * (0.55 if gas_need else 0.10)) * (4.0 if same_system else 1.0) / (1.0 + distance)
				var plan := _plan(destination, source, body, null, founding_cost, settlers, true, reason, score)
				if _better(plan, best):
					best = plan
		if not best.is_empty():
			output[fid] = best
	return output
