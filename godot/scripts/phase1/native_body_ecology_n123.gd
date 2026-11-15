extends RefCounted
## Frozen Rust: agents/celestial_body.rs::BodyBiome, resource_grade, tick_bodies_regen.
## No grade multiplier on extraction: grades are descriptive only.
const REGEN_RATE := 0.0005
const REGEN_INTERVAL_BASE := 5

static func food_multiplier(biome: String) -> float:
	match biome:
		"terrestrial", "temperate", "earthlike": return 1.5
		"ocean", "aquatic": return 1.3
		"forest", "jungle": return 1.4
		"tundra", "arctic": return 0.7
		"desert", "arid": return 0.5
		"volcanic", "molten": return 0.3
		"lifeless", "barren", "rock", "moon": return 0.2
		"asteroid", "belt": return 0.1
		"ice", "frozen": return 0.6
	return 1.0

static func resource_grade(richness: float) -> int:
	if not is_finite(richness) or richness <= 0.0:
		return 0
	if richness < 0.25: return 1
	if richness < 0.45: return 2
	if richness < 0.65: return 3
	if richness < 0.85: return 4
	return 5

## Caller owns tick cadence; result is a copy, not an inventory transaction.
## Current richness is finite; mined depletion must be committed elsewhere.
static func regenerate(body_resources: Dictionary, tick: int, tick_scale: float, tick_multiplier: int) -> Dictionary:
	var result := body_resources.duplicate(true)
	var interval := REGEN_INTERVAL_BASE * tick_multiplier
	if interval <= 0 or tick % interval != 0 or not is_finite(tick_scale):
		return result
	var current: Dictionary = result.get("resources", {})
	var ceilings: Dictionary = result.get("max_resources", {})
	var rate := REGEN_RATE * tick_scale * float(interval)
	for commodity in current.keys():
		if not ceilings.has(commodity):
			continue
		var ceiling := float(ceilings[commodity])
		var value := float(current[commodity])
		if not is_finite(ceiling) or not is_finite(value):
			continue
		current[commodity] = minf(value + rate * ceiling, ceiling)
	result["resources"] = current
	return result
