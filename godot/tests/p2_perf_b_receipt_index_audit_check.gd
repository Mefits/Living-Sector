extends SceneTree
## Independent full-scan oracle for persistent N9 receipt shards and kind counters.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	if not ledger.audit_receipt_index():
		_fail("empty index")
		return
	if not ledger.transfer("trade-1", "buyer", "seller", 7, 1, "trade").get("ok", false):
		_fail("first payment")
		return
	var forked = ledger.fork()
	if not forked.transfer("trade-2", "buyer", "seller", 5, 2, "trade").get("ok", false):
		_fail("fork payment")
		return
	if not ledger.audit_receipt_index() or not forked.audit_receipt_index():
		_fail("fork parity")
		return
	var baseline: Dictionary = forked.snapshot()
	var restored = Ledger.new()
	if not restored.restore(baseline) or not restored.audit_receipt_index():
		_fail("restore")
		return
	var corrupted: Dictionary = baseline.duplicate(true)
	corrupted["receipts"]["trade-1"]["id"] = "forged"
	if restored.restore(corrupted) or not restored.audit_receipt_index():
		_fail("rejected restore damaged live index")
		return
	# Diagnostic negative cases: private test-only corruption must be detected,
	# never repaired or silently accepted by the oracle.
	var wrong_counter = restored.fork()
	wrong_counter.set("_receipt_kind_counts", {"trade": 99})
	if wrong_counter.audit_receipt_index():
		_fail("counter mismatch")
		return
	var missing_order = restored.fork()
	missing_order.set("_receipt_order_chunks", [["trade-1"]])
	if missing_order.audit_receipt_index():
		_fail("missing order ID")
		return
	var duplicate_order = restored.fork()
	duplicate_order.set("_receipt_order_chunks", [["trade-1", "trade-1"]])
	if duplicate_order.audit_receipt_index():
		_fail("duplicate order ID")
		return
	if restored.snapshot() != baseline or not restored.audit_receipt_index():
		_fail("diagnostic mutated authoritative ledger")
		return
	print("P2_PERF_B_RECEIPT_INDEX_AUDIT_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_INDEX_AUDIT_FAIL: " + reason)
	quit(1)
