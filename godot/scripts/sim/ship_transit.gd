extends RefCounted
## N14: authoritative deterministic transit on directed N4 routes.
## Coordinates are world-space and MUST come from the native position resolver,
## never from travel_routes.distance or map screen offsets.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const OrbitalIntercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const NativeAvoidance = preload("res://scripts/sim/ships/native_avoidance.gd")
const BASE_VELOCITY := 0.05 # Rust agents/ship/mod.rs SHIP_BASE_VELOCITY
const ARRIVAL_THRESHOLD := 0.01 # Rust SHIP_ARRIVAL_THRESHOLD
const ARRIVAL_FLOAT_EPSILON := 0.000001 # Vector2 float32 only: 0.1 ~= 2 * 0.05
## Cap the 24-bisection N14 prediction work at one solve per several
## real fired ticks, preserving deterministic target/arrival checks.
const LEAD_REPLAN_TICKS: int = 4
var _next_token: int = 1

func depart(state: RefCounted, graph: RefCounted, ship_id: String, destination: String, positions: Dictionary, tick: int, tick_scale: float) -> bool:
	if tick < 0 or not is_finite(tick_scale) or tick_scale <= 0.0 or not state.ships.has(ship_id):
		return false
	var ship: Dictionary = state.ships[ship_id]
	var origin := str(ship.get("location", ""))
	if origin.is_empty() or not (ship.get("transit", {}) as Dictionary).is_empty():
		return false
	var directed := false
	for edge in graph.outgoing(origin):
		if str(edge["to"]) == destination:
			directed = true
			break
	if not directed or not positions.has(origin) or not positions.has(destination):
		return false
	if not _valid_position(positions[origin]) or not _valid_position(positions[destination]):
		return false
	var from_pos: Vector2 = positions[origin]
	var to_pos: Vector2 = positions[destination]
	var distance := from_pos.distance_to(to_pos)
	if distance <= 0.0 or not is_finite(distance):
		return false
	var spec: Dictionary = Catalog.spec(str(ship["class"]))
	var rate := float(spec.get("fuel_consumption_base", 0.0))
	var speed := float(ship.get("speed_modifier", Catalog.effective_speed(
		str(ship["class"]), str(ship["size"]))))
	if rate <= 0.0 or speed <= 0.0 or float(ship["fuel"]) <= 0.0:
		return false
	var token := _next_token
	_next_token += 1
	ship["location"] = ""
	ship["transit"] = {"from": origin, "to": destination, "departure_tick": tick,
		"departure_position": [from_pos.x, from_pos.y], "position": [from_pos.x, from_pos.y],
		"distance_total": distance, "distance_travelled": 0.0,
		"arrival_tick": tick + ceili(distance / (BASE_VELOCITY * speed * tick_scale)),
		"token": token, "last_tick": tick}
	return true

