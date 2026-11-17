extends SceneTree
## N9 restore must validate every receipt before publishing any state.
## The final malformed row exercises failure after many locally built shards.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var source = Ledger.new()
	if not source.import_accounts({"buyer": 200, "seller": 0}):
		_fail("source accounts")
		return
	for i in range(100):
		if not source.transfer("receipt-%03d" % i, "buyer", "seller", 1, i + 1, "trade").get("ok", false):
			_fail("source transfer")
			return
	var valid: Dictionary = source.snapshot()
	var target = Ledger.new()
	if not target.import_accounts({"original": 7}):
		_fail("target accounts")
		return
	var before: Dictionary = target.snapshot()
	var malformed: Dictionary = valid.duplicate(true)
	malformed["receipts"]["zz-invalid-last"] = {"id": "wrong-id", "legs": []}
	if target.restore(malformed):
		_fail("malformed late receipt accepted")
		return
	if target.snapshot() != before or target.receipt_count() != 0:
		_fail("failed restore changed authoritative state")
		return
	if not target.restore(valid) or target.snapshot() != valid:
		_fail("valid restore roundtrip")
		return
	if target.transfer("receipt-099", "buyer", "seller", 1, 101, "trade").get("ok", false):
		_fail("duplicate paid operation accepted")
		return
	if not target.audit_receipt_index():
		_fail("receipt index invalid")
		return
	print("P2_PERF_B_RESTORE_SINGLE_PASS_ATOMIC_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RESTORE_SINGLE_PASS_ATOMIC_FAIL: " + reason)
	quit(1)
