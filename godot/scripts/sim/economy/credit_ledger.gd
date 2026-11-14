extends RefCounted
## CODE_UNVERIFIED — data-only accounting boundary; not a second money supply.
## Rust reference: economy/money.rs, agents/facility/workforce.rs.
## Amounts are integer credits (i64 in Rust). Do not convert market f32 prices here.
const MAX_CREDITS: int = 9223372036854775807

var _balances: Dictionary = {}
var _receipts: Dictionary = {}

func import_accounts(accounts: Dictionary) -> bool:
	if not _balances.is_empty() or not _receipts.is_empty():
		return false
	for account in accounts:
		if not _valid_account(account) or not _valid_amount(accounts[account]):
			return false
	_balances = accounts.duplicate(true)
	return true

## Register a previously unknown escrow wallet at ZERO only. This is the same
## authoritative N9 ledger: it cannot create credits or replace an existing
## account. The caller must stage/validate the entire contract transaction
## before publishing this ledger snapshot to the canonical World Apply.
func register_empty_account(account: String) -> bool:
	if not _valid_account(account) or _balances.has(account):
		return false
	_balances[account] = 0
	return true

func balance(account: String) -> int:
	return int(_balances.get(account, -1))

func total() -> int:
	var result: int = 0
	for account in _balances:
		result += int(_balances[account])
	return result

func has_receipt(operation_id: String) -> bool:
	return _receipts.has(operation_id)

## All legs are committed together; sum must be zero. Duplicate IDs never reapply.
## legs: [{account: String, delta: int}]. Negative delta is a debit.
func commit(operation_id: String, legs: Array, tick: int, kind: String) -> Dictionary:
	if operation_id.is_empty() or tick < 0 or kind.is_empty():
		return {"ok": false, "reason": "invalid_operation"}
	if _receipts.has(operation_id):
		return {"ok": false, "reason": "duplicate_operation"}
	if legs.size() < 2:
		return {"ok": false, "reason": "missing_counterparty"}
	var changes: Dictionary = {}
	var debits: int = 0
	var credits: int = 0
	for leg in legs:
		if not (leg is Dictionary) or not leg.has("account") or not leg.has("delta"):
			return {"ok": false, "reason": "invalid_leg"}
		var account = leg["account"]
		var delta = leg["delta"]
		if not _valid_account(account) or not _balances.has(account) or typeof(delta) != TYPE_INT:
			return {"ok": false, "reason": "invalid_account_or_delta"}
		if delta == -9223372036854775807 - 1:
			return {"ok": false, "reason": "integer_overflow"}
		if delta < 0:
			if debits > MAX_CREDITS + delta:
				return {"ok": false, "reason": "integer_overflow"}
			debits -= delta
		else:
			if credits > MAX_CREDITS - delta:
				return {"ok": false, "reason": "integer_overflow"}
			credits += delta
		var old_change: int = int(changes.get(account, 0))
		if delta > 0 and old_change > MAX_CREDITS - delta:
			return {"ok": false, "reason": "integer_overflow"}
		if delta < 0 and old_change < -MAX_CREDITS - delta:
			return {"ok": false, "reason": "integer_overflow"}
		changes[account] = old_change + delta
	if debits == 0 or debits != credits:
		return {"ok": false, "reason": "unbalanced"}
	for account in changes:
		var before: int = int(_balances[account])
		var change: int = int(changes[account])
		if change < 0 and before < -change:
			return {"ok": false, "reason": "insufficient_funds"}
		if change > 0 and before > MAX_CREDITS - change:
			return {"ok": false, "reason": "integer_overflow"}
	for account in changes:
		_balances[account] = int(_balances[account]) + int(changes[account])
	var receipt = {"id": operation_id, "tick": tick, "kind": kind, "legs": legs.duplicate(true)}
	_receipts[operation_id] = receipt
	return {"ok": true, "receipt": receipt.duplicate(true)}

func transfer(operation_id: String, source: String, destination: String, amount: int, tick: int, kind: String) -> Dictionary:
	if source == destination or amount <= 0:
		return {"ok": false, "reason": "invalid_transfer"}
	return commit(operation_id, [{"account": source, "delta": -amount}, {"account": destination, "delta": amount}], tick, kind)

## A frozen Rust admin despawn physically destroys the actor and its
## remaining personal/facility credits. It is NOT a treasury transfer.
## Keep an explicit immutable N9 write-off receipt and remove the wallet;
## total credits fall by exactly the erased actor's old credits. This
## privileged operation is used ONLY by the N39 atomic admin cascade.
func close_removed_entity_account(operation_id: String,
		account: String, tick: int, kind: String) -> Dictionary:
	if operation_id.is_empty() or not _valid_account(account) or tick < 0:
		return {"ok": false, "reason": "invalid_admin_account_removal"}
	if kind not in ["ship_decommissioned", "facility_removed"]:
		return {"ok": false, "reason": "invalid_admin_writeoff_kind"}
	if not _balances.has(account) or _receipts.has(operation_id):
		return {"ok": false, "reason": "account_missing_or_previously_removed"}
	if kind == "ship_decommissioned" and not account.begins_with("ship:"):
		return {"ok": false, "reason": "not_a_ship_wallet"}
	if kind == "facility_removed" and not account.begins_with("facility/"):
		return {"ok": false, "reason": "not_a_facility_wallet"}
	var lost: int = int(_balances[account])
	if lost < 0:
		return {"ok": false, "reason": "invalid_decommission_balance"}
	_balances.erase(account)
	var record: Dictionary = {"id": operation_id, "tick": tick,
		"kind": kind, "account_closed": account, "credits_lost": lost,
		"legs": [{"account": account, "delta": -lost}]}
	_receipts[operation_id] = record
	return {"ok": true, "receipt": record.duplicate(true),
		"credits_lost": lost}

func snapshot() -> Dictionary:
	return {"version": 1, "balances": _balances.duplicate(true), "receipts": _receipts.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or not (data.get("balances") is Dictionary) or not (data.get("receipts") is Dictionary):
		return false
	var candidate: Dictionary = data["balances"]
	for account in candidate:
		if not _valid_account(account) or not _valid_amount(candidate[account]):
			return false
	var receipts: Dictionary = data["receipts"]
	for key in receipts:
		if not _valid_account(key) or not (receipts[key] is Dictionary):
			return false
		if receipts[key].get("id") != key or not (receipts[key].get("legs") is Array):
			return false
	_balances = candidate.duplicate(true)
	_receipts = receipts.duplicate(true)
	return true

func _valid_account(value: Variant) -> bool:
	return value is String and not value.is_empty()

func _valid_amount(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0