## Advance exactly one authoritative simulation tick; repeat calls are idempotent.
## Arrival is determined by distance, NEVER by the display-only arrival_tick.
func advance(state: RefCounted, ship_id: String, positions: Dictionary, tick: int,
		tick_scale: float, skipped_ticks: int = 1,
		authorized_lod_fire: bool = false,
		target_ephemeris: Dictionary = {},
		arrival_tolerance: float = ARRIVAL_THRESHOLD,
		solar_exclusion: Dictionary = {}) -> String:
	if not state.ships.has(ship_id) or not is_finite(tick_scale) or (
			tick_scale <= 0.0 or skipped_ticks < 1 or
			not is_finite(arrival_tolerance) or arrival_tolerance <= 0.0):
		return "invalid"
	var ship: Dictionary = state.ships[ship_id]
	var transit: Dictionary = ship.get("transit", {})
	if transit.is_empty():
		return "idle"
	if tick <= int(transit["last_tick"]):
		return "duplicate"
	# N140 controls fired ship frequency, never a second movement loop.
	if not authorized_lod_fire and tick != int(transit["last_tick"]) + 1:
		return "nonsequential_tick"
	if not authorized_lod_fire and skipped_ticks != 1:
		return "lod_authority_required"
	var target_id: String = str(transit["to"])
	if not positions.has(target_id) or not _valid_position(positions[target_id]):
		return "missing_destination"
	var spec: Dictionary = Catalog.spec(str(ship["class"]))
	var speed: float = float(ship.get("speed_modifier",
		Catalog.effective_speed(str(ship["class"]), str(ship["size"]))))
	var position: Vector2 = Vector2(float(transit["position"][0]),
		float(transit["position"][1]))
	var target: Vector2 = positions[target_id]
	var remaining: float = position.distance_to(target)
	var velocity: float = BASE_VELOCITY * speed * tick_scale
	var consumption: float = float(spec.get("fuel_consumption_base", 0.0)) * tick_scale
	if not is_finite(remaining) or not is_finite(velocity) or (
			velocity <= 0.0 or not is_finite(consumption) or consumption <= 0.0):
		return "invalid"

	# Existing routes are native receipts, persisted with the same ship
	# and token as the cargo/fuel. No waypoint recomputation while cruising.
	var waypoints: Variant = transit.get("navigation_waypoints", [])
	if not NativeAvoidance.valid_stored_points(waypoints):
		return "invalid_navigation_waypoints"
	var route: Array = waypoints
	var plan_used: bool = not route.is_empty()
	var lead: Dictionary = {}
	var aim: Vector2 = target
	if not plan_used and not target_ephemeris.is_empty():
		var saved_point: Variant = transit.get("cached_lead_point", null)
		var reuse: bool = (saved_point is Array and
			(saved_point as Array).size() == 2 and
			int(transit.get("lead_replan_tick", -1)) > tick)
		if reuse:
			if not ((saved_point[0] is float or saved_point[0] is int) and
					(saved_point[1] is float or saved_point[1] is int)):
				reuse = false
			else:
				aim = Vector2(float(saved_point[0]), float(saved_point[1]))
				if not (is_finite(aim.x) and is_finite(aim.y)) or (
						position.distance_to(aim) <= velocity * 1.1):
					reuse = false
		if not reuse:
			lead = OrbitalIntercept.aim_point(
				position, BASE_VELOCITY * speed, target_ephemeris, target)
			aim = lead["point"]
			if bool(lead.get("prediction_used", false)):
				transit["cached_lead_point"] = [aim.x, aim.y]
				transit["lead_replan_tick"] = tick + LEAD_REPLAN_TICKS
			else:
				transit.erase("cached_lead_point")
				transit.erase("lead_replan_tick")
	else:
		transit.erase("cached_lead_point")
		transit.erase("lead_replan_tick")

	if not plan_used and not solar_exclusion.is_empty():
		var center: Variant = solar_exclusion.get("center", null)
		var clearance: float = float(solar_exclusion.get("radius", -1.0))
		if not (center is Vector2) or not is_finite(clearance) or (
				clearance <= 0.0):
			return "invalid_navigation_geometry"
		if NativeAvoidance.segment_crosses(position, aim, center, clearance):
			var proposed: Dictionary = NativeAvoidance.plan(
				position, aim, center, clearance)
			if not proposed.get("ok", false):
				# Fail safely with an owned N14 holding state. No free
				# movement through the Sun and no fictitious fuel expense.
				transit["last_tick"] = tick
				transit["navigation_hold"] = str(proposed.get("reason", "unsafe"))
				return "holding"
			route = proposed["points"]
			if not route.is_empty():
				transit["navigation_waypoints"] = route
				transit.erase("navigation_hold")
				plan_used = true

	# A direct final leg is physical only if its path is clear. For
	# verified near-body geometry, the old .01 Rust arrival bubble is
	# far larger than the Moon's orbit and must never skip the final leg.
	var exact_arrival: bool = arrival_tolerance < ARRIVAL_THRESHOLD
	if not plan_used and (not exact_arrival and remaining <= arrival_tolerance
			or exact_arrival and remaining <= 0.0000001):
		ship["location"] = target_id
		ship["transit"] = {}
		return "arrived"
	if float(ship["fuel"]) < consumption:
		transit["last_tick"] = tick
		return "out_of_fuel"

	if plan_used:
		var point: Array = route[0]
		var waypoint: Vector2 = Vector2(float(point[0]), float(point[1]))
		var separation: float = position.distance_to(waypoint)
		var movement: float = minf(velocity, separation)
		var next_pos: Vector2 = position.move_toward(waypoint, movement)
		if separation <= velocity + ARRIVAL_FLOAT_EPSILON:
			route.remove_at(0)
		if route.is_empty():
			transit.erase("navigation_waypoints")
			# Recompute moving-target prediction only when the detour has
			# actually been traversed; never use a stale pre-star aim.
			transit.erase("cached_lead_point")
			transit.erase("lead_replan_tick")
		else:
			transit["navigation_waypoints"] = route
		ship["fuel"] = maxf(0.0, float(ship["fuel"]) - consumption)
		transit["position"] = [next_pos.x, next_pos.y]
		transit["distance_travelled"] = clampf(
			float(transit["distance_total"]) - next_pos.distance_to(target),
			0.0, float(transit["distance_total"]))
		transit["physical_distance_travelled"] = float(transit.get(
			"physical_distance_travelled", 0.0)) + movement
		transit["last_tick"] = tick
		transit["arrival_tick"] = tick + maxi(1, ceili(
			(next_pos.distance_to(target) + float(route.size()) * clearance_estimate(
				solar_exclusion)) / maxf(velocity, 0.00001)))
		return "moving"

	if remaining <= velocity + ARRIVAL_FLOAT_EPSILON:
		ship["fuel"] = maxf(0.0, float(ship["fuel"]) - consumption)
		ship["location"] = target_id
		ship["transit"] = {}
		return "arrived"

	var next_position: Vector2 = position.move_toward(
		aim, minf(velocity, position.distance_to(aim)))
	ship["fuel"] = maxf(0.0, float(ship["fuel"]) - consumption)
	transit["position"] = [next_position.x, next_position.y]
	transit["distance_travelled"] = clampf(
		float(transit["distance_total"]) - next_position.distance_to(target),
		0.0, float(transit["distance_total"]))
	transit["physical_distance_travelled"] = float(transit.get(
		"physical_distance_travelled", 0.0)) + position.distance_to(next_position)
	transit["last_tick"] = tick
	var eta_steps: float = next_position.distance_to(target) / maxf(
		velocity, 0.00001)
	if bool(lead.get("prediction_used", false)):
		eta_steps = float(lead["eta_native"]) / maxf(tick_scale, 0.00001)
	transit["arrival_tick"] = tick + ceili(eta_steps)
	return "moving"


