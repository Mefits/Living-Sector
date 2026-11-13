extends RefCounted
## Phase 1 native economic proposal lifecycle from strategy/economic_proposal.rs.
## All dictionaries are caller-owned detached snapshots. No world money is mutated.
const QUOTE_TTL_TICKS := 600
const REPEAT_AFTER_TICKS := 120
const MAX_CR := 1000000000
const MAX_I64 := 9223372036854775807
const PENDING := "pending"
const APPROVED := "approved"
const REJECTED := "rejected"
const CONSUMED := "consumed"
const EXPIRED := "expired"

static func _positive_quote(quote: int) -> bool:
	return quote > 0 and quote <= MAX_I64

static func _same_target(proposal: Dictionary, mandate: Dictionary) -> bool:
	return str(proposal.get("location", "")) == str(mandate.get("location", "")) and str(proposal.get("kind", "")) == str(mandate.get("kind", "")) and str(proposal.get("commodity", "")) == str(mandate.get("commodity", ""))

static func matches(proposal: Dictionary, mandate: Dictionary, action: String, quote: int, tick: int) -> bool:
	return _same_target(proposal, mandate) and str(proposal.get("action", "")) == action and int(proposal.get("quoted_commitment_cr", -1)) == quote and tick <= int(proposal.get("valid_until_tick", -1))

static func can_spend(proposal: Dictionary, mandate: Dictionary, action: String, quote: int, tick: int) -> String:
	if tick > int(proposal.get("valid_until_tick", -1)):
		return "approval_quote_expired"
	if not matches(proposal, mandate, action, quote, tick):
		return "approval_quote_changed"
	if str(proposal.get("status", "")) != APPROVED:
		return "specific_action_not_approved"
	return ""

static func needs_review(charter: Dictionary) -> bool:
	return str(charter.get("economy_authority", "")) == "review"

static func _mandate_gate(mandate: Dictionary, treasury: int, quote: int) -> String:
	if str(mandate.get("mode", "")) != "delegated":
		return "player_mandate_not_delegated"
	if not _positive_quote(quote):
		return "invalid_mandated_native_payment"
	var spent := int(mandate.get("spent_cr", 0))
	var ceiling := int(mandate.get("budget_ceiling_cr", 0))
	if spent < 0 or ceiling < spent or quote > ceiling - spent:
		return "player_mandate_budget_exhausted"
	var floor_cr := int(mandate.get("treasury_floor_cr", 0))
	if treasury < floor_cr or quote > treasury - floor_cr:
		return "player_mandate_treasury_floor"
	return ""

static func _charter_gate(charter: Dictionary, quote: int, treasury: int, require_tranche: bool = true) -> String:
	if str(charter.get("economy_authority", "")) == "autonomous":
		return "player_mandates_disabled_in_charter"
	if not _positive_quote(quote):
		return "invalid_native_payment"
	var spent := int(charter.get("spent_cr", 0))
	var ceiling := int(charter.get("shared_ceiling_cr", 0))
	if spent < 0 or ceiling < spent or quote > ceiling - spent:
		return "shared_mandate_budget_exhausted"
	var reserve := int(charter.get("protected_treasury_cr", 0))
	if treasury < reserve or quote > treasury - reserve:
		return "charter_treasury_reserve"
	if require_tranche and needs_review(charter):
		var left := int(charter.get("approved_economy_cr", 0)) - int(charter.get("spent_economy_cr", 0))
		if quote > left:
			return "player_approval_required"
	return ""

static func can_offer(mandate: Dictionary, charter: Dictionary, quote: int, treasury: int) -> bool:
	if not needs_review(charter) or _mandate_gate(mandate, treasury, quote) != "":
		return false
	return _charter_gate(charter, quote, treasury, false) == ""

## Returns an unchanged copy when the native quote is ineligible or already active.
static func publish(proposals: Dictionary, faction: String, mandate: Dictionary, charter: Dictionary, action: String, quote: int, treasury: int, tick: int) -> Dictionary:
	var next := proposals.duplicate(true)
	if faction.is_empty() or action.is_empty() or action.length() > 48 or not can_offer(mandate, charter, quote, treasury):
		return next
	if next.has(faction):
		var old: Dictionary = next[faction]
		if matches(old, mandate, action, quote, tick):
			var status := str(old.get("status", ""))
			if status == PENDING or status == APPROVED or status == REJECTED:
				return next
			if status == CONSUMED and tick < int(old.get("created_tick", 0)) + REPEAT_AFTER_TICKS:
				return next
	next[faction] = {
		"proposal_id": "economic-%s-%d" % [faction, tick],
		"location": str(mandate.get("location", "")),
		"commodity": mandate.get("commodity", ""),
		"kind": mandate.get("kind", ""),
		"action": action,
		"quoted_commitment_cr": quote,
		"created_tick": tick,
		"valid_until_tick": tick + QUOTE_TTL_TICKS,
		"status": PENDING,
		"last_reason": "awaiting_player_decision_no_contract_funded",
		"funded_contract_id": null,
		"funded_tick": null,
		"funded_payment_cr": null,
	}
	return next

