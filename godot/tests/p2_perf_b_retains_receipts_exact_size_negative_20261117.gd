extends SceneTree
## Regression: an N9 provenance map with extra or missing operation IDs
## must fail before any expensive full-history walk. No money is changed.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 1000, "seller": 0}):
		_fail("seed")
		return
	for i in range(70):
		var id: String = "paid-%03d" % i
		if not ledger.transfer(id, "buyer", "seller", 1, i + 1, "trade").get("ok", false):
			_fail("paid append")
			return
	var baseline: Dictionary = ledger.snapshot()
	var receipts: Dictionary = baseline["receipts"]
	if not ledger.retains_receipts(receipts):
		_fail("exact provenance rejected")
		return
	var padded: Dictionary = receipts.duplicate(true)
	padded["forged-extra-operation"] = {"id": "forged-extra-operation", "legs": []}
	if ledger.retains_receipts(padded):
		_fail("padded provenance accepted")
		return
	var truncated: Dictionary = receipts.duplicate(true)
	truncated.erase("paid-000")
	if ledger.retains_receipts(truncated):
		_fail("truncated provenance accepted")
		return
	var forged: Dictionary = receipts.duplicate(true)
	forged["paid-010"]["tick"] = 9999
	if ledger.retains_receipts(forged):
		_fail("equal-size forged provenance accepted")
		return
	var forked = ledger.fork()
	if not forked.transfer("paid-fork", "buyer", "seller", 1, 71, "trade").get("ok", false):
		_fail("fork payment")
		return
	if not ledger.retains_receipts(receipts) or forked.retains_receipts(receipts):
		_fail("fork provenance isolation")
		return
	var restored = Ledger.new()
	if not restored.restore(baseline) or not restored.retains_receipts(receipts):
		_fail("N38 restore provenance")
		return
	if ledger.snapshot() != baseline or not ledger.audit_receipt_index():
		_fail("authoritative ledger mutated")
		return
	print("P2_PERF_B_RETAINS_RECEIPTS_EXACT_SIZE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RETAINS_RECEIPTS_EXACT_SIZE_FAIL: " + reason)
	quit(1)
