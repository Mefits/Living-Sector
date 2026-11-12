extends RefCounted
## N150 — full native agents/faction_relations.rs matrix/relations consumers.
## One canonical symmetric relation per unordered faction pair.
## ALL functions return stage-only data or effects; no money, docking,
## physical cargo or treaty enforcement executed from this module.

const MIN_STANDING: int = -100
const MAX_STANDING: int = 100
const MAX_I32: int = 2147483647
const TREATIES := ["neutral", "trade_pact", "allied", "tense", "hostile", "war"]
const RELATIONS_TICK_INTERVAL_BASE: int = 200
const STANDING_DECAY_FRESHNESS_GRACE_BASE: int = 2000
const STANDING_DECAY_DEADBAND: int = 1
const STANDING_DECAY_PER_PASS: int = 1
const TRADE_PACT_SUSTAIN_BASE: int = 500
const ALLIED_SUSTAIN_BASE: int = 1000
const DELIVERY_STANDING_BUMP: int = 2
const BREACH_STANDING_PENALTY: int = -1

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _pair(a: String, b: String) -> Dictionary:
	if a == b:
		return {}
	if a <= b:
		return {"a": a, "b": b, "key": JSON.stringify([a,b])}
	return {"a": b, "b": a, "key": JSON.stringify([b,a])}

static func _state_at(tick: int = 0) -> Dictionary:
	return {"standing": 0, "treaty": "neutral",
		"since_tick": tick, "last_event_tick": tick}

static func _valid_state(state: Dictionary) -> bool:
	if typeof(state.get("standing")) != TYPE_INT or 			int(state["standing"]) < MIN_STANDING or int(state["standing"]) > MAX_STANDING:
		return false
	if not (state.get("treaty") is String) or str(state["treaty"]) not in TREATIES:
		return false
	for k in ["since_tick", "last_event_tick"]:
		if typeof(state.get(k)) != TYPE_INT or int(state[k]) < 0:
			return false
	return true

static func validate_pairs(pairs: Dictionary) -> bool:
	for key in pairs:
		var row = pairs[key]
		if not (key is String) or not (row is Dictionary):
			return false
		var a = row.get("a", null)
		var b = row.get("b", null)
		if not (a is String) or not (b is String):
			return false
		var p := _pair(a,b)
		if p.is_empty() or str(p["key"]) != key or str(p["a"]) != a or str(p["b"]) != b:
			return false
		if not _valid_state(row):
			return false
	return true

static func state(pairs: Dictionary, a: String, b: String) -> Dictionary:
	## Frozen FactionRelations::state returns None for self pair and
	## state_or_default returns neutral; this reads the latter.
	var key := _pair(a,b)
	if key.is_empty():
		return _state_at()
	var value = pairs.get(key["key"], null)
	return value.duplicate(true) if value is Dictionary else _state_at()

static func state_optional(pairs: Dictionary, a: String, b: String) -> Dictionary:
	var key := _pair(a,b)
	if key.is_empty() or not pairs.has(key["key"]):
		return {"present": false, "state": {}}
	return {"present": true, "state": pairs[key["key"]].duplicate(true)}

static func bump_standing(pairs: Dictionary, a: String, b: String,
		delta: int, tick: int) -> Dictionary:
	## Source does not change treaty or since_tick on standing bump.
	if tick < 0 or delta < -MAX_I32 - 1 or delta > MAX_I32 or not validate_pairs(pairs):
		return _fail("invalid_standing_delta_or_pairs")
	if a == b:
		return {"ok": true, "pairs": pairs.duplicate(true), "standing": 0}
	var key := _pair(a,b)
	var next := pairs.duplicate(true)
	var prior: Dictionary = next.get(key["key"], _state_at(tick))
	prior["standing"] = clampi(int(prior["standing"]) + delta, MIN_STANDING, MAX_STANDING)
	prior["last_event_tick"] = tick
	prior["a"] = key["a"]
	prior["b"] = key["b"]
	next[key["key"]] = prior
	return {"ok": true, "pairs": next, "standing": int(prior["standing"])}