## Returns {error, proposals, charters}; errors preserve snapshots except native expiry.
## Caller may submit ONLY faction, proposal_id and decision. Never accept client quote.
static func decide(proposals: Dictionary, charters: Dictionary, mandates: Dictionary, commanders: Dictionary, faction: String, proposal_id: String, approve: bool, tick: int) -> Dictionary:
	var next_p := proposals.duplicate(true)
	var next_c := charters.duplicate(true)
	var result := {"error": "", "proposals": next_p, "charters": next_c}
	if not commanders.has(faction):
		result.error = "unknown_faction"
		return result
	if not mandates.has(faction):
		result.error = "economic_mandate_missing"
		return result
	var mandate: Dictionary = mandates[faction]
	if str(mandate.get("mode", "")) != "delegated":
		result.error = "mandate_is_not_delegated"
		return result
	if not charters.has(faction):
		result.error = "faction_charter_missing"
		return result
	var charter: Dictionary = next_c[faction]
	if not needs_review(charter):
		result.error = "charter_not_in_economic_review"
		return result
	if not next_p.has(faction):
		result.error = "specific_proposal_missing"
		return result
	var proposal: Dictionary = next_p[faction]
	if str(proposal.get("proposal_id", "")) != proposal_id:
		result.error = "stale_proposal_id"
		return result
	if str(proposal.get("status", "")) != PENDING:
		result.error = "proposal_already_decided"
		return result
	if tick > int(proposal.get("valid_until_tick", -1)):
		proposal.status = EXPIRED
		proposal.last_reason = "proposal_expired_before_player_decision"
		result.error = "approval_quote_expired"
		return result
	if not _same_target(proposal, mandate):
		result.error = "proposal_target_changed"
		return result
	if not approve:
		proposal.status = REJECTED
		proposal.last_reason = "player_rejected_specific_action"
		return result
	var quote := int(proposal.get("quoted_commitment_cr", 0))
	var m_spent := int(mandate.get("spent_cr", 0))
	var m_ceiling := int(mandate.get("budget_ceiling_cr", 0))
	if quote <= 0 or m_spent < 0 or m_ceiling < m_spent or quote > m_ceiling - m_spent:
		result.error = "mandate_limit_changed_since_quote"
		return result
	var c_spent := int(charter.get("spent_cr", 0))
	var c_ceiling := int(charter.get("shared_ceiling_cr", 0))
	if c_spent < 0 or c_ceiling < c_spent or quote > c_ceiling - c_spent:
		result.error = "charter_limit_changed_since_quote"
		return result
	var economy_spent := int(charter.get("spent_economy_cr", 0))
	if economy_spent < 0 or economy_spent > MAX_CR or quote > MAX_CR - economy_spent:
		result.error = "approval_tranche_out_of_bounds"
		return result
	charter.approved_economy_cr = maxi(int(charter.get("approved_economy_cr", 0)), economy_spent + quote)
	proposal.status = APPROVED
	proposal.last_reason = "player_approved_exact_native_quote_not_funded"
	return result

## In review, exact proposal token AND cumulative charter gate must both pass.
## Outside review the charter gate applies, with no proposal required.
static func authorize_action(proposals: Dictionary, faction: String, mandate: Dictionary, charter: Dictionary, action: String, quote: int, treasury: int, tick: int) -> String:
	if needs_review(charter):
		if not proposals.has(faction):
			return "specific_action_approval_required"
		var error := can_spend(proposals[faction], mandate, action, quote, tick)
		if error != "":
			return error
	return _charter_gate(charter, quote, treasury)

## This must be called ONLY after the native coordinator has validated a
## specific paid contract receipt. This function NEVER transfers credits.
static func native_paid(proposals: Dictionary, mandates: Dictionary, faction: String, amount: int, contract_id: String, action: String, tick: int) -> Dictionary:
	var next := proposals.duplicate(true)
	if amount <= 0 or contract_id.is_empty() or not next.has(faction) or not mandates.has(faction):
		return next
	var proposal: Dictionary = next[faction]
	if not _same_target(proposal, mandates[faction]):
		return next
	if str(proposal.get("status", "")) == APPROVED and tick <= int(proposal.get("valid_until_tick", -1)) and str(proposal.get("action", "")) == action and amount <= int(proposal.get("quoted_commitment_cr", -1)):
		proposal.status = CONSUMED
		proposal.funded_contract_id = contract_id
		proposal.funded_tick = tick
		proposal.funded_payment_cr = amount
		proposal.last_reason = "native_faction_contract_receipt_linked"
	return next

static func expire(proposals: Dictionary, tick: int) -> Dictionary:
	var next := proposals.duplicate(true)
	for faction in next:
		var proposal: Dictionary = next[faction]
		if tick > int(proposal.get("valid_until_tick", -1)) and str(proposal.get("status", "")) in [PENDING, APPROVED]:
			proposal.status = EXPIRED
			proposal.last_reason = "native_quote_expired_recheck_required"
	return next
