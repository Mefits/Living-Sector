extends RefCounted
## Source: frozen native/crates/sim_core/src/strategy/director.rs::environmental_events.
## Pure staged mutation; caller applies to authoritative FacilityOperations atomically.
const CRISIS_INTERVAL_TICKS := 2400
const DAMAGE := 0.3
const MIN_CONDITION := 0.1
const ELIGIBLE_CONDITION := 0.35

static func propose_event(faction_id: String, tick: int, multiplier: int, next_crisis_tick: int, facilities: Array) -> Dictionary:
	if tick < next_crisis_tick:
		return {"due": false}
	var eligible: Array = []
	for facility in facilities:
		if not facility is Dictionary:
			continue
		if str(facility.get("faction_id", "")) != faction_id:
			continue
		if str(facility.get("facility_type", "")) != "refinery":
			continue
		if float(facility.get("condition", 0.0)) <= ELIGIBLE_CONDITION:
			continue
		eligible.append(facility)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	var result := {
		"due": true,
		"next_crisis_tick": tick + CRISIS_INTERVAL_TICKS * maxi(multiplier, 1),
		"damage": false
	}
	if eligible.is_empty():
		return result
	var chosen: Dictionary = eligible[0]
	result["damage"] = true
	result["facility_id"] = str(chosen.get("id", ""))
	result["new_condition"] = maxf(float(chosen.get("condition", 0.0)) - DAMAGE, MIN_CONDITION)
	result["record"] = {"tick": tick, "action": "industrial_accident", "reason": result["facility_id"], "outcome": "condition_minus_0.30"}
	return result