static func set_treaty(pairs: Dictionary, a: String, b: String,
		treaty: String, tick: int) -> Dictionary:
	## If treaty unchanged, Rust returns immediately, no since_tick reset.
	if tick < 0 or treaty not in TREATIES or not validate_pairs(pairs):
		return _fail("invalid_treaty_or_pairs")
	if a == b:
		return {"ok": true, "pairs": pairs.duplicate(true)}
	var key := _pair(a,b)
	var next := pairs.duplicate(true)
	var created: bool = not next.has(key["key"])
	var prior: Dictionary = next.get(key["key"], _state_at(tick))
	if prior["treaty"] == treaty:
		# Rust entry(...).or_insert_with creates a NEUTRAL pair even
		# when set_treaty(Neutral) makes no state change.
		if created:
			prior["a"] = key["a"]
			prior["b"] = key["b"]
			next[key["key"]] = prior
		return {"ok": true, "pairs": next}
	prior["treaty"] = treaty
	prior["since_tick"] = tick
	prior["last_event_tick"] = tick
	prior["a"] = key["a"]
	prior["b"] = key["b"]
	next[key["key"]] = prior
	return {"ok": true, "pairs": next}

static func set_state(pairs: Dictionary, a: String, b: String,
		standing: int, treaty: String, tick: int) -> Dictionary:
	## Original admin override resets treaty clock only if changed.
	if tick < 0 or treaty not in TREATIES or not validate_pairs(pairs):
		return _fail("invalid_admin_relation")
	if a == b:
		return {"ok": true, "pairs": pairs.duplicate(true)}
	var key := _pair(a,b)
	var next := pairs.duplicate(true)
	var prior: Dictionary = next.get(key["key"], _state_at(tick))
	var changed: bool = prior["treaty"] != treaty
	prior["standing"] = clampi(standing, MIN_STANDING, MAX_STANDING)
	prior["treaty"] = treaty
	prior["last_event_tick"] = tick
	if changed:
		prior["since_tick"] = tick
	prior["a"] = key["a"]
	prior["b"] = key["b"]
	next[key["key"]] = prior
	return {"ok": true, "pairs": next}

static func pass_due(tick: int, multiplier: int) -> bool:
	## Source caller in sim_server runs after 200×mult. This utility
	## does not advance standing; server caller enforces at-most-once.
	return tick >= 0 and multiplier > 0 and 		tick % (RELATIONS_TICK_INTERVAL_BASE * multiplier) == 0

static func _next_treaty(current: String, score: int, sustained: int,
		trade_sustain: int, ally_sustain: int) -> String:
	if current == "war":
		return "war" # War only enters/exits by explicit act.
	if score <= -70:
		return "hostile"
	if score <= -50 and current in ["neutral","trade_pact","allied"]:
		return "tense"
	match current:
		"hostile":
			if score >= -40:
				return "tense"
		"tense":
			if score >= -20:
				return "neutral"
		"neutral":
			if score >= 50 and sustained >= trade_sustain:
				return "trade_pact"
		"trade_pact":
			if score >= 75 and sustained >= ally_sustain:
				return "allied"
			if score < 20:
				return "neutral"
		"allied":
			if score < 50:
				return "trade_pact"
	return current

static func tick_relations(pairs: Dictionary, tick: int, tick_multiplier: int) -> Dictionary:
	## Frozen tick_relations itself does NOT gate 200×mult: caller must
	## call pass_due BEFORE it. Do not invent internal replan cadence.
	if tick < 0 or tick_multiplier < 0 or not validate_pairs(pairs):
		return _fail("invalid_native_diplomacy_tick")
	var fresh_grace: int = STANDING_DECAY_FRESHNESS_GRACE_BASE * maxi(1,tick_multiplier)
	var trade_sustain: int = TRADE_PACT_SUSTAIN_BASE * maxi(1,tick_multiplier)
	var ally_sustain: int = ALLIED_SUSTAIN_BASE * maxi(1,tick_multiplier)
	var next := pairs.duplicate(true)
	var changes: Array[Dictionary] = []
	var keys := next.keys()
	keys.sort()
	for key in keys:
		var row: Dictionary = next[key]
		var last: int = int(row["last_event_tick"])
		var since: int = int(row["since_tick"])
		var fresh: bool = maxi(0,tick - last) < fresh_grace
		var standing: int = int(row["standing"])
		if not fresh and absi(standing) > STANDING_DECAY_DEADBAND:
			var step: int = mini(STANDING_DECAY_PER_PASS, absi(standing))
			standing += -step if standing > 0 else step
		row["standing"] = standing
		var old: String = str(row["treaty"])
		var to: String = _next_treaty(old, standing, maxi(0,tick-since),
			trade_sustain, ally_sustain)
		if to != old:
			row["treaty"] = to
			row["since_tick"] = tick
			# Source deliberately DOES NOT touch last_event_tick when
			# treaty transitions; freshness applies only to standing.
			changes.append({"a": row["a"], "b": row["b"],
				"from": old, "to": to, "standing": standing})
		next[key] = row
	return {"ok": true, "pairs": next, "treaty_changes": changes,
		"authority": "one_native_faction_relations_matrix"}

