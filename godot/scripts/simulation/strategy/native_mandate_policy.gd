extends RefCounted
## Frozen Rust: native/crates/sim_core/src/strategy/{governance,economic_mandate}.rs
## Policy admission only; the existing Director/ledger owns all actual charges.
const MODES := ["delegated", "advise", "hold"]
const SUPPLY := ["food", "water", "fuel", "metals", "components", "electronics", "tools", "alloys"]
const INDUSTRY := ["food", "water", "fuel", "metals", "components", "electronics", "tools", "alloys", "quantum_cores"]

static func validate_research(m: Dictionary, known_technology_ids: Array) -> String:
	if int(m.get("budget_ceiling_cr", 0)) < 100 or int(m.get("budget_ceiling_cr", 0)) > 1000000000:
		return "invalid_mandate_budget"
	if int(m.get("treasury_floor_cr", 0)) < 10000 or int(m.get("treasury_floor_cr", 0)) > 1000000000:
		return "invalid_treasury_floor"
	if not known_technology_ids.has(str(m.get("target_technology", ""))):
		return "unknown_technology"
	if int(m.get("spent_cr", 0)) < 0 or int(m.get("spent_cr", 0)) > int(m["budget_ceiling_cr"]):
		return "invalid_committed_amount"
	return ""

## techs: technology ID -> {prerequisite: null or technology ID}.
static func next_technology(target: String, known: Array, techs: Dictionary) -> Dictionary:
	if not techs.has(target):
		return {"error": "unknown_technology"}
	var next := target
	for i in range(techs.size()):
		if known.has(next):
			return {"technology": null}
		var prereq: Variant = techs[next].get("prerequisite", null)
		if prereq != null and not known.has(prereq):
			next = str(prereq)
			if not techs.has(next):
				return {"error": "invalid_technology_graph"}
			continue
		return {"technology": next}
	return {"error": "technology_dependency_cycle"}

static func preserve_research_approval(old: Dictionary, incoming: Dictionary, tick: int) -> Dictionary:
	var result := incoming.duplicate(true)
	if not old.is_empty() and old.get("target_technology") == result.get("target_technology"):
		result["spent_cr"] = int(old.get("spent_cr", 0))
		result["created_tick"] = int(old.get("created_tick", 0))
		result["last_reason"] = "player_policy_updated_preserving_spend"
	else:
		result["spent_cr"] = 0
		result["created_tick"] = tick
		result["last_reason"] = "approved_in_native_director"
	return result

static func research_spending_gate(m: Dictionary, cost: int, treasury: int) -> String:
	if cost <= 0:
		return "invalid_research_charge"
	var spent := int(m.get("spent_cr", 0))
	var ceiling := int(m.get("budget_ceiling_cr", 0))
	if cost > ceiling or spent > ceiling - cost:
		return "player_mandate_budget_exhausted"
	if treasury < cost or treasury - cost < int(m.get("treasury_floor_cr", 0)):
		return "player_mandate_treasury_floor"
	return ""

static func validate_economic(m: Dictionary) -> String:
	var location := str(m.get("location", ""))
	if location.is_empty() or location.length() > 160:
		return "invalid_station_location"
	for character in location:
		if character.unicode_at(0) < 32:
			return "invalid_station_location"
	var target := int(m.get("min_stock", 0))
	if target < 10 or target > 5000:
		return "invalid_stock_target"
	var budget := int(m.get("budget_ceiling_cr", 0))
	var floor_cr := int(m.get("treasury_floor_cr", 0))
	if budget < 100 or budget > 1000000000 or floor_cr < 10000 or floor_cr > 1000000000:
		return "invalid_mandate_finances"
	if int(m.get("spent_cr", 0)) < 0 or int(m.get("spent_cr", 0)) > budget:
		return "invalid_committed_amount"
	var kind := str(m.get("kind", ""))
	var commodity := str(m.get("commodity", ""))
	if kind == "supply" and not SUPPLY.has(commodity):
		return "unsupported_supply_commodity"
	if kind == "industry" and not INDUSTRY.has(commodity):
		return "unsupported_industry_commodity"
	if kind != "supply" and kind != "industry":
		return "invalid_economic_kind"
	return ""

static func required_native_action(kind: String) -> String:
	if kind == "supply":
		return "deliver"
	if kind == "industry":
		return "build"
	return ""

static func economic_goal(m: Dictionary, stock: float) -> Dictionary:
	if m.get("mode") != "delegated":
		return {}
	if str(m.get("kind", "")) == "supply" and (not is_finite(stock) or stock < 0.0 or stock >= float(m.get("min_stock", 0))):
		return {}
	var kind := str(m.get("kind", ""))
	if kind != "supply" and kind != "industry":
		return {}
	return {"goal_id": "player_supply" if kind == "supply" else "player_industry", "commodity": m.get("commodity"), "destination": m.get("location"), "shortage_ticks": 1000, "score": 150.0}

static func may_commission(m: Dictionary, treasury: int, payment: int) -> String:
	if m.get("mode") != "delegated":
		return "player_mandate_not_delegated"
	if payment <= 0:
		return "invalid_mandated_native_payment"
	var spent := int(m.get("spent_cr", 0))
	var ceiling := int(m.get("budget_ceiling_cr", 0))
	if payment > ceiling or spent > ceiling - payment:
		return "player_mandate_budget_exhausted"
	if treasury < payment or treasury - payment < int(m.get("treasury_floor_cr", 0)):
		return "player_mandate_treasury_floor"
	return ""

## Only invoke after a real paid receipt. Does not debit any account.
static func record_paid(m: Dictionary, amount: int, tick: int, receipt_id: String) -> Dictionary:
	if amount <= 0 or receipt_id.is_empty():
		return {"error": "invalid_paid_receipt"}
	var result := m.duplicate(true)
	var receipts: Dictionary = result.get("receipts", {}).duplicate(true)
	if receipts.has(receipt_id):
		return {"error": "duplicate_paid_receipt"}
	receipts[receipt_id] = tick
	result["receipts"] = receipts
	result["spent_cr"] = int(result.get("spent_cr", 0)) + amount
	result["last_commitment_tick"] = tick
	result["last_reason"] = "native_contract_funded_not_yet_delivered"
	return {"mandate": result}
