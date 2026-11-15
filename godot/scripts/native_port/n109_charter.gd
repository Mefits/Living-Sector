extends RefCounted
## N109: native strategy/charter.rs. Pure admission; caller owns Director and ledger.
const RESEARCH := "research"
const ECONOMY := "economy"
const DELEGATED := "delegated"
const REVIEW := "review"
const AUTONOMOUS := "autonomous"
const MAX_CREDITS := 1000000000

static func default_charter() -> Dictionary:
	return {"research_authority": DELEGATED, "economy_authority": DELEGATED,
		"research_priority": 50, "economy_priority": 50,
		"shared_ceiling_cr": 10000, "protected_treasury_cr": 10000,
		"approved_research_cr": 0, "approved_economy_cr": 0,
		"spent_cr": 0, "spent_research_cr": 0, "spent_economy_cr": 0,
		"updated_tick": 0, "last_reason": ""}

static func validate(c: Dictionary) -> String:
	if not _range(c, "shared_ceiling_cr", 100, MAX_CREDITS) or not _range(c, "protected_treasury_cr", 10000, MAX_CREDITS):
		return "invalid_charter_budget_or_reserve"
	if not _range(c, "research_priority", 0, 100) or not _range(c, "economy_priority", 0, 100):
		return "invalid_charter_priority"
	for department in [RESEARCH, ECONOMY]:
		if not [DELEGATED, REVIEW, AUTONOMOUS].has(c.get(department + "_authority", "")):
			return "invalid_charter_authority"
		if not _range(c, "approved_" + department + "_cr", 0, MAX_CREDITS):
			return "invalid_approval_tranche"
	var spent := int(c.get("spent_cr", -1))
	var rs := int(c.get("spent_research_cr", -1))
	var es := int(c.get("spent_economy_cr", -1))
	if spent < 0 or rs < 0 or es < 0 or spent != rs + es or spent > int(c["shared_ceiling_cr"]):
		return "invalid_charter_ledger"
	if c["research_authority"] == REVIEW and int(c["approved_research_cr"]) < rs:
		return "research_approval_below_paid_receipts"
	if c["economy_authority"] == REVIEW and int(c["approved_economy_cr"]) < es:
		return "economy_approval_below_paid_receipts"
	return ""

static func _range(c: Dictionary, key: String, low: int, high: int) -> bool:
	return c.has(key) and typeof(c[key]) == TYPE_INT and int(c[key]) >= low and int(c[key]) <= high

static func gate(c: Dictionary, department: String, payment: int, treasury: int) -> String:
	if department != RESEARCH and department != ECONOMY:
		return "invalid_department"
	var invalid := validate(c)
	if invalid != "":
		return invalid
	if c[department + "_authority"] == AUTONOMOUS:
		return "player_mandates_disabled_in_charter"
	if payment <= 0:
		return "invalid_native_payment"
	if payment > int(c["shared_ceiling_cr"]) - int(c["spent_cr"]):
		return "shared_mandate_budget_exhausted"
	if treasury < payment or treasury - payment < int(c["protected_treasury_cr"]):
		return "charter_treasury_reserve"
	if c[department + "_authority"] == REVIEW and payment > int(c["approved_" + department + "_cr"]) - int(c["spent_" + department + "_cr"]):
		return "player_approval_required"
	return ""

static func authorize(charters: Dictionary, faction: String, department: String, payment: int, treasury: int) -> String:
	if not charters.has(faction):
		return "" # Rust: absent charter retains old 0.6.1 mandates
	return gate(charters[faction], department, payment, treasury)

static func may_direct(charters: Dictionary, faction: String, department: String) -> bool:
	return not charters.has(faction) or charters[faction].get(department + "_authority") != AUTONOMOUS

static func priority_score(charters: Dictionary, faction: String, department: String, baseline: float) -> float:
	if not charters.has(faction):
		return baseline
	return baseline + 2.0 * (float(charters[faction].get(department + "_priority", 50)) - 50.0)

static func install(charters: Dictionary, faction: String, incoming: Dictionary, known_factions: Array, tick: int) -> Dictionary:
	if not known_factions.has(faction):
		return {"error": "unknown_faction"}
	var next := incoming.duplicate(true)
	var previous: Dictionary = charters.get(faction, {})
	for key in ["spent_cr", "spent_research_cr", "spent_economy_cr"]:
		next[key] = previous.get(key, 0)
	next["updated_tick"] = tick
	var error := validate(next)
	if error != "":
		return {"error": error}
	next["last_reason"] = "charter_applied_native_engine"
	return {"charter": next} # caller commits to Director

static func paid_receipt(c: Dictionary, department: String, amount: int) -> Dictionary:
	if amount <= 0 or not [RESEARCH, ECONOMY].has(department):
		return {"error": "invalid_native_payment"}
	var next := c.duplicate(true)
	if amount > MAX_CREDITS - int(next.get("spent_cr", 0)):
		return {"error": "invalid_charter_ledger"}
	next["spent_cr"] = int(next["spent_cr"]) + amount
	next["spent_" + department + "_cr"] = int(next["spent_" + department + "_cr"]) + amount
	next["last_reason"] = "native_paid_receipt_recorded"
	var error := validate(next)
	if error != "":
		return {"error": error}
	return {"charter": next} # only AFTER actual paid native receipt; no money transfer here
