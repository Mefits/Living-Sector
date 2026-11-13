extends RefCounted
## Frozen Rust: agents/celestial_body.rs::derive_territorial_control.
## Inputs: bodies [{body_id,system_name}], facilities [{body_id,faction_id,facility_type,credits}].
## Pure derived view; never grants ownership or creates a facility.
static func derive(bodies: Array, facilities: Array) -> Dictionary:
	var tallies: Dictionary = {}
	for facility in facilities:
		if not facility is Dictionary:
			continue
		var faction := str(facility.get("faction_id", ""))
		if faction.is_empty() or str(facility.get("facility_type", "")) == "gate":
			continue
		var body := str(facility.get("body_id", ""))
		if not tallies.has(body):
			tallies[body] = {}
		var by_faction: Dictionary = tallies[body]
		var current: Dictionary = by_faction.get(faction, {"count": 0, "credits": 0})
		current["count"] = int(current["count"]) + 1
		current["credits"] = int(current["credits"]) + int(facility.get("credits", 0))
		by_faction[faction] = current
	var territory: Dictionary = {}
	var system_counts: Dictionary = {}
	for body in bodies:
		if not body is Dictionary:
			continue
		var body_id := str(body.get("body_id", ""))
		var system := str(body.get("system_name", ""))
		var counts: Dictionary = tallies.get(body_id, {})
		var leader := ""
		var best_count := -1
		var best_credits := -9223372036854775807
		for faction in counts.keys():
			var entry: Dictionary = counts[faction]
			var count := int(entry["count"])
			var credits := int(entry["credits"])
			if count > best_count or (count == best_count and credits > best_credits) or (count == best_count and credits == best_credits and str(faction) < leader):
				leader = str(faction)
				best_count = count
				best_credits = credits
		territory[body_id] = {"controlling_faction": leader, "contested": counts.size() >= 2}
		if not system_counts.has(system):
			system_counts[system] = {}
		if not leader.is_empty():
			var per_system: Dictionary = system_counts[system]
			per_system[leader] = int(per_system.get(leader, 0)) + 1
	var system_control: Dictionary = {}
	for system in system_counts.keys():
		var votes: Dictionary = system_counts[system]
		var highest := 0
		var winner := ""
		var tied := false
		for faction in votes.keys():
			var n := int(votes[faction])
			if n > highest:
				highest = n
				winner = str(faction)
				tied = false
			elif n == highest:
				tied = true
		system_control[system] = "" if tied else winner
	return {"bodies": territory, "systems": system_control}
