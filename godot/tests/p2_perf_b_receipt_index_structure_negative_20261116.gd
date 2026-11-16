extends SceneTree
## Negative regression: damaged N9 private partition layout must fail closed,
## never throw during diagnostic traversal or mutate a healthy ledger.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 30, "seller": 0}):
		_fail("accounts")
		return
	if not ledger.transfer("paid-1", "buyer", "seller", 7, 1, "trade").get("ok", false):
		_fail("payment")
		return
	var expected: Dictionary = ledger.snapshot()
	if not ledger.audit_receipt_index():
		_fail("healthy baseline")
		return
	var truncated = ledger.fork()
	truncated.set("_receipt_partitions", [])
	if truncated.audit_receipt_index():
		_fail("truncated partitions accepted")
		return
	var extra = ledger.fork()
	var extra_partitions: Array = extra.get("_receipt_partitions").duplicate()
	extra_partitions.append({})
	extra.set("_receipt_partitions", extra_partitions)
	if extra.audit_receipt_index():
		_fail("extra partition accepted")
		return
	var wrong_type = ledger.fork()
	var bad_partitions: Array = wrong_type.get("_receipt_partitions").duplicate()
	bad_partitions[0] = []
	wrong_type.set("_receipt_partitions", bad_partitions)
	if wrong_type.audit_receipt_index():
		_fail("non-dictionary partition accepted")
		return
	if ledger.snapshot() != expected or not ledger.audit_receipt_index():
		_fail("negative audit changed authoritative ledger")
		return
	print("P2_PERF_B_RECEIPT_INDEX_STRUCTURE_NEGATIVE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_INDEX_STRUCTURE_NEGATIVE_FAIL: " + reason)
	quit(1)
