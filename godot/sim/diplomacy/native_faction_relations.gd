extends RefCounted
## Frozen Rust: native/crates/sim_core/src/agents/faction_relations.rs
## Pairwise diplomacy is authoritative here; no world money or goods are changed.
var pairs: Dictionary = {}
const TREATIES := ["neutral", "trade_pact", "allied", "tense", "hostile", "war"]

func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func state(a: String, b: String) -> Dictionary:
	if a == b or a.is_empty() or b.is_empty():
		return {}
	return pairs.get(_key(a, b), {"standing": 0, "treaty": "neutral", "since_tick": 0, "last_event_tick": 0}).duplicate(true)

func bump_standing(a: String, b: String, delta: int, tick: int) -> int:
	if a == b or a.is_empty() or b.is_empty():
		return 0
	var k := _key(a, b)
	var s: Dictionary = pairs.get(k, {"standing": 0, "treaty": "neutral", "since_tick": tick, "last_event_tick": tick})
	s.standing = clampi(int(s.standing) + delta, -100, 100)
	s.last_event_tick = tick
	pairs[k] = s
	return s.standing

func set_state(a: String, b: String, standing: int, treaty: String, tick: int) -> bool:
	if a == b or a.is_empty() or b.is_empty() or not TREATIES.has(treaty):
		return false
	var k := _key(a, b)
	var s: Dictionary = pairs.get(k, {"standing": 0, "treaty": "neutral", "since_tick": tick, "last_event_tick": tick})
	if s.treaty != treaty:
		s.since_tick = tick
	s.treaty = treaty
	s.standing = clampi(standing, -100, 100)
	s.last_event_tick = tick
	pairs[k] = s
	return true

func tick_relations(tick: int, multiplier: int = 1) -> Array:
	var changes: Array = []
	var scale := maxi(1, multiplier)
	var keys := pairs.keys()
	keys.sort()
	for key in keys:
		var s: Dictionary = pairs[key]
		if tick - int(s.last_event_tick) >= 2000 * scale and absi(int(s.standing)) > 1:
			s.standing = int(s.standing) - signi(int(s.standing))
		var old: String = s.treaty
		var score: int = s.standing
		var elapsed := maxi(0, tick - int(s.since_tick))
		var next := old
		if old == "war":
			pass
		elif score <= -70:
			next = "hostile"
		elif score <= -50 and ["neutral", "trade_pact", "allied"].has(old):
			next = "tense"
		elif old == "hostile" and score >= -40:
			next = "tense"
		elif old == "tense" and score >= -20:
			next = "neutral"
		elif old == "neutral" and score >= 50 and elapsed >= 500 * scale:
			next = "trade_pact"
		elif old == "trade_pact":
			if score >= 75 and elapsed >= 1000 * scale:
				next = "allied"
			elif score < 20:
				next = "neutral"
		elif old == "allied" and score < 50:
			next = "trade_pact"
		if next != old:
			s.treaty = next
			s.since_tick = tick
			var ids := String(key).split("|")
			changes.append({"a": ids[0], "b": ids[1], "from": old, "to": next, "standing": score})
		pairs[key] = s
	return changes

func commerce_allowed(a: String, b: String) -> bool:
	return not ["hostile", "war"].has(String(state(a, b).get("treaty", "neutral")))

func dock_modifiers(a: String, b: String) -> Vector2:
	if a == b or a.is_empty() or b.is_empty():
		return Vector2.ONE
	match state(a, b).get("treaty", "neutral"):
		"trade_pact": return Vector2(0.8, 0.5)
		"allied": return Vector2(0.6, 0.0)
	return Vector2.ONE

func payment_multiplier(a: String, b: String) -> float:
	if a == b or a.is_empty() or b.is_empty():
		return 1.0
	match state(a, b).get("treaty", "neutral"):
		"trade_pact": return 1.10
		"allied": return 1.15
	return 1.0

func market_buy_multiplier(ship_faction: String, reputation: int, owner: String) -> float:
	var rep := 50 if owner.is_empty() else (100 if ship_faction == owner and not ship_faction.is_empty() else reputation)
	var base := clampf(1.0 + (50.0 - float(rep)) * 0.005, 0.75, 1.25)
	if ["hostile", "war"].has(state(ship_faction, owner).get("treaty", "neutral")) and base > 1.0:
		return 1.0 + (base - 1.0) * 2.0
	return base

func market_sell_multiplier(ship_faction: String, reputation: int, owner: String) -> float:
	return 1.0 / market_buy_multiplier(ship_faction, reputation, owner)

func snapshot() -> Dictionary:
	return pairs.duplicate(true)
