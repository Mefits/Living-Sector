extends RefCounted
## Frozen Rust: sim_core/src/agents/ship/components.rs::ShipCrewSkills.
## No world mutation. GrantCrewXp must be admitted by authoritative command layer.
const CAP := 100
const DEFAULTS := {"navigation": 30, "engineering": 30, "trading": 30, "combat": 20}
const ROLE_SKILL := {"pilot": "navigation", "engineer": "engineering", "trader": "trading"}

static func for_roles(roles: Array) -> Dictionary:
	var skills := DEFAULTS.duplicate(true)
	for role in roles:
		var key: String = ROLE_SKILL.get(str(role), "")
		if key != "":
			skills[key] = mini(CAP, int(skills[key]) + 10)
	return skills

static func grant(skills: Dictionary, skill: String, amount: int) -> Dictionary:
	var result := skills.duplicate(true)
	if not DEFAULTS.has(skill) or amount < 0 or amount > 255:
		return {"ok": false, "reason": "invalid_skill_or_u8_amount", "skills": result}
	if not result.has(skill):
		return {"ok": false, "reason": "missing_skill", "skills": result}
	result[skill] = mini(CAP, maxi(0, int(result[skill])) + amount)
	return {"ok": true, "skills": result}

static func grant_receipt(skills: Dictionary, receipt: Dictionary, seen: Dictionary) -> Dictionary:
	var id := str(receipt.get("id", ""))
	if id.is_empty() or seen.has(id) or not bool(receipt.get("confirmed", false)):
		return {"ok": false, "reason": "unconfirmed_or_duplicate", "skills": skills.duplicate(true)}
	var outcome := grant(skills, str(receipt.get("skill", "")), int(receipt.get("amount", -1)))
	if bool(outcome.get("ok", false)):
		seen[id] = true
	return outcome
