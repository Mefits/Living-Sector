extends RefCounted
## Frozen Rust: sim_core/agents/ship/components.rs ShipProgression.
## Pure state transitions; successful delivery/retrofit must be authorized externally.
const LEVEL_CAP := 10
const XP_PER_DELIVERY := 15
const U32_MAX := 4294967295
const U8_MAX := 255

static func initial_state() -> Dictionary:
	return {"level": 1, "xp": 0, "retrofit_points": 0, "dirty": false}

static func next_threshold(state: Dictionary) -> int:
	return int(state.get("level", 1)) * 100

static func grant_xp(state: Dictionary, amount: int) -> Dictionary:
	var result := state.duplicate(true)
	var level := int(result.get("level", 1))
	var xp := int(result.get("xp", 0))
	var points := int(result.get("retrofit_points", 0))
	if level < 1 or level > LEVEL_CAP or xp < 0 or points < 0 or amount < 0:
		return {"ok": false, "reason": "invalid_progression"}
	if amount == 0:
		return {"ok": true, "state": result, "levels_gained": 0}
	xp = mini(U32_MAX, xp + amount)
	var gained := 0
	while level < LEVEL_CAP and xp >= level * 100:
		xp -= level * 100
		level += 1
		points = mini(U8_MAX, points + 1)
		gained += 1
	result["level"] = level
	result["xp"] = xp
	result["retrofit_points"] = points
	result["dirty"] = true
	return {"ok": true, "state": result, "levels_gained": gained}

static func grant_delivery_xp(state: Dictionary) -> Dictionary:
	## Call only after a real completed delivery receipt.
	return grant_xp(state, XP_PER_DELIVERY)

static func spend_retrofit_point(state: Dictionary) -> Dictionary:
	## Call only after the authoritative refit transaction succeeds.
	var result := state.duplicate(true)
	var points := int(result.get("retrofit_points", 0))
	if points <= 0:
		return {"ok": false, "reason": "no_retrofit_points", "state": result}
	result["retrofit_points"] = points - 1
	result["dirty"] = true
	return {"ok": true, "state": result}

static func fitting_from_slugs(raw_slots: Dictionary, known_slugs: Dictionary, defaults: Dictionary) -> Dictionary:
	## Rust ShipFitting::from_slugs: unknown non-null slug falls back to slot default.
	## Module effects are supplied by the separate native module catalogue.
	var slots := {}
	for slot in defaults.keys():
		var slug = raw_slots.get(slot, defaults[slot])
		if slug == null:
			slots[slot] = null
		elif known_slugs.has(str(slug)):
			slots[slot] = str(slug)
		else:
			slots[slot] = defaults[slot]
	return slots

static func set_fitting_slot(slots: Dictionary, slot: String, slug: Variant, known_slugs: Dictionary) -> Dictionary:
	if not slots.has(slot) or (slug != null and not known_slugs.has(str(slug))):
		return {"ok": false, "reason": "invalid_slot_or_module"}
	var updated := slots.duplicate(true)
	updated[slot] = slug
	return {"ok": true, "slots": updated, "derived_dirty": true}
