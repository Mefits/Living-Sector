extends RefCounted
## N14: authoritative deterministic transit on directed N4 routes.
## Coordinates are world-space and MUST come from the native position resolver,
## never from travel_routes.distance or map screen offsets.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const BASE_VELOCITY := 0.05 # Rust agents/ship/mod.rs SHIP_BASE_VELOCITY
const ARRIVAL_THRESHOLD := 0.01 # Rust SHIP_ARRIVAL_THRESHOLD
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
func advance(state: RefCounted, ship_id: String, positions: Dictionary, tick: int, tick_scale: float) -> String:
	if not state.ships.has(ship_id) or not is_finite(tick_scale) or tick_scale <= 0.0:
		return "invalid"
	var ship: Dictionary = state.ships[ship_id]
	var transit: Dictionary = ship.get("transit", {})
	if transit.is_empty():
		return "idle"
	if tick <= int(transit["last_tick"]):
		return "duplicate"
	if tick != int(transit["last_tick"]) + 1:
		return "nonsequential_tick"
	var target_id := str(transit["to"])
	if not positions.has(target_id) or not _valid_position(positions[target_id]):
		return "missing_destination"
	var spec: Dictionary = Catalog.spec(str(ship["class"]))
	var speed := float(ship.get("speed_modifier", Catalog.effective_speed(
		str(ship["class"]), str(ship["size"]))))
	var position := Vector2(float(transit["position"][0]), float(transit["position"][1]))
	var target: Vector2 = positions[target_id]
	var remaining := position.distance_to(target)
	var velocity := BASE_VELOCITY * speed * tick_scale
	if not is_finite(remaining) or velocity <= 0.0:
		return "invalid"
	# A final movement step is still a physical flight step. Previously it
	# teleported the ship into dock without paying the final tick of fuel.
	# Check the tank before either advancing or completing this step.
	var consumption := float(spec["fuel_consumption_base"]) * tick_scale
	if not is_finite(consumption) or consumption <= 0.0:
		return "invalid"
	if remaining <= ARRIVAL_THRESHOLD:
		ship["location"] = target_id
		ship["transit"] = {}
		return "arrived"
	if float(ship["fuel"]) < consumption:
		transit["last_tick"] = tick
		return "out_of_fuel"
	if remaining <= velocity:
		ship["fuel"] = maxf(0.0, float(ship["fuel"]) - consumption)
		ship["location"] = target_id
		ship["transit"] = {}
		return "arrived"
	var next_position := position.move_toward(target, minf(velocity, remaining))
	ship["fuel"] = maxf(0.0, float(ship["fuel"]) - consumption)
	transit["position"] = [next_position.x, next_position.y]
	transit["distance_travelled"] = clampf(float(transit["distance_total"]) - next_position.distance_to(target), 0.0, float(transit["distance_total"]))
	transit["last_tick"] = tick
	transit["arrival_tick"] = tick + ceili(next_position.distance_to(target) / maxf(velocity, 0.00001))
	return "moving"

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
