extends RefCounted
## CODE_UNVERIFIED. Read-only reconciliation of N11's authoritative credit ledger.
## Rust parity: economy/money.rs captures native wallets; it does not mint money.
const MAX_CREDITS: int = 9223372036854775807

## initial_accounts must be supplied from the real seed/checkpoint, never inferred.
## Returns a deterministic report and never modifies the ledger or input snapshots.
func reconcile(initial_accounts: Dictionary, ledger_snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var expected: Dictionary = {}
	if ledger_snapshot.get("version") != 1:
		errors.append("unsupported_version")
	if not (ledger_snapshot.get("balances") is Dictionary) or not (ledger_snapshot.get("receipts") is Dictionary):
		errors.append("invalid_snapshot_shape")
		return _report(errors, {}, 0, 0)
	var balances: Dictionary = ledger_snapshot["balances"]
	var receipts: Dictionary = ledger_snapshot["receipts"]
	var keys: Array = initial_accounts.keys()
	keys.sort()
	var initial_total: int = 0
	for account in keys:
		var amount: Variant = initial_accounts[account]
		if not _valid_key(account) or not _valid_amount(amount):
			errors.append("invalid_initial_account:%s" % str(account))
			continue
		if initial_total > MAX_CREDITS - amount:
			errors.append("initial_total_overflow")
			continue
		initial_total += amount
		expected[account] = amount
	var actual_keys: Array = balances.keys()
	actual_keys.sort()
	for account in actual_keys:
		if not expected.has(account):
			errors.append("unexpected_account:%s" % str(account))
		if not _valid_amount(balances[account]):
			errors.append("invalid_balance:%s" % str(account))
	for account in keys:
		if not balances.has(account):
			errors.append("missing_account:%s" % str(account))
	var ids: Array = receipts.keys()
	ids.sort()
	for id in ids:
		var receipt: Variant = receipts[id]
		if not _valid_key(id) or not (receipt is Dictionary):
			errors.append("invalid_receipt:%s" % str(id))
			continue
		if receipt.get("id") != id or typeof(receipt.get("tick")) != TYPE_INT or int(receipt["tick"]) < 0 or not _valid_key(receipt.get("kind")) or not (receipt.get("legs") is Array):
			errors.append("invalid_receipt_header:%s" % str(id))
			continue
		var legs: Array = receipt["legs"]
		if legs.size() < 2:
			errors.append("invalid_legs:%s" % str(id))
			continue
		var debits: int = 0
		var credits: int = 0
		var changes: Dictionary = {}
		var valid: bool = true
		for leg in legs:
			if not (leg is Dictionary) or not _valid_key(leg.get("account")) or typeof(leg.get("delta")) != TYPE_INT:
				valid = false
				break
			var account: String = leg["account"]
			var delta: int = leg["delta"]
			if not expected.has(account) or delta == -MAX_CREDITS - 1:
				valid = false
				break
			if delta < 0:
				if debits > MAX_CREDITS + delta:
					valid = false
					break
				debits -= delta
			else:
				if credits > MAX_CREDITS - delta:
					valid = false
					break
				credits += delta
			var old: int = int(changes.get(account, 0))
			if (delta > 0 and old > MAX_CREDITS - delta) or (delta < 0 and old < -MAX_CREDITS - delta):
				valid = false
				break
			changes[account] = old + delta
		if not valid or debits == 0 or debits != credits:
			errors.append("unbalanced_or_invalid_receipt:%s" % str(id))
			continue
		for account in changes:
			var previous: int = expected[account]
			var change: int = changes[account]
			if (change < 0 and previous < -change) or (change > 0 and previous > MAX_CREDITS - change):
				valid = false
				break
		if not valid:
			errors.append("receipt_balance_violation:%s" % str(id))
			continue
		for account in changes:
			expected[account] = int(expected[account]) + int(changes[account])
	var actual_total: int = 0
	for account in actual_keys:
		var amount: Variant = balances[account]
		if _valid_amount(amount):
			if actual_total > MAX_CREDITS - amount:
				errors.append("actual_total_overflow")
			else:
				actual_total += amount
	for account in keys:
		if expected.has(account) and balances.has(account) and expected[account] != balances[account]:
			errors.append("balance_mismatch:%s" % str(account))
	if initial_total != actual_total:
		errors.append("money_not_conserved")
	return _report(errors, expected, initial_total, actual_total)

func _report(errors: Array[String], expected: Dictionary, initial_total: int, actual_total: int) -> Dictionary:
	errors.sort()
	return {"ok": errors.is_empty(), "errors": errors, "expected_balances": expected.duplicate(true), "initial_total": initial_total, "actual_total": actual_total}

func _valid_key(value: Variant) -> bool:
	return value is String and not value.is_empty()

func _valid_amount(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0
