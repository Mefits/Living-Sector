extends RefCounted
## N150 native agents/celestial_body.rs::derive_territorial_control.
## Pure derived BodyTerritory and AgentStore.system_control projection.
## This is NOT market_controllers: gates excluded here; INCLUDED
## in native faction_relations.rs market_controllers (N150 relations).

const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1
const MAX_U32: int = 4294967295

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _saturating_credits(a: int,b: int) -> int:
	if b > 0 and a > MAX_I64-b:
		return MAX_I64
	if b < 0 and a < MIN_I64-b:
		return MIN_I64
	return a+b

static func derive(bodies: Array, facilities: Array) -> Dictionary:
	## bodies [{body_id,system_name}], physical owned facilities
	## [{body_id, faction_id, facility_type, credits:i64}].
	## Actual DB/ECS is the only source of identities, not map colors.
	var body_system := {}
	for body in bodies:
		if not (body is Dictionary) or not (body.get("body_id") is String) or 				not (body.get("system_name") is String):
			return _fail("invalid_body_identity")
		if body_system.has(body["body_id"]):
			return _fail("duplicate_body_identity")
		body_system[body["body_id"]] = body["system_name"]
	var by_body := {}
	for facility in facilities:
		if not (facility is Dictionary) or not (facility.get("body_id") is String) or 				not (facility.get("faction_id") is String) or 				not (facility.get("facility_type") is String) or 				typeof(facility.get("credits")) != TYPE_INT:
			return _fail("invalid_actual_facility")
		var faction: String = str(facility["faction_id"])
		if faction.is_empty() or str(facility["facility_type"]) == "gate":
			continue
		var body_id: String = str(facility["body_id"])
		if not body_system.has(body_id):
			continue
		var votes: Dictionary = by_body.get(body_id,{})
		var row: Dictionary = votes.get(faction,{"count":0,"credits":0})
		row["count"] = mini(MAX_U32, int(row["count"])+1)
		row["credits"] = _saturating_credits(int(row["credits"]),int(facility["credits"]))
		votes[faction] = row
		by_body[body_id] = votes
	var territory := {}
	var system_votes := {}
	var ambiguity: Array[Dictionary] = []
	# Iterate body identities in supplied order, but resolve candidate
	# factions in stable sorted order for cross-runtime repeatability.
	for body in bodies:
		var body_id: String = str(body["body_id"])
		var system: String = str(body["system_name"])
		var votes: Dictionary = by_body.get(body_id,{})
		var factions := votes.keys()
		factions.sort()
		var leader: Variant = null
		var winner_count: int = -1
		var winner_credits: int = MIN_I64
		var equal_counts_and_credits: bool = false
		for faction in factions:
			var score: Dictionary = votes[faction]
			var count: int = int(score["count"])
			var cash: int = int(score["credits"])
			if count > winner_count or (count == winner_count and cash > winner_credits):
				leader = str(faction)
				winner_count = count
				winner_credits = cash
				equal_counts_and_credits = false
			elif count == winner_count and cash == winner_credits:
				# Frozen Rust HashMap sorting only counts/credits, NO
				# last tie breaker. Which tied owner wins depends on map
				# iteration. Stable lexical order is an explicit adapter
				# policy, NOT guaranteed bit-identical in such rare ties.
				equal_counts_and_credits = true
		if equal_counts_and_credits:
			ambiguity.append({"body_id":body_id,
				"reason":"Rust_equal_count_and_credits_tie_is_underdetermined"})
		territory[body_id] = {"controlling_faction": leader,
			"contested": factions.size() >= 2}
		var counts: Dictionary = system_votes.get(system,{})
		if leader != null:
			counts[leader] = int(counts.get(leader,0)) + 1
		system_votes[system] = counts
	var systems := {}
	for system in system_votes:
		var counts: Dictionary = system_votes[system]
		var factions := counts.keys()
		factions.sort()
		var top: int = 0
		var leader: Variant = null
		var tied := false
		for faction in factions:
			var n: int = int(counts[faction])
			if n > top:
				top = n
				leader = str(faction)
				tied = false
			elif n == top:
				tied = true
		# Source system tie -> None (even if lexical faction first).
		systems[system] = null if tied else leader
	return {"ok": true, "bodies": territory, "systems": systems,
		"original_rust_undefined_equal_credit_ties": ambiguity,
		"authority": "derived_read_only_actual_body_and_facility_ecs"}

static func body_territory_wire(derived: Dictionary, body_id: String) -> Dictionary:
	if not bool(derived.get("ok", false)) or not (derived.get("bodies") is Dictionary):
		return _fail("invalid_native_body_territory")
	if not derived["bodies"].has(body_id):
		return _fail("unknown_native_body")
	# Original BodySnapshot controller is Option<String>, not a
	# fabricated empty-string faction. actual BodySnapshot includes
	# orbital position/resources from their other macro owners.
	var record: Dictionary = derived["bodies"][body_id]
	return {"ok": true, "controlling_faction": record["controlling_faction"],
		"contested": record["contested"]}
