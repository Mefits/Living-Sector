extends RefCounted
## CODE_UNVERIFIED. Frozen Rust agents/faction_relations.rs pairwise standing/treaty.
## This is the canonical data owner, not a substitute for treaty transition cadence.
const TREATIES := ["neutral", "trade_pact", "allied", "tense", "hostile", "war"]
var _pairs: Dictionary = {}

static func pair_key(a: String, b: String) -> String:
	if a.is_empty() or b.is_empty() or a == b:
		return ""
	return JSON.stringify([a, b] if a < b else [b, a])

func set_state(a: String, b: String, standing: int, treaty: String, tick: int) -> bool:
	var key := pair_key(a, b)
	if key.is_empty() or not TREATIES.has(treaty) or tick < 0:
		return false
	var previous: Dictionary = _pairs.get(key, {})
	if not previous.is_empty() and tick < int(previous["last_event_tick"]):
		return false
	_pairs[key] = {"a": a if a < b else b, "b": b if a < b else a, "standing": clampi(standing, -100, 100), "treaty": treaty, "since_tick": tick, "last_event_tick": tick}
	return true

func bump(a: String, b: String, delta: int, tick: int) -> bool:
	var key := pair_key(a, b)
	if key.is_empty() or tick < 0:
		return false
	var old: Dictionary = _pairs.get(key, {})
	if not old.is_empty() and tick < int(old["last_event_tick"]):
		return false
	var current: int = int(old.get("standing", 0))
	var treaty: String = str(old.get("treaty", "neutral"))
	var since: int = int(old.get("since_tick", tick))
	_pairs[key] = {"a": a if a < b else b, "b": b if a < b else a, "standing": clampi(current + delta, -100, 100), "treaty": treaty, "since_tick": since, "last_event_tick": tick}
	return true

func state(a: String, b: String) -> Dictionary:
	return _pairs.get(pair_key(a, b), {"standing": 0, "treaty": "neutral", "since_tick": 0, "last_event_tick": 0}).duplicate(true)

func commerce_allowed(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty() or a == b:
		return true
	return not ["hostile", "war"].has(str(state(a, b)["treaty"]))

func payment_multiplier(a: String, b: String) -> float:
	if a.is_empty() or b.is_empty() or a == b:
		return 1.0
	match str(state(a, b)["treaty"]):
		"trade_pact":
			return 1.10
		"allied":
			return 1.15
	return 1.0

func dock_modifiers(a: String, b: String) -> Vector2:
	if a.is_empty() or b.is_empty() or a == b:
		return Vector2(1.0, 1.0)
	match str(state(a, b)["treaty"]):
		"trade_pact":
			return Vector2(0.8, 0.5)
		"allied":
			return Vector2(0.6, 0.0)
	return Vector2(1.0, 1.0)

func visibility_floor(a: String, b: String) -> int:
	if a.is_empty() or b.is_empty() or a == b:
		return 0
	match str(state(a, b)["treaty"]):
		"trade_pact":
			return 50
		"allied":
			return 70
	return 0

func snapshot() -> Dictionary:
	return {"version": 1, "pairs": _pairs.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or typeof(data.get("pairs")) != TYPE_DICTIONARY:
		return false
	var candidate: Dictionary = data["pairs"]
	for key in candidate:
		var s = candidate[key]
		if typeof(s) != TYPE_DICTIONARY or not s.has("a") or not s.has("b") or not s.has("standing") or not s.has("treaty") or not s.has("since_tick") or not s.has("last_event_tick"):
			return false
		if typeof(s["a"]) != TYPE_STRING or typeof(s["b"]) != TYPE_STRING or key != pair_key(s["a"], s["b"]) or not TREATIES.has(s["treaty"]):
			return false
		if typeof(s["standing"]) != TYPE_INT or abs(s["standing"]) > 100 or typeof(s["since_tick"]) != TYPE_INT or typeof(s["last_event_tick"]) != TYPE_INT:
			return false
		if s["since_tick"] < 0 or s["last_event_tick"] < 0:
			return false
	_pairs = candidate.duplicate(true)
	return true
