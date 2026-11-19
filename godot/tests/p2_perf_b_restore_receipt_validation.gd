extends SceneTree
## Astra II-A: untrusted N38 rows must never become trusted COW receipts.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var source = Ledger.new()
	if not source.import_accounts({"buyer": 100, "seller": 0}):
		_fail("source accounts")
		return
	for i in range(70):
		if not source.transfer("paid-%03d" % i, "buyer", "seller", 1, i, "trade").get("ok", false):
			_fail("source transaction")
			return
	var good: Dictionary = source.snapshot()
	var target = Ledger.new()
	if not target.import_accounts({"original": 9}):
		_fail("target account")
		return
	var before: Dictionary = target.snapshot()
	var bad_rows: Array = [
		{"id": "bad", "legs": [{"account": "buyer", "delta": 1.5}]},
		{"id": "bad", "legs": [{"account": "", "delta": 1}]},
		{"id": "bad", "legs": [{"account": "buyer"}]},
		{"id": "bad", "legs": [{"account": "buyer", "delta": -9223372036854775807 - 1}]},
		{"id": "bad", "legs": [], "kind": "trade"},
		{"id": "bad", "legs": [{"account": "buyer", "delta": 1}], "tick": -1},
		{"id": "bad", "legs": [{"account": "buyer", "delta": 1}], "kind": 4},
		{"id": "bad", "legs": [{"account": "buyer", "delta": 1}], "credits_lost": 1.5},
		{"id": "bad", "legs": [{"account": "buyer", "delta": 1}], "wages_credits_accrued": -2},
	]
	for row in bad_rows:
		var corrupted: Dictionary = good.duplicate(true)
		corrupted["receipts"]["bad"] = row
		if target.restore(corrupted):
			_fail("accepted malformed receipt " + str(row))
			return
		if target.snapshot() != before or target.receipt_count() != 0:
			_fail("failed restore modified live ledger")
			return
	# Historical valid single-leg write-off and wages are not required to
	# balance like ordinary two-leg transfers. They remain roundtrippable.
	var legacy: Dictionary = good.duplicate(true)
	legacy["receipts"]["legacy-writeoff"] = {
		"id": "legacy-writeoff", "kind": "facility_removed", "tick": 71,
		"credits_lost": 4, "legs": [{"account": "facility/old", "delta": -4}]}
	if not target.restore(legacy) or target.snapshot() != legacy:
		_fail("valid historical writeoff rejected")
		return
	var child = target.fork()
	if not child.audit_receipt_index() or not target.audit_receipt_index():
		_fail("forked index corrupted")
		return
	var old: Dictionary = target.snapshot()
	if not child.transfer("next", "buyer", "seller", 1, 72, "trade").get("ok", false):
		_fail("fork append")
		return
	if target.snapshot() != old or child.receipt_count() != target.receipt_count() + 1:
		_fail("fork mutated restored history")
		return
	print("P2_PERF_B_RESTORE_RECEIPT_VALIDATION_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RESTORE_RECEIPT_VALIDATION_FAIL: " + reason)
	quit(1)
