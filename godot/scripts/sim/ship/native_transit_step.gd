extends RefCounted
## Frozen Rust: agents/ship/mod.rs::advance_transits (velocity model).
## Pure per-ship state transform; destination is the CURRENT moving orbital position.
const BASE_VELOCITY := 0.05
const ARRIVAL_THRESHOLD := 0.01

static func advance(ship: Dictionary, target: Vector2, tick: int, tick_scale: float, skipped: int = 1) -> Dictionary:
	var out: Dictionary = ship.duplicate(true)
	if not out.has("transit") or out["transit"] == null:
		if out.get("location_name", "") != "":
			out["position"] = target
		return {"ok": true, "ship": out, "arrived": false}
	if not is_finite(tick_scale) or tick_scale < 0.0 or skipped < 1:
		return {"ok": false, "reason": "invalid_tick_scale"}
	var transit: Dictionary = out["transit"]
	if not transit.has("to") or not out.has("position"):
		return {"ok": false, "reason": "invalid_transit"}
	var pos: Vector2 = out["position"]
	if not is_finite(target.x) or not is_finite(target.y):
		return {"ok": false, "reason": "missing_target"}
	if not transit.has("departure_position") or transit["departure_position"] == null:
		transit["departure_position"] = pos
	var effective_scale: float = tick_scale * float(skipped)
	var speed_modifier: float = float(out.get("speed_modifier", 1.0))
	var burn_rate: float = float(out.get("fuel_consumption_rate", 0.0))
	if not is_finite(speed_modifier) or speed_modifier < 0.0 or not is_finite(burn_rate) or burn_rate < 0.0:
		return {"ok": false, "reason": "invalid_fuel_parameters"}
	var dist: float = pos.distance_to(target)
	var velocity: float = BASE_VELOCITY * speed_modifier * effective_scale
	var step: float = minf(velocity, dist)
	if dist <= maxf(velocity, ARRIVAL_THRESHOLD):
		out["position"] = target
		out["location_name"] = transit["to"]
		out["docked_at"] = null
		var visited: Array = out.get("visited", []).duplicate()
		if not visited.has(transit["to"]):
			visited.append(transit["to"])
		out["visited"] = visited
		out["transit"] = null
		out["dirty"] = true
		return {"ok": true, "ship": out, "arrived": true}
	var ratio: float = step / dist if dist > 0.0 else 0.0
	out["position"] = pos + (target - pos) * ratio
	var total: float = float(transit.get("distance_total", 0.0))
	if total <= 0.0:
		total = dist + maxf(step * 0.5, 0.0001)
	transit["distance_total"] = total
	transit["distance_travelled"] = clampf(total - dist, 0.0, total)
	out["fuel"] = maxf(0.0, float(out.get("fuel", 0.0)) - burn_rate * effective_scale)
	var per_tick: float = BASE_VELOCITY * speed_modifier * maxf(tick_scale, 0.00001)
	transit["arrival_tick"] = tick + int(dist / maxf(per_tick, 0.00001))
	out["transit"] = transit
	out["dirty"] = true
	return {"ok": true, "ship": out, "arrived": false}
