extends RefCounted
## Exact scoring rules from crates/sim_core/src/ai/utility.rs.
## Considerations: name -> {"value": float, "axis": String}; personality is N86 schema.
## Specs: {"name": String, "factors": [{"key": String, "direction": "Positive"|"Negative"}]}.
## No world mutation, no implicit actions.
static func consideration(value: float, axis: String) -> Dictionary:
	return {"value": clampf(value, 0.0, 1.0), "axis": axis}

static func score_action(spec: Dictionary, considerations: Dictionary, personality: Dictionary) -> float:
	var total := 0.0
	for factor in spec.get("factors", []):
		var key: String = str(factor.get("key", ""))
		if not considerations.has(key):
			continue
		var c: Dictionary = considerations[key]
		var axis: String = str(c.get("axis", ""))
		var weight: float = float(personality.get(axis, 0.0))
		var contribution: float = float(c.get("value", 0.0)) * weight
		if factor.get("direction") == "Negative":
			total -= contribution
		else:
			total += contribution
	return total

static func best_action(actions: Array, considerations: Dictionary, personality: Dictionary) -> Dictionary:
	var winner := "idle"
	var best := 0.0
	var bonuses: Dictionary = personality.get("prefer_goals", {})
	for spec in actions:
		var name: String = str(spec.get("name", ""))
		var score: float = score_action(spec, considerations, personality) + float(bonuses.get(name, 0.0))
		# Rust uses strict greater-than: ties keep earlier action; non-positive means idle.
		if score > best:
			best = score
			winner = name
	return {"name": winner, "score": best}

static func rank_actions(actions: Array, considerations: Dictionary, personality: Dictionary) -> Array:
	var bonuses: Dictionary = personality.get("prefer_goals", {})
	var ranked: Array = []
	for spec in actions:
		var name: String = str(spec.get("name", ""))
		ranked.append({"name": name, "score": score_action(spec, considerations, personality) + float(bonuses.get(name, 0.0))})
	# Rust sort is descending; ties are not a ranking preference.
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return ranked