static func clearance_estimate(solar_exclusion: Dictionary) -> float:
	return maxf(0.0, float(solar_exclusion.get("radius", 0.0)))

## Any previously scheduled arrival must carry the same token.
func arrival_token_valid(state: RefCounted, ship_id: String, token: int) -> bool:
	if not state.ships.has(ship_id):
		return false
	var transit: Dictionary = state.ships[ship_id].get("transit", {})
	return not transit.is_empty() and int(transit.get("token", -1)) == token

func cancel(state: RefCounted, ship_id: String) -> bool:
	if not state.ships.has(ship_id):
		return false
	var transit: Dictionary = state.ships[ship_id].get("transit", {})
	if transit.is_empty():
		return false
	# Cancellation does not teleport to origin. Ship remains in flight, but
	# invalidates ETA/event and requires an explicit rescue/replan system.
	transit["token"] = _next_token
	_next_token += 1
	transit["arrival_tick"] = -1
	return true


## N54 combined fleet envelope calls these on the SINGLE transit authority.
## The cursor must be strictly greater than every persisted active token;
## never reuse a token after a save/restore or an interrupted arrival event.
func next_token() -> int:
	return _next_token

func restore_next_token(cursor: int, highest_active_token: int) -> bool:
	if cursor < 1 or highest_active_token < 0:
		return false
	if cursor <= highest_active_token:
		return false
	_next_token = cursor
	return true

func _valid_position(value: Variant) -> bool:
	return value is Vector2 and is_finite(value.x) and is_finite(value.y)
