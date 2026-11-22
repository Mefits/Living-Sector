extends SceneTree
## B-owned bounded N9 provenance lookup; no N39/World mutation.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	if not ledger.transfer("op-a", "buyer", "seller", 17, 3, "trade").get("ok", false):
		_fail("first transfer")
		return
	if not ledger.transfer("op-b", "buyer", "seller", 9, 4, "trade").get("ok", false):
		_fail("second transfer")
		return
	var before: Dictionary = ledger.snapshot()
	var found: Dictionary = ledger.receipts_for_operations(["op-b", "op-a"])
	if not found.get("ok", false):
		_fail("batch lookup")
		return
	var rows: Dictionary = found["receipts"]
	if rows.keys() != ["op-b", "op-a"] or rows["op-a"] != before["receipts"]["op-a"]:
		_fail("order or provenance changed")
		return
	rows["op-a"]["legs"][0]["delta"] = -900
	rows["op-b"]["kind"] = "forged"
	if ledger.snapshot() != before:
		_fail("batch leaked mutable aliases")
		return
	for ids in [["op-a", "op-a"], ["op-a", "absent"], [""], [1]]:
		if ledger.receipts_for_operations(ids).get("ok", false):
			_fail("invalid batch accepted")
			return
	if not ledger.receipts_for_operations([]).get("ok", false):
		_fail("empty batch rejected")
		return
	var forked = ledger.fork()
	if not forked.transfer("op-c", "buyer", "seller", 5, 5, "trade").get("ok", false):
		_fail("fork transfer")
		return
	if ledger.receipts_for_operations(["op-c"]).get("ok", false):
		_fail("fork operation leaked")
		return
	if not forked.receipts_for_operations(["op-a", "op-c"]).get("ok", false):
		_fail("fork provenance unavailable")
		return
	var restored = Ledger.new()
	if not restored.restore(before) or not restored.receipts_for_operations(["op-a", "op-b"]).get("ok", false):
		_fail("restore batch lookup")
		return
	if ledger.balance("buyer") != 74 or ledger.receipt_count() != 2:
		_fail("balance or history mutated")
		return
	print("P2_PERF_B_RECEIPT_BATCH_PROVENANCE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_BATCH_PROVENANCE_FAIL: " + reason)
	quit(1)
