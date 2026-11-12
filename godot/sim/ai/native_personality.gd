extends RefCounted
## Rust crates/sim_core/src/ai/personality.rs, six axes and archetypes.
## Caller supplies seeded RandomNumberGenerator: never silently re-seed on restore.
const AXES := ["profit", "safety", "morale", "exploration", "loyalty", "aggression"]

static func profile(kind: String) -> Dictionary:
	match kind:
		"cautious_trader":
			return _make([0.6, 0.9, 0.5, 0.1, 0.7, 0.0], {"fulfill_contract": 0.3, "fulfill_delivery": 0.3, "station_job": 0.2})
		"aggressive_trader":
			return _make([0.95, 0.2, 0.2, 0.3, 0.3, 0.1], {"trade_run": 0.3})
		"balanced_trader":
			return _make([0.7, 0.5, 0.4, 0.3, 0.5, 0.0], {})
		"explorer":
			return _make([0.3, 0.5, 0.4, 0.9, 0.2, 0.0], {"explore": 0.4})
		"reliable_trucker":
			return _make([0.5, 0.7, 0.5, 0.1, 0.9, 0.0], {"fulfill_delivery": 0.4, "fulfill_contract": 0.3})
		"opportunistic_trucker":
			return _make([0.7, 0.4, 0.3, 0.2, 0.7, 0.1], {"fulfill_delivery": 0.25, "trade_run": 0.2})
		"courier":
			return _make([0.6, 0.8, 0.7, 0.2, 0.8, 0.0], {"fulfill_passenger_transport": 0.35, "fulfill_courier": 0.30, "fulfill_delivery": 0.25, "station_job": 0.15})
		"miner":
			return _make([0.5, 0.6, 0.4, 0.3, 0.6, 0.0], {"mine": 0.4, "fulfill_delivery": 0.2, "station_job": 0.15})
		"diligent":
			return _make([0.3, 0.4, 0.3, 0.1, 0.9, 0.0], {})
		"self_preserving":
			return _make([0.5, 0.9, 0.8, 0.2, 0.2, 0.1], {})
	return {}

static func _make(values: Array, bonuses: Dictionary) -> Dictionary:
	var p := {}
	for i in range(AXES.size()):
		p[AXES[i]] = float(values[i])
	p["prefer_goals"] = bonuses.duplicate(true)
	return p

static func for_class(ship_class: String) -> Dictionary:
	match ship_class:
		"courier": return profile("courier")
		"freighter", "tanker": return profile("reliable_trucker")
		"hauler": return profile("opportunistic_trucker")
		"miner": return profile("miner")
	return profile("balanced_trader")

static func weight(personality: Dictionary, axis: String) -> float:
	return float(personality.get(axis, 0.0)) if axis in AXES else 0.0

static func drift(personality: Dictionary, axis: String, delta: float) -> bool:
	if not axis in AXES or not is_finite(delta):
		return false
	personality[axis] = clampf(float(personality.get(axis, 0.0)) + delta, 0.0, 1.0)
	return true

static func with_variation(personality: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = personality.duplicate(true)
	for axis in AXES:
		var v: float = clampf(float(result.get(axis, 0.0)) + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
		result[axis] = roundf(v * 100.0) / 100.0
	return result

static func random_ship(rng: RandomNumberGenerator) -> Dictionary:
	var kinds := ["cautious_trader", "aggressive_trader", "balanced_trader", "explorer", "reliable_trucker", "opportunistic_trucker", "courier"]
	return with_variation(profile(kinds[rng.randi_range(0, kinds.size() - 1)]), rng)

static func random_crew(rng: RandomNumberGenerator) -> Dictionary:
	var kinds := ["diligent", "self_preserving", "balanced_trader"]
	return with_variation(profile(kinds[rng.randi_range(0, kinds.size() - 1)]), rng)

static func random_pure(rng: RandomNumberGenerator) -> Dictionary:
	var result := {"prefer_goals": {}}
	for axis in AXES:
		result[axis] = rng.randf_range(0.1, 1.0)
	return result