static func _special_treaty(pairs: Dictionary, a: String, b: String) -> String:
	if a.is_empty() or b.is_empty() or a == b:
		return "neutral"
	return str(state(pairs,a,b)["treaty"])

static func trade_pact_dock_modifier(pairs: Dictionary, ship: String, facility: String) -> Dictionary:
	## Pair of actual fee and burn factors consumed by real Dock commit.
	match _special_treaty(pairs,ship,facility):
		"trade_pact":
			return {"fee_factor":0.8,"burn_factor":0.5}
		"allied":
			return {"fee_factor":0.6,"burn_factor":0.0}
	return {"fee_factor":1.0,"burn_factor":1.0}

static func trade_pact_payment_multiplier(pairs: Dictionary, ship: String, requestor: String) -> float:
	match _special_treaty(pairs,ship,requestor):
		"trade_pact":
			return 1.10
		"allied":
			return 1.15
	return 1.0

static func trade_pact_grants_visibility(pairs: Dictionary, ship: String, requestor: String) -> bool:
	if ship.is_empty() or requestor.is_empty() or ship == requestor:
		return ship == requestor
	return _special_treaty(pairs,ship,requestor) in ["trade_pact","allied"]

static func treaty_rep_floors(pairs: Dictionary, ship: String) -> Dictionary:
	var floors := {}
	if ship.is_empty():
		return floors
	for key in pairs:
		var row: Dictionary = pairs[key]
		var other := ""
		if str(row["a"]) == ship:
			other = str(row["b"])
		elif str(row["b"]) == ship:
			other = str(row["a"])
		if other.is_empty():
			continue
		if str(row["treaty"]) == "trade_pact":
			floors[other] = 50
		elif str(row["treaty"]) == "allied":
			floors[other] = 70
	return floors

static func market_controllers(facilities: Array) -> Dictionary:
	## Original faction_relations.rs::market_controllers uses facilities
	## at each LOCATION, even gate facilities. BodyTerritory differs
	## intentionally: gates don't count toward body territorial control.
	## Tie picks lowest lexical faction id.
	var per_location := {}
	for fac in facilities:
		if not (fac is Dictionary) or not (fac.get("location") is String) or 				not (fac.get("faction_id") is String):
			return {}
		var owner: String = str(fac["faction_id"])
		if owner.is_empty():
			continue
		var location: String = str(fac["location"])
		var votes: Dictionary = per_location.get(location,{})
		votes[owner] = int(votes.get(owner,0)) + 1
		per_location[location] = votes
	var controllers := {}
	for location in per_location:
		var votes: Dictionary = per_location[location]
		var candidates := votes.keys()
		candidates.sort()
		var best := ""
		var count := 0
		for owner in candidates:
			if int(votes[owner]) > count:
				best = str(owner)
				count = int(votes[owner])
		if not best.is_empty():
			controllers[location] = best
	return controllers

static func commerce_allowed(pairs: Dictionary, from_faction: String, market_owner: String) -> bool:
	return not (_special_treaty(pairs,from_faction,market_owner) in ["hostile","war"])

static func own_market_priority(from_faction: String, market_owner: String) -> float:
	return 1.25 if not from_faction.is_empty() and from_faction == market_owner else 1.0

static func market_buy_multiplier(pairs: Dictionary, ship_faction: String,
		reputation: int, market_owner: String) -> float:
	## Native price posting stays UNCHANGED; per-ship multiplier applies
	## only when actual trade commits with a real market controller.
	var rep: int = 50 if market_owner.is_empty() else (
		100 if not ship_faction.is_empty() and ship_faction == market_owner else reputation)
	rep = clampi(rep,0,100)
	var base: float = clampf(1.0 + (50.0-float(rep))*0.005,0.75,1.25)
	var hostile: bool = _special_treaty(pairs,ship_faction,market_owner) in ["hostile","war"]
	return 1.0+(base-1.0)*2.0 if hostile and base > 1.0 else base

static func market_sell_multiplier(pairs: Dictionary, ship_faction: String,
		reputation: int, market_owner: String) -> float:
	return 1.0 / market_buy_multiplier(pairs,ship_faction,reputation,market_owner)
